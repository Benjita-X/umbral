-- RemoteGuard: tope de mensajes por jugador y por remoto (cubeta de fichas). Las validaciones de cada servicio
-- (enfriamientos, alcance, tiempos) siguen mandando; esto solo impide que un cliente inunde el servidor.
-- Los límites son holgados: el juego normal nunca se acerca (las pruebas de estrés lo comprueban).

local Players = game:GetService("Players")

local RemoteGuard = {}

-- [nombre] = { tasa por segundo, ráfaga }
local LIMITS = {
	Golpe = { 60, 60 },
	InicioGolpe = { 20, 20 },
	Defensa = { 20, 20 },
	Posicion = { 40, 40 },
	Arma = { 10, 10 },
	Gancho = { 10, 10 },
	Resonancia = { 10, 10 },
	Ejecutar = { 6, 6 },
	Expedicion = { 5, 10 },
}

local buckets = {} -- [jugador] = { [nombre] = { fichas, último } }
local dropped = {} -- [jugador] = mensajes descartados (diagnóstico)

-- ¿Se atiende este mensaje? Devuelve false si el jugador superó el tope de ese remoto.
function RemoteGuard.Allow(player, name)
	local limit = LIMITS[name]
	if not limit then
		return true
	end
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local clock = os.clock()
	local bucket = perPlayer[name]
	if not bucket then
		bucket = { limit[2], clock }
		perPlayer[name] = bucket
	end
	bucket[1] = math.min(limit[2], bucket[1] + (clock - bucket[2]) * limit[1])
	bucket[2] = clock
	if bucket[1] < 1 then
		dropped[player] = (dropped[player] or 0) + 1
		player:SetAttribute("MensajesDescartados", dropped[player])
		return false
	end
	bucket[1] -= 1
	return true
end

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
	dropped[player] = nil
end)

return RemoteGuard
