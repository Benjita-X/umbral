-- GrietaService: reglas de la mazmorra de muestra (La Grieta), solo si existe en el mapa (lugar de
-- desarrollo; el de pruebas no la tiene).
--   · Caer al foso del Abismo te devuelve al borde de inicio (PuntoRetornoAbismo), sin daño.
--     Se comprueba la posición cada cuadro (Touched no es fiable con la física en manos del cliente).
-- El teletransporte lo hace el servidor y avisa a PositionService para que no cuente como movimiento
-- imposible.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local PositionService = require(script.Parent:WaitForChild("PositionService"))

local GrietaService = {}

function GrietaService.Start()
	local grieta = Workspace:WaitForChild("Maps"):FindFirstChild("Grieta")
	if not grieta then
		return
	end
	local pit = grieta:FindFirstChild("AbismoFoso")
	local checkpoint = grieta:FindFirstChild("PuntoRetornoAbismo")
	if not pit or not checkpoint then
		warn("[UMBRAL] La Grieta no tiene AbismoFoso o PuntoRetornoAbismo")
		return
	end
	-- No se usa Touched: con la física del personaje en manos del cliente no es fiable en el servidor.
	-- Cada cuadro: quien esté dentro del área del foso y por debajo del borde vuelve al punto de retorno.
	local lastReturn = {} -- [player] = os.clock()
	local half = pit.Size / 2
	local limitY = pit.Position.Y + half.Y + 6 -- por debajo de esto ya cayó (el borde está a +14)
	game:GetService("RunService").Heartbeat:Connect(function()
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root.Position.Y < limitY and os.clock() - (lastReturn[player] or 0) > 1 then
				local offset = pit.CFrame:PointToObjectSpace(root.Position)
				if math.abs(offset.X) <= half.X and math.abs(offset.Z) <= half.Z then
					lastReturn[player] = os.clock()
					PositionService.AllowTeleport(player, 1)
					root.AssemblyLinearVelocity = Vector3.zero
					character:PivotTo(checkpoint.CFrame)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastReturn[player] = nil
	end)
end

return GrietaService
