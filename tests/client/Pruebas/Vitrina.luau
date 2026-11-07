-- Vitrina (NO corre en la ronda normal; solo con  tools/ejecutar-pruebas.ps1 -Suites Vitrina):
-- lanza cada habilidad de cada Eco frente a un muñeco, una por una, para revisar A OJO cómo se ve.
-- Entre una y otra espera la tecla N (así quien revisa puede capturar cada efecto con calma). La cámara queda
-- fija de costado, mirando al jugador y al muñeco. Arriba dice qué habilidad viene.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

return function(ctx)
	local Config, Input = ctx.CombatConfig, ctx.Input
	local waitUntil = ctx.waitUntil
	local player = ctx.player
	local eco = Config.Eco
	local controllers = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Controllers")
	local Eco = require(controllers:WaitForChild("EcoController"))
	local okHud, SkillBarHUD = pcall(require, controllers:WaitForChild("SkillBarHUD"))
	local EcoEfectos = require(controllers:WaitForChild("EcoEfectos"))
	EcoEfectos.Lento = 4 -- cámara lenta: los efectos duran 4 veces más (solo aquí)
	Eco.SetAimMode("frente")

	local target = nil
	for _, model in ipairs(CollectionService:GetTagged("Objetivo")) do
		if model.Name == "Muneco2" then
			target = model
		end
	end
	if not target then
		ctx.skip("[Vitrina]", "falta el muñeco del Dojo")
		return
	end

	-- Cartel de arriba
	local gui = Instance.new("ScreenGui")
	gui.Name = "UmbralVitrina"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	local banner = Instance.new("TextLabel")
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 8)
	banner.Size = UDim2.fromOffset(620, 30)
	banner.BackgroundColor3 = Color3.fromRGB(10, 12, 20)
	banner.BackgroundTransparency = 0.25
	banner.TextColor3 = Color3.new(1, 1, 1)
	banner.Font = Enum.Font.GothamBold
	banner.TextScaled = true
	banner.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")

	local nextPressed = false
	local connection = UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.N then
			nextPressed = true
		end
	end)
	local function waitForNext()
		nextPressed = false
		waitUntil(function()
			return nextPressed
		end, 180)
	end

	local root = target:WaitForChild("HumanoidRootPart")
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	local stand = root.Position + look * 11
	local function placeAndFrame()
		ctx.remote:FireServer("reiniciar_eco")
		ctx.remote:FireServer("resonancia", 100)
		table.clear(Eco.State.cooldownEnd)
		table.clear(Eco.State.recast)
		Eco.State.swapUntil = 0
		ctx.waitForCharges()
		ctx.teleport(Vector3.new(stand.X, root.Position.Y + 0.5, stand.Z), -look)
		local camera = Workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		local side = Vector3.new(-look.Z, 0, look.X)
		local eye = stand + look * 11 + side * 3 + Vector3.new(0, 6, 0) -- detrás del jugador y un poco arriba
		camera.CFrame = CFrame.lookAt(eye, root.Position + Vector3.new(0, 1, 0))
		task.wait(0.3)
	end

	-- Lista: cada habilidad (y las variantes en el aire), con el relanzamiento automático donde lo hay
	local entries = {}
	for _, kitName in ipairs(eco.Order) do
		local kit = eco.Kits[kitName]
		for _, slot in ipairs(eco.SlotOrder) do
			table.insert(entries, { kit = kitName, slot = slot, skill = kit.slots[slot] })
			if kit.air and kit.air[slot] then
				table.insert(entries, { kit = kitName, slot = slot, skill = kit.air[slot], air = true })
			end
		end
	end
	local RECAST = { Levante = 0.45, PasoSombrio = 0.9 }

	for index, entry in ipairs(entries) do
		local kit = eco.Kits[entry.kit]
		if Eco.KitName() ~= entry.kit then
			Eco.Equip(entry.kit)
			waitUntil(function()
				return player:GetAttribute("Eco") == entry.kit
			end, 2)
		end
		placeAndFrame()
		local spec = eco.Skills[entry.skill]
		banner.TextColor3 = kit.color
		local cam = Workspace.CurrentCamera
		banner.Text = string.format("VITRINA %d/%d · %s · %s%s %s — N · efectos %d · %s (%d)", index, #entries, string.upper(entry.kit), entry.slot, if entry.air then " (aire)" else "", spec and spec.label or entry.skill, EcoEfectos.Creados, cam and cam:GetFullName() or "?", cam and #cam:GetChildren() or -1)
		if okHud and SkillBarHUD.ShowCard and (index == 1 or entries[index - 1].kit ~= entry.kit) then
			SkillBarHUD.ShowCard(true)
		end
		waitForNext()
		if entry.air then
			ctx.humanoid.Jump = true
			waitUntil(function()
				return not ctx.grounded() and ctx.root.AssemblyLinearVelocity.Y <= 4
			end, 1.5)
		end
		Input.Trigger("Habilidad" .. entry.slot)
		if RECAST[entry.skill] then
			task.wait(RECAST[entry.skill])
			Input.Trigger("Habilidad" .. entry.slot)
		end
		task.wait(0.6)
	end

	banner.Text = "VITRINA TERMINADA — pulsa N para cerrar"
	waitForNext()
	connection:Disconnect()
	EcoEfectos.Lento = 1
	gui:Destroy()
	Workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	ctx.record("[Vitrina] Recorrido de todas las habilidades", true, string.format("%d habilidades mostradas", #entries))
end
