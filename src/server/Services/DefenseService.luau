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

-- Latencia de ida (aprox. la mitad del ping), con tope
function DefenseService.OneWay(player)
	return math.min(player:GetNetworkPing() / 2, defense.LagCompensationMax)
end

-- Cuánto debe esperar el servidor tras un impacto para recibir las defensas que el cliente hizo a tiempo
function DefenseService.ResolveDelay(player)
	return math.clamp(player:GetNetworkPing() + 0.05, 0.05, defense.LagCompensationMax)
end

local function validTime(player, t)
	local current = now()
	if type(t) ~= "number" or t ~= t then
		return false, current
	end
	local maxAge = player:GetNetworkPing() + defense.TimestampSlack
	if t > current + 0.05 or t < current - maxAge then
		return false, current
	end
	return true, t
end

local function onDefense(player, action, t, dir)
	local ok, time = validTime(player, t)
	if not ok then
		-- Hora imposible (futura o demasiado vieja): se cuenta y se usa la hora actual, sin ventaja
		player:SetAttribute("DefensasRechazadas", (player:GetAttribute("DefensasRechazadas") or 0) + 1)
	end
	local r = recordFor(player)
	if action == "defender_inicio" then
		-- Solo abre ventana de desvío si pasó el enfriamiento desde la pulsación anterior
		table.insert(r.presses, { t = time, valid = time - r.lastPress >= defense.DeflectCooldown })
		r.lastPress = time
		r.guardDown = time
		r.guardUp = nil
		r.postureActivity = time
		prune(r.presses, time)
	elseif action == "defender_fin" then
		r.guardUp = time
		r.postureActivity = time
	elseif action == "paso" then
		local flatDir = if typeof(dir) == "Vector3" then Vector3.new(dir.X, 0, dir.Z) else Vector3.zero
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if flatDir.Magnitude > 0.1 then
			-- Se guarda dónde estaba al empezar el Paso: sirve para saber si el ataque lo amenazaba
			table.insert(r.pasos, { t = time, dir = flatDir.Unit, position = if root then root.Position else nil })
			prune(r.pasos, time)
		end
	end
end

-- "perfecto", "normal" o nil, para un impacto que el jugador vio en el instante `perceived`
function DefenseService.FindDeflect(player, perceived)
	local r = recordFor(player)
	local best = nil
	for _, press in ipairs(r.presses) do
		local before = perceived - press.t
		if press.valid and before >= -0.03 and before <= defense.DeflectWindow then
			local kind = if before <= defense.PerfectWindow then "perfecto" else "normal"
			if kind == "perfecto" or not best then
				best = kind
			end
		end
	end
	return best
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

function DefenseService.Stun(player, duration)
	local r = recordFor(player)
	local t = now()
	r.stunStart = t
	player:SetAttribute("AturdidoHasta", t + duration)
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

-- Abre la ventana de Contraataque (el cliente la recibe con la latencia de ida ya sumada)
function DefenseService.OpenCounter(player)
	player:SetAttribute("ContraataqueHasta", now() + defense.CounterWindow + DefenseService.OneWay(player))
end

function DefenseService.Start()
	local remote = Instance.new("RemoteEvent")
	remote.Name = "Defensa"
	remote.Parent = ReplicatedStorage:WaitForChild("Remotes")
	remote.OnServerEvent:Connect(function(player, action, t, dir)
		if action == "defender_inicio" or action == "defender_fin" or action == "paso" then
			onDefense(player, action, t, dir)
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
