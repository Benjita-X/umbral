-- CameraController: cámara de tercera persona de Roblox con campo de visión dinámico y vibración.
-- El FOV se abre un poco en sprint y da un golpe breve al iniciar un Paso, para sentir la velocidad.
-- La vibración usa Humanoid.CameraOffset (no pelea con la cámara de Roblox) y se puede apagar en
-- CombatConfig.Feedback.ScreenShake.
--
-- CÁMARA FIJA (PC, EXPERIMENTAL): el ratón queda al centro con una mira, la cámara va sobre el hombro y el
-- personaje mira hacia donde apunta la cámara (como en los juegos de pelea con bloqueo de cámara). Golpes y
-- habilidades salen hacia la mira. Ctrl la activa o la suelta; viene activada en PC. El menú suelta el ratón
-- mientras está abierto. Con mando o en el celular no se usa (la cámara de Roblox ya va bien ahí).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local configFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Config = require(configFolder:WaitForChild("MovementConfig"))
local CombatConfig = require(configFolder:WaitForChild("CombatConfig"))

local CameraController = {}

local trauma = 0 -- 0..1; la vibración crece con su cuadrado (golpes chicos casi no se notan)
local seed = math.random() * 1000

-- ---------- Cámara fija ----------
local SHOULDER = Vector3.new(1.75, 0.4, 0) -- la cámara sobre el hombro derecho
local lockChangedEvent = Instance.new("BindableEvent")
CameraController.LockChanged = lockChangedEvent.Event
local locked = false -- lo que eligió el jugador
local mouseFree = {} -- [clave] = true: algo (el menú) necesita el ratón libre
local lockActive = false -- si está aplicada ahora mismo
local movementRef = nil
local crosshair = nil

local function usingMouse()
	local last = UserInputService:GetLastInputType()
	return last == Enum.UserInputType.Keyboard
		or last == Enum.UserInputType.MouseMovement
		or last == Enum.UserInputType.MouseButton1
		or last == Enum.UserInputType.MouseButton2
		or last == Enum.UserInputType.MouseButton3
		or last == Enum.UserInputType.MouseWheel
end

function CameraController.SetLocked(on)
	locked = on == true
	lockChangedEvent:Fire(locked)
end

function CameraController.IsLocked()
	return locked
end

-- Algo de la interfaz necesita el ratón libre (el menú): mientras tanto la cámara fija se suspende
function CameraController.SetMouseFree(key, free)
	mouseFree[key] = if free then true else nil
end

local function buildCrosshair()
	local gui = Instance.new("ScreenGui")
	gui.Name = "UmbralMira"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 4
	gui.Enabled = false
	local function bar(size, position)
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Size = size
		frame.Position = position
		frame.BackgroundColor3 = Color3.fromRGB(240, 245, 255)
		frame.BorderSizePixel = 0
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Transparency = 0.4
		stroke.Thickness = 1
		stroke.Parent = frame
		frame.Parent = gui
	end
	-- Una cruz pequeña con un hueco al centro
	bar(UDim2.fromOffset(2, 7), UDim2.new(0.5, 0, 0.5, -7))
	bar(UDim2.fromOffset(2, 7), UDim2.new(0.5, 0, 0.5, 7))
	bar(UDim2.fromOffset(7, 2), UDim2.new(0.5, -7, 0.5, 0))
	bar(UDim2.fromOffset(7, 2), UDim2.new(0.5, 7, 0.5, 0))
	local hint = Instance.new("TextLabel")
	hint.Name = "Ayuda"
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.new(0.5, 0, 0.5, 20)
	hint.Size = UDim2.fromOffset(240, 16)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamBold
	hint.TextScaled = true
	hint.TextColor3 = Color3.fromRGB(220, 226, 240)
	hint.TextStrokeTransparency = 0.4
	hint.Text = "Ctrl: soltar el ratón"
	hint.Parent = gui
	task.delay(6, function()
		hint.Visible = false
	end)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

-- Añade vibración (0..1). Los golpes fuertes dan más.
function CameraController.Shake(amount)
	trauma = math.clamp(trauma + amount * CombatConfig.Feedback.ScreenShake, 0, 1)
end

-- Golpe de FOV breve desde otros sistemas (gancho, definitivas): se suma al del Paso y se apaga solo
local externalKick = 0
function CameraController.Kick(amount)
	externalKick = math.max(externalKick, amount)
end

-- Vibración actual como desplazamiento (la cámara fijada a un enemigo la suma a su posición)
local currentShake = Vector3.zero
function CameraController.ShakeOffset()
	return currentShake
end

function CameraController.Start(movement, input)
	local player = Players.LocalPlayer
	player.CameraMinZoomDistance = 6
	player.CameraMaxZoomDistance = 40
	movementRef = movement

	-- Cámara fija: activada de entrada en PC (teclado y ratón)
	locked = UserInputService.KeyboardEnabled and UserInputService.MouseEnabled
	if input then
		input.ActionBegan:Connect(function(action)
			if action == "FijarCamara" then
				CameraController.SetLocked(not locked)
			end
		end)
	end
	crosshair = buildCrosshair()
	-- Se aplica DESPUÉS de la cámara de Roblox en cada cuadro (si no, ella vuelve a soltar el ratón)
	RunService:BindToRenderStep("UmbralCamaraFija", Enum.RenderPriority.Camera.Value + 1, function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local active = locked and next(mouseFree) == nil and usingMouse() and humanoid ~= nil and humanoid.Health > 0
		if active then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		elseif lockActive then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
		if active ~= lockActive then
			lockActive = active
			UserInputService.MouseIconEnabled = not active
			crosshair.Enabled = active
			if movementRef and movementRef.SetCameraFacing then
				movementRef.SetCameraFacing(active)
			end
		end
	end)

	local kick = 0
	movement.Dashed:Connect(function()
		kick = Config.DashFOVKick
	end)
	-- Paredes: el salto de pared y el agarre dan un golpe de FOV más chico; correr por la pared, uno largo
	if movement.WallJumped then
		movement.WallJumped:Connect(function()
			kick = math.max(kick, Config.DashFOVKick * 0.7)
		end)
		movement.Mantled:Connect(function()
			kick = math.max(kick, Config.DashFOVKick * 0.4)
		end)
		movement.WallRunStarted:Connect(function()
			kick = math.max(kick, Config.DashFOVKick)
		end)
	end
	-- Gancho: golpe de FOV al salir disparado
	if movement.Grappled then
		movement.Grappled:Connect(function()
			kick = math.max(kick, Config.DashFOVKick * 1.2)
		end)
	end

	local shakeHumanoid = nil
	RunService.RenderStepped:Connect(function(dt)
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		kick *= math.exp(-10 * dt)
		externalKick *= math.exp(-6 * dt)
		local fast = movement.State.sprinting or movement.State.wallRunning or movement.State.grappling
		local target = (if fast then Config.SprintFOV else Config.BaseFOV) + math.max(kick, externalKick)
		local alpha = 1 - math.exp(-Config.FOVResponsiveness * dt)
		camera.FieldOfView += (target - camera.FieldOfView) * alpha

		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		-- Con la cámara fija, la cámara va sobre el hombro (la vibración se suma encima)
		local base = if lockActive then SHOULDER else Vector3.zero
		if trauma > 0 and humanoid then
			local t = os.clock() * 30
			local strength = trauma * trauma * CombatConfig.Feedback.MaxShakeOffset
			currentShake = Vector3.new(
				math.noise(t, seed) * strength,
				math.noise(t, seed + 17) * strength,
				math.noise(t, seed + 33) * strength * 0.5
			)
			humanoid.CameraOffset = base + currentShake
			shakeHumanoid = humanoid
			trauma = math.max(0, trauma - dt * 3.2)
		elseif humanoid then
			currentShake = Vector3.zero
			if humanoid.CameraOffset ~= base then
				humanoid.CameraOffset = base
			end
			shakeHumanoid = nil
		end
	end)
end

return CameraController
