-- Servidor de pruebas (solo en build/UMBRAL-Pruebas.rbxlx).
-- Atiende al cliente de pruebas (reaparecer) y cierra la sesión de Studio con los resultados.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	return
end

local remote = Instance.new("RemoteEvent")
remote.Name = "UmbralPruebas"
remote.Parent = ReplicatedStorage

local finished = false
local function endTest(value)
	if finished then
		return
	end
	finished = true
	local ok, err = pcall(function()
		game:GetService("StudioTestService"):EndTest(value)
	end)
	if not ok then
		warn("[UMBRAL-PRUEBAS] No se pudo cerrar la sesión: " .. tostring(err))
	end
end

remote.OnServerEvent:Connect(function(player, action, payload, extra)
	if action == "teletransporte" then
		-- Las pruebas mueven al personaje de golpe: se avisa al historial de posiciones para que no lo
		-- marque como movimiento imposible. SOLO existe en el lugar de pruebas (este script no se
		-- incluye en build/UMBRAL-Desarrollo.rbxlx ni en ninguna versión publicable).
		local services = game:GetService("ServerScriptService"):FindFirstChild("Services")
		local module = services and services:FindFirstChild("PositionService")
		if module then
			require(module).AllowTeleport(player, 1, payload)
		end
	elseif action == "perfil" then
		for _, model in ipairs(game:GetService("CollectionService"):GetTagged("Companero")) do
			model:SetAttribute("Perfil", payload)
		end
	elseif action == "retraso" then
		for _, model in ipairs(game:GetService("CollectionService"):GetTagged("Companero")) do
			model:SetAttribute("Retraso", payload)
		end
	elseif action == "vida_enemigo" then
		-- Fija la vida de los enemigos con una etiqueta (p. ej. dejar uno a punto de caer)
		for _, model in ipairs(game:GetService("CollectionService"):GetTagged(payload.tag)) do
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Health = payload.value
			end
		end
	elseif action == "cadena_aturdimiento" then
		-- Aplica 4 aturdimientos seguidos y devuelve las duraciones reales (prueba del Aguante)
		local services = game:GetService("ServerScriptService"):FindFirstChild("Services")
		local DefenseService = require(services:WaitForChild("DefenseService"))
		local durations = {}
		for _ = 1, 4 do
			table.insert(durations, string.format("%.3f", DefenseService.Stun(player, payload or 0.35)))
			task.wait(0.05)
		end
		player:SetAttribute("PruebaCadena", table.concat(durations, ","))
	elseif action == "consulta_defensa" then
		-- Consulta el estado real de defensa del jugador (pruebas de los hallazgos #3 y #4 de Codex)
		local services = game:GetService("ServerScriptService"):FindFirstChild("Services")
		local DefenseService = require(services:WaitForChild("DefenseService"))
		-- `extra`: la hora (del cliente) a la que se consulta; con latencia, la de llegada sería tarde
		local now = if type(extra) == "number" then extra else workspace:GetServerTimeNow()
		if payload == "desvio_doble" then
			local first, press = DefenseService.FindDeflect(player, now + 0.03)
			DefenseService.Consume(press)
			local second = DefenseService.FindDeflect(player, now + 0.04)
			player:SetAttribute("PruebaDefensa", string.format("%s,%s", tostring(first), tostring(second)))
		elseif payload == "guardia" then
			player:SetAttribute("PruebaDefensa", tostring(DefenseService.IsGuarding(player, now)))
		end
	elseif action == "vida_jugador" then
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = payload
		end
	elseif action == "mover_muneco" then
		-- Coloca un muñeco en un punto (prueba de la pared); vuelve solo a su sitio al quedarse quieto
		for _, model in ipairs(game:GetService("CollectionService"):GetTagged("Objetivo")) do
			if model.Name == payload and typeof(extra) == "Vector3" then
				model:PivotTo(CFrame.new(extra))
				-- Un rasguño mínimo: cuenta como golpe reciente y no vuelve a su sitio enseguida
				local humanoid = model:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid.Health -= 0.01
				end
			end
		end
	elseif action == "aturdir_jugador" then
		-- Aturde al jugador como un golpe enemigo de verdad (servidor + aviso al cliente por ResultadoDefensa)
		local services = game:GetService("ServerScriptService"):FindFirstChild("Services")
		local DefenseService = require(services:WaitForChild("DefenseService"))
		DefenseService.ClearStunChain(player)
		local applied = DefenseService.Stun(player, payload or 2)
		local result = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):FindFirstChild("ResultadoDefensa")
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if result and root then
			result:FireAllClients({ player = player, result = "golpe", damage = 0, stun = applied, from = root.Position + root.CFrame.LookVector * 4 })
		end
	elseif action == "concurrencia" then
		-- Muchos golpes A LA VEZ y de tipos distintos sobre el mismo muñeco (como varios jugadores lanzando juntos):
		-- después no debe quedar ninguna fuerza activa ni el muñeco trabado o disparado
		local services = game:GetService("ServerScriptService"):FindFirstChild("Services")
		local DamageService = require(services:WaitForChild("DamageService"))
		local target = nil
		for _, model in ipairs(game:GetService("CollectionService"):GetTagged("Objetivo")) do
			if model.Name == payload then
				target = model
			end
		end
		local root = target and target:FindFirstChild("HumanoidRootPart")
		if not root then
			player:SetAttribute("PruebaConcurrencia", "sin muñeco")
			return
		end
		player:SetAttribute("PruebaConcurrencia", nil)
		task.spawn(function()
			local specs = {
				{ attackName = "EcoPrueba", damage = 1, dragTo = root.Position + Vector3.new(4, 0, 0), dragTime = 0.18, stun = 0.3 },
				{ attackName = "EcoPrueba", damage = 1, direction = Vector3.new(0, 0, 1), knockback = 40, knockUp = 30, launch = true, stun = 0.4, juggle = 1 },
				{ attackName = "EcoPrueba", damage = 1, direction = Vector3.new(1, 0, 0), knockback = 8, suspend = 0.5, stun = 0.3 },
				{ attackName = "EcoPrueba", damage = 1, direction = Vector3.new(-1, 0, 0), knockback = 75, knockUp = 10, stun = 0.5 },
			}
			for _ = 1, 25 do
				for _, spec in ipairs(specs) do
					local copy = table.clone(spec)
					task.spawn(DamageService.ApplyExternalHit, player, target, copy)
				end
				task.wait(0.03)
			end
			task.wait(2)
			local problems = {}
			for _, child in ipairs(root:GetChildren()) do
				if child:IsA("LinearVelocity") and child.Enabled then
					table.insert(problems, child.Name .. " activa")
				end
			end
			local p = root.Position
			if p ~= p or math.abs(p.X) > 1e5 or math.abs(p.Y) > 1e5 then
				table.insert(problems, "posición inválida")
			end
			if root.AssemblyLinearVelocity.Magnitude > 8 then
				table.insert(problems, string.format("velocidad %.1f", root.AssemblyLinearVelocity.Magnitude))
			end
			player:SetAttribute("PruebaConcurrencia", if #problems == 0 then "ok" else table.concat(problems, ", "))
		end)
	elseif action == "malabar_largo" then
		-- Mantiene a un muñeco "en malabar" más de lo permitido (prueba del tope de malabar)
		local services = game:GetService("ServerScriptService"):FindFirstChild("Services")
		local DamageService = require(services:WaitForChild("DamageService"))
		for _, model in ipairs(game:GetService("CollectionService"):GetTagged("Objetivo")) do
			if model.Name == payload then
				task.spawn(function()
					for _ = 1, 12 do
						DamageService.MarkJuggle(model, 1)
						task.wait(0.45)
					end
				end)
			end
		end
	elseif action == "curar" then
		-- Solo la vida (las pruebas de habilidad necesitan conservar postura y aturdimiento)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = humanoid.MaxHealth
		end
	elseif action == "reaparecer" then
		player:LoadCharacterAsync()
	elseif action == "patron" then
		-- Fija el patrón de ataques del compañero de combate (p. ej. "Golpe" o "Barrido")
		for _, model in ipairs(game:GetService("CollectionService"):GetTagged("Companero")) do
			model:SetAttribute("Patron", payload)
		end
	elseif action == "resonancia" then
		player:SetAttribute("Resonancia", payload)
	elseif action == "reiniciar_defensa" then
		player:SetAttribute("Postura", 0)
		player:SetAttribute("AturdidoHasta", nil)
		player:SetAttribute("ContraataqueHasta", nil)
		local services = game:GetService("ServerScriptService"):FindFirstChild("Services")
		local defenseModule = services and services:FindFirstChild("DefenseService")
		if defenseModule then
			require(defenseModule).ClearStunChain(player)
		end
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = humanoid.MaxHealth
		end
	elseif action == "postura" then
		-- Fija la postura de los enemigos con una etiqueta (si llega al máximo, quedan quebrados)
		local services = game:GetService("ServerScriptService"):FindFirstChild("Services")
		local sparringModule = services and services:FindFirstChild("SparringService")
		if sparringModule then
			for _, model in ipairs(game:GetService("CollectionService"):GetTagged(payload.tag)) do
				require(sparringModule).SetPosture(model, payload.value)
			end
		end
	elseif action == "reiniciar_eco" then
		-- Enfriamientos de las habilidades a cero (para probar cada una sin esperar)
		local services = game:GetService("ServerScriptService"):FindFirstChild("Services")
		local ecoModule = services and services:FindFirstChild("EcoService")
		if ecoModule then
			require(ecoModule).ResetCooldowns(player)
		end
		player:SetAttribute("UltimaSinergia", nil)
	elseif action == "fin" then
		print("[UMBRAL-PRUEBAS] Servidor: resultados recibidos, cerrando la prueba")
		endTest(payload)
	end
end)

task.delay(900, function()
	if not finished then
		warn("[UMBRAL-PRUEBAS] Tiempo agotado: cerrando la prueba")
		endTest({ { name = "Tiempo", ok = false, detail = "la prueba no terminó en 900 s" } })
	end
end)

print("[UMBRAL-PRUEBAS] Servidor de pruebas listo")

-- Diagnóstico: el ping que mide el servidor de cada jugador (las pruebas lo imprimen)
task.spawn(function()
	while true do
		for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
			player:SetAttribute("PingServidor", math.floor(player:GetNetworkPing() * 1000 + 0.5))
			player:SetAttribute("FisicaServidor", math.floor(workspace:GetRealPhysicsFPS() + 0.5))
		end
		task.wait(0.25)
	end
end)

-- Latencia simulada (-Retraso): Studio no la cuenta en GetNetworkPing; los servicios la suman con este atributo
do
	local marker = game:GetService("ReplicatedStorage"):FindFirstChild("UmbralPruebasAutomaticas")
	local lag = marker and marker:FindFirstChild("Retraso")
	local seconds = lag and tonumber(lag.Value)
	if seconds and seconds > 0 then
		workspace:SetAttribute("LatenciaSimulada", seconds)
	end
end
