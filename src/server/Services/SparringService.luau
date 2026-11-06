-- SparringService: oponente de entrenamiento configurable del Ring (Fase 3).
--
-- Ciclo: Quieto (vuelve a su sitio) → Preparando (te sigue con la mirada; deja de girar TrackingStop
-- antes del impacto: ahí el ataque queda COMPROMETIDO) → Atacando (se lanza `lunge` studs) →
-- Recuperando → Quieto.
-- Ataques (CombatConfig.Sparring.Attacks): Golpe, Rápido, Pesado (solo desvío perfecto, se lanza
-- lejos) y Barrido (área: se salta o se sale). "Amague": empieza un Golpe, lo corta y prepara el real.
-- Ritmo variable: los ataques "delayable" se quedan armados hasta `maxDelay` del perfil (o el atributo
-- "Retraso" fijo, para pruebas). Perfil: atributo "Perfil" (basico, tecnico, agresivo). Patrón fijo:
-- atributo "Patron" (lo usan las pruebas).
--
-- Estado replicado en atributos (Estado, Ataque, FaseInicio, FaseFin, AtaqueId, en hora del servidor):
-- cada cliente anima y avisa localmente, sincronizado. Un amague es indistinguible de un Golpe hasta que
-- se corta (nada en los atributos lo delata).
--
-- Resolución con compensación de latencia acotada (PositionService): para cada jugador se usan su
-- posición CONFIRMADA al comprometerse el ataque y en el impacto que vio en su pantalla, y se decide en
-- orden: desvío → Contrapaso → salto/esquiva → guardia → golpe.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(shared:WaitForChild("Config"):WaitForChild("CombatConfig"))
local Hurtbox = require(shared:WaitForChild("Combat"):WaitForChild("Hurtbox"))
local services = script.Parent
local DummyService = require(services:WaitForChild("DummyService"))
local DefenseService = require(services:WaitForChild("DefenseService"))
local ResonanceService = require(services:WaitForChild("ResonanceService"))
local DamageService = require(services:WaitForChild("DamageService"))
local PositionService = require(services:WaitForChild("PositionService"))

local SparringService = {}

local sparring = CombatConfig.Sparring
local defense = CombatConfig.Defense
local FORCE = 1e7
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

local function profile(s)
	local name = s.model:GetAttribute("Perfil")
	return sparring.Profiles[name] or sparring.Profiles[sparring.DefaultProfile]
end

local function pattern(s)
	local custom = s.model:GetAttribute("Patron") -- p. ej. "Golpe,Amague,Fuerte" (lo usan las pruebas)
	if type(custom) == "string" and custom ~= "" then
		local list = {}
		for name in string.gmatch(custom, "[^,]+") do
			if sparring.Attacks[name] or name == "Amague" then
				table.insert(list, name)
			end
		end
		if #list > 0 then
			return list
		end
	end
	return profile(s).pattern
end

-- Cuánto se queda armado este ataque (variación de ritmo)
local function delayFor(s, attack)
	if not attack.delayable then
		return 0
	end
	local fixed = s.model:GetAttribute("Retraso")
	if type(fixed) == "number" then
		return math.max(0, fixed)
	end
	return s.random:NextNumber(0, profile(s).maxDelay)
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

-- Mueve al muñeco con velocidad horizontal (lanzarse o volver a su sitio)
local function drive(s, velocity)
	if not s.mover then
		local attachment = Instance.new("Attachment")
		attachment.Name = "UmbralMovimientoA"
		attachment.Parent = s.root
		local mover = Instance.new("LinearVelocity")
		mover.Name = "UmbralMovimiento"
		mover.Attachment0 = attachment
		mover.RelativeTo = Enum.ActuatorRelativeTo.World
		mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		mover.ForceLimitsEnabled = true
		mover.ForceLimitMode = Enum.ForceLimitMode.PerAxis
		mover.MaxAxesForce = Vector3.new(FORCE, 0, FORCE)
		mover.Parent = s.root
		s.mover = mover
	end
	s.mover.VectorVelocity = velocity or Vector3.zero
	s.mover.Enabled = velocity ~= nil
end

-- ¿Una posición está en el área del ataque? (cajas estándar: igual para todo avatar)
local function inArea(attack, attackerCFrame, targetCFrame)
	if attack.shape == "box" then
		return Hurtbox.AttackHits(attackerCFrame, attack.range, attack.hitboxSize, targetCFrame)
	end
	return Hurtbox.InRadius(attackerCFrame.Position, attack.radius, targetCFrame.Position, 6)
end

-- ¿En el aire por encima de un barrido?
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
local function airborne(p, position)
	raycastParams.FilterDescendantsInstances = { p.character }
	local hit = Workspace:Raycast(position, Vector3.new(0, -30, 0), raycastParams)
	if not hit then
		return true
	end
	local standing = p.humanoid.HipHeight + p.root.Size.Y / 2
	return (position.Y - hit.Position.Y) - standing > defense.JumpClearance
end

local function facingAttacker(defenderCFrame, attackerPosition)
	local toAttacker = flat(attackerPosition - defenderCFrame.Position)
	local look = flat(defenderCFrame.LookVector)
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
		drive(s, nil)
		setPhase(s, "Aturdido", nil, duration)
	end
end

-- Decide qué le pasó a un jugador con un ataque (corre en su propio hilo; las esperas están acotadas)
local function resolve(s, info, player)
	local attack = info.attack
	local oneWay = DefenseService.OneWay(player)
	local perceived = info.impactTime + oneWay -- cuándo vio el impacto en su pantalla

	-- Esperar a que lleguen las defensas que hizo a tiempo (acotado)
	while now() < perceived + oneWay + 0.03 do
		RunService.Heartbeat:Wait()
	end
	local p = nil
	for _, candidate in ipairs(alivePlayers()) do
		if candidate.player == player then
			p = candidate
		end
	end
	if not p or not s.model.Parent then
		return
	end

	-- Dónde estaba (confirmado por la física observada). Sin confirmación se usa lo observado ahora.
	local atImpact = PositionService.ConfirmedAt(player, perceived)
	local confirmed = atImpact ~= nil
	atImpact = atImpact or p.root.CFrame
	local atCommit = PositionService.ConfirmedAt(player, info.commitTime + oneWay) or info.observedAtCommit[player]
	local paso = DefenseService.FindPaso(player, perceived - defense.ContrapasoWindow, perceived + 0.03)
	local pasoStart = paso and PositionService.ConfirmedAt(player, paso.t)

	local threat = (atCommit ~= nil and inArea(attack, info.impactCFrame, atCommit))
		or (pasoStart ~= nil and inArea(attack, info.impactCFrame, pasoStart))
	local insideNow = inArea(attack, info.impactCFrame, atImpact)
	if not threat and not insideNow then
		return
	end

	local result, damage, exposed = nil, 0, false
	-- 1. Desvío (el pesado solo con desvío perfecto)
	if attack.deflectable then
		local kind, press = DefenseService.FindDeflect(player, perceived)
		if kind == "perfecto" or (kind == "normal" and not attack.perfectOnly) then
			DefenseService.Consume(press)
			result = if kind == "perfecto" then "desvio_perfecto" else "desvio"
		end
	end
	-- 2. Contrapaso: Paso lateral a tiempo, estando amenazado
	if not result and attack.contrapaso and threat and paso then
		local reference = (pasoStart or atCommit or atImpact).Position
		if isLateral(paso.dir, flat(reference - info.impactCFrame.Position)) then
			result = "contrapaso"
		end
	end
	-- 3. Salió del área o saltó por encima del barrido
	if not result then
		local jumped = attack.shape == "ring" and insideNow and airborne(p, atImpact.Position)
		if not insideNow or jumped then
			local dodgePaso = DefenseService.FindPaso(player, perceived - defense.PreciseDodgeWindow, perceived + 0.03)
			if threat and (dodgePaso or jumped) then
				result = "esquiva"
			else
				return -- simplemente no estaba ahí
			end
		end
	end
	-- 4. Guardia (de frente). Un desvío fallido deja EXPUESTO: sin guardia y con más daño.
	exposed = DefenseService.IsExposed(player, perceived)
	if not result and not exposed and attack.guardable and DefenseService.IsGuarding(player, perceived) and facingAttacker(atImpact, info.impactCFrame.Position) then
		damage = attack.damage * defense.GuardDamageMultiplier
		result = if DefenseService.AddPosture(player, attack.posture) then "ruptura" else "guardia"
	end
	-- 5. Golpe
	if not result then
		result = "golpe"
		damage = attack.damage * (if exposed then defense.ExposedDamageMultiplier else 1)
	end

	-- Consecuencias (la Resonancia de defensa ya está limitada por el ritmo de ataques del rival)
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
		DefenseService.Stun(player, defense.HitStun * (if exposed then 1.3 else 1))
	end
	if damage > 0 then
		p.humanoid:TakeDamage(damage)
		ResonanceService.Touch(player)
	end

	if RunService:IsStudio() then
		print(string.format(
			"[UMBRAL] Defensa · ataque %d %s → %s · amenazado %s · dentro %s · confirmado %s%s · daño %.1f",
			info.attackId,
			info.attackName,
			result,
			tostring(threat),
			tostring(insideNow),
			tostring(confirmed),
			if exposed then " · EXPUESTO" else "",
			damage
		))
	end
	resultRemote:FireAllClients({
		player = player,
		npc = s.model,
		attack = info.attackName,
		attackId = info.attackId,
		result = result,
		damage = damage,
		exposed = exposed,
		from = info.impactCFrame.Position,
	})
end

-- El ataque queda comprometido al dejar de girar: se fija la dirección y se anota quién estaba en el área
local function commit(s)
	s.committed = true
	s.commitTime = now()
	s.commitCFrame = s.root.CFrame
	s.observedAtCommit = {}
	for _, p in ipairs(alivePlayers()) do
		s.observedAtCommit[p.player] = p.root.CFrame
	end
end

local function startActive(s)
	if not s.committed then
		commit(s)
	end
	local attack = sparring.Attacks[s.attackName]
	local info = {
		attack = attack,
		attackName = s.attackName,
		attackId = s.attackId,
		impactTime = s.phaseEnd,
		commitTime = s.commitTime,
		-- El área del golpe ya incluye lo que se lanza hacia adelante
		impactCFrame = s.commitCFrame * CFrame.new(0, 0, -(attack.lunge or 0)),
		observedAtCommit = s.observedAtCommit,
	}
	setPhase(s, "Atacando", s.attackName, attack.active)
	if (attack.lunge or 0) > 0 then
		drive(s, flat(s.commitCFrame.LookVector).Unit * (attack.lunge / attack.active))
	end
	for _, p in ipairs(alivePlayers()) do
		task.spawn(resolve, s, info, p.player)
	end
end

local function startWindup(s, attackName, feint)
	local attack = sparring.Attacks[attackName]
	s.attackId += 1
	s.committed = false
	s.feint = feint
	s.model:SetAttribute("AtaqueId", s.attackId)
	setPhase(s, "Preparando", attackName, attack.startup + (if feint then 0 else delayFor(s, attack)))
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
			setPhase(s, "Quieto", nil, profile(s).pause * 0.5)
		end
	elseif s.state == "Quieto" then
		-- Volver a su sitio tras lanzarse
		local home = flat(s.spawn.Position - s.root.Position)
		drive(s, if home.Magnitude > 0.75 then home.Unit * math.min(sparring.ReturnSpeed, home.Magnitude * 8) else nil)
		if not target then
			s.phaseEnd = math.max(s.phaseEnd, t + profile(s).pause * 0.5) -- empieza a contar cuando llegas
			return
		end
		face(s, target.root, dt)
		if t >= s.phaseEnd and home.Magnitude <= 1.5 then
			drive(s, nil)
			local list = pattern(s)
			s.patternIndex = s.patternIndex % #list + 1
			local step = list[s.patternIndex]
			if step == "Amague" then
				startWindup(s, "Golpe", true)
			else
				startWindup(s, step, false)
			end
		end
	elseif s.state == "Preparando" then
		local elapsed = t - s.phaseStart
		if s.feint and elapsed >= sparring.FeintRestartAt then
			startWindup(s, "Golpe", false) -- el amague se corta y prepara el golpe real
			return
		end
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
			drive(s, nil)
			setPhase(s, "Recuperando", s.attackName, sparring.Attacks[s.attackName].recovery)
		end
	elseif s.state == "Recuperando" then
		if t >= s.phaseEnd then
			setPhase(s, "Quieto", nil, profile(s).pause)
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
					noReset = true, -- vuelve a su sitio por su cuenta
				})
				local s = {
					model = model,
					root = model:FindFirstChild("HumanoidRootPart"),
					spawn = marker.CFrame,
					state = "Quieto",
					patternIndex = 0,
					attackId = 0,
					random = Random.new(1234),
				}
				model:SetAttribute("AtaqueId", 0)
				model:SetAttribute("Perfil", sparring.DefaultProfile)
				setPhase(s, "Quieto", nil, profile(s).pause)
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
