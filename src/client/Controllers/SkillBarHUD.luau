-- SkillBarHUD: la barra de habilidades del Eco (EXPERIMENTAL, v2).
--   · PC y mando: 4 casillas abajo al centro (encima de la vida): tecla, nombre, enfriamiento que baja con los
--     segundos, destello al quedar lista, sacudida roja si se pulsa sin estar lista. V muestra la Resonancia
--     que le falta. Encima, el nombre del Eco puesto (1-5 para cambiar).
--   · Celular: los mismos datos dentro de los botones de cada habilidad.
--   · Avisos: nombre del combo (sinergia) en grande y "no salió: motivo" si el servidor rechazó la habilidad.
--   · Ficha del Eco: qué hace cada tecla. Sale al cambiar de Eco (la primera vez de cada uno, o fuera de combate)
--     y al pulsar el número del Eco que ya llevas puesto. Se esconde sola o al usar una habilidad.
--   · Pista de una habilidad: Alt + su tecla (o el ratón encima de la casilla, con el ratón suelto) muestra qué
--     hace, su enfriamiento, su daño y su variante en el aire.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local CombatConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("CombatConfig"))
local Texto = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Texto"))

local SkillBarHUD = {}

local eco = CombatConfig.Eco
local skills = eco.Skills
local player = Players.LocalPlayer
local SLOT = 58
local GAP = 8
local READY_COLOR = Color3.fromRGB(240, 244, 255)
local DENIED = Color3.fromRGB(255, 90, 80)
local RECAST = Color3.fromRGB(255, 220, 110)
local QUEUED = Color3.fromRGB(240, 248, 255)

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
			weaponLabel.Text = "Q · " .. Texto.Mayusculas(if weapon and weapon.label then weapon.label else "Puños")
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
	local wasReady = nil -- ¿la definitiva estaba lista el cuadro anterior? (nil al empezar: no avisa al entrar)
	local function refreshNames()
		local kit = ecoController.Kit()
		if kitLabel then
			kitLabel.Text = string.format("%s   ·   1-%d cambia de Eco", Texto.Mayusculas(kit.name), #eco.Order)
			kitLabel.TextColor3 = kit.color
		end
		for slot, s in pairs(slots) do
			local skillName = kit.slots[slot]
			local spec = skills[skillName]
			local label = spec and spec.label or "—"
			if s.name then
				s.name.Text = Texto.Mayusculas(label)
			elseif s.frame:IsA("TextButton") then
				s.frame.Text = Texto.Mayusculas(spec and spec.label or slot)
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
	-- Motivos del servidor dichos como los entiende un jugador
	local FRIENDLY = {
		["golpe fallado"] = "tu golpe no contó: espera a que termine",
		["posición no confirmada"] = "se perdió la conexión un instante",
		["cambiando de Eco"] = "el Eco se está cambiando",
	}
	ecoController.Rejected:Connect(function(reason)
		if reason and reason ~= "enfriamiento" then
			notice("No salió: " .. (FRIENDLY[reason] or tostring(reason)))
		end
	end)

	-- Ficha del Eco
	local card = Instance.new("CanvasGroup")
	card.Name = "Ficha"
	-- Abajo a la izquierda (en el centro tapaba el contador de combo); en el celular, arriba
	card.AnchorPoint = if touch then Vector2.new(0.5, 0) else Vector2.new(0, 1)
	card.Position = if touch then UDim2.new(0.5, 0, 0, 58) else UDim2.new(0, 16, 1, -98 - SLOT - 30)
	card.Size = UDim2.fromOffset(450, 120)
	card.BackgroundColor3 = Color3.fromRGB(10, 13, 20)
	card.BackgroundTransparency = 0.2
	card.GroupTransparency = 1
	card.Visible = false
	corner(card)
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Thickness = 1.5
	cardStroke.Transparency = 0.35
	cardStroke.Parent = card
	local cardPadding = Instance.new("UIPadding")
	cardPadding.PaddingTop = UDim.new(0, 7)
	cardPadding.PaddingBottom = UDim.new(0, 7)
	cardPadding.PaddingLeft = UDim.new(0, 12)
	cardPadding.PaddingRight = UDim.new(0, 12)
	cardPadding.Parent = card
	local cardList = Instance.new("UIListLayout")
	cardList.Padding = UDim.new(0, 3)
	cardList.SortOrder = Enum.SortOrder.LayoutOrder
	cardList.Parent = card
	card.Parent = gui

	local function hex(c)
		return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
	end
	local cardToken = 0
	local shownKits = {}
	local function hideCard(duration)
		cardToken += 1
		local token = cardToken
		local tween = TweenService:Create(card, TweenInfo.new(duration or 0.35), { GroupTransparency = 1 })
		tween:Play()
		tween.Completed:Connect(function()
			if token == cardToken then
				card.Visible = false
			end
		end)
	end
	-- Muestra la ficha. Sin `force`, solo la primera vez de cada Eco o fuera de combate. Devuelve si salió.
	local function showCard(force)
		local kit = ecoController.Kit()
		local name = ecoController.KitName()
		local last = ecoController.State.lastCast
		local fighting = last ~= nil and os.clock() - last.time < 3
		if not force and shownKits[name] and fighting then
			return false
		end
		shownKits[name] = true
		for _, child in ipairs(card:GetChildren()) do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		local gamepad = UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad"
		local rows = 0
		local function row(value, height, color)
			rows += 1
			text(card, "Fila" .. rows, {
				Size = UDim2.new(1, 0, 0, height),
				TextXAlignment = Enum.TextXAlignment.Left,
				RichText = true,
				Text = value,
				LayoutOrder = rows,
				TextColor3 = color or READY_COLOR,
				TextStrokeTransparency = 0.7,
			})
		end
		local accent = hex(kit.color)
		row(string.format("<b>%s</b>   ·   %s", Texto.Mayusculas(kit.name), kit.role or ""), 18, kit.color)
		if kit.reacts then
			row(string.format('<font color="%s"><b>REACCIÓN</b></font>   %s', accent, kit.reacts), 15)
		end
		for _, slot in ipairs(eco.SlotOrder) do
			local key = if gamepad then (eco.Gamepad[slot] or slot) else slot
			for _, entry in ipairs({ { kit.slots[slot], key }, { kit.air and kit.air[slot], key .. " en el aire" } }) do
				local spec = entry[1] and skills[entry[1]]
				if spec then
					row(string.format('<font color="%s"><b>%s</b></font>   <b>%s</b>  —  %s', accent, entry[2], Texto.Mayusculas(spec.label), spec.desc or ""), 15)
				end
			end
		end
		card.Size = UDim2.fromOffset(if touch then 420 else 540, 14 + 18 + (rows - 1) * 15 + (rows - 1) * 3)
		cardStroke.Color = kit.color
		cardToken += 1
		local token = cardToken
		card.Visible = true
		TweenService:Create(card, TweenInfo.new(0.15), { GroupTransparency = 0 }):Play()
		task.delay(4.5, function()
			if token == cardToken then
				hideCard()
			end
		end)
		return true
	end
	SkillBarHUD.ShowCard = showCard

	-- Registro de pulsaciones (solo en modo práctica): las últimas habilidades pulsadas y qué pasó con cada una
	-- (salió, esperó en cola o no salió y por qué). Para entender un "pulsé y no salió".
	local inputLog = Instance.new("Frame")
	inputLog.Name = "RegistroPulsaciones"
	inputLog.AnchorPoint = Vector2.new(1, 0.5)
	inputLog.Position = UDim2.new(1, -12, 0.5, 0)
	inputLog.Size = UDim2.fromOffset(250, 5 * 18 + 26)
	inputLog.BackgroundColor3 = Color3.fromRGB(10, 13, 20)
	inputLog.BackgroundTransparency = 0.3
	inputLog.Visible = false
	corner(inputLog)
	local logTitle = text(inputLog, "Titulo", { Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -16, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, Text = "PULSACIONES (modo práctica)", TextColor3 = Color3.fromRGB(170, 180, 205) })
	local _ = logTitle
	local logRows = {}
	for i = 1, 5 do
		logRows[i] = text(inputLog, "Fila" .. i, { Position = UDim2.fromOffset(8, 6 + i * 18), Size = UDim2.new(1, -16, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, Text = "", RichText = true })
	end
	inputLog.Parent = gui
	local entries = {}
	local serverRow = nil -- habilidad de la fila del servidor que está arriba (para actualizarla en su sitio)
	local function redraw()
		for i, row in ipairs(logRows) do
			row.Text = entries[i] or ""
		end
	end
	local function pushLog(line)
		serverRow = nil
		table.insert(entries, 1, line)
		if #entries > 5 then
			table.remove(entries)
		end
		redraw()
	end
	-- Lo que dijo el SERVIDOR (la verdad, no solo lo que se vio aquí): ✓✓ con a cuántos alcanzó o ✕✕ con el motivo.
	-- Una habilidad que sigue golpeando (tornado, Juicio) actualiza su misma fila en vez de llenar el registro.
	local function pushServer(name, line)
		if name ~= nil and serverRow == name and entries[1] then
			entries[1] = line
			redraw()
		else
			pushLog(line)
		end
		serverRow = name
	end
	local function practicing()
		return player:GetAttribute("Practica") == true
	end
	inputLog.Visible = practicing()
	player:GetAttributeChangedSignal("Practica"):Connect(function()
		inputLog.Visible = practicing()
	end)
	ecoController.Used:Connect(function(skillName, slot)
		if practicing() then
			local spec = skills[skillName or ""]
			pushLog(string.format('<font color="#8CFFA0">✓</font> %s · %s', tostring(slot), Texto.Mayusculas(spec and spec.label or tostring(skillName))))
		end
	end)
	ecoController.Denied:Connect(function(slot, reason)
		if practicing() then
			pushLog(string.format('<font color="#FF8070">✕</font> %s · no salió: %s', tostring(slot), tostring(reason)))
		end
	end)
	if ecoController.Replaced then
		ecoController.Replaced:Connect(function(old, new)
			if practicing() then
				pushLog(string.format('<font color="#C8C8D2">↺</font> %s en cola · la reemplazó %s', tostring(old), tostring(new)))
			end
		end)
	end
	player:GetAttributeChangedSignal("UltimoEco"):Connect(function()
		if not practicing() then
			return
		end
		local name, count = string.match(tostring(player:GetAttribute("UltimoEco") or ""), "^([^:]+):(%d+)")
		if name then
			local spec = skills[name]
			pushServer(name, string.format('<font color="#8CFFA0">✓✓</font> servidor: %s · alcanzó a %s', Texto.Mayusculas(spec and spec.label or name), count))
		end
	end)
	ecoController.Rejected:Connect(function(reason)
		if practicing() then
			pushServer(nil, string.format('<font color="#FF8070">✕✕</font> servidor: no salió · %s', tostring(reason)))
		end
	end)
	local loggedQueue = nil
	RunService.Heartbeat:Connect(function()
		local queuedSlot = ecoController.BufferedSlot and ecoController.BufferedSlot()
		if practicing() and queuedSlot and queuedSlot ~= loggedQueue then
			pushLog(string.format('<font color="#F0F8FF">…</font> %s · en cola (sale en cuanto se pueda)', tostring(queuedSlot)))
		end
		loggedQueue = queuedSlot
	end)

	-- Pista de reacción: si el enemigo de enfrente está mojado, cargado o ardiendo, qué Eco reacciona con él
	local hint = text(gui, "PistaReaccion", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, if touch then -190 else -98 - SLOT - 40),
		Size = UDim2.fromOffset(460, 16),
		RichText = true,
		Visible = false,
		TextStrokeTransparency = 0.3,
	})
	local STATES = {
		{ attribute = "MojadoHasta", label = "MOJADO", color = "#6EBEFF", options = { { 5, "Trueno", "ELECTROCUCIÓN" }, { 4, "Fuego", "VAPOR" } } },
		{ attribute = "CargadoHasta", label = "CARGADO", color = "#FFF06E", options = { { 3, "Oscuridad", "PULSO UMBRÍO" }, { 2, "Agua", "CONDUCCIÓN" } } },
		{ attribute = "ArdeHasta", label = "ARDIENDO", color = "#FF8A3C", options = { { 1, "Viento", "TORMENTA ÍGNEA" } } },
	}
	local CollectionService = game:GetService("CollectionService")
	local hintClock = 0
	RunService.Heartbeat:Connect(function(dt)
		hintClock += dt
		if hintClock < 0.2 then
			return
		end
		hintClock = 0
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			hint.Visible = false
			return
		end
		local look = root.CFrame.LookVector
		local best, bestScore = nil, math.huge
		for _, model in ipairs(CollectionService:GetTagged("Objetivo")) do
			local enemyRoot = model ~= character and model:FindFirstChild("HumanoidRootPart")
			if enemyRoot then
				local offset = enemyRoot.Position - root.Position
				local distance = offset.Magnitude
				if distance < 28 and (distance < 6 or offset.Unit:Dot(look) > 0.5) and distance < bestScore then
					best, bestScore = model, distance
				end
			end
		end
		local now = workspace:GetServerTimeNow()
		local textValue = nil
		if best then
			for _, state in ipairs(STATES) do
				if (best:GetAttribute(state.attribute) or 0) > now then
					local parts = {}
					for _, option in ipairs(state.options) do
						local kit = eco.Kits[option[2]]
						table.insert(parts, string.format('<font color="%s"><b>%d %s</b></font>: %s', hex(kit.color), option[1], Texto.Mayusculas(option[2]), option[3]))
					end
					textValue = string.format('<font color="%s"><b>%s</b></font>   ·   %s', state.color, state.label, table.concat(parts, "   ·   "))
					break
				end
			end
		end
		hint.Visible = textValue ~= nil
		if textValue then
			hint.Text = textValue
		end
	end)

	-- Nombre de la técnica al lanzar una definitiva: franja del color del Eco que entra deslizándose (estilo anime)
	local cutIn = Instance.new("Frame")
	cutIn.Name = "Definitiva"
	cutIn.AnchorPoint = Vector2.new(0.5, 0.5)
	cutIn.Position = UDim2.fromScale(0.5, 0.36)
	cutIn.Size = UDim2.new(1.3, 0, 0, 74)
	cutIn.Rotation = -6
	cutIn.BorderSizePixel = 0
	cutIn.Visible = false
	local cutGradient = Instance.new("UIGradient")
	cutGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.18, 0.15),
		NumberSequenceKeypoint.new(0.82, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	cutGradient.Parent = cutIn
	local cutName = text(cutIn, "Nombre", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.new(0.6, 0, 0, 50),
		Font = Enum.Font.GothamBlack,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = Color3.new(0, 0, 0),
	})
	local cutKit = text(cutIn, "Eco", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.72),
		Size = UDim2.new(0.6, 0, 0, 16),
		TextStrokeTransparency = 0.2,
		TextStrokeColor3 = Color3.new(0, 0, 0),
	})
	cutIn.Parent = gui
	local cutToken = 0
	ecoController.Used:Connect(function(skillName)
		local spec = skills[skillName or ""]
		if not spec or (spec.cost or 0) <= 0 then
			return
		end
		cutToken += 1
		local token = cutToken
		local kit = ecoController.Kit()
		cutIn.BackgroundColor3 = kit.color:Lerp(Color3.new(0, 0, 0), 0.35)
		cutName.Text = Texto.Mayusculas(spec.label)
		cutKit.Text = Texto.Mayusculas(kit.name)
		cutIn.BackgroundTransparency = 0
		cutName.TextTransparency, cutKit.TextTransparency = 0, 0
		cutIn.Position = UDim2.fromScale(-0.4, 0.36)
		cutIn.Visible = true
		TweenService:Create(cutIn, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.36) }):Play()
		task.delay(0.75, function()
			if token ~= cutToken then
				return
			end
			local info = TweenInfo.new(0.25)
			TweenService:Create(cutIn, info, { BackgroundTransparency = 1, Position = UDim2.fromScale(0.62, 0.36) }):Play()
			TweenService:Create(cutName, info, { TextTransparency = 1 }):Play()
			TweenService:Create(cutKit, info, { TextTransparency = 1 }):Play()
			task.delay(0.26, function()
				if token == cutToken then
					cutIn.Visible = false
				end
			end)
		end)
	end)
	ecoController.KitChanged:Connect(function()
		if not showCard(false) then
			notice(Texto.Mayusculas(ecoController.Kit().name))
		end
	end)
	-- Pista de una habilidad, encima de su casilla
	local tip = Instance.new("Frame")
	tip.Name = "Pista"
	tip.AnchorPoint = Vector2.new(0.5, 1)
	tip.Size = UDim2.fromOffset(300, 92)
	tip.BackgroundColor3 = Color3.fromRGB(10, 13, 20)
	tip.BackgroundTransparency = 0.12
	tip.Visible = false
	corner(tip)
	local tipStroke = Instance.new("UIStroke")
	tipStroke.Thickness = 1.5
	tipStroke.Parent = tip
	local tipPadding = Instance.new("UIPadding")
	tipPadding.PaddingTop = UDim.new(0, 6)
	tipPadding.PaddingBottom = UDim.new(0, 6)
	tipPadding.PaddingLeft = UDim.new(0, 10)
	tipPadding.PaddingRight = UDim.new(0, 10)
	tipPadding.Parent = tip
	local tipList = Instance.new("UIListLayout")
	tipList.Padding = UDim.new(0, 2)
	tipList.SortOrder = Enum.SortOrder.LayoutOrder
	tipList.Parent = tip
	local tipTitle = text(tip, "Titulo", { Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1, Font = Enum.Font.GothamBlack })
	local tipDesc = text(tip, "Descripcion", { Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, LayoutOrder = 2, Font = Enum.Font.Gotham })
	local tipStats = text(tip, "Datos", { Size = UDim2.new(1, 0, 0, 14), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 3, TextColor3 = Color3.fromRGB(190, 196, 215), Font = Enum.Font.Gotham })
	local tipAir = text(tip, "Aire", { Size = UDim2.new(1, 0, 0, 14), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 4, Font = Enum.Font.Gotham })
	tip.Parent = gui
	local tipToken = 0
	local function hideTip()
		tipToken += 1
		tip.Visible = false
	end
	local function statsOf(spec)
		local parts = { string.format("Enfriamiento %g s", spec.cooldown) }
		local damage = spec.damage or spec.tickDamage
		if damage then
			table.insert(parts, string.format("Daño %g%s", damage, if spec.tickDamage and not spec.damage then " por golpe" else ""))
		end
		if (spec.cost or 0) > 0 then
			table.insert(parts, string.format("Cuesta %d de Resonancia", spec.cost))
		end
		return table.concat(parts, "  ·  ")
	end
	-- Muestra la pista de la tecla `slot` del Eco puesto. `hold`: se queda mientras siga el ratón encima.
	local function showTip(slot, hold)
		local kit = ecoController.Kit()
		local spec = skills[kit.slots[slot] or ""]
		local s = slots[slot]
		if not spec or not s then
			return
		end
		local gamepad = UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad"
		local key = if gamepad then (eco.Gamepad[slot] or slot) else slot
		tipTitle.Text = string.format("%s  ·  %s", key, Texto.Mayusculas(spec.label))
		tipTitle.TextColor3 = kit.color
		tipDesc.Text = spec.desc or ""
		tipStats.Text = statsOf(spec)
		local airSpec = kit.air and kit.air[slot] and skills[kit.air[slot]]
		tipAir.Text = if airSpec then string.format("En el aire: %s — %s", Texto.Mayusculas(airSpec.label), airSpec.desc or "")
			elseif spec.retreat then "Retrocediendo (S): además das un paso atrás"
			else ""
		tipAir.TextColor3 = kit.color
		tipAir.Visible = airSpec ~= nil or spec.retreat == true
		tip.Size = UDim2.fromOffset(310, if tipAir.Visible then 104 else 86)
		tipStroke.Color = kit.color
		local frame = s.frame
		local position = frame.AbsolutePosition
		local guiInset = gui.AbsolutePosition
		tip.Position = UDim2.fromOffset(position.X - guiInset.X + frame.AbsoluteSize.X / 2, position.Y - guiInset.Y - 10)
		tip.Visible = true
		tipToken += 1
		local token = tipToken
		if not hold then
			task.delay(5, function()
				if token == tipToken then
					tip.Visible = false
				end
			end)
		end
	end
	SkillBarHUD.ShowTip = showTip
	if ecoController.InfoRequested then
		ecoController.InfoRequested:Connect(function(_, slot)
			if slot then
				showTip(slot, false)
			else
				showCard(true)
			end
		end)
	end
	-- Soltar Alt esconde la pista; con el ratón libre, pasar por encima de una casilla la muestra
	UserInputService.InputEnded:Connect(function(inputObject)
		if inputObject.KeyCode == Enum.KeyCode.LeftAlt or inputObject.KeyCode == Enum.KeyCode.RightAlt then
			hideTip()
		end
	end)
	for slot, s in pairs(slots) do
		if s.frame:IsA("GuiObject") and not s.frame:IsA("TextButton") then
			s.frame.Active = true
			s.frame.MouseEnter:Connect(function()
				showTip(slot, true)
			end)
			s.frame.MouseLeave:Connect(hideTip)
		end
	end
	ecoController.Used:Connect(function()
		if card.Visible then
			hideCard(0.15)
		end
	end)

	RunService.Heartbeat:Connect(function()
		local resonance = player:GetAttribute("Resonancia") or 0
		-- Lista de verdad: Resonancia suficiente Y la V sin enfriamiento (antes avisaba con la Resonancia aunque la V
		-- siguiera enfriándose). La espera corta del cambio de Eco no cuenta: si no, cada cambio repetiría el aviso.
		local ultimate = skills[ecoController.Kit().slots.V or ""]
		local ready = ultimate ~= nil and resonance >= (ultimate.cost or 0) and ecoController.OwnCooldown("V") <= 0
		if ready and wasReady == false then
			notice("¡DEFINITIVA LISTA! (V)")
			local s = slots.V
			if s then
				s.scale.Scale = 1.3
				TweenService:Create(s.scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				local sound = Instance.new("Sound")
				sound.SoundId = "rbxasset://sounds/volume_slider.ogg"
				sound.Volume = 0.5
				sound.Parent = root
				sound:Play()
				game:GetService("Debris"):AddItem(sound, 2)
			end
		end
		wasReady = ready
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
						s.name.Text = Texto.Mayusculas(spec.label)
					elseif s.frame:IsA("TextButton") then
						s.frame.Text = Texto.Mayusculas(spec.label)
					end
				end
			end
		end
		for slot, s in pairs(slots) do
			-- En el aire, la casilla con variante aérea muestra el enfriamiento de esa variante (es otro)
			local key = if air and kit.air and kit.air[slot] then slot .. "aire" else slot
			local remaining = ecoController.CooldownRemaining(key)
			local length = ecoController.State.cooldownLength[key] or 1
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
				-- En cola: la tecla se pulsó y saldrá en cuanto se pueda (borde blanco que late)
				local queued = ecoController.BufferedSlot and ecoController.BufferedSlot() == slot
				s.stroke.Color = if queued then QUEUED else kit.color
				s.stroke.Transparency = if queued then 0.2 * (1 + math.sin(os.clock() * 30)) elseif ready then 0 else 0.6
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
