-- SparringService: el compañero de combate del Ring (Fase 3), un muñeco que ataca para practicar defensa.
--
-- Ciclo: Quieto → Preparando (te sigue con la mirada; deja de girar TrackingStop antes del impacto)
--        → Atacando (impacto) → Recuperando → Quieto. Patrón por defecto: Golpe, Golpe, Barrido.
--   Golpe   · se desvía, se bloquea y se esquiva con Contrapaso (Paso lateral a tiempo).
--   Barrido · área alrededor: no se desvía ni se bloquea; hay que saltarlo o salir del área.
-- Estado replicado en atributos (Estado, Ataque, FaseInicio, FaseFin, AtaqueId) con hora del servidor:
-- cada cliente anima y avisa localmente, sincronizado.
--
-- Resolución con compensación de lag: en el impacto se anota quién estaba amenazado; luego se espera
-- lo que tarda en llegar la defensa de cada jugador (DefenseService.ResolveDelay) y se decide, en orden:
-- desvío → Contrapaso → salto/esquiva → guardia → golpe.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("CombatConfig"))
local services = script.Parent
local DummyService = require(services:WaitForChild("DummyService"))
local DefenseService = require(services:WaitForChild("DefenseService"))
local ResonanceService = require(services:WaitForChild("ResonanceService"))
local DamageService = require(services:WaitForChild("DamageService"))

local SparringService = {}

local sparring = CombatConfig.Sparring
local defense = CombatConfig.Defense
local npcs = {} -- [model] = estado
local resultRemote

local function now()
	return Workspace:GetServerTimeNow()
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function setPhase(s, state, attackName, duration)
	local t = now()
	s.state = state
	s.attackName = attackName
	s.phaseStart = t
	s.phaseEnd = t + duration
	local m = s.model
	m:SetAttribute("Estado", state)
	m:SetAttribute("Ataque", attackName or "")
	m:SetAttribute("FaseInicio", s.phaseStart)
	m:SetAttribute("FaseFin", s.phaseEnd)
end

local function pattern(s)
	local custom = s.model:GetAttribute("Patron") -- p. ej. "Golpe,Barrido" (lo usan las pruebas)
	if type(custom) == "string" and custom ~= "" then
		local list = {}
		for name in string.gmatch(custom, "[^,]+") do
			if sparring.Attacks[name] then
				table.insert(list, name)
			end
		end
		if #list > 0 then
			return list
		end
	end
	return sparring.Pattern
end

local function alivePlayers()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and root and humanoid.Health > 0 then
			table.insert(list, { player = player, humanoid = humanoid, root = root, character = character })
		end
	end
	return list
end

local function nearestTarget(s)
	local best, bestDistance = nil, sparring.AggroRange
	for _, p in ipairs(alivePlayers()) do
		local distance = flat(p.root.Position - s.root.Position).Magnitude
		if distance <= bestDistance then
			best, bestDistance = p, distance
		end
	end
	return best
end

-- Gira hacia el objetivo con velocidad limitada (se puede esquivar de lado)
local function face(s, targetRoot, dt)
	local position = s.root.Position
	local desired = flat(targetRoot.Position - position)
	if desired.Magnitude < 0.1 then
		return
	end
	desired = desired.Unit
	local current = flat(s.root.CFrame.LookVector)
	current = if current.Magnitude > 0.01 then current.Unit else desired
	local angle = math.acos(math.clamp(current:Dot(desired), -1, 1))
	local maxStep = sparring.TurnSpeed * dt
	local direction = desired
	if angle > maxStep then
		local step = if current:Cross(desired).Y > 0 then maxStep else -maxStep
		direction = CFrame.Angles(0, step, 0):VectorToWorldSpace(current)
	end
	s.root.CFrame = CFrame.lookAt(position, position + direction)
end

-- ¿Una posición está dentro del área del ataque? (se usa el centro del cuerpo: igual para todo avatar)
local function inArea(attack, cframe, position)
	if attack.shape == "box" then
		local box = cframe * CFrame.new(0, 0, -(attack.range / 2 + 0.5))
		local p = box:PointToObjectSpace(position)
		return math.abs(p.X) <= attack.hitboxSize.X / 2 + 1
			and math.abs(p.Y) <= attack.hitboxSize.Y / 2 + 1
			and math.abs(p.Z) <= attack.hitboxSize.Z / 2 + 0.8
	end
	local offset = position - cframe.Position
	return flat(offset).Magnitude <= attack.radius + 0.5 and math.abs(offset.Y) <= 6
end

local function inHitbox(attack, cframe, root)
	return inArea(attack, cframe, root.Position)
end

-- ¿Está en el aire, por encima de la altura de un barrido?
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
local function airborne(p)
	raycastParams.FilterDescendantsInstances = { p.character }
	local hit = Workspace:Raycast(p.root.Position, Vector3.new(0, -30, 0), raycastParams)
	if not hit then
		return true
	end
	local standing = p.humanoid.HipHeight + p.root.Size.Y / 2
	return (p.root.Position.Y - hit.Position.Y) - standing > defense.JumpClearance
end

local function facingAttacker(root, attackerPosition)
	local toAttacker = flat(attackerPosition - root.Position)
	local look = flat(root.CFrame.LookVector)
	if toAttacker.Magnitude < 0.01 or look.Magnitude < 0.01 then
		return true
	end
	return look.Unit:Dot(toAttacker.Unit) >= math.cos(math.rad(defense.GuardAngle / 2))
end

local function isLateral(dir, fromAttacker)
	if fromAttacker.Magnitude < 0.01 then
		return false
	end
	local angle = math.deg(math.acos(math.clamp(dir:Dot(fromAttacker.Unit), -1, 1)))
	return angle >= defense.ContrapasoMinAngle and angle <= defense.ContrapasoMaxAngle
end

local function stagger(s, duration)
	if s.model.Parent then
		setPhase(s, "Aturdido", nil, duration)
	end
end

-- Decide qué le pasó a un jugador con un ataque (se llama tras esperar su latencia)
local function resolve(s, attackName, attack, attackId, impactTime, cframe, player, threat)
	local p = nil
	for _, candidate in ipairs(alivePlayers()) do
		if candidate.player == player then
			p = candidate
		end
	end
	if not p or not s.model.Parent then
		return
	end
	local perceived = impactTime + DefenseService.OneWay(player) -- cuándo vio el impacto en su pantalla
	local insideNow = inHitbox(attack, cframe, p.root)
	-- Amenazado: estaba en el área cuando el ataque quedó comprometido, o al empezar un Paso a tiempo
	if not threat then
		local paso = DefenseService.FindPaso(player, perceived - defense.ContrapasoWindow, perceived + 0.03)
		if paso and paso.position and inArea(attack, cframe, paso.position) then
			threat = { position = paso.position }
		end
	end
	if not threat and not insideNow then
		if RunService:IsStudio() then
			print(string.format("[UMBRAL] Defensa · ataque %d %s → fuera de alcance (%.1f studs)", attackId, attackName, flat(p.root.Position - cframe.Position).Magnitude))
		end
		return
	end

	local result, damage = nil, 0
	-- 1. Desvío
	if attack.deflectable then
		local kind = DefenseService.FindDeflect(player, perceived)
		if kind then
			result = if kind == "perfecto" then "desvio_perfecto" else "desvio"
		end
	end
	-- 2. Contrapaso: Paso lateral a tiempo, estando amenazado
	if not result and attack.contrapaso and threat then
		local paso = DefenseService.FindPaso(player, perceived - defense.ContrapasoWindow, perceived + 0.03)
		if paso and isLateral(paso.dir, flat(threat.position - cframe.Position)) then
			result = "contrapaso"
		end
	end
	-- 3. Salió del área o saltó por encima del barrido
	if not result then
		local jumped = attack.shape == "ring" and insideNow and airborne(p)
		if not insideNow or jumped then
			local paso = DefenseService.FindPaso(player, perceived - defense.PreciseDodgeWindow, perceived + 0.03)
			if threat and (paso or jumped) then
				result = "esquiva"
			else
				return -- simplemente no estaba ahí
			end
		end
	end
	-- 4. Guardia (de frente)
	if not result and attack.guardable and DefenseService.IsGuarding(player, perceived) and facingAttacker(p.root, cframe.Position) then
		damage = attack.damage * defense.GuardDamageMultiplier
		result = if DefenseService.AddPosture(player, attack.posture) then "ruptura" else "guardia"
	end
	-- 5. Golpe
	if not result then
		result = "golpe"
		damage = attack.damage
	end

	-- Consecuencias
	if result == "desvio_perfecto" then
		ResonanceService.Gain(player, "DesvioPerfecto")
		DefenseService.OpenCounter(player)
		stagger(s, sparring.StaggerOnPerfect)
	elseif result == "desvio" then
		ResonanceService.Gain(player, "Desvio")
		DefenseService.AddPosture(player, defense.DeflectPostureChip, false)
	elseif result == "contrapaso" then
		ResonanceService.Gain(player, "Contrapaso")
		DefenseService.OpenCounter(player)
	elseif result == "esquiva" then
		ResonanceService.Gain(player, "Esquiva")
	elseif result == "ruptura" then
		DefenseService.Stun(player, defense.GuardBreakStun)
	elseif result == "golpe" then
		DefenseService.Stun(player, defense.HitStun)
	end
	if damage > 0 then
		p.humanoid:TakeDamage(damage)
		ResonanceService.Touch(player)
	end

	if RunService:IsStudio() then
		print(string.format(
			"[UMBRAL] Defensa · ataque %d %s → %s · amenazado %s · dentro %s · daño %.1f · Resonancia %.1f",
			attackId,
			attackName,
			result,
			tostring(threat ~= nil),
			tostring(insideNow),
			damage,
			ResonanceService.Get(player)
		))
	end
	resultRemote:FireAllClients({
		player = player,
		npc = s.model,
		attack = attackName,
		attackId = attackId,
		result = result,
		damage = damage,
		from = cframe.Position,
	})
end

-- El ataque queda comprometido cuando deja de girar: se anota quién está en el área en ese momento
local function commit(s)
	s.committed = true
	s.commitCFrame = s.root.CFrame
	s.threats = {}
	local attack = sparring.Attacks[s.attackName]
	for _, p in ipairs(alivePlayers()) do
		if inHitbox(attack, s.commitCFrame, p.root) then
			s.threats[p.player] = { position = p.root.Position }
		end
	end
end

local function startActive(s)
	if not s.committed then
		commit(s)
	end
	local attackName = s.attackName
	local attack = sparring.Attacks[attackName]
	local impactTime = s.phaseEnd
	local cframe = s.commitCFrame -- la dirección del golpe quedó fija al comprometerse
	local attackId = s.attackId
	local threats = s.threats
	setPhase(s, "Atacando", attackName, attack.active)

	for _, p in ipairs(alivePlayers()) do
		local threat = threats[p.player]
		if not threat and inHitbox(attack, cframe, p.root) then
			threat = { position = p.root.Position }
		end
		task.delay(DefenseService.ResolveDelay(p.player), resolve, s, attackName, attack, attackId, impactTime, cframe, p.player, threat)
	end
end

local function update(s, dt)
	if not s.model.Parent then
		npcs[s.model] = nil
		return
	end
	local t = now()
	local target = nearestTarget(s)

	if s.state == "Aturdido" then
		if t >= s.phaseEnd then
			setPhase(s, "Quieto", nil, sparring.Pause * 0.5)
		end
	elseif s.state == "Quieto" then
		if not target then
			s.phaseEnd = math.max(s.phaseEnd, t + sparring.Pause * 0.5) -- empieza a contar cuando llegas
			return
		end
		face(s, target.root, dt)
		if t >= s.phaseEnd then
			local list = pattern(s)
			s.patternIndex = s.patternIndex % #list + 1
			local attackName = list[s.patternIndex]
			s.attackId += 1
			s.committed = false
			s.model:SetAttribute("AtaqueId", s.attackId)
			setPhase(s, "Preparando", attackName, sparring.Attacks[attackName].windup)
		end
	elseif s.state == "Preparando" then
		if t < s.phaseEnd - sparring.TrackingStop then
			if target then
				face(s, target.root, dt)
			end
		elseif not s.committed then
			commit(s)
		end
		if t >= s.phaseEnd then
			startActive(s)
		end
	elseif s.state == "Atacando" then
		if t >= s.phaseEnd then
			setPhase(s, "Recuperando", s.attackName, sparring.Attacks[s.attackName].recovery)
		end
	elseif s.state == "Recuperando" then
		if t >= s.phaseEnd then
			setPhase(s, "Quieto", nil, sparring.Pause)
		end
	end
end

function SparringService.Start()
	resultRemote = Instance.new("RemoteEvent")
	resultRemote.Name = "ResultadoDefensa"
	resultRemote.Parent = ReplicatedStorage:WaitForChild("Remotes")

	-- Un golpe fuerte que conecta mientras prepara su ataque lo interrumpe (los golpes rápidos no)
	DamageService.HitApplied:Connect(function(_, target, attackName)
		local s = npcs[target]
		local attack = CombatConfig.Attacks[attackName]
		if s and s.state == "Preparando" and attack and attack.heavy then
			stagger(s, sparring.StaggerOnInterrupt)
		end
	end)

	local ring = Workspace:WaitForChild("Maps"):WaitForChild("MovementLab"):WaitForChild("Ring")
	for _, marker in ipairs(ring:GetChildren()) do
		if marker:IsA("BasePart") and marker.Name == "PuntoSparring" then
			task.spawn(function()
				local model = DummyService.Spawn(marker, {
					maxHealth = sparring.MaxHealth,
					displayName = "Compañero de combate",
					bodyColor = Color3.fromRGB(70, 76, 96),
					legColor = Color3.fromRGB(45, 48, 62),
					tags = { "Sparring" },
				})
				local s = {
					model = model,
					root = model:FindFirstChild("HumanoidRootPart"),
					state = "Quieto",
					patternIndex = 0,
					attackId = 0,
				}
				model:SetAttribute("AtaqueId", 0)
				setPhase(s, "Quieto", nil, sparring.Pause)
				npcs[model] = s
			end)
		end
	end

	RunService.Heartbeat:Connect(function(dt)
		for _, s in pairs(npcs) do
			update(s, dt)
		end
	end)
end

return SparringService
