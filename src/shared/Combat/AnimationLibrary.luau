-- AnimationLibrary: animaciones de combate PROVISIONALES generadas por código (Fase 2).
--
-- Cada clip se arma con poses del esqueleto R15 (KeyframeSequence) y se registra con
-- KeyframeSequenceProvider, que da un ID temporal válido en Studio. Los tiempos de los golpes
-- salen de CombatConfig, así que la animación y la lógica nunca se desincronizan.
--
-- Antes de publicar el juego: subir estas animaciones a Roblox (o reemplazarlas por otras hechas
-- por un animador) y poner sus IDs en CombatConfig.AnimationIds. Ver docs/DECISIONES.md.
--
-- Convención de ángulos (grados, en el espacio de cada articulación del R15):
--   X+: brazo o pierna hacia adelante (90 = horizontal al frente); en codo/rodilla, flexión.
--       En el torso, X+ inclina hacia atrás.
--   Y+: el torso o la cabeza giran hacia la izquierda.
--   Z+: el brazo derecho se abre hacia afuera (el izquierdo, hacia adentro).

local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local CombatConfig = require(script.Parent.Parent:WaitForChild("Config"):WaitForChild("CombatConfig"))

local AnimationLibrary = {}

-- Jerarquía de articulaciones del R15: cada Pose cuelga de la de su parte padre
local HIERARCHY = {
	HumanoidRootPart = { "LowerTorso" },
	LowerTorso = { "UpperTorso", "LeftUpperLeg", "RightUpperLeg" },
	UpperTorso = { "Head", "LeftUpperArm", "RightUpperArm" },
	LeftUpperArm = { "LeftLowerArm" },
	LeftLowerArm = { "LeftHand" },
	RightUpperArm = { "RightLowerArm" },
	RightLowerArm = { "RightHand" },
	LeftUpperLeg = { "LeftLowerLeg" },
	LeftLowerLeg = { "LeftFoot" },
	RightUpperLeg = { "RightLowerLeg" },
	RightLowerLeg = { "RightFoot" },
}

local UPPER_BODY = { "UpperTorso", "Head", "LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm" }
local FULL_BODY = {
	"LowerTorso",
	"UpperTorso",
	"Head",
	"LeftUpperArm",
	"LeftLowerArm",
	"RightUpperArm",
	"RightLowerArm",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"RightUpperLeg",
	"RightLowerLeg",
}

-- Poses (ángulos en grados: { x, y, z })
local GUARD_LEFT = { LeftUpperArm = { 55, 0, 10 }, LeftLowerArm = { 110, 0, 0 } }
local GUARD_RIGHT = { RightUpperArm = { 55, 0, -10 }, RightLowerArm = { 110, 0, 0 } }

local function merge(...)
	local result = {}
	for _, t in ipairs({ ... }) do
		for k, v in pairs(t) do
			result[k] = v
		end
	end
	return result
end

local POSES = {
	JabImpact = merge(GUARD_RIGHT, {
		UpperTorso = { -6, -18, 0 },
		Head = { 0, 15, 0 },
		LeftUpperArm = { 88, 0, 6 },
		LeftLowerArm = { 4, 0, 0 },
	}),
	CrossImpact = merge(GUARD_LEFT, {
		UpperTorso = { -8, 30, 0 },
		Head = { 0, -25, 0 },
		RightUpperArm = { 88, 0, -6 },
		RightLowerArm = { 3, 0, 0 },
	}),
	KickChamber = {
		LowerTorso = { 6, 0, 0 },
		UpperTorso = { 8, 10, 0 },
		RightUpperLeg = { 80, 0, 0 },
		RightLowerLeg = { -100, 0, 0 },
		LeftUpperLeg = { 5, 0, 0 },
		LeftLowerLeg = { -15, 0, 0 },
		RightUpperArm = { -15, 0, 25 },
		RightLowerArm = { 30, 0, 0 },
		LeftUpperArm = { 45, 0, 10 },
		LeftLowerArm = { 95, 0, 0 },
	},
	KickImpact = {
		LowerTorso = { 10, 0, 0 },
		UpperTorso = { 10, 10, 0 },
		Head = { -10, -8, 0 },
		RightUpperLeg = { 95, 0, 0 },
		RightLowerLeg = { -5, 0, 0 },
		LeftUpperLeg = { 10, 0, 0 },
		LeftLowerLeg = { -20, 0, 0 },
		RightUpperArm = { -25, 0, 30 },
		RightLowerArm = { 20, 0, 0 },
		LeftUpperArm = { 40, 0, 10 },
		LeftLowerArm = { 90, 0, 0 },
	},
	HeavyWindup = {
		UpperTorso = { -10, -40, 0 },
		Head = { 0, 35, 0 },
		RightUpperArm = { -35, 0, 15 },
		RightLowerArm = { 95, 0, 0 },
		LeftUpperArm = { 70, 0, 15 },
		LeftLowerArm = { 60, 0, 0 },
	},
	HeavyImpact = {
		UpperTorso = { -15, 45, 0 },
		Head = { 0, -35, 0 },
		RightUpperArm = { 92, 0, -4 },
		RightLowerArm = { 0, 0, 0 },
		LeftUpperArm = { -25, 0, 0 },
		LeftLowerArm = { 80, 0, 0 },
	},
	Guard = {
		UpperTorso = { -8, 0, 0 },
		Head = { -10, 0, 0 },
		RightUpperArm = { 80, 0, -25 },
		RightLowerArm = { 115, 0, 0 },
		LeftUpperArm = { 80, 0, 25 },
		LeftLowerArm = { 115, 0, 0 },
	},
	Hit = {
		UpperTorso = { 22, 0, 0 },
		Head = { 18, 0, 0 },
		RightUpperArm = { -20, 0, 20 },
		LeftUpperArm = { -20, 0, -20 },
	},
	HitHeavy = {
		LowerTorso = { 10, 0, 0 },
		UpperTorso = { 40, 0, 0 },
		Head = { 25, 0, 0 },
		RightUpperArm = { -45, 0, 40 },
		LeftUpperArm = { -45, 0, -40 },
	},
	-- Fase 3
	Deflect = { -- antebrazo derecho que barre hacia afuera, el izquierdo en guardia
		UpperTorso = { -6, -15, 0 },
		Head = { 0, 10, 0 },
		RightUpperArm = { 95, 0, 25 },
		RightLowerArm = { 70, 0, 0 },
		LeftUpperArm = { 60, 0, 15 },
		LeftLowerArm = { 105, 0, 0 },
	},
	Stunned = { -- encorvado, brazos caídos
		LowerTorso = { -5, 0, 0 },
		UpperTorso = { -25, 0, 8 },
		Head = { -20, 0, 0 },
		RightUpperArm = { -8, 0, 8 },
		LeftUpperArm = { -8, 0, -8 },
		RightLowerArm = { 15, 0, 0 },
		LeftLowerArm = { 15, 0, 0 },
	},
	SparringCock = { -- Golpe: brazo derecho arriba y atrás, torso girado (se lee de lejos)
		UpperTorso = { 10, -30, 0 },
		Head = { 0, 25, 0 },
		RightUpperArm = { 160, 0, 20 },
		RightLowerArm = { 60, 0, 0 },
		LeftUpperArm = { 60, 0, 15 },
		LeftLowerArm = { 90, 0, 0 },
	},
	SparringStrike = {
		UpperTorso = { -20, 30, 0 },
		Head = { 0, -25, 0 },
		RightUpperArm = { 80, 0, -5 },
		RightLowerArm = { 0, 0, 0 },
		LeftUpperArm = { -20, 0, 0 },
		LeftLowerArm = { 70, 0, 0 },
	},
	SweepCrouch = { -- Barrido: agachado con los brazos abiertos (silueta distinta al Golpe)
		LowerTorso = { -10, 0, 0, p = Vector3.new(0, -0.8, 0) },
		UpperTorso = { -15, 0, 0 },
		RightUpperLeg = { 60, 0, 0 },
		RightLowerLeg = { -90, 0, 0 },
		LeftUpperLeg = { 60, 0, 0 },
		LeftLowerLeg = { -90, 0, 0 },
		RightUpperArm = { 20, 0, 70 },
		LeftUpperArm = { 20, 0, -70 },
	},
}

-- Barrido: agachado y girando con la pierna estirada
local function sweepSpin(angle)
	return {
		LowerTorso = { -10, angle, 0, p = Vector3.new(0, -0.9, 0) },
		UpperTorso = { -10, 0, 0 },
		RightUpperLeg = { 20, 0, 80 },
		RightLowerLeg = { 0, 0, 0 },
		LeftUpperLeg = { 70, 0, 0 },
		LeftLowerLeg = { -100, 0, 0 },
		RightUpperArm = { 0, 0, 80 },
		LeftUpperArm = { 0, 0, -80 },
	}
end

local NEUTRAL = {}

local function toCFrame(spec)
	if not spec then
		return CFrame.identity
	end
	local offset = spec.p or Vector3.zero
	return CFrame.new(offset) * CFrame.Angles(math.rad(spec[1] or 0), math.rad(spec[2] or 0), math.rad(spec[3] or 0))
end

-- Clip de un golpe: neutro → (preparación) → impacto al empezar "active" → se mantiene → neutro al terminar
local function attackClip(attackName, impact, joints, chamber)
	local a = CombatConfig.Attacks[attackName]
	local keyframes = { { time = 0, poses = NEUTRAL } }
	if chamber then
		table.insert(keyframes, { time = a.startup * 0.55, poses = chamber })
	end
	table.insert(keyframes, { time = a.startup, poses = impact })
	table.insert(keyframes, { time = a.startup + a.active, poses = impact })
	table.insert(keyframes, { time = a.startup + a.active + a.recovery, poses = NEUTRAL })
	return { joints = joints, priority = Enum.AnimationPriority.Action, keyframes = keyframes }
end

local function holdClip(pose, joints, enterTime)
	return {
		joints = joints,
		priority = Enum.AnimationPriority.Action,
		keyframes = {
			{ time = 0, poses = NEUTRAL },
			{ time = enterTime, poses = pose },
			{ time = 10, poses = pose }, -- se mantiene hasta que se detiene la pista
		},
	}
end

local UPPER_BODY_WITH_ROOT = { "LowerTorso", table.unpack(UPPER_BODY) }

local function reactionClip(pose, peak, total)
	return {
		joints = UPPER_BODY_WITH_ROOT,
		priority = Enum.AnimationPriority.Action2,
		keyframes = {
			{ time = 0, poses = NEUTRAL },
			{ time = peak, poses = pose },
			{ time = total, poses = NEUTRAL },
		},
	}
end

local function buildClips()
	local heavy = CombatConfig.Attacks.Fuerte
	local defense = CombatConfig.Defense
	local golpe = CombatConfig.Sparring.Attacks.Golpe
	local barrido = CombatConfig.Sparring.Attacks.Barrido
	return {
		Jab = attackClip("Jab", POSES.JabImpact, UPPER_BODY),
		Cross = attackClip("Cross", POSES.CrossImpact, UPPER_BODY),
		Patada = attackClip("Patada", POSES.KickImpact, FULL_BODY, POSES.KickChamber),
		CargaFuerte = holdClip(POSES.HeavyWindup, UPPER_BODY, 0.15),
		Fuerte = {
			joints = UPPER_BODY,
			priority = Enum.AnimationPriority.Action,
			keyframes = {
				{ time = 0, poses = POSES.HeavyWindup },
				{ time = heavy.startup, poses = POSES.HeavyImpact },
				{ time = heavy.startup + heavy.active, poses = POSES.HeavyImpact },
				{ time = heavy.startup + heavy.active + heavy.recovery, poses = NEUTRAL },
			},
		},
		Guardia = holdClip(POSES.Guard, UPPER_BODY, 0.08),
		Reaccion = reactionClip(POSES.Hit, 0.06, 0.35),
		ReaccionFuerte = reactionClip(POSES.HitHeavy, 0.08, 0.6),

		-- Fase 3: el desvío dura la ventana de desvío y vuelve a la guardia
		Desvio = {
			joints = UPPER_BODY,
			priority = Enum.AnimationPriority.Action2,
			keyframes = {
				{ time = 0, poses = POSES.Guard },
				{ time = 0.05, poses = POSES.Deflect },
				{ time = defense.DeflectWindow, poses = POSES.Deflect },
				{ time = defense.DeflectWindow + 0.12, poses = POSES.Guard },
			},
		},
		Aturdido = holdClip(POSES.Stunned, UPPER_BODY_WITH_ROOT, 0.1),

		-- Compañero de combate (tiempos sacados de CombatConfig.Sparring)
		SparringGolpe = {
			joints = UPPER_BODY,
			priority = Enum.AnimationPriority.Action,
			keyframes = {
				{ time = 0, poses = NEUTRAL },
				{ time = golpe.windup * 0.75, poses = POSES.SparringCock },
				{ time = golpe.windup - 0.02, poses = POSES.SparringCock },
				{ time = golpe.windup + 0.04, poses = POSES.SparringStrike },
				{ time = golpe.windup + golpe.active, poses = POSES.SparringStrike },
				{ time = golpe.windup + golpe.active + golpe.recovery, poses = NEUTRAL },
			},
		},
		SparringBarrido = {
			joints = FULL_BODY,
			priority = Enum.AnimationPriority.Action,
			keyframes = {
				{ time = 0, poses = NEUTRAL },
				{ time = barrido.windup * 0.8, poses = POSES.SweepCrouch },
				{ time = barrido.windup, poses = sweepSpin(0) },
				{ time = barrido.windup + barrido.active * 0.33, poses = sweepSpin(120) },
				{ time = barrido.windup + barrido.active * 0.66, poses = sweepSpin(240) },
				{ time = barrido.windup + barrido.active, poses = sweepSpin(360) },
				{ time = barrido.windup + barrido.active + barrido.recovery, poses = NEUTRAL },
			},
		},
	}
end

local clips = nil
local animations = {}

local function buildPose(partName, joints, poses)
	local pose = Instance.new("Pose")
	pose.Name = partName
	local animated = joints[partName] == true
	pose.Weight = if animated then 1 else 0
	pose.CFrame = if animated then toCFrame(poses[partName]) else CFrame.identity
	pose.EasingStyle = Enum.PoseEasingStyle.Cubic
	pose.EasingDirection = Enum.PoseEasingDirection.Out
	local anyAnimated = animated
	for _, childName in ipairs(HIERARCHY[partName] or {}) do
		local child, childAnimated = buildPose(childName, joints, poses)
		if childAnimated then
			child.Parent = pose
			anyAnimated = true
		else
			child:Destroy()
		end
	end
	return pose, anyAnimated
end

-- Construye la KeyframeSequence de un clip (también sirve para guardarla y publicarla después)
function AnimationLibrary.BuildSequence(name)
	clips = clips or buildClips()
	local clip = clips[name]
	assert(clip, "Animación desconocida: " .. tostring(name))
	local jointSet = {}
	for _, joint in ipairs(clip.joints) do
		jointSet[joint] = true
	end
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = name
	sequence.Loop = false
	sequence.Priority = clip.priority
	for _, kf in ipairs(clip.keyframes) do
		local keyframe = Instance.new("Keyframe")
		keyframe.Time = kf.time
		local rootPose = buildPose("HumanoidRootPart", jointSet, kf.poses)
		rootPose.Parent = keyframe
		keyframe.Parent = sequence
	end
	return sequence
end

function AnimationLibrary.Names()
	clips = clips or buildClips()
	local names = {}
	for name in pairs(clips) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- Devuelve un objeto Animation listo para cargar en un Animator
function AnimationLibrary.GetAnimation(name)
	if animations[name] then
		return animations[name]
	end
	local animation = Instance.new("Animation")
	animation.Name = name
	local published = CombatConfig.AnimationIds[name]
	if published and published ~= "" then
		animation.AnimationId = published
	else
		local ok, result = pcall(function()
			return KeyframeSequenceProvider:RegisterKeyframeSequence(AnimationLibrary.BuildSequence(name))
		end)
		if ok then
			animation.AnimationId = result
		else
			warn("[UMBRAL] No se pudo generar la animación " .. name .. ": " .. tostring(result))
		end
	end
	animations[name] = animation
	return animation
end

-- Carga un clip en un Animator y devuelve la pista (AnimationTrack)
function AnimationLibrary.Load(animator, name)
	return animator:LoadAnimation(AnimationLibrary.GetAnimation(name))
end

return AnimationLibrary
