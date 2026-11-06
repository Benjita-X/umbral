-- DamageService: valida en el servidor los golpes que informan los clientes y aplica daño y empuje.
-- El cliente nunca decide el daño: solo dice "golpeé a X con el ataque Y".
-- Fase 2: los objetivos válidos son los muñecos (etiqueta "Objetivo"). El PvP llega en la Fase 4.
--
-- Tolerancia al lag: el servidor ve la posición del jugador con un pequeño retraso. Si un golpe parece
-- lejano (por ejemplo, justo después de un Paso), se vuelve a comprobar cada cuadro durante
-- Validation.LagWindow con la posición actualizada. Un golpe imposible sigue siendo rechazado.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("CombatConfig"))
local DefenseService = require(script.Parent:WaitForChild("DefenseService"))
local ResonanceService = require(script.Parent:WaitForChild("ResonanceService"))

local DamageService = {}

-- Se dispara con cada golpe aplicado: (jugador, objetivo, nombreDelAtaque)
local hitApplied = Instance.new("BindableEvent")
DamageService.HitApplied = hitApplied.Event

local FORCE = 1e7
local validation = CombatConfig.Validation
local records = {} -- [player] = { lastSeq, lastSeqTime, seqTargets = { [seq] = { [model] = true } }, recent = { tiempos } }
local confirmedRemote

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function reject(player, reason)
	player:SetAttribute("GolpesRechazados", (player:GetAttribute("GolpesRechazados") or 0) + 1)
	player:SetAttribute("UltimoRechazo", reason)
	if RunService:IsStudio() then
		warn(string.format("[UMBRAL] Golpe rechazado de %s: %s", player.Name, reason))
	end
end

local function recordFor(player)
	local record = records[player]
	if not record then
		record = { lastSeq = -1, lastSeqTime = -math.huge, seqTargets = {}, recent = {} }
		records[player] = record
	end
	return record
end

local function knockback(targetRoot, direction, speed, up)
	local attachment = targetRoot:FindFirstChild("UmbralEmpujeA")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "UmbralEmpujeA"
		attachment.Parent = targetRoot
	end
	local push = targetRoot:FindFirstChild("UmbralEmpuje")
	if not push then
		push = Instance.new("LinearVelocity")
		push.Name = "UmbralEmpuje"
		push.Attachment0 = attachment
		push.RelativeTo = Enum.ActuatorRelativeTo.World
		push.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		push.ForceLimitsEnabled = true
		push.ForceLimitMode = Enum.ForceLimitMode.PerAxis
		push.MaxAxesForce = Vector3.new(FORCE, 0, FORCE)
		push.Enabled = false
		push.Parent = targetRoot
	end
	local token = (push:GetAttribute("Token") or 0) + 1
	push:SetAttribute("Token", token)
	push.VectorVelocity = direction * speed
	push.Enabled = speed > 0
	if up > 0 then
		local v = targetRoot.AssemblyLinearVelocity
		targetRoot.AssemblyLinearVelocity = Vector3.new(v.X, up, v.Z)
	end
	task.delay(CombatConfig.Dummy.KnockbackTime, function()
		if push.Parent and push:GetAttribute("Token") == token then
			push.Enabled = false
		end
	end)
end

-- Partes vivas del golpe (se vuelven a leer al reintentar: el jugador pudo reaparecer)
local function bodies(player, target)
	local character = player.Character
	local attackerHumanoid = character and character:FindFirstChildOfClass("Humanoid")
	local attackerRoot = character and character:FindFirstChild("HumanoidRootPart")
	local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	if not attackerHumanoid or not attackerRoot or attackerHumanoid.Health <= 0 then
		return nil, "atacante sin personaje"
	end
	if not targetHumanoid or not targetRoot then
		return nil, "objetivo sin cuerpo"
	end
	return { attackerRoot = attackerRoot, targetHumanoid = targetHumanoid, targetRoot = targetRoot }
end

local function distanceOf(b)
	return flat(b.targetRoot.Position - b.attackerRoot.Position).Magnitude
end

-- Ritmo (sin repetidos ni ráfagas imposibles) y aplicación del golpe
local function applyHit(player, attackName, def, seq, target, charge, b)
	local record = recordFor(player)
	local now = os.clock()
	if seq < record.lastSeq - 8 then
		return reject(player, "secuencia vieja")
	end
	if seq > record.lastSeq then
		if now - record.lastSeqTime < validation.MinSequenceInterval then
			return reject(player, "golpes demasiado seguidos")
		end
		record.lastSeq = seq
		record.lastSeqTime = now
	end
	local targets = record.seqTargets[seq]
	if not targets then
		targets = {}
		record.seqTargets[seq] = targets
		record.seqTargets[seq - 10] = nil -- limpiar secuencias viejas
	end
	if targets[target] then
		return reject(player, "golpe repetido")
	end
	local recent = record.recent
	while recent[1] and now - recent[1] > 1 do
		table.remove(recent, 1)
	end
	if #recent >= validation.MaxHitsPerSecond then
		return reject(player, "demasiados golpes por segundo")
	end
	targets[target] = true
	table.insert(recent, now)

	local damage = def.damage + (def.chargeBonus or 0) * charge
	-- Contraataque: el primer golpe tras un desvío perfecto o un Contrapaso hace más daño
	local counterUntil = player:GetAttribute("ContraataqueHasta")
	local counter = counterUntil ~= nil and Workspace:GetServerTimeNow() <= counterUntil
	if counter then
		damage *= CombatConfig.Defense.CounterDamageMultiplier
		player:SetAttribute("ContraataqueHasta", nil)
	end
	b.targetHumanoid.Health = math.max(0, b.targetHumanoid.Health - damage)
	ResonanceService.Gain(player, "Golpe")

	local direction = flat(b.targetRoot.Position - b.attackerRoot.Position)
	direction = if direction.Magnitude > 0.01 then direction.Unit else flat(b.attackerRoot.CFrame.LookVector).Unit
	b.targetRoot.CFrame = CFrame.lookAt(b.targetRoot.Position, b.targetRoot.Position - direction) -- mira al atacante
	knockback(b.targetRoot, direction, def.knockback * (1 + charge * 0.5), def.knockUp * (1 + charge * 0.5))

	confirmedRemote:FireAllClients({
		attacker = player,
		target = target,
		attack = attackName,
		damage = damage,
		position = b.targetRoot.Position + Vector3.new(0, 1, 0),
		health = b.targetHumanoid.Health,
		counter = counter,
	})
	hitApplied:Fire(player, target, attackName)
end

local function handleHit(player, payload)
	-- 1. Forma de la petición
	if type(payload) ~= "table" then
		return reject(player, "formato")
	end
	local attackName, seq, target, charge = payload.attack, payload.seq, payload.target, payload.charge
	local def = type(attackName) == "string" and CombatConfig.Attacks[attackName]
	if not def then
		return reject(player, "ataque desconocido")
	end
	if type(seq) ~= "number" or seq ~= seq then
		return reject(player, "secuencia inválida")
	end
	if typeof(target) ~= "Instance" or not target:IsA("Model") or not target:HasTag("Objetivo") or not target:IsDescendantOf(workspace) then
		return reject(player, "objetivo inválido")
	end
	charge = if type(charge) == "number" and charge == charge then math.clamp(charge, 0, 1) else 0

	-- 2. Cuerpos vivos y atacante en condiciones (aturdido no golpea; se perdona lo que mandó antes de
	-- enterarse del aturdimiento)
	local b, problem = bodies(player, target)
	if not b then
		return reject(player, problem)
	end
	if DefenseService.IsStunned(player, player:GetNetworkPing() + 0.1) then
		return reject(player, "aturdido")
	end

	-- 3. Distancia posible (alcance + acercamiento + margen), con tolerancia al lag
	local maxDistance = def.range + CombatConfig.MaxLunge + validation.ExtraRange
	if distanceOf(b) <= maxDistance then
		return applyHit(player, attackName, def, seq, target, charge, b)
	end
	task.spawn(function()
		local deadline = os.clock() + validation.LagWindow
		while os.clock() < deadline do
			RunService.Heartbeat:Wait()
			b, problem = bodies(player, target)
			if not b then
				return reject(player, problem)
			end
			if distanceOf(b) <= maxDistance then
				return applyHit(player, attackName, def, seq, target, charge, b)
			end
		end
		reject(player, string.format("distancia %.1f > %.1f", distanceOf(b), maxDistance))
	end)
end

function DamageService.Start()
	local remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	local request = Instance.new("RemoteEvent")
	request.Name = "SolicitudGolpe"
	request.Parent = remotes
	confirmedRemote = Instance.new("RemoteEvent")
	confirmedRemote.Name = "GolpeConfirmado"
	confirmedRemote.Parent = remotes
	remotes.Parent = ReplicatedStorage

	request.OnServerEvent:Connect(handleHit)
	Players.PlayerRemoving:Connect(function(player)
		records[player] = nil
	end)
end

return DamageService
