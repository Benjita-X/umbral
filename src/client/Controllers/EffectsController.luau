-- EffectsController: la respuesta audiovisual del combate (solo en esta pantalla, sin esperar al servidor).
-- Chispas y onda en el impacto, destello del objetivo, estela del golpe, sonidos, vibración de cámara,
-- números de daño y la reacción animada de quien recibe el golpe.
--
-- Sonidos y texturas: los que trae Roblox Studio (rbxasset://), afinados como provisionales.
-- Los definitivos se suben a Roblox y se cambian aquí (SOUNDS).

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(shared:WaitForChild("Config"):WaitForChild("CombatConfig"))
local AnimationLibrary = require(shared:WaitForChild("Combat"):WaitForChild("AnimationLibrary"))
local CameraController = require(script.Parent:WaitForChild("CameraController"))
local EcoEfectos = require(script.Parent:WaitForChild("EcoEfectos"))
local Players = game:GetService("Players")

-- Color del Eco que lleva puesto este jugador (golpes y estelas se tiñen de su elemento)
local function ecoColor()
	local kit = CombatConfig.Eco.Kits[Players.LocalPlayer:GetAttribute("Eco") or ""]
	return if kit then kit.color else Color3.fromRGB(200, 225, 255)
end

-- Partículas del elemento que suelta la hoja de la espada mientras corta (como una técnica elemental)
local BLADE_PARTICLES = {
	Viento = { texture = "rbxasset://textures/particles/sparkles_main.dds", color = { Color3.new(1, 1, 1), Color3.fromRGB(150, 255, 230) }, light = 1, size = 0.35, speed = { 2, 5 }, life = { 0.15, 0.3 }, accel = Vector3.zero },
	Agua = { texture = "rbxasset://textures/particles/sparkles_main.dds", color = { Color3.fromRGB(210, 240, 255), Color3.fromRGB(70, 160, 255) }, light = 0.7, size = 0.4, speed = { 3, 8 }, life = { 0.3, 0.5 }, accel = Vector3.new(0, -40, 0) },
	Oscuridad = { texture = "rbxasset://textures/particles/smoke_main.dds", color = { Color3.fromRGB(80, 30, 120), Color3.fromRGB(20, 5, 30) }, light = 0, size = 0.9, speed = { 1, 3 }, life = { 0.3, 0.55 }, accel = Vector3.zero },
	Fuego = { texture = "rbxasset://textures/particles/fire_main.dds", color = { Color3.fromRGB(255, 210, 100), Color3.fromRGB(255, 60, 10) }, light = 1, size = 0.9, speed = { 2, 5 }, life = { 0.2, 0.4 }, accel = Vector3.new(0, 10, 0) },
	Trueno = { texture = "rbxasset://textures/particles/sparkles_main.dds", color = { Color3.new(1, 1, 1), Color3.fromRGB(255, 235, 90) }, light = 1, size = 0.4, speed = { 8, 16 }, life = { 0.08, 0.18 }, accel = Vector3.zero },
}
local function bladeParticles(limb, enabled)
	local emitter = limb:FindFirstChild("UmbralElementoHoja")
	local element = Players.LocalPlayer:GetAttribute("Eco") or CombatConfig.Eco.Default
	local spec = BLADE_PARTICLES[element]
	if emitter and emitter:GetAttribute("Elemento") ~= element then
		emitter:Destroy()
		emitter = nil
	end
	if not emitter then
		if not enabled or not spec then
			return
		end
		emitter = Instance.new("ParticleEmitter")
		emitter.Name = "UmbralElementoHoja"
		emitter:SetAttribute("Elemento", element)
		emitter.Texture = spec.texture
		emitter.Color = ColorSequence.new(spec.color[1], spec.color[2])
		emitter.LightEmission = spec.light
		emitter.LightInfluence = 0
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, spec.size), NumberSequenceKeypoint.new(1, 0) })
		emitter.Lifetime = NumberRange.new(spec.life[1], spec.life[2])
		emitter.Speed = NumberRange.new(spec.speed[1], spec.speed[2])
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Acceleration = spec.accel
		emitter.Rate = 70
		emitter.Shape = Enum.ParticleEmitterShape.Box
		emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		emitter.Parent = limb
	end
	emitter.Enabled = enabled
end

local EffectsController = {}

local SOUNDS = {
	Swing = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.35, speed = 1.7 },
	SwingHeavy = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.5, speed = 1.15 },
	Hit = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.9, speed = 1.6 },
	HitHeavy = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 1, speed = 1.05 },
	Boom = { id = "rbxasset://sounds/impact_explosion_03.mp3", volume = 0.22, speed = 1.6 },
	-- Fase 3 (provisionales: tonos altos que recuerdan a un choque metálico)
	Parry = { id = "rbxasset://sounds/impact_explosion_03.mp3", volume = 0.35, speed = 2.6 },
	ParryLight = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.8, speed = 2.4 },
	Block = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.7, speed = 1.9 },
	Break = { id = "rbxasset://sounds/impact_explosion_03.mp3", volume = 0.45, speed = 0.9 },
	Dodge = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.45, speed = 2.1 },
	WindupLight = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.6, speed = 0.75 },
	WindupHeavy = { id = "rbxasset://sounds/impact_explosion_03.mp3", volume = 0.3, speed = 0.6 },
}

local TEXTURES = {
	Sparks = "rbxasset://textures/particles/sparkles_main.dds",
	Shockwave = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
}

local LIMB_ATTACHMENT_OFFSET = 0.35

-- Contenedor local de efectos (lo que cuelga de la cámara solo existe en esta pantalla)
local function effectsFolder()
	local camera = Workspace.CurrentCamera
	local folder = camera:FindFirstChild("UmbralEfectos")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "UmbralEfectos"
		folder.Parent = camera
	end
	return folder
end

local function anchorPart(name, position, lifetime)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = CFrame.new(position)
	part.Parent = effectsFolder()
	Debris:AddItem(part, lifetime)
	return part
end

local function playSound(name, parent)
	local spec = SOUNDS[name]
	if not spec then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "Sonido" .. name
	sound.SoundId = spec.id
	sound.Volume = spec.volume
	sound.PlaybackSpeed = spec.speed
	sound.RollOffMaxDistance = 120
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 2)
	return sound
end

local function burst(attachment, texture, props, count)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = texture
	emitter.Rate = 0
	emitter.Enabled = false
	for key, value in pairs(props) do
		emitter[key] = value
	end
	emitter.Parent = attachment
	emitter:Emit(count)
	return emitter
end

local function flashTarget(model, color)
	if not CombatConfig.Feedback.Flashes or not model then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "UmbralDestello"
	highlight.Adornee = model
	highlight.FillColor = color or Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.15
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = effectsFolder()
	TweenService:Create(highlight, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FillTransparency = 1 }):Play()
	Debris:AddItem(highlight, 0.2)
end

local reactionTracks = setmetatable({}, { __mode = "k" })

local function playReaction(model, heavy)
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local tracks = reactionTracks[animator]
	if not tracks then
		tracks = {
			light = AnimationLibrary.Load(animator, "Reaccion"),
			heavy = AnimationLibrary.Load(animator, "ReaccionFuerte"),
		}
		reactionTracks[animator] = tracks
	end
	local track = if heavy then tracks.heavy else tracks.light
	track:Play(0.02, 1, 1)
end

-- Golpe que conecta (predicho en esta pantalla)
-- `blocked`: el golpe dio en una coraza (no hace daño): chispas frías y un golpe seco, sin destello ni reacción del
-- enemigo. Ligero, pesado, bloqueado y acertado se distinguen sin mirar los números.
function EffectsController.Impact(position, attack, targetModel, blocked)
	local heavy = attack.heavy or attack.finisher
	local part = anchorPart("ImpactoUmbral", position, 1)
	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	if blocked then
		burst(attachment, TEXTURES.Sparks, {
			Color = ColorSequence.new(Color3.fromRGB(215, 232, 255), Color3.fromRGB(110, 150, 230)),
			LightEmission = 0.5,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0) }),
			Lifetime = NumberRange.new(0.08, 0.18),
			Speed = NumberRange.new(22, 40),
			SpreadAngle = Vector2.new(55, 55),
			Drag = 5,
		}, math.max(4, math.floor(12 * EcoEfectos.Escala())))
		playSound("Block", part)
		if heavy then
			playSound("Break", part)
		end
		if attack.shake and attack.shake > 0 then
			CameraController.Shake(attack.shake * 0.5)
		end
		return
	end

	burst(attachment, TEXTURES.Sparks, {
		Color = ColorSequence.new(Color3.fromRGB(255, 244, 210), Color3.fromRGB(255, 170, 60)),
		LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, if heavy then 1.1 else 0.7), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.12, 0.26),
		Speed = NumberRange.new(if heavy then 30 else 18, if heavy then 55 else 34),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 7,
	}, math.max(4, math.floor((if heavy then 26 else 14) * EcoEfectos.Escala())))

	burst(attachment, TEXTURES.Shockwave, {
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
		LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, if heavy then 9 else 4.5) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(if heavy then 0.22 else 0.14),
		Speed = NumberRange.new(0),
		LockedToPart = true,
	}, 1)

	if EcoEfectos.Luces() then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 220, 160)
		light.Brightness = if heavy then 6 else 3
		light.Range = if heavy then 14 else 8
		light.Parent = part
		Debris:AddItem(light, 0.07)
	end

	local color = ecoColor()
	EcoEfectos.Destello(position, color, if heavy then 5.5 else 3.2, if heavy then 0.17 else 0.12)
	if heavy then
		EcoEfectos.Rayas(position, color, 7, 4.5)
	end
	playSound(if heavy then "HitHeavy" else "Hit", part)
	if attack.heavy then
		playSound("Boom", part)
	end
	flashTarget(targetModel)
	playReaction(targetModel, heavy)
	if attack.shake and attack.shake > 0 then
		CameraController.Shake(attack.shake)
	end
end

-- Inicio del momento de impacto (con o sin acierto)
function EffectsController.Swing(attack, character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		playSound(if attack.heavy then "SwingHeavy" else "Swing", root)
	end
end

-- Estela en la extremidad que golpea
function EffectsController.SetTrail(character, limbName, enabled)
	local limb = character and character:FindFirstChild(limbName)
	if not limb then
		return
	end
	local trail = limb:FindFirstChild("UmbralEstela")
	if not trail then
		if not enabled then
			return
		end
		-- Las piezas largas (la hoja de la espada, a lo largo de Z) dejan la estela en todo su largo
		local long = limb.Size.Z > 2
		local a0 = Instance.new("Attachment")
		a0.Name = "UmbralEstelaA"
		a0.Position = if long then Vector3.new(0, 0, limb.Size.Z * 0.45) else Vector3.new(0, LIMB_ATTACHMENT_OFFSET, 0)
		a0.Parent = limb
		local a1 = Instance.new("Attachment")
		a1.Name = "UmbralEstelaB"
		a1.Position = if long then Vector3.new(0, 0, -limb.Size.Z * 0.45) else Vector3.new(0, -LIMB_ATTACHMENT_OFFSET, 0)
		a1.Parent = limb
		trail = Instance.new("Trail")
		trail.Name = "UmbralEstela"
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.LightEmission = 1
		trail.Lifetime = if long then 0.16 else 0.12
		trail.FaceCamera = true
		trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
		trail.Parent = limb
	end
	if enabled then
		trail.Color = ColorSequence.new(Color3.new(1, 1, 1), ecoColor())
	end
	trail.Enabled = enabled
	if limb.Size.Z > 2 then
		bladeParticles(limb, enabled)
	end
end

-- Número de daño confirmado por el servidor
function EffectsController.DamageNumber(position, amount, big, color)
	if not CombatConfig.Feedback.DamageNumbers then
		return
	end
	local part = anchorPart("NumeroDanoUmbral", position + Vector3.new(math.random(-10, 10) / 10, 1.5, 0), 1)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(120, 50)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 80
	billboard.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = tostring(math.floor(amount + 0.5))
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color or (if big then Color3.fromRGB(255, 205, 70) else Color3.fromRGB(255, 255, 255))
	label.TextStrokeTransparency = 0.3
	label.Parent = billboard
	TweenService:Create(billboard, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 2.2, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
end

-- ---------- Fase 3: defensa ----------
local DEFENSE_STYLE = {
	desvio_perfecto = { color = Color3.fromRGB(255, 226, 120), size = 1.4, count = 30, sound = "Parry", shake = 0.22 },
	desvio = { color = Color3.fromRGB(185, 215, 255), size = 0.9, count = 16, sound = "ParryLight", shake = 0.08 },
	guardia = { color = Color3.fromRGB(140, 175, 255), size = 0.7, count = 10, sound = "Block", shake = 0.1 },
	ruptura = { color = Color3.fromRGB(255, 90, 70), size = 1.3, count = 26, sound = "Break", shake = 0.45 },
	golpe = { color = Color3.fromRGB(255, 120, 100), size = 0.9, count = 14, sound = "Hit", shake = 0.3 },
}

-- Imagen residual: una copia del cuerpo que se desvanece (Contrapaso, esquiva)
function EffectsController.Afterimage(character, strong)
	if not character then
		return
	end
	local color = if strong then Color3.fromRGB(150, 210, 255) else Color3.fromRGB(200, 220, 255)
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and part.Transparency < 1 then
			local ghost = Instance.new("Part")
			ghost.Name = "UmbralResiduo"
			ghost.Anchored = true
			ghost.CanCollide = false
			ghost.CanQuery = false
			ghost.CanTouch = false
			ghost.CastShadow = false
			ghost.Material = Enum.Material.Neon
			ghost.Color = color
			ghost.Size = part.Size
			ghost.CFrame = part.CFrame
			ghost.Transparency = if strong then 0.35 else 0.55
			ghost.Parent = effectsFolder()
			TweenService:Create(ghost, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 }):Play()
			Debris:AddItem(ghost, 0.4)
		end
	end
end

-- Brillo del Contraataque
function EffectsController.Counter(character)
	flashTarget(character, Color3.fromRGB(255, 220, 110))
end

-- Respuesta a un resultado defensivo del propio jugador
function EffectsController.DefenseFeedback(result, character, from)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local own = character == Players.LocalPlayer.Character
	if result == "contrapaso" or result == "esquiva" then
		EffectsController.Afterimage(character, result == "contrapaso")
		playSound("Dodge", root)
		if own and result == "contrapaso" then
			EcoEfectos.ImpactFrame(Color3.fromRGB(150, 210, 255), 0.45)
		end
		return
	end
	local style = DEFENSE_STYLE[result]
	if not style then
		return
	end
	local toward = Vector3.new(from.X - root.Position.X, 0, from.Z - root.Position.Z)
	toward = if toward.Magnitude > 0.01 then toward.Unit else root.CFrame.LookVector
	local part = anchorPart("DefensaUmbral", root.Position + Vector3.new(0, 0.8, 0) + toward * 1.2, 1)
	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	burst(attachment, TEXTURES.Sparks, {
		Color = ColorSequence.new(style.color),
		LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, style.size), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.12, 0.3),
		Speed = NumberRange.new(20, 42),
		SpreadAngle = Vector2.new(70, 70),
		Drag = 6,
	}, style.count)
	if result == "desvio_perfecto" and own then
		EcoEfectos.ImpactFrame(Color3.fromRGB(255, 225, 140), 0.5)
		EcoEfectos.Destello(part.Position, Color3.fromRGB(255, 220, 120), 5, 0.16)
	end
	if result == "desvio_perfecto" or result == "ruptura" then
		burst(attachment, TEXTURES.Shockwave, {
			Color = ColorSequence.new(style.color),
			LightEmission = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 7) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(0.2),
			Speed = NumberRange.new(0),
			LockedToPart = true,
		}, 1)
	end
	playSound(style.sound, part)
	if result == "golpe" or result == "ruptura" then
		flashTarget(character, style.color)
	end
	CameraController.Shake(style.shake)
end

-- Sonido de aviso de un ataque enemigo (distinto para cada amenaza: no depende solo del color)
function EffectsController.WindupCue(model, heavy)
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if root then
		playSound(if heavy then "WindupHeavy" else "WindupLight", root)
	end
end

-- Golpes confirmados por el servidor (de cualquier jugador)
function EffectsController.OnConfirmed(data, isLocalAttacker)
	local attack = CombatConfig.Attacks[data.attack]
	if data.attack == "GolpeDeGracia" then
		-- El que lo hizo ya vio su impacto; todos ven el número grande
		if not isLocalAttacker and typeof(data.position) == "Vector3" then
			EffectsController.Impact(data.position, CombatConfig.Attacks.Fuerte, data.target)
		end
		if typeof(data.position) == "Vector3" then
			EffectsController.DamageNumber(data.position, data.damage, true)
		end
		return
	end
	if not attack then
		-- Habilidades del Eco: número de daño, destello y reacción del golpeado (el estallido de color lo pone
		-- EcoController con el color del Eco de quien la usó)
		if type(data.attack) == "string" and string.sub(data.attack, 1, 3) == "Eco" and typeof(data.position) == "Vector3" and (data.damage or 0) > 0 then
			-- El número sale con el color del Eco de quien lo hizo (la quemadura, en naranja; un combo, dorado)
			local kit = CombatConfig.Eco.Kits[data.element or ""] or (typeof(data.attacker) == "Instance" and CombatConfig.Eco.Kits[data.attacker:GetAttribute("Eco") or ""])
			local color = if data.synergy then Color3.fromRGB(255, 215, 90)
				elseif data.attack == "EcoQuemadura" then Color3.fromRGB(255, 140, 50)
				elseif kit then kit.color
				else nil
			EffectsController.DamageNumber(data.position, data.damage, data.synergy ~= nil, color)
			flashTarget(data.target)
			playReaction(data.target, (data.damage or 0) >= 10)
			if isLocalAttacker then
				playSound("Hit", anchorPart("ImpactoEcoUmbral", data.position, 1))
			end
		end
		return
	end
	if not isLocalAttacker then
		-- El atacante ya vio su impacto al instante; los demás lo ven al confirmarse
		EffectsController.Impact(data.position, attack, data.target)
	end
	EffectsController.DamageNumber(data.position, data.damage, attack.heavy or attack.finisher)
end

return EffectsController
