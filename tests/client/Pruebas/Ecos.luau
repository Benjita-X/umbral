-- Suite de los Ecos de Agua, Oscuridad, Fuego infernal y Trueno (EXPERIMENTAL). Para cada Eco: se equipa,
-- y se prueban sus habilidades clave contra los muñecos del Dojo. Mide lo que decide el servidor.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

return function(ctx)
	local Config, Input = ctx.CombatConfig, ctx.Input
	local record, waitUntil = ctx.record, ctx.waitUntil
	local player = ctx.player
	local skills = Config.Eco.Skills
	local Eco = require(Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Controllers"):WaitForChild("EcoController"))
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
		ctx.skip("[Ecos] Suite de los Ecos", "faltan los muñecos del Dojo")
		return
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
	local function resetEco()
		ctx.remote:FireServer("reiniciar_eco")
		table.clear(Eco.State.cooldownEnd)
		table.clear(Eco.State.recast)
		Eco.State.swapUntil = 0
		task.wait(0.15)
	end
	local function equip(name)
		Eco.Equip(name)
		waitUntil(function()
			return player:GetAttribute("Eco") == name
		end, 2)
		resetEco()
		return player:GetAttribute("Eco") == name
	end
	local function healthy(model)
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		waitUntil(function()
			local root = model:FindFirstChild("HumanoidRootPart")
			return humanoid.Health >= humanoid.MaxHealth and root and (model:GetAttribute("ArdeHasta") or 0) < Workspace:GetServerTimeNow()
		end, 9)
		task.wait(0.1)
		return humanoid
	end
	local function standFacing(model, distance)
		local root = model:WaitForChild("HumanoidRootPart")
		-- Los muñecos vuelven solos a su sitio; se espera a que estén ahí
		waitUntil(function()
			return root.AssemblyLinearVelocity.Magnitude < 0.5
		end, 3)
		local look = root.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z).Unit
		local position = root.Position + flatLook * distance
		ctx.waitForCharges()
		ctx.teleport(Vector3.new(position.X, root.Position.Y + 0.5, position.Z), -flatLook)
		return root
	end
	local function damageAfter(humanoid, before, seconds)
		waitUntil(function()
			return humanoid.Health < before
		end, 1.5)
		task.wait(seconds or 0.2)
		return before - humanoid.Health
	end
	local function flatDistance(a, b)
		return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
	end
	local function near(value, target)
		return math.abs(value - target) < 0.05
	end

	-- =============== AGUA ===============
	if equip("Agua") then
		-- Burbuja: atrapa y sube al muñeco
		local h = healthy(m2)
		local root = standFacing(m2, 12)
		local y0 = root.Position.Y
		local before = h.Health
		Input.Trigger("HabilidadZ")
		local dealt = damageAfter(h, before, 0.5)
		local lifted = root.Position.Y - y0
		task.wait(0.4)
		local stillUp = root.Position.Y - y0
		record("[Ecos] Agua Z Burbuja: atrapa al enemigo y lo deja flotando", near(dealt, skills.Burbuja.damage) and lifted >= 2.5 and stillUp >= 2, string.format("%.1f de daño (objetivo %d) · subió %.1f · a los 0,9 s seguía a %.1f", dealt, skills.Burbuja.damage, lifted, stillUp))

		-- Géiser: aviso y erupción que lanza
		h = healthy(m1)
		root = standFacing(m1, 9)
		y0 = root.Position.Y
		before = h.Health
		Input.Trigger("HabilidadC")
		local peak = 0
		local t0 = os.clock()
		while os.clock() - t0 < 1.3 do
			task.wait()
			peak = math.max(peak, root.Position.Y - y0)
		end
		dealt = before - h.Health
		record("[Ecos] Agua C Géiser: erupción en el punto apuntado que lanza", near(dealt, skills.Geiser.damage) and peak >= 5, string.format("%.1f de daño (objetivo %d) · subió %.1f studs", dealt, skills.Geiser.damage, peak))

		-- Oleaje: surfeas y arrastras al muñeco
		resetEco()
		h = healthy(m3)
		root = standFacing(m3, 5)
		local start = root.Position
		local playerStart = ctx.root.Position
		before = h.Health
		Input.Trigger("HabilidadX")
		dealt = damageAfter(h, before, 0.5)
		local moved = flatDistance(root.Position, start)
		local surfed = flatDistance(ctx.root.Position, playerStart)
		record("[Ecos] Agua X Oleaje: surfeas y arrastras al enemigo", near(dealt, skills.Oleaje.damage) and moved >= 6 and surfed >= 10, string.format("%.1f de daño · el muñeco se movió %.1f studs · tú surfeaste %.1f", dealt, moved, surfed))
		ctx.settle()

		-- Diluvio: la ola daña y la lluvia te cura
		resetEco()
		h = healthy(m2)
		standFacing(m2, 9)
		setResonance(100)
		ctx.remote:FireServer("vida_jugador", 40)
		waitUntil(function()
			return ctx.humanoid.Health <= 40.5
		end, 1)
		local life0 = ctx.humanoid.Health
		before = h.Health
		Input.Trigger("HabilidadV")
		dealt = damageAfter(h, before, 0.3)
		task.wait(skills.Diluvio.healTime)
		local healed = ctx.humanoid.Health - life0
		record("[Ecos] Agua V Diluvio: gran ola que daña y lluvia que cura", near(dealt, skills.Diluvio.damage) and healed >= skills.Diluvio.heal * 0.7, string.format("%.1f de daño (objetivo %d) · curó %.1f (objetivo %d)", dealt, skills.Diluvio.damage, healed, skills.Diluvio.heal))
		setResonance(0)
		ctx.remote:FireServer("curar")
	else
		ctx.skip("[Ecos] Agua", "no se pudo equipar el Eco del Agua")
	end

	-- =============== OSCURIDAD ===============
	if equip("Oscuridad") then
		-- Paso Sombrío: cruzas cortando y vuelves a tu sombra
		local h = healthy(m1)
		standFacing(m1, 7)
		local start = ctx.root.Position
		local before = h.Health
		Input.Trigger("HabilidadZ")
		local dealt = damageAfter(h, before, 0.25)
		local away = flatDistance(ctx.root.Position, start)
		Input.Trigger("HabilidadZ") -- relanzamiento: volver
		task.wait(0.45)
		local back = flatDistance(ctx.root.Position, start)
		record("[Ecos] Oscuridad Z Paso Sombrío: cruzas cortando y vuelves a tu sombra", near(dealt, skills.PasoSombrio.damage) and away >= 10 and back <= 3, string.format("%.1f de daño · te alejaste %.1f studs · al volver quedaste a %.1f del inicio", dealt, away, back))
		ctx.settle()

		-- Daga + Fauces: la daga marca y el siguiente golpe la detona (y recarga Z)
		resetEco()
		h = healthy(m2)
		standFacing(m2, 9)
		before = h.Health
		local recharges = player:GetAttribute("RecargasZ") or 0
		Input.Trigger("HabilidadX")
		waitUntil(function()
			return (m2:GetAttribute("MarcadoHasta") or 0) > Workspace:GetServerTimeNow()
		end, 1.5)
		local markedOk = (m2:GetAttribute("MarcadoHasta") or 0) > Workspace:GetServerTimeNow()
		Input.Trigger("HabilidadC")
		waitUntil(function()
			return (player:GetAttribute("RecargasZ") or 0) > recharges
		end, 1.5)
		task.wait(0.3)
		local total = before - h.Health
		local expected = skills.Daga.damage + skills.Fauces.damage + skills.Daga.detonate
		record("[Ecos] Oscuridad X Daga marca; C Fauces la detona y recarga Z", markedOk and total >= expected - 0.5 and (player:GetAttribute("RecargasZ") or 0) > recharges, string.format("marcado %s · %.1f de daño (daga %d + fauces %d + detonación %d) · recargas %d", tostring(markedOk), total, skills.Daga.damage, skills.Fauces.damage, skills.Daga.detonate, (player:GetAttribute("RecargasZ") or 0) - recharges))

		-- Eclipse: forma sombría y estallido al terminar
		resetEco()
		h = healthy(m3)
		standFacing(m3, 4)
		setResonance(100)
		before = h.Health
		Input.Trigger("HabilidadV")
		local active = waitUntil(function()
			return (player:GetAttribute("EclipseHasta") or 0) > Workspace:GetServerTimeNow()
		end, 1)
		task.wait(skills.Eclipse.duration + 0.6)
		dealt = before - h.Health
		record("[Ecos] Oscuridad V Eclipse: forma sombría y estallido al final", active and near(dealt, skills.Eclipse.burstDamage), string.format("forma activa %s · %.1f de daño del estallido (objetivo %d)", tostring(active), dealt, skills.Eclipse.burstDamage))
		setResonance(0)
	else
		ctx.skip("[Ecos] Oscuridad", "no se pudo equipar el Eco de la Oscuridad")
	end

	-- =============== FUEGO ===============
	if equip("Fuego") then
		-- Bola Infernal: explota y quema
		local h = healthy(m1)
		standFacing(m1, 14)
		local before = h.Health
		Input.Trigger("HabilidadZ")
		local direct = damageAfter(h, before, 0.05)
		local burning = waitUntil(function()
			return (m1:GetAttribute("ArdeHasta") or 0) > Workspace:GetServerTimeNow()
		end, 0.5)
		task.wait(skills.BolaInfernal.burn + 0.3)
		local total = before - h.Health
		record("[Ecos] Fuego Z Bola Infernal: explota y deja quemadura", direct >= skills.BolaInfernal.damage - 0.05 and burning and total >= skills.BolaInfernal.damage + 4 * Config.Eco.Burn.damage, string.format("explosión %.1f (objetivo %d) · ardiendo %s · total %.1f con la quemadura", direct, skills.BolaInfernal.damage, tostring(burning), total))

		-- Puño Volcánico: embestida y puñetazo que explota (empuja fuerte)
		resetEco()
		h = healthy(m2)
		local root = standFacing(m2, 8)
		local start = root.Position
		before = h.Health
		Input.Trigger("HabilidadC")
		local dealt = damageAfter(h, before, 0.35)
		local pushed = flatDistance(root.Position, start)
		record("[Ecos] Fuego C Puño Volcánico: embestida y puñetazo que empuja", dealt >= skills.PunoVolcanico.damage - 0.05 and pushed >= 3, string.format("%.1f de daño (objetivo %d + quemadura) · empujado %.1f studs", dealt, skills.PunoVolcanico.damage, pushed))

		-- Meteoro (C en el aire): picada que estalla al aterrizar
		resetEco()
		h = healthy(m3)
		standFacing(m3, 6)
		before = h.Health
		ctx.humanoid.Jump = true
		waitUntil(function()
			return not ctx.grounded() and ctx.root.AssemblyLinearVelocity.Y <= 2
		end, 1.5)
		Input.Trigger("HabilidadC")
		dealt = damageAfter(h, before, 0.1)
		record("[Ecos] Fuego C en el aire: Meteoro estalla al aterrizar", dealt >= skills.Meteoro.damage - 0.05, string.format("%.1f de daño (objetivo %d) · motivo si falló: %s", dealt, skills.Meteoro.damage, tostring(player:GetAttribute("EcoRechazado"))))
		ctx.settle()

		-- Infierno: anillo que quema a los de adentro
		resetEco()
		h = healthy(m1)
		standFacing(m1, 4)
		setResonance(100)
		before = h.Health
		Input.Trigger("HabilidadV")
		task.wait(2.2)
		dealt = before - h.Health
		record("[Ecos] Fuego V Infierno: el anillo quema a los de adentro", dealt >= skills.Infierno.tickDamage * 3 and (player:GetAttribute("InfiernoHasta") or 0) > Workspace:GetServerTimeNow(), string.format("%.1f de daño en 2,2 s · forma activa %s", dealt, tostring((player:GetAttribute("InfiernoHasta") or 0) > Workspace:GetServerTimeNow())))
		task.wait(skills.Infierno.duration - 2)
		setResonance(0)
	else
		ctx.skip("[Ecos] Fuego", "no se pudo equipar el Eco del Fuego")
	end

	-- =============== TRUENO ===============
	if equip("Trueno") then
		-- Rayo en cadena: el apuntado y salta a otro cercano
		local h2 = healthy(m2)
		local h1, h3 = healthy(m1), healthy(m3)
		standFacing(m2, 10)
		local b1, b2, b3 = h1.Health, h2.Health, h3.Health
		Input.Trigger("HabilidadZ")
		damageAfter(h2, b2, 0.4)
		local first = b2 - h2.Health
		local jumped = math.max(b1 - h1.Health, b3 - h3.Health)
		record("[Ecos] Trueno Z Rayo: golpea al apuntado y salta a otro cercano", near(first, skills.Rayo.damage) and jumped >= skills.Rayo.damage * skills.Rayo.falloff - 0.05, string.format("primero %.1f (objetivo %d) · salto %.1f · último %s", first, skills.Rayo.damage, jumped, tostring(player:GetAttribute("UltimoEco"))))

		-- Relámpago: cruzas como un rayo dañando a los del camino
		resetEco()
		local h = healthy(m1)
		standFacing(m1, 6)
		local start = ctx.root.Position
		local before = h.Health
		Input.Trigger("HabilidadX")
		local dealt = damageAfter(h, before, 0.2)
		local crossed = flatDistance(ctx.root.Position, start)
		record("[Ecos] Trueno X Relámpago: cruzas dañando a los del camino", near(dealt, skills.Relampago.damage) and crossed >= 10, string.format("%.1f de daño (objetivo %d) · recorriste %.1f studs", dealt, skills.Relampago.damage, crossed))
		ctx.settle()

		-- Pararrayos: el tótem electrocuta al más cercano cada medio segundo
		resetEco()
		h = healthy(m3)
		standFacing(m3, 8)
		before = h.Health
		Input.Trigger("HabilidadC")
		task.wait(2.3)
		dealt = before - h.Health
		record("[Ecos] Trueno C Pararrayos: el tótem electrocuta varias veces", dealt >= skills.Pararrayos.damage * 3 - 0.05, string.format("%.1f de daño en 2,3 s (cada chispazo %d)", dealt, skills.Pararrayos.damage))
		task.wait(skills.Pararrayos.duration - 2.2)

		-- Juicio: rayos del cielo sobre los enemigos cercanos
		resetEco()
		h = healthy(m2)
		standFacing(m2, 5)
		setResonance(100)
		before = h.Health
		Input.Trigger("HabilidadV")
		task.wait(skills.Juicio.strikes * skills.Juicio.interval + 0.5)
		dealt = before - h.Health
		record("[Ecos] Trueno V Juicio: los rayos caen sobre los enemigos cercanos", dealt >= skills.Juicio.damage * 2 - 0.05, string.format("%.1f de daño al muñeco del centro · último %s", dealt, tostring(player:GetAttribute("UltimoEco"))))
		setResonance(0)
	else
		ctx.skip("[Ecos] Trueno", "no se pudo equipar el Eco del Trueno")
	end

	-- Una habilidad de otro Eco se rechaza (el servidor sabe qué Eco llevas)
	equip("Trueno")
	local count = player:GetAttribute("EcosRechazados") or 0
	local remote = game:GetService("ReplicatedStorage").Remotes:FindFirstChild("Eco")
	remote:FireServer("cuchilla", Workspace:GetServerTimeNow(), ctx.root.Position, ctx.root.CFrame.LookVector, ctx.root.CFrame.LookVector)
	waitUntil(function()
		return (player:GetAttribute("EcosRechazados") or 0) > count
	end, 1.5)
	record("[Ecos] Una habilidad de otro Eco se rechaza", player:GetAttribute("EcoRechazado") == "habilidad de otro Eco", "motivo: " .. tostring(player:GetAttribute("EcoRechazado")))

	equip("Viento")
	ctx.remote:FireServer("curar")
	ctx.teleport(Vector3.new(0, 4, 30), Vector3.new(0, 0, 1))
end
