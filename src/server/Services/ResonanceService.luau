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

-- Suma por un motivo de CombatConfig.Resonance.Gains. Límites anti-abuso:
--   · tope por segundo (MaxGainPerSecond)
--   · por rival (`source`): como máximo SourceCap cada SourceWindow segundos
--   · `repeatKey` repetido seguido contra el mismo rival: ×RepeatDecay cada vez
function ResonanceService.Gain(player, reason, source, repeatKey)
	local amount = settings.Gains[reason]
	if not amount then
		return 0
	end
	local i = info(player)
	local now = os.clock()

	if source then
		i.bySource = i.bySource or {}
		local s = i.bySource[source]
		if not s then
			s = { gains = {}, lastKey = nil, lastKeyTime = -math.huge, repeats = 0 }
			i.bySource[source] = s
		end
		if repeatKey then
			if repeatKey == s.lastKey and now - s.lastKeyTime <= settings.RepeatWindow then
				s.repeats += 1
			else
				s.repeats = 0
			end
			s.lastKey, s.lastKeyTime = repeatKey, now
			amount *= settings.RepeatDecay ^ s.repeats
		end
		while s.gains[1] and now - s.gains[1].t > settings.SourceWindow do
			table.remove(s.gains, 1)
		end
		local fromSource = 0
		for _, g in ipairs(s.gains) do
			fromSource += g.amount
		end
		amount = math.min(amount, settings.SourceCap - fromSource)
	end

	local gains = i.recentGains
	while gains[1] and now - gains[1].t > 1 do
		table.remove(gains, 1)
	end
	local recent = 0
	for _, g in ipairs(gains) do
		recent += g.amount
	end
	-- Las recompensas por vencer no pasan por el tope por segundo (ese tope frena el farmeo de golpes; vencer
	-- ya está limitado porque el enemigo tarda en levantarse)
	local isReward = reason == "VencerComun" or reason == "VencerGuardian"
	local granted = if isReward then amount else math.max(0, math.min(amount, settings.MaxGainPerSecond - recent))
	if source and granted > 0 then
		table.insert(i.bySource[source].gains, { t = now, amount = granted })
	end
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
			-- Autoridad del servidor: como mucho un Paso extra cada ExtraDashCooldown (con un pequeño margen
			-- por la variación de la red), y solo si alcanza la Resonancia
			local i = info(player)
			local now = os.clock()
			if now - (i.lastExtraDash or -math.huge) < settings.ExtraDashCooldown - 0.15 or not ResonanceService.Spend(player, settings.DashCost) then
				player:SetAttribute("GastosRechazados", (player:GetAttribute("GastosRechazados") or 0) + 1)
				return
			end
			i.lastExtraDash = now
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
