-- ResonanceService: la Resonancia de cada jugador (0-100), guardada en el atributo "Resonancia".
-- Se gana jugando bien (golpes, desvíos, esquivas, Contrapaso), con un tope por segundo para que no se
-- pueda "farmear", y se apaga sola fuera de combate. Fase 3: se gasta en un Paso extra sin cargas.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("CombatConfig"))

local ResonanceService = {}

local settings = CombatConfig.Resonance
local activity = {} -- [player] = { lastCombat, recentGains = { { t, amount } } }

local function info(player)
	local i = activity[player]
	if not i then
		i = { lastCombat = -math.huge, recentGains = {} }
		activity[player] = i
	end
	return i
end

function ResonanceService.Get(player)
	return player:GetAttribute("Resonancia") or 0
end

local function set(player, value)
	player:SetAttribute("Resonancia", math.clamp(value, 0, settings.Max))
end

-- Marca actividad de combate (detiene el apagado)
function ResonanceService.Touch(player)
	info(player).lastCombat = os.clock()
end

-- Suma por un motivo de CombatConfig.Resonance.Gains (respeta el tope por segundo)
function ResonanceService.Gain(player, reason)
	local amount = settings.Gains[reason]
	if not amount then
		return 0
	end
	local i = info(player)
	local now = os.clock()
	local gains = i.recentGains
	while gains[1] and now - gains[1].t > 1 do
		table.remove(gains, 1)
	end
	local recent = 0
	for _, g in ipairs(gains) do
		recent += g.amount
	end
	local granted = math.max(0, math.min(amount, settings.MaxGainPerSecond - recent))
	if granted > 0 then
		table.insert(gains, { t = now, amount = granted })
		set(player, ResonanceService.Get(player) + granted)
	end
	i.lastCombat = now
	return granted
end

-- Intenta gastar; devuelve true si había suficiente
function ResonanceService.Spend(player, amount)
	local current = ResonanceService.Get(player)
	if current < amount then
		return false
	end
	set(player, current - amount)
	info(player).lastCombat = os.clock()
	return true
end

function ResonanceService.Start()
	local spendRemote = Instance.new("RemoteEvent")
	spendRemote.Name = "GastarResonancia"
	spendRemote.Parent = ReplicatedStorage:WaitForChild("Remotes")
	spendRemote.OnServerEvent:Connect(function(player, kind)
		if kind == "paso" then
			if not ResonanceService.Spend(player, settings.DashCost) then
				player:SetAttribute("GastosRechazados", (player:GetAttribute("GastosRechazados") or 0) + 1)
			end
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		set(player, 0)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("Resonancia") == nil then
			set(player, 0)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		activity[player] = nil
	end)

	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			local value = ResonanceService.Get(player)
			if value > 0 and now - info(player).lastCombat > settings.DecayDelay then
				set(player, value - settings.DecayPerSecond * dt)
			end
		end
	end)
end

return ResonanceService
