-- EcoController: las habilidades del Eco en esta pantalla (EXPERIMENTAL, v2).
--   · Una tecla por habilidad (Z X C V; mando Y L1 L2 R2; un botón por habilidad en el celular). Sale AL PULSAR.
--   · Se lanza sin quedarte quieto y corta la preparación o la recuperación de tus golpes.
--   · Enfriamiento por tecla (lo muestra la barra de habilidades); la definitiva (V) gasta Resonancia.
--   · Variantes en el aire (C del Viento en el aire = Descenso) y relanzamientos (C otra vez tras un Levante
--     que conectó = Ascenso: subes tras el lanzado).
--   · Apuntado: hacia el ratón (PC) o al frente (mando, celular, o el ajuste del menú), con ayuda hacia el
--     enemigo más cercano a la mira.
--   · Teclas 1-5 (cruceta en el mando): cambiar de Eco.
-- Muestra el efecto al instante (predicción visual); el daño y los efectos sobre los enemigos los decide EcoService.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(shared:WaitForChild("Config"):WaitForChild("CombatConfig"))
local AnimationLibrary = require(shared:WaitForChild("Combat"):WaitForChild("AnimationLibrary"))
local EcoEfectos = require(script.Parent:WaitForChild("EcoEfectos"))
local PositionReporter = require(script.Parent:WaitForChild("PositionReporter"))

local EcoController = {}

local function signal(name)
	local event = Instance.new("BindableEvent")
	EcoController[name] = event.Event
	return event
end
local usedEvent = signal("Used") -- (habilidad, tecla): lo usan el tutorial, la barra y las pruebas
local deniedEvent = signal("Denied") -- (tecla, motivo): pulsada sin estar lista
local synergyEvent = signal("Synergy") -- (nombre del combo)
local kitEvent = signal("KitChanged") -- (nombre del Eco)
local recastEvent = signal("Recast") -- (tecla, texto o nil): relanzamiento disponible
local rejectedEvent = signal("Rejected") -- (motivo): el servidor no aceptó la última habilidad

local eco = CombatConfig.Eco
local skills = eco.Skills
local player = Players.LocalPlayer
local CLIENT_AIR_FEET = 2.2 -- altura de los pies desde la que se usa la variante aérea (el servidor acepta con margen)
local MOVE_KEY = "habilidad"

local state = {
	kit = eco.Default,
	cooldownEnd = {}, -- [tecla] = os.clock() en que vuelve a estar lista
	cooldownLength = {}, -- [tecla] = duración del último enfriamiento (para la barra)
	recast = {}, -- [tecla] = { untilTime, label, target }
	swapUntil = 0,
	aimMode = "raton", -- "raton" o "frente"
	lastCast = nil, -- { slot, time }
}
EcoController.State = state

local remote, equipRemote = nil, nil
local ultimateFlash -- (definida más abajo)
local input, movement, combat, camera = nil, nil, nil, nil
local currentTrack = nil
local falling = false
local descentToken = 0
local castToken = 0

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

function EcoController.Kit()
	return eco.Kits[state.kit] or eco.Kits[eco.Default]
end

function EcoController.KitName()
	return if eco.Kits[state.kit] then state.kit else eco.Default
end

-- Habilidad de una tecla (la variante aérea si `air` y existe)
function EcoController.SkillFor(slot, air)
	local kit = EcoController.Kit()
	if air and kit.air and kit.air[slot] then
		return kit.air[slot]
	end
	return kit.slots[slot]
end

function EcoController.CooldownRemaining(slot)
	return math.max(0, (state.cooldownEnd[slot] or 0) - os.clock(), state.swapUntil - os.clock())
end

function EcoController.SetAimMode(mode)
	state.aimMode = if mode == "frente" then "frente" else "raton"
end

local function character()
	return player.Character
end

local function rootPart()
	local c = character()
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function humanoidOf()
	local c = character()
	return c and c:FindFirstChildOfClass("Humanoid")
end

local function color()
	return EcoController.Kit().color
end

-- Altura de los pies sobre el suelo
local feetParams = RaycastParams.new()
feetParams.FilterType = Enum.RaycastFilterType.Exclude
feetParams.RespectCanCollide = true
local function feetHeight()
	local root, humanoid = rootPart(), humanoidOf()
	if not root or not humanoid then
		return 0
	end
	feetParams.FilterDescendantsInstances = { character(), EcoEfectos.Folder() }
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -60, 0), feetParams)
	if not hit then
		return math.huge
	end
	return (root.Position.Y - hit.Position.Y) - (humanoid.HipHeight + root.Size.Y / 2)
end

local function inAir()
	return not movement.State.grounded and feetHeight() >= CLIENT_AIR_FEET
end

-- ¿Las teclas con variante aérea sacarían ahora la del aire? (lo usa la barra para el nombre de la casilla)
function EcoController.InAir()
	return movement ~= nil and inAir()
end

local function playClip(name, speed)
	local humanoid = humanoidOf()
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	local ok, track = pcall(AnimationLibrary.Load, animator, name)
	if ok and track then
		if currentTrack and currentTrack.IsPlaying then
			currentTrack:Stop(0.06)
		end
		track:Play(0.04, 1, speed or 1)
		currentTrack = track
		return track
	end
	return nil
end

-- ---------- Apuntado ----------
local function usingMouse()
	local last = UserInputService:GetLastInputType()
	return last == Enum.UserInputType.Keyboard
		or last == Enum.UserInputType.MouseMovement
		or last == Enum.UserInputType.MouseButton1
		or last == Enum.UserInputType.MouseButton2
		or last == Enum.UserInputType.MouseButton3
		or last == Enum.UserInputType.MouseWheel
end

local function candidates()
	local list = {}
	for _, model in ipairs(CollectionService:GetTagged("Objetivo")) do
		if model:IsA("Model") and model ~= character() then
			table.insert(list, model)
		end
	end
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and other.Character then
			table.insert(list, other.Character)
		end
	end
	return list
end

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude

-- Dirección de apuntado desde el pecho. `allowVertical`: la habilidad puede ir hacia arriba o abajo (proyectiles).
-- Devuelve la dirección (unitaria) y el objetivo asistido (o nil).
local function aim(range, allowVertical, maxPitch)
	local root = rootPart()
	local chest = root.Position + Vector3.new(0, 0.3, 0)
	local forward = movement.DesiredDirection()
	local dir = forward
	local assistAngle = 35
	if state.aimMode == "raton" and usingMouse() then
		assistAngle = 14
		local cam = Workspace.CurrentCamera
		local m = UserInputService:GetMouseLocation()
		local ray = cam:ViewportPointToRay(m.X, m.Y)
		aimParams.FilterDescendantsInstances = { character(), EcoEfectos.Folder() }
		local hit = Workspace:Raycast(ray.Origin, ray.Direction * 600, aimParams)
		local point = if hit then hit.Position else ray.Origin + ray.Direction * 600
		local toPoint = point - chest
		if flat(toPoint).Magnitude > 1.5 then
			dir = toPoint.Unit
		end
	end
	-- Ayuda: el enemigo más cercano a la mira dentro del alcance
	local best, bestAngle = nil, math.rad(assistAngle)
	for _, model in ipairs(candidates()) do
		local targetRoot = model:FindFirstChild("HumanoidRootPart")
		local targetHumanoid = model:FindFirstChildOfClass("Humanoid")
		if targetRoot and targetHumanoid and (targetHumanoid.Health > 0 or not model:HasTag("Sparring")) then
			local offset = targetRoot.Position - chest
			if offset.Magnitude <= range and offset.Magnitude > 0.5 then
				local reference = if allowVertical then dir else flat(dir)
				local compare = if allowVertical then offset else flat(offset)
				if reference.Magnitude > 0.01 and compare.Magnitude > 0.01 then
					local angle = math.acos(math.clamp(reference.Unit:Dot(compare.Unit), -1, 1))
					if angle < bestAngle then
						best, bestAngle = model, angle
					end
				end
			end
		end
	end
	-- Enemigo fijado (R): las habilidades van hacia él si está a su alcance
	local locked = movement.LockedTarget and movement.LockedTarget()
	local lockedRoot = locked and locked:FindFirstChild("HumanoidRootPart")
	if lockedRoot and (lockedRoot.Position - chest).Magnitude <= range + 6 then
		best = locked
	end
	if best then
		dir = (best.HumanoidRootPart.Position - chest).Unit
	end
	if not allowVertical then
		local h = flat(dir)
		return if h.Magnitude > 0.01 then h.Unit else forward, best
	end
	-- Inclinación: desde el suelo no se dispara al piso (salvo hacia un enemigo más abajo)
	local h = flat(dir)
	h = if h.Magnitude > 0.01 then h.Unit else forward
	local pitch = math.asin(math.clamp(dir.Y, -1, 1))
	local limit = math.rad(maxPitch or 45)
	local minPitch = if inAir() or best then -limit else 0
	pitch = math.clamp(pitch, minPitch, limit)
	return (h * math.cos(pitch) + Vector3.new(0, math.sin(pitch), 0)).Unit, best
end

-- Punto del suelo apuntado, a lo sumo `range` studs (ratón: donde apunta; al frente: el enemigo asistido o
-- delante). Nunca detrás de una pared.
local function aimPoint(range)
	local root = rootPart()
	local origin = root.Position
	local dir, target = aim(range + 4, false)
	local distance = math.min(range, 10)
	if target then
		distance = math.min(range, (target.HumanoidRootPart.Position - origin).Magnitude)
	elseif state.aimMode == "raton" and usingMouse() then
		local cam = Workspace.CurrentCamera
		local m = UserInputService:GetMouseLocation()
		local ray = cam:ViewportPointToRay(m.X, m.Y)
		aimParams.FilterDescendantsInstances = { character(), EcoEfectos.Folder() }
		local hit = Workspace:Raycast(ray.Origin, ray.Direction * 600, aimParams)
		if hit then
			distance = math.clamp(flat(hit.Position - origin).Magnitude, 2, range)
		else
			distance = range
		end
	end
	local point = origin + dir * distance
	return EcoEfectos.Ground(point)
end

-- Gira hacia donde se lanza y lo sostiene lo que dura el gesto (las piernas siguen corriendo)
local function commitFacing(dir, duration)
	castToken += 1
	local token = castToken
	movement.Face(dir)
	movement.SetAutoRotateBlocked(MOVE_KEY, true)
	movement.SetSpeedMultiplier(MOVE_KEY, 0.9)
	task.delay(duration or 0.28, function()
		if castToken == token then
			movement.ClearKey(MOVE_KEY)
		end
	end)
end

-- Distancia libre hacia adelante (para no poner nada detrás de una pared)
local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude
wallParams.RespectCanCollide = true
local function freeDistance(from, dir, distance)
	local ignore = { character(), EcoEfectos.Folder() }
	for _, model in ipairs(candidates()) do
		table.insert(ignore, model)
	end
	wallParams.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(from, dir * distance, wallParams)
	return if hit then math.max(0, hit.Distance - 2) else distance
end

local function shake(amount)
	if camera and camera.Shake then
		camera.Shake(amount)
	end
end

-- Espera a tocar el suelo (picadas) y llama a onLand(posición, hora, mirada)
local function untilLanded(window, onLand)
	descentToken += 1
	local token = descentToken
	local humanoid = humanoidOf()
	falling = true
	task.spawn(function()
		local start = os.clock()
		while os.clock() - start < window do
			if not humanoid or humanoid.FloorMaterial ~= Enum.Material.Air then
				break
			end
			task.wait()
		end
		falling = false
		if token ~= descentToken or not humanoid or humanoid.Health <= 0 then
			return
		end
		local tt, landing, lk = PositionReporter.Sample()
		if landing then
			onLand(landing, tt, lk)
		end
	end)
end

-- ---------- Habilidades del Viento ----------
local cast = {}

cast.Cuchilla = function(spec)
	local t, position, look = PositionReporter.Sample()
	local air = inAir()
	local dir = aim(spec.range, true, if air then spec.airMaxPitch else spec.maxPitch)
	commitFacing(flat(dir), 0.25)
	remote:FireServer("cuchilla", t, position, look, dir)
	playClip("EcoCuchilla")
	EcoEfectos.Cuchilla(position + Vector3.new(0, 0.3, 0) + dir * 1.5, dir, spec.speed, spec.range - 1.5, color())
	if air then
		movement.AirStall(spec.airStall)
	end
	shake(0.15)
end

cast.Ciclon = function(spec)
	local t, position, look = PositionReporter.Sample()
	local air = inAir()
	local dir = aim(spec.radius + 4, false)
	commitFacing(dir, 0.3)
	remote:FireServer("ciclon", t, position, look, dir, air)
	playClip("EcoCiclon")
	local center = if air then position + dir * 2.5 else position + dir * spec.pullTo
	EcoEfectos.Ciclon(center, spec.radius, color(), air)
	if air then
		movement.AirStall(0.4)
	end
	shake(0.25)
end

cast.Levante = function(spec)
	local t, position, look = PositionReporter.Sample()
	local dir = aim(spec.range + 4, false)
	commitFacing(dir, 0.3)
	remote:FireServer("levante", t, position, look, dir)
	playClip("EcoLevante")
	EcoEfectos.Columna(position + dir * (spec.range * 0.5 + 0.5), color(), 12, 3)
	shake(0.3)
end

cast.Descenso = function(spec)
	local t, position, look = PositionReporter.Sample()
	local root = rootPart()
	remote:FireServer("descenso", t, position, look)
	playClip("EcoDescenso")
	local v = root.AssemblyLinearVelocity
	movement.Launch(Vector3.new(v.X * 0.3, -spec.plungeSpeed, v.Z * 0.3))
	local c = color()
	untilLanded(spec.window - 0.1, function(landing, tt, lk)
		remote:FireServer("impacto", tt, landing, lk)
		playClip("EcoAterrizaje")
		EcoEfectos.Onda(landing, spec.radius, c)
		shake(0.5)
	end)
end

cast.Tempestad = function(spec)
	local t, position, look = PositionReporter.Sample()
	local dir = aim(spec.distance + spec.radius, false)
	commitFacing(dir, 0.45)
	remote:FireServer("tempestad", t, position, look, dir)
	playClip("EcoTempestad")
	local center = position + dir * freeDistance(position, dir, spec.distance)
	EcoEfectos.Tornado(center, spec.radius, color(), spec.duration)
	shake(0.6)
end

-- Relanzamientos: C otra vez tras un Levante que conectó → Ascenso (subes tras el lanzado)
local recastActions = {}
-- Altura a la que queda flotando un enemigo lanzado por el Levante: la cima del lanzamiento sobre su suelo
local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Exclude
floorParams.RespectCanCollide = true
local function launchApex(model, targetRoot)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	floorParams.FilterDescendantsInstances = { model, character(), EcoEfectos.Folder() }
	local hit = Workspace:Raycast(targetRoot.Position, Vector3.new(0, -60, 0), floorParams)
	if not hit then
		return targetRoot.Position.Y
	end
	local standing = (humanoid and humanoid.HipHeight or 2) + targetRoot.Size.Y / 2
	local apex = skills.Levante.knockUp ^ 2 / (2 * Workspace.Gravity)
	return hit.Position.Y + standing + apex
end

recastActions.Ascenso = function(r)
	local root = rootPart()
	local targetRoot = r.target and r.target:FindFirstChild("HumanoidRootPart")
	local goal = if targetRoot then targetRoot.Position else root.Position + Vector3.new(0, 10, 0)
	if targetRoot then
		-- Se sube hasta donde el lanzado va a quedar flotando (lo que se ve todavía va subiendo, y con retraso)
		goal = Vector3.new(goal.X, math.max(goal.Y, launchApex(r.target, targetRoot)), goal.Z)
	end
	local rise = math.clamp(goal.Y - root.Position.Y + 0.5, 3, 18)
	local vy = math.sqrt(2 * Workspace.Gravity * rise)
	local horizontal = flat(goal - root.Position)
	local apex = vy / Workspace.Gravity
	local reach = math.max(0, horizontal.Magnitude - 2.5)
	movement.Launch(Vector3.new(0, vy, 0))
	if horizontal.Magnitude > 0.05 then
		movement.Face(horizontal)
		if reach > 0.2 then
			movement.Lunge(horizontal, math.min(reach / apex, 55), apex, true)
		end
	end
	playClip("EcoAscenso")
	EcoEfectos.Burst(root.Position - Vector3.new(0, 2, 0), color(), 16, 0.8, 26)
	EcoEfectos.Sound("Viento", root.Position)
	shake(0.15)
	-- Arriba quedas flotando un instante: tiempo para empezar el combo aéreo
	task.delay(apex * 0.92, function()
		movement.AirStall(0.4)
	end)
end

-- Efectos de las habilidades de otros jugadores (y de los que decide el servidor)
local remoteEffects = {}
remoteEffects.Cuchilla = function(data, c)
	EcoEfectos.Cuchilla(data.origin, data.dir, skills.Cuchilla.speed, skills.Cuchilla.range, c)
end
remoteEffects.Ciclon = function(data, c)
	EcoEfectos.Ciclon(data.center, skills.Ciclon.radius, c, data.air == true)
end
remoteEffects.Levante = function(data, c)
	EcoEfectos.Columna(data.center, c, 12, 3)
end
remoteEffects.Impacto = function(data, c)
	EcoEfectos.Onda(data.origin, skills.Descenso.radius, c)
end
remoteEffects.Tempestad = function(data, c)
	EcoEfectos.Tornado(data.center, skills.Tempestad.radius, c, skills.Tempestad.duration)
end

local function openRecast(slot, action, label, data, window)
	local r = data or {}
	r.action = action
	r.label = label
	r.untilTime = os.clock() + window
	state.recast[slot] = r
	recastEvent:Fire(slot, label)
end

local kitsLoaded = false
local function loadKits()
	if kitsLoaded then
		return
	end
	kitsLoaded = true
	local api = {
		skills = skills,
		eco = eco,
		EcoEfectos = EcoEfectos,
		PositionReporter = PositionReporter,
		movement = movement,
		combat = combat,
		state = state,
		flat = flat,
		fire = function(...)
			if remote then
				remote:FireServer(...)
			end
		end,
		aim = aim,
		aimPoint = aimPoint,
		commitFacing = commitFacing,
		playClip = playClip,
		inAir = inAir,
		feetHeight = feetHeight,
		shake = shake,
		freeDistance = freeDistance,
		color = color,
		character = character,
		rootPart = rootPart,
		humanoidOf = humanoidOf,
		openRecast = openRecast,
		untilLanded = untilLanded,
	}
	local ok, kits = pcall(function()
		return require(script.Parent:WaitForChild("EcoKitsCliente"))(api)
	end)
	if not ok or type(kits) ~= "table" then
		warn("[UMBRAL] No se pudieron cargar las habilidades de los Ecos: " .. tostring(kits))
		return
	end
	for name, fn in pairs(kits.casts or {}) do
		cast[name] = fn
	end
	for name, fn in pairs(kits.recasts or {}) do
		recastActions[name] = fn
	end
	for name, fn in pairs(kits.effects or {}) do
		remoteEffects[name] = fn
	end
end

-- Definitiva: un destello de pantalla del color del Eco y un golpe de cámara (se siente grande)
local flashGui = nil
ultimateFlash = function(c)
	if not flashGui then
		flashGui = Instance.new("ScreenGui")
		flashGui.Name = "UmbralDestelloDefinitiva"
		flashGui.IgnoreGuiInset = true
		flashGui.ResetOnSpawn = false
		flashGui.DisplayOrder = 3
		local frame = Instance.new("Frame")
		frame.Name = "Destello"
		frame.Size = UDim2.fromScale(1, 1)
		frame.BorderSizePixel = 0
		frame.BackgroundTransparency = 1
		frame.Parent = flashGui
		flashGui.Parent = player:WaitForChild("PlayerGui")
	end
	local frame = flashGui.Destello
	frame.BackgroundColor3 = c
	frame.BackgroundTransparency = 0.55
	game:GetService("TweenService"):Create(frame, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
	if camera and camera.Kick then
		camera.Kick(9)
	end
end

-- ---------- Lanzar ----------
local function canAct()
	local humanoid = humanoidOf()
	return humanoid ~= nil and humanoid.Health > 0 and rootPart() ~= nil and remote ~= nil and not falling and combat.State.mode ~= "Aturdido"
end

local function deny(slot, reason)
	deniedEvent:Fire(slot, reason)
	local root = rootPart()
	if root then
		EcoEfectos.Sound("NoListo", root)
	end
end

local function tryCast(slot)
	if not canAct() then
		return deny(slot, if combat.State.mode == "Aturdido" then "aturdido" else "ocupado")
	end
	-- Relanzamiento disponible en esta tecla
	local r = state.recast[slot]
	if r and os.clock() <= r.untilTime and recastActions[r.action] then
		state.recast[slot] = nil
		recastEvent:Fire(slot, nil)
		combat.CancelForSkill()
		recastActions[r.action](r)
		usedEvent:Fire(r.action, slot)
		return
	end
	local skillName = EcoController.SkillFor(slot, inAir())
	local spec = skillName and skills[skillName]
	if not spec or not cast[skillName] then
		return deny(slot, "sin habilidad")
	end
	if EcoController.CooldownRemaining(slot) > 0 then
		return deny(slot, "enfriamiento")
	end
	if (spec.cost or 0) > 0 and (player:GetAttribute("Resonancia") or 0) < spec.cost then
		return deny(slot, "resonancia")
	end
	if not combat.CancelForSkill() then
		return deny(slot, "aturdido")
	end
	cast[skillName](spec, slot)
	if (spec.cost or 0) > 0 then
		ultimateFlash(color())
	end
	state.cooldownEnd[slot] = os.clock() + spec.cooldown
	state.cooldownLength[slot] = spec.cooldown
	state.lastCast = { slot = slot, time = os.clock() }
	usedEvent:Fire(skillName, slot)
end

local function equip(name)
	if not eco.Kits[name] or name == state.kit then
		return
	end
	state.kit = name
	state.swapUntil = os.clock() + eco.SwapCooldown
	table.clear(state.recast)
	if equipRemote then
		equipRemote:FireServer(name)
	end
	kitEvent:Fire(name)
end
EcoController.Equip = equip

-- ---------- Lo que confirma el servidor ----------
local function onConfirmed(data)
	if type(data) ~= "table" or type(data.attack) ~= "string" or string.sub(data.attack, 1, 3) ~= "Eco" then
		return
	end
	local attacker = data.attacker
	local kit = eco.Kits[(typeof(attacker) == "Instance" and attacker:GetAttribute("Eco")) or ""] or eco.Kits[eco.Default]
	if typeof(data.position) == "Vector3" and data.attack ~= "EcoQuemadura" and data.attack ~= "EcoInfierno" then
		EcoEfectos.Impacto(data.position, kit.color)
	end
	if attacker ~= player then
		if data.attack == "EcoBurbuja" and typeof(data.target) == "Instance" and (data.damage or 0) > 0 then
			EcoEfectos.Atrapado(data.target, kit.color, skills.Burbuja.trap + 0.25)
		end
		return
	end
	if (data.damage or 0) > 0 then
		combat.RegisterSkillHit(data.damage, data.target)
		-- Cada golpe de habilidad se siente: vibración proporcional al daño (los daños de estado, apenas)
		if data.attack ~= "EcoQuemadura" and data.attack ~= "EcoInfierno" then
			shake(math.clamp(0.06 + data.damage * 0.012, 0.06, 0.3))
		end
		-- Combo aéreo: tus habilidades que conectan en el aire te sostienen un instante
		if not movement.State.grounded and data.attack ~= "EcoDescenso" then
			movement.AirStall(eco.Juggle.AirStall)
		end
	end
	if type(data.synergy) == "string" then
		synergyEvent:Fire(data.synergy)
	end
	if data.attack == "EcoBurbuja" and typeof(data.target) == "Instance" and (data.damage or 0) > 0 then
		EcoEfectos.Atrapado(data.target, kit.color, skills.Burbuja.trap + 0.25)
	end
	if data.attack == "EcoLevante" and (data.damage or 0) > 0 and EcoController.Kit().slots.C == "Levante" then
		state.recast.C = { action = "Ascenso", untilTime = os.clock() + skills.Levante.recastWindow, label = "SUBIR", target = data.target }
		recastEvent:Fire("C", "SUBIR")
	end
end

-- Habilidades de otros jugadores (quien la usa ya la vio en su pantalla). Los efectos que decide el servidor
-- (serverDriven: saltos del rayo, chispazos, suelo ardiente...) se ven en todas las pantallas.
local function onRemoteEffect(data)
	if type(data) ~= "table" or type(data.skill) ~= "string" then
		return
	end
	local own = data.player == player
	if own and not data.serverDriven then
		return
	end
	local kit = eco.Kits[(typeof(data.player) == "Instance" and data.player:GetAttribute("Eco")) or ""] or eco.Kits[eco.Default]
	local handler = remoteEffects[data.skill]
	if handler then
		local ok, err = pcall(handler, data, kit.color, own)
		if not ok then
			warn("[UMBRAL] Efecto " .. data.skill .. ": " .. tostring(err))
		end
	end
end

local SLOT_OF = { HabilidadZ = "Z", HabilidadX = "X", HabilidadC = "C", HabilidadV = "V" }

function EcoController.Start(inputController, movementController, combatController, cameraController)
	input, movement, combat, camera = inputController, movementController, combatController, cameraController
	state.kit = if eco.Kits[player:GetAttribute("Eco") or ""] then player:GetAttribute("Eco") else eco.Default
	loadKits()
	EcoEfectos.WatchStates()
	-- Detonar una marca de la Daga recarga la tecla Z (lo decide el servidor)
	player:GetAttributeChangedSignal("RecargasZ"):Connect(function()
		state.cooldownEnd.Z = 0
		synergyEvent:Fire("RECARGA")
	end)
	-- En celular y mando se apunta al frente; en PC, al ratón (se cambia en el menú)
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		state.aimMode = "frente"
	end

	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		remote = remotes:WaitForChild("Eco")
		equipRemote = remotes:WaitForChild("ElegirEco")
		remotes:WaitForChild("GolpeConfirmado").OnClientEvent:Connect(onConfirmed)
		remotes:WaitForChild("EcoEfecto").OnClientEvent:Connect(onRemoteEffect)
	end)

	input.ActionBegan:Connect(function(action)
		local slot = SLOT_OF[action]
		if slot then
			tryCast(slot)
			return
		end
		local index = type(action) == "string" and tonumber(string.match(action, "^Eco(%d)$"))
		if index then
			local name = eco.Order[index]
			if name then
				equip(name)
			end
		elseif action == "EcoSiguiente" or action == "EcoAnterior" then
			local current = table.find(eco.Order, state.kit) or 1
			local step = if action == "EcoSiguiente" then 1 else -1
			equip(eco.Order[(current - 1 + step) % #eco.Order + 1])
		end
	end)

	-- El Eco que dice el servidor manda (al entrar, al reaparecer, si rechazó un cambio)
	player:GetAttributeChangedSignal("Eco"):Connect(function()
		local name = player:GetAttribute("Eco")
		if eco.Kits[name or ""] and name ~= state.kit then
			state.kit = name
			table.clear(state.recast)
			kitEvent:Fire(name)
		end
	end)

	-- Si el servidor rechazó la última habilidad (por algo que no sea el enfriamiento), se devuelve el
	-- enfriamiento de esa tecla: así la barra no miente
	player:GetAttributeChangedSignal("EcosRechazados"):Connect(function()
		local reason = player:GetAttribute("EcoRechazado")
		local last = state.lastCast
		if last and os.clock() - last.time < 1.5 and reason ~= "enfriamiento" and reason ~= "impacto sin descenso" and reason ~= "impacto sin aterrizaje" then
			state.cooldownEnd[last.slot] = 0
		end
		rejectedEvent:Fire(reason)
	end)

	player.CharacterAdded:Connect(function()
		falling = false
		descentToken += 1
		table.clear(state.recast)
		currentTrack = nil
	end)
end

return EcoController
