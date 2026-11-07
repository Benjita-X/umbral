-- Combos rápidos (EXPERIMENTAL): encadenar golpes y habilidades de varios Ecos a ritmo de jugador, y comprobar
-- que el servidor ACEPTA cada pieza (ningún rechazo), que cada pieza pega y cuánto dura el combo entero.
-- Lo que se pide: "que se puedan hacer combos de forma rápida intercalada con diferentes habilidades".

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

return function(ctx)
	local Config, Input = ctx.CombatConfig, ctx.Input
	local record, waitUntil = ctx.record, ctx.waitUntil
	local player = ctx.player
	local eco = Config.Eco
	local controllers = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Controllers")
	local Eco = require(controllers:WaitForChild("EcoController"))
	Eco.SetAimMode("frente")

	local function byName(name)
		for _, model in ipairs(CollectionService:GetTagged("Objetivo")) do
			if model.Name == name then
				return model
			end
		end
		return nil
	end
	local m1, m2, m3 = byName("Muneco1"), byName("Muneco2"), byName("Muneco3")
	if not (m1 and m2 and m3) then
		ctx.skip("[Combos] Suite de combos", "faltan los muñecos del Dojo")
		return
	end

	local function ecoRejections()
		return player:GetAttribute("EcosRechazados") or 0
	end
	local function hitRejections()
		return player:GetAttribute("GolpesRechazados") or 0
	end
	local function resetAll(resonance)
		ctx.remote:FireServer("reiniciar_eco")
		ctx.remote:FireServer("resonancia", resonance or 0)
		table.clear(Eco.State.cooldownEnd)
		table.clear(Eco.State.recast)
		Eco.State.swapUntil = 0
		task.wait(0.2)
	end
	local function equip(name)
		if Eco.KitName() ~= name then
			Eco.Equip(name)
		end
		waitUntil(function()
			return player:GetAttribute("Eco") == name
		end, 2)
	end
	local function healthy(model)
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		waitUntil(function()
			return humanoid.Health >= humanoid.MaxHealth and (model:GetAttribute("ArdeHasta") or 0) < Workspace:GetServerTimeNow()
		end, 9)
		task.wait(0.1)
		return humanoid
	end
	local function standFacing(model, distance)
		local root = model:WaitForChild("HumanoidRootPart")
		local look = root.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z).Unit
		local position = root.Position + flatLook * distance
		ctx.waitForCharges()
		ctx.teleport(Vector3.new(position.X, root.Position.Y + 0.5, position.Z), -flatLook)
		return root
	end
	-- Cuenta los golpes que le entran a un muñeco (cada bajada de vida) mientras dura un combo
	local function hitCounter(humanoid)
		local count, last = 0, humanoid.Health
		local connection = humanoid.HealthChanged:Connect(function(health)
			if health < last - 0.01 then
				count += 1
			end
			last = health
		end)
		return function()
			connection:Disconnect()
			return count
		end
	end
	-- Espera a que la tecla esté lista como la vería un jugador en la barra (y la pulsa)
	local function press(action, slot, maxWait)
		if slot then
			local skill = Eco.SkillFor(slot, Eco.InAir())
			local key = Eco.CooldownKey and Eco.CooldownKey(slot, eco.Skills[skill or ""]) or slot
			waitUntil(function()
				return Eco.CooldownRemaining(key) <= 0
			end, maxWait or 1.5)
		end
		Input.Trigger(action)
	end
	local function damageAfter(humanoid, before, timeout)
		waitUntil(function()
			return humanoid.Health < before - 0.01
		end, timeout or 1)
		return before - humanoid.Health
	end

	-- ---------- 1. Viento de principio a fin: golpes → Ciclón → Cuchilla → Levante → subir → aire → Descenso ----------
	resetAll()
	equip("Viento")
	resetAll()
	local h3 = healthy(m3)
	local r3 = standFacing(m3, 4)
	local eco0, hit0 = ecoRejections(), hitRejections()
	local hits = hitCounter(h3)
	local synergies = {}
	local synergyConnection = Eco.Synergy:Connect(function(name)
		table.insert(synergies, name)
	end)
	local t0 = os.clock()
	Input.Trigger("Atacar")
	task.wait(0.16)
	Input.Trigger("Atacar")
	damageAfter(h3, h3.Health, 0.4)
	task.wait(0.12)
	press("HabilidadX", "X")
	damageAfter(h3, h3.Health, 0.6)
	task.wait(0.1)
	press("HabilidadZ", "Z")
	damageAfter(h3, h3.Health, 0.6)
	task.wait(0.1)
	local y0 = r3.Position.Y
	press("HabilidadC", "C")
	local recast = waitUntil(function()
		return Eco.State.recast.C ~= nil
	end, 1)
	if recast then
		Input.Trigger("HabilidadC")
	end
	local peakUp = 0
	waitUntil(function()
		peakUp = math.max(peakUp, r3.Position.Y - y0)
		-- Como un jugador: se golpea cuando el muñeco ya llegó arriba, a tu lado (subir llega antes que él)
		return r3.Position.Y - y0 >= 6 and math.abs(r3.Position.Y - ctx.root.Position.Y) < 3
	end, 1.3)
	local atAirHit = string.format("recast %s · muñeco subió %.1f · tú a %.1f del suelo · muñeco a %.1f de ti", tostring(recast), peakUp, ctx.root.Position.Y - y0, (r3.Position - ctx.root.Position).Magnitude)
	local airBefore = h3.Health
	Input.Trigger("Atacar")
	local airHit = damageAfter(h3, airBefore, 0.5) > 0
	task.wait(0.15)
	local inAir = not ctx.grounded()
	local descentBefore = h3.Health
	local function where()
		local offset = r3.Position - ctx.root.Position
		return string.format("muñeco a %.1f en horizontal y %.1f de alto respecto a ti", Vector3.new(offset.X, 0, offset.Z).Magnitude, offset.Y)
	end
	local atPress = where()
	local castDescent = false
	local descentConnection = Eco.Used:Connect(function(name)
		if name == "Descenso" then
			castDescent = true
		end
	end)
	press("HabilidadC", "C", 0.5)
	local descent = damageAfter(h3, descentBefore, 1.6) > 0
	local atLanding = where()
	descentConnection:Disconnect()
	atLanding ..= " · Descenso lanzado " .. tostring(castDescent) .. " · relanzamiento abierto " .. tostring(Eco.State.recast.C ~= nil)
	local elapsed = os.clock() - t0
	task.wait(0.3)
	local total = hits()
	synergyConnection:Disconnect()
	local ecoRejected, hitRejected = ecoRejections() - eco0, hitRejections() - hit0
	record(
		"[Combos] Viento completo: golpes, Ciclón, Cuchilla, Levante, subir, golpe aéreo y Descenso",
		total >= 6 and airHit and descent and ecoRejected == 0 and hitRejected == 0 and elapsed < 5.5,
		string.format(
			"%d golpes en %.1f s · combos: %s · golpe aéreo %s · en el aire al pedir el Descenso %s · Descenso %s (%s) · al golpear en el aire: %s · al pedirlo: %s · al caer: %s · rechazos: habilidades %d (%s), golpes %d",
			total, elapsed, if #synergies > 0 then table.concat(synergies, ", ") else "ninguno", tostring(airHit), tostring(inAir), tostring(descent), tostring(player:GetAttribute("UltimoEco")), atAirHit, atPress, atLanding, ecoRejected, ctx.lastRejections(2), hitRejected
		)
	)
	ctx.settle()

	-- ---------- 2. Entre Ecos: Levante (Viento) → en el aire, Fuego: Bola Infernal → Trueno: Relámpago ----------
	resetAll()
	equip("Viento")
	resetAll()
	local h2 = healthy(m2)
	local r2 = standFacing(m2, 5)
	eco0, hit0 = ecoRejections(), hitRejections()
	hits = hitCounter(h2)
	t0 = os.clock()
	local y2 = r2.Position.Y
	press("HabilidadC", "C")
	recast = waitUntil(function()
		return Eco.State.recast.C ~= nil
	end, 1)
	if recast then
		Input.Trigger("HabilidadC")
	end
	Input.Trigger("Eco4") -- Fuego, a mitad del combo
	waitUntil(function()
		return r2.Position.Y - y2 >= 4
	end, 0.8)
	local fireBefore = h2.Health
	press("HabilidadZ", "Z", 1.2) -- espera la breve pausa del cambio de Eco, como la vería en la barra
	local fireball = damageAfter(h2, fireBefore, 1.2) > 0
	Input.Trigger("Eco5") -- Trueno
	waitUntil(function()
		return ctx.grounded()
	end, 2)
	local boltBefore = h2.Health
	press("HabilidadX", "X", 1.2)
	local bolt = damageAfter(h2, boltBefore, 0.8) > 0
	elapsed = os.clock() - t0
	task.wait(0.3)
	total = hits()
	ecoRejected, hitRejected = ecoRejections() - eco0, hitRejections() - hit0
	record(
		"[Combos] Entre Ecos: Levante del Viento, Bola Infernal en el aire y Relámpago",
		fireball and bolt and total >= 3 and ecoRejected == 0 and elapsed < 5,
		string.format("%d golpes en %.1f s · bola en el aire %s · relámpago %s · Eco final %s · rechazos %d (%s)", total, elapsed, tostring(fireball), tostring(bolt), tostring(player:GetAttribute("Eco")), ecoRejected, ctx.lastRejections(2))
	)
	ctx.settle()

	-- ---------- 3. Oscuridad: Daga (marca) → Paso Sombrío a través (detona) → volver → Fauces ----------
	resetAll()
	equip("Oscuridad")
	resetAll()
	local h1 = healthy(m1)
	standFacing(m1, 9)
	eco0 = ecoRejections()
	hits = hitCounter(h1)
	t0 = os.clock()
	press("HabilidadX", "X")
	waitUntil(function()
		return (m1:GetAttribute("MarcadoHasta") or 0) > Workspace:GetServerTimeNow()
	end, 1)
	local marked = (m1:GetAttribute("MarcadoHasta") or 0) > Workspace:GetServerTimeNow()
	local reloads = player:GetAttribute("RecargasZ") or 0
	press("HabilidadZ", "Z")
	local detonated = waitUntil(function()
		return (player:GetAttribute("RecargasZ") or 0) > reloads
	end, 1)
	task.wait(0.25)
	Input.Trigger("HabilidadZ") -- volver a la sombra (relanzamiento)
	task.wait(0.3)
	standFacing(m1, 6)
	local jawsBefore = h1.Health
	press("HabilidadC", "C")
	local jaws = damageAfter(h1, jawsBefore, 0.8) > 0
	elapsed = os.clock() - t0
	task.wait(0.2)
	total = hits()
	ecoRejected = ecoRejections() - eco0
	record(
		"[Combos] Oscuridad: Daga marca, Paso Sombrío detona y recarga, Fauces",
		marked and detonated and jaws and ecoRejected == 0,
		string.format("%d golpes en %.1f s · marcado %s · detonó y recargó Z %s · Fauces %s · rechazos %d (%s)", total, elapsed, tostring(marked), tostring(detonated), tostring(jaws), ecoRejected, ctx.lastRejections(2))
	)

	-- ---------- 4. Agua → Trueno: Burbuja atrapa, Pararrayos y Juicio sobre el atrapado ----------
	resetAll(100)
	equip("Agua")
	resetAll(100)
	h2 = healthy(m2)
	standFacing(m2, 8)
	eco0 = ecoRejections()
	hits = hitCounter(h2)
	t0 = os.clock()
	local bubbleBefore = h2.Health
	press("HabilidadZ", "Z")
	local bubble = damageAfter(h2, bubbleBefore, 1) > 0
	Input.Trigger("Eco5")
	press("HabilidadC", "C", 1.2)
	task.wait(0.15)
	press("HabilidadV", "V", 1.2)
	task.wait(eco.Skills.Juicio.strikes * eco.Skills.Juicio.interval + 0.6)
	elapsed = os.clock() - t0
	total = hits()
	ecoRejected = ecoRejections() - eco0
	record(
		"[Combos] Agua y Trueno: Burbuja, Pararrayos y Juicio",
		bubble and total >= 4 and ecoRejected == 0,
		string.format("%d golpes en %.1f s · burbuja %s · rechazos %d (%s)", total, elapsed, tostring(bubble), ecoRejected, ctx.lastRejections(2))
	)

	-- ---------- 5. Reacciones: Agua (mojado) → Trueno = ELECTROCUCIÓN (cargado) → Oscuridad = PULSO UMBRÍO ----------
	resetAll()
	equip("Agua")
	resetAll()
	h2 = healthy(m2)
	standFacing(m2, 8)
	eco0 = ecoRejections()
	local reactions = {}
	local reactionConnection = player:GetAttributeChangedSignal("Reacciones"):Connect(function()
		table.insert(reactions, tostring(player:GetAttribute("UltimaReaccion")))
	end)
	t0 = os.clock()
	local wetBefore = h2.Health
	press("HabilidadZ", "Z")
	damageAfter(h2, wetBefore, 1)
	local wet = (m2:GetAttribute("MojadoHasta") or 0) > Workspace:GetServerTimeNow()
	-- (cada tecla tiene un solo enfriamiento para todos los Ecos: se usan teclas distintas)
	task.wait(1.3) -- que la burbuja lo suelte
	Input.Trigger("Eco5")
	press("HabilidadC", "C", 1.2) -- Pararrayos: su primer chispazo electrocuta al mojado
	waitUntil(function()
		return #reactions >= 1
	end, 1.5)
	Input.Trigger("Eco3")
	press("HabilidadX", "X", 1.2) -- Daga sobre el cargado: pulso umbrío
	waitUntil(function()
		return #reactions >= 2
	end, 1.5)
	elapsed = os.clock() - t0
	reactionConnection:Disconnect()
	ecoRejected = ecoRejections() - eco0
	record(
		"[Combos] Reacciones: Agua moja, Trueno electrocuta y Oscuridad hace el pulso",
		wet and reactions[1] == "ELECTROCUCIÓN" and reactions[2] == "PULSO UMBRÍO" and ecoRejected == 0,
		string.format("mojado %s · reacciones: %s · %.1f s · rechazos %d (%s)", tostring(wet), if #reactions > 0 then table.concat(reactions, " → ") else "ninguna", elapsed, ecoRejected, ctx.lastRejections(2))
	)

	-- ---------- 6. Contra la pared: Puño Volcánico estampa al muñeco en el muro y queda marcado ----------
	resetAll()
	equip("Fuego")
	resetAll()
	h2 = healthy(m2)
	local r2w = m2:WaitForChild("HumanoidRootPart")
	ctx.remote:FireServer("mover_muneco", "Muneco2", Vector3.new(-60, r2w.Position.Y, 64.5)) -- el Muro: cara en z = 69
	task.wait(0.4)
	ctx.teleport(Vector3.new(-60, 4, 57), Vector3.new(0, 0, 1))
	local wallBefore = h2.Health
	press("HabilidadC", "C")
	local splat = waitUntil(function()
		return (m2:GetAttribute("ParedHasta") or 0) > Workspace:GetServerTimeNow()
	end, 1.2)
	-- Rebote: un segundo empujón contra el muro (Bola Infernal) lo devuelve hacia ti
	local bounced = false
	if splat then
		press("HabilidadZ", "Z", 0.3)
		bounced = waitUntil(function()
			return (m2:GetAttribute("RebotaHasta") or 0) > Workspace:GetServerTimeNow() - 0.5
		end, 1.2)
	end
	record("[Combos] Rebote: empujar contra el muro al enemigo estampado lo devuelve hacia ti", bounced, "rebote " .. tostring(bounced))
	record(
		"[Combos] Contra la pared: un empujón fuerte estampa al enemigo en el muro",
		splat,
		string.format("estampado %s · daño %.1f · muñeco en z = %.1f", tostring(splat), wallBefore - h2.Health, r2w.Position.Z)
	)

	-- ---------- 7. Tope de malabar: tras 4,5 s en el aire se suelta y resiste ----------
	ctx.remote:FireServer("malabar_largo", "Muneco1")
	local resisted = waitUntil(function()
		return (m1:GetAttribute("ResisteHasta") or 0) > Workspace:GetServerTimeNow()
	end, 7)
	record("[Combos] Tope de malabar: tras 4,5 s en el aire, el enemigo se suelta (¡RESISTE!)", resisted, "resiste " .. tostring(resisted))

	-- ---------- 8. Liberación: Paso estando aturdido sale del aturdimiento y cuesta Resonancia ----------
	resetAll(100)
	ctx.teleport(Vector3.new(0, 4, 30), Vector3.new(0, 0, 1))
	local releasesBefore = player:GetAttribute("Liberaciones") or 0
	ctx.remote:FireServer("aturdir_jugador", 2.5)
	local stunned = waitUntil(function()
		return ctx.Combat.State.mode == "Aturdido"
	end, 1.5)
	local resonanceBefore = player:GetAttribute("Resonancia") or 0
	Input.Trigger("Paso")
	local released = waitUntil(function()
		return (player:GetAttribute("Liberaciones") or 0) > releasesBefore
	end, 1.5)
	task.wait(0.2)
	local serverFree = (player:GetAttribute("AturdidoHasta") or 0) <= Workspace:GetServerTimeNow()
	local spent = resonanceBefore - (player:GetAttribute("Resonancia") or 0)
	record(
		"[Combos] Liberación: Paso estando aturdido te libera y cuesta Resonancia",
		stunned and released and serverFree and ctx.Combat.State.mode ~= "Aturdido" and math.abs(spent - eco.Release.cost) < 1,
		string.format("aturdido %s · liberado %s · libre en el servidor %s · modo %s · gastó %.0f (cuesta %d) · rechazos: %s", tostring(stunned), tostring(released), tostring(serverFree), tostring(ctx.Combat.State.mode), spent, eco.Release.cost, ctx.lastRejections(1))
	)
	ctx.remote:FireServer("reiniciar_defensa")

	resetAll()
	equip("Viento")
	resetAll()
end
