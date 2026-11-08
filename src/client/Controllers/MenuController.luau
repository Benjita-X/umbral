-- MenuController: menú del juego (botón "MENÚ" arriba al centro, o tecla M / Select del mando).
--   · Controles: qué hace cada botón en PC, mando y celular (incluye habilidades y paredes).
--   · Ecos: elegir el Eco (sus 4 habilidades van en Z X C V). También con las teclas 1-5.
--   · Ajustes de accesibilidad, en vivo: vibración de cámara, destellos, números de daño, panel de
--     depuración. Cambian CombatConfig.Feedback en este cliente (se leen en el momento de usarse).
-- El mundo sigue en marcha (es un juego en línea): el menú no pausa la partida.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local configFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local CombatConfig = require(configFolder:WaitForChild("CombatConfig"))
local Texto = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Texto"))

local CameraController = require(script.Parent:WaitForChild("CameraController"))

local MenuController = {}

local player = Players.LocalPlayer
local BG = Color3.fromRGB(14, 16, 26)
local ACCENT = Color3.fromRGB(150, 255, 230)
local TEXT = Color3.fromRGB(235, 238, 248)

local CONTROLS = {
	{ "Moverse", "WASD", "Stick izq.", "Joystick" },
	{ "Atacar (pulsar: combo · mantener: golpe fuerte)", "Clic izq.", "X", "ATACAR" },
	{ "Defender (a tiempo: desvío · mantener: guardia)", "F", "R1", "DEFENDER" },
	{ "Paso · de lado justo antes de un golpe: Contrapaso", "Shift", "B", "PASO" },
	{ "Saltar · doble salto · junto a un muro: salto de pared", "Espacio", "A", "Saltar" },
	{ "Habilidad 1 del Eco (Viento: Cuchilla)", "Z", "Y", "Z" },
	{ "Habilidad 2 (Viento: Ciclón)", "X", "L1", "X" },
	{ "Habilidad 3 (Viento: Levante · otra vez: subir · aire: Descenso)", "C", "L2", "C" },
	{ "Definitiva (gasta Resonancia; Viento: Tempestad)", "V", "R2", "V" },
	{ "Cambiar de Eco", "1-5", "Cruceta", "Menú" },
	{ "Arma: Puños ↔ Espada", "Q", "Cruceta arriba", "ARMA" },
	{ "Gancho al orbe o enemigo marcado", "E", "Cruceta abajo", "GANCHO" },
	{ "Cámara fija (el personaje mira a la mira) / ratón libre", "Ctrl", "—", "—" },
	{ "Fijar enemigo (la cámara lo sigue) · tirón del ratón: cambiar", "R", "R3", "—" },
	{ "Ver qué hace una habilidad (sin lanzarla)", "Alt + Z X C V", "—", "—" },
	{ "Menú", "M", "Select", "MENÚ" },
}

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
	c.Parent = parent
end

local function label(parent, text, size, color, font, align)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Font = font or Enum.Font.Gotham
	l.Text = text
	l.TextColor3 = color or TEXT
	l.TextScaled = true
	l.TextWrapped = true
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

function MenuController.Start(movement, combat, debugHud, tutorial, ecoController)
	local toggle -- (se define abajo: abre o cierra el menú con todo lo que eso implica)
	local gui = Instance.new("ScreenGui")
	gui.Name = "UmbralMenu"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20

	-- Botón para abrir (sirve en todas las plataformas)
	local open = Instance.new("TextButton")
	open.Name = "AbrirMenu"
	-- Arriba al centro: arriba a la izquierda están los botones y el chat de Roblox
	open.AnchorPoint = Vector2.new(0.5, 0)
	open.Position = UDim2.new(0.5, 0, 0, 6)
	open.Size = UDim2.fromOffset(110, 30)
	open.BackgroundColor3 = BG
	open.BackgroundTransparency = 0.25
	open.Font = Enum.Font.GothamBold
	open.Text = "MENÚ (M)"
	open.TextColor3 = ACCENT
	open.TextScaled = true
	corner(open, 8)
	open.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.92, 0, 0.82, 0)
	panel.BackgroundColor3 = BG
	panel.BackgroundTransparency = 0.08
	panel.Visible = false
	corner(panel, 14)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(760, 560)
	limit.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 14)
	pad.PaddingBottom = UDim.new(0, 14)
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = panel
	panel.Parent = gui

	-- Contenido desplazable (en un celular horizontal no cabe todo) y el botón de volver fijo abajo
	-- (hallazgo #9 de Codex)
	local content = Instance.new("ScrollingFrame")
	content.Name = "Contenido"
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Size = UDim2.new(1, 0, 1, -46)
	content.CanvasSize = UDim2.new()
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ScrollBarThickness = 6
	content.ScrollingDirection = Enum.ScrollingDirection.Y
	content.Parent = panel
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = content

	local order = 0
	local function nextOrder(item)
		order += 1
		item.LayoutOrder = order
		return item
	end

	nextOrder(label(content, "UMBRAL · Despierta tu Eco", UDim2.new(1, 0, 0, 30), ACCENT, Enum.Font.GothamBlack))
	nextOrder(label(content, "CONTROLES   (PC · mando · celular)", UDim2.new(1, 0, 0, 18), Color3.fromRGB(170, 180, 205), Enum.Font.GothamBold))
	for _, row in ipairs(CONTROLS) do
		local line = Instance.new("Frame")
		line.BackgroundTransparency = 1
		line.Size = UDim2.new(1, 0, 0, 22)
		nextOrder(line)
		local action = label(line, row[1], UDim2.new(0.58, 0, 1, 0))
		action.Position = UDim2.fromScale(0, 0)
		local keys = label(line, string.format("%s  ·  %s  ·  %s", row[2], row[3], row[4]), UDim2.new(0.42, 0, 1, 0), ACCENT, Enum.Font.GothamBold, Enum.TextXAlignment.Right)
		keys.Position = UDim2.fromScale(0.58, 0)
		line.Parent = content
	end

	-- Ecos: cada uno pone sus 4 habilidades en Z X C V
	if ecoController then
		local eco = CombatConfig.Eco
		nextOrder(label(content, "ECOS   (elige uno · también con las teclas 1-" .. #eco.Order .. ")", UDim2.new(1, 0, 0, 18), Color3.fromRGB(170, 180, 205), Enum.Font.GothamBold))
		local ecoButtons = {}
		local details = nil -- qué hace cada tecla del Eco elegido (se rellena en refreshEcos)
		local function refreshEcos()
			for name, button in pairs(ecoButtons) do
				local kit = eco.Kits[name]
				local current = ecoController.KitName() == name
				button.BackgroundColor3 = if current then Color3.fromRGB(40, 52, 70) else Color3.fromRGB(24, 28, 42)
				button.TextColor3 = if current then kit.color else Color3.fromRGB(180, 186, 200)
				local stroke = button:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Enabled = current
					stroke.Color = kit.color
				end
			end
			if details then
				for _, child in ipairs(details:GetChildren()) do
					if child:IsA("TextLabel") then
						child:Destroy()
					end
				end
				local kit = ecoController.Kit()
				local rows = 0
				for _, slot in ipairs(eco.SlotOrder) do
					for _, entry in ipairs({ { kit.slots[slot], slot }, { kit.air and kit.air[slot], slot .. " en el aire" } }) do
						local skill = entry[1] and eco.Skills[entry[1]]
						if skill then
							rows += 1
							local row = label(details, string.format("%s · %s — %s", entry[2], Texto.Mayusculas(skill.label), skill.desc or ""), UDim2.new(1, 0, 0, 18), kit.color)
							row.Name = "Detalle" .. rows
							row.LayoutOrder = rows
						end
					end
				end
				if kit.reacts then
					rows += 1
					local row = label(details, "Reacción · " .. kit.reacts, UDim2.new(1, 0, 0, 18), kit.color)
					row.Name = "Detalle" .. rows
					row.LayoutOrder = rows
				end
				details.Size = UDim2.new(1, 0, 0, rows * 20)
			end
		end
		for index, name in ipairs(eco.Order) do
			local kit = eco.Kits[name]
			local parts = {}
			for _, slot in ipairs(eco.SlotOrder) do
				local skill = eco.Skills[kit.slots[slot]]
				table.insert(parts, skill and skill.label or "?")
			end
			local button = Instance.new("TextButton")
			button.Name = "Eco" .. name
			button.Size = UDim2.new(1, 0, 0, 34)
			button.Font = Enum.Font.GothamBold
			button.TextScaled = true
			button.TextWrapped = true
			button.Text = string.format("%d · %s  —  %s  (%s)", index, Texto.Mayusculas(kit.name), kit.role or "", table.concat(parts, ", "))
			corner(button, 8)
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 2
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Parent = button
			local padding = Instance.new("UIPadding")
			padding.PaddingLeft = UDim.new(0, 8)
			padding.PaddingRight = UDim.new(0, 8)
			padding.Parent = button
			button.Activated:Connect(function()
				ecoController.Equip(name)
				task.defer(refreshEcos)
			end)
			ecoButtons[name] = button
			nextOrder(button)
			button.Parent = content
		end
		-- Lo que hace cada tecla del Eco elegido
		details = Instance.new("Frame")
		details.Name = "DetallesEco"
		details.BackgroundTransparency = 1
		details.Size = UDim2.new(1, 0, 0, 100)
		local detailsList = Instance.new("UIListLayout")
		detailsList.Padding = UDim.new(0, 2)
		detailsList.SortOrder = Enum.SortOrder.LayoutOrder
		detailsList.Parent = details
		nextOrder(details)
		details.Parent = content
		refreshEcos()
		ecoController.KitChanged:Connect(refreshEcos)
	end

	-- Combos con nombre y reacciones entre elementos (salen de CombatConfig: nunca se desactualizan)
	do
		local eco = CombatConfig.Eco
		local attacks = CombatConfig.Attacks
		local function nameOf(skillOrAttack)
			local skill = eco.Skills[skillOrAttack]
			if skill then
				return skill.slot .. " " .. skill.label
			end
			local attack = attacks[skillOrAttack]
			return if attack and attack.label then attack.label else skillOrAttack
		end
		nextOrder(label(content, "COMBOS   (una técnica y enseguida la otra, sobre el mismo enemigo)", UDim2.new(1, 0, 0, 18), Color3.fromRGB(170, 180, 205), Enum.Font.GothamBold))
		for _, synergy in ipairs(eco.Synergies) do
			local line = label(content, string.format("%s  →  %s   =   %s", nameOf(synergy.first), nameOf(synergy.next), synergy.name), UDim2.new(1, 0, 0, 17), Color3.fromRGB(255, 215, 120))
			line.Name = "Combo" .. synergy.name
			nextOrder(line)
		end
		nextOrder(label(content, "REACCIONES   (cambia de Eco: Agua moja, Trueno carga, Fuego quema)", UDim2.new(1, 0, 0, 18), Color3.fromRGB(170, 180, 205), Enum.Font.GothamBold))
		for _, row in ipairs({
			{ "Mojado + Trueno", "ELECTROCUCIÓN: más daño y un rayo salta a otro" },
			{ "Mojado + Fuego", "VAPOR: explosión que empuja" },
			{ "Ardiendo + Viento", "TORMENTA ÍGNEA: el fuego se contagia" },
			{ "Cargado + Oscuridad", "PULSO UMBRÍO: implosión que atrae" },
			{ "Cargado + Agua", "CONDUCCIÓN: la descarga se reparte" },
		}) do
			nextOrder(label(content, row[1] .. "   =   " .. row[2], UDim2.new(1, 0, 0, 17), Color3.fromRGB(150, 220, 255)))
		end
		nextOrder(label(content, "Contra la pared: un empujón fuerte estampa (¡PARED!); otro empujón lo hace rebotar hacia ti. Aturdido: Paso = Liberación (40 de Resonancia).", UDim2.new(1, 0, 0, 30), Color3.fromRGB(200, 205, 220)))
	end

	nextOrder(label(content, "AJUSTES", UDim2.new(1, 0, 0, 18), Color3.fromRGB(170, 180, 205), Enum.Font.GothamBold))
	local feedback = CombatConfig.Feedback
	local debugStarted = false
	local settings = {
		{
			name = "Vibración de cámara",
			get = function()
				return feedback.ScreenShake > 0
			end,
			set = function(on)
				feedback.ScreenShake = if on then 1 else 0
			end,
		},
		{
			name = "Modo práctica: sin enfriamientos y Resonancia llena (solo Studio)",
			get = function()
				return Players.LocalPlayer:GetAttribute("Practica") == true
			end,
			set = function(on)
				local remote = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):FindFirstChild("Practica")
				if remote then
					remote:FireServer(on)
				end
			end,
		},
		{
			name = "Efectos reducidos (PC modesto o celular)",
			get = function()
				local ok, efectos = pcall(require, script.Parent:WaitForChild("EcoEfectos"))
				return ok and efectos.Reducidos == true
			end,
			set = function(on)
				local ok, efectos = pcall(require, script.Parent:WaitForChild("EcoEfectos"))
				if ok then
					efectos.Reducidos = on
				end
			end,
		},
		{
			name = "Destellos al golpear",
			get = function()
				return feedback.Flashes
			end,
			set = function(on)
				feedback.Flashes = on
			end,
		},
		{
			name = "Números de daño",
			get = function()
				return feedback.DamageNumbers
			end,
			set = function(on)
				feedback.DamageNumbers = on
			end,
		},
		{
			name = "Bordes rojos con poca vida",
			get = function()
				return feedback.LowHealthPulse ~= false
			end,
			set = function(on)
				feedback.LowHealthPulse = on
			end,
		},
		{
			name = "Marca de dónde vino el golpe",
			get = function()
				return feedback.HitIndicator ~= false
			end,
			set = function(on)
				feedback.HitIndicator = on
			end,
		},
		{
			name = "Cámara fija: el personaje mira a la mira (Ctrl)",
			get = function()
				return CameraController.IsLocked()
			end,
			set = function(on)
				CameraController.SetLocked(on)
			end,
		},
		{
			name = "Apuntar habilidades al ratón (NO = al frente)",
			get = function()
				return ecoController ~= nil and ecoController.State.aimMode == "raton"
			end,
			set = function(on)
				if ecoController then
					ecoController.SetAimMode(if on then "raton" else "frente")
				end
			end,
		},
		{
			name = "Panel de depuración",
			get = function()
				local hud = player.PlayerGui:FindFirstChild("UmbralDepuracion")
				return hud ~= nil and hud.Enabled
			end,
			set = function(on)
				local hud = player.PlayerGui:FindFirstChild("UmbralDepuracion")
				if on and not hud and not debugStarted and debugHud then
					debugStarted = true
					debugHud.Start(movement, combat)
					return
				end
				if hud then
					hud.Enabled = on
				end
			end,
		},
	}
	for _, setting in ipairs(settings) do
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(1, 0, 0, 30)
		button.BackgroundColor3 = Color3.fromRGB(28, 32, 48)
		button.Font = Enum.Font.GothamBold
		button.TextScaled = true
		button.TextColor3 = TEXT
		corner(button, 8)
		local function refresh()
			button.Text = string.format("%s:  %s", setting.name, if setting.get() then "SÍ" else "NO")
			button.TextColor3 = if setting.get() then ACCENT else Color3.fromRGB(150, 155, 170)
		end
		button.Activated:Connect(function()
			setting.set(not setting.get())
			task.defer(refresh)
		end)
		refresh()
		nextOrder(button)
		button.Parent = content
	end

	if tutorial then
		local again = Instance.new("TextButton")
		again.Size = UDim2.new(1, 0, 0, 30)
		again.BackgroundColor3 = Color3.fromRGB(28, 32, 48)
		again.Font = Enum.Font.GothamBold
		again.Text = "Repetir tutorial"
		again.TextScaled = true
		again.TextColor3 = ACCENT
		corner(again, 8)
		nextOrder(again)
		again.Parent = content
		again.Activated:Connect(function()
			tutorial.Restart()
			toggle(false)
		end)
	end

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(0, 1)
	close.Position = UDim2.new(0, 0, 1, 0)
	close.Size = UDim2.new(1, 0, 0, 38)
	close.BackgroundColor3 = Color3.fromRGB(30, 110, 100)
	close.Font = Enum.Font.GothamBlack
	close.Text = "VOLVER AL JUEGO"
	close.TextColor3 = TEXT
	close.TextScaled = true
	corner(close, 8)
	close.Parent = panel

	toggle = function(force)
		local visible = if force ~= nil then force else not panel.Visible
		panel.Visible = visible
		-- Con el menú abierto el ratón queda libre (la cámara fija se suspende), nada queda pulsado detrás y las
		-- acciones de combate no salen (un clic en sus botones ya no es también un golpe; Z/X/C/V no lanzan)
		CameraController.SetMouseFree("menu", visible)
		local ok, input = pcall(require, script.Parent:WaitForChild("InputController"))
		if ok and input.SetBlocked then
			input.SetBlocked("menu", visible)
		end
	end
	open.Activated:Connect(function()
		toggle()
	end)
	close.Activated:Connect(function()
		toggle(false)
	end)
	ContextActionService:BindAction("UmbralMenu", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			toggle()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.M, Enum.KeyCode.ButtonSelect)

	gui.Parent = player:WaitForChild("PlayerGui")
end

return MenuController
