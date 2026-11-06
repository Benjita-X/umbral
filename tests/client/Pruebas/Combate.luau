-- Suite de pruebas del combate corporal (Fase 2).
-- Corre después de la de movimiento, que ya hizo reaparecer al personaje: todo esto prueba también
-- que el combate funciona con un personaje nuevo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

return function(ctx)
	local Config, Input, Movement, Combat = ctx.CombatConfig, ctx.Input, ctx.Movement, ctx.Combat
	local record, near, waitUntil = ctx.record, ctx.near, ctx.waitUntil
	local player = ctx.player
	local attacks = Config.Attacks

	-- ---------- Registro de lo que pasa ----------
	local started, ended, hits, confirms = {}, {}, {}, {}
	local poses = {}
	local dashes = 0
	local LIMB_FOR = { Jab = "LeftHand", Cross = "RightHand", Patada = "RightFoot", Fuerte = "RightHand" }
	local UPPER_FOR = { Jab = "LeftUpperArm", Cross = "RightUpperArm", Patada = "RightUpperLeg", Fuerte = "RightUpperArm" }
	local connections = {
		Combat.AttackStarted:Connect(function(name)
			table.insert(started, { name = name, t = os.clock() })
		end),
		Combat.AttackEnded:Connect(function(name, hit)
			table.insert(ended, { name = name, hit = hit, t = os.clock() })
		end),
		Combat.Hit:Connect(function(name, target)
			table.insert(hits, { name = name, target = target, t = os.clock() })
		end),
		Combat.Confirmed:Connect(function(data)
			table.insert(confirms, { attack = data.attack, damage = data.damage, health = data.health, target = data.target, t = os.clock() })
		end),
		Movement.Dashed:Connect(function()
			dashes += 1
		end),
		-- Pose en el impacto: DIRECCIÓN desde la articulación (hombro o cadera) hasta la mano o el pie, en el
		-- espacio del cuerpo. No depende del tamaño del avatar. Se guarda la mejor de todas las veces.
		Combat.PhaseChanged:Connect(function(name, phase)
			if phase == "active" and LIMB_FOR[name] then
				task.delay(0.03, function()
					local character = player.Character
					local limb = character and character:FindFirstChild(LIMB_FOR[name])
					local body = character and character:FindFirstChild("HumanoidRootPart")
					local upper = character and character:FindFirstChild(UPPER_FOR[name])
					local joint = upper and (upper:FindFirstChildOfClass("AnimationConstraint") or upper:FindFirstChildOfClass("Motor6D"))
					if not limb or not body or not joint then
						return
					end
					local pivot = if joint:IsA("AnimationConstraint") then joint.Attachment0.WorldPosition else (joint.Part0.CFrame * joint.C0).Position
					local direction = body.CFrame:VectorToObjectSpace((limb.Position - pivot).Unit)
					local sample = { forward = -direction.Z, up = direction.Y, count = 1 }
					local previous = poses[name]
					if previous then
						sample.count = previous.count + 1
						if previous.forward > sample.forward then
							sample.forward, sample.up = previous.forward, previous.up
						end
					end
					poses[name] = sample
				end)
			end
		end),
	}

	local function since(list, from)
		local out = {}
		for i = from + 1, #list do
			table.insert(out, list[i])
		end
		return out
	end
	local function names(list)
		local out = {}
		for _, item in ipairs(list) do
			table.insert(out, item.name or item.attack)
		end
		return table.concat(out, ", ")
	end
	local function sumDamage(list)
		local total = 0
		for _, c in ipairs(list) do
			total += c.damage
		end
		return total
	end

	-- ---------- Muñecos ----------
	local folder = Workspace:WaitForChild("Munecos", 20)
	local ready = folder ~= nil and waitUntil(function()
		return #folder:GetChildren() >= 4
	end, 25)
	record("Muñecos en el Dojo", ready, string.format("%d muñecos", if folder then #folder:GetChildren() else 0))
	if not ready then
		for _, c in ipairs(connections) do
			c:Disconnect()
		end
		return
	end
	local dojo = Workspace:WaitForChild("Maps"):WaitForChild("MovementLab"):WaitForChild("Dojo")
	local function dummy(name)
		local model = folder:WaitForChild(name, 5)
		return model, model:FindFirstChildOfClass("Humanoid"), model:FindFirstChild("HumanoidRootPart"), dojo:FindFirstChild("Punto" .. name)
	end

	local m1, h1 = dummy("Muneco1")
	record(
		"Muñecos R15 con vida completa",
		h1.RigType == Enum.HumanoidRigType.R15 and h1.Health == Config.Dummy.MaxHealth and m1:HasTag("Objetivo"),
		string.format("RigType %s, vida %d/%d", h1.RigType.Name, h1.Health, h1.MaxHealth)
	)
	record("Animaciones de combate cargadas", Combat.LoadedTrackCount() == 9, string.format("%d de 9 pistas", Combat.LoadedTrackCount()))

	local function waitComboReset()
		waitUntil(function()
			return Combat.State.mode == "Libre" and os.clock() - Combat.State.lastAttackEnd > Config.ComboResetTime + 0.05
		end, 3)
	end

	-- Deja el muñeco en su sitio, quieto y con vida, y pone al jugador delante (a `distance`, girado `angle`)
	local function prepare(name, distance, angle)
		local model, humanoid, body, marker = dummy(name)
		waitUntil(function()
			return (body.Position - marker.Position).Magnitude < 3
				and body.AssemblyLinearVelocity.Magnitude < 1
				and humanoid.Health >= math.min(70, humanoid.MaxHealth)
		end, 9)
		ctx.waitForCharges()
		local look = Vector3.new(0, 0, -1)
		if angle then
			look = CFrame.Angles(0, math.rad(angle), 0):VectorToWorldSpace(look)
		end
		ctx.teleport(Vector3.new(body.Position.X, body.Position.Y + 0.5, body.Position.Z + distance), look)
		waitComboReset()
		return model, humanoid, body
	end

	local function openArea()
		ctx.waitForCharges()
		ctx.teleport(Vector3.new(0, 4, 150), Vector3.new(0, 0, 1))
		waitComboReset()
	end

	-- ---------- 1. Golpe rápido, efectos y hitstop ----------
	local model, humanoid, body = prepare("Muneco1", 3.2)
	local h0 = humanoid.Health
	local c0, s0, e0 = #confirms, #started, #ended
	local snapshot = {}
	local snap = Combat.Hit:Connect(function()
		local fx = Workspace.CurrentCamera:FindFirstChild("UmbralEfectos")
		local impact = fx and fx:FindFirstChild("ImpactoUmbral")
		snapshot.impact = impact ~= nil
		snapshot.flash = fx ~= nil and fx:FindFirstChild("UmbralDestello") ~= nil
		snapshot.sound = impact ~= nil and impact:FindFirstChild("SonidoHit") ~= nil
	end)
	Input.Trigger("Atacar")
	local confirmed = waitUntil(function()
		return #confirms > c0
	end, 1.5)
	waitUntil(function()
		return #ended > e0
	end, 1)
	snap:Disconnect()
	local c = confirms[#confirms]
	record(
		"Golpe rápido conecta",
		confirmed and c.attack == "Jab" and near(h0 - c.health, attacks.Jab.damage, 0.01),
		if confirmed then string.format("%s confirmado por el servidor: %d de daño (vida %d → %d)", c.attack, c.damage, h0, c.health) else "el servidor no confirmó el golpe"
	)
	record(
		"Efectos de impacto",
		snapshot.impact and snapshot.flash and snapshot.sound,
		string.format("chispas %s · destello %s · sonido %s", tostring(snapshot.impact), tostring(snapshot.flash), tostring(snapshot.sound))
	)
	local jabStart, jabEnd = started[s0 + 1], ended[e0 + 1]
	local expectedHit = attacks.Jab.startup + attacks.Jab.active + attacks.Jab.recovery + attacks.Jab.hitstop
	local durationHit = if jabStart and jabEnd then jabEnd.t - jabStart.t else -1
	record("Duración del golpe con hitstop", near(durationHit, expectedHit, 0.06), string.format("%.2f s (objetivo %.2f)", durationHit, expectedHit))

	-- ---------- 2. Encadenar solo si conecta ----------
	prepare("Muneco1", 3.2)
	s0 = #started
	Input.Trigger("Atacar")
	task.wait(0.1)
	Input.Trigger("Atacar")
	waitUntil(function()
		return #started >= s0 + 2
	end, 1)
	local gapHit = if started[s0 + 2] then started[s0 + 2].t - started[s0 + 1].t else -1
	local expectedGapHit = attacks.Jab.startup + attacks.Jab.active + attacks.Jab.hitstop
	record("Encadenar al conectar", near(gapHit, expectedGapHit, 0.06), string.format("el Directo sale a los %.2f s (objetivo %.2f)", gapHit, expectedGapHit))

	openArea()
	s0, e0 = #started, #ended
	Input.Trigger("Atacar")
	task.wait(0.1)
	Input.Trigger("Atacar")
	waitUntil(function()
		return #started >= s0 + 2
	end, 1.5)
	local gapWhiff = if started[s0 + 2] then started[s0 + 2].t - started[s0 + 1].t else -1
	local expectedGapWhiff = attacks.Jab.startup + attacks.Jab.active + attacks.Jab.recovery * Config.WhiffRecoveryMultiplier
	record(
		"Fallar no se cancela",
		near(gapWhiff, expectedGapWhiff, 0.06) and ended[e0 + 1] ~= nil and ended[e0 + 1].hit == false,
		string.format("tras fallar, el siguiente sale a los %.2f s (objetivo %.2f)", gapWhiff, expectedGapWhiff)
	)

	-- ---------- 3. Combo de 3 y remate ----------
	local m2, hm2, b2 = prepare("Muneco2", 3.2)
	s0, c0 = #started, #confirms
	local beforePos = b2.Position
	Input.Trigger("Atacar")
	task.wait(0.1)
	Input.Trigger("Atacar")
	task.wait(0.1)
	Input.Trigger("Atacar")
	waitUntil(function()
		return #confirms >= c0 + 3
	end, 2)
	task.wait(0.3)
	local comboStarted, comboConfirms = since(started, s0), since(confirms, c0)
	local expectedCombo = attacks.Jab.damage + attacks.Cross.damage + attacks.Patada.damage
	record(
		"Combo de 3 golpes",
		names(comboStarted) == "Jab, Cross, Patada" and #comboConfirms == 3 and near(sumDamage(comboConfirms), expectedCombo, 0.01),
		string.format("%s · %d confirmados · %d de daño (objetivo %d)", names(comboStarted), #comboConfirms, sumDamage(comboConfirms), expectedCombo)
	)
	record("Contador de combo", Combat.State.comboHits >= 3, string.format("x%d", Combat.State.comboHits))
	local pushed = Vector3.new(b2.Position.X - beforePos.X, 0, b2.Position.Z - beforePos.Z).Magnitude
	record("El remate empuja", pushed >= 2.5, string.format("el muñeco se movió %.1f studs", pushed))

	-- ---------- 4. El combo se reinicia ----------
	openArea()
	s0 = #started
	Input.Trigger("Atacar")
	task.wait(Config.ComboResetTime + 0.45)
	Input.Trigger("Atacar")
	waitUntil(function()
		return #started >= s0 + 2
	end, 1)
	record("El combo se reinicia tras una pausa", names(since(started, s0)) == "Jab, Jab", names(since(started, s0)))

	-- ---------- 5. Golpe fuerte ----------
	local mT, hT, bT = prepare("MunecoAguante", 3.2)
	s0, c0 = #started, #confirms
	beforePos = bT.Position
	local maxRise = 0
	Input.Press("Atacar")
	task.wait(0.6)
	Input.Release("Atacar")
	local t0 = os.clock()
	while os.clock() - t0 < 1 do
		maxRise = math.max(maxRise, bT.Position.Y - beforePos.Y)
		task.wait()
	end
	local heavyConfirm = nil
	for _, conf in ipairs(since(confirms, c0)) do
		if conf.attack == "Fuerte" then
			heavyConfirm = conf
		end
	end
	local heavyMin, heavyMax = attacks.Fuerte.damage, attacks.Fuerte.damage + attacks.Fuerte.chargeBonus
	record(
		"Mantener = golpe fuerte",
		names(since(started, s0)) == "Jab, Fuerte" and heavyConfirm ~= nil and heavyConfirm.damage >= heavyMin and heavyConfirm.damage <= heavyMax,
		string.format("%s · daño del fuerte %s (entre %d y %d)", names(since(started, s0)), if heavyConfirm then string.format("%.1f", heavyConfirm.damage) else "—", heavyMin, heavyMax)
	)
	pushed = Vector3.new(bT.Position.X - beforePos.X, 0, bT.Position.Z - beforePos.Z).Magnitude
	record("El golpe fuerte empuja y levanta", pushed >= 3 and maxRise >= 0.5, string.format("empuje %.1f studs · sube %.1f studs", pushed, maxRise))

	prepare("MunecoAguante", 3.2)
	s0, c0 = #started, #confirms
	Input.Press("Atacar")
	task.wait(1.3)
	local releasedAlone = false
	for _, st in ipairs(since(started, s0)) do
		if st.name == "Fuerte" then
			releasedAlone = true
		end
	end
	Input.Release("Atacar")
	waitUntil(function()
		for _, conf in ipairs(since(confirms, c0)) do
			if conf.attack == "Fuerte" then
				return true
			end
		end
		return false
	end, 1)
	heavyConfirm = nil
	for _, conf in ipairs(since(confirms, c0)) do
		if conf.attack == "Fuerte" then
			heavyConfirm = conf
		end
	end
	record(
		"Carga completa sale sola",
		releasedAlone and heavyConfirm ~= nil and near(heavyConfirm.damage, heavyMax, 0.01),
		string.format("sale sin soltar: %s · daño %s (objetivo %d)", tostring(releasedAlone), if heavyConfirm then string.format("%.1f", heavyConfirm.damage) else "—", heavyMax)
	)

	-- ---------- 6. Orientación asistida y alcance ----------
	local m3 = prepare("Muneco3", 4, 50)
	c0 = #confirms
	Input.Trigger("Atacar")
	local turned = waitUntil(function()
		return #confirms > c0
	end, 1)
	record("Orientación asistida", turned and confirms[#confirms].target == m3, "mirando 50° hacia otro lado, el golpe se orienta y conecta")

	prepare("Muneco1", 6.5)
	c0 = #confirms
	Input.Trigger("Atacar")
	local reached = waitUntil(function()
		return #confirms > c0
	end, 1)
	record("El golpe se acerca al rival", reached, "a 6,5 studs el golpe avanza y conecta")

	prepare("Muneco1", 13)
	c0 = #confirms
	Input.Trigger("Atacar")
	task.wait(0.8)
	record("Fuera de alcance no conecta", #confirms == c0, "a 13 studs el golpe sale al aire")

	-- ---------- 7. Cancelaciones con Paso ----------
	prepare("Muneco1", 3.2)
	local d0 = dashes
	Input.Trigger("Atacar")
	task.wait()
	task.wait()
	Input.Trigger("Paso")
	task.wait(0.05)
	local blocked = dashes == d0
	-- Segunda parte: un golpe nuevo, y en su recuperación el Paso también lo termina
	ctx.settle()
	ctx.waitForCharges()
	local d1 = dashes
	Input.Trigger("Atacar")
	waitUntil(function()
		return Combat.State.attack ~= nil and Combat.State.attack.phase == "recovery"
	end, 1)
	Input.Trigger("Paso")
	local canceled = waitUntil(function()
		return dashes > d1 and Combat.State.mode == "Libre"
	end, 0.4)
	-- Diseño desde el 2026-11-06 (DECISIONES #49): el Paso CANCELA la preparación del golpe (movilidad y amagues)
	local dashCanceledStartup = not blocked
	record("El Paso cancela la preparación del golpe", dashCanceledStartup, if dashCanceledStartup then "el Paso sale y el golpe se cancela" else "el Paso no salió durante la preparación")
	record("El Paso cancela la recuperación", canceled, "en la recuperación el Paso sale y termina el golpe")

	openArea()
	s0 = #started
	Input.Trigger("Paso")
	waitUntil(function()
		return Movement.State.dashing
	end, 0.3)
	Input.Trigger("Atacar")
	local attackedFromDash = waitUntil(function()
		return #started > s0
	end, 0.4)
	record(
		"Golpear desde el Paso",
		attackedFromDash and not Movement.State.dashing and Movement.State.lastDashDistance < ctx.MovementConfig.DashDistance - 1,
		string.format("el Paso se corta a %.1f studs y sale el golpe", Movement.State.lastDashDistance)
	)

	-- ---------- 8. Guardia ----------
	openArea()
	Input.Press("Defender")
	local guarding = waitUntil(function()
		return Combat.State.mode == "Guardia"
	end, 0.3)
	ctx.humanoid:Move(Vector3.new(0, 0, 1))
	task.wait(0.25)
	local guardSpeed = ctx.flatSpeed()
	local expectedGuard = ctx.MovementConfig.RunSpeed * Config.GuardMoveMultiplier
	Input.Release("Defender")
	local unguarded = waitUntil(function()
		return Combat.State.mode == "Libre"
	end, 0.3)
	task.wait(0.2)
	local freeSpeed = ctx.flatSpeed()
	ctx.humanoid:Move(Vector3.zero)
	record(
		"Guardia",
		guarding and unguarded and near(guardSpeed, expectedGuard, 1.5) and freeSpeed > ctx.MovementConfig.RunSpeed - 1,
		string.format("en guardia %.1f studs/s (objetivo %.1f), al soltar %.1f", guardSpeed, expectedGuard, freeSpeed)
	)

	openArea()
	Input.Press("Defender")
	waitUntil(function()
		return Combat.State.mode == "Guardia"
	end, 0.3)
	Input.Trigger("Atacar")
	local fromGuard = waitUntil(function()
		return Combat.State.mode == "Ataque"
	end, 0.3)
	Input.Release("Defender")
	record("Golpear desde la guardia", fromGuard, "pulsar Atacar en guardia la suelta y golpea")

	-- ---------- 9. El servidor manda ----------
	local rejectedBefore = player:GetAttribute("GolpesRechazados") or 0
	record("Ningún golpe legítimo rechazado", rejectedBefore == 0, string.format("%d rechazados hasta ahora", rejectedBefore))
	local request = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SolicitudGolpe")
	local mA, hA = dummy("Muneco1")

	local startRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("InicioAtaque")
	local Workspace = game:GetService("Workspace")
	local function serverNow()
		return Workspace:GetServerTimeNow()
	end
	-- Los inicios falsos usan números de secuencia propios; después se adelanta la secuencia del cliente
	-- para que sus golpes legítimos siguientes no choquen con ellos.
	local fakeSeq = Combat.State.sequence + 1000
	local function nextFake()
		fakeSeq += 1
		return fakeSeq
	end
	local function rejectedAfter(before, fire)
		fire()
		waitUntil(function()
			return (player:GetAttribute("GolpesRechazados") or 0) > before
		end, 1.5)
		task.wait(0.1)
		return (player:GetAttribute("GolpesRechazados") or 0) - before, tostring(player:GetAttribute("UltimoRechazo"))
	end

	openArea() -- a más de 100 studs del muñeco
	local healthBefore = hA.Health
	-- Inicio legal y hora correcta, pero el muñeco está lejos: lo debe rechazar la geometría
	local seqFar = nextFake()
	local count, reason = rejectedAfter(rejectedBefore, function()
		startRemote:FireServer(seqFar, "Jab", serverNow())
		task.wait(Config.Attacks.Jab.startup + 0.02)
		request:FireServer({ attack = "Jab", seq = seqFar, target = mA, charge = 0, t = serverNow(), pos = ctx.root.Position, look = ctx.root.CFrame.LookVector })
	end)
	record("Rechaza golpes imposibles por distancia", count == 1 and hA.Health == healthBefore and string.find(reason, "alcance", 1, true) ~= nil, "motivo: " .. reason)

	rejectedBefore = player:GetAttribute("GolpesRechazados") or 0
	count, reason = rejectedAfter(rejectedBefore, function()
		request:FireServer({ attack = "Kamehameha", seq = nextFake(), target = mA, charge = 0, t = serverNow() })
	end)
	record("Rechaza ataques inventados", count == 1, "motivo: " .. reason)

	rejectedBefore = player:GetAttribute("GolpesRechazados") or 0
	count, reason = rejectedAfter(rejectedBefore, function()
		request:FireServer({ attack = "Jab", seq = nextFake(), target = mA, charge = 0, t = serverNow() - 3, pos = ctx.root.Position })
	end)
	record("Rechaza golpes con hora manipulada", count == 1 and string.find(reason, "hora", 1, true) ~= nil, "motivo: " .. reason .. " (hora 3 s en el pasado)")

	rejectedBefore = player:GetAttribute("GolpesRechazados") or 0
	count, reason = rejectedAfter(rejectedBefore, function()
		request:FireServer({ attack = "Patada", seq = nextFake(), target = mA, charge = 0, t = serverNow(), pos = ctx.root.Position })
	end)
	record("Rechaza golpes sin inicio de ataque", count == 1 and string.find(reason, "inicio", 1, true) ~= nil, "motivo: " .. reason)

	-- Secuencia ilegal: tras un Jab no puede venir una Patada (se salta el Directo)
	task.wait(0.4)
	rejectedBefore = player:GetAttribute("GolpesRechazados") or 0
	count, reason = rejectedAfter(rejectedBefore, function()
		startRemote:FireServer(nextFake(), "Jab", serverNow())
		task.wait(0.25)
		startRemote:FireServer(nextFake(), "Patada", serverNow())
	end)
	record("Rechaza combos fuera de orden", count == 1 and string.find(reason, "secuencia ilegal", 1, true) ~= nil, "motivo: " .. reason)

	-- Ráfaga: dos inicios más rápido de lo que dura un ataque
	task.wait(0.4)
	rejectedBefore = player:GetAttribute("GolpesRechazados") or 0
	count, reason = rejectedAfter(rejectedBefore, function()
		startRemote:FireServer(nextFake(), "Jab", serverNow())
		startRemote:FireServer(nextFake(), "Jab", serverNow())
	end)
	record("Rechaza ataques más rápidos que posible", count == 1 and string.find(reason, "después del anterior", 1, true) ~= nil, "motivo: " .. reason)
	Combat.State.sequence = fakeSeq + 10
	task.wait(0.4)

	prepare("Muneco1", 3.2)
	c0 = #confirms
	Input.Trigger("Atacar")
	waitUntil(function()
		return #confirms > c0
	end, 1)
	task.wait(0.05)
	rejectedBefore = player:GetAttribute("GolpesRechazados") or 0
	healthBefore = hA.Health
	-- El mismo golpe otra vez, con hora y posición válidas: solo lo frena la regla de repetidos
	local lastConfirmedSeq = Combat.State.sequence
	count, reason = rejectedAfter(rejectedBefore, function()
		request:FireServer({ attack = "Jab", seq = lastConfirmedSeq, target = mA, charge = 0, t = serverNow(), pos = ctx.root.Position, look = ctx.root.CFrame.LookVector })
	end)
	record("Rechaza golpes repetidos", count == 1 and hA.Health == healthBefore, "motivo: " .. reason)

	-- ---------- 10. Poses en el impacto ----------
	-- forward 1 = la extremidad apunta recta al frente; 0,75 ≈ menos de 41° de desvío
	local function poseCheck(name, label)
		local p = poses[name]
		local ok = p ~= nil and p.forward >= 0.75
		record(
			"Pose: " .. label,
			ok,
			if p
				then string.format("apunta %.0f° respecto al frente (%d golpes medidos)", math.deg(math.acos(math.clamp(p.forward, -1, 1))), p.count)
				else "sin medición"
		)
	end
	poseCheck("Jab", "el puño izquierdo llega al frente (Jab)")
	poseCheck("Cross", "el puño derecho llega al frente (Directo)")
	poseCheck("Patada", "la pierna sale al frente (Patada)")
	poseCheck("Fuerte", "el puño derecho llega al frente (Fuerte)")

	-- ---------- 11. Combo a ~30 FPS ----------
	local removeLoad, measureFps = ctx.artificialLoad(0.026)
	local lowFps = measureFps()
	prepare("Muneco2", 3.2)
	c0 = #confirms
	Input.Trigger("Atacar")
	task.wait(0.1)
	Input.Trigger("Atacar")
	task.wait(0.1)
	Input.Trigger("Atacar")
	waitUntil(function()
		return #confirms >= c0 + 3
	end, 2.5)
	removeLoad()
	local lowConfirms = since(confirms, c0)
	record(
		"Combo a baja tasa de cuadros",
		lowFps <= 40 and #lowConfirms == 3 and near(sumDamage(lowConfirms), expectedCombo, 0.01),
		string.format("%d golpes confirmados, %d de daño a %d FPS", #lowConfirms, sumDamage(lowConfirms), lowFps)
	)

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
end
