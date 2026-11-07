-- MovementAnimator: animaciones de la movilidad (EXPERIMENTAL). Paso, salto de pared, carrera por la pared
-- y agarre de borde tienen su propia pose (antes se veían con la animación genérica de caída de Roblox).
-- Solo visual: escucha los eventos de MovementController.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationLibrary = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Combat"):WaitForChild("AnimationLibrary"))

local MovementAnimator = {}

local player = Players.LocalPlayer
local tracks = {} -- [nombre] = AnimationTrack del personaje actual
local trackOwner = nil

local function play(name, fade)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	if trackOwner ~= character then
		tracks = {}
		trackOwner = character
	end
	local track = tracks[name]
	if not track then
		local ok, loaded = pcall(AnimationLibrary.Load, animator, name)
		if not ok or not loaded then
			return nil
		end
		track = loaded
		tracks[name] = track
	end
	track:Play(fade or 0.04)
	return track
end

function MovementAnimator.Start(movement)
	movement.Dashed:Connect(function()
		play("Paso")
	end)
	if movement.WallJumped then
		movement.WallJumped:Connect(function()
			play("SaltoPared")
		end)
		movement.Mantled:Connect(function()
			play("AgarreBorde")
		end)
		movement.WallRunStarted:Connect(function()
			local track = play("CarreraPared", 0.06)
			if not track then
				return
			end
			-- Se mantiene mientras dura la carrera por la pared
			local connection
			connection = RunService.Heartbeat:Connect(function()
				if not movement.State.wallRunning then
					connection:Disconnect()
					track:Stop(0.12)
				end
			end)
		end)
	end
end

return MovementAnimator
