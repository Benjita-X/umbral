-- ExpedicionHUD: la expedición de La Grieta en pantalla (ExpedicionService manda; esto solo muestra y pide).
--   · Junto al portal de la entrada, sin partida: elegir dificultad (Iniciación, Expedición, Desafío).
--   · Durante la partida: encuentro actual, enemigos que quedan, nivel con su barra de experiencia y tiempo.
--   · Tras ciertos encuentros: elegir una mejora entre tres (mientras eliges, no sale ningún golpe).
--   · Al vencer al Guardián: resumen (tiempo, caídas, nivel, mejoras) y repetir o cambiar de dificultad.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("CombatConfig"))

local ExpedicionHUD = {}

local balance = CombatConfig.Balance
local ACCENT = Color3.fromRGB(170, 130, 255)
local TEXT = Color3.fromRGB(235, 238, 248)
local DIM = Color3.fromRGB(150, 155, 172)
local PANEL = Color3.fromRGB(16, 18, 28)

local function corner(instance, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = instance
end

local function label(parent, text, size, position, color, font)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position or UDim2.new()
	l.Font = font or Enum.Font.GothamBold
	l.TextScaled = true
	l.TextColor3 = color or TEXT
	l.Text = text
	l.Parent = parent
	return l
end

local function button(parent, text, size, position)
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = position
	b.BackgroundColor3 = Color3.fromRGB(34, 30, 56)
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.TextColor3 = TEXT
	b.Text = text
	b.AutoButtonColor = true
	corner(b)
	local stroke = Instance.new("UIStroke")
	stroke.Color = ACCENT
	stroke.Transparency = 0.4
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = b
	b.Parent = parent
	return b
end

local function panel(gui, name, size)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = size
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.08
	frame.Visible = false
	corner(frame, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = ACCENT
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = frame
	frame.Parent = gui
	return frame
end

function ExpedicionHUD.Start(input, movement, camera)
	local player = Players.LocalPlayer
	local state = ReplicatedStorage:WaitForChild("Expedicion", 30)
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Expedicion", 30)
	if not state or not remote then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "UmbralExpedicion"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Un panel abierto bloquea las acciones de combate y suelta el ratón (como el menú)
	local open = {}
	local function setOpen(name, on)
		open[name] = if on then true else nil
		local any = next(open) ~= nil
		if input and input.SetBlocked then
			input.SetBlocked("expedicion", any)
		end
		if camera and camera.SetMouseFree then
			camera.SetMouseFree("expedicion", any)
		end
	end

	-- ---------- Marcador ----------
	local bar = Instance.new("Frame")
	bar.Name = "Marcador"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 44)
	bar.Size = UDim2.fromOffset(440, 46)
	bar.BackgroundColor3 = PANEL
	bar.BackgroundTransparency = 0.25
	bar.Visible = false
	corner(bar, 8)
	bar.Parent = gui
	local line1 = label(bar, "", UDim2.new(1, -16, 0, 20), UDim2.fromOffset(8, 3))
	local line2 = label(bar, "", UDim2.new(1, -16, 0, 14), UDim2.fromOffset(8, 24), DIM, Enum.Font.Gotham)
	local xpBack = Instance.new("Frame")
	xpBack.Position = UDim2.new(0, 8, 1, -5)
	xpBack.Size = UDim2.new(1, -16, 0, 3)
	xpBack.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
	xpBack.BorderSizePixel = 0
	xpBack.Parent = bar
	local xpFill = Instance.new("Frame")
	xpFill.Size = UDim2.fromScale(0, 1)
	xpFill.BackgroundColor3 = ACCENT
	xpFill.BorderSizePixel = 0
	xpFill.Parent = xpBack

	-- ---------- Dificultad (junto al portal) ----------
	local choose = panel(gui, "Dificultad", UDim2.fromOffset(460, 250))
	label(choose, "EXPEDICIÓN · LA GRIETA", UDim2.new(1, -20, 0, 26), UDim2.fromOffset(10, 10), ACCENT, Enum.Font.GothamBlack)
	label(choose, "Encuentros con enemigos que mueren de verdad, mejoras a elegir y el Guardián al final.", UDim2.new(1, -20, 0, 30), UDim2.fromOffset(10, 40), DIM, Enum.Font.Gotham)
	local order = { "Iniciacion", "Expedicion", "Desafio" }
	for i, id in ipairs(order) do
		local d = balance.Difficulties[id]
		local b = button(choose, d.label, UDim2.new(1, -20, 0, 34), UDim2.fromOffset(10, 76 + (i - 1) * 50))
		label(choose, d.desc, UDim2.new(1, -20, 0, 12), UDim2.fromOffset(10, 111 + (i - 1) * 50), DIM, Enum.Font.Gotham)
		b.Activated:Connect(function()
			remote:FireServer("empezar", id)
		end)
	end
	local dismissed = false
	local closeChoose = button(choose, "✕", UDim2.fromOffset(28, 28), UDim2.new(1, -36, 0, 8))
	closeChoose.Activated:Connect(function()
		dismissed = true
	end)

	-- ---------- Mejora (una de tres) ----------
	local upgrade = panel(gui, "Mejora", UDim2.fromOffset(620, 200))
	label(upgrade, "ELIGE UNA MEJORA", UDim2.new(1, -20, 0, 26), UDim2.fromOffset(10, 10), ACCENT, Enum.Font.GothamBlack)
	local cards = {}
	local function showUpgrades(options)
		for _, card in ipairs(cards) do
			card:Destroy()
		end
		table.clear(cards)
		local width = (600 - (#options - 1) * 10) / #options
		for i, option in ipairs(options) do
			local card = button(upgrade, "", UDim2.fromOffset(width, 140), UDim2.fromOffset(10 + (i - 1) * (width + 10), 46))
			card.TextTransparency = 1
			label(card, option.label, UDim2.new(1, -16, 0, 26), UDim2.fromOffset(8, 10), TEXT, Enum.Font.GothamBlack)
			local desc = label(card, option.desc, UDim2.new(1, -16, 0, 80), UDim2.fromOffset(8, 46), DIM, Enum.Font.Gotham)
			desc.TextWrapped = true
			card.Activated:Connect(function()
				remote:FireServer("mejora", option.id)
				upgrade.Visible = false
				setOpen("mejora", false)
			end)
			table.insert(cards, card)
		end
		upgrade.Visible = true
		setOpen("mejora", true)
	end

	-- ---------- Fin ----------
	local finish = panel(gui, "Fin", UDim2.fromOffset(440, 260))
	label(finish, "¡EXPEDICIÓN COMPLETADA!", UDim2.new(1, -20, 0, 30), UDim2.fromOffset(10, 12), ACCENT, Enum.Font.GothamBlack)
	local details = label(finish, "", UDim2.new(1, -20, 0, 110), UDim2.fromOffset(10, 50), TEXT, Enum.Font.Gotham)
	details.TextWrapped = true
	details.TextYAlignment = Enum.TextYAlignment.Top
	local again = button(finish, "Repetir", UDim2.new(0.5, -15, 0, 36), UDim2.new(0, 10, 1, -88))
	local other = button(finish, "Otra dificultad", UDim2.new(0.5, -15, 0, 36), UDim2.new(0.5, 5, 1, -88))
	local close = button(finish, "Cerrar", UDim2.new(1, -20, 0, 30), UDim2.new(0, 10, 1, -44))
	local function hideFinish()
		finish.Visible = false
		setOpen("fin", false)
	end
	again.Activated:Connect(function()
		remote:FireServer("repetir")
		hideFinish()
	end)
	other.Activated:Connect(function()
		remote:FireServer("abandonar")
		dismissed = false
		hideFinish()
	end)
	close.Activated:Connect(hideFinish)

	remote.OnClientEvent:Connect(function(kind, data)
		if kind == "mejoras" and type(data) == "table" and type(data.options) == "table" then
			showUpgrades(data.options)
		elseif kind == "fin" and type(data) == "table" then
			local d = balance.Difficulties[data.difficulty or ""]
			local upgrades = {}
			for id in string.gmatch(tostring(data.upgrades or ""), "[^,]+") do
				local spec = CombatConfig.Expedition.Upgrades[id]
				table.insert(upgrades, spec and spec.label or id)
			end
			local t = math.floor(data.time or 0)
			details.Text = string.format("Dificultad: %s\nTiempo: %d:%02d\nCaídas: %d\nNivel alcanzado: %d\nMejoras: %s",
				d and d.label or "?", t // 60, t % 60, data.deaths or 0, data.level or 1, if #upgrades > 0 then table.concat(upgrades, ", ") else "ninguna")
			again.Visible = not data.test
			other.Visible = not data.test
			finish.Visible = true
			setOpen("fin", true)
		end
	end)

	-- Mejora "Celeridad": los Pasos se recargan más rápido (el servidor aplica lo mismo)
	local function applyUpgrades()
		local list = "," .. tostring(player:GetAttribute("Mejoras") or "") .. ","
		if movement and movement.SetRechargeScale then
			movement.SetRechargeScale(if string.find(list, ",Celeridad,", 1, true) then 0.75 else 1)
		end
	end
	player:GetAttributeChangedSignal("Mejoras"):Connect(applyUpgrades)
	applyUpgrades()

	local portal = nil
	RunService.Heartbeat:Connect(function()
		local active = state:GetAttribute("Activa") == true
		-- Marcador
		bar.Visible = active
		if active then
			local d = balance.Difficulties[state:GetAttribute("Dificultad") or ""]
			local fase = state:GetAttribute("Fase")
			local encounter = state:GetAttribute("Encuentro") or 0
			local total = state:GetAttribute("Total") or 0
			local where = if fase == "combate" then string.format("%s · enemigos %d", tostring(state:GetAttribute("NombreEncuentro") or ""), state:GetAttribute("Restantes") or 0)
				elseif fase == "completada" then "¡completada!"
				else "explora y sigue adelante"
			line1.Text = string.format("EXPEDICIÓN · %s · %d/%d · %s", d and d.label or "?", encounter, total, where)
			local level = player:GetAttribute("Nivel") or 1
			local xp = player:GetAttribute("Experiencia") or 0
			local need = balance.Levels.XpPerLevel * level
			local elapsed = math.max(0, math.floor(Workspace:GetServerTimeNow() - (state:GetAttribute("Inicio") or Workspace:GetServerTimeNow())))
			line2.Text = string.format("Nivel %d · %d/%d de experiencia · %d:%02d", level, xp, need, elapsed // 60, elapsed % 60)
			xpFill.Size = UDim2.fromScale(math.clamp(xp / math.max(need, 1), 0, 1), 1)
		end
		-- Portal: sin partida (o terminada), cerca del círculo, se ofrece elegir dificultad
		portal = portal or Workspace:FindFirstChild("PortalExpedicion", true)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local near = portal ~= nil and root ~= nil and (root.Position - portal.Position).Magnitude <= 10
		local canStart = not active or state:GetAttribute("Fase") == "completada"
		local show = near and canStart and not dismissed and not finish.Visible
		if not near then
			dismissed = false
		end
		if choose.Visible ~= show then
			choose.Visible = show
			setOpen("dificultad", show)
		end
	end)
end

return ExpedicionHUD
