-- AvisosHUD: dos ayudas para pelear contra varios enemigos (solo se ven en esta pantalla).
--   · Indicador de golpe: si te pegan, una marca roja en el borde de la pantalla señala de dónde vino el golpe
--     (útil cuando el atacante está detrás o fuera de la vista).
--   · Vida baja: por debajo del 30 % de vida, los bordes de la pantalla laten en rojo.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local AvisosHUD = {}

local RED = Color3.fromRGB(255, 60, 50)
local LOW_HEALTH = 0.3

local function edge(parent, anchor, position, size, rotation)
	local frame = Instance.new("Frame")
	frame.AnchorPoint = anchor
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = RED
	frame.BorderSizePixel = 0
	frame.BackgroundTransparency = 0
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	gradient.Parent = frame
	frame.Parent = parent
	return frame
end

function AvisosHUD.Start(combat)
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "UmbralAvisos"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 4

	-- Viñeta de vida baja: cuatro bordes con degradado hacia el centro
	local vignette = Instance.new("CanvasGroup")
	vignette.Name = "VidaBaja"
	vignette.Size = UDim2.fromScale(1, 1)
	vignette.BackgroundTransparency = 1
	vignette.GroupTransparency = 1
	vignette.Parent = gui
	edge(vignette, Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.new(1, 0, 0.18, 0), 90)
	edge(vignette, Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.new(1, 0, 0.18, 0), -90)
	edge(vignette, Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.new(0.12, 0, 1, 0), 0)
	edge(vignette, Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.new(0.12, 0, 1, 0), 180)

	-- Indicador de golpe: una marca que gira alrededor del centro hacia el atacante
	local pivot = Instance.new("Frame")
	pivot.Name = "IndicadorGolpe"
	pivot.AnchorPoint = Vector2.new(0.5, 0.5)
	pivot.Position = UDim2.fromScale(0.5, 0.5)
	pivot.Size = UDim2.fromScale(0.62, 0.62)
	pivot.SizeConstraint = Enum.SizeConstraint.RelativeYY
	pivot.BackgroundTransparency = 1
	pivot.Visible = false
	pivot.Parent = gui
	local mark = Instance.new("Frame")
	mark.AnchorPoint = Vector2.new(0.5, 0)
	mark.Position = UDim2.fromScale(0.5, 0)
	mark.Size = UDim2.new(0.22, 0, 0, 9)
	mark.BackgroundColor3 = RED
	mark.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = mark
	local markGradient = Instance.new("UIGradient")
	markGradient.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) })
	markGradient.Parent = mark
	mark.Parent = pivot
	gui.Parent = player:WaitForChild("PlayerGui")

	local hitToken = 0
	local from = nil
	local function showHit(position)
		from = position
		hitToken += 1
		local token = hitToken
		pivot.Visible = true
		mark.BackgroundTransparency = 0
		task.delay(0.5, function()
			if token == hitToken then
				TweenService:Create(mark, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
				task.delay(0.32, function()
					if token == hitToken then
						pivot.Visible = false
						from = nil
					end
				end)
			end
		end)
	end
	-- Entrenador de defensa: si pulsaste Defender cerca del golpe, cuánto te faltó para el desvío (perfecto)
	local defense = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("CombatConfig")).Defense
	local coach = Instance.new("TextLabel")
	coach.Name = "Entrenador"
	coach.AnchorPoint = Vector2.new(0.5, 0.5)
	coach.Position = UDim2.fromScale(0.5, 0.62)
	coach.Size = UDim2.fromOffset(420, 22)
	coach.BackgroundTransparency = 1
	coach.Font = Enum.Font.GothamBold
	coach.TextScaled = true
	coach.TextColor3 = Color3.fromRGB(235, 235, 245)
	coach.TextStrokeTransparency = 0.3
	coach.TextTransparency = 1
	coach.TextStrokeTransparency = 1
	coach.Parent = gui
	local coachToken = 0
	local function advise(text)
		coachToken += 1
		local token = coachToken
		coach.Text = text
		coach.TextTransparency, coach.TextStrokeTransparency = 0, 0.3
		task.delay(1.4, function()
			if token == coachToken then
				TweenService:Create(coach, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		end)
	end
	if combat and combat.DefenseResult then
		combat.DefenseResult:Connect(function(data)
			if type(data) ~= "table" then
				return
			end
			if (data.result == "golpe" or data.result == "ruptura") and typeof(data.from) == "Vector3" then
				showHit(data.from)
			end
			local timing = data.timing
			if type(timing) == "number" then
				local ms = math.floor(math.abs(timing) * 1000 + 0.5)
				if data.result == "desvio" then
					local toPerfect = math.floor((timing - defense.PerfectWindow) * 1000 + 0.5)
					if toPerfect > 0 then
						advise(string.format("desvío: para el perfecto, pulsa %d ms más tarde", toPerfect))
					end
				elseif data.result ~= "desvio_perfecto" and data.result ~= "contrapaso" and data.result ~= "esquiva" then
					if timing > defense.DeflectWindow then
						advise(string.format("desvío %d ms temprano", math.floor((timing - defense.DeflectWindow) * 1000 + 0.5)))
					elseif timing < -0.03 then
						advise(string.format("desvío %d ms tarde", ms))
					end
				end
			end
		end)
	end

	-- Golpe que en esta pantalla conectó pero el servidor no aceptó: una ✕ sobre el objetivo con el motivo (así se
	-- entiende por qué no contó, en vez de sentir que el juego se lo comió)
	local lastTarget, lastHitClock = nil, -math.huge
	if combat and combat.Hit then
		combat.Hit:Connect(function(_, model)
			if typeof(model) == "Instance" then
				lastTarget, lastHitClock = model, os.clock()
			end
		end)
	end
	local rejectedBefore = player:GetAttribute("GolpesRechazados") or 0
	player:GetAttributeChangedSignal("GolpesRechazados"):Connect(function()
		local count = player:GetAttribute("GolpesRechazados") or 0
		local grew = count > rejectedBefore
		rejectedBefore = count
		local root = lastTarget and lastTarget:FindFirstChild("HumanoidRootPart")
		if not grew or not root or os.clock() - lastHitClock > 0.8 then
			return
		end
		local reason = tostring(player:GetAttribute("UltimoRechazo") or "")
		reason = string.match(reason, "^[^%(·]+") or reason -- solo la causa, sin los datos técnicos
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(170, 40)
		gui.StudsOffset = Vector3.new(0, 4, 0)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		local mark = Instance.new("TextLabel")
		mark.BackgroundTransparency = 1
		mark.Size = UDim2.new(1, 0, 0.6, 0)
		mark.Font = Enum.Font.GothamBlack
		mark.TextScaled = true
		mark.Text = "✕"
		mark.TextColor3 = Color3.fromRGB(200, 200, 210)
		mark.TextStrokeTransparency = 0.2
		mark.Parent = gui
		local why = Instance.new("TextLabel")
		why.BackgroundTransparency = 1
		why.Position = UDim2.fromScale(0, 0.6)
		why.Size = UDim2.new(1, 0, 0.4, 0)
		why.Font = Enum.Font.GothamBold
		why.TextScaled = true
		why.Text = "no contó: " .. reason
		why.TextColor3 = Color3.fromRGB(200, 200, 210)
		why.TextStrokeTransparency = 0.3
		why.Parent = gui
		gui.Adornee = root
		gui.Parent = player:WaitForChild("PlayerGui")
		task.delay(0.9, function()
			TweenService:Create(mark, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			TweenService:Create(why, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			task.delay(0.32, function()
				gui:Destroy()
			end)
		end)
	end)

	local pulse = 0
	RunService.RenderStepped:Connect(function(dt)
		-- La marca apunta al atacante según hacia dónde mira la cámara (arriba = delante, abajo = detrás)
		local camera = Workspace.CurrentCamera
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if from and camera and root then
			local offset = from - root.Position
			local look = camera.CFrame.LookVector
			local right = camera.CFrame.RightVector
			local forward = Vector3.new(look.X, 0, look.Z)
			local side = Vector3.new(right.X, 0, right.Z)
			if forward.Magnitude > 0.01 and side.Magnitude > 0.01 then
				local angle = math.atan2(offset:Dot(side.Unit), offset:Dot(forward.Unit))
				pivot.Rotation = math.deg(angle)
			end
		end
		-- Vida baja: late más rápido cuanto menos vida queda
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local ratio = if humanoid and humanoid.MaxHealth > 0 then humanoid.Health / humanoid.MaxHealth else 1
		if humanoid and humanoid.Health > 0 and ratio < LOW_HEALTH then
			pulse += dt * (4 + (LOW_HEALTH - ratio) * 20)
			vignette.GroupTransparency = 0.45 + 0.35 * (0.5 + 0.5 * math.sin(pulse))
		elseif vignette.GroupTransparency < 1 then
			vignette.GroupTransparency = math.min(1, vignette.GroupTransparency + dt * 2)
		end
	end)
end

return AvisosHUD
