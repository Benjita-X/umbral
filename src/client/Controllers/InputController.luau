-- InputController: traduce teclado, mando y pantalla táctil a las acciones del juego.
-- Emite ActionBegan(acción) al pulsar y ActionEnded(acción) al soltar.
--   Atacar      · clic izquierdo · X (mando) · botón ATACAR   (pulsar = combo, mantener = golpe fuerte)
--   Defender    · F · R1/RB (mando) · botón DEFENDER          (mantener = guardia)
--   Paso        · Shift · B (mando) · botón PASO
--   Saltar      · Espacio · A (mando) · botón de salto de Roblox
--   HabilidadZ/X/C/V · Z X C V · Y, L1, L2, R2 (mando) · un botón por habilidad: las del Eco puesto
--   Eco1..Eco5  · teclas 1-5 · cruceta izq./der. (EcoAnterior / EcoSiguiente): cambiar de Eco
--   Arma        · Q · cruceta arriba · botón ARMA: Puños ↔ Espada
--   Gancho      · E · cruceta abajo · botón GANCHO: engancharse al punto o enemigo marcado
--   FijarCamara · Ctrl: cámara fija (el personaje mira hacia la mira) o ratón libre
--   FijarObjetivo · R · R3: fijar al enemigo del centro de la pantalla (la cámara lo sigue)
-- El clic derecho NO se usa: en Roblox gira la cámara.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local InputController = {}

local beganEvent = Instance.new("BindableEvent")
local endedEvent = Instance.new("BindableEvent")
InputController.ActionBegan = beganEvent.Event
InputController.ActionEnded = endedEvent.Event

local held = {}

-- JumpRequest puede dispararse varias veces seguidas mientras se mantiene el salto:
-- solo cuenta como pulsación nueva si hubo una pausa mayor que esto.
local JUMP_REPEAT_GAP = 0.1
local lastJumpRequest = -math.huge

local function press(action)
	if held[action] then
		return
	end
	held[action] = true
	beganEvent:Fire(action)
end

local function release(action)
	if not held[action] then
		return
	end
	held[action] = nil
	endedEvent:Fire(action)
end

function InputController.IsHeld(action)
	return held[action] == true
end

-- Para botones propios y pruebas automáticas
function InputController.Press(action)
	if action == "Saltar" then
		beganEvent:Fire("Saltar")
	else
		press(action)
	end
end

function InputController.Release(action)
	release(action)
end

-- Pulsar y soltar enseguida (un toque)
function InputController.Trigger(action)
	InputController.Press(action)
	InputController.Release(action)
end

local function bind(action, ...)
	ContextActionService:BindAction("Umbral" .. action, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			press(action)
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			release(action)
		end
		return Enum.ContextActionResult.Sink
	end, false, ...)
end

-- ---------- Botones táctiles ----------
local TOUCH_BUTTONS = {
	-- dx, dy: desplazamiento del centro respecto al botón de salto, en tamaños de ese botón
	{ action = "Atacar", label = "ATACAR", dx = -1.15, dy = 0.05, scale = 1.1, color = Color3.fromRGB(150, 40, 40) },
	{ action = "Paso", label = "PASO", dx = -0.2, dy = -1.05, scale = 0.8, color = Color3.fromRGB(28, 36, 58) },
	{ action = "Defender", label = "DEFENDER", dx = -1.3, dy = -1.0, scale = 0.8, color = Color3.fromRGB(40, 90, 70) },
	-- Habilidades del Eco: un arco a la izquierda (EcoController les pone el nombre y el enfriamiento)
	{ action = "HabilidadZ", label = "Z", dx = -2.3, dy = 0.3, scale = 0.72, color = Color3.fromRGB(30, 96, 90) },
	{ action = "HabilidadX", label = "X", dx = -2.4, dy = -0.62, scale = 0.72, color = Color3.fromRGB(30, 96, 90) },
	{ action = "HabilidadC", label = "C", dx = -2.05, dy = -1.52, scale = 0.72, color = Color3.fromRGB(30, 96, 90) },
	{ action = "HabilidadV", label = "V", dx = -1.15, dy = -1.98, scale = 0.8, color = Color3.fromRGB(90, 70, 30) },
	{ action = "Arma", label = "ARMA", dx = -0.1, dy = -2.0, scale = 0.6, color = Color3.fromRGB(70, 60, 50) },
	{ action = "Gancho", label = "GANCHO", dx = 0.7, dy = -1.75, scale = 0.6, color = Color3.fromRGB(30, 100, 95) },
	{ action = "FijarObjetivo", label = "FIJAR", dx = 0.7, dy = -2.6, scale = 0.55, color = Color3.fromRGB(110, 40, 40) },
}

local function makeButton(spec, gui)
	local button = Instance.new("TextButton")
	button.Name = spec.action
	button.Text = spec.label
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.TextColor3 = Color3.fromRGB(240, 244, 255)
	button.BackgroundColor3 = spec.color
	button.BackgroundTransparency = 0.2
	button.AutoButtonColor = true
	button.AnchorPoint = Vector2.new(0.5, 0.5)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.5
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.16, 0)
	padding.PaddingRight = UDim.new(0.16, 0)
	padding.Parent = button

	-- Responde al tocar (sin esperar a soltar) y suelta aunque el dedo se salga del botón
	button.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		press(spec.action)
		local connection
		connection = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
			if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then
				connection:Disconnect()
				release(spec.action)
			end
		end)
	end)

	button.Parent = gui
	return button
end

local function createTouchButtons()
	local gui = Instance.new("ScreenGui")
	gui.Name = "UmbralControlesTactiles"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5

	local buttons = {}
	for _, spec in ipairs(TOUCH_BUTTONS) do
		buttons[spec] = makeButton(spec, gui)
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Posición de respaldo (si no aparece el botón de salto de Roblox)
	local function placeFallback()
		local size = 70
		for spec, button in pairs(buttons) do
			button.Size = UDim2.fromOffset(size * spec.scale, size * spec.scale)
			button.Position = UDim2.new(1, -60 + spec.dx * size, 1, -60 + spec.dy * size)
		end
	end
	placeFallback()

	local touchGui = Players.LocalPlayer.PlayerGui:WaitForChild("TouchGui", 10)
	local jumpButton = touchGui and touchGui:FindFirstChild("JumpButton", true)
	if not jumpButton then
		return
	end
	gui.IgnoreGuiInset = touchGui.IgnoreGuiInset
	local function reposition()
		local size = jumpButton.AbsoluteSize.X
		local center = jumpButton.AbsolutePosition + jumpButton.AbsoluteSize / 2
		for spec, button in pairs(buttons) do
			local s = math.floor(size * spec.scale)
			button.Size = UDim2.fromOffset(s, s)
			button.Position = UDim2.fromOffset(center.X + spec.dx * size, center.Y + spec.dy * size)
		end
	end
	reposition()
	jumpButton:GetPropertyChangedSignal("AbsolutePosition"):Connect(reposition)
	jumpButton:GetPropertyChangedSignal("AbsoluteSize"):Connect(reposition)
end

function InputController.Start()
	bind("Atacar", Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonX)
	bind("Defender", Enum.KeyCode.F, Enum.KeyCode.ButtonR1)
	bind("Paso", Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonB)
	bind("HabilidadZ", Enum.KeyCode.Z, Enum.KeyCode.ButtonY)
	bind("HabilidadX", Enum.KeyCode.X, Enum.KeyCode.ButtonL1)
	bind("HabilidadC", Enum.KeyCode.C, Enum.KeyCode.ButtonL2)
	bind("HabilidadV", Enum.KeyCode.V, Enum.KeyCode.ButtonR2)
	local numbers = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five }
	for i, key in ipairs(numbers) do
		bind("Eco" .. i, key)
	end
	bind("Arma", Enum.KeyCode.Q, Enum.KeyCode.DPadUp)
	bind("Gancho", Enum.KeyCode.E, Enum.KeyCode.DPadDown)
	bind("FijarCamara", Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl)
	bind("FijarObjetivo", Enum.KeyCode.R, Enum.KeyCode.ButtonR3)
	bind("EcoAnterior", Enum.KeyCode.DPadLeft)
	bind("EcoSiguiente", Enum.KeyCode.DPadRight)

	UserInputService.JumpRequest:Connect(function()
		local now = os.clock()
		local isNewPress = (now - lastJumpRequest) > JUMP_REPEAT_GAP
		lastJumpRequest = now
		if isNewPress then
			beganEvent:Fire("Saltar")
		end
	end)

	if UserInputService.TouchEnabled then
		task.spawn(createTouchButtons)
	end
end

return InputController
