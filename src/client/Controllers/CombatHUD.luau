-- CombatHUD: contador de combo ("x3 COMBO · 16 de daño") que aparece al conectar golpes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("CombatConfig"))

local CombatHUD = {}

function CombatHUD.Start(combat)
	local gui = Instance.new("ScreenGui")
	gui.Name = "UmbralCombo"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8

	local frame = Instance.new("Frame")
	frame.Name = "Combo"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	-- En el celular, arriba al centro (los pulgares tapan la parte de abajo)
	frame.Position = if UserInputService.TouchEnabled then UDim2.new(0.5, 0, 0, 70) else UDim2.new(0.72, 0, 0.62, 0)
	frame.Size = UDim2.fromOffset(240, 80)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = gui

	local scale = Instance.new("UIScale")
	scale.Parent = frame

	local count = Instance.new("TextLabel")
	count.Name = "Cuenta"
	count.Size = UDim2.new(1, 0, 0.65, 0)
	count.BackgroundTransparency = 1
	count.Font = Enum.Font.GothamBlack
	count.TextScaled = true
	count.TextColor3 = Color3.fromRGB(255, 225, 90)
	count.TextStrokeTransparency = 0.2
	count.Text = ""
	count.Parent = frame

	local damage = Instance.new("TextLabel")
	damage.Name = "Dano"
	damage.Position = UDim2.new(0, 0, 0.65, 0)
	damage.Size = UDim2.new(1, 0, 0.35, 0)
	damage.BackgroundTransparency = 1
	damage.Font = Enum.Font.GothamBold
	damage.TextScaled = true
	damage.TextColor3 = Color3.fromRGB(235, 240, 255)
	damage.TextStrokeTransparency = 0.4
	damage.Text = ""
	damage.Parent = frame

	-- Aviso del resultado defensivo ("¡DESVÍO PERFECTO!", "¡CONTRAPASO!"...)
	local callout = Instance.new("TextLabel")
	callout.Name = "Aviso"
	callout.AnchorPoint = Vector2.new(0.5, 0.5)
	callout.Position = UDim2.new(0.5, 0, if UserInputService.TouchEnabled then 0.3 else 0.38, 0)
	callout.Size = UDim2.fromOffset(420, 46)
	callout.BackgroundTransparency = 1
	callout.Font = Enum.Font.GothamBlack
	callout.TextScaled = true
	callout.TextColor3 = Color3.fromRGB(255, 230, 140)
	callout.TextStrokeTransparency = 0.2
	callout.Text = ""
	callout.Visible = false
	callout.Parent = gui
	local calloutScale = Instance.new("UIScale")
	calloutScale.Parent = callout
	local calloutToken = 0

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	combat.DefenseResult:Connect(function(data, text)
		if not text then
			return
		end
		calloutToken += 1
		local token = calloutToken
		callout.Text = text
		callout.TextColor3 = if data.result == "ruptura" then Color3.fromRGB(255, 110, 90) else Color3.fromRGB(255, 230, 140)
		callout.Visible = true
		calloutScale.Scale = 1.3
		TweenService:Create(calloutScale, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		task.delay(0.9, function()
			if calloutToken == token then
				callout.Visible = false
			end
		end)
	end)

	combat.Hit:Connect(function()
		local s = combat.State
		count.Text = string.format("x%d COMBO", s.comboHits)
		damage.Text = string.format("%d de daño", math.floor(s.comboDamage + 0.5))
		frame.Visible = true
		scale.Scale = 1.25
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)

	RunService.RenderStepped:Connect(function()
		if frame.Visible and os.clock() - combat.State.lastHitTime > Config.ComboResetTime + 0.6 then
			frame.Visible = false
		end
	end)
end

return CombatHUD
