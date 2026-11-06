-- Suite de pruebas de defensa (Fase 3): desvío, guardia, ruptura, Contrapaso, esquiva, salto,
-- interrupción, Contraataque y Resonancia, contra el compañero de combate del Ring.
-- Las acciones se programan con la hora del servidor para pulsar en el instante exacto respecto al impacto.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

return function(ctx)
	local Config, Input, Movement, Combat = ctx.CombatConfig, ctx.Input, ctx.Movement, ctx.Combat
	local record, near, waitUntil = ctx.record, ctx.near, ctx.waitUntil
	local player = ctx.player
	local defense = Config.Defense
	local gains = Config.Resonance.Gains
	local remotes = ReplicatedStorage:WaitForChild("Remotes")

	local results, started, confirms = {}, {}, {}
	local activeAt = {}
	local dashes = 0
	local connections = {
		remotes:WaitForChild("ResultadoDefensa").OnClientEvent:Connect(function(data)
			if data.player == player then
				table.insert(results, { result = data.result, damage = data.damage, attack = data.attack, id = data.attackId, t = os.clock() })
			end
		end),
		Combat.AttackStarted:Connect(function(name, _, counter)
			table.insert(started, { name = name, counter = counter, t = os.clock() })
		end),
		Combat.PhaseChanged:Connect(function(name, phase)
			if phase == "active" then
				table.insert(activeAt, { name = name, t = os.clock() })
			end
		end),
		Combat.Confirmed:Connect(function(data)
			table.insert(confirms, { attack = data.attack, damage = data.damage, target = data.target, counter = data.counter })
		end),
		Movement.Dashed:Connect(function()
			dashes += 1
		end),
	}
	local function cleanupAll()
		ctx.remote:FireServer("patron", "")
		for _, c in ipairs(connections) do
			c:Disconnect()
		end
	end

	local function serverNow()
		return Workspace:GetServerTimeNow()
	end
	local function resonance()
		return player:GetAttribute("Resonancia") or 0
	end

	-- ---------- Compañero de combate ----------
	local npc = nil
	waitUntil(function()
		npc = CollectionService:GetTagged("Sparring")[1]
		return npc ~= nil and npc:GetAttribute("Estado") ~= nil
	end, 25)
	record("Compañero de combate listo", npc ~= nil, if npc then "en el Ring, estado " .. tostring(npc:GetAttribute("Estado")) else "no apareció")
	if not npc then
		cleanupAll()
		return
	end
	local marker = Workspace:WaitForChild("Maps"):WaitForChild("MovementLab"):WaitForChild("Ring"):WaitForChild("PuntoSparring")
	local npcRoot = npc:WaitForChild("HumanoidRootPart")
	local npcHumanoid = npc:FindFirstChildOfClass("Humanoid")

	local function setPattern(name)
		ctx.remote:FireServer("patron", name)
		task.wait(0.1)
	end

	local rejectedAtStart = player:GetAttribute("GolpesRechazados") or 0

	-- Vida llena, sin postura, sin aturdimiento, sin Resonancia; controles sueltos
	local function reset()
		Input.Release("Defender")
		Input.Release("Atacar")
		ctx.humanoid:Move(Vector3.zero)
		ctx.remote:FireServer("reiniciar_defensa")
		ctx.remote:FireServer("resonancia", 0)
		waitUntil(function()
			return (player:GetAttribute("Postura") or 0) == 0 and Combat.State.mode ~= "Aturdido" and resonance() == 0
		end, 3)
	end

	local readySince = 0 -- hora del servidor en que el jugador quedó en posición
	local function stand(distance)
		local position = Vector3.new(marker.Position.X, npcRoot.Position.Y + 0.5, marker.Position.Z + distance)
		ctx.waitForCharges()
		ctx.teleport(position, Vector3.new(0, 0, -1))
		readySince = serverNow()
	end

	-- Espera un ataque del tipo pedido que EMPIECE después de ubicarse, con margen suficiente
	local function nextAttack(name, margin)
		local impact, id = nil, nil
		waitUntil(function()
			if npc:GetAttribute("Estado") == "Preparando" and npc:GetAttribute("Ataque") == name and (npc:GetAttribute("FaseInicio") or 0) > readySince then
				local finish = npc:GetAttribute("FaseFin")
				if finish - serverNow() >= (margin or 0.3) then
					impact, id = finish, npc:GetAttribute("AtaqueId")
					return true
				end
			end
			return false
		end, 9)
		return impact, id
	end

	local function at(serverTime)
		while serverNow() < serverTime do
			task.wait()
		end
	end

	local function resultFor(id, timeout)
		local found = nil
		waitUntil(function()
			for i = #results, 1, -1 do
				if results[i].id == id then
					found = results[i]
					return true
				end
			end
			return false
		end, timeout or 2)
		return found
	end

	local function describe(r, attackId)
		if r then
			return string.format("%s · %.1f de daño", r.result, r.damage)
		end
		local seen = {}
		for i = math.max(1, #results - 3), #results do
			table.insert(seen, string.format("%s#%s", results[i].result, tostring(results[i].id)))
		end
		return string.format("sin resultado para el ataque #%s (últimos: %s; estado %s #%s)", tostring(attackId), table.concat(seen, ", "), tostring(npc:GetAttribute("Estado")), tostring(npc:GetAttribute("AtaqueId")))
	end
	-- Estado del jugador justo antes de una acción (para entender un fallo)
	local function snapshot()
		return string.format("[%s · %s]", Combat.State.mode, Movement.Debug())
	end

	-- ---------- 1. Ataca al acercarse ----------
	setPattern("Golpe")
	reset()
	stand(3.5)
	local attacked = waitUntil(function()
		return npc:GetAttribute("Estado") == "Preparando"
	end, 4)
	record("Ataca al acercarse", attacked, "prepara un ataque cuando estás a 3,5 studs")
	resultFor(npc:GetAttribute("AtaqueId"), 2)
	task.wait(0.5)

	-- ---------- 2. Sin defensa: recibe el golpe y queda aturdido ----------
	reset()
	stand(3.5)
	local impact, id = nextAttack("Golpe")
	local healthBefore = ctx.humanoid.Health
	local r = resultFor(id)
	local stunned = waitUntil(function()
		return Combat.State.mode == "Aturdido"
	end, 0.3)
	local startedBefore = #started
	Input.Trigger("Atacar")
	task.wait(0.1)
	local blockedWhileStunned = #started == startedBefore
	record(
		"Sin defensa recibe el golpe",
		r ~= nil and r.result == "golpe" and near(r.damage, Config.Sparring.Attacks.Golpe.damage, 0.01) and ctx.humanoid.Health < healthBefore,
		describe(r, id)
	)
	record("Aturdido tras el golpe", stunned and blockedWhileStunned, "queda aturdido y no puede atacar durante el aturdimiento")

	-- ---------- 3. Desvío perfecto + Contraataque ----------
	reset()
	stand(3.5)
	impact, id = nextAttack("Golpe")
	local res0 = resonance()
	at(impact - 0.05)
	Input.Trigger("Defender")
	r = resultFor(id)
	local npcStunned = waitUntil(function()
		return npc:GetAttribute("Estado") == "Aturdido"
	end, 0.5)
	waitUntil(function()
		return resonance() > res0
	end, 0.5)
	record(
		"Desvío perfecto",
		r ~= nil and r.result == "desvio_perfecto" and r.damage == 0 and npcStunned,
		describe(r, id) .. string.format(" · rival aturdido: %s", tostring(npcStunned))
	)
	record("Resonancia por desvío perfecto", near(resonance() - res0, gains.DesvioPerfecto, 0.01), string.format("+%d (objetivo +%d)", resonance() - res0, gains.DesvioPerfecto))

	local s0, a0, c0 = #started, #activeAt, #confirms
	Input.Trigger("Atacar")
	waitUntil(function()
		return #confirms > c0
	end, 1)
	local counterStart, counterActive = started[s0 + 1], activeAt[a0 + 1]
	local counterConfirm = confirms[c0 + 1]
	local expectedCounter = Config.Attacks.Jab.damage * defense.CounterDamageMultiplier
	record(
		"Contraataque tras el desvío",
		counterStart ~= nil and counterStart.counter == true and counterConfirm ~= nil and counterConfirm.counter == true and near(counterConfirm.damage, expectedCounter, 0.01),
		if counterConfirm then string.format("%.1f de daño (objetivo %.1f), confirmado por el servidor", counterConfirm.damage, expectedCounter) else "no conectó"
	)
	local counterStartup = if counterStart and counterActive then counterActive.t - counterStart.t else -1
	local expectedStartup = Config.Attacks.Jab.startup * defense.CounterStartupMultiplier
	record("El Contraataque sale más rápido", counterStartup >= 0 and counterStartup <= expectedStartup + 0.035, string.format("preparación %.3f s (objetivo %.3f)", counterStartup, expectedStartup))

	-- ---------- 4. Desvío normal, tardío y machacando ----------
	reset()
	stand(3.5)
	impact, id = nextAttack("Golpe")
	res0 = resonance()
	at(impact - 0.15)
	Input.Trigger("Defender")
	r = resultFor(id)
	waitUntil(function()
		return resonance() > res0
	end, 0.5)
	record("Desvío normal", r ~= nil and r.result == "desvio" and r.damage == 0 and near(resonance() - res0, gains.Desvio, 0.01), describe(r, id) .. string.format(" · +%d Resonancia", resonance() - res0))

	reset()
	stand(3.5)
	impact, id = nextAttack("Golpe")
	at(impact + 0.06)
	Input.Trigger("Defender")
	r = resultFor(id)
	record("Desvío tardío no sirve", r ~= nil and r.result == "golpe", describe(r, id))

	reset()
	stand(3.5)
	impact, id = nextAttack("Golpe", 0.45)
	-- Si el rival no preparó un ataque a tiempo, se registra como fallo (no como error de la suite)
	local pressTime = (impact or serverNow()) - 0.42
	while impact and pressTime <= impact + 0.02 do
		at(pressTime)
		Input.Trigger("Defender")
		pressTime += 0.08
	end
	r = resultFor(id)
	record("Machacar Defender no sirve", r ~= nil and r.result == "golpe", describe(r, id) .. " (pulsando cada 0,08 s)")

	-- ---------- 5. Guardia y ruptura ----------
	reset()
	stand(3.5)
	impact, id = nextAttack("Golpe")
	at(impact - 0.45)
	Input.Press("Defender")
	r = resultFor(id)
	local posture = player:GetAttribute("Postura") or 0
	Input.Release("Defender")
	record(
		"Guardia",
		r ~= nil and r.result == "guardia" and near(r.damage, Config.Sparring.Attacks.Golpe.damage * defense.GuardDamageMultiplier, 0.01) and posture >= Config.Sparring.Attacks.Golpe.posture - 1,
		describe(r, id) .. string.format(" · postura %d", posture)
	)

	reset()
	stand(3.5)
	Input.Press("Defender")
	local chain = {}
	for _ = 1, 4 do
		impact, id = nextAttack("Golpe", 0.05)
		r = resultFor(id, 3)
		table.insert(chain, if r then r.result else "nada")
		if r and r.result == "ruptura" then
			break
		end
	end
	local brokenStun = waitUntil(function()
		return Combat.State.mode == "Aturdido"
	end, 0.3)
	Input.Release("Defender")
	record("Ruptura de guardia", chain[#chain] == "ruptura" and #chain == 4 and brokenStun, table.concat(chain, " → "))

	-- ---------- 6. Barrido: no se bloquea, se salta ----------
	setPattern("Barrido")
	reset()
	stand(3.5)
	Input.Press("Defender")
	impact, id = nextAttack("Barrido")
	r = resultFor(id)
	Input.Release("Defender")
	record("El barrido no se bloquea", r ~= nil and r.result == "golpe" and near(r.damage, Config.Sparring.Attacks.Barrido.damage, 0.01), describe(r, id) .. " (con guardia puesta)")

	reset()
	stand(3.5)
	impact, id = nextAttack("Barrido")
	res0 = resonance()
	at(impact - 0.15)
	local beforeJump = snapshot()
	ctx.humanoid.Jump = true
	r = resultFor(id)
	record("Saltar el barrido", r ~= nil and r.result == "esquiva" and r.damage == 0, describe(r, id) .. " " .. beforeJump)

	-- ---------- 7. Contrapaso ----------
	setPattern("Golpe")
	reset()
	stand(3.5)
	impact, id = nextAttack("Golpe")
	res0 = resonance()
	at(impact - 0.15)
	ctx.humanoid:Move(Vector3.new(1, 0, 0)) -- de lado respecto al rival
	task.wait()
	task.wait()
	local beforeContrapaso = snapshot()
	Input.Trigger("Paso")
	r = resultFor(id)
	ctx.humanoid:Move(Vector3.zero)
	waitUntil(function()
		return resonance() > res0
	end, 0.5)
	record(
		"Contrapaso",
		r ~= nil and r.result == "contrapaso" and r.damage == 0 and near(resonance() - res0, gains.Contrapaso, 0.01),
		describe(r, id) .. string.format(" · +%d Resonancia ", resonance() - res0) .. beforeContrapaso
	)
	c0 = #confirms
	s0 = #started
	task.wait(0.15)
	Input.Trigger("Atacar")
	waitUntil(function()
		return #confirms > c0
	end, 1)
	counterConfirm = confirms[c0 + 1]
	record(
		"Contraataque vuelve al rival",
		started[s0 + 1] ~= nil and started[s0 + 1].counter == true and counterConfirm ~= nil and counterConfirm.target == npc and counterConfirm.counter == true,
		if counterConfirm then string.format("tras apartarse de lado, vuelve y conecta (%.1f de daño)", counterConfirm.damage) else "no conectó"
	)

	setPattern("Barrido")
	reset()
	stand(3.5)
	impact, id = nextAttack("Barrido")
	at(impact - 0.15)
	ctx.humanoid:Move(Vector3.new(1, 0, 0))
	task.wait()
	task.wait()
	local beforeSweepDash = snapshot()
	Input.Trigger("Paso")
	r = resultFor(id)
	ctx.humanoid:Move(Vector3.zero)
	record("El barrido no admite Contrapaso", r ~= nil and r.result == "esquiva" and os.clock() > Combat.State.counterUntil, describe(r, id) .. " (sale del área, pero sin Contraataque) " .. beforeSweepDash)

	-- ---------- 8. Esquiva precisa ----------
	setPattern("Golpe")
	reset()
	stand(3.5)
	impact, id = nextAttack("Golpe")
	res0 = resonance()
	-- El Paso tarda 0,18 s en recorrer 14 studs: para salir de un alcance de ~10 studs desde 3,5 studs hay
	-- que salir ~0,2 s antes (dentro de la ventana de esquiva precisa de 0,3 s). Con 0,13 s el jugador
	-- seguía dentro del área: la prueba pedía algo físicamente imposible.
	at(impact - 0.22)
	ctx.humanoid:Move(Vector3.new(0, 0, 1)) -- hacia atrás
	task.wait()
	task.wait()
	local beforeDodge = snapshot()
	Input.Trigger("Paso")
	r = resultFor(id)
	ctx.humanoid:Move(Vector3.zero)
	waitUntil(function()
		return resonance() > res0
	end, 0.5)
	record("Esquiva precisa", r ~= nil and r.result == "esquiva" and near(resonance() - res0, gains.Esquiva, 0.01), describe(r, id) .. string.format(" · +%d Resonancia ", resonance() - res0) .. beforeDodge)

	-- ---------- 9. Interrupción ----------
	reset()
	stand(3.2)
	impact, id = nextAttack("Golpe", 0.45)
	Input.Press("Atacar")
	task.wait(0.28)
	Input.Release("Atacar")
	local interrupted = waitUntil(function()
		return npc:GetAttribute("Estado") == "Aturdido"
	end, 0.8)
	task.wait(0.4)
	local gotResult = resultFor(id, 0.2) ~= nil
	record("El golpe fuerte interrumpe su preparación", interrupted and not gotResult, "el ataque se cancela y queda aturdido")

	reset()
	stand(3.2)
	impact, id = nextAttack("Golpe", 0.4)
	Input.Trigger("Atacar")
	local continued = waitUntil(function()
		return npc:GetAttribute("Estado") == "Atacando"
	end, 1)
	resultFor(id)
	record("Los golpes rápidos no lo interrumpen", continued, "un Jab en la preparación no cancela su ataque")

	-- ---------- 10. Resonancia ----------
	ctx.waitForCharges()
	ctx.teleport(Vector3.new(0, 4, 150), Vector3.new(0, 0, 1)) -- lejos del Ring
	ctx.remote:FireServer("resonancia", 60)
	waitUntil(function()
		return resonance() == 60
	end, 1)
	ctx.waitForCharges()
	local d0 = dashes
	for _ = 1, 3 do
		Input.Trigger("Paso")
		task.wait(0.3)
	end
	waitUntil(function()
		return resonance() <= 30
	end, 1)
	record("Paso extra con Resonancia", dashes - d0 == 3 and near(resonance(), 30, 0.5), string.format("%d Pasos con 2 cargas · Resonancia %d (objetivo 30)", dashes - d0, resonance()))

	ctx.remote:FireServer("resonancia", 10)
	waitUntil(function()
		return resonance() == 10
	end, 1)
	ctx.waitForCharges()
	d0 = dashes
	for _ = 1, 3 do
		Input.Trigger("Paso")
		task.wait(0.3)
	end
	record("Sin Resonancia no hay Paso extra", dashes - d0 == 2, string.format("%d Pasos (con 10 de Resonancia)", dashes - d0))

	ctx.remote:FireServer("resonancia", 50)
	waitUntil(function()
		return resonance() == 50
	end, 1)
	task.wait(Config.Resonance.DecayDelay + 1.2)
	record("La Resonancia se apaga fuera de combate", resonance() < 50, string.format("50 → %d tras %.1f s sin combatir", resonance(), Config.Resonance.DecayDelay + 1.2))

	-- ---------- 11. El servidor manda ----------
	local defenseRemote = remotes:WaitForChild("Defensa")
	local rejected0 = player:GetAttribute("DefensasRechazadas") or 0
	defenseRemote:FireServer("defender_inicio", serverNow() + 2)
	defenseRemote:FireServer("defender_fin", serverNow() - 3)
	waitUntil(function()
		return (player:GetAttribute("DefensasRechazadas") or 0) >= rejected0 + 2
	end, 1)
	record("Rechaza tiempos de defensa falsos", (player:GetAttribute("DefensasRechazadas") or 0) == rejected0 + 2, "una hora futura y una demasiado vieja")
	record("Ningún golpe legítimo rechazado en la defensa", (player:GetAttribute("GolpesRechazados") or 0) == rejectedAtStart, string.format("%d rechazados en esta suite", (player:GetAttribute("GolpesRechazados") or 0) - rejectedAtStart))

	-- ---------- 12. Desvío a baja tasa de cuadros ----------
	local removeLoad, measureFps = ctx.artificialLoad(0.026)
	local lowFps = measureFps()
	setPattern("Golpe")
	reset()
	stand(3.5)
	impact, id = nextAttack("Golpe")
	at(impact - 0.05)
	Input.Trigger("Defender")
	r = resultFor(id)
	removeLoad()
	record("Desvío perfecto a baja tasa de cuadros", lowFps <= 40 and r ~= nil and r.result == "desvio_perfecto", describe(r, id) .. string.format(" a %d FPS", lowFps))

	reset()
	cleanupAll()
	local _ = npcHumanoid
end
