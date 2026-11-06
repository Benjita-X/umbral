-- VitalsHUD: vida, postura y Resonancia del jugador.
-- La postura solo aparece cuando importa (al bloquear); la barra de Resonancia brilla cuando alcanza
-- para un Paso extra, y "CONTRAATAQUE" aparece mientras dura esa ventana.
-- (Provisional: más adelante la vida será un anillo y la Resonancia el brillo del aura.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("CombatConfig"))

local VitalsHUD = {}

local function bar(parent, name, order, color, height)
	local back = Instance.new("Frame")
	back.Name = name
	back.LayoutOrder = order
	back.Size = UDim2.new(1, 0, 0, height)
	back.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
	back.BackgroundTransparency = 0.2
	back.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = back
	local fill = Instance.new("Frame")
	fill.Name = "Relleno"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = back
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = fill
	local label = Instance.new("TextLabel")
	label.Name = "Texto"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Parent = back
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 1)
	padding.PaddingBottom = UDim.new(0, 1)
	padding.Parent = label
	back.Parent = parent
	return back, fill, label
end

function VitalsHUD.Start(combat)
	local player = Players.LocalPlayer
	local touch = UserInputService.TouchEnabled

	local gui = Instance.new("ScreenGui")
	gui.Name = "UmbralVitales"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 7

	local frame = Instance.new("Frame")
	frame.Name = "Vitales"
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = Vector2.new(0.5, if touch then 0 else 1)
	frame.Position = if touch then UDim2.new(0.5, 0, 0, 8) else UDim2.new(0.5, 0, 1, -18)
	frame.Size = UDim2.fromOffset(if touch then 240 else 320, 70)
	frame.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = frame

	local _, healthFill, healthText = bar(frame, "Vida", 1, Color3.fromRGB(90, 210, 120), 18)
	local postureBack, postureFill, postureText = bar(frame, "Postura", 2, Color3.fromRGB(235, 120, 60), 10)
	local resonanceBack, resonanceFill, resonanceText = bar(frame, "Resonancia", 3, Color3.fromRGB(110, 170, 255), 12)
	local resonanceStroke = Instance.new("UIStroke")
	resonanceStroke.Color = Color3.fromRGB(255, 220, 120)
	resonanceStroke.Thickness = 2
	resonanceStroke.Parent = resonanceBack

	local counterLabel = Instance.new("TextLabel")
	counterLabel.Name = "Contraataque"
	counterLabel.LayoutOrder = 0
	counterLabel.Size = UDim2.new(1, 0, 0, 16)
	counterLabel.BackgroundTransparency = 1
	counterLabel.Font = Enum.Font.GothamBlack
	counterLabel.TextScaled = true
	counterLabel.TextColor3 = Color3.fromRGB(255, 220, 110)
	counterLabel.TextStrokeTransparency = 0.3
	counterLabel.Text = "¡CONTRAATAQUE!"
	counterLabel.Visible = false
	counterLabel.Parent = frame

	gui.Parent = player:WaitForChild("PlayerGui")

	RunService.RenderStepped:Connect(function()
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local ratio = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
			healthFill.Size = UDim2.fromScale(ratio, 1)
			healthText.Text = string.format("%d", math.floor(humanoid.Health + 0.5))
		end
		local posture = player:GetAttribute("Postura") or 0
		postureBack.Visible = posture > 0.5
		postureFill.Size = UDim2.fromScale(math.clamp(posture / Config.Defense.PostureMax, 0, 1), 1)
		postureText.Text = ""
		local resonance = player:GetAttribute("Resonancia") or 0
		resonanceFill.Size = UDim2.fromScale(math.clamp(resonance / Config.Resonance.Max, 0, 1), 1)
		resonanceText.Text = string.format("RESONANCIA %d", math.floor(resonance + 0.5))
		resonanceStroke.Enabled = resonance >= Config.Resonance.DashCost
		counterLabel.Visible = os.clock() <= combat.State.counterUntil
	end)
end

return VitalsHUD
