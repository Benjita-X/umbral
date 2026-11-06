-- Plugin local de UMBRAL para Roblox Studio.
-- Al abrir build/UMBRAL-Pruebas.rbxlx inicia solo una sesión de Play, deja correr las pruebas automáticas
-- y guarda todo lo que imprimen (y cualquier error) con plugin:SetSetting, para leerlo desde fuera de Studio.
-- En cualquier otro lugar NO hace nada: busca la carpeta-marca ReplicatedStorage.UmbralPruebasAutomaticas,
-- que solo existe en el lugar de pruebas.
-- Para quitarlo: borra UmbralPruebas.rbxmx de la carpeta de plugins de Studio (%LOCALAPPDATA%\Roblox\Plugins).

local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MARKER = "UmbralPruebasAutomaticas"
local CONTEXTS = { "edicion", "servidor", "cliente" }
local context = if RunService:IsEdit() then "edicion" elseif RunService:IsServer() then "servidor" else "cliente"
local KEY = "UmbralPruebas_" .. context
local MAX_LINES = 400

-- ¿Es el lugar de pruebas? En edición la marca ya está; en el cliente llega al replicarse.
local marker = if context == "edicion"
	then ReplicatedStorage:FindFirstChild(MARKER)
	else ReplicatedStorage:WaitForChild(MARKER, 20)
if not marker then
	return
end
local runIdValue = marker:FindFirstChild("RunId")
local runId = if runIdValue then runIdValue.Value else "?"

local buffer = {}
local dirty = false
local function add(kind, text)
	if #buffer >= MAX_LINES then
		return
	end
	table.insert(buffer, string.format("%s | %s | %s", os.date("!%H:%M:%S"), kind, text))
	dirty = true
end

local function flush()
	if not dirty then
		return
	end
	dirty = false
	local ok = pcall(function()
		plugin:SetSetting(KEY, { run = runId, lines = buffer })
	end)
	if not ok then
		dirty = true -- los tres contextos escriben el mismo archivo: se reintenta en la próxima vuelta
	end
end

local KINDS = {
	[Enum.MessageType.MessageOutput] = "salida",
	[Enum.MessageType.MessageInfo] = "info",
	[Enum.MessageType.MessageWarning] = "AVISO",
	[Enum.MessageType.MessageError] = "ERROR",
}

local function capture(message, messageType)
	local kind = KINDS[messageType] or "?"
	-- Todo lo de UMBRAL y cualquier error o aviso (ahí aparecen los fallos de los scripts)
	if string.find(message, "UMBRAL", 1, true) or kind == "ERROR" or kind == "AVISO" then
		add(kind, message)
	end
end

add("info", "plugin activo en contexto " .. context)
-- Lo que se imprimió ANTES de que el plugin se activara (errores de arranque de los scripts, por ejemplo)
for _, entry in ipairs(LogService:GetLogHistory()) do
	capture(entry.message, entry.messageType)
end
LogService.MessageOut:Connect(capture)
flush()

task.spawn(function()
	while true do
		task.wait(0.5)
		flush()
	end
end)

if context ~= "edicion" then
	return -- en servidor y cliente solo se registra la salida
end

task.spawn(function()
	-- Borrar los registros de una ejecución anterior
	for _, other in ipairs(CONTEXTS) do
		if other ~= context then
			pcall(function()
				plugin:SetSetting("UmbralPruebas_" .. other, { run = runId, lines = {} })
			end)
		end
	end

	-- En edición game.Loaded puede no dispararse nunca: se espera con un tope
	add("info", "esperando a que Studio termine de cargar (IsLoaded = " .. tostring(game:IsLoaded()) .. ")")
	flush()
	local waited = 0
	while not game:IsLoaded() and waited < 10 do
		task.wait(0.5)
		waited += 0.5
	end
	task.wait(4)
	add("info", string.format("carga lista tras %.1f s", waited + 4))
	flush()

	local okService, StudioTestService = pcall(function()
		return game:GetService("StudioTestService")
	end)
	if not okService or not StudioTestService then
		add("ERROR", "StudioTestService no está disponible: " .. tostring(StudioTestService))
		flush()
		return
	end

	add("info", "iniciando modo Play")
	flush()
	local okRun, result = pcall(function()
		return StudioTestService:ExecutePlayModeAsync({ origen = "UmbralPruebas" })
	end)
	if not okRun then
		add("ERROR", "no se pudo ejecutar el modo Play: " .. tostring(result))
		flush()
		return
	end

	if type(result) == "table" then
		-- El detalle sale de lo que devolvió EndTest: llega completo aunque el cliente se cierre antes de guardar
		local passed, total, skipped = 0, 0, 0
		for _, r in ipairs(result) do
			if type(r) == "table" then
				local label = if r.skipped then "OMITIDA" elseif r.ok then "OK" else "FALLA"
				if r.skipped then
					skipped += 1
				else
					total += 1
					if r.ok then
						passed += 1
					end
				end
				add("resultado", string.format("%s · %s · %s", label, tostring(r.name), tostring(r.detail)))
			end
		end
		add("info", string.format("sesión terminada · %d/%d pruebas OK · %d omitidas", passed, total, skipped))
	else
		add("info", "sesión terminada · resultado: " .. tostring(result))
	end
	flush()
end)
