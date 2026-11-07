-- TutorialController: tutorial jugable de la entrada de la Grieta (EXPERIMENTAL).
-- Guía paso a paso y marca cada paso cuando el jugador DE VERDAD lo hizo (eventos del movimiento, del
-- combate confirmado por el servidor y del Eco). Se puede saltar (tecla T o botón) y repetir desde el menú.
-- Solo aparece donde existe la Grieta (lugar de desarrollo); el Instructor espera en la sala de entrada.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local configFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local CombatConfig = require(configFolder:WaitForChild("CombatConfig"))
local MovementConfig = require(configFolder:WaitForChild("MovementConfig"))

local TutorialController = {}

local player = Players.LocalPlayer
local ACCENT = Color3.fromRGB(150, 255, 230)
local DONE = Color3.fromRGB(120, 255, 140)

-- Pasos: texto y cómo se cumple (cada uno recibe el "contexto" con contadores)
local STEPS = {
	{ text = "Muévete con WASD y apunta moviendo el ratón (Ctrl suelta el ratón)", done = function(c)
		return c.moved >= 8
	end, hint = function()
		return "Con la cámara fija el personaje mira hacia la mira: golpes y habilidades salen hacia ella"
	end },
	{ text = "Da un PASO: Shift (botón PASO) — te lanza 14 studs", done = function(c)
		return c.dashes >= 1
	end },
	{ text = "Salta con Espacio y vuelve a saltar en el aire: DOBLE SALTO", done = function(c)
		return c.doubleJumps >= 1
	end },
	{ text = "Acércate al INSTRUCTOR y golpéalo 3 veces seguidas: clic, clic, clic", done = function(c)
		return c.instructorHits >= 3
	end },
	{ text = "Cuando el Instructor brille ROJO, pulsa F justo antes del golpe: ¡DESVÍO!", done = function(c)
		return c.deflects >= 1
	end },
	{ text = "CONTRAPASO: Shift hacia un costado justo antes de su golpe", done = function(c)
		return c.contrapasos >= 1
	end },
	{ text = "HABILIDADES: cada una en su tecla. Usa dos distintas: Z Cuchilla · X Ciclón · C Levante", done = function(c)
		return c.skillCount >= 2
	end, hint = function()
		return "Salen al instante y puedes moverte mientras las lanzas. La barra de abajo muestra cuándo vuelven a estar listas"
	end },
	{ text = "COMBO: X (Ciclón) atrae al Instructor y enseguida Z o C sobre él: ¡SINERGIA!", done = function(c)
		return c.synergies >= 1
	end, hint = function()
		return "Tras un Levante (C) que conecta, pulsa C otra vez para subir tras él y sigue golpeando en el aire. V: la definitiva (gasta Resonancia)"
	end },
	{ text = "ECOS: tienes 5. Pulsa 2 para cambiar al Eco del AGUA (1-5 los cambia)", done = function(c)
		return c.kitChanges >= 1
	end, hint = function()
		return "La ficha te dice qué hace cada tecla; pulsa el número de tu Eco para volver a verla. Puedes cambiar a mitad de un combo"
	end },
	{ text = "REACCIONES: moja al Instructor con el AGUA (2, tecla Z) y cambia a TRUENO (5, tecla C): ¡ELECTROCUCIÓN!", done = function(c)
		return c.reactions >= 1
	end, hint = function()
		return "Agua moja · Trueno carga · Fuego quema. Golpear con otro Eco provoca una reacción; abajo se ve qué Eco aprovecha al enemigo de enfrente"
	end },
	{ text = "ARMAS: pulsa Q para sacar la ESPADA y golpea 2 veces al Instructor con ella", done = function(c)
		return c.swordHits >= 2
	end, hint = function()
		return "Q otra vez: puños. Atacar justo tras un Paso: golpe en carrera · cayendo desde alto: picada · E: gancho a los orbes brillantes"
	end },
}

local context = nil
local current = 0
local gui, title, body, hintLabel = nil, nil, nil, nil
local active = false

local function newContext()
	return { moved = 0, dashes = 0, doubleJumps = 0, instructorHits = 0, deflects = 0, contrapasos = 0, skillsUsed = {}, skillCount = 0, synergies = 0, kitChanges = 0, reactions = 0, swordHits = 0, start = nil }
end

local function show()
	if not gui then
		return
	end
	if current > #STEPS then
		title.Text = "TUTORIAL COMPLETO"
		title.TextColor3 = DONE
		body.Text = "¡Listo! Sigue las antorchas: el abismo, los enemigos y el Guardián te esperan. (Menú → Repetir tutorial)"
		hintLabel.Text = ""
		task.delay(7, function()
			if current > #STEPS and gui then
				gui.Enabled = false
				active = false
			end
		end)
		return
	end
	title.Text = string.format("TUTORIAL %d/%d", current, #STEPS)
	title.TextColor3 = ACCENT
	body.Text = STEPS[current].text
	local step = STEPS[current]
	hintLabel.Text = if step.hint then (step.hint() or "") else ""
end

local function advance()
	if not active or current > #STEPS then
		return
	end
	local step = STEPS[current]
	if step and step.done(context) then
		current += 1
		-- destello verde al cumplir
		title.TextColor3 = DONE
		local scale = title:FindFirstChildOfClass("UIScale")
		if scale then
			scale.Scale = 1.25
			TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
		task.delay(0.35, show)
	elseif step and step.hint then
		hintLabel.Text = step.hint() or ""
	end
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "UmbralTutorial"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 44)
	frame.Size = UDim2.new(0.6, 0, 0, 92)
	frame.BackgroundColor3 = Color3.fromRGB(12, 16, 24)
	frame.BackgroundTransparency = 0.2
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(640, 92)
	limit.Parent = frame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame
	frame.Parent = gui

	title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(12, 6)
	title.Size = UDim2.new(1, -110, 0, 22)
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = ACCENT
	Instance.new("UIScale").Parent = title
	title.Parent = frame

	body = Instance.new("TextLabel")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(12, 30)
	body.Size = UDim2.new(1, -24, 0, 34)
	body.Font = Enum.Font.GothamBold
	body.TextScaled = true
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextColor3 = Color3.fromRGB(235, 238, 248)
	body.Parent = frame

	hintLabel = Instance.new("TextLabel")
	hintLabel.BackgroundTransparency = 1
	hintLabel.Position = UDim2.fromOffset(12, 66)
	hintLabel.Size = UDim2.new(1, -24, 0, 18)
	hintLabel.Font = Enum.Font.Gotham
	hintLabel.TextScaled = true
	hintLabel.TextXAlignment = Enum.TextXAlignment.Left
	hintLabel.TextColor3 = Color3.fromRGB(255, 220, 140)
	hintLabel.Text = ""
	hintLabel.Parent = frame

	local skip = Instance.new("TextButton")
	skip.AnchorPoint = Vector2.new(1, 0)
	skip.Position = UDim2.new(1, -8, 0, 6)
	skip.Size = UDim2.fromOffset(96, 22)
	skip.BackgroundColor3 = Color3.fromRGB(40, 44, 60)
	skip.Font = Enum.Font.GothamBold
	skip.Text = "Saltar (T)"
	skip.TextScaled = true
	skip.TextColor3 = Color3.fromRGB(200, 205, 220)
	local skipCorner = Instance.new("UICorner")
	skipCorner.CornerRadius = UDim.new(0, 6)
	skipCorner.Parent = skip
	skip.Parent = frame
	skip.Activated:Connect(function()
		TutorialController.Skip()
	end)
	gui.Parent = player:WaitForChild("PlayerGui")
end

function TutorialController.Skip()
	active = false
	if gui then
		gui.Enabled = false
	end
end

function TutorialController.Restart()
	context = newContext()
	current = 1
	active = true
	if gui then
		gui.Enabled = true
	end
	show()
end

-- Título al entrar: "UMBRAL · Despierta tu Eco" que aparece y se desvanece
local function titleCard()
	local gui = Instance.new("ScreenGui")
	gui.Name = "UmbralTitulo"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	local shade = Instance.new("Frame")
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.fromRGB(6, 4, 14)
	shade.BackgroundTransparency = 0.25
	shade.BorderSizePixel = 0
	shade.Parent = gui
	local title = Instance.new("TextLabel")
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.42)
	title.Size = UDim2.new(0.7, 0, 0, 90)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.Text = "UMBRAL"
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(205, 160, 255)
	title.TextStrokeTransparency = 0.2
	title.Parent = shade
	local subtitle = Instance.new("TextLabel")
	subtitle.AnchorPoint = Vector2.new(0.5, 0)
	subtitle.Position = UDim2.new(0.5, 0, 0.42, 52)
	subtitle.Size = UDim2.new(0.6, 0, 0, 30)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.GothamBold
	subtitle.Text = "Despierta tu Eco"
	subtitle.TextScaled = true
	subtitle.TextColor3 = Color3.fromRGB(150, 255, 230)
	subtitle.TextStrokeTransparency = 0.3
	subtitle.Parent = shade
	gui.Parent = player:WaitForChild("PlayerGui")
	task.delay(2.2, function()
		local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(shade, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(title, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(subtitle, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.delay(1, function()
			gui:Destroy()
		end)
	end)
end

function TutorialController.Start(movement, combat, eco)
	-- Solo donde existe la Grieta
	local maps = Workspace:WaitForChild("Maps", 10)
	if not maps or not maps:WaitForChild("Grieta", 5) then
		return
	end
	task.spawn(titleCard)
	build()
	context = newContext()

	movement.Dashed:Connect(function()
		context.dashes += 1
		advance()
	end)
	combat.Confirmed:Connect(function(data)
		if type(data) == "table" and typeof(data.target) == "Instance" and data.target:HasTag("Instructor") then
			context.instructorHits += 1
			local def = CombatConfig.Attacks[data.attack]
			if def and def.weapon == "Espada" then
				context.swordHits += 1
			end
			advance()
		end
	end)
	combat.DefenseResult:Connect(function(data)
		if type(data) ~= "table" then
			return
		end
		if data.result == "desvio" or data.result == "desvio_perfecto" then
			context.deflects += 1
		elseif data.result == "contrapaso" then
			context.contrapasos += 1
		end
		advance()
	end)
	if eco and eco.Used then
		eco.Used:Connect(function(skillName)
			if type(skillName) == "string" and not context.skillsUsed[skillName] then
				context.skillsUsed[skillName] = true
				context.skillCount += 1
			end
			advance()
		end)
	end
	if eco and eco.Synergy then
		eco.Synergy:Connect(function()
			context.synergies += 1
			advance()
		end)
	end
	if eco and eco.KitChanged then
		eco.KitChanged:Connect(function()
			context.kitChanges += 1
			advance()
		end)
	end
	player:GetAttributeChangedSignal("Reacciones"):Connect(function()
		context.reactions += 1
		advance()
	end)
	player:GetAttributeChangedSignal("Resonancia"):Connect(advance)

	-- Movimiento y doble salto: se miden cada cuadro (baratos)
	local last = nil
	game:GetService("RunService").Heartbeat:Connect(function()
		if not active then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			if last then
				local step = Vector3.new(root.Position.X - last.X, 0, root.Position.Z - last.Z).Magnitude
				if step < 5 then -- ignora teletransportes
					context.moved += step
				end
			end
			last = root.Position
		end
		if not movement.State.grounded and movement.State.airJumpsLeft < MovementConfig.AirJumps then
			context.doubleJumps = math.max(context.doubleJumps, 1)
		end
		if current <= #STEPS and STEPS[current].done(context) then
			advance()
		end
	end)

	ContextActionService:BindAction("UmbralSaltarTutorial", function(_, state)
		if state == Enum.UserInputState.Begin and active then
			TutorialController.Skip()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.T)

	TutorialController.Restart()
end

return TutorialController
