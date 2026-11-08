-- Expedición: enemigos que mueren de verdad, experiencia, escala por dificultad y ronda, y el gancho de combate
-- (los pesados lo resisten hasta romperles la postura; tiene su propia espera). Usa el encuentro de prueba de
-- ExpedicionService (el lugar de pruebas no tiene la Grieta).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

return function(ctx)
	local Config = ctx.CombatConfig
	local record, waitUntil = ctx.record, ctx.waitUntil
	local player = ctx.player
	local state = ReplicatedStorage:WaitForChild("Expedicion")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local OPEN = Vector3.new(0, 4, 150)

	local function spawned(tag)
		local found = nil
		waitUntil(function()
			for _, model in ipairs(CollectionService:GetTagged(tag)) do
				if model:GetAttribute("Mortal") then
					found = model
					return true
				end
			end
			return false
		end, 6)
		return found
	end
	local function kill(tag)
		ctx.remote:FireServer("vida_enemigo", { tag = tag, value = 0 })
	end

	ctx.waitForCharges()
	ctx.teleport(OPEN, Vector3.new(0, 0, 1))
	task.wait(0.4)

	-- ---------- 1. Muere de verdad y da experiencia ----------
	local xp0 = (player:GetAttribute("Nivel") or 1) * 1000 + (player:GetAttribute("Experiencia") or 0)
	ctx.remote:FireServer("encuentro_prueba", { difficulty = "Expedicion", round = 1, spawns = { { kind = "Latido", distance = 12 } } })
	local latido = spawned("Latido")
	local humanoid = latido and latido:WaitForChild("Humanoid", 3)
	local health = humanoid and humanoid.MaxHealth or 0
	kill("Latido")
	local defeated = latido ~= nil and waitUntil(function()
		return latido:GetAttribute("Estado") == "Vencido"
	end, 2)
	local untargetable = latido ~= nil and waitUntil(function()
		return not latido:HasTag("Objetivo")
	end, 1)
	local gone = latido ~= nil and waitUntil(function()
		return latido.Parent == nil
	end, 5)
	task.wait(0.3)
	local xp1 = (player:GetAttribute("Nivel") or 1) * 1000 + (player:GetAttribute("Experiencia") or 0)
	local completed = state:GetAttribute("Fase") == "completada"
	record("[Expedición] Un enemigo de expedición muere de verdad (deja de ser objetivo, desaparece y no se levanta)",
		latido ~= nil and defeated and untargetable and gone,
		string.format("apareció %s · vencido %s · sin ser objetivo %s · retirado %s", tostring(latido ~= nil), tostring(defeated), tostring(untargetable), tostring(gone)))
	record("[Expedición] Vencerlo da experiencia y supera el encuentro",
		xp1 > xp0 and completed and math.abs(health - Config.Sparring.Types.Latido.maxHealth) < 1,
		string.format("experiencia %s → %s · encuentro completado %s · vida %d (base %d)", tostring(xp0), tostring(xp1), tostring(completed), health, Config.Sparring.Types.Latido.maxHealth))
	-- el panel de fin de este encuentro se cierra (no tapa las pruebas siguientes)
	local hud = player.PlayerGui:FindFirstChild("UmbralExpedicion")
	local finPanel = hud and hud:FindFirstChild("Fin")
	if finPanel then
		finPanel.Visible = false
	end
	ctx.Input.SetBlocked("expedicion", false)

	-- ---------- 2. La vida escala con dificultad y ronda ----------
	ctx.remote:FireServer("encuentro_prueba", { difficulty = "Desafio", round = 3, spawns = { { kind = "Centinela", distance = 14 } } })
	local centinela = spawned("Centinela")
	local centinelaHumanoid = centinela and centinela:WaitForChild("Humanoid", 3)
	local scaledHealth = centinelaHumanoid and centinelaHumanoid.MaxHealth or 0
	local balance = Config.Balance
	local expected = math.floor(Config.Sparring.Types.Centinela.maxHealth * balance.Difficulties.Desafio.health * (1 + 2 * balance.RoundGrowth.health) + 0.5)
	record("[Expedición] La vida de los enemigos escala con la dificultad y la ronda (con límites)",
		math.abs(scaledHealth - expected) <= 1,
		string.format("Centinela en Desafío, ronda 3: %d de vida (esperado %d; base %d)", scaledHealth, expected, Config.Sparring.Types.Centinela.maxHealth))
	kill("Centinela")
	task.wait(0.5)

	-- ---------- 3. Gancho de combate: el pesado lo resiste hasta romperle la postura; luego, su espera ----------
	ctx.remote:FireServer("encuentro_prueba", { difficulty = "Expedicion", round = 1, spawns = { { kind = "Acechador", distance = 16, elite = true } } })
	local elite = spawned("Acechador")
	local hookRemote = remotes:WaitForChild("Gancho")
	local function hook(target)
		local c0 = player:GetAttribute("GanchosRechazados") or 0
		local h0 = player:GetAttribute("GanchoHora")
		local t = Workspace:GetServerTimeNow()
		hookRemote:FireServer(t, target, ctx.root.Position, ctx.root.CFrame.LookVector)
		waitUntil(function()
			return (player:GetAttribute("GanchosRechazados") or 0) > c0 or player:GetAttribute("GanchoHora") ~= h0
		end, 1)
		if (player:GetAttribute("GanchosRechazados") or 0) > c0 then
			return false, player:GetAttribute("GanchoRechazado")
		end
		return player:GetAttribute("GanchoHora") == t, "aceptado"
	end
	if elite then
		task.wait(0.3)
		local okResist, whyResist = hook(elite)
		ctx.remote:FireServer("postura", { tag = "Acechador", value = 9999 })
		waitUntil(function()
			return (elite:GetAttribute("QuebradoHasta") or 0) > Workspace:GetServerTimeNow()
		end, 1)
		local okBroken, whyBroken = hook(elite)
		local okAgain, whyAgain = hook(elite)
		record("[Expedición] Un élite resiste el gancho hasta romperle la postura",
			not okResist and string.find(tostring(whyResist), "resiste", 1, true) ~= nil and okBroken,
			string.format("con postura: %s · quebrado: %s", tostring(whyResist), tostring(whyBroken)))
		record("[Expedición] El gancho de combate tiene su propia espera (no se encadena)",
			not okAgain and string.find(tostring(whyAgain), "enfriamiento", 1, true) ~= nil,
			string.format("segundo gancho seguido: %s (espera %d s)", tostring(whyAgain), Config.Weapons.Grapple.EnemyCooldown))
		kill("Acechador")
	else
		ctx.skip("[Expedición] Gancho contra un élite", "no apareció el élite")
	end
	task.wait(3)
	if finPanel then
		finPanel.Visible = false
	end
	ctx.Input.SetBlocked("expedicion", false)

	-- ---------- 4. La definitiva no se carga mientras está en enfriamiento ----------
	local ecoRemote = remotes:FindFirstChild("Eco")
	if ecoRemote and player:GetAttribute("Eco") == "Viento" then
		ctx.remote:FireServer("reiniciar_eco")
		ctx.remote:FireServer("resonancia", 100)
		waitUntil(function()
			return (player:GetAttribute("Resonancia") or 0) >= 99
		end, 1)
		local look = ctx.root.CFrame.LookVector
		ecoRemote:FireServer("tempestad", Workspace:GetServerTimeNow(), ctx.root.Position, look, look)
		waitUntil(function()
			return player:GetAttribute("DefinitivaHasta") ~= nil
		end, 1.5)
		local untilTime = player:GetAttribute("DefinitivaHasta")
		local left = if type(untilTime) == "number" then untilTime - Workspace:GetServerTimeNow() else -1
		local cooldown = Config.Eco.Skills.Tempestad.cooldown
		record("[Expedición] Tras lanzar la definitiva, la Resonancia no se carga hasta que termine su enfriamiento",
			left > cooldown - 1.5 and left <= cooldown + 0.1,
			string.format("Resonancia en pausa %.1f s (enfriamiento de la V: %d s)", left, cooldown))
		task.wait(Config.Eco.Skills.Tempestad.duration)
		ctx.remote:FireServer("reiniciar_eco")
		ctx.remote:FireServer("resonancia", 0)
	end
	ctx.settle()
end
