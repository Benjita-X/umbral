-- Libertad de movimiento y ataque (la dirección del golpe NO es la del movimiento; acercarse es una decisión):
--   1. Golpe sin moverse: solo el paso propio del golpe, igual con o sin rival (no te acerca al rival).
--   2. Adelante + golpe: ahí sí te acerca y conecta.
--   3. Retroceder golpeando: los golpes siguen saliendo hacia delante y el cuerpo no se gira.
--   4. Paso lateral junto a un rival: se conserva la orientación y el golpe siguiente sale igual.
--   5. Con R (fijado) y sin él: ningún acercamiento automático; con R + adelante, sí.
--   6. Contraataque: alcance corto, no persigue a un rival lejano; de cerca, acerca poco.
--   7. Rutas del combo: a ritmo, con pausa, mantenido, tras el Paso y retrocediendo (no cambia la ruta).
--   8. Lo mismo con ~30 FPS y con latencia simulada (el servidor contesta tarde): el golpe no persigue.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

return function(ctx)
	local Input, Combat, Movement = ctx.Input, ctx.Combat, ctx.Movement
	local record, waitUntil = ctx.record, ctx.waitUntil
	local controllers = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Controllers")
	local Fijar = require(controllers:WaitForChild("FijarObjetivoController"))
	local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("CombatConfig"))
	local STEP = Config.LungeWithoutTarget
	local OPEN = Vector3.new(0, 4, 150)

	local function flat(v)
		return Vector3.new(v.X, 0, v.Z)
	end
	local function byName(name)
		for _, model in ipairs(CollectionService:GetTagged("Objetivo")) do
			if model.Name == name then
				return model
			end
		end
		return nil
	end

	local started, hits = {}, {}
	local connections = {
		Combat.AttackStarted:Connect(function(name, _, counter)
			local look = flat(ctx.root.CFrame.LookVector).Unit
			table.insert(started, { name = name, counter = counter, look = look, pos = ctx.root.Position, t = os.clock() })
		end),
		Combat.Hit:Connect(function(name, model)
			if model.Name == "Muneco1" then -- (con la asistencia, otro muñeco cercano puede ser el orientado)
				table.insert(hits, { name = name, model = model })
			end
		end),
	}
	local function names(from)
		local list = {}
		for i = from + 1, #started do
			table.insert(list, started[i].name)
		end
		return table.concat(list, ", ")
	end
	local function idle()
		return waitUntil(function()
			return Combat.State.mode == "Libre"
		end, 2)
	end
	local function comboReset()
		idle()
		task.wait(Config.ComboResetTime + 0.25)
	end

	local dummy = byName("Muneco1")
	if not dummy then
		ctx.skip("[Libertad] todas", "falta Muneco1")
		return
	end
	local dummyRoot = dummy:WaitForChild("HumanoidRootPart")
	local dummyHumanoid = dummy:FindFirstChildOfClass("Humanoid")
	local maps = workspace:FindFirstChild("Maps")
	local lab = maps and maps:FindFirstChild("MovementLab")
	local dojo = lab and lab:FindFirstChild("Dojo")
	local marker = dojo and dojo:FindFirstChild("PuntoMuneco1")

	-- Te deja a `distance` studs del muñeco (en +Z de él), mirándolo; `angle` gira la mirada
	local function place(distance, angle)
		ctx.humanoid:Move(Vector3.zero)
		Fijar.LockOn(nil)
		-- El muñeco vuelve andando a su marca tras un remate: se espera a que esté en ella, quieto y con vida
		waitUntil(function()
			return (not marker or flat(dummyRoot.Position - marker.Position).Magnitude < 2.5)
				and dummyRoot.AssemblyLinearVelocity.Magnitude < 1
				and (not dummyHumanoid or dummyHumanoid.Health >= math.min(60, dummyHumanoid.MaxHealth))
		end, 9)
		task.wait(0.2)
		ctx.waitForCharges()
		local look = Vector3.new(0, 0, -1)
		if angle then
			look = CFrame.Angles(0, math.rad(angle), 0):VectorToWorldSpace(look)
		end
		ctx.teleport(Vector3.new(dummyRoot.Position.X, dummyRoot.Position.Y + 0.5, dummyRoot.Position.Z + distance), look)
		task.wait(0.3)
		ctx.settle()
		comboReset()
	end
	local function toward()
		return flat(dummyRoot.Position - ctx.root.Position).Unit
	end
	-- Avance hacia el muñeco durante un golpe (desde que sale hasta que termina)
	local function attackAdvance(setup)
		local dir = toward()
		local start = ctx.root.Position
		local h0 = #hits
		if setup then
			setup()
		end
		Input.Trigger("Atacar")
		task.wait(0.05)
		idle()
		return flat(ctx.root.Position - start):Dot(dir), #hits > h0
	end
	local defaultLevel = Combat.AimAssist()

	-- ---------- 1. Golpe sin moverse ----------
	for _, level in ipairs({ "Completa", "Ligera", "Manual" }) do
		Combat.SetAimAssist(level)
		place(7.5)
		local advance, hit = attackAdvance()
		record(string.format("[Libertad] Golpe sin moverse no acerca al rival (%s)", level), advance <= STEP + 0.45 and not hit,
			string.format("a 7,5 studs avanzó %.2f (paso propio %.1f) · conectó %s", advance, STEP, tostring(hit)))
	end
	Combat.SetAimAssist("Ligera")
	ctx.waitForCharges()
	ctx.teleport(OPEN, Vector3.new(0, 0, 1))
	task.wait(0.3)
	ctx.settle()
	comboReset()
	local openStart = ctx.root.Position
	Input.Trigger("Atacar")
	task.wait(0.05)
	idle()
	local openAdvance = flat(ctx.root.Position - openStart):Dot(Vector3.new(0, 0, 1))
	record("[Libertad] El golpe al aire tiene el mismo paso propio (no se siente estático)", openAdvance >= STEP * 0.5 and openAdvance <= STEP + 0.45,
		string.format("avanzó %.2f sin rival (paso propio %.1f)", openAdvance, STEP))

	-- ---------- 2. Adelante + golpe ----------
	place(6)
	local fwdAdvance, fwdHit = attackAdvance(function()
		ctx.humanoid:Move(toward())
		task.wait(0.05)
	end)
	ctx.humanoid:Move(Vector3.zero)
	record("[Libertad] Adelante + golpe sí te acerca y conecta", fwdAdvance >= 2 and fwdHit,
		string.format("a 6 studs avanzó %.2f · conectó %s", fwdAdvance, tostring(fwdHit)))

	-- ---------- 3. Retroceder golpeando hacia delante ----------
	place(3.2)
	local s0 = #started
	local forwardLook = toward()
	Input.Trigger("Atacar")
	task.wait(0.1)
	ctx.humanoid:Move(-forwardLook) -- atrás
	task.wait(0.15)
	Input.Trigger("Atacar")
	task.wait(0.3)
	Input.Trigger("Atacar")
	task.wait(0.1)
	idle()
	task.wait(0.25) -- sigue retrocediendo un instante después del combo
	local stillFacing = flat(ctx.root.CFrame.LookVector).Unit:Dot(forwardLook)
	ctx.humanoid:Move(Vector3.zero)
	local worst = 1
	for i = s0 + 1, #started do
		worst = math.min(worst, started[i].look:Dot(forwardLook))
	end
	record("[Libertad] Retroceder mientras atacas: cada golpe sale hacia delante y no te giras",
		#started - s0 >= 3 and worst > 0.9 and stillFacing > 0.85,
		string.format("golpes %s · peor orientación %.2f · mirada tras el combo %.2f", names(s0), worst, stillFacing))

	-- ---------- 4. Paso lateral y seguir atacando ----------
	place(5)
	local before = flat(ctx.root.CFrame.LookVector).Unit
	local side = before:Cross(Vector3.yAxis).Unit
	ctx.humanoid:Move(side)
	task.wait()
	Input.Trigger("Paso")
	task.wait(0.3)
	local s1 = #started
	Input.Trigger("Atacar") -- sigue pulsando el lado
	task.wait(0.08)
	local after = started[s1 + 1]
	task.wait(0.25)
	ctx.humanoid:Move(Vector3.zero)
	idle()
	record("[Libertad] Tras un Paso lateral junto al rival, el golpe sale con la misma orientación",
		after ~= nil and after.look:Dot(before) > 0.9,
		string.format("orientación del golpe respecto a la previa %s", if after then string.format("%.2f", after.look:Dot(before)) else "sin golpe"))

	-- ---------- 5. Fijado (R) sin acercamiento automático ----------
	for _, level in ipairs({ "Ligera", "Completa" }) do
		Combat.SetAimAssist(level)
		place(7.5, 30)
		local locked = Fijar.LockOn(dummy)
		task.wait(0.2)
		local advance, hit = attackAdvance()
		local faced = started[#started] and started[#started].look:Dot(toward()) or 0
		record(string.format("[Libertad] Con R fijado y sin moverte, el golpe te orienta pero no te acerca (%s)", level),
			locked and advance <= STEP + 0.45 and not hit and faced > 0.95,
			string.format("fijado %s · avanzó %.2f · conectó %s · mira al fijado %.2f", tostring(locked), advance, tostring(hit), faced))
	end
	place(6)
	Fijar.LockOn(dummy)
	task.wait(0.2)
	local lockAdvance, lockHit = attackAdvance(function()
		ctx.humanoid:Move(toward())
		task.wait(0.05)
	end)
	ctx.humanoid:Move(Vector3.zero)
	Fijar.LockOn(nil)
	record("[Libertad] Con R fijado + adelante, el golpe sí te acerca", lockAdvance >= 2 and lockHit,
		string.format("avanzó %.2f · conectó %s", lockAdvance, tostring(lockHit)))

	-- ---------- 6. Contraataque sin persecución ----------
	Combat.SetAimAssist("Completa")
	place(10)
	local s2 = #started
	local counterFar, counterFarHit = attackAdvance(function()
		Combat.State.counterUntil = os.clock() + 1
	end)
	local wasCounter = started[s2 + 1] and started[s2 + 1].counter
	record("[Libertad] El contraataque no persigue a un rival lejano (10 studs)",
		wasCounter and counterFar <= STEP + 0.45 and not counterFarHit,
		string.format("contraataque %s · avanzó %.2f · conectó %s", tostring(wasCounter), counterFar, tostring(counterFarHit)))
	place(5.5)
	local counterNear = attackAdvance(function()
		Combat.State.counterUntil = os.clock() + 1
	end)
	record("[Libertad] De cerca, el contraataque acerca poco (sin teletransporte)",
		counterNear <= Config.Defense.CounterMaxLunge + 0.5 and counterNear >= 0.8,
		string.format("a 5,5 studs avanzó %.2f (máximo %.1f)", counterNear, Config.Defense.CounterMaxLunge))
	Combat.SetAimAssist("Manual")
	place(4.5, 35)
	local s3 = #started
	attackAdvance(function()
		Combat.State.counterUntil = os.clock() + 1
	end)
	local manualCounter = started[s3 + 1]
	local manualDot = if manualCounter then manualCounter.look:Dot(toward()) else 1
	record("[Libertad] En Manual el contraataque no se autoapunta", manualCounter ~= nil and manualDot < 0.93,
		string.format("rival a 35°: mira %.2f", manualDot))
	Combat.SetAimAssist("Ligera")

	-- ---------- 7. Rutas del combo ----------
	local weapon = Config.Weapons[Players.LocalPlayer:GetAttribute("Arma") or "Punos"] or Config.Weapons.Punos
	local chain = weapon.chain
	place(3.2)
	local r0 = #started
	for _ = 1, 3 do
		Input.Trigger("Atacar")
		task.wait(0.22)
	end
	idle()
	record("[Libertad] Ruta a ritmo: la cadena completa", names(r0) == table.concat(chain, ", "), "golpes: " .. names(r0))

	place(3.2)
	local r1 = #started
	local hp = #hits
	Input.Trigger("Atacar")
	task.wait(0.05)
	idle()
	local firstHit = #hits > hp
	task.wait((Config.ChainPause.min + Config.ChainPause.max) / 2)
	local pauseIdle = os.clock() - Combat.State.lastAttackEnd
	local chainHit = Combat.State.chainHit
	Input.Trigger("Atacar")
	task.wait(0.05)
	idle()
	record("[Libertad] Ruta con pausa: primer golpe · pausa · remate", names(r1) == chain[1] .. ", " .. chain[#chain],
		string.format("golpes: %s · el primero conectó %s (marca %s) · pausa %.2f s", names(r1), tostring(firstHit), tostring(chainHit), pauseIdle))

	place(3.2)
	local r2 = #started
	Input.Trigger("Atacar")
	task.wait(0.05)
	idle()
	task.wait(Config.ChainPause.max + 0.3)
	Input.Trigger("Atacar")
	task.wait(0.05)
	idle()
	record("[Libertad] Esperar de más reinicia la cadena (no salta al remate)", names(r2) == chain[1] .. ", " .. chain[1], "golpes: " .. names(r2))

	place(3.2)
	local r3 = #started
	Input.Press("Atacar") -- la pulsación es el primer golpe; mantenerla pide el fuerte
	task.wait(Config.HoldThreshold + 0.35)
	Input.Release("Atacar")
	task.wait(0.1)
	idle()
	record("[Libertad] Ruta mantenida: golpe · mantener → fuerte", names(r3) == chain[1] .. ", " .. weapon.heavy, "golpes: " .. names(r3))

	place(6)
	local r4 = #started
	ctx.humanoid:Move(toward())
	task.wait()
	Input.Trigger("Paso")
	task.wait(0.12)
	ctx.humanoid:Move(Vector3.zero)
	Input.Trigger("Atacar")
	task.wait(0.05)
	idle()
	record("[Libertad] Ruta tras el Paso: golpe especial", names(r4) == weapon.dash, "golpes: " .. names(r4))

	place(3.2)
	local r5 = #started
	Input.Trigger("Atacar")
	task.wait(0.1)
	ctx.humanoid:Move(toward() * -1)
	task.wait(0.1)
	Input.Trigger("Atacar")
	task.wait(0.1)
	ctx.humanoid:Move(Vector3.zero)
	idle()
	record("[Libertad] Retroceder no cambia la ruta (sigue la cadena hacia delante)", names(r5) == chain[1] .. ", " .. chain[2], "golpes: " .. names(r5))

	-- ---------- 8. FPS bajos y latencia simulada ----------
	local stopLoad, measure = ctx.artificialLoad(0.03)
	local fps = measure()
	place(7.5)
	local lowAdvance, lowHit = attackAdvance()
	place(5.5)
	local lowFwd = attackAdvance(function()
		ctx.humanoid:Move(toward())
		task.wait(0.05)
	end)
	ctx.humanoid:Move(Vector3.zero)
	stopLoad()
	record("[Libertad] Con FPS bajos: sin acercamiento automático y adelante sigue acercando",
		lowAdvance <= STEP + 0.6 and not lowHit and lowFwd >= 1.5,
		string.format("%d FPS · quieto avanzó %.2f · adelante avanzó %.2f", fps, lowAdvance, lowFwd))

	-- Latencia: la replicación llega tarde (NetworkSettings.IncomingReplicationLag, si este nivel lo permite); el
	-- golpe local no depende de la red, así que no debe perseguir ni girarse mientras espera al servidor
	local lagApplied = pcall(function()
		settings().Network.IncomingReplicationLag = 0.25
	end)
	task.wait(0.2)
	place(7.5)
	local lagAdvance, lagHit = attackAdvance()
	place(3.2)
	ctx.root.CFrame = CFrame.lookAt(ctx.root.Position, ctx.root.Position + Vector3.new(0, 0, -1))
	local l0 = #started
	Input.Trigger("Atacar")
	task.wait(0.1)
	ctx.humanoid:Move(toward() * -1)
	Input.Trigger("Atacar")
	task.wait(0.1)
	ctx.humanoid:Move(Vector3.zero)
	idle()
	local lagWorst = 1
	for i = l0 + 1, #started do
		lagWorst = math.min(lagWorst, started[i].look:Dot(Vector3.new(0, 0, -1)))
	end
	if lagApplied then
		pcall(function()
			settings().Network.IncomingReplicationLag = 0
		end)
	end
	record("[Libertad] Con latencia: sin acercamiento automático y retroceder sigue golpeando hacia delante",
		-- (con retraso, el muñeco puede verse aún recolocándose: aquí cuenta el avance, no si conectó)
		lagAdvance <= STEP + 0.45 and #started - l0 >= 2 and lagWorst > 0.9,
		string.format("retraso simulado %s · ping %d ms · quieto avanzó %.2f · conectó %s · golpes %s · peor orientación %.2f",
			if lagApplied then "0,25 s" else "no disponible (ping real)", math.floor(Players.LocalPlayer:GetNetworkPing() * 1000 + 0.5), lagAdvance, tostring(lagHit), names(l0), lagWorst))

	Combat.SetAimAssist(defaultLevel)
	Fijar.LockOn(nil)
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
end
