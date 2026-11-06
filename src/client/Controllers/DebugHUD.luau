-- DebugHUD: panel provisional para medir el movimiento mientras se prueba.
-- Se desactiva con MovementConfig.DebugHUD = false.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local DebugHUD = {}

function DebugHUD.Start(movement, combat)
	local touch = UserInputService.TouchEnabled

	local gui = Instance.new("ScreenGui")
	gui.Name = "UmbralDepuracion"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10

	local label = Instance.new("TextLabel")
	label.Name = "Datos"
	label.Position = UDim2.fromOffset(12, 12)
	label.Size = if touch then UDim2.fromOffset(250, 165) else UDim2.fromOffset(380, 220)
	label.BackgroundColor3 = Color3.fromRGB(10, 12, 20)
	label.BackgroundTransparency = 0.3
	label.TextColor3 = Color3.fromRGB(230, 236, 255)
	label.Font = Enum.Font.Code
	label.TextSize = if touch then 11 else 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Text = ""

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 6)
	padding.Parent = label

	label.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local controls = if touch
		then "ATACAR (mantener: fuerte) · DEFENDER · PASO · Saltar x2"
		else "Clic: atacar (mantener: fuerte) · F: guardia · Shift: paso · Espacio x2"

	local fps, peak, accumulator = 60, 0, 0
	RunService.RenderStepped:Connect(function(dt)
		local s = movement.State
		fps += ((1 / math.max(dt, 1e-4)) - fps) * 0.1
		peak = math.max(s.speed, peak - 25 * dt)
		accumulator += dt
		if accumulator < 0.1 then
			return
		end
		accumulator = 0
		label.Text = string.format(
			"UMBRAL · Laboratorio de movimiento\n"
				.. "Velocidad   %5.1f  (pico %5.1f)\n"
				.. "Sprint      %s\n"
				.. "Pasos       %d/%d   aire: salto %d · paso %d\n"
				.. "Último paso %.1f studs\n"
				.. "Estado      %s\n"
				.. "Combate     %s\n"
				.. "Resonancia  %d · postura %d\n"
				.. "FPS         %d\n"
				.. "%s",
			s.speed,
			peak,
			if s.dashing then "PASO" elseif s.sprinting then "sí" else "no",
			s.charges,
			movement.MaxCharges,
			s.airJumpsLeft,
			s.airDashesLeft,
			s.lastDashDistance,
			s.humanoidState,
			if combat
				then string.format(
					"%s%s · combo %d",
					combat.State.mode,
					if combat.State.attack then " (" .. combat.State.attack.name .. ", " .. combat.State.attack.phase .. ")" else "",
					combat.State.comboHits
				)
				else "-",
			math.floor((Players.LocalPlayer:GetAttribute("Resonancia") or 0) + 0.5),
			math.floor((Players.LocalPlayer:GetAttribute("Postura") or 0) + 0.5),
			math.floor(fps + 0.5),
			controls
		)
	end)
end

return DebugHUD
