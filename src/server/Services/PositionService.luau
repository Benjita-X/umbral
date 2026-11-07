-- PositionService: historial de posiciones con hora del servidor, para juzgar golpes y defensas en el
-- instante en que ocurrieron (compensación de latencia ACOTADA y validada).
--
-- Dos historiales:
--   · Observado: lo que el servidor ve de cada personaje (jugadores, muñecos, enemigos), cada cuadro.
--   · Informado: lo que cada cliente dice de sí mismo, con su hora sincronizada (20 por segundo, y en
--     cada golpe o defensa). Es más preciso en el tiempo, porque la física replicada llega con retraso.
--
-- LÍMITE DE CONFIANZA (importante): en Roblox el cliente es dueño de la física de su personaje (network
-- ownership), así que la posición "observada" de un JUGADOR también la produce su cliente. Confirmar lo
-- informado contra lo observado demuestra COHERENCIA (no se puede informar un punto por el que el
-- personaje nunca pasó), no legitimidad. La legitimidad del movimiento se vigila aparte, sobre lo
-- observado: velocidades imposibles (ObservedSpeedCheck). Para muñecos y enemigos (dueño: el servidor)
-- lo observado sí es la verdad.
--
-- Reglas de una posición informada:
--   1. Hora coherente: no futura y no más vieja que min(ping, MaxRewind) + ClockSlack. El retroceso está
--      ACOTADO: una conexión muy lenta (o un "lag switch") no compra más ventana.
--   2. Velocidad posible respecto a sus vecinas en el tiempo (anterior y siguiente), salvo teletransporte
--      autorizado por el servidor (reaparecer, pruebas).
--   3. Confirmación: la trayectoria observada pasa a menos de ConfirmRadius + velocidad × ConfirmSpeedFactor
--      del punto informado (distancia a SEGMENTOS entre muestras, no a puntos sueltos). Quieto, el margen
--      es ConfirmRadius (2,25 studs); durante un Paso crece lo justo. Así nadie gana alcance informando un punto
--      desplazado.
--   4. Tasa máxima de informes por jugador; duplicados (misma hora) se ignoran.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("CombatConfig"))

local PositionService = {}

local net = CombatConfig.Network
local observed = setmetatable({}, { __mode = "k" }) -- [model] = { {t, cframe} } (orden temporal)
local reported = {} -- [player] = { {t, position, look} } (orden temporal)
local teleportAllowance = {} -- [player] = hora hasta la que un salto de posición es legítimo
local rate = {} -- [player] = { windowStart, count }
local teleportCut = {} -- [player] = hora del último teletransporte: lo informado antes ya no vale

local function now()
	return Workspace:GetServerTimeNow()
end

local function trim(list, t)
	-- Las listas son cortas (HistorySeconds × 60 como mucho); quitar del frente es barato.
	while list[1] and t - list[1].t > net.HistorySeconds do
		table.remove(list, 1)
	end
end

local function flag(player, attribute)
	player:SetAttribute(attribute, (player:GetAttribute(attribute) or 0) + 1)
end

local function flatDistance(a, b)
	local d = a - b
	return Vector3.new(d.X, 0, d.Z).Magnitude
end

-- Retroceso máximo aceptado para este jugador (latencia de ida y vuelta, con tope)
function PositionService.Rewind(player)
	return math.min(player:GetNetworkPing(), net.MaxRewind)
end

-- Latencia de ida (aprox. la mitad del ping), con tope
function PositionService.OneWay(player)
	return math.min(player:GetNetworkPing() / 2, net.MaxRewind / 2)
end

function PositionService.Teleporting(player)
	local untilTime = teleportAllowance[player]
	return untilTime ~= nil and now() <= untilTime
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

-- Distancia de un punto a un segmento
local function segmentDistance(p, a, b)
	local ab = b - a
	local lengthSq = ab:Dot(ab)
	if lengthSq < 1e-6 then
		return (p - a).Magnitude
	end
	local alpha = math.clamp((p - a):Dot(ab) / lengthSq, 0, 1)
	return (p - (a + ab * alpha)).Magnitude
end

-- ¿La trayectoria observada pasó cerca de `position` entre `from` y `to`? El margen depende de la
-- velocidad observada en ese tramo (quieto: ConfirmRadius; en un Paso: un poco más).
local function observedNear(model, position, from, to)
	local list = observed[model]
	if not list then
		return false
	end
	for i = 1, #list - 1 do
		local a, b = list[i], list[i + 1]
		if b.t >= from and a.t <= to then
			local pa, pb = a.cframe.Position, b.cframe.Position
			local speed = (pb - pa).Magnitude / math.max(b.t - a.t, 1e-3)
			local radius = net.ConfirmRadius + math.min(speed, net.MaxSpeed) * net.ConfirmSpeedFactor
			if segmentDistance(position, pa, pb) <= radius then
				return true
			end
		end
	end
	-- Una sola muestra en la ventana (personaje quieto recién registrado)
	local last = list[#list]
	return last ~= nil and last.t >= from and last.t <= to and (last.cframe.Position - position).Magnitude <= net.ConfirmRadius
end

-- ---------- Historial informado ----------

-- Hora coherente: no futura, y no más vieja que el retroceso acotado
function PositionService.ValidTime(player, t)
	local current = now()
	return type(t) == "number" and t == t and t <= current + 0.05 and t >= current - (PositionService.Rewind(player) + net.ClockSlack)
end

local function underRate(player)
	local r = rate[player]
	local t = os.clock()
	if not r or t - r.windowStart >= 1 then
		rate[player] = { windowStart = t, count = 1 }
		return true
	end
	r.count += 1
	return r.count <= net.MaxReportsPerSecond
end

local function plausibleStep(a, b, allowed)
	if not a or not b or allowed then
		return true
	end
	local dt = math.abs(b.t - a.t)
	local distance = (b.position - a.position).Magnitude
	if distance <= 3 then
		return true -- ruido de medición
	end
	return dt > 0 and distance / dt <= net.MaxSpeed
end

-- Guarda una muestra informada por el cliente (sin confirmar todavía). Devuelve false si es imposible.
function PositionService.Report(player, t, position, look)
	if not underRate(player) then
		flag(player, "PosicionesExcedidas")
		return false
	end
	if typeof(position) ~= "Vector3" or position ~= position or not PositionService.ValidTime(player, t) then
		flag(player, "PosicionesRechazadas")
		return false
	end
	if typeof(look) ~= "Vector3" or look ~= look or look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	-- Muestras de antes de un teletransporte que llegan tarde (canal liviano, desordenado): se descartan
	-- sin contarlas como sospechosas, para no mezclar el lugar viejo con el nuevo
	if teleportCut[player] and t < teleportCut[player] then
		return false
	end
	local list = reported[player]
	if not list then
		list = {}
		reported[player] = list
	end
	-- Lugar en orden temporal (los envíos por el canal liviano pueden llegar desordenados)
	local index = #list + 1
	while index > 1 and list[index - 1].t > t do
		index -= 1
	end
	local previous, nextSample = list[index - 1], list[index]
	if (previous and previous.t == t) or (nextSample and nextSample.t == t) then
		return true -- duplicado: ya lo tenemos
	end
	local sample = { t = t, position = position, look = Vector3.new(look.X, 0, look.Z) }
	local allowed = PositionService.Teleporting(player)
	if not plausibleStep(previous, sample, allowed) or not plausibleStep(sample, nextSample, allowed) then
		flag(player, "MovimientoSospechoso")
		return false
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
	local cut = teleportCut[player]
	for i = #list, 1, -1 do
		local a = list[i]
		if a.t <= t then
			local b = list[i + 1]
			if cut and a.t < cut then
				if t >= cut then
					return nil -- una muestra de antes del teletransporte no vale para un instante posterior
				end
				if b and b.t >= cut then
					b = nil -- no se interpola a través de un teletransporte
				end
			end
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

-- Posición INFORMADA por el cliente en la hora `t` (sin confirmar todavía): solo para comprobaciones que no dan
-- ventaja de alcance (p. ej. si empezó una picada en el aire). Devuelve Vector3 o nil.
function PositionService.ReportedAt(player, t)
	local sample = reportedAt(player, t)
	return sample and sample.position
end

-- Posición del jugador en la hora `t`, CONFIRMADA por la física observada. Espera (acotado, por
-- cuadros del servidor, no un tiempo fijo) a que lleguen los datos. Devuelve CFrame o nil: sin
-- confirmación no se le da ventaja a nadie.
function PositionService.ConfirmedAt(player, t)
	local character = player.Character
	if not character then
		return nil
	end
	local deadline = t + PositionService.OneWay(player) + net.ConfirmWindow
	while true do
		local sample = reportedAt(player, t)
		if sample and observedNear(character, sample.position, t - 0.05, deadline) then
			local look = if sample.look.Magnitude > 0.01 then sample.look.Unit else Vector3.new(0, 0, -1)
			return CFrame.lookAt(sample.position, sample.position + look)
		end
		if now() >= deadline or player.Character ~= character then
			-- Segundo valor: por qué no se confirmó (diagnóstico en Studio)
			if not sample then
				return nil, "sin informe del cliente para ese instante"
			end
			local root = character:FindFirstChild("HumanoidRootPart")
			return nil, string.format("lo informado está a %.1f studs de lo observado ahora", if root then (root.Position - sample.position).Magnitude else -1)
		end
		RunService.Heartbeat:Wait()
	end
end

-- Para teletransportes legítimos (reaparecer, pruebas): durante un instante, un salto no es sospechoso
function PositionService.AllowTeleport(player, seconds)
	teleportAllowance[player] = now() + (seconds or 0.5)
	teleportCut[player] = now()
	-- Lo informado ANTES no se borra (un golpe dado justo antes todavía se confirma con ello); al
	-- interpolar no se cruza el corte (ver reportedAt). El historial OBSERVADO tampoco se borra: es lo que vio el servidor, y un golpe dado justo antes del
	-- teletransporte todavía se juzga con él
end

-- Velocidad horizontal observada imposible (jugadores): solo se REGISTRA (atributo), no se castiga
-- automáticamente; la sanción necesita revisión humana y datos de juego real.
local speedWindow = {} -- [player] = { t, position }
local function observedSpeedCheck(player, character, t)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local w = speedWindow[player]
	if not w or w.character ~= character then
		speedWindow[player] = { t = t, position = root.Position, character = character }
		return
	end
	local dt = t - w.t
	if dt < net.ObservedSpeedWindow then
		return
	end
	local speed = flatDistance(root.Position, w.position) / dt
	if speed > net.MaxSpeed and not PositionService.Teleporting(player) then
		flag(player, "VelocidadObservadaImposible")
		if RunService:IsStudio() then
			warn(string.format("[UMBRAL] %s se movió a %.0f studs/s (máximo %d)", player.Name, speed, net.MaxSpeed))
		end
	end
	w.t, w.position = t, root.Position
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
		teleportCut[player] = nil
		rate[player] = nil
		speedWindow[player] = nil
	end)

	-- Historial observado: cada cuadro
	RunService.Heartbeat:Connect(function()
		local t = now()
		for model, list in pairs(observed) do
			-- Sin padre: no se muestrea (la tabla es de claves débiles: un modelo destruido se libera solo;
			-- un personaje que todavía no entró al mundo empieza a muestrearse al entrar)
			local root = model.Parent and model:FindFirstChild("HumanoidRootPart")
			if root then
				table.insert(list, { t = t, cframe = root.CFrame })
				trim(list, t)
			end
		end
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Character then
				observedSpeedCheck(player, player.Character, t)
			end
		end
	end)
end

return PositionService
