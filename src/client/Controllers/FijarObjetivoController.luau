-- FijarObjetivoController: fijar un enemigo (EXPERIMENTAL), como en los juegos de acción con espada.
--   · R (mando: R3) fija al enemigo más cercano al centro de la pantalla (hasta 45 studs, con línea de visión).
--   · La cámara lo sigue sola por encima del hombro y el personaje lo encara siempre: golpes, habilidades y
--     desvíos van hacia él. Moverse en círculo alrededor del enemigo es natural (WASD relativo a la cámara).
--   · R otra vez lo suelta. También se suelta solo si el enemigo cae, se aleja demasiado o queda tapado un rato.
--   · Mientras está fijado, mover el ratón hacia un lado (un tirón) cambia al siguiente enemigo de ese lado.
-- Usa la cámara en modo Scriptable solo mientras dura; al soltar vuelve la cámara normal de Roblox.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local FijarObjetivoController = {}

local RANGE = 45
local KEEP_RANGE = 55
local DISTANCE = 13 -- distancia de la cámara detrás del jugador
local HEIGHT = 4.5
local SHOULDER = 2.2
local LOST_SIGHT_TIME = 1.2
local FLICK = 140 -- píxeles de tirón del ratón para cambiar de enemigo

local player = Players.LocalPlayer
local target = nil
local lostSince = nil
local marker = nil
local cameraController, movement = nil, nil
local flickAccum = 0
local lastSwitch = 0

local changedEvent = Instance.new("BindableEvent")
FijarObjetivoController.Changed = changedEvent.Event

local function rootPart()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function targetRoot(model)
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if humanoid and root and humanoid.Health > 0 and model:IsDescendantOf(Workspace) then
		return root
	end
	return nil
end

local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude
sightParams.RespectCanCollide = true
local function visible(from, model)
	local root = targetRoot(model)
	if not root then
		return false
	end
	sightParams.FilterDescendantsInstances = { player.Character, model, Workspace.CurrentCamera }
	return Workspace:Raycast(from, root.Position - from, sightParams) == nil
end

local function candidates()
	local list = {}
	for _, model in ipairs(CollectionService:GetTagged("Objetivo")) do
		if model ~= player.Character and targetRoot(model) then
			table.insert(list, model)
		end
	end
	return list
end

-- El enemigo más cercano al centro de la pantalla (o, con `side`, el siguiente hacia ese lado del actual)
local function pick(side)
	local root = rootPart()
	local camera = Workspace.CurrentCamera
	if not root or not camera then
		return nil
	end
	local eye = root.Position + Vector3.new(0, 1.5, 0)
	local best, bestScore = nil, math.huge
	local currentScreenX = nil
	if side and target then
		local currentRoot = targetRoot(target)
		if currentRoot then
			currentScreenX = camera:WorldToViewportPoint(currentRoot.Position).X
		end
	end
	local viewport = camera.ViewportSize
	for _, model in ipairs(candidates()) do
		if model ~= target or not side then
			local enemyRoot = targetRoot(model)
			local distance = (enemyRoot.Position - root.Position).Magnitude
			if distance <= RANGE then
				local screen, onScreen = camera:WorldToViewportPoint(enemyRoot.Position)
				if onScreen and visible(eye, model) then
					local dx = screen.X - viewport.X / 2
					local dy = screen.Y - viewport.Y / 2
					local score = math.sqrt(dx * dx + dy * dy) + distance * 3
					if side and currentScreenX then
						local offset = screen.X - currentScreenX
						if (side > 0 and offset <= 10) or (side < 0 and offset >= -10) then
							score = math.huge -- no está hacia ese lado
						else
							score = math.abs(offset) + distance * 2
						end
					end
					if score < bestScore then
						best, bestScore = model, score
					end
				end
			end
		end
	end
	return best
end

local function buildMarker()
	local gui = Instance.new("BillboardGui")
	gui.Name = "UmbralFijado"
	gui.Size = UDim2.fromOffset(34, 34)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Enabled = false
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(12, 12)
	dot.Rotation = 45
	dot.BackgroundColor3 = Color3.fromRGB(255, 80, 70)
	dot.BorderSizePixel = 0
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 2
	stroke.Parent = dot
	dot.Parent = gui
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(1, 1)
	ring.BackgroundTransparency = 1
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ring
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = Color3.fromRGB(255, 80, 70)
	ringStroke.Thickness = 2
	ringStroke.Transparency = 0.3
	ringStroke.Parent = ring
	ring.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui
end

local function release()
	if not target then
		return
	end
	target = nil
	lostSince = nil
	marker.Enabled = false
	if movement and movement.SetLockedTarget then
		movement.SetLockedTarget(nil)
	end
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
	if cameraController and cameraController.SetMouseFree then
		cameraController.SetMouseFree("fijar", false)
	end
	changedEvent:Fire(nil)
end

local function lockOn(model)
	if not model then
		return false
	end
	target = model
	lostSince = nil
	flickAccum = 0
	marker.Adornee = targetRoot(model)
	marker.Enabled = true
	if movement and movement.SetLockedTarget then
		movement.SetLockedTarget(model)
	end
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	changedEvent:Fire(model)
	return true
end

function FijarObjetivoController.Target()
	return target
end

function FijarObjetivoController.Toggle()
	if target then
		release()
		return nil
	end
	local model = pick(nil)
	lockOn(model)
	return model
end

-- Para pruebas: fijar uno concreto (o nil para soltar)
function FijarObjetivoController.LockOn(model)
	if model == nil then
		release()
		return true
	end
	return lockOn(model)
end

function FijarObjetivoController.Start(input, movementController, camera)
	movement, cameraController = movementController, camera
	marker = buildMarker()
	input.ActionBegan:Connect(function(action)
		if action == "FijarObjetivo" then
			FijarObjetivoController.Toggle()
		end
	end)
	-- Tirón del ratón hacia un lado: siguiente enemigo de ese lado
	UserInputService.InputChanged:Connect(function(inputObject)
		if not target or inputObject.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end
		flickAccum = flickAccum * 0.85 + inputObject.Delta.X
		if math.abs(flickAccum) > FLICK and os.clock() - lastSwitch > 0.35 then
			local nextModel = pick(if flickAccum > 0 then 1 else -1)
			flickAccum = 0
			if nextModel then
				lastSwitch = os.clock()
				lockOn(nextModel)
			end
		end
	end)
	player.CharacterAdded:Connect(release)

	local cameraCFrame = nil
	RunService:BindToRenderStep("UmbralFijarObjetivo", Enum.RenderPriority.Camera.Value + 2, function(dt)
		if not target then
			cameraCFrame = nil
			return
		end
		local root = rootPart()
		local enemyRoot = targetRoot(target)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not root or not enemyRoot or not humanoid or humanoid.Health <= 0 then
			release()
			return
		end
		local offset = enemyRoot.Position - root.Position
		if offset.Magnitude > KEEP_RANGE then
			release()
			return
		end
		-- Tapado un rato por una pared: se suelta
		if visible(root.Position + Vector3.new(0, 1.5, 0), target) then
			lostSince = nil
		else
			lostSince = lostSince or os.clock()
			if os.clock() - lostSince > LOST_SIGHT_TIME then
				release()
				return
			end
		end
		local camera = Workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		local flatDir = Vector3.new(offset.X, 0, offset.Z)
		flatDir = if flatDir.Magnitude > 0.1 then flatDir.Unit else Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
		local right = Vector3.new(-flatDir.Z, 0, flatDir.X)
		local position = root.Position - flatDir * DISTANCE + Vector3.new(0, HEIGHT, 0) + right * SHOULDER
		-- La cámara no se mete dentro de las paredes: se acerca si algo tapa
		sightParams.FilterDescendantsInstances = { player.Character, target, camera }
		local pivot = root.Position + Vector3.new(0, 2.5, 0)
		local hit = Workspace:Raycast(pivot, position - pivot, sightParams)
		if hit then
			position = hit.Position + (pivot - hit.Position).Unit * 0.6
		end
		local lookAt = enemyRoot.Position:Lerp(root.Position, 0.25) + Vector3.new(0, 1, 0)
		local desired = CFrame.lookAt(position, lookAt)
		cameraCFrame = if cameraCFrame then cameraCFrame:Lerp(desired, 1 - math.exp(-12 * dt)) else desired
		-- La vibración de los golpes también se ve con la cámara fijada
		local shake = if cameraController and cameraController.ShakeOffset then cameraController.ShakeOffset() else Vector3.zero
		camera.CFrame = cameraCFrame * CFrame.new(shake)
	end)
end

return FijarObjetivoController
