-- DamageService: valida en el servidor los golpes que informan los clientes y aplica daño y empuje.
-- El cliente nunca decide el daño: solo dice "golpeé a X con el ataque Y".
-- Fase 2: los objetivos válidos son los muñecos (etiqueta "Objetivo"). El PvP llega en la Fase 4.
--
-- Compensación de latencia acotada (ver PositionService): el golpe se juzga en su instante `t`.
--   · Atacante: la posición que informó en `t`, CONFIRMADA por la física que observa el servidor.
--   · Objetivo: dónde lo veía el atacante, es decir, el historial observado en `t - latencia de ida`.
--   · Alcance: caja del ataque contra la caja estándar del objetivo (Hurtbox), con 1,5 studs de margen.
-- La espera máxima está acotada; si la posición no se confirma, el golpe se rechaza.
--
-- Secuencia legal (autoridad del servidor sobre el combo): el cliente avisa cada INICIO de ataque
-- (remote "InicioAtaque": seq, nombre, hora). El servidor comprueba que el ataque sea legal según el
-- anterior (Jab → Directo → Patada; el combo puede volver a Jab), que no empiece antes de que el
-- anterior pudiera cancelarse, que el golpe fuerte haya podido cargarse, y luego que cada golpe
-- informado pertenezca a un inicio aceptado y caiga dentro de SU ventana activa. Así nadie pide
-- "Patada" o "Fuerte" con carga completa a voluntad para hacer más daño.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(shared:WaitForChild("Config"):WaitForChild("CombatConfig"))
local Hurtbox = require(shared:WaitForChild("Combat"):WaitForChild("Hurtbox"))
local DefenseService = require(script.Parent:WaitForChild("DefenseService"))
local ResonanceService = require(script.Parent:WaitForChild("ResonanceService"))
local PositionService = require(script.Parent:WaitForChild("PositionService"))

local DamageService = {}

-- Se dispara con cada golpe aplicado: (jugador, objetivo, nombreDelAtaque)
local hitApplied = Instance.new("BindableEvent")
DamageService.HitApplied = hitApplied.Event

local FORCE = 1e7
local validation = CombatConfig.Validation
local records = {} -- [player] = { lastSeq, lastSeqTime, seqTargets = { [seq] = { [model] = true } }, recent = { tiempos }, starts = { [seq] = inicio }, lastStart }
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
		record = { lastSeq = -1, lastSeqTime = -math.huge, seqTargets = {}, recent = {}, starts = {}, lastStart = nil, startTimes = {} }
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


-- ---------- Inicios de ataque (secuencia legal) ----------
local LIGHT_NEXT = {} -- [ataque] = siguiente del combo
for i, name in ipairs(CombatConfig.LightChain) do
	LIGHT_NEXT[name] = CombatConfig.LightChain[i % #CombatConfig.LightChain + 1]
end
local FIRST_LIGHT = CombatConfig.LightChain[1]

-- Lo mínimo que dura un ataque antes de poder empezar otro (cancelar su recuperación al conectar)
local function minBusy(def, counter)
	local startup = if counter then def.startup * CombatConfig.Defense.CounterStartupMultiplier else def.startup
	return startup + def.active
end

-- ¿Es legal empezar `attackName` en la hora `t`, viniendo de `previous`? Devuelve ok, motivo, cargaMáxima
local function legalStart(previous, attackName, def, t)
	if not previous then
		return attackName == FIRST_LIGHT or def.heavy == true, "el combo empieza por " .. FIRST_LIGHT, 1
	end
	local elapsed = t - previous.t
	-- Se usa la duración mínima posible (como Contraataque): el servidor y el cliente pueden discrepar
	-- por un instante sobre si la ventana de Contraataque seguía abierta, y eso no debe rechazar nada
	local busy = minBusy(previous.def, true)
	if elapsed < busy - validation.StartTimeSlack then
		return false, string.format("empezó %.2f s después del anterior (mínimo %.2f)", elapsed, busy), 0
	end
	if def.heavy then
		-- Hay que mantener Atacar HoldThreshold; la carga extra cabe en el tiempo libre desde el anterior
		local free = elapsed - busy
		local maxCharge = math.clamp((free - CombatConfig.HoldThreshold) / CombatConfig.HeavyMaxCharge + 0.15, 0, 1)
		if free < CombatConfig.HoldThreshold * 0.5 - validation.StartTimeSlack then
			return false, "golpe fuerte sin tiempo de mantener", 0
		end
		return true, nil, maxCharge
	end
	-- Ligeros: Jab siempre (el combo se reinicia); los demás, solo después de su anterior en la cadena
	if attackName == FIRST_LIGHT or LIGHT_NEXT[previous.name] == attackName then
		return true, nil, 0
	end
	return false, string.format("%s no puede seguir a %s", attackName, previous.name), 0
end

local function handleStart(player, seq, attackName, t)
	local def = type(attackName) == "string" and CombatConfig.Attacks[attackName]
	if not def or type(seq) ~= "number" or seq ~= seq then
		return reject(player, "inicio inválido")
	end
	if not PositionService.ValidTime(player, t) then
		return reject(player, "hora de inicio inválida")
	end
	local record = recordFor(player)
	if record.lastStart and seq <= record.lastStart.seq then
		return reject(player, "inicio repetido o desordenado")
	end
	local clock = os.clock()
	local times = record.startTimes
	while times[1] and clock - times[1] > 1 do
		table.remove(times, 1)
	end
	if #times >= validation.MaxStartsPerSecond then
		return reject(player, "demasiados inicios por segundo")
	end
	if DefenseService.IsStunned(player, player:GetNetworkPing() + 0.1) then
		return reject(player, "inicio aturdido")
	end
	local ok, why, maxCharge = legalStart(record.lastStart, attackName, def, t)
	if not ok then
		return reject(player, "secuencia ilegal: " .. tostring(why))
	end
	table.insert(times, clock)
	local counterUntil = player:GetAttribute("ContraataqueHasta")
	local start = {
		seq = seq,
		name = attackName,
		def = def,
		t = t,
		maxCharge = maxCharge,
		counter = not def.heavy and counterUntil ~= nil and Workspace:GetServerTimeNow() <= counterUntil,
	}
	record.lastStart = start
	record.starts[seq] = start
	record.starts[seq - 12] = nil -- limpiar inicios viejos
end

-- Espera (acotada) el inicio de `seq`: llega por otro remote y puede adelantarse el golpe
local function startFor(player, seq)
	local record = recordFor(player)
	local deadline = os.clock() + 0.3
	while not record.starts[seq] and os.clock() < deadline do
		RunService.Heartbeat:Wait()
	end
	return record.starts[seq]
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
	-- Solo dan Resonancia los rivales que pelean (no los muñecos), con rendimiento decreciente si se
	-- repite el mismo golpe contra el mismo rival
	if target:HasTag("Sparring") or Players:GetPlayerFromCharacter(target) then
		ResonanceService.Gain(player, "Golpe", target, attackName)
	end

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

	-- 3. El instante del golpe: hora coherente con el ping y posición informada en ese instante
	local t = payload.t
	if not PositionService.ValidTime(player, t) then
		return reject(player, "hora inválida")
	end
	PositionService.Report(player, t, payload.pos, payload.look)

	-- 4. Alcance en ese instante (espera acotada a que la física observada confirme la posición)
	task.spawn(function()
		-- 4a. El golpe pertenece a un inicio aceptado del mismo ataque, y cae en su ventana activa
		local start = startFor(player, seq)
		if not start or start.name ~= attackName then
			return reject(player, "golpe sin inicio válido")
		end
		local minStartup = def.startup * CombatConfig.Defense.CounterStartupMultiplier
		local offset = t - start.t
		if offset < minStartup - validation.StartTimeSlack or offset > def.startup + def.active + validation.HitWindowSlack then
			return reject(player, string.format("golpe fuera de su ventana activa (%.2f s tras el inicio)", offset))
		end
		charge = math.min(charge, start.maxCharge)
		local attackerCFrame, whyNot = PositionService.ConfirmedAt(player, t)
		if not attackerCFrame then
			return reject(player, "posición no confirmada por la física observada (" .. tostring(whyNot) .. ")")
		end
		local current, problemNow = bodies(player, target)
		if not current then
			return reject(player, problemNow)
		end
		-- El atacante veía al objetivo como estaba hace (latencia de ida + interpolación) aprox.
		local targetCFrame = PositionService.ObservedAt(target, t - PositionService.OneWay(player)) or current.targetRoot.CFrame
		if not Hurtbox.AttackHits(attackerCFrame, def.range, def.hitboxSize, targetCFrame, validation.Tolerance) then
			return reject(player, string.format("fuera de alcance (%.1f studs)", flat(targetCFrame.Position - attackerCFrame.Position).Magnitude))
		end
		applyHit(player, attackName, def, seq, target, charge, current)
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

	local startRemote = Instance.new("RemoteEvent")
	startRemote.Name = "InicioAtaque"
	startRemote.Parent = remotes

	request.OnServerEvent:Connect(handleHit)
	startRemote.OnServerEvent:Connect(handleStart)
	Players.PlayerRemoving:Connect(function(player)
		records[player] = nil
	end)
end

return DamageService
