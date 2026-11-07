-- Suite de los enemigos comunes (EXPERIMENTAL): Centinela, Latido, Gemelos y Desvío Reflejado.
-- Usa la zona PruebasEnemigos (solo existe en el lugar de pruebas). Cada prueba mide lo que confirma el
-- servidor (daño, notas, vida, resultados de defensa), no lo que predice el cliente.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

return function(ctx)
	local Config, Input, Combat = ctx.CombatConfig, ctx.Input, ctx.Combat
	local record, waitUntil = ctx.record, ctx.waitUntil
	local player = ctx.player
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local types = Config.Sparring.Types

	local function serverNow()
		return Workspace:GetServerTimeNow()
	end
	local function at(t)
		while serverNow() < t do
			task.wait()
		end
	end
	local function enemy(tag, index)
		local list = CollectionService:GetTagged(tag)
		table.sort(list, function(a, b)
			return a:GetPivot().Position.X < b:GetPivot().Position.X
		end)
		return list[index or 1]
	end

	local confirms, results, notices, waves = {}, {}, {}, {}
	local connections = {
		Combat.Confirmed:Connect(function(data)
			table.insert(confirms, data)
		end),
		remotes:WaitForChild("ResultadoDefensa").OnClientEvent:Connect(function(data)
			if data.player == player then
				table.insert(results, data)
			end
		end),
		remotes:WaitForChild("AvisoGrieta").OnClientEvent:Connect(function(data)
			table.insert(notices, data)
		end),
		remotes:WaitForChild("OndaReflejo").OnClientEvent:Connect(function(data)
			table.insert(waves, data)
		end),
	}

	local ready = waitUntil(function()
		return enemy("Centinela") ~= nil and enemy("Latido") ~= nil and enemy("Gemelo", 2) ~= nil
	end, 15)
	if not ready then
		ctx.skip("[Enemigos] Suite de enemigos comunes", "la zona de pruebas de enemigos no apareció")
		for _, c in ipairs(connections) do
			c:Disconnect()
		end
		return
	end

	local function reset()
		Input.Release("Defender")
		ctx.remote:FireServer("reiniciar_defensa")
		ctx.remote:FireServer("resonancia", 0)
		waitUntil(function()
			return Combat.State.mode ~= "Aturdido"
		end, 3)
	end
	-- Ponerse a `distance` studs delante de un enemigo (que mira a +Z), mirándolo
	local function standFront(model, distance)
		local root = model:WaitForChild("HumanoidRootPart")
		ctx.waitForCharges()
		ctx.teleport(Vector3.new(root.Position.X, root.Position.Y + 0.5, root.Position.Z + distance), Vector3.new(0, 0, -1))
		return root
	end
	local function lastConfirmFor(model, since, timeout)
		local found = nil
		waitUntil(function()
			for i = #confirms, since + 1, -1 do
				if confirms[i].target == model then
					found = confirms[i]
					return true
				end
			end
			return false
		end, timeout or 1.5)
		return found
	end

	-- ---------- Centinela: coraza frontal ----------
	reset()
	local centinela = enemy("Centinela")
	local centinelaHumanoid = centinela:FindFirstChildOfClass("Humanoid")
	standFront(centinela, 3.2)
	local c0 = #confirms
	Input.Trigger("Atacar")
	local front = lastConfirmFor(centinela, c0)
	record(
		"[Enemigos] Centinela: de frente la coraza bloquea",
		front ~= nil and front.damage == 0 and type(front.note) == "string" and string.find(front.note, "BLOQUEADO", 1, true) ~= nil,
		if front then string.format("%.1f de daño · nota: %s", front.damage, tostring(front.note)) else "el golpe no se confirmó"
	)

	-- Por la espalda, en la ventana real del juego: durante su RECUPERACIÓN tras atacar (ahí no se gira)
	task.wait(0.5)
	reset()
	local cRoot = centinela:WaitForChild("HumanoidRootPart")
	waitUntil(function()
		return centinela:GetAttribute("Estado") == "Recuperando" and Combat.State.mode ~= "Aturdido"
	end, 8)
	local back = cRoot.Position - cRoot.CFrame.LookVector * 3.2
	ctx.remote:FireServer("teletransporte")
	task.wait(0.06)
	ctx.root.AssemblyLinearVelocity = Vector3.zero
	ctx.root.CFrame = CFrame.lookAt(Vector3.new(back.X, cRoot.Position.Y + 0.5, back.Z), Vector3.new(cRoot.Position.X, cRoot.Position.Y + 0.5, cRoot.Position.Z))
	task.wait()
	c0 = #confirms
	Input.Trigger("Atacar")
	local behind = lastConfirmFor(centinela, c0)
	-- El combo puede seguir (Jab o Directo): se mide el multiplicador sobre el ataque que salió
	local backDef = behind and Config.Attacks[behind.attack] or Config.Attacks.Jab
	local expectedBack = backDef.damage * types.Centinela.backMultiplier
	record(
		"[Enemigos] Centinela: por la espalda hace más daño",
		behind ~= nil and math.abs(behind.damage - expectedBack) < 0.01 and type(behind.note) == "string" and string.find(behind.note, "ESPALDA", 1, true) ~= nil,
		if behind then string.format("%.1f de daño (objetivo %.1f) · nota: %s", behind.damage, expectedBack, tostring(behind.note)) else "el golpe no se confirmó"
	)
	local _ = centinelaHumanoid

	-- ---------- Gemelos: vida compartida ----------
	task.wait(0.5)
	reset()
	local gemeloA, gemeloB = enemy("Gemelo", 1), enemy("Gemelo", 2)
	local hA, hB = gemeloA:FindFirstChildOfClass("Humanoid"), gemeloB:FindFirstChildOfClass("Humanoid")
	ctx.remote:FireServer("vida_enemigo", { tag = "Gemelo", value = types.Gemelo.maxHealth })
	waitUntil(function()
		return hA.Health == types.Gemelo.maxHealth and hB.Health == types.Gemelo.maxHealth
	end, 1)
	standFront(gemeloA, 3.2)
	c0 = #confirms
	Input.Trigger("Atacar")
	local twinHit = lastConfirmFor(gemeloA, c0)
	waitUntil(function()
		return hB.Health < types.Gemelo.maxHealth
	end, 1)
	record(
		"[Enemigos] Gemelos: comparten una sola vida",
		twinHit ~= nil and twinHit.damage > 0 and math.abs(hA.Health - hB.Health) < 0.01 and hB.Health < types.Gemelo.maxHealth,
		string.format("golpe a uno: A %.1f · B %.1f (de %d)", hA.Health, hB.Health, types.Gemelo.maxHealth)
	)

	-- ---------- Desvío Reflejado: desviar perfecto a un Gemelo daña al otro ----------
	reset()
	ctx.remote:FireServer("vida_enemigo", { tag = "Gemelo", value = types.Gemelo.maxHealth })
	task.wait(0.3)
	standFront(gemeloA, 3.2)
	local reflectedOk, waveSeen, healthDrop = false, false, 0
	for _ = 1, 4 do
		-- Esperar un ataque desviable del Gemelo A (Golpe o Rápido)
		local finish = nil
		waitUntil(function()
			local name = gemeloA:GetAttribute("Ataque")
			if gemeloA:GetAttribute("Estado") == "Preparando" and (name == "Golpe" or name == "Rapido") then
				local f = gemeloA:GetAttribute("FaseFin")
				if f - serverNow() > 0.12 then
					finish = f
					return true
				end
			end
			return false
		end, 6)
		if not finish then
			break
		end
		local before = hA.Health
		local w0, r0 = #waves, #results
		at(finish - 0.05)
		Input.Trigger("Defender")
		waitUntil(function()
			return #results > r0
		end, 1.5)
		local r = results[#results]
		if r and r.result == "desvio_perfecto" then
			waitUntil(function()
				return #waves > w0
			end, 0.5)
			task.wait(0.1)
			waveSeen = #waves > w0 and (waves[#waves].reflected or 0) >= 1
			healthDrop = before - hA.Health
			reflectedOk = waveSeen and healthDrop > 0
			break
		end
		task.wait(0.3)
	end
	record(
		"[Enemigos] Desvío Reflejado daña al enemigo cercano",
		reflectedOk,
		string.format("onda con objetivos: %s · la vida compartida bajó %.1f", tostring(waveSeen), healthDrop)
	)

	-- ---------- Latido: Contratiempo tras 3 desvíos perfectos ----------
	reset()
	local latido = enemy("Latido")
	local latidoHumanoid = latido:FindFirstChildOfClass("Humanoid")
	ctx.remote:FireServer("vida_enemigo", { tag = "Latido", value = types.Latido.maxHealth })
	standFront(latido, 3.2)
	local n0 = #notices
	local perfects = 0
	local lastId = nil
	local deadline = os.clock() + 20
	while perfects < types.Latido.rhythmStreak and os.clock() < deadline do
		local finish, id = nil, nil
		waitUntil(function()
			if latido:GetAttribute("Estado") == "Preparando" and latido:GetAttribute("AtaqueId") ~= lastId then
				local f = latido:GetAttribute("FaseFin")
				if f - serverNow() > 0.12 then
					finish, id = f, latido:GetAttribute("AtaqueId")
					return true
				end
			end
			return false
		end, 5)
		if not finish then
			break
		end
		lastId = id
		local r0 = #results
		at(finish - 0.05)
		Input.Trigger("Defender")
		waitUntil(function()
			return #results > r0
		end, 1.5)
		local r = results[#results]
		if r and r.result == "desvio_perfecto" then
			perfects += 1
		else
			perfects = 0
		end
	end
	local gotNotice = waitUntil(function()
		for i = n0 + 1, #notices do
			if string.find(tostring(notices[i].title), "CONTRATIEMPO", 1, true) then
				return true
			end
		end
		return false
	end, 1)
	local stunLength = (latido:GetAttribute("FaseFin") or 0) - (latido:GetAttribute("FaseInicio") or 0)
	record(
		"[Enemigos] Latido: 3 desvíos perfectos = Contratiempo",
		perfects >= types.Latido.rhythmStreak and gotNotice and latido:GetAttribute("Estado") == "Aturdido" and stunLength >= types.Latido.rhythmStun - 0.05,
		string.format("%d perfectos seguidos · aviso %s · aturdido %.2f s (objetivo %.1f)", perfects, tostring(gotNotice), stunLength, types.Latido.rhythmStun)
	)

	-- ---------- Vencer a un enemigo común da Resonancia ----------
	reset()
	ctx.remote:FireServer("vida_enemigo", { tag = "Latido", value = 2 })
	waitUntil(function()
		return latidoHumanoid.Health <= 2
	end, 1)
	standFront(latido, 3.2)
	local res0 = player:GetAttribute("Resonancia") or 0
	c0 = #confirms
	Input.Trigger("Atacar")
	lastConfirmFor(latido, c0)
	waitUntil(function()
		return (player:GetAttribute("Resonancia") or 0) - res0 >= Config.Resonance.Gains.VencerComun
	end, 1.5)
	local gained = (player:GetAttribute("Resonancia") or 0) - res0
	record(
		"[Enemigos] Vencer a un enemigo común da Resonancia",
		latidoHumanoid.Health <= 0 and gained >= Config.Resonance.Gains.VencerComun and latido:GetAttribute("Estado") == "Aturdido",
		string.format("vida %.0f · +%d Resonancia (al menos %d) · estado %s", latidoHumanoid.Health, gained, Config.Resonance.Gains.VencerComun, tostring(latido:GetAttribute("Estado")))
	)

	-- ---------- Acechador: Golpe de Oportunidad tras un golpe pesado fallado ----------
	reset()
	local acechador = enemy("Acechador")
	local punished, attempts = false, 0
	if acechador then
		local aRoot = acechador:WaitForChild("HumanoidRootPart")
		for attempt = 1, 3 do
			attempts = attempt
			ctx.waitForCharges()
			-- A 9 studs y DE ESPALDAS: el golpe fuerte sale al aire (sin rival en el cono, no se acerca)
			ctx.teleport(Vector3.new(aRoot.Position.X, aRoot.Position.Y + 0.5, aRoot.Position.Z + 9), Vector3.new(0, 0, 1))
			waitUntil(function()
				return acechador:GetAttribute("Estado") == "Quieto"
			end, 4)
			Input.Press("Atacar")
			task.wait(Config.HoldThreshold + 0.15)
			Input.Release("Atacar")
			punished = waitUntil(function()
				return acechador:GetAttribute("Ataque") == "Embestida"
			end, 1.5)
			if punished then
				break
			end
			task.wait(types.Acechador.opportunityCooldown + 0.2)
		end
	end
	record(
		"[Enemigos] Acechador castiga un golpe fuerte fallado",
		punished,
		if acechador then string.format("Embestida tras fallar: %s (intentos %d)", tostring(punished), attempts) else "no apareció el Acechador"
	)
	task.wait(1.5)

	-- ---------- Aguante: ni cinco enemigos pueden encadenarte aturdimientos para siempre ----------
	task.wait(Config.Defense.StunChainWindow + Config.Defense.AguanteTime + 0.2)
	player:SetAttribute("PruebaCadena", nil)
	ctx.remote:FireServer("cadena_aturdimiento", Config.Defense.HitStun)
	waitUntil(function()
		return player:GetAttribute("PruebaCadena") ~= nil
	end, 2)
	local chain = {}
	for value in string.gmatch(tostring(player:GetAttribute("PruebaCadena")), "[^,]+") do
		table.insert(chain, tonumber(value))
	end
	local d = Config.Defense
	local expected = { d.HitStun, d.HitStun * d.StunChainFactor, d.HitStun * d.StunChainFactor ^ 2, 0 }
	local chainOk = #chain == 4
	for i = 1, 4 do
		chainOk = chainOk and chain[i] ~= nil and math.abs(chain[i] - expected[i]) < 0.002
	end
	record(
		"[Enemigos] Aguante: cada aturdimiento seguido dura menos y el cuarto no entra",
		chainOk,
		string.format("duraciones %s (objetivo %.3f, %.3f, %.3f, 0)", tostring(player:GetAttribute("PruebaCadena")), expected[1], expected[2], expected[3])
	)
	task.wait(d.AguanteTime + 0.5)

	-- Volver a dejar todo como estaba
	ctx.remote:FireServer("vida_enemigo", { tag = "Latido", value = types.Latido.maxHealth })
	ctx.remote:FireServer("vida_enemigo", { tag = "Gemelo", value = types.Gemelo.maxHealth })
	reset()
	ctx.teleport(Vector3.new(0, 4, 150), Vector3.new(0, 0, 1))
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
end
