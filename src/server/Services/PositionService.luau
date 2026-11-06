-- PositionService: historial de posiciones con hora del servidor, para juzgar golpes y defensas en el
-- instante en que ocurrieron (compensación de latencia ACOTADA y validada).
--
-- Dos historiales:
--   · Observado: lo que el servidor ve de cada personaje (jugadores, muñecos, enemigos), cada cuadro.
--   · Informado: lo que cada cliente dice de sí mismo, con su hora sincronizada (20 por segundo, y en
--     cada golpe o defensa). Es más preciso en el tiempo, porque la física replicada llega con retraso.
--
-- Regla anti-trampa: una posición informada solo se acepta si (1) su hora es coherente con el ping del
-- jugador, (2) no implica moverse más rápido que lo posible, y (3) la física que observa el servidor la
-- CONFIRMA: el personaje pasa a menos de ConfirmRadius de ese punto dentro de ConfirmWindow (+ latencia).
-- Si no se confirma a tiempo, no cuenta. Así nadie gana nada informando posiciones falsas, y la espera
-- máxima está acotada.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("CombatConfig"))

local PositionService = {}

local net = CombatConfig.Network
local observed = setmetatable({}, { __mode = "k" }) -- [model] = { {t, cframe} }
local reported = {} -- [player] = { {t, position, look} }
local teleportAllowance = {} -- [player] = hora hasta la que un salto de posición es legítimo

local function now()
	return Workspace:GetServerTimeNow()
end

local function trim(list, t)
	while list[1] and t - list[1].t > net.HistorySeconds do
		table.remove(list, 1)
	end
end

local function flag(player, attribute)
	player:SetAttribute(attribute, (player:GetAttribute(attribute) or 0) + 1)
end

-- ---------- Historial observado ----------
function PositionService.Track(model)
	if not observed[model] then
		observed[model] = {}
	end
end

-- CFrame observada de un modelo en la hora `t` (interpolada); nil si no hay datos de ese momento
function PositionService.ObservedAt(model, t)
	local list = observed[model]
	if not list or #list == 0 then
		return nil
	end
	if t <= list[1].t then
		return list[1].cframe
	end
	for i = #list, 1, -1 do
		local a = list[i]
		if a.t <= t then
			local b = list[i + 1]
			if not b then
				return a.cframe
			end
			local alpha = (t - a.t) / math.max(b.t - a.t, 1e-4)
			return a.cframe:Lerp(b.cframe, alpha)
		end
	end
	return list[#list].cframe
end

-- ¿La física observada pasó cerca de `position` entre `from` y `to`?
local function observedNear(model, position, from, to)
	local list = observed[model]
	if not list then
		return false
	end
	for _, sample in ipairs(list) do
		if sample.t >= from and sample.t <= to and (sample.cframe.Position - position).Magnitude <= net.ConfirmRadius then
			return true
		end
	end
	return false
end

-- ---------- Historial informado ----------
local function oneWay(player)
	return math.min(player:GetNetworkPing() / 2, net.ConfirmWindow)
end

-- Hora coherente con el ping del jugador
function PositionService.ValidTime(player, t)
	local current = now()
	return type(t) == "number" and t == t and t <= current + 0.05 and t >= current - (player:GetNetworkPing() + net.ClockSlack + net.ConfirmWindow)
end

-- Guarda una muestra informada por el cliente (sin confirmar todavía). Devuelve false si es imposible.
function PositionService.Report(player, t, position, look)
	if typeof(position) ~= "Vector3" or not PositionService.ValidTime(player, t) then
		flag(player, "PosicionesRechazadas")
		return false
	end
	if typeof(look) ~= "Vector3" or look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	local list = reported[player]
	if not list then
		list = {}
		reported[player] = list
	end
	-- Velocidad posible respecto a la muestra anterior (salvo un teletransporte legítimo)
	local previous = nil
	for i = #list, 1, -1 do
		if list[i].t <= t then
			previous = list[i]
			break
		end
	end
	if previous and t > previous.t then
		local speed = (position - previous.position).Magnitude / (t - previous.t)
		local allowed = teleportAllowance[player] and now() <= teleportAllowance[player]
		if speed > net.MaxSpeed and not allowed and (position - previous.position).Magnitude > 3 then
			flag(player, "MovimientoSospechoso")
			return false
		end
	end
	-- Insertar en orden (los envíos rápidos pueden llegar desordenados)
	local sample = { t = t, position = position, look = Vector3.new(look.X, 0, look.Z) }
	local index = #list + 1
	while index > 1 and list[index - 1].t > t do
		index -= 1
	end
	table.insert(list, index, sample)
	trim(list, now())
	return true
end

-- Posición informada en la hora `t` (interpolada entre muestras cercanas); nil si no hay datos
local function reportedAt(player, t)
	local list = reported[player]
	if not list or #list == 0 then
		return nil
	end
	for i = #list, 1, -1 do
		local a = list[i]
		if a.t <= t then
			local b = list[i + 1]
			if b then
				local alpha = (t - a.t) / math.max(b.t - a.t, 1e-4)
				return { position = a.position:Lerp(b.position, alpha), look = if alpha < 0.5 then a.look else b.look }
			end
			if t - a.t <= 1.5 / net.ReportRate then
				return { position = a.position, look = a.look }
			end
			return nil
		end
	end
	return nil
end

-- Posición del jugador en la hora `t`, CONFIRMADA por la física observada. Espera (acotado) a que lleguen
-- los datos. Devuelve CFrame (o nil si no se pudo confirmar: no se le da ventaja a nadie).
function PositionService.ConfirmedAt(player, t)
	local character = player.Character
	if not character then
		return nil
	end
	local deadline = t + oneWay(player) + net.ConfirmWindow
	while true do
		local sample = reportedAt(player, t)
		if sample and observedNear(character, sample.position, t - 0.05, deadline) then
			local look = if sample.look.Magnitude > 0.01 then sample.look.Unit else Vector3.new(0, 0, -1)
			return CFrame.lookAt(sample.position, sample.position + look)
		end
		if now() >= deadline then
			return nil
		end
		RunService.Heartbeat:Wait()
	end
end

-- Para teletransportes legítimos (reaparecer, pruebas): durante un instante, un salto no es sospechoso
function PositionService.AllowTeleport(player, seconds)
	teleportAllowance[player] = now() + (seconds or 0.5)
	reported[player] = {}
end

function PositionService.Start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local stream = Instance.new("UnreliableRemoteEvent")
	stream.Name = "Posicion"
	stream.Parent = remotes
	stream.OnServerEvent:Connect(function(player, t, position, look)
		PositionService.Report(player, t, position, look)
	end)

	local function watchPlayer(player)
		player.CharacterAdded:Connect(function(character)
			PositionService.AllowTeleport(player, 1)
			PositionService.Track(character)
		end)
		if player.Character then
			PositionService.Track(player.Character)
		end
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		reported[player] = nil
		teleportAllowance[player] = nil
	end)

	-- Historial observado: cada cuadro
	RunService.Heartbeat:Connect(function()
		local t = now()
		for model, list in pairs(observed) do
			local root = model.Parent and model:FindFirstChild("HumanoidRootPart")
			if root then
				table.insert(list, { t = t, cframe = root.CFrame })
				trim(list, t)
			end
		end
	end)
end

return PositionService
