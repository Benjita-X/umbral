-- Pruebas de la auditoría máxima (commit fd4a899): lo que haría un cliente modificado o desincronizado.
--   1. Golpe fallado según el SERVIDOR: una habilidad no corta la recuperación de un golpe que no contó (y pasada
--      la recuperación, sí sale).
--   2. El rechazo de un golpe llega con su seq y su objetivo (la ✕ y la reconciliación saben QUÉ golpe fue).
--   3. Cargas del Paso en el servidor iguales a las del cliente: 2; una tercera sin pagar no cuenta.
--   4. Gancho validado: fuera de alcance se rechaza; un gancho sin llegar al enemigo no abre el golpe tras el Paso.
--   5. Relanzamiento: respeta la regla de cancelar (espera en cola durante la fase activa y sale después).
--   6. Menú abierto: las acciones de combate no salen.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

return function(ctx)
	local Config, Input, Combat = ctx.CombatConfig, ctx.Input, ctx.Combat
	local record, waitUntil = ctx.record, ctx.waitUntil
	local player = ctx.player
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local controllers = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Controllers")
	local Eco = require(controllers:WaitForChild("EcoController"))
	local function now()
		return Workspace:GetServerTimeNow()
	end
	local function byName(name)
		for _, model in ipairs(CollectionService:GetTagged("Objetivo")) do
			if model.Name == name then
				return model
			end
		end
		return nil
	end
	local OPEN = Vector3.new(0, 4, 150) -- zona abierta, sin enemigos cerca

	if player:GetAttribute("Eco") ~= "Viento" then
		Eco.Equip("Viento")
		task.wait(1)
	end
	ctx.remote:FireServer("resonancia", 0)
	ctx.waitForCharges()
	ctx.teleport(OPEN, Vector3.new(0, 0, 1))
	task.wait(0.5)

	-- ---------- 1. Golpe fallado según el servidor ----------
	local ecoRemote = remotes:WaitForChild("Eco")
	local function whiffThenSkill(offsetFromRecoveryEnd)
		ctx.remote:FireServer("reiniciar_eco")
		task.wait(0.2)
		local count0 = player:GetAttribute("EcosRechazados") or 0
		local last0 = player:GetAttribute("UltimoEco")
		local started = now()
		Input.Trigger("Atacar") -- al aire: golpe fallado
		local a = Combat.State.attack
		local def = a and a.def or Config.Attacks.Jab
		-- Ventana que exige el servidor: desde el fin de la fase activa hasta el fin de la recuperación alargada
		local from = def.startup + def.active + 0.05
		local to = def.startup * Config.Defense.CounterStartupMultiplier + def.active + def.recovery * Config.WhiffRecoveryMultiplier - 0.05
		local fireAt = started + (if offsetFromRecoveryEnd then def.startup + def.active + def.recovery * Config.WhiffRecoveryMultiplier + offsetFromRecoveryEnd else (from + to) / 2)
		while now() < fireAt do
			task.wait()
		end
		local look = ctx.root.CFrame.LookVector
		-- Lo que haría un cliente modificado: pedir la habilidad directamente, sin la regla local
		ecoRemote:FireServer("cuchilla", now(), ctx.root.Position, look, look)
		waitUntil(function()
			return (player:GetAttribute("EcosRechazados") or 0) > count0 or player:GetAttribute("UltimoEco") ~= last0
		end, 1.5)
		local refused = (player:GetAttribute("EcosRechazados") or 0) > count0
		return refused, if refused then player:GetAttribute("EcoRechazado") else player:GetAttribute("UltimoEco"), def
	end
	local refused, why, def = whiffThenSkill(nil)
	record("[Máxima] Una habilidad no corta la recuperación de un golpe fallado (lo exige el servidor)", refused and why == "golpe fallado", string.format("%s · %s", def.label or "?", tostring(why)))
	task.wait(0.5)
	refused, why, def = whiffThenSkill(0.06)
	record("[Máxima] Pasada esa recuperación, la habilidad sí sale", not refused, string.format("%s · %s", def.label or "?", tostring(why)))
	task.wait(0.5)

	-- ---------- 2. El rechazo dice qué golpe y a quién ----------
	local dummy = byName("Muneco1")
	if dummy then
		local got = nil
		local connection = remotes:WaitForChild("GolpeRechazado").OnClientEvent:Connect(function(data)
			got = data
		end)
		local fakeSeq = Combat.State.sequence + 40 -- un ataque que nunca empezó
		remotes:WaitForChild("SolicitudGolpe"):FireServer({ attack = "Jab", seq = fakeSeq, target = dummy, charge = 0, t = now(), pos = ctx.root.Position, look = ctx.root.CFrame.LookVector })
		waitUntil(function()
			return got ~= nil
		end, 1.5)
		connection:Disconnect()
		record("[Máxima] El rechazo de un golpe llega con su seq y su objetivo", got ~= nil and got.seq == fakeSeq and got.target == dummy,
			if got then string.format("seq %s (esperado %d) · objetivo %s · motivo: %s", tostring(got.seq), fakeSeq, tostring(got.target), tostring(got.reason)) else "no llegó ningún rechazo")
	else
		ctx.skip("[Máxima] Rechazo con seq y objetivo", "falta Muneco1")
	end

	-- ---------- 3. Cargas del Paso del servidor ----------
	-- Sin Resonancia, tres avisos de Paso seguidos (un cliente que inventa Pasos): el tercero no cuenta
	task.wait(1.8) -- el servidor recupera sus cargas
	local defenseRemote = remotes:WaitForChild("Defensa")
	local excess0 = player:GetAttribute("PasosExcedidos") or 0
	for _ = 1, 3 do
		defenseRemote:FireServer("paso", now(), Vector3.new(1, 0, 0), ctx.root.Position, ctx.root.CFrame.LookVector)
		task.wait(0.06)
	end
	waitUntil(function()
		return (player:GetAttribute("PasosExcedidos") or 0) > excess0
	end, 1)
	local excess = (player:GetAttribute("PasosExcedidos") or 0) - excess0
	record("[Máxima] El servidor da las mismas 2 cargas de Paso que el cliente (la tercera sin pagar no cuenta)", excess == 1, string.format("avisos rechazados: %d de 3 (esperado 1)", excess))
	task.wait(1.8)

	-- ---------- 4. Gancho validado ----------
	local hookRemote = remotes:WaitForChild("Gancho")
	local grapple = Config.Weapons.Grapple
	local function hookResult(target)
		local c0 = player:GetAttribute("GanchosRechazados") or 0
		local h0 = player:GetAttribute("GanchoHora")
		local t = now()
		hookRemote:FireServer(t, target, ctx.root.Position, ctx.root.CFrame.LookVector)
		waitUntil(function()
			return (player:GetAttribute("GanchosRechazados") or 0) > c0 or player:GetAttribute("GanchoHora") ~= h0
		end, 1)
		if (player:GetAttribute("GanchosRechazados") or 0) > c0 then
			return false, player:GetAttribute("GanchoRechazado")
		end
		return player:GetAttribute("GanchoHora") == t, "aceptado"
	end
	if dummy then
		local root = dummy:WaitForChild("HumanoidRootPart")
		local distance = (root.Position - ctx.root.Position).Magnitude
		if distance > grapple.EnemyRange + 8 then
			local ok, reason = hookResult(dummy)
			record("[Máxima] Un gancho a un enemigo fuera de alcance se rechaza", not ok and string.find(tostring(reason), "fuera de alcance", 1, true) ~= nil, string.format("a %.0f studs · %s", distance, tostring(reason)))
		else
			ctx.skip("[Máxima] Gancho fuera de alcance", string.format("el muñeco está a %.0f studs (cerca)", distance))
		end
		task.wait(0.2) -- (el gancho rechazado no gasta la espera)
		-- Gancho "avisado" a un enemigo a 20 studs, sin llegar: el golpe tras el Paso no se abre
		if (player:GetAttribute("Arma") or "Punos") == "Punos" then
			local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
			local start = root.Position + look * 20
			ctx.waitForCharges()
			ctx.teleport(Vector3.new(start.X, root.Position.Y + 0.5, start.Z), -look)
			task.wait(0.4)
			local accepted, hookWhy = hookResult(dummy)
			local r0 = player:GetAttribute("GolpesRechazados") or 0
			Combat.State.sequence += 1 -- el cliente no lo sabe: se le avanza la cuenta para no desordenar lo que siga
			local seq = Combat.State.sequence
			remotes:WaitForChild("InicioAtaque"):FireServer(seq, "PatadaVoladora", now(), ctx.root.Position, ctx.root.CFrame.LookVector)
			waitUntil(function()
				return (player:GetAttribute("GolpesRechazados") or 0) > r0
			end, 1)
			local reason = player:GetAttribute("UltimoRechazo")
			record("[Máxima] Un gancho sin llegar al enemigo no abre el golpe tras el Paso", accepted and reason == "golpe tras el gancho sin llegar al enemigo", string.format("gancho: %s · inicio: %s", tostring(hookWhy), tostring(reason)))
		else
			ctx.skip("[Máxima] Gancho sin llegar", "no lleva Puños")
		end
	end

	-- ---------- 5. Relanzamiento con la regla de cancelar ----------
	-- Con SUBIR (relanzamiento del Levante) abierto, pulsar C en plena fase activa de un golpe en el suelo no lo
	-- corta: espera en la cola sin gastarse y sale al terminar el golpe
	ctx.waitForCharges()
	ctx.teleport(OPEN, Vector3.new(0, 0, 1))
	task.wait(0.4)
	ctx.settle()
	Eco.State.recast.C = { action = "Ascenso", untilTime = os.clock() + 1.5, label = "SUBIR" }
	Input.Trigger("Atacar")
	waitUntil(function()
		local a = Combat.State.attack
		return a ~= nil and a.phase == "active"
	end, 0.5)
	local active = Combat.State.attack ~= nil and Combat.State.attack.phase == "active"
	Input.Trigger("HabilidadC")
	local keptOpen = Eco.State.recast.C ~= nil
	local queued = Eco.BufferedSlot() == "C"
	waitUntil(function()
		return Eco.State.recast.C == nil
	end, 1.2)
	local usedLater = Eco.State.recast.C == nil
	record("[Máxima] El relanzamiento respeta la fase activa: espera en cola y sale después", active and keptOpen and queued and usedLater,
		string.format("en fase activa %s · no se gastó al pulsar %s · en cola %s · salió después %s", tostring(active), tostring(keptOpen), tostring(queued), tostring(usedLater)))
	Eco.State.recast.C = nil
	task.wait(1.2)
	ctx.settle()

	-- ---------- 6. Menú abierto ----------
	Input.SetBlocked("menu", true)
	Input.Press("Atacar")
	task.wait(0.15)
	local attackedBlocked = Combat.State.mode == "Ataque" or Combat.State.mode == "Carga"
	Input.Release("Atacar")
	Input.SetBlocked("menu", false)
	task.wait(0.1)
	Input.Trigger("Atacar")
	local attackedAfter = Combat.State.mode == "Ataque"
	record("[Máxima] Con el menú abierto, Atacar no sale (y al cerrarlo sí)", not attackedBlocked and attackedAfter, string.format("con menú: %s · sin menú: %s", tostring(attackedBlocked), tostring(attackedAfter)))
	task.wait(0.6)
	ctx.settle()
end
