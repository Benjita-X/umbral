-- WeaponService: el arma de cada jugador (EXPERIMENTAL): Puños o Espada (tecla Q).
--   · Atributo "Arma" en el jugador ("Punos" o "Espada"): DamageService lo usa para validar que cada golpe sea
--     del arma que lleva.
--   · La espada es un modelo simple de piezas soldado a la mano derecha (lo ven todos). La hoja sale del puño,
--     perpendicular al antebrazo; las animaciones de espada giran la muñeca para orientarla.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("CombatConfig"))

local WeaponService = {}

local weapons = CombatConfig.Weapons
local SWORD_PARTS = { "UmbralEspadaMango", "UmbralEspadaGuarda", "UmbralEspadaHoja", "UmbralEspadaFilo" }

local function clearSword(character)
	for _, name in ipairs(SWORD_PARTS) do
		local part = character:FindFirstChild(name)
		if part then
			part:Destroy()
		end
	end
end

local function makePart(name, size, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.Metal
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.Anchored = false
	return part
end

local function weld(hand, part, offset, character)
	part.CFrame = hand.CFrame * offset
	local w = Instance.new("Weld")
	w.Part0 = hand
	w.Part1 = part
	w.C0 = offset
	w.Parent = part
	part.Parent = character
end

local function buildSword(character)
	clearSword(character)
	local hand = character:FindFirstChild("RightHand")
	if not hand then
		return
	end
	-- La hoja va a lo largo del eje -Z de la mano (sale del puño hacia adelante con el brazo colgando)
	weld(hand, makePart("UmbralEspadaMango", Vector3.new(0.26, 0.26, 1.1), Color3.fromRGB(70, 46, 32), Enum.Material.Wood), CFrame.new(0, -0.1, 0.1), character)
	weld(hand, makePart("UmbralEspadaGuarda", Vector3.new(0.3, 1.25, 0.16), Color3.fromRGB(196, 164, 92)), CFrame.new(0, -0.1, -0.5), character)
	weld(hand, makePart("UmbralEspadaHoja", Vector3.new(0.14, 0.5, 4.2), Color3.fromRGB(205, 214, 230)), CFrame.new(0, -0.1, -2.65), character)
	weld(hand, makePart("UmbralEspadaFilo", Vector3.new(0.06, 0.12, 4), Color3.fromRGB(150, 225, 255), Enum.Material.Neon), CFrame.new(0, 0.12, -2.7), character)
end

local function apply(player)
	local character = player.Character
	if not character then
		return
	end
	if player:GetAttribute("Arma") == "Espada" then
		buildSword(character)
	else
		clearSword(character)
	end
end

function WeaponService.Equip(player, name)
	if type(name) ~= "string" or not weapons[name] or name == "Order" then
		return false
	end
	player:SetAttribute("Arma", name)
	apply(player)
	return true
end

function WeaponService.Start()
	local remote = Instance.new("RemoteEvent")
	remote.Name = "ElegirArma"
	remote.Parent = ReplicatedStorage:WaitForChild("Remotes")
	local last = {}
	remote.OnServerEvent:Connect(function(player, name)
		local clock = os.clock()
		if clock - (last[player] or -math.huge) < weapons.SwitchTime * 0.8 then
			return
		end
		last[player] = clock
		WeaponService.Equip(player, name)
	end)
	-- Gancho: el cliente dice A QUÉ se enganchó (un punto "PuntoGancho" del mapa o un enemigo "Objetivo") y desde
	-- dónde. El servidor comprueba la hora, el enfriamiento, que el enganche exista, el alcance y la línea de visión,
	-- y solo entonces anota el gancho (DefenseService.RecordGrapple). Llegar a un ENEMIGO enganchado habilita el
	-- golpe tras el Paso (DamageService lo juzga contra ese registro).
	local hookRemote = Instance.new("RemoteEvent")
	hookRemote.Name = "Gancho"
	hookRemote.Parent = ReplicatedStorage:WaitForChild("Remotes")
	local PositionService = require(script.Parent:WaitForChild("PositionService"))
	local DefenseService = require(script.Parent:WaitForChild("DefenseService"))
	local DamageService = require(script.Parent:WaitForChild("DamageService"))
	local grapple = CombatConfig.Weapons.Grapple
	local lastHook = {}
	local function refuseHook(player, reason)
		player:SetAttribute("GanchoRechazado", reason)
		player:SetAttribute("GanchosRechazados", (player:GetAttribute("GanchosRechazados") or 0) + 1)
	end
	hookRemote.OnServerEvent:Connect(function(player, t, target, position, look)
		local clock = os.clock()
		if clock - (lastHook[player] or -math.huge) < grapple.Cooldown * 0.8 then
			return refuseHook(player, "gancho en enfriamiento")
		end
		if not PositionService.ValidTime(player, t) then
			return refuseHook(player, "hora inválida")
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or typeof(target) ~= "Instance" or not target:IsDescendantOf(workspace) then
			return refuseHook(player, "enganche inválido")
		end
		local enemy = target:IsA("Model") and target:HasTag("Objetivo") and target ~= character
		local anchor = target:IsA("BasePart") and target.Name == "PuntoGancho"
		if not enemy and not anchor then
			return refuseHook(player, "enganche inválido")
		end
		local targetPosition
		if enemy then
			local humanoid = target:FindFirstChildOfClass("Humanoid")
			local targetRootPart = target:FindFirstChild("HumanoidRootPart")
			if not humanoid or humanoid.Health <= 0 or not targetRootPart then
				return refuseHook(player, "enemigo vencido")
			end
			local seen = PositionService.ObservedAt(target, t - PositionService.OneWay(player))
			targetPosition = if seen then seen.Position else targetRootPart.Position
		else
			targetPosition = target.Position
		end
		-- Desde dónde: lo que informa, si es coherente con lo observado (a pocos studs); si no, lo observado
		local seenSelf = PositionService.ObservedAt(character, t)
		local from = if seenSelf then seenSelf.Position else root.Position
		if typeof(position) == "Vector3" and ((position - from).Magnitude <= 10 or (position - root.Position).Magnitude <= 10) then
			PositionService.Report(player, t, position, look)
			from = position
		end
		local range = if enemy then grapple.EnemyRange else grapple.PointRange
		if (targetPosition - from).Magnitude > range + 6 then
			return refuseHook(player, string.format("gancho fuera de alcance (%.0f studs)", (targetPosition - from).Magnitude))
		end
		if DamageService.SolidBetween(character, target, from + Vector3.new(0, 0.5, 0), targetPosition) then
			return refuseHook(player, "gancho a través de una pared")
		end
		lastHook[player] = clock
		DefenseService.RecordGrapple(player, t, target, enemy, from)
		player:SetAttribute("GanchoHora", t)
	end)

	local function setup(player)
		if not weapons[player:GetAttribute("Arma") or ""] then
			player:SetAttribute("Arma", "Punos")
		end
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("RightHand", 10)
			apply(player)
		end)
		if player.Character then
			task.spawn(apply, player)
		end
	end
	Players.PlayerAdded:Connect(setup)
	for _, player in ipairs(Players:GetPlayers()) do
		setup(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		last[player] = nil
		lastHook[player] = nil
	end)
end

return WeaponService
