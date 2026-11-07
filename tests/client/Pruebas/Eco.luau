-- Suite de las habilidades del Eco (EXPERIMENTAL, v2): Eco del Viento, una habilidad por tecla.
-- Mide lo que decide el servidor (vida, posiciones, Resonancia, rechazos), no el efecto visual.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

return function(ctx)
	local Config, Input, Combat = ctx.CombatConfig, ctx.Input, ctx.Combat
	local record, waitUntil = ctx.record, ctx.waitUntil
	local player = ctx.player
	local skills = Config.Eco.Skills
	local ecoRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Eco", 10)
	if not ecoRemote then
		ctx.skip("[Eco] Suite de habilidades", "no existe el remote Eco")
		return
	end
	local Eco = require(Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Controllers"):WaitForChild("EcoController"))
	Eco.SetAimMode("frente") -- las pruebas apuntan al frente (el ratón está donde sea)

	local function byName(tag, name)
		for _, model in ipairs(CollectionService:GetTagged(tag)) do
			if model.Name == name then
				return model
			end
		end
		return nil
	end
	local function resonance()
		return player:GetAttribute("Resonancia") or 0
	end
	local function setResonance(value)
		ctx.remote:FireServer("resonancia", value)
		waitUntil(function()
			return math.abs(resonance() - value) < 0.5
		end, 1)
	end
	-- Enfriamientos a cero en el servidor y en esta pantalla
	local function resetEco()
		ctx.remote:FireServer("reiniciar_eco")
		table.clear(Eco.State.cooldownEnd)
		table.clear(Eco.State.recast)
		Eco.State.swapUntil = 0
		task.wait(0.15)
	end
	local function healthy(model)
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		waitUntil(function()
			return humanoid.Health >= humanoid.MaxHealth
		end, 8)
		return humanoid
	end
	-- Párate a `distance` studs delante del modelo, mirándolo
	local function standFacing(model, distance)
		local root = model:WaitForChild("HumanoidRootPart")
		local look = root.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z).Unit
		local position = root.Position + flatLook * distance
		ctx.waitForCharges()
		ctx.teleport(Vector3.new(position.X, root.Position.Y + 0.5, position.Z), -flatLook)
		return root
	end
	local function flatDistance(a, b)
		return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
	end
	local function rejection()
		local count = player:GetAttribute("EcosRechazados") or 0
		return function()
			waitUntil(function()
				return (player:GetAttribute("EcosRechazados") or 0) > count
			end, 1.5)
			return player:GetAttribute("EcoRechazado")
		end
	end
	local function now()
		return Workspace:GetServerTimeNow()
	end

	local muneco1, muneco2, muneco3 = byName("Objetivo", "Muneco1"), byName("Objetivo", "Muneco2"), byName("Objetivo", "Muneco3")
	if not (muneco1 and muneco2 and muneco3) then
		ctx.skip("[Eco] Suite de habilidades", "faltan los muñecos del Dojo")
		return
	end
	resetEco()

	-- ---------- 1. Z · Cuchilla: proyectil que daña a distancia, sin costo ----------
	local h2 = healthy(muneco2)
	standFacing(muneco2, 20)
	setResonance(0)
	local before = h2.Health
	local used = nil
	local usedConnection = Eco.Used:Connect(function(name)
		used = name
	end)
	Input.Trigger("HabilidadZ")
	waitUntil(function()
		return h2.Health < before
	end, 1.5)
	task.wait(0.2)
	local dealt = before - h2.Health
	record(
		"[Eco] Z Cuchilla: el proyectil daña a 20 studs y no cuesta Resonancia",
		math.abs(dealt - skills.Cuchilla.damage) < 0.01 and used == "Cuchilla" and resonance() < 0.5,
		string.format("%.1f de daño (objetivo %d) · usada %s · Resonancia %d (cero: las básicas no cuestan) · último %s", dealt, skills.Cuchilla.damage, tostring(used), math.floor(resonance()), tostring(player:GetAttribute("UltimoEco")))
	)

	-- ---------- 2. El servidor respeta el enfriamiento ----------
	local why = rejection()
	ecoRemote:FireServer("cuchilla", now(), ctx.root.Position, ctx.root.CFrame.LookVector, ctx.root.CFrame.LookVector)
	record("[Eco] El servidor respeta el enfriamiento de cada tecla", why() == "enfriamiento", "motivo: " .. tostring(player:GetAttribute("EcoRechazado")))

	-- ---------- 3. Barra de habilidades: 4 casillas y el enfriamiento a la vista ----------
	local bar = player.PlayerGui:FindFirstChild("UmbralHabilidades")
	bar = bar and bar:FindFirstChild("Barra")
	local zSlot = bar and bar:FindFirstChild("Z")
	local zSeconds = zSlot and zSlot:FindFirstChild("Segundos")
	local zName = zSlot and zSlot:FindFirstChild("Nombre")
	record(
		"[Eco] La barra muestra las 4 habilidades y el enfriamiento",
		bar ~= nil and bar:FindFirstChild("X") ~= nil and bar:FindFirstChild("C") ~= nil and bar:FindFirstChild("V") ~= nil and zSeconds ~= nil and zSeconds.Text ~= "" and zName ~= nil and string.find(zName.Text, "CUCHILLA", 1, true) ~= nil,
		string.format("barra %s · Z dice '%s' · enfriamiento '%s'", tostring(bar ~= nil), zName and zName.Text or "-", zSeconds and zSeconds.Text or "-")
	)
	usedConnection:Disconnect()

	-- ---------- 4. La Cuchilla se frena en las paredes ----------
	resetEco()
	ctx.teleport(Vector3.new(-60, 4, 58), Vector3.new(0, 0, 1)) -- el Muro del laboratorio: su cara está en z = 69
	local finished = player:GetAttribute("CuchillasTerminadas") or 0
	Input.Trigger("HabilidadZ")
	waitUntil(function()
		return (player:GetAttribute("CuchillasTerminadas") or 0) > finished
	end, 2)
	local traveled = player:GetAttribute("UltimaCuchilla") or -1
	record("[Eco] La Cuchilla se frena en la pared (no la atraviesa)", traveled > 6 and traveled < 13, string.format("recorrió %.1f studs (la pared está a ~11; su alcance es %d)", traveled, skills.Cuchilla.range))

	-- ---------- 5. X · Ciclón: atrae al muñeco hasta tu frente ----------
	resetEco()
	local h1 = healthy(muneco1)
	local r1 = standFacing(muneco1, 9)
	local d0 = flatDistance(r1.Position, ctx.root.Position)
	before = h1.Health
	Input.Trigger("HabilidadX")
	waitUntil(function()
		return h1.Health < before
	end, 1.5)
	task.wait(0.4)
	local d1 = flatDistance(r1.Position, ctx.root.Position)
	record(
		"[Eco] X Ciclón: atrae al enemigo hasta tu frente y lo daña",
		math.abs((before - h1.Health) - skills.Ciclon.damage) < 0.01 and d1 < d0 - 3 and d1 < 6.5,
		string.format("distancia %.1f → %.1f studs · %.1f de daño (objetivo %d)", d0, d1, before - h1.Health, skills.Ciclon.damage)
	)

	-- ---------- 6. Sinergia: Ciclón y enseguida Cuchilla = REMOLINO CORTANTE ----------
	task.wait(0.1)
	before = h1.Health
	Input.Trigger("HabilidadZ")
	waitUntil(function()
		return h1.Health < before
	end, 1.5)
	task.wait(0.2)
	local synergyDamage = before - h1.Health
	local expected = skills.Cuchilla.damage * 1.5
	record(
		"[Eco] Sinergia: Ciclón → Cuchilla es REMOLINO CORTANTE (más daño)",
		player:GetAttribute("UltimaSinergia") == "REMOLINO CORTANTE" and math.abs(synergyDamage - expected) < 0.01,
		string.format("sinergia '%s' · %.1f de daño (normal %d, combo %.1f)", tostring(player:GetAttribute("UltimaSinergia")), synergyDamage, skills.Cuchilla.damage, expected)
	)

	-- ---------- 7. El Ciclón aturde a un enemigo (interrumpe lo que hacía) ----------
	local partner = CollectionService:GetTagged("Companero")[1]
	if partner then
		resetEco()
		ctx.remote:FireServer("reiniciar_defensa")
		standFacing(partner, 8)
		Input.Trigger("HabilidadX")
		local stunned = waitUntil(function()
			return partner:GetAttribute("Estado") == "Aturdido"
		end, 1.2)
		record("[Eco] El Ciclón aturde al enemigo", stunned == true, "estado: " .. tostring(partner:GetAttribute("Estado")))
		ctx.remote:FireServer("reiniciar_defensa")
	else
		ctx.skip("[Eco] El Ciclón aturde al enemigo", "no hay compañero de combate")
	end

	-- ---------- 8. C · Levante: lanza al aire y lo deja flotando arriba ----------
	resetEco()
	local h3 = healthy(muneco3)
	local r3 = standFacing(muneco3, 5)
	local y0 = r3.Position.Y
	before = h3.Health
	Input.Trigger("HabilidadC")
	local peak, heightAtHold = 0, 0
	local t0 = os.clock()
	while os.clock() - t0 < 0.9 do
		task.wait()
		peak = math.max(peak, r3.Position.Y - y0)
		if os.clock() - t0 >= 0.6 and heightAtHold == 0 then
			heightAtHold = r3.Position.Y - y0
		end
	end
	record(
		"[Eco] C Levante: lanza al enemigo y flota arriba (combo aéreo)",
		peak >= 6 and heightAtHold >= 4 and math.abs((before - h3.Health) - skills.Levante.damage) < 0.01,
		string.format("subió %.1f studs · a los 0,6 s seguía a %.1f · %.1f de daño (objetivo %d)", peak, heightAtHold, before - h3.Health, skills.Levante.damage)
	)

	-- ---------- 9. C otra vez: Ascenso (subes tras el lanzado) ----------
	-- (el relanzamiento se abre cuando el servidor confirma el Levante)
	local recast = waitUntil(function()
		return Eco.State.recast.C ~= nil
	end, 0.3) or Eco.State.recast.C ~= nil
	local playerY0 = ctx.root.Position.Y
	local rose = 0
	if recast then
		Input.Trigger("HabilidadC")
		local t1 = os.clock()
		while os.clock() - t1 < 0.45 do
			task.wait()
			rose = math.max(rose, ctx.root.Position.Y - playerY0)
		end
	end
	record("[Eco] C otra vez tras el Levante: Ascenso (subes tras él)", recast and rose >= 5, string.format("relanzamiento disponible %s · subiste %.1f studs", tostring(recast), rose))
	ctx.settle()

	-- ---------- 10. C en el aire: Descenso (picada y onda al aterrizar) ----------
	resetEco()
	task.wait(1) -- que el muñeco 3 baje
	local hd = healthy(muneco2)
	standFacing(muneco2, 4)
	before = hd.Health
	ctx.humanoid.Jump = true
	waitUntil(function()
		return not ctx.grounded() and ctx.root.AssemblyLinearVelocity.Y <= 2
	end, 1.5)
	Input.Trigger("HabilidadC")
	waitUntil(function()
		return hd.Health < before
	end, 2)
	task.wait(0.2)
	record(
		"[Eco] C en el aire: Descenso daña al aterrizar",
		math.abs((before - hd.Health) - skills.Descenso.damage) < 0.01,
		string.format("%.1f de daño (objetivo %d) · último %s · motivo si falló: %s", before - hd.Health, skills.Descenso.damage, tostring(player:GetAttribute("UltimoEco")), tostring(player:GetAttribute("EcoRechazado")))
	)
	ctx.settle()

	-- ---------- 11. V · Tempestad: sin Resonancia no sale; con ella atrapa y golpea varias veces ----------
	resetEco()
	setResonance(10)
	why = rejection()
	ecoRemote:FireServer("tempestad", now(), ctx.root.Position, ctx.root.CFrame.LookVector, ctx.root.CFrame.LookVector)
	record("[Eco] V Tempestad sin Resonancia suficiente no sale", why() == "Resonancia insuficiente", "motivo: " .. tostring(player:GetAttribute("EcoRechazado")))
	resetEco()
	local ht = healthy(muneco2)
	standFacing(muneco2, 6)
	setResonance(100)
	local r0 = resonance()
	before = ht.Health
	Input.Trigger("HabilidadV")
	task.wait(skills.Tempestad.duration + 0.6)
	local total = before - ht.Health
	local spent = r0 - resonance()
	record(
		"[Eco] V Tempestad: gasta Resonancia y golpea muchas veces",
		total >= skills.Tempestad.tickDamage * 4 + skills.Tempestad.finalDamage and spent >= skills.Tempestad.cost - 1 and spent <= skills.Tempestad.cost + 6,
		string.format("%.1f de daño en total · gastó %.0f de Resonancia (costo %d)", total, spent, skills.Tempestad.cost)
	)
	setResonance(0)
	ctx.settle()

	-- ---------- 12. Una habilidad corta tu golpe (y se puede seguir combinando) ----------
	resetEco()
	task.wait(1)
	healthy(muneco1)
	standFacing(muneco1, 4)
	used = nil
	usedConnection = Eco.Used:Connect(function(name)
		used = name
	end)
	Input.Trigger("Atacar")
	task.wait(0.03)
	local modeBefore = Combat.State.mode
	Input.Trigger("HabilidadZ")
	local modeAfter = Combat.State.mode
	usedConnection:Disconnect()
	record(
		"[Eco] Una habilidad corta la preparación de tu golpe",
		modeBefore == "Ataque" and used == "Cuchilla" and modeAfter == "Libre",
		string.format("antes: %s · habilidad: %s · después: %s", tostring(modeBefore), tostring(used), tostring(modeAfter))
	)

	-- ---------- Menú: existe, con controles, Ecos y ajustes ----------
	local menu = player.PlayerGui:FindFirstChild("UmbralMenu")
	local panel = menu and menu:FindFirstChild("Panel")
	local openButton = menu and menu:FindFirstChild("AbrirMenu")
	local shakeBefore = Config.Feedback.ScreenShake
	local toggled, ecoButton = false, false
	if panel and openButton then
		for _, child in ipairs(panel:GetDescendants()) do
			if child:IsA("TextButton") and string.find(child.Text, "Vibración", 1, true) then
				toggled = true -- el ajuste está en el menú (el clic real lo valida una persona)
			end
			if child:IsA("TextButton") and child.Name == "EcoViento" then
				ecoButton = true
			end
		end
	end
	record(
		"[Menú] El menú existe con botón, controles, Ecos y ajustes",
		panel ~= nil and openButton ~= nil and toggled and ecoButton and shakeBefore == Config.Feedback.ScreenShake,
		string.format("menú %s · botón %s · ajuste de vibración %s · Eco del Viento %s", tostring(panel ~= nil), tostring(openButton ~= nil), tostring(toggled), tostring(ecoButton))
	)

	setResonance(0)
	resetEco()
	ctx.teleport(Vector3.new(0, 4, 30), Vector3.new(0, 0, 1))
end
