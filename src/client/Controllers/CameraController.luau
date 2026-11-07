-- CameraController: cámara de tercera persona de Roblox con campo de visión dinámico y vibración.
-- El FOV se abre un poco en sprint y da un golpe breve al iniciar un Paso, para sentir la velocidad.
-- La vibración usa Humanoid.CameraOffset (no pelea con la cámara de Roblox) y se puede apagar en
-- CombatConfig.Feedback.ScreenShake.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local configFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Config = require(configFolder:WaitForChild("MovementConfig"))
local CombatConfig = require(configFolder:WaitForChild("CombatConfig"))

local CameraController = {}

local trauma = 0 -- 0..1; la vibración crece con su cuadrado (golpes chicos casi no se notan)
local seed = math.random() * 1000

-- Añade vibración (0..1). Los golpes fuertes dan más.
function CameraController.Shake(amount)
	trauma = math.clamp(trauma + amount * CombatConfig.Feedback.ScreenShake, 0, 1)
end

function CameraController.Start(movement)
	local player = Players.LocalPlayer
	player.CameraMinZoomDistance = 6
	player.CameraMaxZoomDistance = 40

	local kick = 0
	movement.Dashed:Connect(function()
		kick = Config.DashFOVKick
	end)
	-- Paredes: el salto de pared y el agarre dan un golpe de FOV más chico; correr por la pared, uno largo
	if movement.WallJumped then
		movement.WallJumped:Connect(function()
			kick = math.max(kick, Config.DashFOVKick * 0.7)
		end)
		movement.Mantled:Connect(function()
			kick = math.max(kick, Config.DashFOVKick * 0.4)
		end)
		movement.WallRunStarted:Connect(function()
			kick = math.max(kick, Config.DashFOVKick)
		end)
	end

	local shakeHumanoid = nil
	RunService.RenderStepped:Connect(function(dt)
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		kick *= math.exp(-10 * dt)
		local fast = movement.State.sprinting or movement.State.wallRunning
		local target = (if fast then Config.SprintFOV else Config.BaseFOV) + kick
		local alpha = 1 - math.exp(-Config.FOVResponsiveness * dt)
		camera.FieldOfView += (target - camera.FieldOfView) * alpha

		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if trauma > 0 and humanoid then
			local t = os.clock() * 30
			local strength = trauma * trauma * CombatConfig.Feedback.MaxShakeOffset
			humanoid.CameraOffset = Vector3.new(
				math.noise(t, seed) * strength,
				math.noise(t, seed + 17) * strength,
				math.noise(t, seed + 33) * strength * 0.5
			)
			shakeHumanoid = humanoid
			trauma = math.max(0, trauma - dt * 3.2)
		elseif shakeHumanoid then
			shakeHumanoid.CameraOffset = Vector3.zero
			shakeHumanoid = nil
		end
	end)
end

return CameraController
