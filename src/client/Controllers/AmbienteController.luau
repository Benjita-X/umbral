-- AmbienteController: vida en el ambiente de los mapas (solo se ve; no cambia nada del juego).
--   · Piezas "Motas": polvo de luz que flota lento dentro de su volumen, del color de la pieza.
--   · Piezas "Niebla": bruma baja que se arrastra (el foso del Abismo).
-- Las piezas las pone el mapa (tools/mazmorra.mjs) invisibles y sin colisión; aquí se les añaden las partículas
-- (con las texturas que trae Roblox: no hay que subir nada).

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local AmbienteController = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function motes(part)
	local volume = part.Size.X * part.Size.Y * part.Size.Z
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "UmbralMotas"
	emitter.Texture = SPARKLE
	emitter.Color = ColorSequence.new(part.Color)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, 0.22),
		NumberSequenceKeypoint.new(0.8, 0.16),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, 0.25),
		NumberSequenceKeypoint.new(0.75, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(5, 9)
	emitter.Speed = NumberRange.new(0.2, 0.7)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 0.12, 0)
	emitter.RotSpeed = NumberRange.new(-40, 40)
	emitter.Rate = math.clamp(volume / 900, 3, 22)
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.Parent = part
end

local function mist(part)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "UmbralNiebla"
	emitter.Texture = SMOKE
	emitter.Color = ColorSequence.new(part.Color)
	emitter.LightEmission = 0.6
	emitter.LightInfluence = 0.2
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 11) })
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.82),
		NumberSequenceKeypoint.new(0.7, 0.86),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(6, 10)
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = Vector2.new(180, 20)
	emitter.RotSpeed = NumberRange.new(-12, 12)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Rate = 7
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.Parent = part
end

local HANDLERS = { Motas = motes, Niebla = mist }

local function decorate(instance)
	if instance:IsA("BasePart") and HANDLERS[instance.Name] and not instance:FindFirstChildOfClass("ParticleEmitter") then
		local ok, err = pcall(HANDLERS[instance.Name], instance)
		if not ok then
			warn("[UMBRAL] Ambiente: " .. tostring(err))
		end
	end
end

function AmbienteController.Start()
	local maps = Workspace:WaitForChild("Maps", 20)
	if not maps then
		return
	end
	for _, descendant in ipairs(maps:GetDescendants()) do
		decorate(descendant)
	end
	maps.DescendantAdded:Connect(decorate)
	CollectionService:GetInstanceAddedSignal("Ambiente"):Connect(decorate)
end

return AmbienteController
