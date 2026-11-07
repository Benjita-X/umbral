-- DefenseService: estado defensivo de cada jugador visto por el servidor.
--
-- El cliente informa CUÁNDO pulsó Defender, cuándo la soltó y cuándo dio un Paso, con la hora del
-- servidor según su reloj sincronizado (workspace:GetServerTimeNow()). El servidor acepta esa hora solo
-- si es coherente con el ping medido del jugador: así un desvío que en su pantalla fue perfecto cuenta
-- como perfecto aunque haya lag, y nadie puede inventarse tiempos para desviar "hacia atrás".
--
-- También guarda la postura (atributo "Postura"), el aturdimiento ("AturdidoHasta") y la ventana de
-- Contraataque ("ContraataqueHasta"), en hora del servidor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("CombatConfig"))

local DefenseService = {}

local defense = CombatConfig.Defense
local KEEP_SECONDS = 2
local PositionService = nil -- lo inyecta ServerBootstrap
local records = {} -- [player] = { presses = { {t, valid} }, lastPress, guardDown, guardUp, pasos = { {t, dir} }, postureActivity, stunStart }

local function now()
	return Workspace:GetServerTimeNow()
end

local function recordFor(player)
	local r = records[player]
	if not r then
		r = { presses = {}, lastPress = -math.huge, guardDown = nil, guardUp = nil, pasos = {}, postureActivity = -math.huge, stunStart = -math.huge }
		records[player] = r
	end
	return r
end

local function prune(list, t)
	while list[1] and t - list[1].t > KEEP_SECONDS do
		table.remove(list, 1)
	end
end

-- Latencia de ida (aprox. la mitad del ping), con el MISMO tope que el historial de posiciones
function DefenseService.OneWay(player)
	return math.min(player:GetNetworkPing() / 2, CombatConfig.Network.MaxRewind / 2)
end

local MAX_EVENTS_PER_SECOND = 30 -- defensas por segundo y jugador (machacar a mano no llega a 15)

-- La hora que manda el cliente solo vale si es coherente: ni futura ni más vieja que el retroceso
-- acotado (min(ping, MaxRewind)) más un margen. Una hora inválida no se usa: se toma la actual.
local function validTime(player, t)
	local current = now()
	if type(t) ~= "number" or t ~= t then
		return false, current
	end
	local maxAge = math.min(player:GetNetworkPing(), CombatConfig.Network.MaxRewind) + defense.TimestampSlack
	if t > current + 0.05 or t < current - maxAge then
		return false, current
	end
	return true, t
end

local function onDefense(player, action, t, dir, position, look)
	local r = recordFor(player)
	local clock = os.clock()
	if clock - (r.rateStart or -math.huge) >= 1 then
		r.rateStart, r.rateCount = clock, 0
	end
	r.rateCount += 1
	if r.rateCount > MAX_EVENTS_PER_SECOND then
		player:SetAttribute("DefensasExcedidas", (player:GetAttribute("DefensasExcedidas") or 0) + 1)
		return
	end
	local ok, time = validTime(player, t)
	if not ok then
		-- Hora imposible (futura o demasiado vieja): se cuenta y se usa la hora actual, sin ventaja
		player:SetAttribute("DefensasRechazadas", (player:GetAttribute("DefensasRechazadas") or 0) + 1)
	elseif PositionService then
		PositionService.Report(player, time, position, look) -- dónde estaba en ese instante
	end
	if action == "defender_inicio" then
		-- Duplicado exacto (reenvío): se ignora
		for _, press in ipairs(r.presses) do
			if press.t == time then
				return
			end
		end
		-- Solo abre ventana de desvío si pasó el enfriamiento desde la pulsación anterior. Si el mensaje
		-- llega desordenado (más viejo que la última pulsación), no abre ventana ni hace retroceder el
		-- reloj del enfriamiento.
		local valid = time - r.lastPress >= defense.DeflectCooldown
		table.insert(r.presses, { t = time, valid = valid, consumed = false })
		table.sort(r.presses, function(a, b)
			return a.t < b.t
		end)
		r.lastPress = math.max(r.lastPress, time)
		-- El estado de guardia solo avanza con eventos más nuevos que el último (un inicio atrasado no
		-- reabre una guardia ya soltada) — hallazgo #4 de Codex
		if time >= (r.guardEventTime or -math.huge) then
			r.guardEventTime = time
			r.guardDown = time
			r.guardUp = nil
		end
		r.postureActivity = math.max(r.postureActivity, time)
		prune(r.presses, time)
	elseif action == "defender_fin" then
		if time >= (r.guardEventTime or -math.huge) then
			r.guardEventTime = time
			r.guardUp = time
		end
		r.postureActivity = math.max(r.postureActivity, time)
		-- La pulsación que se suelta es la más nueva ANTERIOR a esta hora
		for i = #r.presses, 1, -1 do
			local press = r.presses[i]
			if press.t <= time then
				if press.released == nil then
					press.released = time
				end
				break
			end
		end
	elseif action == "paso" then
		local flatDir = if typeof(dir) == "Vector3" then Vector3.new(dir.X, 0, dir.Z) else Vector3.zero
		if flatDir.Magnitude > 0.1 then
			table.insert(r.pasos, { t = time, dir = flatDir.Unit })
			prune(r.pasos, time)
		end
	end
end

-- "perfecto", "normal" o nil, para un impacto que el jugador vio en el instante `perceived`.
-- La pulsación que desvía queda "usada" (no cuenta como desvío fallido).
function DefenseService.FindDeflect(player, perceived)
	local r = recordFor(player)
	local best, bestPress = nil, nil
	for _, press in ipairs(r.presses) do
		local before = perceived - press.t
		-- Una pulsación ya usada no desvía otro ataque (dos enemigos a la vez) — hallazgo #3 de Codex
		if press.valid and not press.consumed and before >= -0.03 and before <= defense.DeflectWindow then
			local kind = if before <= defense.PerfectWindow then "perfecto" else "normal"
			if kind == "perfecto" or not best then
				best, bestPress = kind, press
			end
		end
	end
	return best, bestPress
end

function DefenseService.Consume(press)
	if press then
		press.consumed = true
	end
end

-- ¿Expuesto por un desvío fallido? Una pulsación SUELTA (no mantenida) cuya ventana terminó sin desviar
-- nada deja al jugador vulnerable WhiffPenalty segundos: sin guardia y con más daño.
function DefenseService.IsExposed(player, perceived)
	for _, press in ipairs(recordFor(player).presses) do
		local windowEnd = press.t + defense.DeflectWindow
		local tapped = press.released ~= nil and press.released <= windowEnd
		if tapped and not press.consumed and perceived > windowEnd and perceived <= windowEnd + defense.WhiffPenalty then
			return true
		end
	end
	return false
end

-- Inyecta el servicio de posiciones (evita dependencias circulares al arrancar)
function DefenseService.SetPositionService(service)
	PositionService = service
end

-- Primer Paso dado entre `from` y `to` (hora del servidor)
function DefenseService.FindPaso(player, from, to)
	for _, paso in ipairs(recordFor(player).pasos) do
		if paso.t >= from and paso.t <= to then
			return paso
		end
	end
	return nil
end

function DefenseService.IsGuarding(player, at)
	local r = recordFor(player)
	return r.guardDown ~= nil and r.guardDown <= at and (r.guardUp == nil or r.guardUp > at)
end

-- Suma postura; devuelve true si se rompió la guardia (la postura vuelve a 0)
function DefenseService.AddPosture(player, amount, canBreak)
	local r = recordFor(player)
	r.postureActivity = now()
	local posture = (player:GetAttribute("Postura") or 0) + amount
	if canBreak ~= false and posture >= defense.PostureMax then
		player:SetAttribute("Postura", 0)
		return true
	end
	player:SetAttribute("Postura", math.min(posture, defense.PostureMax - 1))
	return false
end

-- Aturde al jugador y devuelve la duración REAL aplicada (0 si está en Aguante), para que el cliente use
-- la misma. Anticadena: cada aturdimiento seguido dura menos y al tercero llega el Aguante.
function DefenseService.Stun(player, duration)
	local r = recordFor(player)
	local t = now()
	if r.aguanteUntil and t < r.aguanteUntil then
		return 0
	end
	r.recentStuns = r.recentStuns or {}
	local window = defense.StunChainWindow
	while r.recentStuns[1] and t - r.recentStuns[1] > window do
		table.remove(r.recentStuns, 1)
	end
	local applied = duration * defense.StunChainFactor ^ #r.recentStuns
	table.insert(r.recentStuns, t)
	r.stunStart = t
	player:SetAttribute("AturdidoHasta", t + applied)
	if #r.recentStuns >= defense.StunChainMax then
		r.recentStuns = {}
		r.aguanteUntil = t + applied + defense.AguanteTime
		player:SetAttribute("AguanteHasta", r.aguanteUntil)
	end
	return applied
end

-- ¿Aturdido? `grace` evita castigar acciones que el cliente hizo antes de enterarse del aturdimiento
function DefenseService.IsStunned(player, grace)
	local untilTime = player:GetAttribute("AturdidoHasta")
	local t = now()
	if not untilTime or t >= untilTime then
		return false
	end
	return t - recordFor(player).stunStart > (grace or 0)
end

-- Borra la cadena de aturdimientos y el Aguante (reaparecer, pruebas)
function DefenseService.ClearStunChain(player)
	local r = recordFor(player)
	r.recentStuns = {}
	r.aguanteUntil = nil
	player:SetAttribute("AguanteHasta", nil)
end

-- Abre la ventana de Contraataque (el cliente la recibe con la latencia de ida ya sumada)
function DefenseService.OpenCounter(player)
	player:SetAttribute("ContraataqueHasta", now() + defense.CounterWindow + DefenseService.OneWay(player))
end

function DefenseService.Start()
	local remote = Instance.new("RemoteEvent")
	remote.Name = "Defensa"
	remote.Parent = ReplicatedStorage:WaitForChild("Remotes")
	remote.OnServerEvent:Connect(function(player, action, t, dir, position, look)
		if action == "defender_inicio" or action == "defender_fin" or action == "paso" then
			onDefense(player, action, t, dir, position, look)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		records[player] = nil
	end)

	-- La postura se recupera si no estás en guardia ni recibiendo golpes
	RunService.Heartbeat:Connect(function(dt)
		local t = now()
		for _, player in ipairs(Players:GetPlayers()) do
			local posture = player:GetAttribute("Postura") or 0
			if posture > 0 then
				local r = recordFor(player)
				local guarding = r.guardDown ~= nil and r.guardUp == nil
				if not guarding and t - r.postureActivity > defense.PostureRegenDelay then
					player:SetAttribute("Postura", math.max(0, posture - defense.PostureRegenPerSecond * dt))
				end
			end
		end
	end)
end

return DefenseService
