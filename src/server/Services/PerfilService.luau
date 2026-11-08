-- PerfilService: progreso PERMANENTE mínimo (DataStore). Solo dos datos de juego:
--   · ExpedicionesCompletadas: expediciones de la Grieta terminadas (vencido el Guardián).
--   · NivelGlobal: 1 + ExpedicionesCompletadas // ExpedicionesPorNivel (tope NivelGlobalMax). Es distinto del atributo
--     "Nivel", que es el nivel TEMPORAL de la expedición en curso (BalanceService) y se reinicia cada partida.
-- Seguridad:
--   · Clave por UserId ("u_<UserId>"), perfil versionado { v, NivelGlobal, ExpedicionesCompletadas, meta }.
--   · Sesión con cerrojo: al cargar, el servidor se apunta como dueño (meta.sesion = JobId) con UpdateAsync. Si otro
--     servidor sigue siendo dueño (p. ej. el jugador saltó de servidor y el anterior aún guarda), se espera; un
--     cerrojo viejo (sin renovar en CERROJO_VENCE s) se considera abandonado. Toda escritura comprueba que seguimos
--     siendo dueños: un servidor desplazado NUNCA sobrescribe un perfil más nuevo.
--   · Si la carga falla tras los reintentos: el perfil queda en estado "error", se avisa al jugador y no se guarda
--     nada de ese jugador en toda la sesión (nunca se pisa un perfil real con valores iniciales).
--   · Escrituras ordenadas por jugador (una a la vez; si llega otra mientras guarda, se repite al terminar).
--   · Victoria deduplicada: meta.ultimaPartida guarda el id de la última expedición contada.
--   · Guarda al completar una expedición, al salir, periódicamente si hay cambios y al cerrar el servidor.
--   · El cliente no puede cambiar nada: no hay remoto de perfil; los atributos los pone solo el servidor.
-- En Studio sin publicar (PlaceId 0) los DataStores no existen: se usa una tienda SIMULADA en memoria y el estado lo
-- dice ("simulado"). Una simulación NO prueba el servicio real: eso se valida en una experiencia de pruebas publicada.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PerfilService = {}

local STORE_NAME = "UmbralPerfiles"
local VERSION = 1
local EXPEDICIONES_POR_NIVEL = 2
local NIVEL_GLOBAL_MAX = 50
local CERROJO_VENCE = 150 -- s: un cerrojo sin renovar más tiempo que esto se da por abandonado
local REINTENTOS = 4
local ESPERA_CERROJO = 6 -- s entre intentos mientras otro servidor tiene la sesión
local INTENTOS_CERROJO = 5
local AUTOGUARDADO = 90 -- s

PerfilService.ExpedicionesPorNivel = EXPEDICIONES_POR_NIVEL

-- ---------- Tienda: real o simulada ----------
local simulated = RunService:IsStudio() and game.PlaceId == 0
local mockData = {} -- [clave] = copia del valor (tienda simulada)
local mockFail = { load = 0, save = 0 } -- fallos inyectados (pruebas)
local store = nil

local function deepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local c = {}
	for k, v in pairs(t) do
		c[k] = deepCopy(v)
	end
	return c
end

-- UpdateAsync con la misma semántica en ambas tiendas: fn(actual) → nuevo (o nil para no escribir)
local function updateAsync(key, fn, kind)
	if simulated then
		if mockFail[kind] > 0 then
			mockFail[kind] -= 1
			error("fallo simulado de " .. kind)
		end
		task.wait(0.05)
		local result = fn(deepCopy(mockData[key]))
		if result ~= nil then
			mockData[key] = deepCopy(result)
		end
		return deepCopy(mockData[key])
	end
	store = store or DataStoreService:GetDataStore(STORE_NAME)
	return store:UpdateAsync(key, fn)
end

local function withRetries(label, fn)
	local lastErr = nil
	for attempt = 1, REINTENTOS do
		local ok, a, b = pcall(fn)
		if ok then
			return true, a, b
		end
		lastErr = a
		warn(string.format("[UMBRAL] Perfil: %s falló (intento %d/%d): %s", label, attempt, REINTENTOS, tostring(a)))
		task.wait(math.min(8, 1.5 ^ attempt))
	end
	return false, lastErr
end

-- ---------- Perfiles en memoria ----------
-- [jugador] = { key, estado ("cargando"|"listo"|"error"|"cerrado"), data, dirty, saving, again, done (BindableEvent) }
local sessions = {}

local function levelFor(completed)
	return math.clamp(1 + completed // EXPEDICIONES_POR_NIVEL, 1, NIVEL_GLOBAL_MAX)
end

local function blank()
	return { v = VERSION, NivelGlobal = 1, ExpedicionesCompletadas = 0, meta = {} }
end

-- Lee y normaliza un perfil guardado (versiones futuras: migrar aquí)
local function normalize(data)
	if type(data) ~= "table" then
		return blank()
	end
	local completed = math.max(0, math.floor(tonumber(data.ExpedicionesCompletadas) or 0))
	return {
		v = VERSION,
		ExpedicionesCompletadas = completed,
		NivelGlobal = levelFor(completed),
		meta = if type(data.meta) == "table" then data.meta else {},
	}
end

local function publish(player, session)
	if not player.Parent then
		return
	end
	player:SetAttribute("PerfilEstado", if simulated and session.estado == "listo" then "simulado" else session.estado)
	if session.data then
		player:SetAttribute("NivelGlobal", session.data.NivelGlobal)
		player:SetAttribute("ExpedicionesCompletadas", session.data.ExpedicionesCompletadas)
	end
end

local noticeRemote = nil
local function notify(player, title, subtitle)
	if noticeRemote and player.Parent then
		noticeRemote:FireClient(player, { title = title, subtitle = subtitle or "" })
	end
end

-- Escribe el perfil si seguimos siendo dueños de la sesión. release = soltar el cerrojo (salida o cierre).
local function write(player, session, release)
	if session.estado ~= "listo" then
		return false
	end
	local snapshot = deepCopy(session.data)
	local jobId = game.JobId
	local stolen = false
	local ok, err = withRetries("guardar", function()
		return updateAsync(session.key, function(current)
			local meta = type(current) == "table" and type(current.meta) == "table" and current.meta or {}
			if meta.sesion ~= nil and meta.sesion ~= jobId then
				stolen = true -- otro servidor tomó la sesión: no pisar su perfil
				return nil
			end
			local out = deepCopy(snapshot)
			out.meta = out.meta or {}
			out.meta.sesion = if release then nil else jobId
			out.meta.sesionHora = os.time()
			out.meta.guardado = os.time()
			return out
		end, "save")
	end)
	if stolen then
		warn("[UMBRAL] Perfil: otro servidor tiene la sesión de " .. player.Name .. "; este servidor deja de guardar")
		session.estado = "cerrado"
		return false
	end
	if not ok then
		warn("[UMBRAL] Perfil: no se pudo guardar el progreso de " .. player.Name .. ": " .. tostring(err))
		notify(player, "NO SE PUDO GUARDAR", "Tu progreso se volverá a intentar guardar")
		player:SetAttribute("PerfilGuardadoFallido", true)
		return false
	end
	player:SetAttribute("PerfilGuardadoFallido", nil)
	return true
end

-- Guardado ordenado: una escritura a la vez por jugador; si se pide otra durante la actual, se repite al terminar
local function save(player, release)
	local session = sessions[player]
	if not session or session.estado ~= "listo" then
		return false
	end
	if session.saving then
		session.again = true
		session.releaseAfter = session.releaseAfter or release
		session.done.Event:Wait()
		return not session.dirty
	end
	session.saving = true
	local okAll = true
	repeat
		session.again = false
		session.dirty = false
		local ok = write(player, session, release or session.releaseAfter)
		if not ok then
			session.dirty = true
			okAll = false
		end
	until not session.again or session.estado ~= "listo"
	session.saving = false
	session.done:Fire()
	return okAll
end

local function load(player)
	local session = { key = "u_" .. player.UserId, estado = "cargando", done = Instance.new("BindableEvent") }
	sessions[player] = session
	publish(player, session)
	local jobId = game.JobId
	for _ = 1, INTENTOS_CERROJO do
		local busy = false
		local ok, result = withRetries("cargar", function()
			return updateAsync(session.key, function(current)
				local data = normalize(current)
				local meta = data.meta
				if meta.sesion ~= nil and meta.sesion ~= jobId and os.time() - (tonumber(meta.sesionHora) or 0) < CERROJO_VENCE then
					busy = true -- otro servidor aún tiene la sesión (y quizá está guardando): esperar
					return nil
				end
				busy = false
				meta.sesion = jobId
				meta.sesionHora = os.time()
				return data
			end, "load")
		end)
		if sessions[player] ~= session then
			return -- salió mientras cargaba
		end
		if not ok then
			break
		end
		if not busy then
			session.data = normalize(result)
			session.estado = "listo"
			publish(player, session)
			return
		end
		task.wait(ESPERA_CERROJO)
	end
	session.estado = "error"
	publish(player, session)
	warn("[UMBRAL] Perfil: no se pudo cargar el perfil de " .. player.Name .. "; el progreso permanente queda en pausa")
	notify(player, "NO SE PUDO CARGAR TU PROGRESO", "Puedes jugar, pero esta sesión no guardará progreso. Vuelve a entrar más tarde.")
end

-- ---------- API ----------
-- Suma una expedición completada (una sola vez por partida: runId). Guarda al momento.
function PerfilService.RecordCompletion(player, runId)
	local session = sessions[player]
	if not session or session.estado ~= "listo" or type(runId) ~= "string" then
		return false
	end
	if session.data.meta.ultimaPartida == runId then
		return false -- esta victoria ya se contó
	end
	session.data.meta.ultimaPartida = runId
	session.data.ExpedicionesCompletadas += 1
	session.data.NivelGlobal = levelFor(session.data.ExpedicionesCompletadas)
	session.dirty = true
	publish(player, session)
	task.spawn(save, player, false)
	return true
end

function PerfilService.Get(player)
	local session = sessions[player]
	return session and session.data and deepCopy(session.data), session and session.estado
end

function PerfilService.IsSimulated()
	return simulated
end

-- ---------- Ganchos de prueba (solo tienda simulada) ----------
function PerfilService.TestFailNext(kind, count)
	if simulated and mockFail[kind] then
		mockFail[kind] = count
	end
end

function PerfilService.TestStored(player)
	return simulated and deepCopy(mockData["u_" .. player.UserId]) or nil
end

-- Simula que otro servidor dejó una sesión abierta (reentrada rápida): fija el cerrojo ajeno con hora `age` s atrás
function PerfilService.TestForeignLock(player, age, completed)
	if not simulated then
		return
	end
	local key = "u_" .. player.UserId
	local data = normalize(mockData[key])
	if completed then
		data.ExpedicionesCompletadas = completed
		data.NivelGlobal = levelFor(completed)
	end
	data.meta.sesion = "otro-servidor"
	data.meta.sesionHora = os.time() - (age or 0)
	mockData[key] = data
end

-- El otro servidor termina de guardar y suelta la sesión (con `completed` como su último dato guardado)
function PerfilService.TestReleaseForeign(player, completed)
	if not simulated then
		return
	end
	local key = "u_" .. player.UserId
	local data = normalize(mockData[key])
	if completed then
		data.ExpedicionesCompletadas = completed
		data.NivelGlobal = levelFor(completed)
	end
	data.meta.sesion = nil
	mockData[key] = data
end

-- Vuelve a cargar el perfil de un jugador como si acabara de entrar (simula salir y volver)
function PerfilService.TestReload(player)
	local session = sessions[player]
	if session and session.estado == "listo" then
		save(player, true)
	end
	sessions[player] = nil
	load(player)
	local s = sessions[player]
	return s and s.estado
end

function PerfilService.Save(player)
	return save(player, false)
end

function PerfilService.Start()
	noticeRemote = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):FindFirstChild("AvisoGrieta")
	if simulated then
		warn("[UMBRAL] Perfil: Studio sin publicar → tienda SIMULADA en memoria (no es el DataStore real)")
	end
	Players.PlayerAdded:Connect(load)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		if session and session.estado == "listo" then
			save(player, true)
		end
		if sessions[player] == session then
			sessions[player] = nil
		end
	end)
	-- Autoguardado (solo si hay cambios sin guardar)
	task.spawn(function()
		while true do
			task.wait(AUTOGUARDADO)
			for player, session in pairs(sessions) do
				if session.estado == "listo" and session.dirty and not session.saving then
					task.spawn(save, player, false)
				end
			end
		end
	end)
	-- Cierre del servidor: guardar y soltar todos los perfiles (Roblox da ~30 s)
	game:BindToClose(function()
		local pending = 0
		for player, session in pairs(sessions) do
			if session.estado == "listo" then
				pending += 1
				task.spawn(function()
					save(player, true)
					pending -= 1
				end)
			end
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.1)
		end
	end)
end

return PerfilService
