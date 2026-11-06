-- DummyService: muñecos del Dojo y base de cualquier personaje de práctica (el compañero de combate
-- de la Fase 3 también se crea con DummyService.Spawn).
-- Personajes R15 con barra de vida que NO mueren (se quedan en 0), se recuperan solos al dejar de
-- recibir golpes y vuelven a su sitio después de un empuje.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(shared:WaitForChild("Config"):WaitForChild("CombatConfig"))
local Rig = require(shared:WaitForChild("Combat"):WaitForChild("Rig"))
local PositionService = require(script.Parent:WaitForChild("PositionService"))

local PhysicsService = game:GetService("PhysicsService")

local DummyService = {}

-- Los luchadores (jugadores, muñecos, enemigos) no chocan entre sí: se atraviesan, como en los juegos de
-- pelea. Sí chocan con el escenario. Evita que un enemigo que se lanza contra el jugador salga disparado
-- por la física o quede bloqueado al volver a su sitio. Los golpes no dependen de colisiones (Hurtbox).
local FIGHTERS = "Luchadores"
local groupReady = false
local function ensureGroup()
	if groupReady then
		return
	end
	groupReady = true
	pcall(function()
		PhysicsService:RegisterCollisionGroup(FIGHTERS)
	end)
	PhysicsService:CollisionGroupSetCollidable(FIGHTERS, FIGHTERS, false)
end

function DummyService.MarkFighter(model)
	ensureGroup()
	local function mark(part)
		if part:IsA("BasePart") then
			part.CollisionGroup = FIGHTERS
		end
	end
	for _, part in ipairs(model:GetDescendants()) do
		mark(part)
	end
	model.DescendantAdded:Connect(mark)
end

local WOOD = Color3.fromRGB(178, 134, 86)
local WOOD_DARK = Color3.fromRGB(140, 102, 64)
local settings = CombatConfig.Dummy
local dummies = {} -- [model] = { spawn, lastHit, lastHealth, humanoid, root, maxHealth }

local function buildR15(bodyColor, legColor)
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = bodyColor
	description.TorsoColor = bodyColor
	description.LeftArmColor = bodyColor
	description.RightArmColor = bodyColor
	description.LeftLegColor = legColor
	description.RightLegColor = legColor
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15)
	end)
	if ok and model then
		return model
	end
	warn("[UMBRAL] No se pudo crear un personaje R15 (" .. tostring(model) .. "); uso uno de bloques")
	return nil
end

-- Respaldo sin conexión: un muñeco de bloques (sin articulaciones, no anima)
local function buildBlocky(bodyColor)
	local model = Instance.new("Model")
	local function block(name, size, offset)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Color = bodyColor
		part.CFrame = CFrame.new(offset)
		part.Parent = model
		return part
	end
	local root = block("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0))
	root.Transparency = 1
	local torso = block("UpperTorso", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0))
	local head = block("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 4.6, 0))
	for _, part in ipairs({ torso, head }) do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
	end
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = 2
	humanoid.Parent = model
	Instance.new("Animator").Parent = humanoid
	model.PrimaryPart = root
	return model
end

local function healthBar(model, humanoid, maxHealth)
	local head = model:FindFirstChild("Head") or model.PrimaryPart
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BarraVida"
	billboard.Size = UDim2.fromScale(4, 0.55)
	billboard.StudsOffset = Vector3.new(0, 2.3, 0)
	billboard.MaxDistance = 70
	billboard.LightInfluence = 0
	billboard.Adornee = head
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
	back.BorderSizePixel = 0
	back.Parent = billboard
	local fill = Instance.new("Frame")
	fill.Name = "Relleno"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(110, 220, 120)
	fill.BorderSizePixel = 0
	fill.Parent = back
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.3
	text.Parent = back
	local function refresh()
		local ratio = math.clamp(humanoid.Health / maxHealth, 0, 1)
		fill.Size = UDim2.fromScale(ratio, 1)
		fill.BackgroundColor3 = Color3.fromRGB(110, 220, 120):Lerp(Color3.fromRGB(230, 70, 60), 1 - ratio)
		text.Text = string.format("%d / %d", math.floor(humanoid.Health + 0.5), maxHealth)
	end
	refresh()
	humanoid.HealthChanged:Connect(refresh)
	billboard.Parent = model
end

local function folder()
	local f = Workspace:FindFirstChild("Munecos")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Munecos"
		f.Parent = Workspace
	end
	return f
end

-- Crea un personaje de práctica en una marca del mapa.
-- options: maxHealth, displayName, bodyColor, legColor, tags (lista extra de etiquetas),
--          noReset (no vuelve solo a su sitio: el compañero de combate lo hace por su cuenta),
--          noRegen (no se cura solo: el Guardián de la Grieta)
function DummyService.Spawn(marker, options)
	options = options or {}
	local maxHealth = options.maxHealth or settings.MaxHealth
	local bodyColor = options.bodyColor or WOOD
	local model = buildR15(bodyColor, options.legColor or WOOD_DARK) or buildBlocky(bodyColor)
	model.Name = string.gsub(marker.Name, "^Punto", "")

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	humanoid.DisplayName = options.displayName or "Muñeco de práctica"
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.WalkSpeed = 0
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	humanoid.BreakJointsOnDeath = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false) -- nunca muere: se queda en 0
	-- No tropieza ni cae al chocar (un compañero tumbado tras lanzarse contra el jugador dejaba de atacar)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)

	Rig.MakeKinematic(model) -- animaciones nítidas
	model:PivotTo(marker.CFrame)
	model:AddTag("Objetivo")
	for _, tag in ipairs(options.tags or {}) do
		model:AddTag(tag)
	end
	model:SetAttribute("Muneco", true)
	healthBar(model, humanoid, maxHealth)
	model.Parent = folder()

	local root = model:FindFirstChild("HumanoidRootPart")
	pcall(function()
		root:SetNetworkOwner(nil) -- el servidor simula el personaje (empujes y giros)
	end)

	PositionService.Track(model) -- historial observado (para juzgar golpes en su instante)
	DummyService.MarkFighter(model)

	local info = { noRegen = options.noRegen == true, noReset = options.noReset == true, spawn = marker.CFrame, lastHit = -math.huge, lastHealth = maxHealth, humanoid = humanoid, root = root, maxHealth = maxHealth }
	dummies[model] = info
	humanoid.HealthChanged:Connect(function(health)
		if health < info.lastHealth then
			info.lastHit = os.clock()
		end
		info.lastHealth = health
	end)
	return model
end

function DummyService.Start()
	folder()
	-- Los personajes de los jugadores también son luchadores
	local function watchPlayer(player)
		player.CharacterAdded:Connect(DummyService.MarkFighter)
		if player.Character then
			DummyService.MarkFighter(player.Character)
		end
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end
	local dojo = Workspace:WaitForChild("Maps"):WaitForChild("MovementLab"):WaitForChild("Dojo")
	for _, marker in ipairs(dojo:GetChildren()) do
		if marker:IsA("BasePart") and string.sub(marker.Name, 1, 11) == "PuntoMuneco" then
			local tough = string.find(marker.Name, "Aguante", 1, true) ~= nil
			task.spawn(DummyService.Spawn, marker, {
				maxHealth = if tough then settings.ToughMaxHealth else settings.MaxHealth,
				displayName = if tough then "Muñeco de aguante" else "Muñeco de práctica",
			})
		end
	end

	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for model, info in pairs(dummies) do
			if not model.Parent then
				dummies[model] = nil
				continue
			end
			local idle = now - info.lastHit
			if not info.noRegen and idle >= settings.RegenDelay and info.humanoid.Health < info.maxHealth then
				info.humanoid.Health = math.min(info.maxHealth, info.humanoid.Health + settings.RegenPerSecond * dt)
			end
			if not info.noReset and idle >= settings.ResetDelay and (info.root.Position - info.spawn.Position).Magnitude > 3 then
				model:PivotTo(info.spawn)
				info.root.AssemblyLinearVelocity = Vector3.zero
			end
		end
	end)
end

return DummyService
