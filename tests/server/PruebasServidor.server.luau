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

remote.OnServerEvent:Connect(function(player, action, payload)
	if action == "teletransporte" then
		-- Las pruebas mueven al personaje de golpe: se avisa al historial de posiciones para que no lo
		-- marque como movimiento imposible. SOLO existe en el lugar de pruebas (este script no se
		-- incluye en build/UMBRAL-Desarrollo.rbxlx ni en ninguna versión publicable).
		local services = game:GetService("ServerScriptService"):FindFirstChild("Services")
		local module = services and services:FindFirstChild("PositionService")
		if module then
			require(module).AllowTeleport(player, 1)
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
	elseif action == "fin" then
		print("[UMBRAL-PRUEBAS] Servidor: resultados recibidos, cerrando la prueba")
		endTest(payload)
	end
end)

task.delay(540, function()
	if not finished then
		warn("[UMBRAL-PRUEBAS] Tiempo agotado: cerrando la prueba")
		endTest({ { name = "Tiempo", ok = false, detail = "la prueba no terminó en 540 s" } })
	end
end)

print("[UMBRAL-PRUEBAS] Servidor de pruebas listo")
