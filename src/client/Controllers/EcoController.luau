-- EcoController: el botón Eco en esta pantalla (Fase 7, EXPERIMENTAL). Primer Eco: Eco del Viento.
--   En el suelo → Ráfaga (onda frontal).  En el aire → Descenso (picada y onda al aterrizar).
-- Muestra el efecto al instante (predicción visual); el daño y la Resonancia los decide EcoService.
-- Indicador "ECO" que se enciende cuando la Resonancia alcanza para usarlo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(shared:WaitForChild("Config"):WaitForChild("CombatConfig"))
local AnimationLibrary = require(shared:WaitForChild("Combat"):WaitForChild("AnimationLibrary"))

local EcoController = {}

local eco = CombatConfig.Eco
local player = Players.LocalPlayer
local WIND = Color3.fromRGB(150, 255, 230)
local remote = nil
local lastUse = {} -- [técnica] = os.clock
local falling = false

local function resonance()
	return player:GetAttribute("Resonancia") or 0
end

local function ready(technique)
	local spec = eco.Techniques[technique]
	return resonance() >= spec.cost and os.clock() - (lastUse[technique] or -math.huge) >= spec.cooldown
end

local function sample()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	return Workspace:GetServerTimeNow(), root.Position, root.CFrame.LookVector, root
end

local function effectPart(size, cframe, shape)
	local part = Instance.new("Part")
	part.Name = "UmbralEfectoEco"
	part.Shape = shape or Enum.PartType.Block
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = WIND
	part.Transparency = 0.35
	part.Size = size
	part.CFrame = cframe
	part.Parent = Workspace.CurrentCamera
	return part
end

local function playClip(name, speed)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local ok, track = pcall(AnimationLibrary.Load, animator, name)
	if ok and track then
		track:Play(0.05, 1, speed or 1)
	end
end

-- Ráfaga: una pared de viento que avanza hasta el alcance real
local function rafaga(combat, camera)
	local t, position, look, root = sample()
	if not t then
		return
	end
	local spec = eco.Techniques.Rafaga
	lastUse.Rafaga = os.clock()
	remote:FireServer("rafaga", t, position, look)
	playClip("Fuerte", 1.6)
	local flatLook = Vector3.new(look.X, 0, look.Z)
	flatLook = if flatLook.Magnitude > 0.01 then flatLook.Unit else Vector3.new(0, 0, -1)
	local base = CFrame.lookAt(root.Position, root.Position + flatLook)
	local wave = effectPart(Vector3.new(spec.hitboxSize.X * 0.6, spec.hitboxSize.Y * 0.7, 0.6), base * CFrame.new(0, 0, -1.5))
	local tween = TweenService:Create(wave, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = base * CFrame.new(0, 0, -(spec.range + 0.5)),
		Size = Vector3.new(spec.hitboxSize.X, spec.hitboxSize.Y, 0.3),
		Transparency = 1,
	})
	tween.Completed:Connect(function()
		wave:Destroy()
	end)
	tween:Play()
	if camera then
		camera.Shake(0.35)
	end
end

-- Descenso: picada; al aterrizar, onda circular
local function descenso(movement, camera)
	local t, position, look, root = sample()
	if not t then
		return
	end
	local spec = eco.Techniques.Descenso
	lastUse.Descenso = os.clock()
	falling = true
	remote:FireServer("descenso", t, position, look)
	local v = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(v.X * 0.3, -spec.plungeSpeed, v.Z * 0.3)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	task.spawn(function()
		local start = os.clock()
		while os.clock() - start < spec.window - 0.1 do
			if humanoid and humanoid.FloorMaterial ~= Enum.Material.Air then
				break
			end
			task.wait()
		end
		falling = false
		local tt, pos, lk, r = sample()
		if not tt then
			return
		end
		remote:FireServer("impacto", tt, pos, lk)
		local ground = r.Position - Vector3.new(0, (humanoid and humanoid.HipHeight or 2) + r.Size.Y / 2 - 0.1, 0)
		local ring = effectPart(Vector3.new(0.3, 2, 2), CFrame.new(ground) * CFrame.Angles(0, 0, math.rad(90)), Enum.PartType.Cylinder)
		local tween = TweenService:Create(ring, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.3, spec.radius * 2, spec.radius * 2),
			Transparency = 1,
		})
		tween.Completed:Connect(function()
			ring:Destroy()
		end)
		tween:Play()
		if camera then
			camera.Shake(0.5)
		end
	end)
	local _ = movement
end

local function indicator()
	local gui = Instance.new("ScreenGui")
	gui.Name = "UmbralEco"
	gui.ResetOnSpawn = false
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -78)
	label.Size = UDim2.fromOffset(220, 22)
	label.BackgroundColor3 = Color3.fromRGB(12, 20, 24)
	label.BackgroundTransparency = 0.35
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = WIND
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = label
	label.Parent = gui
	local key = if UserInputService.TouchEnabled then "ECO" elseif UserInputService.GamepadEnabled then "Y" else "Q"
	local function refresh()
		local cost = eco.Techniques.Rafaga.cost
		if resonance() >= cost then
			label.Text = string.format("%s · ECO DEL VIENTO LISTO", key)
			label.TextTransparency = 0
		else
			label.Text = string.format("ECO · %d/%d de Resonancia", math.floor(resonance()), cost)
			label.TextTransparency = 0.45
		end
	end
	player:GetAttributeChangedSignal("Resonancia"):Connect(refresh)
	refresh()
	gui.Parent = player:WaitForChild("PlayerGui")
end

function EcoController.Start(input, movement, combat, camera)
	task.spawn(function()
		remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Eco")
	end)
	task.spawn(indicator)
	input.ActionBegan:Connect(function(action)
		if action ~= "Eco" or not remote or falling then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 or combat.State.mode == "Aturdido" then
			return
		end
		local technique = if movement.State.grounded then "Rafaga" else "Descenso"
		if not ready(technique) then
			return
		end
		if technique == "Rafaga" then
			rafaga(combat, camera)
		else
			descenso(movement, camera)
		end
	end)
end

return EcoController
