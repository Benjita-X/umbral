-- MenuController: menú del juego (botón "MENÚ" arriba al centro, o tecla M / Select del mando).
--   · Controles: qué hace cada botón en PC, mando y celular (incluye Eco y paredes).
--   · Ajustes de accesibilidad, en vivo: vibración de cámara, destellos, números de daño, panel de
--     depuración. Cambian CombatConfig.Feedback en este cliente (se leen en el momento de usarse).
-- El mundo sigue en marcha (es un juego en línea): el menú no pausa la partida.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local configFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local CombatConfig = require(configFolder:WaitForChild("CombatConfig"))

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
	{ "Eco · suelo: Ráfaga · aire: Descenso (cuesta Resonancia)", "Q", "Y", "ECO" },
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

function MenuController.Start(movement, combat, debugHud, tutorial)
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
			panel.Visible = false
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

	local function toggle(force)
		local visible = if force ~= nil then force else not panel.Visible
		panel.Visible = visible
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
