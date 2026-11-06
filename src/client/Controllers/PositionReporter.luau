-- PositionReporter: manda al servidor la posición del jugador con la hora sincronizada
-- (workspace:GetServerTimeNow), 20 veces por segundo, por un canal liviano (UnreliableRemoteEvent).
-- El servidor la usa para juzgar golpes y defensas en el instante exacto, siempre confirmándola con la
-- física que él mismo observa (ver PositionService). Sample() da la muestra actual para adjuntarla a un
-- golpe o a un Paso.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("CombatConfig"))

local PositionReporter = {}

local player = Players.LocalPlayer

-- Muestra actual: hora del servidor, posición y hacia dónde mira
function PositionReporter.Sample()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return Workspace:GetServerTimeNow(), nil, nil
	end
	return Workspace:GetServerTimeNow(), root.Position, root.CFrame.LookVector
end

function PositionReporter.Start()
	local stream = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Posicion")
	local interval = 1 / CombatConfig.Network.ReportRate
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < interval then
			return
		end
		elapsed = 0
		local t, position, look = PositionReporter.Sample()
		if position then
			stream:FireServer(t, position, look)
		end
	end)
end

return PositionReporter
