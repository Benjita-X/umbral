-- GanchoController: el gancho (EXPERIMENTAL). E (mando: cruceta abajo · celular: botón GANCHO) te engancha al
-- punto de enganche que tengas en la mira (orbes "PuntoGancho" del mapa) o a un enemigo, y te lleva hasta allí.
--   · Un marco circular con la tecla marca a qué te engancharías (como en los juegos de acción con gancho).
--   · Al llegar a un enganche sales impulsado hacia adelante y arriba, con el doble salto y el Paso aéreo
--     recargados: se encadena con saltos, paredes y más ganchos.
--   · Al llegar a un enemigo quedas frente a él y el siguiente golpe sale como golpe tras el Paso (patada
--     voladora o estocada en carrera).
-- El movimiento lo simula este cliente (MovementController.Grapple); el servidor vigila las velocidades.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local GanchoController = {}

local POINT_RANGE = 50
local ENEMY_RANGE = 32
local CONE = 38 -- grados alrededor del centro de la cámara
local COOLDOWN = 0.8
local SPEED = 95
local COLOR = Color3.fromRGB(120, 255, 230)

local player = Players.LocalPlayer
local anchors = {}
local movement, combat = nil, nil
local current = nil -- { target, enemy }
local lastUse = -math.huge
local marker, rope, ropeA0, ropeA1 = nil, nil, nil, nil

local function rootPart()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function addAnchor(instance)
	if instance:IsA("BasePart") and instance.Name == "PuntoGancho" and not table.find(anchors, instance) then
		table.insert(anchors, instance)
	end
end

local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude
sightParams.RespectCanCollide = true
local function clearSight(from, to, ignore)
	local list = { player.Character, Workspace.CurrentCamera }
	if ignore then
		table.insert(list, ignore)
	end
	sightParams.FilterDescendantsInstances = list
	local hit = Workspace:Raycast(from, to - from, sightParams)
	return hit == nil
end

local function enemyRoot(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if humanoid and root and humanoid.Health > 0 then
		return root
	end
	return nil
end

-- El enganche más cercano al centro de la cámara (puntos del mapa o enemigos), con línea de visión
local function bestTarget()
	local root = rootPart()
	local camera = Workspace.CurrentCamera
	if not root or not camera then
		return nil
	end
	local eye = root.Position + Vector3.new(0, 1.5, 0)
	local look = camera.CFrame.LookVector
	local best, bestScore, bestEnemy = nil, math.huge, false
	local function consider(target, position, range, enemy, ignore)
		local offset = position - root.Position
		local distance = offset.Magnitude
		-- A los enemigos que ya tienes encima no hace falta engancharse (y el marco estorbaría en el combate)
		if distance > range or distance < (if enemy then 9 else 5) then
			return
		end
		local fromCamera = (position - camera.CFrame.Position).Unit
		local angle = math.deg(math.acos(math.clamp(fromCamera:Dot(look), -1, 1)))
		if angle > CONE then
			return
		end
		local score = angle * 1.5 + distance * 0.25 + (if enemy then 4 else 0)
		if score < bestScore and clearSight(eye, position, ignore) then
			best, bestScore, bestEnemy = target, score, enemy
		end
	end
	for _, anchor in ipairs(anchors) do
		if anchor.Parent then
			consider(anchor, anchor.Position, POINT_RANGE, false, anchor)
		end
	end
	for _, model in ipairs(CollectionService:GetTagged("Objetivo")) do
		local targetRoot = enemyRoot(model)
		if targetRoot and model ~= player.Character then
			consider(model, targetRoot.Position, ENEMY_RANGE, true, model)
		end
	end
	return best, bestEnemy
end

local function positionOf(target)
	if typeof(target) ~= "Instance" or not target.Parent then
		return nil
	end
	if target:IsA("BasePart") then
		return target.Position
	end
	local root = enemyRoot(target)
	return root and root.Position
end

-- ---------- Marco y cuerda ----------
local function buildMarker()
	local gui = Instance.new("BillboardGui")
	gui.Name = "UmbralMarcoGancho"
	gui.Size = UDim2.fromOffset(46, 46)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Enabled = false
	local ring = Instance.new("Frame")
	ring.Size = UDim2.fromScale(1, 1)
	ring.BackgroundTransparency = 1
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR
	stroke.Thickness = 3
	stroke.Parent = ring
	ring.Parent = gui
	local key = Instance.new("TextLabel")
	key.Name = "Tecla"
	key.AnchorPoint = Vector2.new(0.5, 0.5)
	key.Position = UDim2.fromScale(0.5, 0.5)
	key.Size = UDim2.fromScale(0.55, 0.55)
	key.BackgroundTransparency = 1
	key.Font = Enum.Font.GothamBlack
	key.TextScaled = true
	key.TextColor3 = COLOR
	key.TextStrokeTransparency = 0.3
	key.Text = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "" else "E"
	key.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui
end

local function showRope(target)
	local character = player.Character
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("HumanoidRootPart"))
	if not hand then
		return
	end
	if rope then
		rope:Destroy()
		ropeA0:Destroy()
		ropeA1:Destroy()
	end
	ropeA0 = Instance.new("Attachment")
	ropeA0.Parent = hand
	ropeA1 = Instance.new("Attachment")
	local targetPart = if target:IsA("BasePart") then target else target:FindFirstChild("HumanoidRootPart")
	ropeA1.Parent = targetPart
	rope = Instance.new("Beam")
	rope.Attachment0 = ropeA0
	rope.Attachment1 = ropeA1
	rope.Color = ColorSequence.new(COLOR)
	rope.LightEmission = 1
	rope.Width0 = 0.18
	rope.Width1 = 0.1
	rope.FaceCamera = true
	rope.Segments = 1
	rope.Parent = hand
end

local function hideRope()
	if rope then
		rope:Destroy()
		ropeA0:Destroy()
		ropeA1:Destroy()
		rope, ropeA0, ropeA1 = nil, nil, nil
	end
end

local function playSound(position)
	local root = rootPart()
	if not root then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxasset://sounds/action_jump.mp3"
	sound.Volume = 0.5
	sound.PlaybackSpeed = 2.6
	sound.Parent = root
	sound:Play()
	game:GetService("Debris"):AddItem(sound, 2)
	local _ = position
end

-- Engancharse a un objetivo concreto (lo usan la tecla y las pruebas)
function GanchoController.GrappleTo(target)
	if not movement or os.clock() - lastUse < COOLDOWN or not positionOf(target) then
		return false
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or (combat and combat.State.mode == "Aturdido") then
		return false
	end
	local enemy = not target:IsA("BasePart")
	if combat then
		combat.CancelForSkill()
	end
	local ok = movement.Grapple(function()
		return positionOf(target)
	end, enemy, SPEED)
	if ok then
		lastUse = os.clock()
		showRope(target)
		playSound(positionOf(target))
		-- El servidor anota la hora del gancho (al llegar a un enemigo, el siguiente golpe sale como golpe tras el Paso)
		local remote = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
		remote = remote and remote:FindFirstChild("Gancho")
		if remote then
			remote:FireServer(Workspace:GetServerTimeNow())
		end
	end
	return ok
end

function GanchoController.Target()
	return current and current.target, current and current.enemy
end

function GanchoController.Start(input, movementController, combatController)
	movement, combat = movementController, combatController
	for _, instance in ipairs(Workspace:GetDescendants()) do
		addAnchor(instance)
	end
	Workspace.DescendantAdded:Connect(addAnchor)
	marker = buildMarker()

	input.ActionBegan:Connect(function(action)
		if action == "Gancho" and current then
			GanchoController.GrappleTo(current.target)
		end
	end)
	movement.GrappleEnded:Connect(function(wasEnemy)
		hideRope()
		-- Llegar a un enemigo deja listo el golpe tras el Paso (patada voladora / estocada en carrera)
		if wasEnemy and combat then
			combat.State.lastDash = os.clock()
		end
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.05 then
			return
		end
		elapsed = 0
		local target, enemy = bestTarget()
		current = if target then { target = target, enemy = enemy } else nil
		local ready = os.clock() - lastUse >= COOLDOWN and not movement.State.grappling
		if target and ready then
			local adornee = if target:IsA("BasePart") then target else target:FindFirstChild("HumanoidRootPart")
			marker.Adornee = adornee
			marker.Enabled = true
		else
			marker.Enabled = false
		end
	end)
	player.CharacterAdded:Connect(hideRope)
end

return GanchoController
