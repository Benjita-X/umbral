-- Eco del Fuego Infernal (EXPERIMENTAL): daño sostenido y explosiones. La quemadura hace daño cada medio
-- segundo sin empujar ni interrumpir (EcoService.burn).
--   Z Bola Infernal: proyectil que explota al chocar (enemigo o pared) y deja el suelo ardiendo.
--   X Estela Ardiente: Paso de fuego (te mueves tú) que corta a quien cruzas y deja un rastro que quema.
--   C Puño Volcánico: embestida corta y puñetazo que explota. En el aire, C es Meteoro: picada en diagonal hacia
--     donde apuntas que estalla al aterrizar y deja un cráter ardiente.
--   V Infierno (definitiva): anillo de fuego que quema a los de adentro; tus golpes del combo arden (EcoService).

return function(api)
	local skills = api.skills
	local Hurtbox = api.Hurtbox
	local H = {}

	-- Suelo ardiente: quema a quien esté dentro, cada medio segundo
	local function burningGround(player, center, radius, duration)
		api.zone(player, duration, 0.5, function()
			for _, model in ipairs(api.radiusTargets(player, center + Vector3.new(0, 3, 0), radius, 6, api.now())) do
				api.burn(player, model, 1)
			end
		end)
	end

	-- ---------- Z · Bola Infernal ----------
	H.bola_infernal = function(player, t, position, look, aim)
		local spec = skills.BolaInfernal
		local origin, feet = api.begin(player, "BolaInfernal", t, position, look)
		if not origin then
			return
		end
		local dir = api.aimDirection(aim, origin.LookVector, if feet >= api.AIR_FEET then spec.airMaxPitch else spec.maxPitch)
		local start = origin.Position + Vector3.new(0, 0.3, 0)
		api.broadcast(player, "BolaInfernal", { origin = start, dir = dir })
		player:SetAttribute("UltimoEco", "BolaInfernal:0")
		local _, finish = api.projectile(player, {
			start = start,
			dir = dir,
			t = t,
			speed = spec.speed,
			range = spec.range,
			reachX = spec.radius + Hurtbox.Size.X / 2,
			reachY = spec.radius + Hurtbox.Size.Y / 2,
			pierce = false,
			onHit = function() end, -- la explosión hace el daño (también al que tocó)
		})
		if not player.Parent then
			return
		end
		-- Explosión: daña y quema alrededor; deja el suelo ardiendo
		api.broadcast(player, "Explosion", { center = finish, radius = spec.blast, serverDriven = true })
		local targets = api.radiusTargets(player, finish, spec.blast, 6, api.now())
		for _, model in ipairs(targets) do
			local root = model:FindFirstChild("HumanoidRootPart")
			api.strike(player, model, "BolaInfernal", {
				damage = spec.damage,
				direction = api.flatUnit(root.Position - finish, api.flatUnit(dir)),
				knockback = spec.knockback,
				knockUp = spec.knockUp,
				launch = true,
				stun = spec.stun,
			}, api.synergyFor(player, model, "BolaInfernal"))
			api.burn(player, model, spec.burn)
		end
		local floor = api.floorBelow(player.Character, finish + Vector3.new(0, 1, 0))
		if floor and (finish - floor).Magnitude < 8 then
			burningGround(player, floor, spec.groundRadius, spec.groundTime)
			api.broadcast(player, "SueloArdiente", { center = floor, radius = spec.groundRadius, duration = spec.groundTime, serverDriven = true })
		end
		player:SetAttribute("UltimoEco", string.format("BolaInfernal:%d", #targets))
	end

	-- ---------- X · Estela Ardiente ----------
	H.estela_ardiente = function(player, t, position, look, aim)
		local spec = skills.EstelaArdiente
		local origin = api.begin(player, "EstelaArdiente", t, position, look)
		if not origin then
			return
		end
		local dir = api.aimDirection(aim, origin.LookVector, 0)
		local finish = api.dashEnd(player.Character, origin.Position, dir, spec.distance)
		api.broadcast(player, "EstelaArdiente", { origin = origin.Position, finish = finish, duration = spec.trailTime })
		local targets = api.pathTargets(player, origin.Position, finish, spec.width, t)
		for _, model in ipairs(targets) do
			api.strike(player, model, "EstelaArdiente", {
				damage = spec.damage,
				direction = dir,
				knockback = 8,
				stun = spec.stun,
			}, api.synergyFor(player, model, "EstelaArdiente"))
			api.burn(player, model, spec.burn)
		end
		-- El rastro sigue quemando a quien lo pise
		local from, to = origin.Position, finish
		api.zone(player, spec.trailTime, 0.5, function()
			for _, model in ipairs(api.pathTargets(player, from, to, spec.width, api.now())) do
				api.burn(player, model, 1)
			end
		end)
		player:SetAttribute("UltimoEco", string.format("EstelaArdiente:%d", #targets))
	end

	-- ---------- C · Puño Volcánico ----------
	H.puno_volcanico = function(player, t, position, look, aim)
		local spec = skills.PunoVolcanico
		local origin, feet, release = api.begin(player, "PunoVolcanico", t, position, look)
		if not origin then
			return
		end
		if feet > api.GROUND_FEET then
			release()
			return api.refuse(player, "puño en el aire")
		end
		local dir = api.aimDirection(aim, origin.LookVector, 0)
		local reachEnd = api.dashEnd(player.Character, origin.Position, dir, spec.lunge + spec.range)
		local fist = api.dashEnd(player.Character, origin.Position, dir, spec.lunge)
		api.broadcast(player, "PunoVolcanico", { center = fist + dir * 2 })
		-- Todo el recorrido del puño (la embestida y el golpe), con el ancho de la explosión
		local targets = api.pathTargets(player, origin.Position, reachEnd, spec.hitboxSize.X, t)
		for _, model in ipairs(targets) do
			api.strike(player, model, "PunoVolcanico", {
				damage = spec.damage,
				direction = dir,
				knockback = spec.knockback,
				knockUp = spec.knockUp,
				launch = true,
				stun = spec.stun,
			}, api.synergyFor(player, model, "PunoVolcanico"))
			api.burn(player, model, spec.burn)
		end
		player:SetAttribute("UltimoEco", string.format("PunoVolcanico:%d", #targets))
	end

	-- ---------- C en el aire · Meteoro ----------
	H.meteoro = function(player, t, position, look)
		local spec = skills.Meteoro
		local r = api.recordFor(player)
		r.pending = { kind = "meteor", t = t, clock = os.clock() }
		local origin, feet, release = api.begin(player, "Meteoro", t, position, look)
		if not origin then
			r.pending = nil
			return
		end
		if feet < spec.minHeight then
			r.pending = nil
			release()
			return api.refuse(player, "meteoro sin estar en el aire")
		end
		r.pending = nil
		r.meteor = { t = t, untilTime = t + spec.window, startY = origin.Position.Y, character = player.Character }
		api.broadcast(player, "Meteoro", { origin = origin.Position })
	end

	H.meteoro_impacto = function(player, t, position, look)
		local spec = skills.Meteoro
		local r = api.recordFor(player)
		local meteor = r.meteor or api.awaitPending(r, "meteor", "meteor")
		if not meteor or type(t) ~= "number" or t < meteor.t or t > meteor.untilTime or not api.PositionService.ValidTime(player, t) then
			return api.refuse(player, "impacto sin meteoro")
		end
		r.meteor = nil
		if player.Character ~= meteor.character then
			return api.refuse(player, "impacto con otro personaje")
		end
		api.PositionService.Report(player, t, position, look)
		local landing = api.PositionService.ConfirmedAt(player, t)
		if not landing then
			return api.refuse(player, "posición no confirmada")
		end
		if meteor.startY - landing.Position.Y < spec.minHeight * 0.5 or api.feetHeight(player.Character, landing.Position) > api.GROUND_FEET then
			return api.refuse(player, "impacto sin aterrizaje")
		end
		api.broadcast(player, "MeteoroImpacto", { origin = landing.Position })
		local targets = api.radiusTargets(player, landing.Position, spec.radius, 6, t)
		for _, model in ipairs(targets) do
			local root = model:FindFirstChild("HumanoidRootPart")
			api.strike(player, model, "Meteoro", {
				damage = spec.damage,
				direction = api.flatUnit(root.Position - landing.Position, api.flatUnit(landing.LookVector)),
				knockback = 30,
				knockUp = spec.knockUp,
				launch = true,
				stun = spec.stun,
			}, api.synergyFor(player, model, "Meteoro"))
			api.burn(player, model, spec.burn)
		end
		local floor = api.floorBelow(player.Character, landing.Position)
		if floor then
			burningGround(player, floor, spec.craterRadius, spec.craterTime)
			api.broadcast(player, "SueloArdiente", { center = floor, radius = spec.craterRadius, duration = spec.craterTime, serverDriven = true })
		end
		player:SetAttribute("UltimoEco", string.format("Meteoro:%d", #targets))
	end

	-- ---------- V · Infierno ----------
	H.infierno = function(player, t, position, look)
		local spec = skills.Infierno
		local origin, _, release = api.begin(player, "Infierno", t, position, look)
		if not origin then
			return
		end
		if not api.ResonanceService.Spend(player, spec.cost) then
			release()
			return api.refuse(player, "Resonancia insuficiente")
		end
		local center = origin.Position
		local untilTime = api.now() + spec.duration
		player:SetAttribute("InfiernoHasta", untilTime)
		api.broadcast(player, "Infierno", { center = center, radius = spec.radius, duration = spec.duration })
		local touched = {}
		local count = 0
		api.zone(player, spec.duration, spec.tick, function()
			for _, model in ipairs(api.radiusTargets(player, center, spec.radius, 8, api.now())) do
				if not touched[model] then
					touched[model] = true
					count += 1
				end
				api.strike(player, model, "Infierno", {
					damage = spec.tickDamage,
					direction = Vector3.new(0, 0, -1),
					knockback = 0,
					ignoreModifier = true,
					dot = true,
					noResonance = true,
				}, nil)
				api.burn(player, model, 1)
			end
			player:SetAttribute("UltimoEco", string.format("Infierno:%d", count))
		end)
		task.delay(spec.duration, function()
			if player:GetAttribute("InfiernoHasta") == untilTime then
				player:SetAttribute("InfiernoHasta", nil)
			end
		end)
		player:SetAttribute("UltimoEco", "Infierno:0")
	end

	return H
end
