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
	movement.Dashed:Connect(function(direction)
		-- Hacia adelante y en el suelo: voltereta. De lado, hacia atrás o en el aire: el Paso inclinado.
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local forward = 0
		if root and typeof(direction) == "Vector3" and direction.Magnitude > 0.01 then
			local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
			local dir = Vector3.new(direction.X, 0, direction.Z)
			if look.Magnitude > 0.01 and dir.Magnitude > 0.01 then
				forward = look.Unit:Dot(dir.Unit)
			end
		end
		if movement.State.grounded and forward > 0.6 then
			play("PasoVoltereta", 0.03)
		else
			play("Paso")
		end
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
