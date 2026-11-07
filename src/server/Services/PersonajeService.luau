-- PersonajeService: integridad del personaje del jugador.
--   · Red de seguridad: recuerda el último suelo firme que pisó cada jugador. Si cae más de
--     CombatConfig.Recovery.SafetyDrop por debajo de él (atravesó el suelo por un fallo de la física, se
--     salió del mapa...), vuelve a ese suelo sin morir. El foso del Abismo tiene su propio regreso
--     (GrietaService); esto es la red general para lo inesperado.
--   · Atascado: si el centro del cuerpo queda DENTRO de una pieza sólida (la física lo metió en una pared)
--     durante 1 s, también vuelve al último suelo firme.
--   · Apariencia: si al reaparecer el personaje llega sin su avatar (sin ropa ni accesorios), se le vuelve
--     a aplicar la apariencia de su cuenta. Roblox a veces no termina de cargarla al reaparecer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("CombatConfig"))
local PositionService = require(script.Parent:WaitForChild("PositionService"))

local PersonajeService = {}

local recovery = CombatConfig.Recovery
local CHECK_INTERVAL = 0.2
local lastSafe = {} -- [player] = CFrame sobre el último suelo firme
local nextCheck = {} -- [player] = os.clock()
local stuckSince = {} -- [player] = os.clock() desde que el cuerpo está metido en una pieza sólida
local STUCK_SECONDS = 1

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude
overlapParams.RespectCanCollide = true

-- ¿El centro del cuerpo está metido dentro de una pieza sólida (no un personaje)? Un radio chico: apoyarse
-- en una pared no cuenta, solo estar adentro.
local function insideSolid(character, root)
	overlapParams.FilterDescendantsInstances = { character }
	for _, part in ipairs(Workspace:GetPartBoundsInRadius(root.Position, 0.15, overlapParams)) do
		local model = part:FindFirstAncestorOfClass("Model")
		if not (model and model:FindFirstChildOfClass("Humanoid")) then
			return true
		end
	end
	return false
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true

-- ¿Está parado en un suelo firme? Devuelve el punto de apoyo
local function firmGround(character, root, humanoid)
	groundParams.FilterDescendantsInstances = { character }
	local reach = humanoid.HipHeight + root.Size.Y / 2 + 1.5
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), groundParams)
	if not hit or hit.Normal.Y < 0.7 then
		return nil
	end
	local model = hit.Instance:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then
		return nil -- parado sobre otro personaje: no es suelo firme
	end
	if hit.Instance.Name == "AbismoFoso" then
		return nil -- el fondo del foso no es un lugar seguro
	end
	return hit.Position
end

local function rescue(player, character, root)
	local target = lastSafe[player]
	if not target then
		return
	end
	PositionService.AllowTeleport(player, 1)
	root.AssemblyLinearVelocity = Vector3.zero
	character:PivotTo(target)
	player:SetAttribute("Rescates", (player:GetAttribute("Rescates") or 0) + 1)
	if RunService:IsStudio() then
		warn(string.format("[UMBRAL] Red de seguridad: %s cayó fuera del suelo y volvió a (%.0f, %.0f, %.0f)", player.Name, target.X, target.Y, target.Z))
	end
end

-- Apariencia: ¿llegó sin avatar? (ni ropa ni accesorios)
local function looksBare(character)
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") or child:IsA("Shirt") or child:IsA("Pants") or child:IsA("ShirtGraphic") then
			return false
		end
	end
	return true
end

local function guardAppearance(player, character)
	if player.UserId <= 0 then
		return -- jugadores de prueba de Studio no tienen avatar
	end
	-- Esperar a que Roblox termine de cargar la apariencia (con tope)
	local loaded = player:HasAppearanceLoaded()
	local start = os.clock()
	while not loaded and os.clock() - start < 8 and character.Parent do
		task.wait(0.25)
		loaded = player:HasAppearanceLoaded()
	end
	task.wait(0.5)
	if not character.Parent or player.Character ~= character or not looksBare(character) then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local ok, description = pcall(Players.GetHumanoidDescriptionFromUserId, Players, player.UserId)
	if ok and description then
		local applied = pcall(humanoid.ApplyDescription, humanoid, description)
		if RunService:IsStudio() then
			warn(string.format("[UMBRAL] %s reapareció sin avatar: apariencia reaplicada (%s)", player.Name, tostring(applied)))
		end
	end
end

function PersonajeService.Start()
	local function watch(player)
		player.CharacterAdded:Connect(function(character)
			lastSafe[player] = nil
			task.spawn(guardAppearance, player, character)
		end)
		if player.Character then
			task.spawn(guardAppearance, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastSafe[player] = nil
		nextCheck[player] = nil
		stuckSince[player] = nil
	end)

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if humanoid and root and humanoid.Health > 0 then
				local safe = lastSafe[player]
				-- Cayó demasiado por debajo del último suelo firme: vuelve a él
				if safe and root.Position.Y < safe.Position.Y - recovery.SafetyDrop then
					rescue(player, character, root)
				elseif now >= (nextCheck[player] or 0) then
					nextCheck[player] = now + CHECK_INTERVAL
					-- Atascado dentro de una pared: tras STUCK_SECONDS, de vuelta al último suelo firme
					if insideSolid(character, root) then
						stuckSince[player] = stuckSince[player] or now
						if now - stuckSince[player] >= STUCK_SECONDS then
							stuckSince[player] = nil
							rescue(player, character, root)
							continue
						end
					else
						stuckSince[player] = nil
					end
					local ground = firmGround(character, root, humanoid)
					if ground then
						local standing = humanoid.HipHeight + root.Size.Y / 2 + 0.3
						local look = root.CFrame.LookVector
						local flatLook = Vector3.new(look.X, 0, look.Z)
						flatLook = if flatLook.Magnitude > 0.01 then flatLook.Unit else Vector3.new(0, 0, -1)
						local position = ground + Vector3.new(0, standing, 0)
						lastSafe[player] = CFrame.lookAt(position, position + flatLook)
					end
				end
			end
		end
	end)
end

return PersonajeService
