-- ExpedicionService: La Grieta como una partida completa. Eliges dificultad en el portal de la entrada, avanzas por
-- encuentros cuyos enemigos MUEREN de verdad, cada encuentro superado abre la puerta siguiente y da experiencia,
-- tras algunos eliges una mejora entre tres, y al final te espera el Guardián (dos fases). Al vencerlo: resumen y
-- repetir (misma u otra dificultad).
--   · Un encuentro se activa al entrar en su zona; sus enemigos escalan con la dificultad, la ronda y el número de
--     jugadores (BalanceService), y sobre todo cambian de COMPOSICIÓN (élites y enemigos extra según dificultad).
--   · Morir: reapareces en el último punto de control. Si caen todos los participantes, el encuentro en curso se
--     reinicia entero (sus enemigos vuelven con toda la vida al entrar otra vez en su zona).
--   · Lo que ven todos: atributos de ReplicatedStorage.Expedicion (Activa, Fase, Dificultad, Encuentro, Total,
--     Restantes, NombreEncuentro, Inicio). Cada jugador: Nivel, Experiencia, Mejoras.
-- Sin la Grieta en el mapa (lugar de pruebas) existe solo el encuentro de prueba (StartTestEncounter).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("CombatConfig"))
local SparringService = require(script.Parent:WaitForChild("SparringService"))
local BalanceService = require(script.Parent:WaitForChild("BalanceService"))
local PositionService = require(script.Parent:WaitForChild("PositionService"))
local PerfilService = require(script.Parent:WaitForChild("PerfilService"))

local RemoteGuard = require(script.Parent:WaitForChild("RemoteGuard"))

local ExpedicionService = {}

local balance = CombatConfig.Balance
local expedition = CombatConfig.Expedition

-- Encuentros de la Grieta (marcas "PuntoExpedicion_<marca>", zonas "ZonaEncuentroN", puertas "PuertaExpedicionN",
-- puntos de control "ControlEncuentroN"). extra = solo en Desafío; elite = élite si la dificultad tiene élites.
local ENCOUNTERS = {
	{
		name = "El pasillo",
		zone = "ZonaEncuentro1",
		door = "PuertaExpedicion1",
		checkpoint = "ControlEncuentro1",
		spawns = { { kind = "Latido", marker = "E1_A" }, { kind = "Latido", marker = "E1_B", extra = true } },
	},
	{
		name = "El abismo",
		zone = "ZonaEncuentro2",
		door = "PuertaExpedicion2",
		checkpoint = "ControlEncuentro2",
		spawns = { { kind = "Acechador", marker = "E2_Isla" }, { kind = "Centinela", marker = "E2_Borde" }, { kind = "Latido", marker = "E2_Extra", extra = true } },
	},
	{
		name = "El ascenso",
		zone = "ZonaEncuentro3",
		door = "PuertaExpedicion3",
		checkpoint = "ControlEncuentro3",
		spawns = { { kind = "Gemelo", marker = "E3_GemeloA", twin = true }, { kind = "Gemelo", marker = "E3_GemeloB", twin = true }, { kind = "Centinela", marker = "E3_Extra", extra = true } },
	},
	{
		name = "La vanguardia",
		zone = "ZonaEncuentro4",
		checkpoint = "ControlEncuentro4",
		spawns = { { kind = "Acechador", marker = "E4_Elite", elite = true }, { kind = "Latido", marker = "E4_Apoyo" }, { kind = "Centinela", marker = "E4_Extra", extra = true } },
	},
	{
		name = "El Guardián",
		zone = "ZonaEncuentro4", -- tras un reinicio, vuelve a aparecer al entrar en su sala
		auto = true, -- aparece solo al caer la vanguardia
		checkpoint = "ControlEncuentro4",
		spawns = { { guardian = true, marker = "E5_Guardian" } },
	},
}

local stateFolder, remote
local grieta = nil
local run = nil -- partida en curso (ver newRun)
local runCounter = 0

local function now()
	return Workspace:GetServerTimeNow()
end

local function setState(key, value)
	stateFolder:SetAttribute(key, value)
end

local function find(name)
	return grieta and grieta:FindFirstChild(name, true)
end

-- Puertas: cerradas, una barrera de luz que no se cruza; abiertas, desaparecen
local function setDoor(name, open)
	local door = name and find(name)
	if door and door:IsA("BasePart") then
		door.CanCollide = not open
		door.CanQuery = not open
		door.Transparency = if open then 1 else 0.55
		for _, child in ipairs(door:GetChildren()) do
			if child:IsA("Light") then
				child.Enabled = not open
			end
		end
	end
end

local function closeAllDoors()
	for i = 0, 3 do
		setDoor("PuertaExpedicion" .. i, false)
	end
end

local function inside(part, position)
	local offset = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y + 4 and math.abs(offset.Z) <= half.Z
end

local function rootOf(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and humanoid.Health > 0 then
		return root
	end
	return nil
end

local function participantCount()
	local n = 0
	for player in pairs(run.participants) do
		if player.Parent then
			n += 1
		end
	end
	return math.max(1, n)
end

local function publish()
	if not run then
		setState("Activa", false)
		setState("Fase", "")
		setState("Encuentro", 0)
		setState("Restantes", 0)
		setState("NombreEncuentro", "")
		return
	end
	local remaining = 0
	for model in pairs(run.active) do
		if SparringService.IsAlive(model) then
			remaining += 1
		end
	end
	setState("Activa", true)
	setState("Fase", run.phase)
	setState("Dificultad", run.difficulty)
	setState("Encuentro", run.index)
	setState("Total", run.total)
	setState("Restantes", remaining)
	setState("NombreEncuentro", run.encounterName or "")
	setState("Inicio", run.startedAt)
end

local function newRun(difficulty, players, total)
	runCounter += 1
	run = {
		id = string.format("%s:%d:%d", game.JobId, runCounter, math.floor(now() * 1000)), -- identifica la victoria (perfil)
		difficulty = if balance.Difficulties[difficulty] then difficulty else balance.DefaultDifficulty,
		startedAt = now(),
		phase = "explorando", -- explorando · combate · completada
		index = 0, -- encuentro actual (o el último superado mientras se explora)
		total = total,
		cleared = {}, -- [n] = true
		active = {}, -- [modelo] = true (enemigos vivos del encuentro en curso)
		deaths = 0,
		participants = {},
		choosing = {}, -- [jugador] = { id, ... } mejoras ofrecidas sin elegir
		checkpoint = nil,
	}
	for _, player in ipairs(players) do
		run.participants[player] = true
		BalanceService.ResetProgress(player)
	end
	return run
end

local function removeEnemies()
	if not run then
		return
	end
	for model in pairs(run.active) do
		SparringService.Remove(model)
	end
	table.clear(run.active)
end

-- Elige `count` mejoras distintas que el jugador no tenga
local function offerUpgrades(player)
	local pool = {}
	for id in pairs(expedition.Upgrades) do
		if not BalanceService.HasUpgrade(player, id) then
			table.insert(pool, id)
		end
	end
	table.sort(pool)
	local random = Random.new()
	local options = {}
	for _ = 1, math.min(3, #pool) do
		local index = random:NextInteger(1, #pool)
		table.insert(options, table.remove(pool, index))
	end
	if #options == 0 then
		return
	end
	run.choosing[player] = options
	local payload = {}
	for _, id in ipairs(options) do
		local spec = expedition.Upgrades[id]
		table.insert(payload, { id = id, label = spec.label, desc = spec.desc })
	end
	remote:FireClient(player, "mejoras", { options = payload })
end

local function summary()
	local list = {}
	for player in pairs(run.participants) do
		if player.Parent then
			table.insert(list, player)
		end
	end
	return {
		time = now() - run.startedAt,
		deaths = run.deaths,
		difficulty = run.difficulty,
		players = list,
	}
end

local function complete()
	if run.phase == "completada" then
		return -- una partida se completa una sola vez
	end
	run.phase = "completada"
	run.completedAt = now()
	publish()
	setDoor("PuertaExpedicion0", true)
	local data = summary()
	for _, player in ipairs(data.players) do
		-- Progreso permanente: solo expediciones reales (o el encuentro de prueba con la tienda simulada de Studio)
		local counted = false
		if not run.test or PerfilService.IsSimulated() then
			counted = PerfilService.RecordCompletion(player, run.id)
		end
		remote:FireClient(player, "fin", {
			counted = counted,
			completed = player:GetAttribute("ExpedicionesCompletadas"),
			globalLevel = player:GetAttribute("NivelGlobal"),
			profile = player:GetAttribute("PerfilEstado"),
			time = data.time,
			deaths = data.deaths,
			difficulty = data.difficulty,
			level = BalanceService.Level(player),
			upgrades = player:GetAttribute("Mejoras") or "",
			test = run.test == true,
		})
	end
end

local function cleared(index)
	run.cleared[index] = true
	run.phase = "explorando"
	run.encounterName = nil
	local def = run.encounters[index]
	if def.door then
		setDoor(def.door, true)
	end
	run.checkpoint = def.checkpoint or run.checkpoint
	for player in pairs(run.participants) do
		BalanceService.GainXp(player, balance.Rewards.Encuentro)
	end
	publish()
	if index >= run.total then
		complete()
		return
	end
	for _, after in ipairs(expedition.ChoicesAfter) do
		if after == index then
			for player in pairs(run.participants) do
				if player.Parent then
					offerUpgrades(player)
				end
			end
		end
	end
	local nextDef = run.encounters[index + 1]
	if nextDef and nextDef.auto then
		task.delay(2.5, function()
			if run and run.cleared[index] and not run.cleared[index + 1] and run.phase == "explorando" then
				ExpedicionService.StartEncounter(index + 1)
			end
		end)
	end
end

-- Arranca el encuentro `index`: crea sus enemigos (mortales, escalados)
function ExpedicionService.StartEncounter(index)
	if not run or run.cleared[index] or run.phase == "combate" then
		return
	end
	local def = run.encounters[index]
	local difficulty = balance.Difficulties[run.difficulty]
	run.index = index
	run.phase = "combate"
	run.encounterName = def.name
	local players = participantCount()
	local pendingTwin = nil
	for _, spawn in ipairs(def.spawns) do
		if not spawn.extra or difficulty.extra then
			local cframe = spawn.cframe
			if not cframe then
				local marker = find("PuntoExpedicion_" .. spawn.marker)
				cframe = marker and marker.CFrame
			end
			if cframe then
				local elite = spawn.elite == true and difficulty.elites == true
				local healthScale, damageScale = BalanceService.EnemyScales(run.difficulty, index - 1, players, elite)
				local model = SparringService.Spawn(spawn.kind, cframe, {
					mortal = true,
					elite = elite,
					guardian = spawn.guardian == true,
					healthScale = healthScale,
					damageScale = damageScale,
				})
				model:SetAttribute("Recompensa", if spawn.guardian then balance.Rewards.Jefe elseif elite then balance.Rewards.Elite else balance.Rewards.Comun)
				run.active[model] = true
				if spawn.twin then
					if pendingTwin then
						SparringService.LinkTwins(pendingTwin, model)
						pendingTwin = nil
					else
						pendingTwin = model
					end
				end
			end
		end
	end
	publish()
end

-- Reinicia el encuentro en curso (cayeron todos): fuera sus enemigos; vuelve a empezar al entrar en su zona
local function resetEncounter()
	if not run or run.phase ~= "combate" then
		return
	end
	removeEnemies()
	run.phase = "explorando"
	run.encounterName = nil
	publish()
end

local function teleport(player, cframe)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and cframe then
		PositionService.AllowTeleport(player, 1)
		root.AssemblyLinearVelocity = Vector3.zero
		character:PivotTo(cframe + Vector3.new(0, 3, 0))
	end
end

local function entranceCFrame()
	local spawn = find("Aparicion")
	return spawn and spawn.CFrame
end

-- Fin o abandono: fuera los enemigos, puertas cerradas, sin partida
local function resetRun()
	if run then
		removeEnemies()
	end
	run = nil
	closeAllDoors()
	publish()
end

local function startRun(difficulty)
	resetRun()
	newRun(difficulty, Players:GetPlayers(), #ENCOUNTERS)
	run.encounters = ENCOUNTERS
	setDoor("PuertaExpedicion0", true)
	publish()
end

-- ---------- Encuentro de prueba (lugar de pruebas, sin la Grieta) ----------
-- Enemigos mortales en `spawns` ({ kind, cframe, elite }) con la escala de la dificultad y la ronda dadas; vale como
-- una expedición de un solo encuentro (experiencia, fin y resumen incluidos).
function ExpedicionService.StartTestEncounter(players, spawns, difficulty, round)
	resetRun()
	newRun(difficulty, players, 1)
	run.test = true
	local encounter = { name = "Encuentro de prueba", spawns = spawns }
	run.encounters = { encounter }
	-- La ronda pedida se simula escalando como si fuera ese encuentro
	if round and round > 1 then
		run.encounters = {}
		for i = 1, round do
			run.encounters[i] = encounter
		end
		run.total = round
		for i = 1, round - 1 do
			run.cleared[i] = true
		end
	end
	ExpedicionService.StartEncounter(run.total)
	return run
end

function ExpedicionService.Run()
	return run
end

function ExpedicionService.Start()
	stateFolder = Instance.new("Folder")
	stateFolder.Name = "Expedicion"
	stateFolder.Parent = ReplicatedStorage
	remote = Instance.new("RemoteEvent")
	remote.Name = "Expedicion"
	remote.Parent = ReplicatedStorage:WaitForChild("Remotes")
	grieta = Workspace:WaitForChild("Maps"):FindFirstChild("Grieta")
	publish()
	if grieta then
		closeAllDoors()
	end

	-- Cada enemigo vencido de la partida: experiencia para quienes pelearon y, si era el último, encuentro superado
	SparringService.Defeated:Connect(function(model, winner, participants, partner)
		if not run or not run.active[model] then
			return
		end
		local reward = model:GetAttribute("Recompensa") or balance.Rewards.Comun
		run.active[model] = nil
		if partner then
			run.active[partner] = nil
		end
		local rewarded = {}
		for player in pairs(participants or {}) do
			rewarded[player] = true
		end
		if winner then
			rewarded[winner] = true
		end
		for player in pairs(rewarded) do
			run.participants[player] = true -- quien llega a mitad de partida y pelea, participa
			BalanceService.GainXp(player, reward)
		end
		publish()
		if next(run.active) == nil and run.phase == "combate" then
			cleared(run.index)
		end
	end)

	remote.OnServerEvent:Connect(function(player, action, value)
		if not RemoteGuard.Allow(player, "Expedicion") then
			return
		end
		if action == "empezar" then
			if not grieta or (run and run.phase ~= "completada") then
				return
			end
			-- Solo desde el portal de la entrada
			local portal = find("PortalExpedicion")
			local root = rootOf(player)
			if portal and root and (root.Position - portal.Position).Magnitude <= 16 then
				startRun(value)
			end
		elseif action == "mejora" then
			local options = run and run.choosing[player]
			if options and type(value) == "string" and table.find(options, value) then
				run.choosing[player] = nil
				BalanceService.AddUpgrade(player, value)
			end
		elseif action == "repetir" then
			if not run or run.phase ~= "completada" or not run.participants[player] then
				return
			end
			local difficulty = if type(value) == "string" and balance.Difficulties[value] then value else run.difficulty
			local wasTest = run.test
			local players = {}
			for p in pairs(run.participants) do
				table.insert(players, p)
			end
			if wasTest then
				resetRun()
				return
			end
			startRun(difficulty)
			for _, p in ipairs(players) do
				teleport(p, entranceCFrame())
			end
		elseif action == "abandonar" then
			if run and run.participants[player] and run.phase ~= "completada" and not run.test then
				-- A mitad de partida, abandonar saca SOLO a quien lo pide; la partida sigue para los demás
				local others = false
				for p in pairs(run.participants) do
					if p ~= player and p.Parent then
						others = true
					end
				end
				if others then
					run.participants[player] = nil
					run.choosing[player] = nil
					BalanceService.ResetProgress(player)
					publish()
					teleport(player, entranceCFrame())
					return
				end
			end
			if run and run.participants[player] then
				local players = {}
				for p in pairs(run.participants) do
					table.insert(players, p)
				end
				resetRun()
				for _, p in ipairs(players) do
					teleport(p, entranceCFrame())
				end
			end
		end
	end)

	-- Zonas: entrar en la del siguiente encuentro lo arranca
	local check = 0
	RunService.Heartbeat:Connect(function(dt)
		check += dt
		if check < 0.15 or not run or run.test or run.phase ~= "explorando" then
			return
		end
		check = 0
		local nextIndex = nil
		for i = 1, run.total do
			if not run.cleared[i] then
				nextIndex = i
				break
			end
		end
		local def = nextIndex and run.encounters[nextIndex]
		local zone = def and def.zone and find(def.zone)
		if not zone then
			return
		end
		for player in pairs(run.participants) do
			local root = rootOf(player)
			if root and inside(zone, root.Position) then
				ExpedicionService.StartEncounter(nextIndex)
				return
			end
		end
	end)

	-- Morir: al reaparecer, al último punto de control; si caen todos, el encuentro en curso se reinicia
	local function watch(player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 10)
			if humanoid then
				humanoid.Died:Connect(function()
					if not run or not run.participants[player] then
						return
					end
					run.deaths += 1
					local anyoneAlive = false
					for p in pairs(run.participants) do
						if p ~= player and rootOf(p) then
							anyoneAlive = true
						end
					end
					if not anyoneAlive then
						local wasFighting = run.phase == "combate"
						resetEncounter()
						if wasFighting then
							for p in pairs(run.participants) do
								if p.Parent then
									remote:FireClient(p, "derrota", { encounter = run.index })
								end
							end
						end
					end
				end)
			end
			if run and run.participants[player] and run.checkpoint and not run.test then
				local marker = find(run.checkpoint)
				task.delay(0.2, function()
					if run and marker then
						teleport(player, marker.CFrame)
					end
				end)
			end
		end)
	end
	Players.PlayerAdded:Connect(function(player)
		-- Quien entra con una partida en curso se une a ella (empieza en nivel 1 y aparece en el último punto de control)
		if run and not run.test and run.phase ~= "completada" then
			run.participants[player] = true
			BalanceService.ResetProgress(player)
		end
		watch(player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		if run then
			run.participants[player] = nil
			run.choosing[player] = nil
			if next(run.participants) == nil then
				resetRun()
			end
		end
	end)
end

return ExpedicionService
