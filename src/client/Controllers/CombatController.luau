-- CombatController: combate del jugador local (Fases 2 y 3).
--
-- Modos: Libre · Ataque (preparación → impacto → recuperación) · Carga (golpe fuerte) · Guardia · Aturdido.
-- Ataque (Fase 2):
--   · Pulsar Atacar encadena Jab → Directo → Patada. Lo pulsado antes de tiempo queda en búfer.
--   · Si el golpe CONECTA, se encadena al empezar la recuperación; si FALLA, la recuperación dura más.
--   · Mantener Atacar convierte el combo en golpe fuerte con carga. El Paso cancela la carga (amague).
--   · Paso y salto cancelan la recuperación, nunca la preparación ni el impacto.
--   · Orientación asistida y acercamiento, iguales en PC, mando y celular.
-- Defensa (Fase 3):
--   · Pulsar Defender abre una ventana de desvío; mantenerla es guardia. Pulsar otra vez antes del
--     enfriamiento no abre ventana: machacar no sirve.
--   · Cada pulsación, cada vez que se suelta y cada Paso se informan al servidor con la hora sincronizada.
--     El servidor decide el resultado (desvío, Contrapaso, esquiva, guardia, ruptura o golpe).
--   · Tras un desvío perfecto o un Contrapaso, el siguiente golpe es un Contraataque: sale el doble de
--     rápido, alcanza al rival aunque te hayas apartado y hace más daño (el servidor lo valida).
--   · La Resonancia paga un Paso extra cuando no quedan cargas.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(shared:WaitForChild("Config"):WaitForChild("CombatConfig"))
local AnimationLibrary = require(shared:WaitForChild("Combat"):WaitForChild("AnimationLibrary"))
local Rig = require(shared:WaitForChild("Combat"):WaitForChild("Rig"))
local Hurtbox = require(shared:WaitForChild("Combat"):WaitForChild("Hurtbox"))
local Effects = require(script.Parent:WaitForChild("EffectsController"))
local PositionReporter = require(script.Parent:WaitForChild("PositionReporter"))

local defense = Config.Defense
local player = Players.LocalPlayer
local KEY = "combate" -- clave de los bloqueos que este sistema pone al movimiento
local STUN_KEY = "aturdido"
local TRACK_NAMES = {
	"Jab", "Cross", "Patada", "CargaFuerte", "Fuerte", "Guardia", "Desvio", "Aturdido", "Reaccion",
	-- Armas y golpes especiales (EXPERIMENTAL)
	"PatadaVoladora", "PatadaPicada", "Tajo", "Reves", "Estocada", "TajoFuerte", "CargaEspada", "EstocadaCarrera", "Clavada", "DesenvainarEspada",
}
local weapons = Config.Weapons

local CombatController = {}

local events = {}
for _, name in ipairs({ "AttackStarted", "PhaseChanged", "Hit", "AttackEnded", "Confirmed", "DefenseResult" }) do
	events[name] = Instance.new("BindableEvent")
	CombatController[name] = events[name].Event
end

local state = {
	mode = "Libre",
	attack = nil,
	comboIndex = 0,
	comboHits = 0,
	comboDamage = 0,
	confirmedDamage = 0,
	lastAttackEnd = -math.huge,
	lastHitTime = -math.huge,
	sequence = 0,
	charge = 0,
	lastAttackName = nil,
	ready = false,
	-- Fase 3
	deflecting = false, -- dentro de la ventana de desvío
	deflectStart = -math.huge,
	counterUntil = -math.huge, -- reloj local: hasta cuándo el siguiente golpe es Contraataque
	stunnedUntil = -math.huge,
	lastResult = nil,
	-- Armas (EXPERIMENTAL)
	weapon = "Punos",
	switchUntil = -math.huge,
	lastDash = -math.huge,
}
CombatController.State = state

local input, movement
local character, humanoid, root, animator
local tracks = {}
local currentTrack = nil
local hitstop = 0
local queued = nil -- "Atacar" o "Defender" pulsado antes de poder salir
local attackPressTime = -math.huge
local heavyConsumed = true
local heavyRequested = false
local chargeTime = 0
local lastDefendPress = -math.huge
local pendingSpend = 0
local remotes = {}


local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function serverNow()
	return Workspace:GetServerTimeNow()
end

-- Informa una acción defensiva con su hora y la posición en ese instante
local function report(action, dir)
	if remotes.defense then
		local t, position, look = PositionReporter.Sample()
		remotes.defense:FireServer(action, t, dir, position, look)
	end
end

-- ---------- Animaciones ----------
local function stopTrack(fade)
	if currentTrack then
		currentTrack:Stop(fade or 0.08)
		currentTrack = nil
	end
end

local function playTrack(name, fade)
	stopTrack(0.05)
	local track = tracks[name]
	if track then
		track:Play(fade or 0.04, 1, 1)
		currentTrack = track
	end
	return track
end

-- ---------- Objetivos ----------
local function targetRootOf(model)
	local targetHumanoid = model:FindFirstChildOfClass("Humanoid")
	local targetRoot = model:FindFirstChild("HumanoidRootPart")
	if targetHumanoid and targetRoot and (targetHumanoid.Health > 0 or model:HasTag("Objetivo")) then
		return targetRoot
	end
	return nil
end

local function candidateTargets()
	local list = {}
	for _, model in ipairs(CollectionService:GetTagged("Objetivo")) do
		if model:IsA("Model") and model ~= character then
			table.insert(list, model)
		end
	end
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and other.Character then
			table.insert(list, other.Character)
		end
	end
	return list
end

-- El rival más cercano dentro del cono hacia donde apuntas (cosLimit -1 = en cualquier dirección)
local function findSoftTarget(desired, range, cosLimit)
	local best, bestDistance = nil, math.huge
	for _, model in ipairs(candidateTargets()) do
		local targetRoot = targetRootOf(model)
		if targetRoot then
			local offset = flat(targetRoot.Position - root.Position)
			local distance = offset.Magnitude
			if distance > 0.01 and distance <= range and offset.Unit:Dot(desired) >= cosLimit and distance < bestDistance then
				best, bestDistance = model, distance
			end
		end
	end
	return best, bestDistance
end

local function defaultSoftTarget(desired)
	return findSoftTarget(desired, Config.SoftTargetRange, math.cos(math.rad(Config.SoftTargetAngle)))
end

-- ---------- Bloqueos del movimiento ----------
-- Solo el instante del impacto ("active", ~0,06 s) queda comprometido: en la preparación un Paso o un
-- salto cancelan el golpe (movilidad y amagues), y en la recuperación se puede girar libremente.
local function setAttackLocks(phase)
	local committed = phase == "active"
	movement.SetDashBlocked(KEY, committed)
	movement.SetJumpBlocked(KEY, committed)
	movement.SetAutoRotateBlocked(KEY, phase ~= "recovery")
	movement.SetSpeedMultiplier(KEY, Config.AttackMoveMultiplier)
end

local function clearLocks()
	movement.ClearKey(KEY)
end

local function dropAttackVisuals()
	if state.attack then
		Effects.SetTrail(character, state.attack.def.limb, false)
	end
end

-- ---------- Golpes ----------
local function onHit(a, model, targetRoot)
	local def = a.def
	local firstHit = not a.hit
	a.hit = true

	local t = os.clock()
	if t - state.lastHitTime > Config.ComboResetTime + 0.6 then
		state.comboHits = 0
		state.comboDamage = 0
	end
	state.comboHits += 1
	local predicted = def.damage + (def.chargeBonus or 0) * a.charge
	if a.counter then
		predicted *= defense.CounterDamageMultiplier
	end
	state.comboDamage += predicted
	state.lastHitTime = t

	if firstHit and def.hitstop > 0 then
		hitstop = def.hitstop
		if currentTrack then
			currentTrack:AdjustSpeed(0)
		end
		movement.HoldLunge(def.hitstop)
	end
	-- Combo aéreo: conectar en el aire te sostiene flotando un instante para seguir golpeando
	if firstHit and not movement.State.grounded then
		movement.AirStall(Config.Eco.Juggle.AirStall)
	end

	local toAttacker = flat(root.Position - targetRoot.Position)
	local hitPosition = targetRoot.Position + Vector3.new(0, 0.6, 0)
	if toAttacker.Magnitude > 0.01 then
		hitPosition += toAttacker.Unit * 0.9
	end
	Effects.Impact(hitPosition, def, model)

	if remotes.request then
		-- El golpe va con su instante y la posición en ese instante (el servidor juzga ese momento)
		local t, position, look = PositionReporter.Sample()
		remotes.request:FireServer({ attack = a.name, seq = a.seq, target = model, charge = a.charge, t = t, pos = position, look = look })
	end
	events.Hit:Fire(a.name, model)
end

-- Cajas de impacto estándar (Hurtbox): el tamaño del avatar del rival no cambia nada
local function detectHits(a)
	local def = a.def
	for _, model in ipairs(candidateTargets()) do
		if not a.targets[model] then
			local targetRoot = targetRootOf(model)
			if targetRoot and Hurtbox.AttackHits(root.CFrame, def.range, def.hitboxSize, targetRoot.CFrame) then
				a.targets[model] = true
				onHit(a, model, targetRoot)
			end
		end
	end
end

local function startAttack(name, charge)
	local def = Config.Attacks[name]
	if not def or not root then
		return
	end
	dropAttackVisuals()
	movement.CancelDash()
	movement.StopLunge()

	-- Contraataque: tras un desvío perfecto o un Contrapaso
	local counter = not def.heavy and os.clock() <= state.counterUntil
	if counter then
		state.counterUntil = -math.huge
	end
	local startup = if counter then def.startup * defense.CounterStartupMultiplier else def.startup

	state.sequence += 1
	-- El servidor valida la secuencia de ataques: se le avisa cada inicio con su hora
	if remotes.start then
		if def.special then
			-- Los especiales mandan también la posición (el servidor comprueba la altura de la picada)
			local t, position, look = PositionReporter.Sample()
			remotes.start:FireServer(state.sequence, name, t, position, look)
		else
			remotes.start:FireServer(state.sequence, name, serverNow())
		end
	end
	local desired = movement.DesiredDirection()
	local target, distance
	if counter then
		target, distance = findSoftTarget(desired, defense.CounterTargetRange, -1)
	else
		target, distance = defaultSoftTarget(desired)
	end
	local direction = desired
	if target then
		direction = flat(targetRootOf(target).Position - root.Position).Unit
	end
	movement.Face(direction)

	-- El avance debe LLEGAR a mitad de la ventana activa (antes llegaba justo al cerrarse y el golpe salía
	-- al aire, sobre todo el Contraataque que recorre ~11 studs). Si el tramo es largo, la preparación se
	-- alarga lo justo para recorrerlo sin pasar de MAX_LUNGE_SPEED (el servidor vigila las velocidades).
	local MAX_LUNGE_SPEED = 120
	local maxLunge = if counter then defense.CounterMaxLunge else Config.MaxLunge
	local ideal = def.idealDistance or Config.IdealDistance
	local lungeDistance = if target then math.clamp(distance - ideal, 0, maxLunge) else Config.LungeWithoutTarget
	if def.special == "dash" and def.lunge then
		-- Golpe tras el Paso: sale con el impulso del Paso (más recorrido, aunque no haya rival)
		lungeDistance = if target then math.clamp(distance - ideal, 0, def.lunge) else def.lunge * 0.6
	end
	local lungeTime = startup + def.active * 0.5
	if lungeDistance / lungeTime > MAX_LUNGE_SPEED then
		lungeTime = lungeDistance / MAX_LUNGE_SPEED
		startup = math.max(startup, lungeTime - def.active * 0.5)
	end
	if def.special == "plunge" then
		-- Picada: cae en línea hacia abajo y un poco hacia adelante
		movement.Launch(direction * 14 + Vector3.new(0, -(def.plungeSpeed or 70), 0))
	elseif lungeDistance > 0.05 then
		movement.Lunge(direction, lungeDistance / lungeTime, lungeTime)
	end

	state.mode = "Ataque"
	state.attack = {
		name = name,
		def = def,
		t = 0,
		phase = "startup",
		startup = startup,
		hit = false,
		targets = {},
		seq = state.sequence,
		charge = charge or 0,
		recovery = def.recovery,
		cancelable = false,
		counter = counter,
	}
	state.lastAttackName = name
	setAttackLocks("startup")
	local track = playTrack(name, 0.03)
	if counter and track then
		track:AdjustSpeed(def.startup / startup) -- la preparación pasa más rápido
	end
	if counter then
		Effects.Counter(character)
	end
	events.AttackStarted:Fire(name, state.sequence, counter)
	events.PhaseChanged:Fire(name, "startup")
end

local function nextLightName()
	if state.mode == "Libre" and os.clock() - state.lastAttackEnd > Config.ComboResetTime then
		state.comboIndex = 0
	end
	local chain = (weapons[state.weapon] or weapons.Punos).chain
	state.comboIndex = state.comboIndex % #chain + 1
	return chain[state.comboIndex]
end

local function enterActive(a)
	a.phase = "active"
	if a.counter and currentTrack then
		currentTrack:AdjustSpeed(1)
	end
	setAttackLocks("active")
	Effects.Swing(a.def, character)
	Effects.SetTrail(character, a.def.limb, true)
	events.PhaseChanged:Fire(a.name, "active")
end

local function enterRecovery(a)
	a.phase = "recovery"
	Effects.SetTrail(character, a.def.limb, false)
	movement.StopLunge()
	if not a.hit then
		a.recovery = a.def.recovery * Config.WhiffRecoveryMultiplier
		if currentTrack then
			currentTrack:AdjustSpeed(1 / Config.WhiffRecoveryMultiplier)
		end
	end
	a.cancelable = a.hit and not a.def.finisher
	setAttackLocks("recovery")
	events.PhaseChanged:Fire(a.name, "recovery")
end

local function finishAttack()
	local a = state.attack
	if a then
		Effects.SetTrail(character, a.def.limb, false)
		if a.def.finisher then
			state.comboIndex = 0
		end
	end
	state.attack = nil
	state.mode = "Libre"
	state.lastAttackEnd = os.clock()
	stopTrack(0.12)
	clearLocks()
	if a then
		events.AttackEnded:Fire(a.name, a.hit)
	end
end

-- ---------- Golpe fuerte ----------
local function startCharge()
	dropAttackVisuals()
	movement.CancelDash()
	movement.StopLunge()
	local target = defaultSoftTarget(movement.DesiredDirection())
	if target then
		movement.Face(flat(targetRootOf(target).Position - root.Position))
	end
	state.attack = nil
	state.mode = "Carga"
	chargeTime = 0
	state.charge = 0
	clearLocks()
	movement.SetJumpBlocked(KEY, true) -- el Paso sí se permite: cancela la carga (amague)
	movement.SetSpeedMultiplier(KEY, Config.ChargeMoveMultiplier)
	playTrack(if state.weapon == "Espada" then "CargaEspada" else "CargaFuerte", 0.05)
	events.PhaseChanged:Fire("Fuerte", "carga")
end

local function releaseCharge()
	startAttack((weapons[state.weapon] or weapons.Punos).heavy, math.clamp(chargeTime / Config.HeavyMaxCharge, 0, 1))
end

local function cancelToFree()
	dropAttackVisuals()
	state.attack = nil
	state.mode = "Libre"
	state.deflecting = false
	state.lastAttackEnd = os.clock()
	stopTrack(0.08)
	clearLocks()
end

-- ---------- Guardia y desvío ----------
-- `deflect`: esta pulsación abre ventana de desvío (no se machacó)
local function startGuard(deflect)
	dropAttackVisuals()
	movement.CancelDash()
	movement.StopLunge()
	state.attack = nil
	state.mode = "Guardia"
	state.deflecting = deflect
	state.deflectStart = os.clock()
	clearLocks()
	movement.SetSpeedMultiplier(KEY, Config.GuardMoveMultiplier)
	movement.SetJumpBlocked(KEY, true)
	playTrack(if deflect then "Desvio" else "Guardia", 0.03)
	events.PhaseChanged:Fire("Guardia", if deflect then "desvio" else "inicio")
end

local function endGuard()
	state.mode = "Libre"
	if not state.deflecting then
		stopTrack(0.1) -- si está desviando, la animación termina sola
	end
	clearLocks()
	events.PhaseChanged:Fire("Guardia", "fin")
end

-- ---------- Aturdimiento ----------
local function stun(duration, broken)
	cancelToFree()
	queued = nil
	heavyRequested = false
	state.mode = "Aturdido"
	state.stunnedUntil = os.clock() + duration
	movement.SetDashBlocked(STUN_KEY, true)
	movement.SetJumpBlocked(STUN_KEY, true)
	movement.SetSpeedMultiplier(STUN_KEY, 0.3)
	playTrack(if broken then "Aturdido" else "Reaccion", 0.03)
end

local function endStun()
	state.mode = "Libre"
	stopTrack(0.15)
	movement.ClearKey(STUN_KEY)
end

-- ---------- Entradas ----------
local function alive()
	return humanoid ~= nil and root ~= nil and humanoid.Health > 0
end

-- ¿Hay un rival a la altura del jugador cerca? (en pleno combo aéreo se golpea normal, no en picada)
local function airborneTargetNear()
	for _, model in ipairs(candidateTargets()) do
		local targetRoot = targetRootOf(model)
		if targetRoot and math.abs(targetRoot.Position.Y - root.Position.Y) < 4.5 and flat(targetRoot.Position - root.Position).Magnitude < Config.SoftTargetRange then
			return true
		end
	end
	return false
end

local feetParams = RaycastParams.new()
feetParams.FilterType = Enum.RaycastFilterType.Exclude
feetParams.RespectCanCollide = true
local function feetHeight()
	feetParams.FilterDescendantsInstances = { character }
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -80, 0), feetParams)
	if not hit then
		return math.huge
	end
	return (root.Position.Y - hit.Position.Y) - (humanoid.HipHeight + root.Size.Y / 2)
end

-- ---------- Golpe de Gracia ----------
-- Un enemigo QUEBRADO (postura llena) cerca: atacar hace el Golpe de Gracia en vez del golpe normal
local function brokenTargetNear()
	local best, bestDistance = nil, Config.EnemyPosture.Execute.range
	local t = serverNow()
	for _, model in ipairs(CollectionService:GetTagged("Sparring")) do
		local untilTime = model:GetAttribute("QuebradoHasta")
		local targetRoot = untilTime and untilTime > t and targetRootOf(model)
		if targetRoot then
			local distance = flat(targetRoot.Position - root.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = model, distance
			end
		end
	end
	return best, bestDistance
end

local function execute(model, distance)
	local targetRoot = targetRootOf(model)
	if not targetRoot then
		return
	end
	dropAttackVisuals()
	movement.CancelDash()
	movement.StopLunge()
	state.attack = nil
	state.mode = "Gracia"
	queued = nil
	local dir = flat(targetRoot.Position - root.Position)
	dir = if dir.Magnitude > 0.01 then dir.Unit else flat(root.CFrame.LookVector)
	movement.Face(dir)
	movement.SetAutoRotateBlocked(KEY, true)
	movement.SetDashBlocked(KEY, true)
	movement.SetJumpBlocked(KEY, true)
	movement.SetSpeedMultiplier(KEY, 0.2)
	local approach = math.max(0, distance - 2.6)
	if approach > 0.1 then
		movement.Lunge(dir, approach / 0.14, 0.14, true)
	end
	playTrack(if state.weapon == "Espada" then "TajoFuerte" else "Fuerte", 0.03)
	Effects.Counter(character)
	events.DefenseResult:Fire({ result = "gracia" }, "¡GOLPE DE GRACIA!")
	task.delay(0.16, function()
		if state.mode ~= "Gracia" then
			return
		end
		if remotes.execute then
			remotes.execute:FireServer(model)
		end
		local hitPosition = targetRoot.Position + Vector3.new(0, 0.6, 0)
		Effects.Impact(hitPosition, Config.Attacks.Fuerte, model)
		hitstop = 0.18
		if currentTrack then
			currentTrack:AdjustSpeed(0)
		end
	end)
	task.delay(0.6, function()
		if state.mode == "Gracia" then
			state.mode = "Libre"
			state.lastAttackEnd = os.clock()
			clearLocks()
			stopTrack(0.15)
		end
	end)
end

-- El golpe que toca al pulsar Atacar estando libre: tras el Paso, en picada o el siguiente del combo
local function nextAttackName()
	local weapon = weapons[state.weapon] or weapons.Punos
	if os.clock() - state.lastDash <= weapons.DashWindow and weapon.dash then
		state.lastDash = -math.huge -- un golpe especial por Paso
		state.comboIndex = 0
		return weapon.dash
	end
	if weapon.plunge and not movement.State.grounded and feetHeight() >= weapons.PlungeMinHeight and not airborneTargetNear() then
		state.comboIndex = 0
		return weapon.plunge
	end
	return nextLightName()
end

local function onAttackPressed()
	if not alive() or state.mode == "Aturdido" or os.clock() < state.switchUntil then
		return
	end
	attackPressTime = os.clock()
	heavyConsumed = false
	heavyRequested = false
	-- Enemigo quebrado cerca: Golpe de Gracia (desde libre, guardia o la recuperación de un golpe)
	if state.mode == "Libre" or state.mode == "Guardia" or (state.mode == "Ataque" and state.attack and state.attack.phase == "recovery") then
		local broken, distance = brokenTargetNear()
		if broken then
			heavyConsumed = true
			if state.mode == "Guardia" then
				endGuard()
			end
			execute(broken, distance)
			return
		end
	end
	if state.mode == "Libre" then
		startAttack(nextAttackName())
	elseif state.mode == "Guardia" then
		endGuard()
		startAttack(nextAttackName())
	elseif state.mode == "Ataque" then
		local a = state.attack
		if a.phase == "recovery" and a.cancelable then
			startAttack(nextAttackName())
		else
			queued = "Atacar"
		end
	end
end

local function onAttackReleased()
	if state.mode == "Carga" then
		releaseCharge()
	end
end

local function onDefendPressed()
	if not alive() then
		return
	end
	-- Se informa siempre (también aturdido: el servidor lleva su propia cuenta del enfriamiento)
	report("defender_inicio")
	local now = os.clock()
	local deflect = now - lastDefendPress >= defense.DeflectCooldown
	lastDefendPress = now
	if state.mode == "Aturdido" then
		return
	end
	if state.mode == "Libre" or state.mode == "Carga" then
		startGuard(deflect)
	elseif state.mode == "Guardia" then
		startGuard(deflect)
	elseif state.mode == "Ataque" then
		local a = state.attack
		if a.phase == "recovery" and a.cancelable then
			startGuard(deflect)
		else
			queued = "Defender"
		end
	end
end

local function onDefendReleased()
	report("defender_fin")
	if queued == "Defender" then
		queued = nil
	end
	if state.mode == "Guardia" then
		endGuard()
	end
end

local function runQueued()
	local action = queued
	queued = nil
	if action == "Atacar" then
		startAttack(nextLightName())
	elseif action == "Defender" and input.IsHeld("Defender") then
		startGuard(false)
	end
end

-- ---------- Resultados del servidor ----------
local CALLOUTS = {
	desvio_perfecto = "¡DESVÍO PERFECTO!",
	desvio = "Desvío",
	contrapaso = "¡CONTRAPASO!",
	esquiva = "Esquiva",
	guardia = "Bloqueado",
	ruptura = "¡GUARDIA ROTA!",
	golpe = nil,
}

local function onDefenseResult(data)
	if data.player ~= player or not alive() then
		return
	end
	local result = data.result
	state.lastResult = result
	local from = typeof(data.from) == "Vector3" and data.from or root.Position
	local away = flat(root.Position - from)
	away = if away.Magnitude > 0.01 then away.Unit else -flat(root.CFrame.LookVector)

	if result == "desvio_perfecto" or result == "contrapaso" then
		state.counterUntil = os.clock() + defense.CounterWindow
	end
	-- La duración del aturdimiento la decide el servidor (anticadena, expuesto); 0 = Aguante
	local serverStun = if type(data.stun) == "number" then data.stun else nil
	if result == "golpe" then
		local duration = serverStun or defense.HitStun
		if duration > 0 then
			stun(duration, false)
		end
		movement.Knockback(away, defense.HitKnockback, 0.15)
	elseif result == "ruptura" then
		local duration = serverStun or defense.GuardBreakStun
		if duration > 0 then
			stun(duration, true)
		end
		movement.Knockback(away, defense.HitKnockback * 0.6, 0.12)
	end
	if serverStun == 0 and (result == "golpe" or result == "ruptura") then
		events.DefenseResult:Fire(data, "AGUANTE")
		Effects.DefenseFeedback(result, character, from)
		return
	end
	Effects.DefenseFeedback(result, character, from)
	events.DefenseResult:Fire(data, CALLOUTS[result])
end

-- ---------- Ciclo ----------
local function update(dt)
	if not alive() then
		return
	end

	if state.mode == "Aturdido" then
		if os.clock() >= state.stunnedUntil then
			endStun()
		end
		return
	end

	-- Fin de la ventana de desvío: si se mantiene Defender, guardia normal
	if state.deflecting and os.clock() - state.deflectStart >= defense.DeflectWindow then
		state.deflecting = false
		if state.mode == "Guardia" then
			playTrack("Guardia", 0.06)
		end
	end

	-- Guardia: mira al rival más cercano (la guardia solo cubre el frente)
	if state.mode == "Guardia" then
		local target = findSoftTarget(movement.DesiredDirection(), Config.SoftTargetRange, -1)
		if target then
			movement.SetAutoRotateBlocked(KEY, true)
			movement.Face(flat(targetRootOf(target).Position - root.Position))
		else
			movement.SetAutoRotateBlocked(KEY, false)
		end
	end

	-- Mantener Atacar pide el golpe fuerte
	if not heavyConsumed and input.IsHeld("Atacar") and os.clock() - attackPressTime >= Config.HoldThreshold then
		heavyConsumed = true
		heavyRequested = true
		queued = nil
	end

	-- Hitstop: el tiempo del golpe se congela un instante
	if hitstop > 0 then
		hitstop -= dt
		if hitstop <= 0 and currentTrack then
			currentTrack:AdjustSpeed(1)
		end
		return
	end

	if state.mode == "Libre" then
		if heavyRequested then
			heavyRequested = false
			startCharge()
		end
	elseif state.mode == "Ataque" then
		local a = state.attack
		local def = a.def
		a.t += dt
		if a.phase == "startup" and humanoid:GetState() == Enum.HumanoidStateType.Jumping then
			finishAttack() -- saltar en la preparación cancela el golpe (amague / movilidad)
			return
		end
		if a.phase == "startup" and a.t >= a.startup then
			enterActive(a)
		end
		if a.phase == "active" then
			detectHits(a)
			if hitstop > 0 then
				return
			end
			if a.t >= a.startup + def.active then
				enterRecovery(a)
			end
		end
		if a.phase == "recovery" then
			if heavyRequested and not def.finisher then
				heavyRequested = false
				startCharge()
				return
			end
			if a.cancelable and queued then
				runQueued()
				return
			end
			if humanoid:GetState() == Enum.HumanoidStateType.Jumping then
				finishAttack() -- el salto cancela la recuperación
				return
			end
			if a.t >= a.startup + def.active + a.recovery then
				finishAttack()
				if queued then
					runQueued()
				end
			end
		end
	elseif state.mode == "Carga" then
		chargeTime += dt
		state.charge = math.clamp(chargeTime / Config.HeavyMaxCharge, 0, 1)
		if not input.IsHeld("Atacar") or chargeTime >= Config.HeavyMaxCharge then
			releaseCharge()
		end
	end
end

local function bindCharacter(newCharacter)
	state.ready = false
	clearLocks()
	movement.ClearKey(STUN_KEY)
	stopTrack(0)
	state.mode = "Libre"
	state.attack = nil
	state.comboIndex = 0
	state.deflecting = false
	state.counterUntil = -math.huge
	queued = nil
	hitstop = 0
	heavyRequested = false
	heavyConsumed = true

	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid")
	root = newCharacter:WaitForChild("HumanoidRootPart")
	animator = humanoid:WaitForChild("Animator")
	Rig.MakeKinematic(newCharacter) -- poses exactas: las articulaciones siguen la animación al instante
	tracks = {}
	for _, name in ipairs(TRACK_NAMES) do
		local ok, track = pcall(AnimationLibrary.Load, animator, name)
		if ok then
			tracks[name] = track
		else
			warn("[UMBRAL] No se pudo cargar la animación " .. name .. ": " .. tostring(track))
		end
	end
	humanoid.Died:Connect(function()
		cancelToFree()
	end)
	state.ready = true
end

-- La Resonancia paga un Paso extra cuando no quedan cargas
local lastExtraDash = -math.huge
local function payExtraDash()
	if state.mode == "Aturdido" then
		return false
	end
	-- Como mucho un Paso extra cada ExtraDashCooldown (el servidor aplica la misma regla)
	if os.clock() - lastExtraDash < Config.Resonance.ExtraDashCooldown then
		return false
	end
	local available = (player:GetAttribute("Resonancia") or 0) - pendingSpend
	if available < Config.Resonance.DashCost or not remotes.spend then
		return false
	end
	pendingSpend += Config.Resonance.DashCost
	lastExtraDash = os.clock()
	remotes.spend:FireServer("paso")
	return true
end

function CombatController.Start(inputController, movementController)
	input = inputController
	movement = movementController

	input.ActionBegan:Connect(function(action)
		if action == "Atacar" then
			onAttackPressed()
		elseif action == "Defender" then
			onDefendPressed()
		elseif action == "Arma" then
			CombatController.SwitchWeapon()
		end
	end)
	-- El arma que dice el servidor manda (al entrar, al reaparecer)
	local function syncWeapon()
		local name = player:GetAttribute("Arma")
		if weapons[name or ""] and name ~= "Order" then
			state.weapon = name
		end
	end
	player:GetAttributeChangedSignal("Arma"):Connect(syncWeapon)
	syncWeapon()
	input.ActionEnded:Connect(function(action)
		if action == "Atacar" then
			onAttackReleased()
		elseif action == "Defender" then
			onDefendReleased()
		end
	end)

	-- El Paso: se informa al servidor (esquiva y Contrapaso) y cancela recuperación, carga y guardia
	movement.Dashed:Connect(function(direction)
		report("paso", direction)
		state.lastDash = os.clock()
		if state.mode == "Ataque" and state.attack and state.attack.phase ~= "active" then
			finishAttack() -- el Paso cancela la preparación (amague) o la recuperación
		elseif state.mode == "Carga" or state.mode == "Guardia" then
			cancelToFree()
		end
	end)
	movement.SetExtraDashProvider(payExtraDash)
	player:GetAttributeChangedSignal("Resonancia"):Connect(function()
		pendingSpend = 0 -- el servidor ya descontó lo pendiente
	end)

	player.CharacterAdded:Connect(bindCharacter)
	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end

	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("Remotes")
		remotes.request = folder:WaitForChild("SolicitudGolpe")
		remotes.start = folder:WaitForChild("InicioAtaque")
		remotes.defense = folder:WaitForChild("Defensa")
		remotes.spend = folder:WaitForChild("GastarResonancia")
		remotes.weapon = folder:WaitForChild("ElegirArma", 10)
		remotes.execute = folder:WaitForChild("GolpeDeGracia", 10)
		folder:WaitForChild("GolpeConfirmado").OnClientEvent:Connect(function(data)
			local mine = data.attacker == player
			Effects.OnConfirmed(data, mine)
			if mine then
				state.confirmedDamage += data.damage
				-- Si el servidor cambió el daño (coraza: bloqueado o por la espalda), el contador del combo se
				-- corrige con el daño real en vez de quedarse con el previsto
				local def = data.note and Config.Attacks[data.attack]
				if def then
					local predicted = def.damage * (if data.counter then defense.CounterDamageMultiplier else 1)
					state.comboDamage = math.max(0, state.comboDamage + data.damage - predicted)
					if data.damage <= 0 then
						state.comboHits = math.max(0, state.comboHits - 1)
					end
				end
				events.Confirmed:Fire(data)
			end
		end)
		folder:WaitForChild("ResultadoDefensa").OnClientEvent:Connect(onDefenseResult)
	end)

	RunService.Heartbeat:Connect(update)
end

-- Una habilidad del Eco corta lo que estés haciendo (preparación, recuperación, carga o guardia), como el Paso.
-- El combo NO se reinicia: tras la habilidad puedes seguir con el golpe que tocaba. Devuelve false si no se
-- puede (aturdido o sin personaje).
-- Liberación aceptada (o pedida): sale del aturdimiento en esta pantalla al instante
function CombatController.EndStun()
	if state.mode == "Aturdido" then
		endStun()
	end
end

-- ¿Puede una habilidad cortar lo que hace ahora? Devuelve true, o false + motivo + segundos que faltan.
-- Castigo al fallar (auditoría externa): la preparación se puede cortar (amago) y tras un golpe ACERTADO
-- también (ruta de combo); pero ni la fase activa ni la recuperación de un golpe FALLADO: la tecla espera en la
-- cola y sale justo al terminar (no se pierde y el rival tiene su ventana para castigar).
function CombatController.CancelForSkill()
	if not alive() or state.mode == "Aturdido" then
		return false, "aturdido"
	end
	local a = state.attack
	-- Solo en el suelo: en el aire las posiciones cambian tanto que esperar arruinaría los combos aéreos
	-- (el Descenso tras un golpe aéreo debe salir al instante)
	if state.mode == "Ataque" and a and movement.State.grounded then
		if a.phase == "active" then
			return false, "golpeando", math.max(0, a.startup + a.def.active - a.t) + 0.05
		end
		if a.phase == "recovery" and not a.hit then
			return false, "recuperando", math.max(0, a.startup + a.def.active + a.recovery - a.t)
		end
	end
	if state.mode == "Ataque" or state.mode == "Carga" or state.mode == "Guardia" then
		local keepIndex = state.comboIndex
		movement.StopLunge()
		cancelToFree()
		state.comboIndex = keepIndex
	end
	queued = nil
	heavyRequested = false
	heavyConsumed = true
	return true
end

-- Cambia de arma (Puños ↔ Espada). Solo estando libre; un instante sin poder atacar mientras se cambia.
function CombatController.SwitchWeapon(name)
	if not alive() or (state.mode ~= "Libre" and state.mode ~= "Guardia") then
		return false
	end
	local order = weapons.Order
	local current = table.find(order, state.weapon) or 1
	local nextName = name or order[current % #order + 1]
	if not weapons[nextName] or nextName == state.weapon then
		return false
	end
	if state.mode == "Guardia" then
		endGuard()
	end
	state.weapon = nextName
	state.comboIndex = 0
	state.switchUntil = os.clock() + weapons.SwitchTime
	if remotes.weapon then
		remotes.weapon:FireServer(nextName)
	end
	if nextName == "Espada" then
		playTrack("DesenvainarEspada", 0.05)
	end
	events.PhaseChanged:Fire("Arma", nextName)
	return true
end

-- Un golpe de habilidad confirmado por el servidor suma al contador de combo
function CombatController.RegisterSkillHit(damage, model)
	local t = os.clock()
	if t - state.lastHitTime > Config.ComboResetTime + 0.6 + 1.5 then
		state.comboHits = 0
		state.comboDamage = 0
	end
	state.comboHits += 1
	state.comboDamage += damage or 0
	state.lastHitTime = t
	events.Hit:Fire("Habilidad", model)
end

-- Número total de pistas de animación cargadas (para pruebas)
function CombatController.LoadedTrackCount()
	local n = 0
	for _ in pairs(tracks) do
		n += 1
	end
	return n
end

return CombatController
