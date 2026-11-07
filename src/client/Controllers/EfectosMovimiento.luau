-- EfectosMovimiento: lo que se SIENTE del movimiento (EXPERIMENTAL). Solo en esta pantalla.
--   · Caer desde alto: polvo en los pies y una sacudida de cámara proporcional a la velocidad del golpe.
--   · Paso: una silueta fantasma que se desvanece (se lee la velocidad del Paso).
--   · Gancho: chispas al soltar.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local EfectosMovimiento = {}

local player = Players.LocalPlayer
local DUST = Color3.fromRGB(190, 180, 170)
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function folder()
	local camera = Workspace.CurrentCamera
	local f = camera:FindFirstChild("UmbralEfectosMovimiento")
	if not f then
		f = Instance.new("Folder")
		f.Name = "UmbralEfectosMovimiento"
		f.Parent = camera
	end
	return f
end

local function dust(position, strength)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = folder()
	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SMOKE
	emitter.Color = ColorSequence.new(DUST)
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 2.4 + strength * 2) })
	emitter.Lifetime = NumberRange.new(0.35, 0.6)
	emitter.Speed = NumberRange.new(6, 10 + strength * 10)
	emitter.SpreadAngle = Vector2.new(90, 5)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Acceleration = Vector3.new(0, -6, 0)
	emitter.Drag = 4
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(math.floor(10 + strength * 14))
	-- Un aro de polvo que se abre
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.SmoothPlastic
	ring.Color = DUST
	ring.Transparency = 0.55
	ring.Size = Vector3.new(0.2, 2, 2)
	ring.CFrame = CFrame.new(position + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = folder()
	local radius = 4 + strength * 6
	TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.2, radius * 2, radius * 2), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.4)
	Debris:AddItem(anchor, 1)
end

local function ghost(character)
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and part.Transparency < 1 and not string.find(part.Name, "Umbral", 1, true) then
			local copy = Instance.new("Part")
			copy.Anchored = true
			copy.CanCollide = false
			copy.CanQuery = false
			copy.CanTouch = false
			copy.CastShadow = false
			copy.Material = Enum.Material.Neon
			copy.Color = Color3.fromRGB(200, 220, 255)
			copy.Size = part.Size
			copy.CFrame = part.CFrame
			copy.Transparency = 0.7
			copy.Parent = folder()
			TweenService:Create(copy, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 }):Play()
			Debris:AddItem(copy, 0.3)
		end
	end
end

-- Líneas de velocidad en los bordes de la pantalla (gancho y Paso)
local function speedLines(movement)
	local gui = Instance.new("ScreenGui")
	gui.Name = "UmbralLineasVelocidad"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 2
	local lines = {}
	local random = Random.new(7)
	for i = 1, 22 do
		local angle = (i / 22) * math.pi * 2 + random:NextNumber(-0.1, 0.1)
		local line = Instance.new("Frame")
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.BackgroundColor3 = Color3.fromRGB(235, 242, 255)
		line.BorderSizePixel = 0
		line.BackgroundTransparency = 1
		line.Rotation = math.deg(angle)
		line.Parent = gui
		table.insert(lines, { frame = line, angle = angle, length = random:NextNumber(0.12, 0.22), offset = random:NextNumber(0.38, 0.48) })
	end
	gui.Parent = player:WaitForChild("PlayerGui")
	local lastDash = -math.huge
	movement.Dashed:Connect(function()
		lastDash = os.clock()
	end)
	local strength = 0
	game:GetService("RunService").RenderStepped:Connect(function(dt)
		local target = 0
		if movement.State.grappling then
			target = 0.5
		elseif os.clock() - lastDash < 0.22 then
			target = 0.35
		end
		strength += (target - strength) * math.min(1, dt * 14)
		local visible = strength > 0.02
		for _, line in ipairs(lines) do
			local frame = line.frame
			if visible then
				local jitter = random:NextNumber(-0.02, 0.02)
				local radius = line.offset + jitter
				frame.Position = UDim2.fromScale(0.5 + math.cos(line.angle) * radius, 0.5 + math.sin(line.angle) * radius)
				frame.Size = UDim2.new(line.length, 0, 0, 2)
				frame.BackgroundTransparency = 1 - strength * random:NextNumber(0.6, 1)
			elseif frame.BackgroundTransparency < 1 then
				frame.BackgroundTransparency = 1
			end
		end
	end)
end

function EfectosMovimiento.Start(movement, camera)
	task.spawn(speedLines, movement)
	if movement.Landed then
		movement.Landed:Connect(function(speed)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not root or not humanoid or speed < 45 then
				return
			end
			local strength = math.clamp((speed - 45) / 90, 0, 1)
			local feet = root.Position - Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
			dust(feet, strength)
			if camera and camera.Shake then
				camera.Shake(0.08 + strength * 0.3)
			end
		end)
	end
	movement.Dashed:Connect(function()
		local character = player.Character
		if character then
			ghost(character)
		end
	end)
end

return EfectosMovimiento
