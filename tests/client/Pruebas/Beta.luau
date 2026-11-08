-- Beta: progreso permanente (tienda SIMULADA de Studio: no sustituye a la prueba con el DataStore real), victoria
-- contada una sola vez, recarga, fallos de carga/guardado, reentrada rápida a otro servidor, morir sin perder
-- progreso y tope de mensajes por remoto.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

return function(ctx)
	local record, waitUntil = ctx.record, ctx.waitUntil
	local player = ctx.player
	local remotes = ReplicatedStorage:WaitForChild("Remotes")

	local function completed()
		return player:GetAttribute("ExpedicionesCompletadas") or -1
	end
	local function estado()
		return player:GetAttribute("PerfilEstado")
	end
	-- Cada petición lleva una marca: la respuesta del servidor es "marca|resultado" (así nunca se lee una vieja)
	local serial = 0
	local function reloadStatus(tag)
		local value = tostring(player:GetAttribute("PerfilRecarga") or "")
		local got, result = string.match(value, "^([^|]*)|(.*)$")
		if got == tag then
			return result
		end
		return nil
	end
	local function startReload()
		serial += 1
		local tag = "r" .. serial
		ctx.remote:FireServer("perfil_recargar", tag)
		return tag
	end
	local function awaitReload(tag, timeout)
		waitUntil(function()
			local r = reloadStatus(tag)
			return r ~= nil and r ~= "esperando"
		end, timeout or 20)
		return reloadStatus(tag)
	end
	local function reload(timeout)
		return awaitReload(startReload(), timeout)
	end
	local function saveNow()
		serial += 1
		local tag = "g" .. serial
		ctx.remote:FireServer("perfil_guardar", tag)
		local result, stored = nil, nil
		waitUntil(function()
			local got, r, n = string.match(tostring(player:GetAttribute("PerfilGuardado") or ""), "^([^|]*)|([^|]*)|(.*)$")
			if got == tag then
				result, stored = r, tonumber(n)
				return true
			end
			return false
		end, 20)
		return result, stored
	end

	-- ---------- 0. Perfil cargado ----------
	local loaded = waitUntil(function()
		return estado() == "simulado" or estado() == "listo" or estado() == "error"
	end, 15)
	ctx.remote:FireServer("perfil_simulado")
	waitUntil(function()
		return player:GetAttribute("PerfilSimulado") ~= nil
	end, 3)
	if player:GetAttribute("PerfilSimulado") ~= true then
		ctx.skip("[Beta] Perfil permanente", "la tienda no es la simulada (este lugar está publicado): pruébalo a mano")
		return
	end
	record("[Beta] El perfil permanente carga al entrar (NivelGlobal y ExpedicionesCompletadas, separados del Nivel de la partida)",
		loaded and estado() == "simulado" and completed() >= 0 and (player:GetAttribute("NivelGlobal") or 0) >= 1,
		string.format("estado %s · expediciones %d · nivel global %s · nivel de partida %s", tostring(estado()), completed(),
			tostring(player:GetAttribute("NivelGlobal")), tostring(player:GetAttribute("Nivel"))))

	-- ---------- 1. Completar una expedición suma exactamente una ----------
	ctx.waitForCharges()
	ctx.teleport(Vector3.new(0, 4, 150), Vector3.new(0, 0, 1))
	task.wait(0.3)
	local before = completed()
	ctx.remote:FireServer("encuentro_prueba", { difficulty = "Expedicion", round = 1, spawns = { { kind = "Latido", distance = 12 } } })
	local enemy = nil
	waitUntil(function()
		for _, model in ipairs(CollectionService:GetTagged("Latido")) do
			if model:GetAttribute("Mortal") then
				enemy = model
				return true
			end
		end
		return false
	end, 6)
	ctx.remote:FireServer("vida_enemigo", { tag = "Latido", value = 0 })
	local counted = waitUntil(function()
		return completed() == before + 1
	end, 6)
	task.wait(1)
	local levelOk = (player:GetAttribute("NivelGlobal") or 0) == 1 + completed() // 2
	record("[Beta] Completar una expedición suma exactamente 1 expedición y recalcula el nivel global",
		enemy ~= nil and counted and completed() == before + 1 and levelOk,
		string.format("%d → %d · nivel global %s (regla: 1 + expediciones // 2)", before, completed(), tostring(player:GetAttribute("NivelGlobal"))))
	local hud = player.PlayerGui:FindFirstChild("UmbralExpedicion")
	local finPanel = hud and hud:FindFirstChild("Fin")
	if finPanel then
		finPanel.Visible = false
	end
	ctx.Input.SetBlocked("expedicion", false)
	if ctx.Camera and ctx.Camera.SetMouseFree then
		ctx.Camera.SetMouseFree("expedicion", false)
	end

	-- ---------- 2. La misma victoria no cuenta dos veces ----------
	local c0 = completed()
	local id = "dup-" .. tostring(os.clock())
	ctx.remote:FireServer("perfil_completar", id)
	waitUntil(function()
		return completed() == c0 + 1
	end, 3)
	ctx.remote:FireServer("perfil_completar", id)
	task.wait(0.5)
	record("[Beta] Una misma victoria (mismo id de partida) solo cuenta una vez",
		completed() == c0 + 1 and player:GetAttribute("PerfilConto") == false,
		string.format("%d → %d tras repetir la misma victoria", c0, completed()))

	-- ---------- 3. Guardar, salir y volver: el contador se mantiene ----------
	local saved, stored = saveNow()
	local c1 = completed()
	local r = reload()
	record("[Beta] Guardar, salir y volver: se recupera el mismo contador",
		saved == "ok" and stored == c1 and (r == "listo") and completed() == c1,
		string.format("guardado %s (almacenado %s) · recarga %s · expediciones %d (antes %d)", tostring(saved), tostring(stored), tostring(r), completed(), c1))

	-- ---------- 4. Morir / reaparecer conserva el progreso permanente ----------
	local c2 = completed()
	local oldCharacter = player.Character
	ctx.remote:FireServer("reaparecer")
	local respawned = waitUntil(function()
		return player.Character ~= nil and player.Character ~= oldCharacter and ctx.Combat.State.ready
	end, 12)
	if respawned then
		ctx.bindCharacter(player.Character)
	end
	task.wait(0.5)
	record("[Beta] Reaparecer conserva el progreso permanente y deja el combate listo",
		respawned and completed() == c2,
		string.format("reapareció %s · expediciones %d (antes %d)", tostring(respawned), completed(), c2))

	-- ---------- 5. Fallo de carga: no sobrescribe el perfil ----------
	saveNow()
	local c3 = completed()
	ctx.remote:FireServer("perfil_fallo", { kind = "load", count = 99 })
	local r2 = reload(40)
	local errorState = estado() == "error"
	ctx.remote:FireServer("perfil_fallo", { kind = "load", count = 0 })
	local storedAfter = select(2, saveNow()) -- con el perfil en error, guardar no escribe nada
	record("[Beta] Si la carga falla, el perfil queda en error, se avisa y NO se sobrescribe lo guardado",
		r2 == "error" and errorState and storedAfter == c3,
		string.format("recarga %s · estado %s · almacenado %s (antes %d)", tostring(r2), tostring(estado()), tostring(storedAfter), c3))
	local r3 = reload()
	record("[Beta] Al volver a entrar después del fallo, el perfil se recupera intacto",
		r3 == "listo" and completed() == c3,
		string.format("recarga %s · expediciones %d (esperadas %d)", tostring(r3), completed(), c3))

	-- ---------- 6. Fallo de guardado: se informa y se recupera ----------
	ctx.remote:FireServer("perfil_fallo", { kind = "save", count = 99 })
	local s1 = saveNow()
	local flagged = player:GetAttribute("PerfilGuardadoFallido") == true
	ctx.remote:FireServer("perfil_fallo", { kind = "save", count = 0 })
	local s2, stored2 = saveNow()
	record("[Beta] Si el guardado falla, se avisa y el siguiente guardado lo recupera",
		s1 == "fallo" and flagged and s2 == "ok" and stored2 == completed() and waitUntil(function()
			return player:GetAttribute("PerfilGuardadoFallido") == nil
		end, 2),
		string.format("primer guardado %s (aviso %s) · reintento %s · almacenado %s", tostring(s1), tostring(flagged), tostring(s2), tostring(stored2)))

	-- ---------- 7. Reentrada rápida: espera al servidor anterior y no restaura un perfil viejo ----------
	local c4 = completed()
	-- Este servidor "sale" (suelta la sesión) y otro servidor la toma con un dato MÁS NUEVO aún sin soltar
	local tag7 = startReload() -- guarda y suelta; luego vuelve a cargar...
	ctx.remote:FireServer("perfil_cerrojo", { age = 0, completed = c4 + 5 }) -- ...pero otro servidor ya la tiene
	task.wait(3)
	local waiting = reloadStatus(tag7) == "esperando"
	ctx.remote:FireServer("perfil_soltar", c4 + 5) -- el otro servidor termina de guardar y la suelta
	local r7 = awaitReload(tag7, 25)
	record("[Beta] Reentrada rápida: espera a que el otro servidor suelte el perfil y carga el dato más nuevo",
		waiting and r7 == "listo" and completed() == c4 + 5,
		string.format("esperó %s · recarga %s · expediciones %d (esperadas %d, el viejo era %d)", tostring(waiting),
			tostring(r7), completed(), c4 + 5, c4))

	-- ---------- 8. Las 40 animaciones publicadas cargan y se reproducen ----------
	local animator = ctx.humanoid and ctx.humanoid:FindFirstChildOfClass("Animator")
	local ids = require(ReplicatedStorage.Shared.Config.AnimacionesSubidas)
	if animator then
		local total, okCount, bad = 0, 0, {}
		local tracks = {}
		for name, id in pairs(ids) do
			total += 1
			local animation = Instance.new("Animation")
			animation.AnimationId = id
			local okLoad, track = pcall(function()
				return animator:LoadAnimation(animation)
			end)
			if okLoad and track then
				tracks[name] = track
			else
				table.insert(bad, name)
			end
		end
		waitUntil(function()
			for _, track in pairs(tracks) do
				if track.Length <= 0 then
					return false
				end
			end
			return true
		end, 15)
		for name, track in pairs(tracks) do
			if track.Length > 0 then
				track:Play(0, 0.01)
				okCount += 1
				track:Stop(0)
			else
				table.insert(bad, name)
			end
			track:Destroy()
		end
		table.sort(bad)
		record("[Beta] Las animaciones publicadas cargan y se reproducen (en Studio, con tu sesión)",
			total >= 40 and okCount == total,
			string.format("%d de %d cargadas%s", okCount, total, if #bad > 0 then " · sin cargar: " .. table.concat(bad, ", ") else ""))
	end

	-- ---------- 9. Tope de mensajes: una inundación se descarta, el uso normal no ----------
	local dropped0 = player:GetAttribute("MensajesDescartados") or 0
	local expedRemote = remotes:WaitForChild("Expedicion")
	for _ = 1, 60 do
		expedRemote:FireServer("nada")
	end
	waitUntil(function()
		return (player:GetAttribute("MensajesDescartados") or 0) > dropped0
	end, 3)
	local dropped1 = player:GetAttribute("MensajesDescartados") or 0
	record("[Beta] Inundar un remoto: el servidor descarta el exceso (el juego normal nunca llega al tope)",
		dropped1 - dropped0 >= 40,
		string.format("descartados %d de 60 mensajes seguidos (descartes previos en toda la ronda: %d)", dropped1 - dropped0, dropped0))
	ctx.settle()
end
