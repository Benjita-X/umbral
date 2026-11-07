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
	QuickChamber = { -- Golpe rápido: guardia compacta, casi sin aviso
		UpperTorso = { -5, -10, 0 },
		RightUpperArm = { 50, 0, -10 },
		RightLowerArm = { 110, 0, 0 },
		LeftUpperArm = { 55, 0, 10 },
		LeftLowerArm = { 105, 0, 0 },
	},
	QuickStrike = {
		UpperTorso = { -8, 22, 0 },
		Head = { 0, -15, 0 },
		RightUpperArm = { 90, 0, -6 },
		RightLowerArm = { 0, 0, 0 },
		LeftUpperArm = { 55, 0, 10 },
		LeftLowerArm = { 105, 0, 0 },
	},
	HeavyRaise = { -- Golpe pesado: los dos brazos arriba (silueta inconfundible)
		UpperTorso = { 15, 0, 0 },
		Head = { 10, 0, 0 },
		RightUpperArm = { 170, 0, 15 },
		RightLowerArm = { 30, 0, 0 },
		LeftUpperArm = { 170, 0, -15 },
		LeftLowerArm = { 30, 0, 0 },
	},
	HeavySlam = {
		UpperTorso = { -30, 0, 0 },
		Head = { -15, 0, 0 },
		RightUpperArm = { 70, 0, -10 },
		RightLowerArm = { 10, 0, 0 },
		LeftUpperArm = { 70, 0, 10 },
		LeftLowerArm = { 10, 0, 0 },
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
	-- ---------- Eco del Viento (EXPERIMENTAL) ----------
	EcoGather = { -- reúne el viento: manos al pecho, torso cargado
		UpperTorso = { -5, 25, 0 },
		Head = { 0, -15, 0 },
		RightUpperArm = { 60, 0, -30 },
		RightLowerArm = { 105, 0, 0 },
		LeftUpperArm = { 60, 0, 30 },
		LeftLowerArm = { 105, 0, 0 },
	},
	EcoPush = { -- las dos palmas empujan al frente
		UpperTorso = { -14, 0, 0 },
		Head = { -6, 0, 0 },
		RightUpperArm = { 90, 0, 10 },
		RightLowerArm = { 0, 0, 0 },
		LeftUpperArm = { 90, 0, -10 },
		LeftLowerArm = { 0, 0, 0 },
	},
	DiveFist = { -- picada: puño hacia abajo, rodillas recogidas
		UpperTorso = { -30, 0, 0 },
		Head = { -15, 0, 0 },
		RightUpperArm = { 25, 0, -5 },
		RightLowerArm = { 10, 0, 0 },
		LeftUpperArm = { -30, 0, 25 },
		LeftLowerArm = { 30, 0, 0 },
		RightUpperLeg = { 70, 0, 0 },
		RightLowerLeg = { -110, 0, 0 },
		LeftUpperLeg = { 40, 0, 0 },
		LeftLowerLeg = { -80, 0, 0 },
	},
	LandCrouch = { -- aterrizaje: agachado, brazos abiertos
		LowerTorso = { -10, 0, 0, p = Vector3.new(0, -0.8, 0) },
		UpperTorso = { -22, 0, 0 },
		RightUpperLeg = { 60, 0, 0 },
		RightLowerLeg = { -90, 0, 0 },
		LeftUpperLeg = { 60, 0, 0 },
		LeftLowerLeg = { -90, 0, 0 },
		RightUpperArm = { 25, 0, 45 },
		LeftUpperArm = { 25, 0, -45 },
	},
	SlashWind = { -- Estela: el brazo cargado atrás antes del corte
		UpperTorso = { -10, -45, 0 },
		Head = { 0, 30, 0 },
		RightUpperArm = { 90, 0, 65 },
		RightLowerArm = { 10, 0, 0 },
		LeftUpperArm = { 40, 0, 10 },
		LeftLowerArm = { 95, 0, 0 },
	},
	SlashCut = { -- el corte cruza al otro lado
		UpperTorso = { -12, 40, 0 },
		Head = { 0, -25, 0 },
		RightUpperArm = { 90, 0, -45 },
		RightLowerArm = { 0, 0, 0 },
		LeftUpperArm = { 30, 0, 20 },
		LeftLowerArm = { 80, 0, 0 },
	},
	-- ---------- Habilidades v2 (EXPERIMENTAL) ----------
	CycloneReach = { -- brazos abiertos hacia adelante: agarra el viento
		UpperTorso = { -10, 0, 0 },
		Head = { -5, 0, 0 },
		RightUpperArm = { 95, 0, 45 },
		RightLowerArm = { 5, 0, 0 },
		LeftUpperArm = { 95, 0, -45 },
		LeftLowerArm = { 5, 0, 0 },
	},
	CyclonePull = { -- tira hacia el pecho, el cuerpo hacia atrás
		UpperTorso = { 10, 0, 0 },
		Head = { 6, 0, 0 },
		RightUpperArm = { 55, 0, -35 },
		RightLowerArm = { 120, 0, 0 },
		LeftUpperArm = { 55, 0, 35 },
		LeftLowerArm = { 120, 0, 0 },
	},
	UppercutLow = { -- palma abajo, el cuerpo cargado
		UpperTorso = { -18, -22, 0 },
		Head = { 0, 12, 0 },
		RightUpperArm = { -25, 0, 20 },
		RightLowerArm = { 55, 0, 0 },
		LeftUpperArm = { 55, 0, 12 },
		LeftLowerArm = { 105, 0, 0 },
	},
	UppercutHigh = { -- la palma sube hasta arriba
		UpperTorso = { 14, 18, 0 },
		Head = { 12, -8, 0 },
		RightUpperArm = { 172, 0, -6 },
		RightLowerArm = { 8, 0, 0 },
		LeftUpperArm = { -20, 0, -18 },
		LeftLowerArm = { 45, 0, 0 },
	},
	AscentRise = { -- sube: un brazo arriba, rodilla recogida
		UpperTorso = { 12, 0, 0 },
		Head = { 10, 0, 0 },
		RightUpperArm = { 168, 0, 10 },
		RightLowerArm = { 10, 0, 0 },
		LeftUpperArm = { -30, 0, -25 },
		LeftLowerArm = { 30, 0, 0 },
		RightUpperLeg = { 85, 0, 0 },
		RightLowerLeg = { -105, 0, 0 },
		LeftUpperLeg = { 15, 0, 0 },
		LeftLowerLeg = { -35, 0, 0 },
	},
	ThrowWind = { -- lanzar: brazo atrás y arriba
		UpperTorso = { -6, -38, 0 },
		Head = { 0, 28, 0 },
		RightUpperArm = { 120, 0, 60 },
		RightLowerArm = { 40, 0, 0 },
		LeftUpperArm = { 70, 0, 10 },
		LeftLowerArm = { 70, 0, 0 },
	},
	ThrowRelease = { -- lanzar: el brazo cruza y suelta al frente
		UpperTorso = { -14, 34, 0 },
		Head = { 0, -22, 0 },
		RightUpperArm = { 85, 0, -30 },
		RightLowerArm = { 0, 0, 0 },
		LeftUpperArm = { 25, 0, 20 },
		LeftLowerArm = { 80, 0, 0 },
	},
	-- ---------- Espada y patadas especiales (EXPERIMENTAL) ----------
	-- La hoja sigue la línea del antebrazo derecho (ver WeaponService): estos ángulos apuntan la hoja
	TajoChamber = { -- brazo abierto a la derecha, torso cargado
		UpperTorso = { -6, -32, 0 },
		Head = { 0, 24, 0 },
		RightUpperArm = { 95, 0, 75 },
		RightLowerArm = { 20, 0, 0 },
		LeftUpperArm = { 55, 0, 12 },
		LeftLowerArm = { 100, 0, 0 },
		RightHand = { -80, 0, 0 },
	},
	TajoImpact = { -- la hoja cruza de derecha a izquierda
		UpperTorso = { -10, 38, 0 },
		Head = { 0, -24, 0 },
		RightUpperArm = { 92, 0, -42 },
		RightLowerArm = { 6, 0, 0 },
		LeftUpperArm = { 35, 0, 18 },
		LeftLowerArm = { 85, 0, 0 },
		RightHand = { -80, 0, 0 },
	},
	RevesChamber = { -- la hoja cargada del lado izquierdo
		UpperTorso = { -6, 36, 0 },
		Head = { 0, -22, 0 },
		RightUpperArm = { 85, 0, -65 },
		RightLowerArm = { 35, 0, 0 },
		LeftUpperArm = { 40, 0, 15 },
		LeftLowerArm = { 90, 0, 0 },
		RightHand = { -80, 0, 0 },
	},
	RevesImpact = { -- revés: cruza de izquierda a derecha
		UpperTorso = { -10, -36, 0 },
		Head = { 0, 24, 0 },
		RightUpperArm = { 92, 0, 60 },
		RightLowerArm = { 5, 0, 0 },
		LeftUpperArm = { 55, 0, 12 },
		LeftLowerArm = { 100, 0, 0 },
		RightHand = { -80, 0, 0 },
	},
	EstocadaChamber = { -- la espada recogida junto a la cadera
		UpperTorso = { -4, -30, 0 },
		Head = { 0, 22, 0 },
		RightUpperArm = { 40, 0, 15 },
		RightLowerArm = { 95, 0, 0 },
		LeftUpperArm = { 70, 0, 10 },
		LeftLowerArm = { 60, 0, 0 },
		RightHand = { -70, 0, 0 },
	},
	EstocadaImpact = { -- estocada: todo el brazo al frente
		UpperTorso = { -18, 22, 0 },
		Head = { -6, -14, 0 },
		RightUpperArm = { 94, 0, -4 },
		RightLowerArm = { 0, 0, 0 },
		LeftUpperArm = { -25, 0, -20 },
		LeftLowerArm = { 40, 0, 0 },
		RightHand = { -80, 0, 0 },
	},
	TajoFuerteImpact = { -- tajo cargado: de arriba abajo
		UpperTorso = { -32, 10, 0 },
		Head = { -15, 0, 0 },
		RightUpperArm = { 62, 0, -8 },
		RightLowerArm = { 4, 0, 0 },
		LeftUpperArm = { 50, 0, 10 },
		LeftLowerArm = { 70, 0, 0 },
		RightHand = { -80, 0, 0 },
	},
	FlyingKick = { -- patada voladora: el cuerpo en línea, pierna al frente
		LowerTorso = { 18, 0, 0 },
		UpperTorso = { 14, 8, 0 },
		Head = { -12, -5, 0 },
		RightUpperLeg = { 100, 0, 0 },
		RightLowerLeg = { -4, 0, 0 },
		LeftUpperLeg = { -10, 0, 0 },
		LeftLowerLeg = { -95, 0, 0 },
		RightUpperArm = { -30, 0, 35 },
		RightLowerArm = { 20, 0, 0 },
		LeftUpperArm = { 50, 0, -20 },
		LeftLowerArm = { 80, 0, 0 },
	},
	DiveKick = { -- patada en picada: pierna estirada hacia abajo y adelante
		LowerTorso = { -25, 0, 0 },
		UpperTorso = { -15, 0, 0 },
		Head = { -10, 0, 0 },
		RightUpperLeg = { 35, 0, 0 },
		RightLowerLeg = { -5, 0, 0 },
		LeftUpperLeg = { 95, 0, 0 },
		LeftLowerLeg = { -115, 0, 0 },
		RightUpperArm = { 120, 0, 30 },
		LeftUpperArm = { 120, 0, -30 },
	},
	HeavyRaiseSword = { -- la espada en alto, la hoja hacia atrás
		UpperTorso = { 15, 0, 0 },
		Head = { 10, 0, 0 },
		RightUpperArm = { 170, 0, 15 },
		RightLowerArm = { 30, 0, 0 },
		RightHand = { -60, 0, 0 },
		LeftUpperArm = { 160, 0, -15 },
		LeftLowerArm = { 40, 0, 0 },
	},
	PlungeSword = { -- clavada: la espada apunta abajo, rodillas recogidas
		UpperTorso = { -28, 0, 0 },
		Head = { -15, 0, 0 },
		RightUpperArm = { 15, 0, 8 },
		RightLowerArm = { 25, 0, 0 },
		RightHand = { 80, 0, 0 },
		LeftUpperArm = { 10, 0, -10 },
		LeftLowerArm = { 30, 0, 0 },
		RightUpperLeg = { 75, 0, 0 },
		RightLowerLeg = { -110, 0, 0 },
		LeftUpperLeg = { 50, 0, 0 },
		LeftLowerLeg = { -90, 0, 0 },
	},
	-- ---------- Movilidad (EXPERIMENTAL) ----------
	DashLean = { -- Paso: cuerpo inclinado, brazos atrás
		UpperTorso = { -28, 0, 0 },
		Head = { -10, 0, 0 },
		RightUpperArm = { -45, 0, 15 },
		LeftUpperArm = { -45, 0, -15 },
		RightLowerArm = { 20, 0, 0 },
		LeftLowerArm = { 20, 0, 0 },
	},
	WallKick = { -- salto de pared: brazos arriba, una pierna empuja
		UpperTorso = { 12, 0, 0 },
		RightUpperArm = { 150, 0, 35 },
		LeftUpperArm = { 150, 0, -35 },
		RightUpperLeg = { 45, 0, 10 },
		RightLowerLeg = { -70, 0, 0 },
		LeftUpperLeg = { -25, 0, -10 },
	},
	WallStride = { -- carrera por la pared: zancada inclinada
		LowerTorso = { -10, 0, 0 },
		UpperTorso = { -15, 0, 0 },
		RightUpperArm = { -40, 0, 10 },
		LeftUpperArm = { 60, 0, -10 },
		LeftLowerArm = { 60, 0, 0 },
		RightUpperLeg = { 55, 0, 0 },
		RightLowerLeg = { -75, 0, 0 },
		LeftUpperLeg = { -25, 0, 0 },
		LeftLowerLeg = { -20, 0, 0 },
	},
	MantleReach = { -- agarre: brazos arriba al borde
		UpperTorso = { -20, 0, 0 },
		RightUpperArm = { 160, 0, 10 },
		LeftUpperArm = { 160, 0, -10 },
		RightLowerArm = { 30, 0, 0 },
		LeftLowerArm = { 30, 0, 0 },
		RightUpperLeg = { 70, 0, 0 },
		RightLowerLeg = { -90, 0, 0 },
	},
	MantlePush = { -- se impulsa sobre el borde
		UpperTorso = { -35, 0, 0 },
		RightUpperArm = { 30, 0, 15 },
		LeftUpperArm = { 30, 0, -15 },
		RightUpperLeg = { 80, 0, 0 },
		RightLowerLeg = { -100, 0, 0 },
		LeftUpperLeg = { 30, 0, 0 },
	},
}

-- Torbellino: gira sobre sí mismo con los brazos abiertos
local function spinArms(angle)
	return {
		LowerTorso = { 0, angle, 0 },
		UpperTorso = { -8, 0, 0 },
		RightUpperArm = { 15, 0, 85 },
		LeftUpperArm = { 15, 0, -85 },
		RightLowerArm = { 0, 0, 0 },
		LeftLowerArm = { 0, 0, 0 },
		RightUpperLeg = { 15, 0, 5 },
		LeftUpperLeg = { 15, 0, -5 },
	}
end

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

-- Pose recogida de la voltereta: el cuerpo gira `angle` grados (X−: hacia adelante) y baja `drop` studs
local function rollPose(angle, drop)
	return {
		LowerTorso = { angle, 0, 0, p = Vector3.new(0, drop, 0) },
		UpperTorso = { -25, 0, 0 },
		Head = { -20, 0, 0 },
		RightUpperArm = { 70, 0, -15 },
		RightLowerArm = { 100, 0, 0 },
		LeftUpperArm = { 70, 0, 15 },
		LeftLowerArm = { 100, 0, 0 },
		RightUpperLeg = { 105, 0, 0 },
		RightLowerLeg = { -125, 0, 0 },
		LeftUpperLeg = { 105, 0, 0 },
		LeftLowerLeg = { -125, 0, 0 },
	}
end

-- Guardia de pelea: base de la que parten y a la que vuelven los golpes (en un combo los brazos no bajan
-- entre golpe y golpe)
local STANCE = {
	UpperTorso = { -4, -8, 0 },
	Head = { 0, 6, 0 },
	LeftUpperArm = { 62, 0, 14 },
	LeftLowerArm = { 105, 0, 0 },
	RightUpperArm = { 55, 0, -16 },
	RightLowerArm = { 112, 0, 0 },
}

-- Curvas (la curva de un keyframe describe el tramo HACIA el siguiente):
--   ANTICIPA: sale rápido y frena (preparación)     GOLPEA: acelera hacia el impacto (sin frenar al llegar)
--   VUELVE: suave en los dos extremos (recuperación)
local ANTICIPA = { Enum.PoseEasingStyle.Cubic, Enum.PoseEasingDirection.Out }
local GOLPEA = { Enum.PoseEasingStyle.Cubic, Enum.PoseEasingDirection.In }
local VUELVE = { Enum.PoseEasingStyle.Cubic, Enum.PoseEasingDirection.InOut }
local SECO = { Enum.PoseEasingStyle.Linear, Enum.PoseEasingDirection.In }

-- Exagera una pose un poco más allá (overshoot): el golpe "llega" con fuerza y retrocede al impacto
local function extend(pose, factor)
	local result = {}
	for joint, spec in pairs(pose) do
		result[joint] = { (spec[1] or 0) * factor, (spec[2] or 0) * factor, (spec[3] or 0) * factor, p = spec.p }
	end
	return result
end

local function toCFrame(spec)
	if not spec then
		return CFrame.identity
	end
	local offset = spec.p or Vector3.zero
	return CFrame.new(offset) * CFrame.Angles(math.rad(spec[1] or 0), math.rad(spec[2] or 0), math.rad(spec[3] or 0))
end

-- Clip de un golpe: guardia → (preparación) → acelera hasta pasarse un poco del impacto al empezar
-- "active" → retrocede a la pose de impacto → vuelve a la guardia al terminar
local function attackClip(attackName, impact, joints, chamber)
	local a = CombatConfig.Attacks[attackName]
	local keyframes = {}
	if chamber then
		table.insert(keyframes, { time = 0, poses = STANCE, ease = ANTICIPA })
		table.insert(keyframes, { time = a.startup * 0.55, poses = chamber, ease = GOLPEA })
	else
		table.insert(keyframes, { time = 0, poses = STANCE, ease = GOLPEA })
	end
	table.insert(keyframes, { time = a.startup, poses = extend(impact, 1.08), ease = SECO })
	table.insert(keyframes, { time = a.startup + a.active, poses = impact, ease = VUELVE })
	table.insert(keyframes, { time = a.startup + a.active + a.recovery, poses = STANCE, ease = VUELVE })
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
-- Golpes de espada: también la muñeca derecha (orienta la hoja)
local SWORD_BODY = { "LowerTorso", "UpperTorso", "Head", "LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm", "RightHand" }
local SWORD_FULL = { "LowerTorso", "UpperTorso", "Head", "LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg" }

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
	local rapido = CombatConfig.Sparring.Attacks.Rapido
	local fuerte = CombatConfig.Sparring.Attacks.Fuerte
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
				{ time = 0, poses = POSES.HeavyWindup, ease = GOLPEA },
				{ time = heavy.startup, poses = extend(POSES.HeavyImpact, 1.08), ease = SECO },
				{ time = heavy.startup + heavy.active, poses = POSES.HeavyImpact, ease = VUELVE },
				{ time = heavy.startup + heavy.active + heavy.recovery, poses = STANCE, ease = VUELVE },
			},
		},
		-- Golpes especiales y espada (EXPERIMENTAL)
		PatadaVoladora = attackClip("PatadaVoladora", POSES.FlyingKick, FULL_BODY, POSES.KickChamber),
		PatadaPicada = attackClip("PatadaPicada", POSES.DiveKick, FULL_BODY, POSES.KickChamber),
		Tajo = attackClip("Tajo", POSES.TajoImpact, SWORD_BODY, POSES.TajoChamber),
		Reves = attackClip("Reves", POSES.RevesImpact, SWORD_BODY, POSES.RevesChamber),
		Estocada = attackClip("Estocada", POSES.EstocadaImpact, SWORD_BODY, POSES.EstocadaChamber),
		TajoFuerte = {
			joints = SWORD_BODY,
			priority = Enum.AnimationPriority.Action,
			keyframes = {
				{ time = 0, poses = POSES.HeavyRaiseSword, ease = GOLPEA },
				{ time = CombatConfig.Attacks.TajoFuerte.startup, poses = extend(POSES.TajoFuerteImpact, 1.08), ease = SECO },
				{ time = CombatConfig.Attacks.TajoFuerte.startup + CombatConfig.Attacks.TajoFuerte.active, poses = POSES.TajoFuerteImpact, ease = VUELVE },
				{ time = CombatConfig.Attacks.TajoFuerte.startup + CombatConfig.Attacks.TajoFuerte.active + CombatConfig.Attacks.TajoFuerte.recovery, poses = STANCE, ease = VUELVE },
			},
		},
		CargaEspada = holdClip(POSES.HeavyRaiseSword, SWORD_BODY, 0.15),
		EstocadaCarrera = attackClip("EstocadaCarrera", POSES.EstocadaImpact, SWORD_BODY, POSES.EstocadaChamber),
		Clavada = attackClip("Clavada", POSES.PlungeSword, SWORD_FULL, POSES.HeavyRaiseSword),
		DesenvainarEspada = {
			joints = UPPER_BODY,
			priority = Enum.AnimationPriority.Action2,
			keyframes = {
				{ time = 0, poses = STANCE, ease = ANTICIPA },
				{ time = 0.1, poses = POSES.RevesChamber, ease = VUELVE },
				{ time = 0.22, poses = POSES.TajoImpact, ease = VUELVE },
				{ time = 0.4, poses = STANCE, ease = VUELVE },
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

		-- Eco del Viento (EXPERIMENTAL): una animación propia por técnica
		EcoRafaga = {
			joints = UPPER_BODY_WITH_ROOT,
			priority = Enum.AnimationPriority.Action2,
			keyframes = {
				{ time = 0, poses = STANCE, ease = ANTICIPA },
				{ time = 0.08, poses = POSES.EcoGather, ease = GOLPEA },
				{ time = 0.16, poses = extend(POSES.EcoPush, 1.08), ease = SECO },
				{ time = 0.3, poses = POSES.EcoPush, ease = VUELVE },
				{ time = 0.55, poses = STANCE, ease = VUELVE },
			},
		},
		EcoTorbellino = {
			joints = FULL_BODY,
			priority = Enum.AnimationPriority.Action2,
			keyframes = {
				{ time = 0, poses = STANCE, ease = ANTICIPA },
				{ time = 0.06, poses = spinArms(0), ease = SECO },
				{ time = 0.18, poses = spinArms(120), ease = SECO },
				{ time = 0.3, poses = spinArms(240), ease = SECO },
				{ time = 0.42, poses = spinArms(360), ease = VUELVE },
				{ time = 0.62, poses = STANCE, ease = VUELVE },
			},
		},
		EcoDescenso = {
			joints = FULL_BODY,
			priority = Enum.AnimationPriority.Action2,
			keyframes = {
				{ time = 0, poses = NEUTRAL, ease = ANTICIPA },
				{ time = 0.1, poses = POSES.DiveFist, ease = VUELVE },
				{ time = 3, poses = POSES.DiveFist }, -- se mantiene hasta aterrizar (la pista se detiene)
			},
		},
		EcoAterrizaje = {
			joints = FULL_BODY,
			priority = Enum.AnimationPriority.Action2,
			keyframes = {
				{ time = 0, poses = POSES.DiveFist, ease = SECO },
				{ time = 0.06, poses = POSES.LandCrouch, ease = VUELVE },
				{ time = 0.22, poses = POSES.LandCrouch, ease = VUELVE },
				{ time = 0.45, poses = NEUTRAL, ease = VUELVE },
			},
		},
		EcoEstela = {
			joints = UPPER_BODY_WITH_ROOT,
			priority = Enum.AnimationPriority.Action2,
			keyframes = {
				{ time = 0, poses = POSES.SlashWind, ease = GOLPEA },
				{ time = 0.1, poses = extend(POSES.SlashCut, 1.06), ease = SECO },
				{ time = 0.22, poses = POSES.SlashCut, ease = VUELVE },
				{ time = 0.45, poses = STANCE, ease = VUELVE },
			},
		},
		-- Habilidades v2 (EXPERIMENTAL): solo la parte de arriba (se puede correr mientras se lanzan), salvo
		-- las que mueven todo el cuerpo (Ascenso, Tempestad)
		EcoCuchilla = {
			joints = UPPER_BODY,
			priority = Enum.AnimationPriority.Action2,
			keyframes = {
				{ time = 0, poses = STANCE, ease = ANTICIPA },
				{ time = 0.06, poses = POSES.ThrowWind, ease = GOLPEA },
				{ time = 0.13, poses = extend(POSES.ThrowRelease, 1.08), ease = SECO },
				{ time = 0.24, poses = POSES.ThrowRelease, ease = VUELVE },
				{ time = 0.42, poses = STANCE, ease = VUELVE },
			},
		},
		EcoCiclon = {
			joints = UPPER_BODY,
			priority = Enum.AnimationPriority.Action2,
			keyframes = {
				{ time = 0, poses = STANCE, ease = ANTICIPA },
				{ time = 0.07, poses = extend(POSES.CycloneReach, 1.05), ease = GOLPEA },
				{ time = 0.2, poses = POSES.CyclonePull, ease = VUELVE },
				{ time = 0.3, poses = POSES.CyclonePull, ease = VUELVE },
				{ time = 0.5, poses = STANCE, ease = VUELVE },
			},
		},
		EcoLevante = {
			joints = UPPER_BODY,
			priority = Enum.AnimationPriority.Action2,
			keyframes = {
				{ time = 0, poses = STANCE, ease = ANTICIPA },
				{ time = 0.06, poses = POSES.UppercutLow, ease = GOLPEA },
				{ time = 0.14, poses = extend(POSES.UppercutHigh, 1.05), ease = SECO },
				{ time = 0.26, poses = POSES.UppercutHigh, ease = VUELVE },
				{ time = 0.5, poses = STANCE, ease = VUELVE },
			},
		},
		EcoPuno = {
			joints = UPPER_BODY_WITH_ROOT,
			priority = Enum.AnimationPriority.Action2,
			keyframes = {
				{ time = 0, poses = STANCE, ease = ANTICIPA },
				{ time = 0.07, poses = POSES.HeavyWindup, ease = GOLPEA },
				{ time = 0.15, poses = extend(POSES.HeavyImpact, 1.1), ease = SECO },
				{ time = 0.28, poses = POSES.HeavyImpact, ease = VUELVE },
				{ time = 0.5, poses = STANCE, ease = VUELVE },
			},
		},
		EcoAscenso = {
			joints = FULL_BODY,
			priority = Enum.AnimationPriority.Action2,
			keyframes = {
				{ time = 0, poses = NEUTRAL, ease = ANTICIPA },
				{ time = 0.07, poses = POSES.AscentRise, ease = VUELVE },
				{ time = 0.32, poses = POSES.AscentRise, ease = VUELVE },
				{ time = 0.55, poses = NEUTRAL, ease = VUELVE },
			},
		},
		EcoTempestad = {
			joints = FULL_BODY,
			priority = Enum.AnimationPriority.Action2,
			keyframes = {
				{ time = 0, poses = STANCE, ease = ANTICIPA },
				{ time = 0.12, poses = POSES.HeavyRaise, ease = VUELVE },
				{ time = 0.24, poses = spinArms(180), ease = SECO },
				{ time = 0.36, poses = spinArms(360), ease = GOLPEA },
				{ time = 0.46, poses = extend(POSES.EcoPush, 1.08), ease = SECO },
				{ time = 0.62, poses = POSES.EcoPush, ease = VUELVE },
				{ time = 0.85, poses = STANCE, ease = VUELVE },
			},
		},
		-- Movilidad (EXPERIMENTAL)
		Paso = {
			joints = UPPER_BODY_WITH_ROOT,
			priority = Enum.AnimationPriority.Action,
			keyframes = {
				{ time = 0, poses = NEUTRAL, ease = SECO },
				{ time = 0.04, poses = POSES.DashLean, ease = VUELVE },
				{ time = 0.16, poses = POSES.DashLean, ease = VUELVE },
				{ time = 0.3, poses = NEUTRAL, ease = VUELVE },
			},
		},
		-- Voltereta del Paso hacia adelante en el suelo (el esquive con voltereta de los juegos de acción): el cuerpo
		-- se recoge y gira una vuelta completa alrededor de la cintura. Cada tramo gira menos de 180° (así la
		-- interpolación va siempre hacia adelante).
		PasoVoltereta = {
			joints = FULL_BODY,
			priority = Enum.AnimationPriority.Action,
			keyframes = {
				{ time = 0, poses = NEUTRAL, ease = SECO },
				{ time = 0.05, poses = rollPose(-70, -0.4), ease = SECO },
				{ time = 0.12, poses = rollPose(-180, -0.6), ease = SECO },
				{ time = 0.2, poses = rollPose(-290, -0.45), ease = SECO },
				{ time = 0.26, poses = rollPose(-360, -0.15), ease = VUELVE },
				{ time = 0.38, poses = NEUTRAL, ease = VUELVE },
			},
		},
		SaltoPared = {
			joints = FULL_BODY,
			priority = Enum.AnimationPriority.Action,
			keyframes = {
				{ time = 0, poses = NEUTRAL, ease = SECO },
				{ time = 0.06, poses = POSES.WallKick, ease = VUELVE },
				{ time = 0.25, poses = POSES.WallKick, ease = VUELVE },
				{ time = 0.45, poses = NEUTRAL, ease = VUELVE },
			},
		},
		CarreraPared = {
			joints = FULL_BODY,
			priority = Enum.AnimationPriority.Action,
			keyframes = {
				{ time = 0, poses = NEUTRAL, ease = ANTICIPA },
				{ time = 0.08, poses = POSES.WallStride, ease = VUELVE },
				{ time = 3, poses = POSES.WallStride }, -- se mantiene mientras corre (la pista se detiene)
			},
		},
		AgarreBorde = {
			joints = FULL_BODY,
			priority = Enum.AnimationPriority.Action,
			keyframes = {
				{ time = 0, poses = POSES.MantleReach, ease = VUELVE },
				{ time = 0.14, poses = POSES.MantlePush, ease = VUELVE },
				{ time = 0.38, poses = NEUTRAL, ease = VUELVE },
			},
		},

		-- Compañero de combate (tiempos sacados de CombatConfig.Sparring)
		SparringGolpe = {
			joints = UPPER_BODY,
			priority = Enum.AnimationPriority.Action,
			keyframes = {
				{ time = 0, poses = NEUTRAL, ease = ANTICIPA },
				{ time = golpe.holdAt, poses = POSES.SparringCock, ease = VUELVE },
				{ time = golpe.startup - 0.02, poses = extend(POSES.SparringCock, 1.05), ease = GOLPEA },
				{ time = golpe.startup + 0.04, poses = extend(POSES.SparringStrike, 1.08), ease = SECO },
				{ time = golpe.startup + golpe.active, poses = POSES.SparringStrike, ease = VUELVE },
				{ time = golpe.startup + golpe.active + golpe.recovery, poses = NEUTRAL, ease = VUELVE },
			},
		},
		SparringRapido = {
			joints = UPPER_BODY,
			priority = Enum.AnimationPriority.Action,
			keyframes = {
				{ time = 0, poses = NEUTRAL, ease = ANTICIPA },
				{ time = rapido.startup * 0.6, poses = POSES.QuickChamber, ease = GOLPEA },
				{ time = rapido.startup, poses = extend(POSES.QuickStrike, 1.08), ease = SECO },
				{ time = rapido.startup + rapido.active, poses = POSES.QuickStrike, ease = VUELVE },
				{ time = rapido.startup + rapido.active + rapido.recovery, poses = NEUTRAL, ease = VUELVE },
			},
		},
		SparringFuerte = {
			joints = UPPER_BODY,
			priority = Enum.AnimationPriority.Action,
			keyframes = {
				{ time = 0, poses = NEUTRAL, ease = ANTICIPA },
				{ time = fuerte.holdAt, poses = POSES.HeavyRaise, ease = VUELVE },
				{ time = fuerte.startup - 0.02, poses = extend(POSES.HeavyRaise, 1.04), ease = GOLPEA },
				{ time = fuerte.startup + 0.04, poses = extend(POSES.HeavySlam, 1.1), ease = SECO },
				{ time = fuerte.startup + fuerte.active, poses = POSES.HeavySlam, ease = VUELVE },
				{ time = fuerte.startup + fuerte.active + fuerte.recovery, poses = NEUTRAL, ease = VUELVE },
			},
		},
		SparringBarrido = {
			joints = FULL_BODY,
			priority = Enum.AnimationPriority.Action,
			keyframes = {
				{ time = 0, poses = NEUTRAL },
				{ time = barrido.startup * 0.8, poses = POSES.SweepCrouch },
				{ time = barrido.startup, poses = sweepSpin(0) },
				{ time = barrido.startup + barrido.active * 0.33, poses = sweepSpin(120) },
				{ time = barrido.startup + barrido.active * 0.66, poses = sweepSpin(240) },
				{ time = barrido.startup + barrido.active, poses = sweepSpin(360) },
				{ time = barrido.startup + barrido.active + barrido.recovery, poses = NEUTRAL },
			},
		},
	}
end

local clips = nil
local animations = {}

local function buildPose(partName, joints, poses, ease)
	local pose = Instance.new("Pose")
	pose.Name = partName
	local animated = joints[partName] == true
	pose.Weight = if animated then 1 else 0
	pose.CFrame = if animated then toCFrame(poses[partName]) else CFrame.identity
	pose.EasingStyle = if ease then ease[1] else Enum.PoseEasingStyle.Cubic
	pose.EasingDirection = if ease then ease[2] else Enum.PoseEasingDirection.Out
	local anyAnimated = animated
	for _, childName in ipairs(HIERARCHY[partName] or {}) do
		local child, childAnimated = buildPose(childName, joints, poses, ease)
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
		local rootPose = buildPose("HumanoidRootPart", jointSet, kf.poses, kf.ease)
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
