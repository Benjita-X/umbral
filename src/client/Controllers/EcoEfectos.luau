-- EcoEfectos: lo que se VE de las habilidades del Eco (solo en esta pantalla; el daño lo decide el servidor).
-- Piezas de neón con interpolaciones (TweenService) y partículas de las texturas que trae Roblox. Cada función
-- recibe el color del Eco, así sirven para todos los kits.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local EcoEfectos = {}

local TEXTURES = {
	Sparks = "rbxasset://textures/particles/sparkles_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Shockwave = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
}
EcoEfectos.Textures = TEXTURES
local SOUNDS = {
	Lanzar = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.55, speed = 2.2 },
	Viento = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.6, speed = 0.8 },
	Golpe = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.8, speed = 1.4 },
	Estallido = { id = "rbxasset://sounds/impact_explosion_03.mp3", volume = 0.35, speed = 1.2 },
	Grave = { id = "rbxasset://sounds/impact_explosion_03.mp3", volume = 0.45, speed = 0.7 },
	NoListo = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.35, speed = 3 },
	Agua = { id = "rbxasset://sounds/impact_water.mp3", volume = 0.7, speed = 1.1 },
	AguaGrave = { id = "rbxasset://sounds/impact_water.mp3", volume = 0.9, speed = 0.7 },
	Surf = { id = "rbxasset://sounds/action_swim.mp3", volume = 0.6, speed = 1.3 },
	Remolino = { id = "rbxasset://sounds/action_falling.ogg", volume = 0.45, speed = 1.6 },
}

local function folder()
	local camera = Workspace.CurrentCamera
	local f = camera:FindFirstChild("UmbralEfectosEco")
	if not f then
		f = Instance.new("Folder")
		f.Name = "UmbralEfectosEco"
		f.Parent = camera
	end
	return f
end
EcoEfectos.Folder = folder

EcoEfectos.Creados = 0 -- piezas de efecto creadas (diagnóstico de la vitrina)
EcoEfectos.Lento = 1 -- la vitrina lo sube para ver los efectos en cámara lenta (alarga duraciones)
function EcoEfectos.Part(size, cframe, color, shape, transparency)
	EcoEfectos.Creados += 1
	local part = Instance.new("Part")
	part.Name = "UmbralEfectoEco"
	part.Shape = shape or Enum.PartType.Block
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency or 0.35
	part.Size = size
	part.CFrame = cframe
	part.Parent = folder()
	return part
end

local function tween(instance, time, props, style, direction)
	local t = TweenService:Create(instance, TweenInfo.new(time * EcoEfectos.Lento, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end
EcoEfectos.Tween = tween

local function fadeAndDestroy(part, time, props)
	props = props or {}
	props.Transparency = 1
	tween(part, time, props).Completed:Connect(function()
		part:Destroy()
	end)
end
EcoEfectos.Fade = fadeAndDestroy

function EcoEfectos.Sound(name, parentOrPosition)
	local spec = SOUNDS[name]
	if not spec then
		return
	end
	local parent = parentOrPosition
	if typeof(parentOrPosition) == "Vector3" then
		parent = EcoEfectos.Part(Vector3.new(0.2, 0.2, 0.2), CFrame.new(parentOrPosition), Color3.new(1, 1, 1), nil, 1)
		Debris:AddItem(parent, 2)
	end
	if typeof(parent) ~= "Instance" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = spec.id
	sound.Volume = spec.volume
	sound.PlaybackSpeed = spec.speed
	sound.RollOffMaxDistance = 140
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 2)
end

-- Suelo debajo de un punto (o el punto mismo si no hay suelo cerca)
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true
function EcoEfectos.Ground(position)
	local ignore = { folder() }
	local character = Players.LocalPlayer.Character
	if character then
		table.insert(ignore, character)
	end
	groundParams.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -40, 0), groundParams)
	return if hit then hit.Position else position
end

-- Destello de partículas
function EcoEfectos.Burst(position, color, count, size, speed)
	local anchor = EcoEfectos.Part(Vector3.new(0.2, 0.2, 0.2), CFrame.new(position), color, nil, 1)
	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = TEXTURES.Sparks
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size or 0.8), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.15, 0.35)
	emitter.Speed = NumberRange.new((speed or 30) * 0.5, speed or 30)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 6
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(count or 16)
	Debris:AddItem(anchor, 1)
end

-- Anillo que se abre en el suelo
function EcoEfectos.Ring(center, radius, color, duration, thickness)
	local ring = EcoEfectos.Part(Vector3.new(thickness or 0.3, 2, 2), CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.PartType.Cylinder, 0.25)
	fadeAndDestroy(ring, duration or 0.3, { Size = Vector3.new(thickness or 0.3, radius * 2, radius * 2) })
	return ring
end

-- Proyectil visual que vuela recto a `speed` hasta `range` o hasta chocar con una pared. `build(cframe)`
-- devuelve las piezas (se mueven juntas); `onEnd(position, hitWall)` al terminar.
local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude
wallParams.RespectCanCollide = true
function EcoEfectos.Projectile(origin, dir, speed, range, parts, onEnd, relative)
	local ignore = { folder() }
	for _, other in ipairs(Players:GetPlayers()) do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	wallParams.FilterDescendantsInstances = ignore
	local traveled = 0
	local position = origin
	local basis = CFrame.lookAt(Vector3.zero, dir)
	local offsets = {}
	-- relative = true: las piezas conservan su posición respecto al proyectil (se crearon ya colocadas)
	local startFrame = CFrame.new(origin) * basis.Rotation
	for i, part in ipairs(parts) do
		offsets[i] = if relative then startFrame:ToObjectSpace(part.CFrame) else part.CFrame.Rotation
	end
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		local step = math.min(speed / EcoEfectos.Lento * dt, range - traveled)
		local hit = Workspace:Raycast(position, dir * step, wallParams)
		-- los personajes no frenan el proyectil (lo decide el servidor): solo las paredes
		while hit do
			local model = hit.Instance:FindFirstAncestorOfClass("Model")
			if model and model:FindFirstChildOfClass("Humanoid") then
				table.insert(ignore, model)
				wallParams.FilterDescendantsInstances = ignore
				hit = Workspace:Raycast(position, dir * step, wallParams)
			else
				break
			end
		end
		local finished = false
		if hit then
			position = hit.Position - dir * 0.3
			finished = true
		else
			position += dir * step
			traveled += step
			finished = traveled >= range - 1e-3
		end
		for i, part in ipairs(parts) do
			part.CFrame = CFrame.new(position) * basis.Rotation * offsets[i]
		end
		if finished then
			connection:Disconnect()
			for _, part in ipairs(parts) do
				fadeAndDestroy(part, 0.12)
			end
			if onEnd then
				onEnd(position, hit ~= nil)
			end
		end
	end)
end

-- ---------- Viento ----------

-- Cuchilla: un disco de viento ancho y fino con estela
function EcoEfectos.Cuchilla(origin, dir, speed, range, color)
	-- Media luna horizontal que vuela con la panza hacia adelante: tramos de neón de color con el filo blanco
	local frame = CFrame.lookAt(origin, origin + dir) * CFrame.Angles(0, 0, math.rad(22))
	local parts = {}
	local radius, count = 3.4, 9
	local tips = {}
	for i = 1, count do
		local t = (i - 0.5) / count
		local angle = math.rad(-70 + 140 * t)
		local profile = math.sin(math.pi * t) ^ 0.7
		local local_ = Vector3.new(math.sin(angle) * radius, 0, -(math.cos(angle) * radius) + radius * 0.75)
		local radial = Vector3.new(math.sin(angle), 0, -math.cos(angle))
		local segFrame = frame * CFrame.fromMatrix(local_, radial, Vector3.yAxis)
		local w = math.max(0.15, 1.1 * profile)
		table.insert(parts, EcoEfectos.Part(Vector3.new(w, 0.5, radius * 0.3), segFrame, color, Enum.PartType.Block, 0.15))
		table.insert(parts, EcoEfectos.Part(Vector3.new(w * 0.38, 0.4, radius * 0.3), segFrame * CFrame.new(w * 0.3, 0, 0), Color3.new(1, 1, 1), Enum.PartType.Block, 0))
		table.insert(parts, EcoEfectos.Part(Vector3.new(w * 1.8, 1, radius * 0.32), segFrame, color, Enum.PartType.Block, 0.78))
		if i == 1 or i == count then
			table.insert(tips, parts[#parts - 2])
		end
	end
	-- Estelas desde las dos puntas
	for _, tip in ipairs(tips) do
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.25, 0)
		a0.Parent = tip
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.25, 0)
		a1.Parent = tip
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
		trail.LightEmission = 1
		trail.Lifetime = 0.2
		trail.FaceCamera = true
		trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		trail.Parent = tip
	end
	EcoEfectos.Sound("Lanzar", origin)
	EcoEfectos.Projectile(origin, dir, speed, range, parts, function(position, hitWall)
		if hitWall then
			EcoEfectos.Burst(position, color, 14, 0.7, 24)
			EcoEfectos.Destello(position, color, 3.5, 0.12)
		end
	end, true)
end

-- Ciclón: anillos que giran y se cierran hacia el centro
function EcoEfectos.Ciclon(center, radius, color, air)
	local base = if air then center else EcoEfectos.Ground(center) + Vector3.new(0, 0.3, 0)
	for i = 1, 3 do
		local ring = EcoEfectos.Part(Vector3.new(0.35, radius * 2, radius * 2), CFrame.new(base + Vector3.new(0, (i - 1) * 1.2, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.PartType.Cylinder, 0.3)
		local spin = 0
		local start = os.clock()
		local duration = (0.32 + i * 0.05) * EcoEfectos.Lento
		local connection
		connection = RunService.Heartbeat:Connect(function(dt)
			local alpha = math.clamp((os.clock() - start) / duration, 0, 1)
			spin += dt * 14
			local d = radius * 2 * (1 - alpha) + 0.5
			ring.Size = Vector3.new(0.35, d, d)
			ring.Transparency = 0.3 + 0.7 * alpha
			ring.CFrame = CFrame.new(base + Vector3.new(0, (i - 1) * 1.2, 0)) * CFrame.Angles(0, spin, 0) * CFrame.Angles(0, 0, math.rad(90))
			if alpha >= 1 then
				connection:Disconnect()
				ring:Destroy()
			end
		end)
	end
	EcoEfectos.Burst(base + Vector3.new(0, 1.5, 0), color, 20, 0.9, 18)
	EcoEfectos.Sound("Remolino", base)
end

-- Columna: el viento sale del suelo y lanza hacia arriba
function EcoEfectos.Columna(position, color, height, radius)
	height = height or 12
	radius = radius or 3
	local ground = EcoEfectos.Ground(position)
	local column = EcoEfectos.Part(Vector3.new(1, radius * 2, radius * 2), CFrame.new(ground + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.PartType.Cylinder, 0.3)
	tween(column, 0.12, { Size = Vector3.new(height, radius * 1.6, radius * 1.6), CFrame = CFrame.new(ground + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)) }).Completed:Connect(function()
		fadeAndDestroy(column, 0.3, { Size = Vector3.new(height * 1.1, radius * 0.4, radius * 0.4) })
	end)
	EcoEfectos.Ring(ground + Vector3.new(0, 0.2, 0), radius * 1.6, color, 0.3)
	EcoEfectos.Burst(ground + Vector3.new(0, 1, 0), color, 18, 0.8, 34)
	EcoEfectos.Espiral(ground + Vector3.new(0, 0.5, 0), height * 0.9, radius * 1.25, color, 0.42, 4)
	EcoEfectos.Sound("Estallido", ground)
end

-- Tornado: anillos apilados que giran durante `duration` y estallan al final
function EcoEfectos.Tornado(center, radius, color, duration)
	local ground = EcoEfectos.Ground(center)
	local rings = {}
	for i = 1, 6 do
		local r = radius * (0.35 + i * 0.12)
		local ring = EcoEfectos.Part(Vector3.new(0.4, r * 2, r * 2), CFrame.new(ground + Vector3.new(0, i * 1.8, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.PartType.Cylinder, 0.55)
		table.insert(rings, { part = ring, height = i * 1.8, radius = r })
	end
	local core = EcoEfectos.Part(Vector3.new(14, 3, 3), CFrame.new(ground + Vector3.new(0, 7, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.PartType.Cylinder, 0.75)
	local start = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - start
		for i, ring in ipairs(rings) do
			local wobble = Vector3.new(math.sin(elapsed * 6 + i) * 0.6, 0, math.cos(elapsed * 6 + i) * 0.6)
			ring.part.CFrame = CFrame.new(ground + Vector3.new(0, ring.height, 0) + wobble) * CFrame.Angles(0, elapsed * (10 + i), 0) * CFrame.Angles(0, 0, math.rad(90))
		end
		core.CFrame = CFrame.new(ground + Vector3.new(0, 7, 0)) * CFrame.Angles(0, elapsed * 8, 0) * CFrame.Angles(0, 0, math.rad(90))
		if elapsed >= duration then
			connection:Disconnect()
			for _, ring in ipairs(rings) do
				fadeAndDestroy(ring.part, 0.25, { Size = Vector3.new(0.4, ring.radius * 3, ring.radius * 3) })
			end
			fadeAndDestroy(core, 0.25)
			EcoEfectos.Ring(ground + Vector3.new(0, 0.5, 0), radius * 1.3, color, 0.4, 0.6)
			EcoEfectos.Burst(ground + Vector3.new(0, 4, 0), color, 40, 1.2, 50)
			EcoEfectos.Sound("Grave", ground)
		end
	end)
	EcoEfectos.Sound("Remolino", ground)
end

-- Impacto de una habilidad sobre un enemigo (confirmado por el servidor)
function EcoEfectos.Impacto(position, color, element, big)
	EcoEfectos.Burst(position, color, if big then 18 else 12, 0.7, 26)
	EcoEfectos.Destello(position, color, if big then 7 else 4.6, if big then 0.2 else 0.15)
	EcoEfectos.Rayas(position, color, if big then 10 else 6, if big then 6 else 4)
	if element then
		EcoEfectos.Elemento(position, element, if big then 1.4 else 0.8)
	end
	if big then
		local camera = Workspace.CurrentCamera
		local toCamera = if camera then (camera.CFrame.Position - position) else Vector3.yAxis
		EcoEfectos.OndaChoque(position, color, 5, if toCamera.Magnitude > 0.1 then toCamera.Unit else Vector3.yAxis, 0.22)
	end
	local flash = EcoEfectos.Part(Vector3.new(1, 1, 1), CFrame.new(position), color, Enum.PartType.Ball, 0.2)
	fadeAndDestroy(flash, 0.16, { Size = Vector3.new(3.5, 3.5, 3.5) })
end

-- Estela de picada (Descenso) y onda al aterrizar
function EcoEfectos.Onda(position, radius, color)
	local ground = EcoEfectos.Ground(position)
	EcoEfectos.Ring(ground + Vector3.new(0, 0.2, 0), radius, color, 0.32, 0.5)
	EcoEfectos.Ring(ground + Vector3.new(0, 1, 0), radius * 0.7, color, 0.25)
	EcoEfectos.Burst(ground + Vector3.new(0, 1, 0), color, 26, 1, 40)
	EcoEfectos.Sound("Estallido", ground)
end


-- ---------- Comunes de los demás Ecos ----------

-- Esfera que vuela (burbuja, bola de fuego, daga): `size` y `glow` opcionales; partículas de `texture`
function EcoEfectos.Orbe(origin, dir, speed, range, color, size, texture, onEnd)
	size = size or 1.6
	local core = EcoEfectos.Part(Vector3.new(size, size, size), CFrame.new(origin), color, Enum.PartType.Ball, 0.15)
	local glow = EcoEfectos.Part(Vector3.new(size * 1.6, size * 1.6, size * 1.6), CFrame.new(origin), color, Enum.PartType.Ball, 0.75)
	local attachment = Instance.new("Attachment")
	attachment.Parent = core
	if texture then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = texture
		emitter.Color = ColorSequence.new(color)
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.9), NumberSequenceKeypoint.new(1, 0) })
		emitter.Lifetime = NumberRange.new(0.2, 0.35)
		emitter.Speed = NumberRange.new(1, 3)
		emitter.Rate = 60
		emitter.Parent = attachment
	end
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, size * 0.4, 0)
	a0.Parent = core
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -size * 0.4, 0)
	a1.Parent = core
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(color)
	trail.LightEmission = 0.8
	trail.Lifetime = 0.15
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	trail.Parent = core
	EcoEfectos.Sound("Lanzar", origin)
	EcoEfectos.Projectile(origin, dir, speed, range, { core, glow }, onEnd)
end

-- Rayo entre dos puntos: tramos en zigzag que destellan y se apagan
function EcoEfectos.Rayo(from, to, color, width, quiet)
	local points = { from }
	local segments = math.clamp(math.floor((to - from).Magnitude / 3), 3, 12)
	for i = 1, segments - 1 do
		local alpha = i / segments
		local jitter = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 1.6
		table.insert(points, from:Lerp(to, alpha) + jitter)
	end
	table.insert(points, to)
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local length = (b - a).Magnitude
		if length > 0.05 then
			local w = width or 0.35
			local bolt = EcoEfectos.Part(Vector3.new(w * 2.2, w * 2.2, length), CFrame.lookAt((a + b) / 2, b), color, Enum.PartType.Block, 0.45)
			fadeAndDestroy(bolt, 0.22, { Size = Vector3.new(0.05, 0.05, length) })
			local core = EcoEfectos.Part(Vector3.new(w, w, length), CFrame.lookAt((a + b) / 2, b), Color3.new(1, 1, 1), Enum.PartType.Block, 0)
			fadeAndDestroy(core, 0.18, { Size = Vector3.new(0.03, 0.03, length) })
		end
	end
	if quiet then
		return
	end
	EcoEfectos.Burst(to, color, 10, 0.6, 22)
	EcoEfectos.Destello(to, color, 3.5, 0.14)
	EcoEfectos.Sound("Golpe", to)
end

-- Rastro en el suelo entre dos puntos que dura `duration` (fuego, sombra, agua)
function EcoEfectos.Rastro(from, to, color, width, duration, texture)
	local a, b = EcoEfectos.Ground(from), EcoEfectos.Ground(to)
	local length = (b - a).Magnitude
	if length < 0.3 then
		return
	end
	local strip = EcoEfectos.Part(Vector3.new(width, 0.25, length), CFrame.lookAt((a + b) / 2 + Vector3.new(0, 0.15, 0), b + Vector3.new(0, 0.15, 0)), color, Enum.PartType.Block, 0.3)
	if texture then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = texture
		emitter.Color = ColorSequence.new(color)
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
		emitter.Lifetime = NumberRange.new(0.4, 0.7)
		emitter.Speed = NumberRange.new(2, 5)
		emitter.SpreadAngle = Vector2.new(10, 10)
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.Rate = math.clamp(length * 6, 10, 90)
		emitter.Shape = Enum.ParticleEmitterShape.Box
		emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		emitter.Parent = strip
		task.delay(math.max(0, duration - 0.3), function()
			emitter.Enabled = false
		end)
	end
	task.delay(math.max(0, duration - 0.3), function()
		if strip.Parent then
			fadeAndDestroy(strip, 0.3)
		end
	end)
end

-- Círculo en el suelo que dura (aviso del géiser, suelo ardiente, anillo de fuego)
function EcoEfectos.Circulo(center, radius, color, duration, transparency, texture)
	local ground = EcoEfectos.Ground(center)
	local disc = EcoEfectos.Part(Vector3.new(0.2, radius * 2, radius * 2), CFrame.new(ground + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.PartType.Cylinder, transparency or 0.55)
	if texture then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = texture
		emitter.Color = ColorSequence.new(color)
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0) })
		emitter.Lifetime = NumberRange.new(0.4, 0.8)
		emitter.Speed = NumberRange.new(2, 6)
		emitter.Rate = math.clamp(radius * radius * 2, 15, 120)
		emitter.Shape = Enum.ParticleEmitterShape.Cylinder
		emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		emitter.EmissionDirection = Enum.NormalId.Right
		emitter.Parent = disc
		task.delay(math.max(0, duration - 0.3), function()
			emitter.Enabled = false
		end)
	end
	task.delay(math.max(0, duration - 0.25), function()
		if disc.Parent then
			fadeAndDestroy(disc, 0.25)
		end
	end)
	return disc
end

-- Explosión: bola que se infla, anillo y chispas
function EcoEfectos.Explosion(center, radius, color)
	local ball = EcoEfectos.Part(Vector3.new(1, 1, 1), CFrame.new(center), color, Enum.PartType.Ball, 0.1)
	fadeAndDestroy(ball, 0.3, { Size = Vector3.new(radius * 2, radius * 2, radius * 2) })
	EcoEfectos.Ring(EcoEfectos.Ground(center) + Vector3.new(0, 0.3, 0), radius * 1.2, color, 0.3, 0.5)
	EcoEfectos.OndaChoque(EcoEfectos.Ground(center) + Vector3.new(0, 0.35, 0), color, radius * 1.4, Vector3.yAxis, 0.3)
	EcoEfectos.Destello(center, color, radius * 1.1, 0.18)
	EcoEfectos.Burst(center, color, 30, 1.1, 45)
	EcoEfectos.Burst(center, Color3.fromRGB(255, 240, 200), 14, 0.8, 30)
	EcoEfectos.Sound("Estallido", center)
end

-- Silueta del personaje que se desvanece (sombra, rayo, agua)
function EcoEfectos.Silueta(character, color, duration, transparency)
	if not character then
		return
	end
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and part.Transparency < 1 then
			local ghost = EcoEfectos.Part(part.Size, part.CFrame, color, Enum.PartType.Block, transparency or 0.4)
			fadeAndDestroy(ghost, duration or 0.4)
		end
	end
end

-- Aura en el personaje (formas de las definitivas): destello de color que dura
function EcoEfectos.Aura(character, color, duration)
	if not character then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "UmbralAuraEco"
	highlight.Adornee = character
	highlight.FillColor = color
	highlight.FillTransparency = 0.55
	highlight.OutlineColor = color
	highlight.OutlineTransparency = 0.1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = folder()
	task.delay(math.max(0, duration - 0.3), function()
		if highlight.Parent then
			tween(highlight, 0.3, { FillTransparency = 1, OutlineTransparency = 1 }).Completed:Connect(function()
				highlight:Destroy()
			end)
		end
	end)
end

-- ---------- Agua ----------
function EcoEfectos.Ola(origin, finish, color, duration)
	local dir = Vector3.new(finish.X - origin.X, 0, finish.Z - origin.Z)
	if dir.Magnitude < 0.1 then
		return
	end
	dir = dir.Unit
	local ground = EcoEfectos.Ground(origin)
	local wave = EcoEfectos.Part(Vector3.new(6, 3.5, 2.5), CFrame.lookAt(ground + Vector3.new(0, 1.5, 0), ground + Vector3.new(0, 1.5, 0) + dir), color, Enum.PartType.Block, 0.35)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = wave
	local target = EcoEfectos.Ground(finish) + Vector3.new(0, 1.5, 0)
	tween(wave, duration, { CFrame = CFrame.lookAt(target, target + dir) }, Enum.EasingStyle.Linear).Completed:Connect(function()
		EcoEfectos.Burst(target, color, 20, 0.9, 25)
		fadeAndDestroy(wave, 0.2, { Size = Vector3.new(8, 1, 3) })
	end)
	EcoEfectos.Rastro(origin, finish, color, 4, 0.8, TEXTURES.Smoke)
	EcoEfectos.Sound("Surf", origin)
end

function EcoEfectos.Geiser(center, color, delay)
	local ground = EcoEfectos.Ground(center)
	EcoEfectos.Circulo(ground, 5, color, delay + 0.1, 0.6)
	task.delay(delay, function()
		EcoEfectos.Columna(ground, color, 14, 3.2)
		EcoEfectos.Burst(ground + Vector3.new(0, 3, 0), Color3.fromRGB(220, 240, 255), 26, 1, 40)
		EcoEfectos.Sound("AguaGrave", ground)
	end)
end

function EcoEfectos.Diluvio(origin, dir, color, delay)
	local ground = EcoEfectos.Ground(origin)
	local base = CFrame.lookAt(ground + Vector3.new(0, 3, 0), ground + Vector3.new(0, 3, 0) + dir)
	local wave = EcoEfectos.Part(Vector3.new(12, 7, 3), base * CFrame.new(0, 0, -1.5), color, Enum.PartType.Block, 0.3)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = wave
	task.delay(delay * 0.5, function()
		tween(wave, 0.45, { CFrame = base * CFrame.new(0, -0.5, -22), Size = Vector3.new(14, 5, 4) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Connect(function()
			local splash = (base * CFrame.new(0, -0.5, -22)).Position
			EcoEfectos.Burst(splash, color, 40, 1.2, 50)
			EcoEfectos.Ring(EcoEfectos.Ground(splash) + Vector3.new(0, 0.3, 0), 9, color, 0.4, 0.6)
			EcoEfectos.Sound("AguaGrave", splash)
			fadeAndDestroy(wave, 0.25)
		end)
	end)
	EcoEfectos.Sound("Surf", ground)
end

-- Lluvia que cura alrededor del personaje
function EcoEfectos.Lluvia(character, color, duration)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, 8, 0)
	attachment.Parent = root
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = TEXTURES.Sparks
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.6
	emitter.Size = NumberSequence.new(0.25)
	emitter.Lifetime = NumberRange.new(0.5, 0.7)
	emitter.Speed = NumberRange.new(18, 24)
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.Rate = 70
	emitter.Parent = attachment
	EcoEfectos.Aura(character, Color3.fromRGB(120, 255, 170), duration)
	task.delay(duration, function()
		emitter.Enabled = false
		Debris:AddItem(attachment, 1)
	end)
end

-- Burbuja alrededor del atrapado
function EcoEfectos.Atrapado(model, color, duration)
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local bubble = EcoEfectos.Part(Vector3.new(7, 7, 7), root.CFrame, color, Enum.PartType.Ball, 0.7)
	local start = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not root.Parent or os.clock() - start >= duration then
			connection:Disconnect()
			if bubble.Parent then
				EcoEfectos.Burst(bubble.Position, color, 18, 0.8, 24)
				EcoEfectos.Sound("Agua", bubble.Position)
				bubble:Destroy()
			end
			return
		end
		bubble.CFrame = root.CFrame
	end)
end

-- ---------- Oscuridad ----------
function EcoEfectos.Fauces(origin, dir, color, range)
	local ground = EcoEfectos.Ground(origin)
	local right = Vector3.new(-dir.Z, 0, dir.X)
	for row = 1, 4 do
		for col = -row, row do
			local position = ground + dir * (row * range / 4) + right * (col * 1.3)
			local spike = EcoEfectos.Part(Vector3.new(0.8, 0.2, 0.8), CFrame.new(position), color, Enum.PartType.Block, 0.15)
			local height = 2.5 + math.random() * 2
			task.delay(row * 0.03, function()
				tween(spike, 0.08, { Size = Vector3.new(0.6, height, 0.6), CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(math.rad(math.random(-15, 15)), 0, math.rad(math.random(-15, 15))) }).Completed:Connect(function()
					task.delay(0.35, function()
						fadeAndDestroy(spike, 0.2, { Size = Vector3.new(0.2, 0.2, 0.2) })
					end)
				end)
			end)
		end
	end
	EcoEfectos.Sound("Grave", ground)
end

-- Sombra que queda donde empezó el Paso Sombrío (hasta que vuelves o caduca)
function EcoEfectos.Sombra(position, color, duration)
	local ground = EcoEfectos.Ground(position)
	local disc = EcoEfectos.Circulo(ground, 1.6, color, duration, 0.35)
	local pillar = EcoEfectos.Part(Vector3.new(1.2, 5, 1.2), CFrame.new(ground + Vector3.new(0, 2.5, 0)), color, Enum.PartType.Block, 0.65)
	task.delay(math.max(0, duration - 0.2), function()
		if pillar.Parent then
			fadeAndDestroy(pillar, 0.2)
		end
	end)
	return disc, pillar
end

-- Oscurece la pantalla un poco (Eclipse, solo en esta pantalla)
function EcoEfectos.Penumbra(duration)
	local camera = Workspace.CurrentCamera
	local tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "UmbralPenumbra"
	tint.Saturation = 0
	tint.TintColor = Color3.new(1, 1, 1)
	tint.Parent = camera
	tween(tint, 0.25, { Saturation = -0.45, TintColor = Color3.fromRGB(205, 185, 255), Brightness = -0.05 })
	task.delay(math.max(0, duration - 0.3), function()
		if tint.Parent then
			tween(tint, 0.3, { Saturation = 0, TintColor = Color3.new(1, 1, 1), Brightness = 0 }).Completed:Connect(function()
				tint:Destroy()
			end)
		end
	end)
end

-- ---------- Fuego ----------
function EcoEfectos.AnilloFuego(center, radius, color, duration)
	local ground = EcoEfectos.Ground(center)
	local ring = EcoEfectos.Part(Vector3.new(4, radius * 2, radius * 2), CFrame.new(ground + Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.PartType.Cylinder, 0.7)
	EcoEfectos.Circulo(ground, radius, color, duration, 0.8, TEXTURES.Fire)
	local start = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - start
		ring.CFrame = CFrame.new(ground + Vector3.new(0, 2, 0)) * CFrame.Angles(0, elapsed * 2, 0) * CFrame.Angles(0, 0, math.rad(90))
		ring.Transparency = 0.6 + math.sin(elapsed * 10) * 0.08
		if elapsed >= duration then
			connection:Disconnect()
			fadeAndDestroy(ring, 0.3)
		end
	end)
	EcoEfectos.Sound("Grave", ground)
end

-- Fuego pegado a una pieza (Meteoro): devuelve el emisor; se apaga solo a los 2 s
function EcoEfectos.Fire(part, color)
	if not part then
		return nil
	end
	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = TEXTURES.Fire
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.25, 0.45)
	emitter.Speed = NumberRange.new(2, 5)
	emitter.Rate = 80
	emitter.Parent = attachment
	task.delay(2, function()
		emitter.Enabled = false
		Debris:AddItem(attachment, 1)
	end)
	return emitter
end

-- ---------- Trueno ----------
function EcoEfectos.Totem(center, color, duration)
	local ground = EcoEfectos.Ground(center)
	local pole = EcoEfectos.Part(Vector3.new(0.6, 5, 0.6), CFrame.new(ground + Vector3.new(0, 2.5, 0)), Color3.fromRGB(70, 70, 90), Enum.PartType.Block, 0)
	pole.Material = Enum.Material.Metal
	local tip = EcoEfectos.Part(Vector3.new(1.4, 1.4, 1.4), CFrame.new(ground + Vector3.new(0, 5.3, 0)), color, Enum.PartType.Ball, 0.1)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 10
	light.Brightness = 2
	light.Parent = tip
	EcoEfectos.Rayo(ground + Vector3.new(0, 25, 0), ground + Vector3.new(0, 5.3, 0), color, 0.5)
	task.delay(duration, function()
		fadeAndDestroy(pole, 0.25)
		fadeAndDestroy(tip, 0.25)
	end)
end

function EcoEfectos.Nube(center, color, duration)
	local cloud = EcoEfectos.Part(Vector3.new(30, 3, 30), CFrame.new(center + Vector3.new(0, 22, 0)), Color3.fromRGB(40, 40, 60), Enum.PartType.Ball, 0.5)
	cloud.Material = Enum.Material.SmoothPlastic
	fadeAndDestroy(cloud, duration + 0.4)
	local _ = color
end

-- =====================================================================================================
-- ---------- Estilo: arcos, destellos y estelas (lo que hace que las habilidades se vean "de anime") ----------
-- Todo con piezas de neón (el brillo de la iluminación las hace resplandecer) y texturas que trae Roblox.
-- =====================================================================================================

local ELEMENT_TEXTURES = {
	Embers = "rbxasset://textures/particles/fire_sparks_main.dds",
	Vortex = "rbxasset://textures/particles/forcefield_vortex_main.dds",
}
local WHITE = Color3.new(1, 1, 1)

-- Arco de corte en media luna: núcleo blanco por fuera y borde de color, que BARRE en `sweep` s (aparece del
-- primer al último tramo) y se desvanece afinándose. El arco va de `fromDeg` a `toDeg`, medidos desde `axisA`
-- girando hacia `axisB` (p. ej. A = frente y B = derecha: un tajo horizontal de izquierda a derecha).
-- opts: width (grosor máximo), sweep, fade, core (false: sin núcleo blanco), transparency.
function EcoEfectos.Arco(center, axisA, axisB, radius, fromDeg, toDeg, color, opts)
	opts = opts or {}
	local width = opts.width or 1.1
	local sweep = (opts.sweep or 0.07) * EcoEfectos.Lento
	local fade = (opts.fade or 0.2) * EcoEfectos.Lento
	local base = opts.transparency or 0.12
	axisA, axisB = axisA.Unit, axisB.Unit
	local normal = axisA:Cross(axisB)
	if normal.Magnitude < 0.01 then
		return
	end
	normal = normal.Unit
	local from, to = math.rad(fromDeg), math.rad(toDeg)
	local length = radius * math.abs(to - from)
	local count = math.clamp(math.floor(length / 1.15), 6, 14)
	local segLength = length / count * 1.2
	local segments = {}
	for i = 1, count do
		local t = (i - 0.5) / count
		local angle = from + (to - from) * t
		local radial = axisA * math.cos(angle) + axisB * math.sin(angle)
		local profile = math.sin(math.pi * t) ^ 0.7 -- fino en las puntas, grueso en el medio
		local w = math.max(0.12, width * profile)
		local position = center + radial * radius
		local frame = CFrame.fromMatrix(position, radial, normal)
		local depth = math.max(0.3, w * 0.4) -- grosor en la normal: se ve aunque el arco quede de canto
		local outer = EcoEfectos.Part(Vector3.new(w, depth, segLength), frame, color, Enum.PartType.Block, 1)
		local halo = EcoEfectos.Part(Vector3.new(w * 1.7, depth * 1.8, segLength), frame, color, Enum.PartType.Block, 1)
		local core = nil
		if opts.core ~= false then
			core = EcoEfectos.Part(Vector3.new(w * 0.36, depth * 0.7, segLength), frame * CFrame.new(w * 0.28, 0, 0), WHITE, Enum.PartType.Block, 1)
		end
		segments[i] = { outer = outer, halo = halo, core = core, w = w, depth = depth, frame = frame, appear = (i - 1) / count * sweep }
	end
	local start = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - start
		local alive = false
		for _, seg in ipairs(segments) do
			local life = elapsed - seg.appear
			if life < 0 then
				alive = true
			else
				local k = math.clamp(life / fade, 0, 1)
				if k < 1 then
					alive = true
				end
				local thin = 1 - 0.75 * k
				seg.outer.Transparency = base + (1 - base) * k
				seg.outer.Size = Vector3.new(seg.w * thin, seg.depth, segLength)
				seg.halo.Transparency = 0.78 + 0.22 * k
				seg.halo.Size = Vector3.new(seg.w * 1.7 * thin, seg.depth * 1.8, segLength)
				if seg.core then
					seg.core.Transparency = k
					seg.core.Size = Vector3.new(seg.w * 0.36 * thin, seg.depth * 0.7, segLength)
					seg.core.CFrame = seg.frame * CFrame.new(seg.w * 0.28 * thin, 0, 0)
				end
			end
		end
		if not alive then
			connection:Disconnect()
			for _, seg in ipairs(segments) do
				seg.outer:Destroy()
				seg.halo:Destroy()
				if seg.core then
					seg.core:Destroy()
				end
			end
		end
	end)
end

-- Espiral: trazos de neón que suben girando alrededor de un eje vertical (viento, agua, fuego que asciende)
function EcoEfectos.Espiral(base, height, radius, color, duration, streaks)
	duration = (duration or 0.45) * EcoEfectos.Lento
	streaks = streaks or 3
	local parts = {}
	for i = 1, streaks do
		local part = EcoEfectos.Part(Vector3.new(0.35, 0.35, 2.2), CFrame.new(base), if i % 2 == 0 then WHITE else color, Enum.PartType.Block, 0.1)
		table.insert(parts, { part = part, phase = (i - 1) / streaks * math.pi * 2, lag = (i - 1) * 0.06 })
	end
	local start = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - start
		local done = true
		for _, s in ipairs(parts) do
			local t = math.clamp((elapsed - s.lag * EcoEfectos.Lento) / duration, 0, 1)
			if t < 1 then
				done = false
			end
			local angle = s.phase + t * math.pi * 3
			local r = radius * (1 - 0.35 * t)
			local position = base + Vector3.new(math.cos(angle) * r, height * t, math.sin(angle) * r)
			local tangent = Vector3.new(-math.sin(angle), 0.55, math.cos(angle)).Unit
			s.part.CFrame = CFrame.lookAt(position, position + tangent)
			s.part.Transparency = 0.1 + 0.9 * t
		end
		if done then
			connection:Disconnect()
			for _, s in ipairs(parts) do
				s.part:Destroy()
			end
		end
	end)
end

-- Escombros y grietas en el suelo (golpes contra el suelo): piedras del color del suelo que saltan en arco y
-- grietas oscuras que se abren. Sin física (no chocan con nadie): la trayectoria se calcula aquí.
function EcoEfectos.Escombros(position, strength)
	strength = strength or 1
	local ignore = { folder() }
	for _, other in ipairs(Players:GetPlayers()) do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	groundParams.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), groundParams)
	if not hit then
		return
	end
	local ground = hit.Position
	local rockColor = hit.Instance.Color
	local material = if hit.Material == Enum.Material.Neon or hit.Material == Enum.Material.Air then Enum.Material.Slate else hit.Material
	local rocks = {}
	for _ = 1, math.floor(7 * strength) do
		local size = 0.4 + math.random() * 0.7 * strength
		local rock = EcoEfectos.Part(Vector3.new(size, size * 0.8, size), CFrame.new(ground) * CFrame.Angles(math.random() * 6, math.random() * 6, 0), rockColor, Enum.PartType.Block, 0)
		rock.Material = material
		local angle = math.random() * math.pi * 2
		local speed = 10 + math.random() * 14 * strength
		table.insert(rocks, { part = rock, velocity = Vector3.new(math.cos(angle) * speed, 18 + math.random() * 16 * strength, math.sin(angle) * speed), spin = CFrame.Angles(math.random() * 0.4, math.random() * 0.4, 0) })
	end
	local start = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		local elapsed = os.clock() - start
		for _, r in ipairs(rocks) do
			if not r.landed then
				r.velocity += Vector3.new(0, -110 * dt, 0)
				local nextPosition = r.part.Position + r.velocity * dt
				if nextPosition.Y <= ground.Y + 0.2 and r.velocity.Y < 0 then
					nextPosition = Vector3.new(nextPosition.X, ground.Y + 0.2, nextPosition.Z)
					r.landed = true
				end
				r.part.CFrame = (r.part.CFrame - r.part.Position + nextPosition) * r.spin
			end
		end
		if elapsed > 1.1 then
			connection:Disconnect()
			for _, r in ipairs(rocks) do
				fadeAndDestroy(r.part, 0.4)
			end
		end
	end)
	-- Grietas: trazos oscuros que salen del centro
	for k = 1, 6 do
		local angle = (k / 6) * math.pi * 2 + math.random() * 0.5
		local length = (2.5 + math.random() * 2.5) * strength
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local crack = EcoEfectos.Part(Vector3.new(0.25, 0.06, 0.2), CFrame.lookAt(ground + Vector3.new(0, 0.04, 0), ground + Vector3.new(0, 0.04, 0) + dir), Color3.fromRGB(20, 16, 22), Enum.PartType.Block, 0.1)
		crack.Material = Enum.Material.SmoothPlastic
		tween(crack, 0.12, { Size = Vector3.new(0.3, 0.06, length), CFrame = CFrame.lookAt(ground + Vector3.new(0, 0.04, 0) + dir * length / 2, ground + Vector3.new(0, 0.04, 0) + dir * length) })
		task.delay(1.4, function()
			if crack.Parent then
				fadeAndDestroy(crack, 0.5)
			end
		end)
	end
end

-- Estampado contra la pared: onda en el muro, grietas en su plano, chispas y el aviso "¡PARED!"
function EcoEfectos.Pared(point, normal)
	if typeof(point) ~= "Vector3" or typeof(normal) ~= "Vector3" or normal.Magnitude < 0.1 then
		return
	end
	normal = normal.Unit
	EcoEfectos.OndaChoque(point + normal * 0.2, Color3.fromRGB(255, 230, 200), 4.5, normal, 0.3)
	EcoEfectos.Rayas(point + normal * 0.5, Color3.fromRGB(255, 220, 160), 8, 4)
	EcoEfectos.Burst(point + normal * 0.5, Color3.fromRGB(200, 190, 180), 18, 0.8, 26)
	local helper = if math.abs(normal.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis
	local right = helper:Cross(normal).Unit
	local up = normal:Cross(right).Unit
	for k = 1, 7 do
		local angle = (k / 7) * math.pi * 2 + math.random() * 0.4
		local dir = right * math.cos(angle) + up * math.sin(angle)
		local length = 1.8 + math.random() * 2.2
		local base = point + normal * 0.06
		local crack = EcoEfectos.Part(Vector3.new(0.22, 0.22, length), CFrame.lookAt(base + dir * length / 2, base + dir * length), Color3.fromRGB(22, 18, 24), Enum.PartType.Block, 0.1)
		crack.Material = Enum.Material.SmoothPlastic
		task.delay(1.4, function()
			if crack.Parent then
				fadeAndDestroy(crack, 0.5)
			end
		end)
	end
	local anchor = EcoEfectos.Part(Vector3.new(0.2, 0.2, 0.2), CFrame.new(point + normal * 1.5), Color3.new(1, 1, 1), nil, 1)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 40)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.StudsOffset = Vector3.new(0, 2.5, 0)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = "¡PARED!"
	label.TextColor3 = Color3.fromRGB(255, 225, 150)
	label.TextStrokeTransparency = 0
	label.Parent = gui
	gui.Parent = anchor
	tween(label, 0.6, { TextTransparency = 1, TextStrokeTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	Debris:AddItem(anchor, 0.8)
	EcoEfectos.Sound("Grave", point)
end

-- Reacción entre elementos (la decide el servidor; se ve en todas las pantallas)
local REACTION_LOOK = {
	["ELECTROCUCIÓN"] = { color = Color3.fromRGB(255, 240, 120), element = "Trueno" },
	VAPOR = { color = Color3.fromRGB(235, 245, 255), element = "Agua" },
	["TORMENTA ÍGNEA"] = { color = Color3.fromRGB(255, 120, 40), element = "Fuego" },
	["PULSO UMBRÍO"] = { color = Color3.fromRGB(180, 90, 255), element = "Oscuridad" },
	["CONDUCCIÓN"] = { color = Color3.fromRGB(120, 220, 255), element = "Trueno" },
}
function EcoEfectos.Reaccion(name, center)
	local look = REACTION_LOOK[name]
	if not look or typeof(center) ~= "Vector3" then
		return
	end
	EcoEfectos.Destello(center, look.color, 8, 0.22)
	EcoEfectos.Elemento(center, look.element, 2)
	EcoEfectos.OndaChoque(EcoEfectos.Ground(center) + Vector3.new(0, 0.4, 0), look.color, if name == "VAPOR" then 8 else 6, Vector3.yAxis, 0.35)
	if name == "VAPOR" then
		EcoEfectos.Elemento(center + Vector3.new(0, 1.5, 0), "Agua", 2)
		EcoEfectos.Espiral(EcoEfectos.Ground(center), 8, 3, look.color, 0.5, 4)
	elseif name == "TORMENTA ÍGNEA" then
		EcoEfectos.Espiral(EcoEfectos.Ground(center), 9, 4, look.color, 0.5, 5)
	elseif name == "PULSO UMBRÍO" then
		EcoEfectos.Rayas(center, look.color, 12, 6)
	end
end

-- Tajo horizontal delante de un personaje (o de un punto) hacia `dir`, un poco inclinado
function EcoEfectos.Tajo(origin, dir, color, radius, tiltDeg, opts)
	local flat = Vector3.new(dir.X, 0, dir.Z)
	flat = if flat.Magnitude > 0.05 then flat.Unit else Vector3.new(0, 0, -1)
	local right = flat:Cross(Vector3.yAxis).Unit
	local tilt = math.rad(tiltDeg or 0)
	local up = Vector3.yAxis * math.cos(tilt) + right * math.sin(tilt)
	local axisB = up:Cross(flat).Unit -- "derecha" inclinada
	EcoEfectos.Arco(origin, flat, axisB, radius or 3.4, -80, 80, color, opts)
end

-- Destello de impacto: estrella de agujas de neón mirando a la cámara, que se abre y se cierra en un instante
function EcoEfectos.Destello(position, color, size, duration)
	size = size or 4.5
	duration = (duration or 0.16) * EcoEfectos.Lento
	local camera = Workspace.CurrentCamera
	local toCamera = if camera then camera.CFrame.Position - position else Vector3.new(0, 0, 1)
	if toCamera.Magnitude < 0.01 then
		toCamera = Vector3.new(0, 0, 1)
	end
	local base = CFrame.lookAt(position, position + toCamera.Unit)
	local spin = math.random() * math.pi
	local rays = {}
	for k = 0, 3 do
		local long = k % 2 == 0
		local length = size * (if long then 1 else 0.55)
		local frame = base * CFrame.Angles(0, 0, spin + k * math.pi / 4) * CFrame.Angles(0, math.rad(90), 0)
		for layer = 1, 2 do
			local thickness = size * (if layer == 1 then 0.16 else 0.07)
			local part = EcoEfectos.Part(Vector3.new(thickness, thickness, length * (if layer == 1 then 1.1 else 1)), frame, if layer == 1 then color else WHITE, Enum.PartType.Block, if layer == 1 then 0.35 else 0)
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Scale = Vector3.new(0.2, 0.2, 0.2)
			mesh.Parent = part
			table.insert(rays, { part = part, mesh = mesh, base = part.Transparency })
		end
	end
	local start = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local t = (os.clock() - start) / duration
		local scale = if t < 0.3 then 0.2 + 0.8 * (t / 0.3) else math.max(0, 1 - (t - 0.3) / 0.7)
		for _, ray in ipairs(rays) do
			ray.mesh.Scale = Vector3.new(math.max(scale, 0.05), math.max(scale, 0.05), math.max(scale * 1.15, 0.05))
			ray.part.Transparency = ray.base + (1 - ray.base) * math.clamp((t - 0.5) / 0.5, 0, 1)
		end
		if t >= 1 then
			connection:Disconnect()
			for _, ray in ipairs(rays) do
				ray.part:Destroy()
			end
		end
	end)
end

-- Rayas de velocidad que salen disparadas del punto de impacto (en 3D)
function EcoEfectos.Rayas(position, color, count, length, duration)
	count = count or 6
	length = length or 4
	duration = (duration or 0.16) * EcoEfectos.Lento
	local streaks = {}
	for _ = 1, count do
		local dir = Vector3.new(math.random() - 0.5, (math.random() - 0.3) * 0.9, math.random() - 0.5)
		dir = if dir.Magnitude > 0.05 then dir.Unit else Vector3.new(1, 0, 0)
		local part = EcoEfectos.Part(Vector3.new(0.1, 0.1, 0.5), CFrame.lookAt(position, position + dir), if math.random() < 0.5 then WHITE else color, Enum.PartType.Block, 0.05)
		table.insert(streaks, { part = part, dir = dir, length = length * (0.6 + math.random() * 0.6) })
	end
	local start = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local t = math.clamp((os.clock() - start) / duration, 0, 1)
		local ease = 1 - (1 - t) ^ 3
		for _, s in ipairs(streaks) do
			local len = s.length * (0.25 + 0.75 * ease) * (1 - t * 0.5)
			local head = position + s.dir * (0.6 + s.length * ease)
			s.part.Size = Vector3.new(0.1 * (1 - t) + 0.02, 0.1 * (1 - t) + 0.02, len)
			s.part.CFrame = CFrame.lookAt(head - s.dir * len / 2, head)
			s.part.Transparency = 0.05 + 0.95 * t
		end
		if t >= 1 then
			connection:Disconnect()
			for _, s in ipairs(streaks) do
				s.part:Destroy()
			end
		end
	end)
end

-- Onda de choque con textura (plana, perpendicular a `normal`; por defecto, en el suelo)
function EcoEfectos.OndaChoque(position, color, radius, normal, duration)
	normal = (normal or Vector3.yAxis).Unit
	local helper = if math.abs(normal.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis
	local right = helper:Cross(normal).Unit
	local anchor = EcoEfectos.Part(Vector3.new(0.2, 0.2, 0.2), CFrame.fromMatrix(position, right, normal), color, nil, 1)
	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = TEXTURES.Shockwave
	emitter.Color = ColorSequence.new(WHITE:Lerp(color, 0.5), color)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Speed = NumberRange.new(0.01)
	emitter.SpreadAngle = Vector2.new(0, 0)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, radius * 2) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new((duration or 0.28) * EcoEfectos.Lento)
	emitter.LockedToPart = true
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(1)
	Debris:AddItem(anchor, (duration or 0.28) + 0.2)
end

-- Partículas propias de cada elemento: viento (chispas blancas), agua (gotas), oscuridad (humo), fuego (brasas),
-- trueno (chispazos). `amount` multiplica la cantidad.
function EcoEfectos.Elemento(position, element, amount)
	amount = amount or 1
	local anchor = EcoEfectos.Part(Vector3.new(0.2, 0.2, 0.2), CFrame.new(position), WHITE, nil, 1)
	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor
	local function emit(props, count)
		local emitter = Instance.new("ParticleEmitter")
		emitter.Rate = 0
		emitter.LightInfluence = 0
		for key, value in pairs(props) do
			emitter[key] = value
		end
		emitter.Parent = attachment
		emitter:Emit(math.max(1, math.floor(count * amount + 0.5)))
	end
	if element == "Agua" then
		emit({ Texture = TEXTURES.Sparks, Color = ColorSequence.new(Color3.fromRGB(200, 240, 255), Color3.fromRGB(70, 160, 255)), LightEmission = 0.7, Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0.1) }), Lifetime = NumberRange.new(0.35, 0.7), Speed = NumberRange.new(14, 30), SpreadAngle = Vector2.new(70, 70), EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, -70, 0), Drag = 1 }, 18)
		emit({ Texture = TEXTURES.Smoke, Color = ColorSequence.new(Color3.fromRGB(180, 225, 255)), LightEmission = 0.4, Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 3.5) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }), Lifetime = NumberRange.new(0.3, 0.5), Speed = NumberRange.new(3, 8), SpreadAngle = Vector2.new(180, 180) }, 5)
	elseif element == "Fuego" then
		emit({ Texture = ELEMENT_TEXTURES.Embers, Color = ColorSequence.new(Color3.fromRGB(255, 230, 120), Color3.fromRGB(255, 90, 20)), LightEmission = 1, Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }), Lifetime = NumberRange.new(0.4, 0.9), Speed = NumberRange.new(10, 24), SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, 18, 0), Drag = 3 }, 16)
		emit({ Texture = TEXTURES.Fire, Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 60, 10)), LightEmission = 1, Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.4), NumberSequenceKeypoint.new(1, 0) }), Lifetime = NumberRange.new(0.2, 0.4), Speed = NumberRange.new(4, 10), SpreadAngle = Vector2.new(180, 180) }, 8)
	elseif element == "Oscuridad" then
		emit({ Texture = TEXTURES.Smoke, Color = ColorSequence.new(Color3.fromRGB(70, 20, 110), Color3.fromRGB(15, 5, 25)), LightEmission = 0, Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 4.5) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }), Lifetime = NumberRange.new(0.45, 0.85), Speed = NumberRange.new(3, 8), SpreadAngle = Vector2.new(180, 180), RotSpeed = NumberRange.new(-90, 90) }, 9)
		emit({ Texture = TEXTURES.Sparks, Color = ColorSequence.new(Color3.fromRGB(220, 160, 255)), LightEmission = 1, Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }), Lifetime = NumberRange.new(0.15, 0.35), Speed = NumberRange.new(18, 34), SpreadAngle = Vector2.new(180, 180), Drag = 6 }, 10)
	elseif element == "Trueno" then
		emit({ Texture = TEXTURES.Sparks, Color = ColorSequence.new(WHITE, Color3.fromRGB(255, 235, 90)), LightEmission = 1, Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }), Lifetime = NumberRange.new(0.08, 0.22), Speed = NumberRange.new(30, 55), SpreadAngle = Vector2.new(180, 180), Drag = 9 }, 20)
		for _ = 1, 2 do
			local dir = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
			if dir.Magnitude > 0.05 then
				EcoEfectos.Rayo(position, position + dir.Unit * (2.5 + math.random() * 2), Color3.fromRGB(255, 240, 140), 0.18, true)
			end
		end
	else -- Viento (y cualquier otro)
		emit({ Texture = TEXTURES.Sparks, Color = ColorSequence.new(WHITE, Color3.fromRGB(150, 255, 230)), LightEmission = 1, Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }), Lifetime = NumberRange.new(0.15, 0.35), Speed = NumberRange.new(20, 40), SpreadAngle = Vector2.new(180, 180), Drag = 5 }, 14)
		emit({ Texture = ELEMENT_TEXTURES.Vortex, Color = ColorSequence.new(Color3.fromRGB(200, 255, 240)), LightEmission = 1, Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 4) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }), Lifetime = NumberRange.new(0.25), Speed = NumberRange.new(0), RotSpeed = NumberRange.new(400, 600) }, 1)
	end
	Debris:AddItem(anchor, 1.2)
end

-- Estelas de color en manos y pies mientras dura una habilidad (blanco que se tiñe del color del Eco)
local LIMBS = { "RightHand", "LeftHand", "RightFoot", "LeftFoot", "Right Arm", "Left Arm", "Right Leg", "Left Leg" }
function EcoEfectos.Estela(character, color, duration)
	if not character then
		return
	end
	duration = duration or 0.45
	local untilTime = os.clock() + duration
	for _, name in ipairs(LIMBS) do
		local limb = character:FindFirstChild(name)
		if limb and limb:IsA("BasePart") then
			local trail = limb:FindFirstChild("UmbralEstelaEco")
			if not trail then
				local r6 = limb.Size.Y > 1.5 -- brazo o pierna entera (R6): la estela va en la punta
				local tip = if r6 then -limb.Size.Y / 2 + 0.2 else 0
				local a0 = Instance.new("Attachment")
				a0.Name = "UmbralEstelaEcoA"
				a0.Position = Vector3.new(0, tip + 0.28, 0)
				a0.Parent = limb
				local a1 = Instance.new("Attachment")
				a1.Name = "UmbralEstelaEcoB"
				a1.Position = Vector3.new(0, tip - 0.28, 0)
				a1.Parent = limb
				trail = Instance.new("Trail")
				trail.Name = "UmbralEstelaEco"
				trail.Attachment0 = a0
				trail.Attachment1 = a1
				trail.LightEmission = 1
				trail.Lifetime = 0.24
				trail.FaceCamera = true
				trail.MinLength = 0.05
				trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
				trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.15) })
				trail.Parent = limb
			end
			trail.Color = ColorSequence.new(WHITE:Lerp(color, 0.35), color)
			trail.Enabled = true
			trail:SetAttribute("Hasta", untilTime)
			task.delay(duration, function()
				if trail.Parent and (trail:GetAttribute("Hasta") or 0) <= os.clock() + 0.01 then
					trail.Enabled = false
				end
			end)
		end
	end
end

-- Cuadro de impacto: un instante de alto contraste y casi sin color (y un velo blanco) en los golpes grandes.
-- Se apaga con el ajuste "Destellos al golpear" del menú.
local impactEffect, impactGui = nil, nil
function EcoEfectos.ImpactFrame(color, strength)
	local feedback = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("CombatConfig")).Feedback
	if not feedback.Flashes then
		return
	end
	strength = strength or 1
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	if not impactEffect or not impactEffect.Parent then
		impactEffect = Instance.new("ColorCorrectionEffect")
		impactEffect.Name = "UmbralCuadroImpacto"
		impactEffect.Parent = camera
	end
	impactEffect.Contrast = 0.55 * strength
	impactEffect.Saturation = -0.55 * strength
	impactEffect.Brightness = 0.1 * strength
	impactEffect.TintColor = WHITE:Lerp(color, 0.2)
	task.delay(0.05, function()
		tween(impactEffect, 0.18, { Contrast = 0, Saturation = 0, Brightness = 0, TintColor = WHITE })
	end)
	local player = Players.LocalPlayer
	if not impactGui or not impactGui.Parent then
		impactGui = Instance.new("ScreenGui")
		impactGui.Name = "UmbralVeloImpacto"
		impactGui.IgnoreGuiInset = true
		impactGui.ResetOnSpawn = false
		impactGui.DisplayOrder = 3
		local frame = Instance.new("Frame")
		frame.Name = "Velo"
		frame.Size = UDim2.fromScale(1, 1)
		frame.BorderSizePixel = 0
		frame.BackgroundTransparency = 1
		frame.Parent = impactGui
		impactGui.Parent = player:WaitForChild("PlayerGui")
	end
	local veil = impactGui.Velo
	veil.BackgroundColor3 = WHITE:Lerp(color, 0.3)
	veil.BackgroundTransparency = 1 - 0.32 * strength
	tween(veil, 0.14, { BackgroundTransparency = 1 })
end


-- ---------- Estados visibles en los enemigos ----------
-- Fuego encima de quien arde (atributo ArdeHasta) y un rombo morado sobre quien está marcado (MarcadoHasta).
-- Los decide el servidor; aquí solo se muestran.
function EcoEfectos.WatchStates()
	local CollectionService = game:GetService("CollectionService")
	local FIRE = Color3.fromRGB(255, 120, 40)
	local MARK = Color3.fromRGB(190, 110, 255)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.15 then
			return
		end
		elapsed = 0
		local now = Workspace:GetServerTimeNow()
		for _, model in ipairs(CollectionService:GetTagged("Objetivo")) do
			local root = model:FindFirstChild("HumanoidRootPart")
			if root then
				local burning = (model:GetAttribute("ArdeHasta") or 0) > now
				local fire = root:FindFirstChild("UmbralArde")
				if burning and not fire then
					fire = Instance.new("ParticleEmitter")
					fire.Name = "UmbralArde"
					fire.Texture = TEXTURES.Fire
					fire.Color = ColorSequence.new(FIRE)
					fire.LightEmission = 1
					fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0) })
					fire.Lifetime = NumberRange.new(0.3, 0.6)
					fire.Speed = NumberRange.new(3, 6)
					fire.Rate = 40
					fire.Parent = root
				elseif not burning and fire then
					fire:Destroy()
				end
				for _, state in ipairs({
					{ attribute = "MojadoHasta", name = "UmbralMojado", color = Color3.fromRGB(110, 190, 255), accel = Vector3.new(0, -25, 0), speed = 1, light = 0.5 },
					{ attribute = "CargadoHasta", name = "UmbralCargado", color = Color3.fromRGB(255, 240, 110), accel = Vector3.zero, speed = 6, light = 1 },
				}) do
					local active = (model:GetAttribute(state.attribute) or 0) > now
					local emitter = root:FindFirstChild(state.name)
					if active and not emitter then
						emitter = Instance.new("ParticleEmitter")
						emitter.Name = state.name
						emitter.Texture = TEXTURES.Sparks
						emitter.Color = ColorSequence.new(state.color)
						emitter.LightEmission = state.light
						emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
						emitter.Lifetime = NumberRange.new(0.25, 0.5)
						emitter.Speed = NumberRange.new(state.speed * 0.5, state.speed)
						emitter.SpreadAngle = Vector2.new(180, 180)
						emitter.Acceleration = state.accel
						emitter.Rate = 22
						emitter.Shape = Enum.ParticleEmitterShape.Box
						emitter.Parent = root
					elseif not active and emitter then
						emitter:Destroy()
					end
				end
				-- Furia del Guardián: aura roja y rugido (una vez por fase)
				local fury = model:GetAttribute("Furia") == true
				local aura = model:FindFirstChild("UmbralFuria")
				if fury and not aura then
					aura = Instance.new("Highlight")
					aura.Name = "UmbralFuria"
					aura.FillColor = Color3.fromRGB(255, 40, 40)
					aura.FillTransparency = 0.7
					aura.OutlineColor = Color3.fromRGB(255, 90, 60)
					aura.OutlineTransparency = 0
					aura.Parent = model
					EcoEfectos.OndaChoque(EcoEfectos.Ground(root.Position) + Vector3.new(0, 0.4, 0), Color3.fromRGB(255, 60, 40), 14, Vector3.yAxis, 0.6)
					EcoEfectos.Rayas(root.Position, Color3.fromRGB(255, 80, 50), 14, 8)
					EcoEfectos.ImpactFrame(Color3.fromRGB(255, 50, 40), 0.8)
					EcoEfectos.Sound("Grave", root.Position)
					local player = Players.LocalPlayer
					local gui = Instance.new("ScreenGui")
					gui.Name = "UmbralAvisoFuria"
					gui.ResetOnSpawn = false
					local label = Instance.new("TextLabel")
					label.AnchorPoint = Vector2.new(0.5, 0.5)
					label.Position = UDim2.fromScale(0.5, 0.22)
					label.Size = UDim2.fromOffset(620, 46)
					label.BackgroundTransparency = 1
					label.Font = Enum.Font.GothamBlack
					label.TextScaled = true
					label.Text = "¡EL GUARDIÁN SE ENFURECE!"
					label.TextColor3 = Color3.fromRGB(255, 90, 70)
					label.TextStrokeTransparency = 0
					label.Parent = gui
					gui.Parent = player:WaitForChild("PlayerGui")
					task.delay(1.6, function()
						tween(label, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 })
						Debris:AddItem(gui, 0.5)
					end)
				elseif not fury and aura then
					aura:Destroy()
				end
				local wallUntil = model:GetAttribute("ParedHasta")
				if wallUntil and wallUntil > now and model:GetAttribute("UmbralParedVista") ~= wallUntil then
					model:SetAttribute("UmbralParedVista", wallUntil)
					EcoEfectos.Pared(model:GetAttribute("ParedPunto"), model:GetAttribute("ParedNormal"))
				end
				local marked = (model:GetAttribute("MarcadoHasta") or 0) > now
				local markGui = root:FindFirstChild("UmbralMarca")
				if marked and not markGui then
					markGui = Instance.new("BillboardGui")
					markGui.Name = "UmbralMarca"
					markGui.Size = UDim2.fromOffset(26, 26)
					markGui.StudsOffset = Vector3.new(0, 4.2, 0)
					markGui.AlwaysOnTop = true
					markGui.LightInfluence = 0
					local diamond = Instance.new("Frame")
					diamond.AnchorPoint = Vector2.new(0.5, 0.5)
					diamond.Position = UDim2.fromScale(0.5, 0.5)
					diamond.Size = UDim2.fromScale(0.7, 0.7)
					diamond.Rotation = 45
					diamond.BackgroundColor3 = MARK
					diamond.BorderSizePixel = 0
					local stroke = Instance.new("UIStroke")
					stroke.Color = Color3.new(1, 1, 1)
					stroke.Thickness = 2
					stroke.Parent = diamond
					diamond.Parent = markGui
					markGui.Parent = root
				elseif not marked and markGui then
					markGui:Destroy()
				end
			end
		end
	end)
end

return EcoEfectos
