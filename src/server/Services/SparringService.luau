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
local TweenService = game:GetService("TweenService")
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
local noticeRemote -- avisos grandes y chicos (Guardián, enemigo vencido, Contratiempo)
local waveRemote -- onda del Desvío Reflejado

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
	-- Orden importante: quien escucha "Estado" o "FaseInicio" lee FaseFin y Ataque en ese momento, así
	-- que se publican ANTES (si no, leen los de la fase anterior y el aviso se desincroniza)
	local m = s.model
	m:SetAttribute("Ataque", attackName or "")
	m:SetAttribute("FaseFin", s.phaseEnd)
	m:SetAttribute("FaseInicio", s.phaseStart)
	m:SetAttribute("Estado", state)
end

local function profile(s)
	local name = s.model:GetAttribute("Perfil")
	return sparring.Profiles[name] or sparring.Profiles[sparring.DefaultProfile]
end

-- Pausa entre ataques. Un perfil con ritmo (Latido) se acelera al perder vida (hasta un 45 % más rápido)
local function pauseFor(s)
	local p = profile(s)
	if p.rhythm then
		local humanoid = s.model:FindFirstChildOfClass("Humanoid")
		local ratio = if humanoid and humanoid.MaxHealth > 0 then math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) else 1
		return p.pause * (0.55 + 0.45 * ratio)
	end
	return p.pause
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
-- `originCFrame`: desde donde parte el atacante. Un ataque que se lanza `lunge` studs barre TODO su
-- recorrido: la caja va desde el atacante hasta el final del lanzamiento (si no, quien está pegado a él
-- quedaría "detrás" de una caja desplazada hacia adelante).
local function inArea(attack, originCFrame, targetCFrame)
	if attack.shape == "box" then
		local reach = attack.range + (attack.lunge or 0)
		local size = Vector3.new(attack.hitboxSize.X, attack.hitboxSize.Y, reach)
		return Hurtbox.AttackHits(originCFrame, reach, size, targetCFrame)
	end
	return Hurtbox.InRadius(originCFrame.Position, attack.radius, targetCFrame.Position, 6)
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
	if RunService:IsStudio() then
		print(string.format("[UMBRAL] Compañero aturdido %.2f s en %s (ataque %d)", duration, tostring(s.state), s.attackId))
	end
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
	local atImpact, whyNot = PositionService.ConfirmedAt(player, perceived)
	local confirmed = atImpact ~= nil
	atImpact = atImpact or p.root.CFrame
	local atCommit = PositionService.ConfirmedAt(player, info.commitTime + oneWay) or info.observedAtCommit[player]
	local paso = DefenseService.FindPaso(player, perceived - defense.ContrapasoWindow, perceived + 0.03)
	local pasoStart = paso and PositionService.ConfirmedAt(player, paso.t)

	local threat = (atCommit ~= nil and inArea(attack, info.originCFrame, atCommit))
		or (pasoStart ~= nil and inArea(attack, info.originCFrame, pasoStart))
	local insideNow = inArea(attack, info.originCFrame, atImpact)
	if not threat and not insideNow then
		if RunService:IsStudio() then
			print(string.format(
				"[UMBRAL] Defensa · ataque %d %s → fuera del área · al comprometerse %s · en el impacto %s (confirmado %s%s) · origen %s",
				info.attackId, info.attackName,
				if atCommit then tostring(Vector3.new(math.floor(atCommit.X * 10) / 10, 0, math.floor(atCommit.Z * 10) / 10)) else "?",
				tostring(Vector3.new(math.floor(atImpact.X * 10) / 10, 0, math.floor(atImpact.Z * 10) / 10)),
				tostring(confirmed), if whyNot then ", " .. whyNot else "",
				tostring(Vector3.new(math.floor(info.originCFrame.X * 10) / 10, 0, math.floor(info.originCFrame.Z * 10) / 10))
			))
		end
		return
	end

	local result, damage, exposed = nil, 0, false
	local stunApplied = nil -- duración real del aturdimiento (el cliente usa la misma)
	-- 1. Desvío (el pesado solo con desvío perfecto)
	if attack.deflectable then
		local kind, press = DefenseService.FindDeflect(player, perceived)
		if kind == "perfecto" or (kind == "normal" and not attack.perfectOnly) then
			DefenseService.Consume(press)
			result = if kind == "perfecto" then "desvio_perfecto" else "desvio"
		end
	end
	-- 2. Contrapaso: Paso lateral a tiempo, estando amenazado. La dirección se mide respecto al vector
	-- ATACANTE → defensor (la amenaza), no respecto al punto de impacto (que va adelantado por el
	-- lanzamiento y, de cerca, da un vector diminuto y de dirección casi aleatoria) ni a la cámara.
	if not result and attack.contrapaso and threat and paso then
		local reference = (pasoStart or atCommit or atImpact).Position
		if isLateral(paso.dir, flat(reference - info.originCFrame.Position)) then
			result = "contrapaso"
		end
	end
	-- 3. Salió del área o saltó por encima del barrido
	if not result then
		-- Saltar el barrido: dentro del círculo en horizontal y en el aire (aunque el salto lleve por encima de
		-- la altura del área, eso es "lo saltó", no "no estaba")
		local overRing = attack.shape == "ring"
			and Hurtbox.InRadius(info.originCFrame.Position, attack.radius, atImpact.Position, math.huge)
			and airborne(p, atImpact.Position)
		local jumped = overRing or (attack.shape == "ring" and insideNow and airborne(p, atImpact.Position))
		if not insideNow or jumped then
			local dodgePaso = DefenseService.FindPaso(player, perceived - defense.PreciseDodgeWindow, perceived + 0.03)
			if threat and (dodgePaso or jumped) then
				result = "esquiva"
			else
				if RunService:IsStudio() then
					print(string.format("[UMBRAL] Defensa · ataque %d %s → no estaba en el área en el impacto", info.attackId, info.attackName))
				end
				return -- simplemente no estaba ahí
			end
		end
	end
	-- 4. Guardia (de frente). Un desvío fallido deja EXPUESTO: sin guardia y con más daño.
	exposed = DefenseService.IsExposed(player, perceived)
	if not result and not exposed and attack.guardable and DefenseService.IsGuarding(player, perceived) and facingAttacker(atImpact, info.originCFrame.Position) then
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
		-- DESVÍO REFLEJADO: la onda daña y aturde a los otros enemigos cercanos
		local origin = atImpact.Position
		local reflected = 0
		for other, os in pairs(npcs) do
			if reflected < sparring.ReflectMaxTargets and os ~= s and os.root and other.Parent and flat(os.root.Position - origin).Magnitude <= sparring.ReflectRadius then
				local otherHumanoid = other:FindFirstChildOfClass("Humanoid")
				if otherHumanoid and otherHumanoid.Health > 0 then
					os.lastHitter = player
					otherHumanoid.Health = math.max(0, otherHumanoid.Health - attack.damage)
					if otherHumanoid.Health > 0 then
						stagger(os, sparring.ReflectStun)
					end
					reflected += 1
				end
			end
		end
		if waveRemote then
			waveRemote:FireAllClients({ position = origin, radius = sparring.ReflectRadius, reflected = reflected, player = player })
		end
		-- CONTRATIEMPO (Latido): desvíos perfectos seguidos al ritmo
		if s.kind and s.kind.rhythmStreak then
			s.streak = (s.streak or 0) + 1
			if s.streak >= s.kind.rhythmStreak then
				s.streak = 0
				stagger(s, s.kind.rhythmStun)
				ResonanceService.Gain(player, "Contratiempo")
				noticeRemote:FireClient(player, { title = "¡CONTRATIEMPO!", subtitle = string.format("%d desvíos perfectos al ritmo", s.kind.rhythmStreak), small = true })
			end
		end
	elseif result == "desvio" then
		s.streak = 0
		ResonanceService.Gain(player, "Desvio")
		DefenseService.AddPosture(player, defense.DeflectPostureChip, false)
	elseif result == "contrapaso" then
		ResonanceService.Gain(player, "Contrapaso")
		DefenseService.OpenCounter(player)
	elseif result == "esquiva" then
		ResonanceService.Gain(player, "Esquiva")
	elseif result == "ruptura" then
		stunApplied = DefenseService.Stun(player, defense.GuardBreakStun)
	elseif result == "golpe" then
		s.streak = 0
		stunApplied = DefenseService.Stun(player, defense.HitStun * (if exposed then 1.3 else 1))
	end
	if damage > 0 then
		p.humanoid:TakeDamage(damage)
		ResonanceService.Touch(player)
	end

	if RunService:IsStudio() then
		print(string.format(
			"[UMBRAL] Defensa · ataque %d %s → %s · amenazado %s · dentro %s (a %.1f studs) · confirmado %s%s%s · daño %.1f",
			info.attackId,
			info.attackName,
			result,
			tostring(threat),
			tostring(insideNow),
			flat(atImpact.Position - info.originCFrame.Position).Magnitude,
			tostring(confirmed),
			if whyNot then " (" .. whyNot .. ")" else "",
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
		stun = stunApplied,
		from = info.originCFrame.Position, -- el empuje sale desde el atacante, no desde el punto adelantado
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
		originCFrame = s.commitCFrame, -- desde dónde ataca (referencia de dirección)
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
	if s.heart then
		-- El latido marca el ritmo: se enciende al empezar y se apaga justo hasta el impacto
		s.heart.Transparency = 0
		s.heart.Size = Vector3.new(0.9, 0.9, 0.3)
		TweenService:Create(s.heart, TweenInfo.new(attack.startup, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 0.75, Size = Vector3.new(0.5, 0.5, 0.2) }):Play()
	end
end

local function update(s, dt)
	if not s.model.Parent then
		npcs[s.model] = nil
		return
	end
	local t = now()
	if s.root and s.root.Position.Y < s.spawn.Position.Y - 12 then
		drive(s, nil)
		s.model:PivotTo(s.spawn) -- se cayó (al abismo): vuelve a su sitio
		s.root.AssemblyLinearVelocity = Vector3.zero
	end
	local target = nearestTarget(s)

	if s.state == "Aturdido" then
		if t >= s.phaseEnd then
			setPhase(s, "Quieto", nil, pauseFor(s) * 0.5)
		end
	elseif s.state == "Quieto" then
		-- Volver a su sitio tras lanzarse
		local home = flat(s.spawn.Position - s.root.Position)
		drive(s, if home.Magnitude > 0.75 then home.Unit * math.min(sparring.ReturnSpeed, home.Magnitude * 8) else nil)
		if not target then
			s.phaseEnd = math.max(s.phaseEnd, t + pauseFor(s) * 0.5) -- empieza a contar cuando llegas
			return
		end
		face(s, target.root, dt)
		-- Si no logra volver a su sitio (p. ej. el jugador le bloquea el camino tras un lanzamiento largo),
		-- ataca desde donde está en vez de quedarse esperando para siempre
		local stuck = t - s.phaseStart > pauseFor(s) + 1.5
		if t >= s.phaseEnd and (home.Magnitude <= 1.5 or stuck) then
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
			setPhase(s, "Quieto", nil, pauseFor(s))
		end
	end
end

-- Aspecto del Guardián: ojos que brillan, cristales del Eco en los hombros y un aura violeta.
-- Piezas sin colisión ni masa, soldadas al cuerpo (no cambian la Hurtbox: esa es estándar).
local function dressGuardian(model, glowColor, withHeart)
	local color = glowColor or Color3.fromRGB(190, 110, 255)
	local heart = nil
	local function glow(name, parentPart, size, offset, light)
		if not parentPart then
			return
		end
		local piece = Instance.new("Part")
		piece.Name = name
		piece.Size = size
		piece.Material = Enum.Material.Neon
		piece.Color = color
		piece.CanCollide = false
		piece.CanQuery = false
		piece.CanTouch = false
		piece.Massless = true
		piece.CastShadow = false
		piece.CFrame = parentPart.CFrame * offset
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = parentPart
		weld.Part1 = piece
		weld.Parent = piece
		if light then
			local point = Instance.new("PointLight")
			point.Color = color
			point.Range = light
			point.Brightness = 1.5
			point.Parent = piece
		end
		piece.Parent = model
		return piece
	end
	local head = model:FindFirstChild("Head")
	local torso = model:FindFirstChild("UpperTorso")
	glow("OjoIzq", head, Vector3.new(0.22, 0.12, 0.08), CFrame.new(-0.2, 0.1, -0.58), nil)
	glow("OjoDer", head, Vector3.new(0.22, 0.12, 0.08), CFrame.new(0.2, 0.1, -0.58), 8)
	glow("CristalHombroIzq", torso, Vector3.new(0.35, 1.1, 0.35), CFrame.new(-1.1, 1.1, 0) * CFrame.Angles(0, 0, math.rad(20)), nil)
	glow("CristalHombroDer", torso, Vector3.new(0.35, 1.1, 0.35), CFrame.new(1.1, 1.1, 0) * CFrame.Angles(0, 0, math.rad(-20)), 14)
	if withHeart then
		heart = glow("Corazon", torso, Vector3.new(0.9, 0.9, 0.3), CFrame.new(0, 0.2, -0.55), 12)
	else
		glow("Nucleo", torso, Vector3.new(0.4, 0.4, 0.1), CFrame.new(0, 0.2, -0.52), nil)
	end
	return heart
end

-- Guardián de la Grieta: al llegar a 0 de vida queda vencido (aviso a todos), y se levanta para la revancha
local guardian = sparring.Guardian
-- Vencer a un enemigo: queda tendido (aturdido) un rato, da Resonancia a quien lo venció y se levanta.
-- El Guardián avisa a todos; un enemigo común solo a quien lo venció. Los Gemelos caen y se levantan juntos.
local function watchDefeat(s, isGuardian)
	local humanoid = s.model:FindFirstChildOfClass("Humanoid")
	local riseAfter = if isGuardian then guardian.RiseAfter else s.kind.riseAfter
	local defeated = false
	humanoid.HealthChanged:Connect(function(health)
		if defeated or health > 0 then
			return
		end
		defeated = true
		task.wait() -- el golpe que lo venció registra a su autor justo después del cambio de vida
		local group = { s, s.partner }
		for _, member in ipairs(group) do
			drive(member, nil)
			setPhase(member, "Aturdido", nil, riseAfter)
		end
		local winner = s.lastHitter or (s.partner and s.partner.lastHitter)
		if isGuardian then
			noticeRemote:FireAllClients({ title = "¡GRIETA SUPERADA!", subtitle = string.format("El Guardián se levantará en %d s", riseAfter) })
		elseif winner then
			noticeRemote:FireClient(winner, { title = "¡" .. string.upper(s.kind.label) .. " VENCIDO!", subtitle = "+ Resonancia", small = true })
		end
		if winner and winner.Parent then
			ResonanceService.Gain(winner, if isGuardian then "VencerGuardian" else "VencerComun")
		end
		task.delay(riseAfter, function()
			for _, member in ipairs(group) do
				local h = member.model.Parent and member.model:FindFirstChildOfClass("Humanoid")
				if h then
					h.Health = h.MaxHealth
				end
			end
			defeated = false
			if isGuardian and s.model.Parent then
				noticeRemote:FireAllClients({ title = "EL GUARDIÁN SE LEVANTA", subtitle = "" })
			end
		end)
	end)
end

-- Gemelos: una sola vida para los dos (lo que le pasa a uno le pasa al otro)
local function linkTwins(a, b)
	a.partner, b.partner = b, a
	local syncing = false
	local function mirror(from, to)
		from.model:FindFirstChildOfClass("Humanoid").HealthChanged:Connect(function(health)
			if syncing then
				return
			end
			syncing = true
			local h = to.model:FindFirstChildOfClass("Humanoid")
			if h and math.abs(h.Health - health) > 0.01 then
				h.Health = health
			end
			syncing = false
		end)
	end
	mirror(a, b)
	mirror(b, a)
end

function SparringService.Start()
	noticeRemote = Instance.new("RemoteEvent")
	noticeRemote.Name = "AvisoGrieta"
	noticeRemote.Parent = ReplicatedStorage:WaitForChild("Remotes")
	resultRemote = Instance.new("RemoteEvent")
	resultRemote.Name = "ResultadoDefensa"
	resultRemote.Parent = ReplicatedStorage:WaitForChild("Remotes")
	waveRemote = Instance.new("RemoteEvent")
	waveRemote.Name = "OndaReflejo"
	waveRemote.Parent = ReplicatedStorage:WaitForChild("Remotes")

	-- Coraza frontal (Centinela): de frente no hace daño, por la espalda más; aturdido no protege
	DamageService.SetModifier(function(_, target, _, b, geometry)
		local s = npcs[target]
		if not s or not s.kind or not s.kind.frontArmor then
			return 1, nil, false
		end
		if s.state == "Aturdido" then
			return 1, nil, true
		end
		-- Orientación y posiciones en el INSTANTE del golpe (no al juzgarlo: para entonces ya se giró)
		local attackerPos = if geometry and geometry.attacker then geometry.attacker.Position else b.attackerRoot.Position
		local targetCF = if geometry and geometry.target then geometry.target else b.targetRoot.CFrame
		local toAttacker = flat(attackerPos - targetCF.Position)
		local look = flat(targetCF.LookVector)
		if toAttacker.Magnitude < 0.01 or look.Magnitude < 0.01 then
			return 1, nil, true
		end
		local dot = look.Unit:Dot(toAttacker.Unit)
		if dot >= math.cos(math.rad(s.kind.frontAngle)) then
			return 0, "BLOQUEADO · busca su espalda", true
		elseif dot <= -0.35 then
			return s.kind.backMultiplier, "¡POR LA ESPALDA!", true
		end
		return 1, nil, true
	end)

	-- GOLPE DE OPORTUNIDAD (Acechador): un golpe pesado fallado cerca de él abre su Embestida. Solo reacciona
	-- a un hecho que el servidor ya comprobó (el golpe terminó sin conectar), nunca a entradas futuras.
	DamageService.AttackWhiffed:Connect(function(player, _, recoveryEnd)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		for _, s in pairs(npcs) do
			local kind = s.kind
			if kind and kind.opportunityRange and s.root and s.model.Parent
				and (s.state == "Quieto" or s.state == "Recuperando")
				and now() - (s.lastOpportunity or -math.huge) >= kind.opportunityCooldown
				and flat(root.Position - s.root.Position).Magnitude <= kind.opportunityRange
				and recoveryEnd - now() > 0.15 then
				s.lastOpportunity = now()
				drive(s, nil)
				local toPlayer = flat(root.Position - s.root.Position)
				if toPlayer.Magnitude > 0.1 then
					s.root.CFrame = CFrame.lookAt(s.root.Position, s.root.Position + toPlayer.Unit)
				end
				startWindup(s, "Embestida", false)
				break -- un solo castigo por error
			end
		end
	end)

	-- Un golpe fuerte que conecta mientras prepara su ataque lo interrumpe (los golpes rápidos no)
	DamageService.HitApplied:Connect(function(attacker, target, attackName)
		local s = npcs[target]
		if s then
			s.lastHitter = attacker
		end
		local attack = CombatConfig.Attacks[attackName]
		local isEco = type(attackName) == "string" and string.sub(attackName, 1, 3) == "Eco"
		if s and s.state == "Preparando" and ((attack and attack.heavy) or isEco) then
			stagger(s, sparring.StaggerOnInterrupt) -- los golpes fuertes y los Ecos interrumpen la preparación
		end
	end)

	-- Un compañero por cada marca PuntoSparring del mapa (el Ring del laboratorio y, en el lugar de
	-- desarrollo, la sala del Guardián de la Grieta)
	local maps = Workspace:WaitForChild("Maps")
	maps:WaitForChild("MovementLab"):WaitForChild("Ring")
	local pendingTwin = nil
	for _, marker in ipairs(maps:GetDescendants()) do
		local kindName = marker:IsA("BasePart") and string.match(marker.Name, "^PuntoSparring_?(%a*)$")
		if kindName then
			-- "PuntoSparring" en la Grieta = Guardián; "PuntoSparring_<Tipo>" = enemigo común de ese tipo
			local kind = sparring.Types[kindName]
			local grieta = maps:FindFirstChild("Grieta")
			local isGuardian = kindName == "" and grieta ~= nil and marker:IsDescendantOf(grieta)
			local tags = { "Sparring" }
			if isGuardian then
				table.insert(tags, "Guardian")
			elseif kind then
				table.insert(tags, kindName)
			else
				table.insert(tags, "Companero") -- el compañero de combate del Ring (lo usan las pruebas)
			end
			task.spawn(function()
				local model = DummyService.Spawn(marker, {
					maxHealth = if isGuardian then guardian.MaxHealth elseif kind then kind.maxHealth else sparring.MaxHealth,
					displayName = if isGuardian then "Guardián de la Grieta" elseif kind then kind.label else "Compañero de combate",
					bodyColor = if isGuardian then Color3.fromRGB(58, 40, 82) elseif kind then kind.body else Color3.fromRGB(70, 76, 96),
					legColor = if isGuardian then Color3.fromRGB(30, 22, 44) elseif kind then kind.legs else Color3.fromRGB(45, 48, 62),
					tags = tags,
					noReset = true, -- vuelve a su sitio por su cuenta
					noRegen = isGuardian or kind ~= nil,
				})
				local s = {
					model = model,
					root = model:FindFirstChild("HumanoidRootPart"),
					spawn = marker.CFrame,
					state = "Quieto",
					patternIndex = 0,
					attackId = 0,
					random = Random.new(1234),
					kind = kind,
				}
				model:SetAttribute("AtaqueId", 0)
				model:SetAttribute("Perfil", if isGuardian then guardian.Profile elseif kind then kind.profile else sparring.DefaultProfile)
				setPhase(s, "Quieto", nil, pauseFor(s))
				npcs[model] = s
				if isGuardian then
					dressGuardian(model)
					watchDefeat(s, true)
				elseif kind then
					s.heart = dressGuardian(model, kind.glow, kind.rhythmStreak ~= nil)
					if kind.linked then
						if pendingTwin then
							linkTwins(pendingTwin, s)
							watchDefeat(pendingTwin, false) -- uno solo vigila: la vida es compartida
							pendingTwin = nil
						else
							pendingTwin = s
						end
					else
						watchDefeat(s, false)
					end
				end
			end)
		end
	end

	-- Rendimiento: un enemigo sin jugadores cerca (ActiveRange) se duerme y solo revisa SleepCheck veces por
	-- segundo si alguien se acerca. Nunca se duerme a mitad de un ataque (solo en Quieto o Aturdido).
	local function anyPlayerNear(s)
		if not s.root then
			return false
		end
		for _, p in ipairs(alivePlayers()) do
			if (p.root.Position - s.root.Position).Magnitude <= sparring.ActiveRange then
				return true
			end
		end
		return false
	end
	RunService.Heartbeat:Connect(function(dt)
		local t = os.clock()
		for _, s in pairs(npcs) do
			local idle = s.state == "Quieto" or s.state == "Aturdido"
			if idle and t >= (s.nextAwakeCheck or 0) then
				local wasAsleep = s.asleep
				s.asleep = not anyPlayerNear(s)
				s.nextAwakeCheck = t + 1 / sparring.SleepCheck
				if wasAsleep and not s.asleep and s.state == "Quieto" then
					s.phaseEnd = math.max(s.phaseEnd, now() + pauseFor(s) * 0.5) -- respiro al llegar
				end
			end
			if not (idle and s.asleep) then
				update(s, dt)
			elseif s.state == "Aturdido" and now() >= s.phaseEnd then
				update(s, dt) -- termina su aturdimiento aunque duerma
			end
		end
	end)
end

return SparringService
