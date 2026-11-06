-- EnemyController: cómo se ve y se oye el compañero de combate en ESTA pantalla.
-- El servidor solo publica su estado (atributos Estado, Ataque, FaseInicio, FaseFin con hora del servidor);
-- aquí se anima y se avisa, sincronizado con esa hora aunque haya lag.
-- Cada amenaza se reconoce por tres señales, no solo por color:
--   Golpe   · brazo armado arriba · brillo rojo · sonido grave corto
--   Barrido · agachado · brillo violeta + anillo en el suelo con el área · sonido de explosión grave

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(shared:WaitForChild("Config"):WaitForChild("CombatConfig"))
local AnimationLibrary = require(shared:WaitForChild("Combat"):WaitForChild("AnimationLibrary"))
local Effects = require(script.Parent:WaitForChild("EffectsController"))

local EnemyController = {}

local sparring = CombatConfig.Sparring
local TELEGRAPH = {
	Golpe = { color = Color3.fromRGB(255, 70, 60), clip = "SparringGolpe", heavy = false },
	Barrido = { color = Color3.fromRGB(170, 80, 255), clip = "SparringBarrido", heavy = true },
}

local enemies = {} -- [model] = { tracks, highlight, ring, current }

local function serverNow()
	return Workspace:GetServerTimeNow()
end

local function cleanup(e)
	if e.highlight then
		e.highlight:Destroy()
		e.highlight = nil
	end
	if e.ring then
		e.ring:Destroy()
		e.ring = nil
	end
end

local function trackFor(e, model, clip)
	if e.tracks[clip] then
		return e.tracks[clip]
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	local ok, track = pcall(AnimationLibrary.Load, animator, clip)
	if ok then
		e.tracks[clip] = track
		return track
	end
	return nil
end

local function play(e, model, clip, fromTime)
	if e.current then
		e.current:Stop(0.1)
		e.current = nil
	end
	local track = trackFor(e, model, clip)
	if track then
		track:Play(0.05, 1, 1)
		if fromTime and fromTime > 0 then
			track.TimePosition = math.min(fromTime, math.max(track.Length - 0.01, 0))
		end
		e.current = track
	end
end

local function onState(model, e)
	local state = model:GetAttribute("Estado")
	local attackName = model:GetAttribute("Ataque")
	local start = model:GetAttribute("FaseInicio") or serverNow()
	local finish = model:GetAttribute("FaseFin") or serverNow()
	local elapsed = math.max(0, serverNow() - start)

	if state == "Preparando" and TELEGRAPH[attackName] then
		local style = TELEGRAPH[attackName]
		local attack = sparring.Attacks[attackName]
		cleanup(e)
		play(e, model, style.clip, elapsed)
		Effects.WindupCue(model, style.heavy)

		-- Brillo que se intensifica hasta el impacto
		local highlight = Instance.new("Highlight")
		highlight.Name = "UmbralAviso"
		highlight.Adornee = model
		highlight.FillColor = style.color
		highlight.OutlineColor = style.color
		highlight.FillTransparency = 0.85
		highlight.OutlineTransparency = 0.2
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = Workspace.CurrentCamera
		e.highlight = highlight
		local remaining = math.max(0.05, finish - serverNow())
		TweenService:Create(highlight, TweenInfo.new(remaining, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { FillTransparency = 0.3 }):Play()

		-- Barrido: anillo en el suelo con el área real
		if attack.shape == "ring" then
			local root = model:FindFirstChild("HumanoidRootPart")
			if root then
				local ring = Instance.new("Part")
				ring.Name = "UmbralAreaBarrido"
				ring.Shape = Enum.PartType.Cylinder
				ring.Anchored = true
				ring.CanCollide = false
				ring.CanQuery = false
				ring.CanTouch = false
				ring.CastShadow = false
				ring.Material = Enum.Material.Neon
				ring.Color = style.color
				ring.Transparency = 0.85
				ring.Size = Vector3.new(0.1, attack.radius * 2, attack.radius * 2)
				local ground = root.Position - Vector3.new(0, 2.9, 0)
				ring.CFrame = CFrame.new(ground) * CFrame.Angles(0, 0, math.rad(90))
				ring.Parent = Workspace.CurrentCamera
				e.ring = ring
				TweenService:Create(ring, TweenInfo.new(remaining, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 0.45 }):Play()
			end
		end
	elseif state == "Atacando" then
		if e.highlight then
			e.highlight.FillColor = Color3.new(1, 1, 1)
			e.highlight.FillTransparency = 0.2
		end
		if e.ring then
			e.ring.Transparency = 0.25
		end
	elseif state == "Recuperando" then
		cleanup(e)
	elseif state == "Aturdido" then
		cleanup(e)
		play(e, model, "Aturdido", 0)
	else
		cleanup(e)
		if e.current and e.current.Animation and e.current.Animation.Name == "Aturdido" then
			e.current:Stop(0.2)
			e.current = nil
		end
	end
end

local function watch(model)
	if enemies[model] then
		return
	end
	local e = { tracks = {} }
	enemies[model] = e
	model:GetAttributeChangedSignal("Estado"):Connect(function()
		onState(model, e)
	end)
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(Workspace) then
			cleanup(e)
			enemies[model] = nil
		end
	end)
	onState(model, e)
end

function EnemyController.Start()
	for _, model in ipairs(CollectionService:GetTagged("Sparring")) do
		task.spawn(watch, model)
	end
	CollectionService:GetInstanceAddedSignal("Sparring"):Connect(function(model)
		task.spawn(watch, model)
	end)
end

return EnemyController
