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

	local function showCallout(text, color)
		calloutToken += 1
		local token = calloutToken
		callout.Text = text
		callout.TextColor3 = color or Color3.fromRGB(255, 230, 140)
		callout.Visible = true
		calloutScale.Scale = 1.3
		TweenService:Create(calloutScale, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		task.delay(0.9, function()
			if calloutToken == token then
				callout.Visible = false
			end
		end)
	end

	combat.DefenseResult:Connect(function(data, text)
		if not text then
			return
		end
		showCallout(text, if data.result == "ruptura" then Color3.fromRGB(255, 110, 90) else nil)
	end)

	-- Notas del servidor sobre tus golpes (coraza del Centinela: "BLOQUEADO", "¡POR LA ESPALDA!")
	task.spawn(function()
		local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
		remotes:WaitForChild("GolpeConfirmado").OnClientEvent:Connect(function(data)
			if type(data) == "table" and data.attacker == Players.LocalPlayer and type(data.note) == "string" then
				local blocked = data.damage == 0
				showCallout(data.note, if blocked then Color3.fromRGB(150, 190, 255) else Color3.fromRGB(255, 200, 90))
			end
		end)
		local wave = remotes:WaitForChild("OndaReflejo", 30)
		if wave then
			wave.OnClientEvent:Connect(function(data)
				if type(data) == "table" and data.player == Players.LocalPlayer and (data.reflected or 0) > 0 then
					showCallout("¡DESVÍO REFLEJADO!", Color3.fromRGB(150, 255, 230))
				end
			end)
		end
	end)

	-- Avisos grandes de la Grieta (Guardián vencido / se levanta)
	local banner = Instance.new("TextLabel")
	banner.Name = "AvisoGrieta"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.24)
	banner.Size = UDim2.new(0.7, 0, 0, 70)
	banner.BackgroundTransparency = 1
	banner.Font = Enum.Font.GothamBlack
	banner.TextScaled = true
	banner.TextColor3 = Color3.fromRGB(205, 160, 255)
	banner.TextStrokeTransparency = 0.1
	banner.Visible = false
	banner.Parent = gui
	local bannerSub = Instance.new("TextLabel")
	bannerSub.AnchorPoint = Vector2.new(0.5, 0)
	bannerSub.Position = UDim2.new(0.5, 0, 1, 4)
	bannerSub.Size = UDim2.new(1, 0, 0, 26)
	bannerSub.BackgroundTransparency = 1
	bannerSub.Font = Enum.Font.GothamBold
	bannerSub.TextScaled = true
	bannerSub.TextColor3 = Color3.fromRGB(235, 225, 255)
	bannerSub.TextStrokeTransparency = 0.3
	bannerSub.Parent = banner
	local bannerToken = 0
	task.spawn(function()
		local remote = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("AvisoGrieta", 30)
		if not remote then
			return
		end
		remote.OnClientEvent:Connect(function(data)
			if type(data) ~= "table" then
				return
			end
			bannerToken += 1
			local token = bannerToken
			banner.Text = tostring(data.title or "")
			bannerSub.Text = tostring(data.subtitle or "")
			-- Aviso chico (enemigo común vencido, Contratiempo) o grande (Guardián)
			banner.Size = if data.small then UDim2.new(0.45, 0, 0, 44) else UDim2.new(0.7, 0, 0, 70)
			banner.Visible = true
			banner.TextTransparency = 1
			TweenService:Create(banner, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
			task.delay(3.5, function()
				if bannerToken == token then
					banner.Visible = false
				end
			end)
		end)
	end)

	-- El servidor puede corregir el daño (coraza): se refresca el contador con el valor real
	combat.Confirmed:Connect(function(data)
		if type(data) == "table" and data.note and frame.Visible then
			local s = combat.State
			count.Text = string.format("x%d COMBO", s.comboHits)
			damage.Text = string.format("%d de daño", math.floor(s.comboDamage + 0.5))
		end
	end)

	combat.Hit:Connect(function()
		local s = combat.State
		count.Text = string.format("x%d COMBO", s.comboHits)
		-- Igual que el servidor: desde el 9.º golpe seguido cada uno hace un 7 % menos (mínimo 50 %)
		local scaling = if s.comboHits > 8 then math.max(50, 100 - (s.comboHits - 8) * 7) else 100
		damage.Text = if scaling < 100
			then string.format("%d de daño · golpes al %d %%", math.floor(s.comboDamage + 0.5), scaling)
			else string.format("%d de daño", math.floor(s.comboDamage + 0.5))
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
