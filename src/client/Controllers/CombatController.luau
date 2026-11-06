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
local Effects = require(script.Parent:WaitForChild("EffectsController"))

local defense = Config.Defense
local player = Players.LocalPlayer
local KEY = "combate" -- clave de los bloqueos que este sistema pone al movimiento
local STUN_KEY = "aturdido"
local TRACK_NAMES = { "Jab", "Cross", "Patada", "CargaFuerte", "Fuerte", "Guardia", "Desvio", "Aturdido", "Reaccion" }

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

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function serverNow()
	return Workspace:GetServerTimeNow()
end

local function report(action, dir)
	if remotes.defense then
		remotes.defense:FireServer(action, serverNow(), dir)
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
local function setAttackLocks(phase)
	local committed = phase == "startup" or phase == "active"
	movement.SetDashBlocked(KEY, committed)
	movement.SetJumpBlocked(KEY, committed)
	movement.SetAutoRotateBlocked(KEY, true)
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

	local toAttacker = flat(root.Position - targetRoot.Position)
	local hitPosition = targetRoot.Position + Vector3.new(0, 0.6, 0)
	if toAttacker.Magnitude > 0.01 then
		hitPosition += toAttacker.Unit * 0.9
	end
	Effects.Impact(hitPosition, def, model)

	if remotes.request then
		remotes.request:FireServer({ attack = a.name, seq = a.seq, target = model, charge = a.charge })
	end
	events.Hit:Fire(a.name, model)
end

local function detectHits(a)
	local def = a.def
	local boxCFrame = root.CFrame * CFrame.new(0, 0, -(def.range / 2 + 0.5))
	overlapParams.FilterDescendantsInstances = { character, Workspace.CurrentCamera }
	for _, part in ipairs(Workspace:GetPartBoundsInBox(boxCFrame, def.hitboxSize, overlapParams)) do
		local model = part:FindFirstAncestorOfClass("Model")
		while model and not model:FindFirstChildOfClass("Humanoid") do
			model = model:FindFirstAncestorOfClass("Model")
		end
		if model and model ~= character and not a.targets[model] then
			local targetRoot = targetRootOf(model)
			if targetRoot then
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

	local lungeTime = startup + def.active
	local maxLunge = if counter then defense.CounterMaxLunge else Config.MaxLunge
	local lungeDistance = if target then math.clamp(distance - Config.IdealDistance, 0, maxLunge) else Config.LungeWithoutTarget
	if lungeDistance > 0.05 then
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
	state.comboIndex = state.comboIndex % #Config.LightChain + 1
	return Config.LightChain[state.comboIndex]
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
	playTrack("CargaFuerte", 0.05)
	events.PhaseChanged:Fire("Fuerte", "carga")
end

local function releaseCharge()
	startAttack("Fuerte", math.clamp(chargeTime / Config.HeavyMaxCharge, 0, 1))
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

local function onAttackPressed()
	if not alive() or state.mode == "Aturdido" then
		return
	end
	attackPressTime = os.clock()
	heavyConsumed = false
	heavyRequested = false
	if state.mode == "Libre" then
		startAttack(nextLightName())
	elseif state.mode == "Guardia" then
		endGuard()
		startAttack(nextLightName())
	elseif state.mode == "Ataque" then
		local a = state.attack
		if a.phase == "recovery" and a.cancelable then
			startAttack(nextLightName())
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
	if result == "golpe" then
		stun(defense.HitStun, false)
		movement.Knockback(away, defense.HitKnockback, 0.15)
	elseif result == "ruptura" then
		stun(defense.GuardBreakStun, true)
		movement.Knockback(away, defense.HitKnockback * 0.6, 0.12)
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
local function payExtraDash()
	if state.mode == "Aturdido" then
		return false
	end
	local available = (player:GetAttribute("Resonancia") or 0) - pendingSpend
	if available < Config.Resonance.DashCost or not remotes.spend then
		return false
	end
	pendingSpend += Config.Resonance.DashCost
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
		end
	end)
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
		if state.mode == "Ataque" and state.attack and state.attack.phase == "recovery" then
			finishAttack()
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
		remotes.defense = folder:WaitForChild("Defensa")
		remotes.spend = folder:WaitForChild("GastarResonancia")
		folder:WaitForChild("GolpeConfirmado").OnClientEvent:Connect(function(data)
			local mine = data.attacker == player
			Effects.OnConfirmed(data, mine)
			if mine then
				state.confirmedDamage += data.damage
				events.Confirmed:Fire(data)
			end
		end)
		folder:WaitForChild("ResultadoDefensa").OnClientEvent:Connect(onDefenseResult)
	end)

	RunService.Heartbeat:Connect(update)
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
