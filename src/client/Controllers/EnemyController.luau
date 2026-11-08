-- EnemyController: cómo se ve y se oye el compañero de combate en ESTA pantalla.
-- El servidor solo publica su estado (atributos Estado, Ataque, FaseInicio, FaseFin con hora del servidor);
-- aquí se anima y se avisa, sincronizado con esa hora aunque haya lag.
-- Cada amenaza se reconoce por tres señales, no solo por color:
--   Golpe   · brazo armado arriba · brillo rojo · sonido grave corto
--   Rápido  · preparación corta · brillo naranja
--   Pesado  · brillo rojo oscuro · aviso pesado (solo el desvío PERFECTO lo detiene)
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
-- Color y peso del aviso de cada ataque (el clip sale de attack.clip en CombatConfig)
local TELEGRAPH = {
	Golpe = { color = Color3.fromRGB(255, 70, 60), heavy = false },
	Rapido = { color = Color3.fromRGB(255, 150, 40), heavy = false },
	Fuerte = { color = Color3.fromRGB(150, 20, 30), heavy = true },
	Barrido = { color = Color3.fromRGB(170, 80, 255), heavy = true },
	Embestida = { color = Color3.fromRGB(255, 250, 220), heavy = false }, -- Golpe de Oportunidad: blanco
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
	if e.fill then
		e.fill:Destroy()
		e.fill = nil
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

	local attack = sparring.Attacks[attackName]
	if state == "Preparando" and attack and TELEGRAPH[attackName] then
		local style = TELEGRAPH[attackName]
		cleanup(e)
		e.holdToken = (e.holdToken or 0) + 1
		play(e, model, attack.clip, elapsed)
		Effects.WindupCue(model, style.heavy)
		-- Retraso deliberado: la preparación dura más que el clip. Se congela la pose armada (holdAt)
		-- el tiempo extra, así la animación sigue llegando al impacto en el instante real.
		local extra = (finish - start) - attack.startup
		if extra > 0.01 and attack.holdAt and e.current then
			local token, track = e.holdToken, e.current
			local holdStart = start + attack.holdAt
			local function freezeAt(serverTime, fn)
				task.delay(math.max(0, serverTime - serverNow()), function()
					if e.holdToken == token and e.current == track then
						fn()
					end
				end)
			end
			if serverNow() < holdStart + extra then
				freezeAt(holdStart, function()
					track.TimePosition = attack.holdAt
					track:AdjustSpeed(0)
				end)
				freezeAt(holdStart + extra, function()
					track:AdjustSpeed(1)
				end)
			end
		end

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
				-- Relleno que crece desde el centro y toca el borde JUSTO en el impacto: se lee cuándo saltar o salir
				local fill = ring:Clone()
				fill.Name = "UmbralTiempoBarrido"
				fill.Transparency = 0.6
				fill.Size = Vector3.new(0.12, 0.6, 0.6)
				fill.Parent = Workspace.CurrentCamera
				e.fill = fill
				TweenService:Create(fill, TweenInfo.new(remaining, Enum.EasingStyle.Linear), { Size = Vector3.new(0.12, attack.radius * 2, attack.radius * 2) }):Play()
			end
		end
	elseif state == "Atacando" then
		e.holdToken = (e.holdToken or 0) + 1
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

-- Barra de postura sobre el enemigo (naranja) y el aviso de QUEBRADO (rojo): atacar cerca = Golpe de Gracia
local function postureBar(model)
	-- El servidor fija la postura máxima justo después de crear al enemigo: se espera un poco
	local start = os.clock()
	while not model:GetAttribute("PosturaMax") and os.clock() - start < 6 and model.Parent do
		task.wait(0.2)
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not model:GetAttribute("PosturaMax") or root:FindFirstChild("UmbralPostura") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "UmbralPostura"
	gui.Size = UDim2.fromOffset(110, 26)
	gui.StudsOffset = Vector3.new(0, 4.6, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 70
	local back = Instance.new("Frame")
	back.AnchorPoint = Vector2.new(0.5, 1)
	back.Position = UDim2.fromScale(0.5, 1)
	back.Size = UDim2.new(1, 0, 0, 7)
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
	back.BackgroundTransparency = 0.3
	back.BorderSizePixel = 0
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(255, 160, 60)
	fill.BorderSizePixel = 0
	fill.Parent = back
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, -9)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 90, 80)
	label.TextStrokeTransparency = 0.2
	label.Text = ""
	label.Parent = gui
	gui.Adornee = root
	gui.Parent = root
	local function refresh()
		local max = model:GetAttribute("PosturaMax") or 100
		local value = model:GetAttribute("Postura") or 0
		local brokenUntil = model:GetAttribute("QuebradoHasta") or 0
		local isBroken = brokenUntil > serverNow()
		back.Visible = value > 0.5 or isBroken
		fill.Size = UDim2.fromScale(math.clamp(value / max, 0, 1), 1)
		fill.BackgroundColor3 = if isBroken then Color3.fromRGB(255, 70, 60) elseif value / max > 0.75 then Color3.fromRGB(255, 120, 50) else Color3.fromRGB(255, 170, 70)
		label.Text = if isBroken then "¡QUEBRADO! · ATACA" else ""
	end
	model:GetAttributeChangedSignal("Postura"):Connect(refresh)
	model:GetAttributeChangedSignal("QuebradoHasta"):Connect(function()
		refresh()
		local untilTime = model:GetAttribute("QuebradoHasta")
		if untilTime then
			task.delay(math.max(0, untilTime - serverNow()) + 0.05, refresh)
		end
	end)
	refresh()
end

local function watch(model)
	if enemies[model] then
		return
	end
	local e = { tracks = {} }
	enemies[model] = e
	task.spawn(postureBar, model)
	model:GetAttributeChangedSignal("Estado"):Connect(function()
		onState(model, e)
	end)
	-- Un amague reinicia la preparación sin cambiar Estado: FaseInicio sí cambia
	model:GetAttributeChangedSignal("FaseInicio"):Connect(function()
		if model:GetAttribute("Estado") == "Preparando" then
			onState(model, e)
		end
	end)
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(Workspace) then
			cleanup(e)
			enemies[model] = nil
		end
	end)
	onState(model, e)
end

-- Onda del Desvío Reflejado: un anillo que se expande desde el jugador hasta el alcance real
local function reflectWave(data)
	if type(data) ~= "table" or typeof(data.position) ~= "Vector3" then
		return
	end
	local radius = tonumber(data.radius) or 10
	local ring = Instance.new("Part")
	ring.Name = "UmbralOndaReflejo"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(150, 255, 230)
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.2, 1, 1)
	ring.CFrame = CFrame.new(data.position - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = Workspace.CurrentCamera
	local tween = TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, radius * 2, radius * 2),
		Transparency = 1,
	})
	tween.Completed:Connect(function()
		ring:Destroy()
	end)
	tween:Play()
end

function EnemyController.Start()
	task.spawn(function()
		local wave = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("OndaReflejo", 30)
		if wave then
			wave.OnClientEvent:Connect(reflectWave)
		end
	end)
	for _, model in ipairs(CollectionService:GetTagged("Sparring")) do
		task.spawn(watch, model)
	end
	CollectionService:GetInstanceAddedSignal("Sparring"):Connect(function(model)
		task.spawn(watch, model)
	end)
end

return EnemyController
