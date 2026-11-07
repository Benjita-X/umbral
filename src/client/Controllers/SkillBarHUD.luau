-- SkillBarHUD: la barra de habilidades del Eco (EXPERIMENTAL, v2).
--   · PC y mando: 4 casillas abajo al centro (encima de la vida): tecla, nombre, enfriamiento que baja con los
--     segundos, destello al quedar lista, sacudida roja si se pulsa sin estar lista. V muestra la Resonancia
--     que le falta. Encima, el nombre del Eco puesto (1-5 para cambiar).
--   · Celular: los mismos datos dentro de los botones de cada habilidad.
--   · Avisos: nombre del combo (sinergia) en grande y "no salió: motivo" si el servidor rechazó la habilidad.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local CombatConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("CombatConfig"))

local SkillBarHUD = {}

local eco = CombatConfig.Eco
local skills = eco.Skills
local player = Players.LocalPlayer
local SLOT = 58
local GAP = 8
local READY_COLOR = Color3.fromRGB(240, 244, 255)
local DENIED = Color3.fromRGB(255, 90, 80)
local RECAST = Color3.fromRGB(255, 220, 110)

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 10)
	c.Parent = parent
	return c
end

local function text(parent, name, props)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = READY_COLOR
	label.TextStrokeTransparency = 0.5
	for key, value in pairs(props) do
		label[key] = value
	end
	label.Parent = parent
	return label
end

-- Una casilla (o los añadidos de un botón táctil): devuelve sus piezas
local function makeSlot(parent, slot, isButton)
	local frame = parent
	if not isButton then
		frame = Instance.new("Frame")
		frame.Name = slot
		frame.Size = UDim2.fromOffset(SLOT, SLOT)
		frame.BackgroundColor3 = Color3.fromRGB(14, 18, 26)
		frame.BackgroundTransparency = 0.15
		corner(frame)
		frame.Parent = parent
	end
	local stroke = frame:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	local cooldown = Instance.new("Frame")
	cooldown.Name = "Enfriamiento"
	cooldown.AnchorPoint = Vector2.new(0, 0)
	cooldown.Position = UDim2.fromScale(0, 0)
	cooldown.Size = UDim2.fromScale(1, 0)
	cooldown.BackgroundColor3 = Color3.new(0, 0, 0)
	cooldown.BackgroundTransparency = 0.35
	cooldown.BorderSizePixel = 0
	cooldown.ZIndex = 3
	corner(cooldown, if isButton then UDim.new(1, 0) else UDim.new(0, 10))
	cooldown.Parent = frame
	local seconds = text(frame, "Segundos", {
		Size = UDim2.fromScale(0.7, 0.42),
		Position = UDim2.fromScale(0.15, 0.22),
		Font = Enum.Font.GothamBlack,
		ZIndex = 4,
		Text = "",
	})
	local key, name = nil, nil
	if not isButton then
		key = text(frame, "Tecla", {
			Size = UDim2.fromOffset(18, 16),
			Position = UDim2.fromOffset(4, 2),
			Font = Enum.Font.GothamBlack,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 5,
			Text = slot,
		})
		name = text(frame, "Nombre", {
			Size = UDim2.new(1, -6, 0, 13),
			Position = UDim2.new(0, 3, 1, -15),
			ZIndex = 5,
			Text = "",
		})
	end
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	return { frame = frame, stroke = stroke, cooldown = cooldown, seconds = seconds, key = key, name = name, scale = scale, wasReady = true, base = nil }
end

function SkillBarHUD.Start(ecoController)
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local gui = Instance.new("ScreenGui")
	gui.Name = "UmbralHabilidades"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 7

	local slots = {}
	local kitLabel
	local bar = nil
	if not touch then
		bar = Instance.new("Frame")
		bar.Name = "Barra"
		bar.AnchorPoint = Vector2.new(0.5, 1)
		bar.Position = UDim2.new(0.5, 0, 1, -98)
		bar.Size = UDim2.fromOffset(SLOT * 4 + GAP * 3, SLOT)
		bar.BackgroundTransparency = 1
		bar.Parent = gui
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.Padding = UDim.new(0, GAP)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = bar
		for i, slot in ipairs(eco.SlotOrder) do
			local s = makeSlot(bar, slot, false)
			s.frame.LayoutOrder = i
			slots[slot] = s
		end
		-- Arma actual a la izquierda de la barra (Q la cambia)
		local weaponLabel = text(gui, "Arma", {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(0.5, -(SLOT * 4 + GAP * 3) / 2 - 10, 1, -98),
			Size = UDim2.fromOffset(110, 26),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextStrokeTransparency = 0.3,
		})
		local function refreshWeapon()
			local name = player:GetAttribute("Arma")
			local weapon = CombatConfig.Weapons[name or ""]
			weaponLabel.Text = "Q · " .. string.upper(if weapon and weapon.label then weapon.label else "Puños")
			weaponLabel.TextColor3 = if name == "Espada" then Color3.fromRGB(150, 225, 255) else Color3.fromRGB(230, 230, 240)
		end
		player:GetAttributeChangedSignal("Arma"):Connect(refreshWeapon)
		refreshWeapon()
		kitLabel = text(gui, "Eco", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -98 - SLOT - 4),
			Size = UDim2.fromOffset(SLOT * 4 + GAP * 3, 15),
			TextStrokeTransparency = 0.3,
		})
	end

	local synergyLabel = text(gui, "Sinergia", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, if touch then 0.22 else 0.3),
		Size = UDim2.fromOffset(460, 44),
		Font = Enum.Font.GothamBlack,
		TextStrokeTransparency = 0.15,
		Visible = false,
	})
	local synergyScale = Instance.new("UIScale")
	synergyScale.Parent = synergyLabel
	local noticeLabel = text(gui, "Aviso", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, if touch then -170 else -98 - SLOT - 22),
		Size = UDim2.fromOffset(360, 15),
		TextColor3 = Color3.fromRGB(200, 205, 220),
		Visible = false,
	})
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Celular: los datos van dentro de los botones de habilidad
	if touch then
		task.spawn(function()
			local controls = player.PlayerGui:WaitForChild("UmbralControlesTactiles", 15)
			if not controls then
				return
			end
			for _, slot in ipairs(eco.SlotOrder) do
				local button = controls:WaitForChild("Habilidad" .. slot, 5)
				if button then
					slots[slot] = makeSlot(button, slot, true)
				end
			end
		end)
	end

	local lastAir = nil -- última variante mostrada (suelo/aire) en las casillas con variante aérea
	local function refreshNames()
		local kit = ecoController.Kit()
		if kitLabel then
			kitLabel.Text = string.format("%s   ·   1-%d cambia de Eco", string.upper(kit.name), #eco.Order)
			kitLabel.TextColor3 = kit.color
		end
		for slot, s in pairs(slots) do
			local skillName = kit.slots[slot]
			local spec = skills[skillName]
			local label = spec and spec.label or "—"
			if s.name then
				s.name.Text = string.upper(label)
			elseif s.frame:IsA("TextButton") then
				s.frame.Text = string.upper(spec and spec.label or slot)
			end
			s.stroke.Color = kit.color
		end
	end
	refreshNames()
	ecoController.KitChanged:Connect(function()
		lastAir = nil
		refreshNames()
	end)

	-- Tecla o botón del mando según con qué se esté jugando
	local function refreshKeys()
		local last = UserInputService:GetLastInputType()
		local gamepad = last.Name:sub(1, 7) == "Gamepad"
		for slot, s in pairs(slots) do
			if s.key then
				s.key.Text = if gamepad then (eco.Gamepad[slot] or slot) else slot
				s.key.Size = UDim2.fromOffset(if gamepad then 24 else 18, 16)
			end
		end
	end
	refreshKeys()
	UserInputService.LastInputTypeChanged:Connect(refreshKeys)

	local recastLabels = {}
	ecoController.Recast:Connect(function(slot, label)
		recastLabels[slot] = label
	end)

	-- Sacudida roja: pulsada sin estar lista
	ecoController.Denied:Connect(function(slot)
		local s = slots[slot]
		if not s then
			return
		end
		s.stroke.Color = DENIED
		s.scale.Scale = 1.12
		TweenService:Create(s.scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		if not s.frame:IsA("TextButton") then
			local base = s.frame.Position
			for i, dx in ipairs({ 5, -5, 3, 0 }) do
				task.delay(i * 0.035, function()
					s.frame.Position = base + UDim2.fromOffset(dx, 0)
				end)
			end
		end
		task.delay(0.25, function()
			s.stroke.Color = ecoController.Kit().color
		end)
	end)

	-- Pulsada y lanzada: un pulso
	ecoController.Used:Connect(function(_, slot)
		local s = slots[slot]
		if s then
			s.scale.Scale = 0.88
			TweenService:Create(s.scale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end)

	local synergyToken = 0
	ecoController.Synergy:Connect(function(name)
		synergyToken += 1
		local token = synergyToken
		synergyLabel.Text = "¡" .. name .. "!"
		synergyLabel.TextColor3 = ecoController.Kit().color
		synergyLabel.Visible = true
		synergyScale.Scale = 1.5
		TweenService:Create(synergyScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		task.delay(1.2, function()
			if token == synergyToken then
				synergyLabel.Visible = false
			end
		end)
	end)

	local noticeToken = 0
	local function notice(message)
		noticeToken += 1
		local token = noticeToken
		noticeLabel.Text = message
		noticeLabel.Visible = true
		task.delay(1.6, function()
			if token == noticeToken then
				noticeLabel.Visible = false
			end
		end)
	end
	ecoController.Rejected:Connect(function(reason)
		if reason and reason ~= "enfriamiento" then
			notice("No salió: " .. tostring(reason))
		end
	end)
	ecoController.KitChanged:Connect(function()
		notice(string.upper(ecoController.Kit().name))
	end)

	RunService.Heartbeat:Connect(function()
		local resonance = player:GetAttribute("Resonancia") or 0
		local kit = ecoController.Kit()
		-- Las teclas con variante aérea muestran lo que harán AHORA (Levante en el suelo, Descenso en el aire)
		local air = ecoController.InAir()
		if air ~= lastAir then
			lastAir = air
			for slot, s in pairs(slots) do
				local variant = kit.air and kit.air[slot]
				if variant and skills[variant] then
					local spec = skills[if air then variant else kit.slots[slot]]
					if s.name then
						s.name.Text = string.upper(spec.label)
					elseif s.frame:IsA("TextButton") then
						s.frame.Text = string.upper(spec.label)
					end
				end
			end
		end
		for slot, s in pairs(slots) do
			local remaining = ecoController.CooldownRemaining(slot)
			local length = ecoController.State.cooldownLength[slot] or 1
			local swapping = ecoController.State.swapUntil - os.clock() > 0 and remaining <= ecoController.State.swapUntil - os.clock() + 0.01
			if swapping then
				length = eco.SwapCooldown
			end
			local spec = skills[kit.slots[slot]]
			local cost = spec and spec.cost or 0
			local recast = recastLabels[slot] and ecoController.State.recast[slot] ~= nil
			if recast then
				s.cooldown.Size = UDim2.fromScale(1, 0)
				s.seconds.Text = recastLabels[slot]
				s.seconds.TextColor3 = RECAST
				s.stroke.Color = RECAST
			elseif remaining > 0 then
				s.cooldown.Size = UDim2.fromScale(1, math.clamp(remaining / math.max(length, 0.01), 0, 1))
				s.seconds.Text = if remaining >= 1 then string.format("%d", math.ceil(remaining)) else string.format("%.1f", remaining)
				s.seconds.TextColor3 = READY_COLOR
			elseif cost > 0 and resonance < cost then
				-- Definitiva: se ve cuánta Resonancia falta
				s.cooldown.Size = UDim2.fromScale(1, 1 - math.clamp(resonance / cost, 0, 1))
				s.seconds.Text = string.format("%d", math.floor(resonance)) .. "/" .. cost
				s.seconds.TextColor3 = Color3.fromRGB(150, 190, 255)
			else
				s.cooldown.Size = UDim2.fromScale(1, 0)
				s.seconds.Text = ""
			end
			local ready = remaining <= 0 and not (cost > 0 and resonance < cost)
			if ready and not s.wasReady then
				-- Destello: ¡lista otra vez!
				s.scale.Scale = 1.18
				TweenService:Create(s.scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
			if not recast and s.stroke.Color ~= DENIED then
				s.stroke.Color = kit.color
				s.stroke.Transparency = if ready then 0 else 0.6
			end
			s.wasReady = ready
		end
		-- Los relanzamientos caducan
		for slot, r in pairs(ecoController.State.recast) do
			if os.clock() > r.untilTime then
				ecoController.State.recast[slot] = nil
				recastLabels[slot] = nil
			end
		end
	end)
end

return SkillBarHUD
