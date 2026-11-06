-- Suite "habilidad, no machacar" (simulación adversarial de la defensa, perfil técnico).
-- Cuatro jugadores-robot contra el mismo ciclo de ataques (Golpe, Rápido, Pesado, Barrido, Amague, Golpe,
-- con retrasos de hasta 0,3 s):
--   · Lector: reacciona al aviso leyendo FaseFin (el instante real del impacto). Meta: > 90 % defendido.
--   · Machacador: pulsa Defender cada 0,3 s sin mirar. Meta: < 30 %.
--   · Solo guardia: mantiene la guardia siempre. Debe recibir el Barrido y pagar el Pesado (ruptura o golpe).
--   · Reloj fijo: desvía siempre 0,45 s después de que empieza el aviso. Debe fallar contra el Rápido, el
--     Pesado, los retrasos y el amague. Meta: < 50 %.
-- LÍMITE: el Lector conoce el instante exacto (lo lee del servidor). Esto valida que las REGLAS premian leer
-- y castigan machacar; NO demuestra que una persona pueda leer la animación a tiempo. Eso queda pendiente de
-- validación humana (docs/PRUEBAS-FASE3.md).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

return function(ctx)
	local Input = ctx.Input
	local record, waitUntil = ctx.record, ctx.waitUntil
	local player = ctx.player
	local remotes = ReplicatedStorage:WaitForChild("Remotes")

	local npc = nil
	waitUntil(function()
		npc = CollectionService:GetTagged("Sparring")[1]
		return npc ~= nil and npc:GetAttribute("Estado") ~= nil
	end, 10)
	if not npc then
		ctx.skip("[Adversarial] Suite de habilidad", "no apareció el compañero de combate")
		return
	end
	local npcRoot = npc:WaitForChild("HumanoidRootPart")
	local marker = Workspace:WaitForChild("Maps"):WaitForChild("MovementLab"):WaitForChild("Ring"):WaitForChild("PuntoSparring")

	local function serverNow()
		return Workspace:GetServerTimeNow()
	end
	local function at(t)
		while serverNow() < t do
			task.wait()
		end
	end

	local standPosition = nil -- dónde se para el bot (se fija en cada ronda)
	local results = {} -- [attackId] = resultado
	local attacks = {} -- ataques reales (los que llegan a "Atacando"): { id, name }
	local connections = {
		remotes:WaitForChild("ResultadoDefensa").OnClientEvent:Connect(function(data)
			if data.player == player then
				results[data.attackId] = data.result
			end
		end),
		npc:GetAttributeChangedSignal("Estado"):Connect(function()
			local estado = npc:GetAttribute("Estado")
			if estado == "Atacando" then
				table.insert(attacks, { id = npc:GetAttribute("AtaqueId"), name = npc:GetAttribute("Ataque") })
			elseif estado == "Recuperando" then
				ctx.remote:FireServer("curar") -- que ningún bot muera a mitad del ciclo
				-- Volver a su sitio (a 3,5 studs): los empujes lo alejan y el rival empieza a atacar a 12 studs
				-- aunque su golpe solo llega a ~10 (hallazgo de diseño anotado en AUDITORIA-FASE3.md)
				if standPosition then
					ctx.remote:FireServer("teletransporte")
					ctx.root.AssemblyLinearVelocity = Vector3.zero
					ctx.root.CFrame = CFrame.lookAt(standPosition, standPosition + Vector3.new(0, 0, -1))
				end
			end
		end),
	}

	local function reset()
		Input.Release("Defender")
		Input.Release("Atacar")
		ctx.humanoid:Move(Vector3.zero)
		ctx.remote:FireServer("reiniciar_defensa")
		waitUntil(function()
			return (player:GetAttribute("Postura") or 0) == 0 and ctx.Combat.State.mode ~= "Aturdido"
		end, 3)
	end

	-- Corre un bot durante `count` ataques reales y devuelve la lista { name, result }
	local function runBot(label, setup, onWindup, teardown, count)
		reset()
		-- Esperar a que el rival esté quieto para empezar un ciclo limpio desde el principio del patrón
		ctx.remote:FireServer("patron", "")
		ctx.remote:FireServer("perfil", "tecnico")
		ctx.remote:FireServer("retraso", nil)
		waitUntil(function()
			return npc:GetAttribute("Estado") == "Quieto"
		end, 6)
		local position = Vector3.new(marker.Position.X, npcRoot.Position.Y + 0.5, marker.Position.Z + 3.5)
		ctx.teleport(position, Vector3.new(0, 0, -1))
		standPosition = position
		local first = #attacks + 1
		local token = 0
		-- Un aviso nuevo llega por "Estado" (empieza a preparar) o por "FaseInicio" (el amague reinicia sin
		-- cambiar Estado). Se escuchan los dos y se descarta el repetido (mismo FaseInicio).
		local lastStart = nil
		local function onChange()
			local startTime = npc:GetAttribute("FaseInicio")
			if npc:GetAttribute("Estado") ~= "Preparando" or startTime == lastStart then
				return
			end
			lastStart = startTime
			token += 1
			local mine = token
			task.spawn(onWindup, {
				attack = npc:GetAttribute("Ataque"),
				start = startTime,
				finish = npc:GetAttribute("FaseFin"),
				alive = function()
					return token == mine
				end,
			})
		end
		local windupConnections = {
			npc:GetAttributeChangedSignal("FaseInicio"):Connect(onChange),
			npc:GetAttributeChangedSignal("Estado"):Connect(onChange),
		}
		local stop = setup and setup()
		waitUntil(function()
			return #attacks - first + 1 >= count
		end, count * 4 + 6)
		task.wait(0.5) -- que llegue el último resultado
		standPosition = nil
		for _, c in ipairs(windupConnections) do
			c:Disconnect()
		end
		if stop then
			stop()
		end
		if teardown then
			teardown()
		end
		local list = {}
		for i = first, math.min(#attacks, first + count - 1) do
			local a = attacks[i]
			table.insert(list, { name = a.name, result = results[a.id] or "fuera" })
		end
		-- Ponerse otra vez de pie entre bots (fuera del alcance del rival)
		ctx.teleport(Vector3.new(marker.Position.X, npcRoot.Position.Y + 0.5, marker.Position.Z + 30), Vector3.new(0, 0, -1))
		return list
	end

	local function defended(result)
		return result ~= "golpe" and result ~= "ruptura"
	end
	local function rate(list)
		local ok = 0
		for _, item in ipairs(list) do
			if defended(item.result) then
				ok += 1
			end
		end
		return if #list > 0 then ok / #list else 0, ok
	end
	local function summary(list)
		local parts = {}
		for _, item in ipairs(list) do
			table.insert(parts, item.name .. "→" .. item.result)
		end
		return table.concat(parts, ", ")
	end

	local COUNT = 6
	local COUNT_MASH = 10 -- el machacador acierta por azar: más ataques para una medida estable

	-- Lector
	local lector = runBot("Lector", nil, function(w)
		if w.attack == "Barrido" then
			at(w.finish - 0.15)
			if w.alive() then
				ctx.humanoid.Jump = true
			end
		else
			at(w.finish - 0.05)
			if w.alive() and npc:GetAttribute("Estado") == "Preparando" then
				Input.Trigger("Defender")
			end
		end
	end, nil, COUNT)
	local lectorRate = rate(lector)
	record("[Adversarial] Lector defiende más del 90 %", #lector == COUNT and lectorRate > 0.9, string.format("%.0f %% · %s", lectorRate * 100, summary(lector)))

	-- Machacador
	local machacador = runBot("Machacador", function()
		local running = true
		task.spawn(function()
			while running do
				Input.Trigger("Defender")
				task.wait(0.3)
			end
		end)
		return function()
			running = false
		end
	end, function() end, nil, COUNT_MASH)
	local machacadorRate = rate(machacador)
	record("[Adversarial] Machacar Defender rinde menos del 30 %", #machacador == COUNT_MASH and machacadorRate < 0.3, string.format("%.0f %% · %s", machacadorRate * 100, summary(machacador)))

	-- Solo guardia
	local guardia = runBot("Solo guardia", function()
		Input.Press("Defender")
		return function()
			Input.Release("Defender")
		end
	end, function() end, nil, COUNT)
	local sweepHit, heavyPaid = false, false
	for _, item in ipairs(guardia) do
		if item.name == "Barrido" and item.result == "golpe" then
			sweepHit = true
		end
		if item.name == "Fuerte" and (item.result == "golpe" or item.result == "ruptura" or item.result == "guardia") then
			heavyPaid = true
		end
	end
	local hadBreak = false
	for _, item in ipairs(guardia) do
		if item.result == "ruptura" or item.result == "golpe" then
			hadBreak = true
		end
	end
	record("[Adversarial] Solo guardia pierde contra el Barrido y paga el Pesado", #guardia == COUNT and sweepHit and heavyPaid and hadBreak, summary(guardia))

	-- Reloj fijo
	local lastWindup = -math.huge
	local reloj = runBot("Reloj fijo", nil, function(w)
		-- Solo reacciona al PRIMER aviso de cada ataque (no ve el reinicio del amague, que llega 0,3 s después)
		local isRestart = w.start - lastWindup < 0.4
		lastWindup = w.start
		if not isRestart then
			local pressAt = w.start + 0.45
			at(pressAt)
			Input.Trigger("Defender")
		end
	end, nil, COUNT)
	local relojRate = rate(reloj)
	record("[Adversarial] Reloj fijo falla con ritmo variable (< 50 %)", #reloj == COUNT and relojRate < 0.5, string.format("%.0f %% · %s", relojRate * 100, summary(reloj)))

	ctx.remote:FireServer("perfil", "basico")
	ctx.remote:FireServer("retraso", nil)
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
	reset()
end
