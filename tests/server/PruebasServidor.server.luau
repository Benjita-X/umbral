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
	if action == "reaparecer" then
		player:LoadCharacterAsync()
	elseif action == "patron" then
		-- Fija el patrón de ataques del compañero de combate (p. ej. "Golpe" o "Barrido")
		for _, model in ipairs(game:GetService("CollectionService"):GetTagged("Sparring")) do
			model:SetAttribute("Patron", payload)
		end
	elseif action == "resonancia" then
		player:SetAttribute("Resonancia", payload)
	elseif action == "reiniciar_defensa" then
		player:SetAttribute("Postura", 0)
		player:SetAttribute("AturdidoHasta", nil)
		player:SetAttribute("ContraataqueHasta", nil)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = humanoid.MaxHealth
		end
	elseif action == "fin" then
		print("[UMBRAL-PRUEBAS] Servidor: resultados recibidos, cerrando la prueba")
		endTest(payload)
	end
end)

task.delay(300, function()
	if not finished then
		warn("[UMBRAL-PRUEBAS] Tiempo agotado: cerrando la prueba")
		endTest({ { name = "Tiempo", ok = false, detail = "la prueba no terminó en 300 s" } })
	end
end)

print("[UMBRAL-PRUEBAS] Servidor de pruebas listo")
