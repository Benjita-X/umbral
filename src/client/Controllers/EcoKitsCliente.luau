-- EcoKitsCliente: cómo se lanzan en esta pantalla las habilidades de Agua, Oscuridad, Fuego infernal y Trueno
-- (EXPERIMENTAL). Cada una: apuntado, movimiento propio (embestidas, picadas), animación, efecto al instante y el
-- pedido al servidor, que decide daño y efectos. También cómo se ven las habilidades de otros jugadores y los
-- efectos que decide el servidor (rayos en cadena, chispazos del tótem, suelo ardiente...).
-- Lo usa EcoController: require(...)(api) → { casts, recasts, effects }.

return function(api)
	local skills = api.skills
	local E = api.EcoEfectos
	local T = E.Textures
	local movement = api.movement
	local casts, recasts, effects = {}, {}, {}

	local function sample()
		return api.PositionReporter.Sample()
	end
	local function chest(position)
		return position + Vector3.new(0, 0.3, 0)
	end

	-- Proyectil con orbe: burbuja, daga, bola de fuego
	local function throwOrb(action, spec, size, texture, onEnd)
		local t, position, look = sample()
		local air = api.inAir()
		local dir = api.aim(spec.range, true, if air then spec.airMaxPitch else spec.maxPitch)
		api.commitFacing(api.flat(dir), 0.25)
		api.fire(action, t, position, look, dir)
		api.playClip("EcoCuchilla")
		E.Tajo(chest(position) + api.flat(dir) * 0.6, dir, api.color(), 2.4, 25, { width = 0.7, sweep = 0.05, fade = 0.14 })
		E.Elemento(chest(position) + dir * 1.2, api.element(), 0.5)
		local start = chest(position) + dir * 1.5
		E.Orbe(start, dir, spec.speed, spec.range - 1.5, api.color(), size, texture, onEnd)
		if air then
			movement.AirStall(0.25)
		end
		api.shake(0.12)
	end

	-- Embestida propia (surf, sombra, fuego, rayo): el movimiento lo simula este cliente
	local function dash(dir, spec)
		movement.Lunge(dir, spec.distance / spec.duration, spec.duration, true)
	end

	-- ---------- Agua ----------
	casts.Burbuja = function(spec)
		throwOrb("burbuja", spec, 2.2, T.Sparks)
	end
	effects.Burbuja = function(data, color)
		E.Orbe(data.origin, data.dir, skills.Burbuja.speed, skills.Burbuja.range, color, 2.2, T.Sparks)
	end

	casts.Oleaje = function(spec)
		local t, position, look = sample()
		local dir = api.aim(spec.distance + 4, false)
		api.commitFacing(dir, spec.duration + 0.1)
		api.fire("oleaje", t, position, look, dir)
		api.playClip("Paso")
		dash(dir, spec)
		E.Ola(position, position + dir * api.freeDistance(position, dir, spec.distance), api.color(), spec.duration)
		E.Arco(position + dir * 1.5, dir, Vector3.yAxis, 2.6, -30, 150, api.color(), { width = 1.3, sweep = 0.12, fade = 0.3 })
		E.Elemento(position, "Agua", 1)
		api.shake(0.2)
	end
	effects.Oleaje = function(data, color)
		E.Ola(data.origin, data.finish, color, skills.Oleaje.duration)
	end

	casts.Geiser = function(spec)
		local t, position, look = sample()
		local point = api.aimPoint(spec.range)
		local toPoint = point - position
		api.commitFacing(api.flat(toPoint), 0.3)
		api.fire("geiser", t, position, look, toPoint)
		api.playClip("EcoLevante")
		local color = api.color()
		E.Geiser(point, color, spec.delay)
		task.delay(spec.delay, function()
			api.shake(0.3)
			local ground = E.Ground(point)
			E.OndaChoque(ground + Vector3.new(0, 0.3, 0), color, spec.radius * 1.2, Vector3.yAxis, 0.3)
			E.Elemento(ground + Vector3.new(0, 1, 0), "Agua", 2)
		end)
	end
	effects.Geiser = function(data, color)
		E.Geiser(data.center, color, skills.Geiser.delay)
	end

	casts.Diluvio = function(spec)
		local t, position, look = sample()
		local dir = api.aim(spec.length, false)
		api.commitFacing(dir, 0.5)
		api.fire("diluvio", t, position, look, dir)
		api.playClip("EcoTempestad")
		local color = api.color()
		E.Diluvio(position, dir, color, spec.delay)
		E.Lluvia(api.character(), color, spec.healTime)
		task.delay(spec.delay * 0.6, function()
			local right = dir:Cross(Vector3.yAxis)
			if right.Magnitude > 0.05 then
				E.Arco(position + dir * 3 + Vector3.new(0, 1, 0), dir, right.Unit, 6, -85, 85, color, { width = 2, sweep = 0.12, fade = 0.35 })
				E.Arco(position + dir * 5 + Vector3.new(0, 3, 0), dir, right.Unit, 7, -80, 80, color, { width = 1.6, sweep = 0.14, fade = 0.35 })
			end
			E.Elemento(position + dir * 6, "Agua", 2.5)
		end)
		api.shake(0.5)
	end
	effects.Diluvio = function(data, color)
		E.Diluvio(data.origin, data.dir, color, skills.Diluvio.delay)
		if typeof(data.player) == "Instance" then
			E.Lluvia(data.player.Character, color, skills.Diluvio.healTime)
		end
	end

	-- ---------- Oscuridad ----------
	casts.PasoSombrio = function(spec, slot)
		local t, position, look = sample()
		local dir = api.aim(spec.distance + 4, false)
		local distance = api.freeDistance(position, dir, spec.distance)
		E.Silueta(api.character(), api.color(), 0.5, 0.35)
		api.fire("paso_sombrio", t, position, look, dir)
		api.commitFacing(dir, spec.duration + 0.05)
		api.playClip("Paso")
		dash(dir, spec)
		E.Sombra(position, api.color(), spec.recastWindow)
		E.Rastro(position, position + dir * distance, api.color(), 1.5, 0.5, T.Smoke)
		E.Elemento(chest(position), "Oscuridad", 0.8)
		local color = api.color()
		task.delay(spec.duration, function()
			local root = api.rootPart()
			if root then
				E.Tajo(root.Position + Vector3.new(0, 0.4, 0), -dir, color, 3.6, 30, { width = 1.2, sweep = 0.06, fade = 0.22 })
			end
		end)
		E.Sound("Viento", position)
		api.openRecast(slot, "VueltaSombra", "VOLVER", { origin = position }, spec.recastWindow)
	end
	recasts.VueltaSombra = function(r)
		local root = api.rootPart()
		local spec = skills.PasoSombrio
		local back = api.flat(r.origin - root.Position)
		local distance = math.min(back.Magnitude, spec.returnMax)
		if distance < 0.5 then
			return
		end
		local speed = 150
		E.Silueta(api.character(), api.color(), 0.4, 0.4)
		movement.Face(back)
		movement.Lunge(back, speed, distance / speed, true)
		api.playClip("Paso")
		E.Sound("Viento", root.Position)
	end
	effects.PasoSombrio = function(data, color)
		E.Rastro(data.origin, data.finish, color, 1.5, 0.5, T.Smoke)
		E.Sombra(data.origin, color, skills.PasoSombrio.recastWindow)
	end

	casts.Daga = function(spec)
		throwOrb("daga", spec, 0.8, nil)
	end
	effects.Daga = function(data, color)
		E.Orbe(data.origin, data.dir, skills.Daga.speed, skills.Daga.range, color, 0.8, nil)
	end

	casts.Fauces = function(spec)
		local t, position, look = sample()
		local dir = api.aim(spec.range + 3, false)
		api.commitFacing(dir, 0.3)
		api.fire("fauces", t, position, look, dir)
		api.playClip("EcoEstela")
		E.Fauces(position, dir, api.color(), spec.range)
		E.Elemento(position + dir * spec.range * 0.6 + Vector3.new(0, 1, 0), "Oscuridad", 1.4)
		local right = dir:Cross(Vector3.yAxis)
		if right.Magnitude > 0.05 then
			-- Dos mandíbulas: un arco arriba y otro abajo que se cierran
			E.Arco(position + dir * 2 + Vector3.new(0, 1.6, 0), dir, Vector3.yAxis, spec.range * 0.45, 70, -10, api.color(), { width = 1.2, sweep = 0.08, fade = 0.2 })
			E.Arco(position + dir * 2 + Vector3.new(0, 0.4, 0), dir, -Vector3.yAxis, spec.range * 0.45, 70, -10, api.color(), { width = 1.2, sweep = 0.08, fade = 0.2 })
		end
		api.shake(0.25)
	end
	effects.Fauces = function(data, color)
		E.Fauces(data.origin, data.dir, color, skills.Fauces.range)
	end

	casts.Eclipse = function(spec)
		local t, position, look = sample()
		api.fire("eclipse", t, position, look, look)
		api.playClip("EcoTorbellino")
		E.Aura(api.character(), api.color(), spec.duration)
		E.Penumbra(spec.duration)
		E.Burst(position, api.color(), 30, 1, 30)
		E.Elemento(chest(position), "Oscuridad", 2.2)
		E.OndaChoque(E.Ground(position) + Vector3.new(0, 0.3, 0), api.color(), 8, Vector3.yAxis, 0.35)
		movement.SetSpeedBoost("eclipse", spec.speedBoost)
		task.delay(spec.duration, function()
			movement.SetSpeedBoost("eclipse", nil)
		end)
		api.shake(0.3)
	end
	effects.Eclipse = function(data, color)
		if typeof(data.player) == "Instance" then
			E.Aura(data.player.Character, color, skills.Eclipse.duration)
		end
	end
	effects.EclipseFin = function(data, color)
		E.Explosion(data.center, skills.Eclipse.burstRadius, color)
	end

	-- ---------- Fuego infernal ----------
	casts.BolaInfernal = function(spec)
		local color = api.color()
		throwOrb("bola_infernal", spec, 2, T.Fire, function(position)
			E.Explosion(position, spec.blast, color)
			E.Elemento(position, "Fuego", 1.5)
		end)
	end
	effects.BolaInfernal = function(data, color)
		local spec = skills.BolaInfernal
		E.Orbe(data.origin, data.dir, spec.speed, spec.range, color, 2, T.Fire, function(position)
			E.Explosion(position, spec.blast, color)
		end)
	end
	effects.SueloArdiente = function(data, color)
		E.Circulo(data.center, data.radius, color, data.duration, 0.65, T.Fire)
	end

	casts.EstelaArdiente = function(spec)
		local t, position, look = sample()
		local dir = api.aim(spec.distance + 4, false)
		local distance = api.freeDistance(position, dir, spec.distance)
		api.commitFacing(dir, spec.duration + 0.05)
		api.fire("estela_ardiente", t, position, look, dir)
		api.playClip("Paso")
		dash(dir, spec)
		E.Rastro(position, position + dir * distance, api.color(), spec.width, spec.trailTime, T.Fire)
		E.Elemento(position, "Fuego", 1.2)
		E.Sound("Estallido", position)
		api.shake(0.2)
	end
	effects.EstelaArdiente = function(data, color)
		E.Rastro(data.origin, data.finish, color, skills.EstelaArdiente.width, data.duration or skills.EstelaArdiente.trailTime, T.Fire)
	end

	casts.PunoVolcanico = function(spec)
		local t, position, look = sample()
		local dir = api.aim(spec.lunge + spec.range + 3, false)
		local color = api.color()
		api.commitFacing(dir, 0.4)
		api.fire("puno_volcanico", t, position, look, dir)
		api.playClip("EcoPuno")
		movement.Lunge(dir, spec.lunge / spec.duration, spec.duration, true)
		task.delay(spec.duration, function()
			local root = api.rootPart()
			if root then
				E.Explosion(root.Position + dir * 2.5, 4.5, color)
				E.Tajo(root.Position + dir * 1.5 + Vector3.new(0, 0.4, 0), dir, color, 2.6, 10, { width = 1.3, sweep = 0.04, fade = 0.18 })
				E.OndaChoque(root.Position + dir * 3, color, 5, dir, 0.25)
				E.Elemento(root.Position + dir * 2.5, "Fuego", 2)
				api.shake(0.4)
			end
		end)
	end
	effects.PunoVolcanico = function(data, color)
		E.Explosion(data.center, 4.5, color)
	end

	casts.Meteoro = function(spec)
		local t, position, look = sample()
		local aimDir = api.aim(45, true, spec.maxPitch)
		local h = api.flat(aimDir)
		h = if h.Magnitude > 0.01 then h.Unit else api.flat(look).Unit
		-- Siempre hacia abajo: entre 35° y maxPitch
		local pitch = math.clamp(math.asin(math.clamp(aimDir.Y, -1, 1)), -math.rad(spec.maxPitch), -math.rad(35))
		local diveDir = (h * math.cos(pitch) + Vector3.new(0, math.sin(pitch), 0)).Unit
		local color = api.color()
		api.fire("meteoro", t, position, look, diveDir)
		api.playClip("EcoDescenso")
		movement.Face(h)
		movement.Launch(diveDir * spec.speed)
		local vertical = math.max(spec.speed * math.abs(math.sin(pitch)), 1)
		movement.Lunge(h, spec.speed * math.cos(pitch), math.clamp(api.feetHeight() / vertical, 0.05, 0.5), true)
		local trail = E.Fire and E.Fire(api.rootPart(), color) or nil
		api.untilLanded(spec.window - 0.1, function(landing, tt, lk)
			if trail then
				trail.Enabled = false
			end
			api.fire("meteoro_impacto", tt, landing, lk)
			api.playClip("EcoAterrizaje")
			E.Explosion(landing, spec.radius, color)
			E.Elemento(landing + Vector3.new(0, 1, 0), "Fuego", 2.5)
			E.Rayas(landing, color, 10, 6)
			api.shake(0.6)
		end)
	end
	effects.Meteoro = function(data, color)
		E.Burst(data.origin, color, 20, 1, 20)
	end
	effects.MeteoroImpacto = function(data, color)
		E.Explosion(data.origin, skills.Meteoro.radius, color)
	end

	casts.Infierno = function(spec)
		local t, position, look = sample()
		api.fire("infierno", t, position, look, look)
		api.playClip("EcoTempestad")
		E.AnilloFuego(position, spec.radius, api.color(), spec.duration)
		E.Aura(api.character(), api.color(), spec.duration)
		api.shake(0.4)
	end
	effects.Infierno = function(data, color)
		E.AnilloFuego(data.center, data.radius or skills.Infierno.radius, color, data.duration or skills.Infierno.duration)
		if typeof(data.player) == "Instance" then
			E.Aura(data.player.Character, color, skills.Infierno.duration)
		end
	end

	-- ---------- Trueno ----------
	local predictedBolt = -math.huge
	casts.Rayo = function(spec)
		local t, position, look = sample()
		local dir, target = api.aim(spec.range, true, 70)
		api.commitFacing(api.flat(dir), 0.25)
		api.fire("rayo", t, position, look, dir)
		api.playClip("EcoCuchilla")
		local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
		if targetRoot then
			-- El primer tramo se ve al instante; los saltos los decide el servidor
			E.Rayo(chest(position), targetRoot.Position, api.color(), 0.4)
			predictedBolt = os.clock()
		end
		api.shake(0.15)
	end
	effects.RayoSalto = function(data, color, own)
		if own and data.jump == 0 and os.clock() - predictedBolt < 1 then
			return
		end
		E.Rayo(data.origin, data.finish, color, 0.4)
	end
	effects.RayoFallido = function(data, color)
		E.Rayo(data.origin, data.finish, color, 0.22)
	end

	casts.Relampago = function(spec)
		local t, position, look = sample()
		local dir = api.aim(spec.distance + 4, false)
		local distance = api.freeDistance(position, dir, spec.distance)
		E.Silueta(api.character(), api.color(), 0.35, 0.3)
		api.commitFacing(dir, spec.duration + 0.05)
		api.fire("relampago", t, position, look, dir)
		api.playClip("Paso")
		dash(dir, spec)
		E.Rayo(chest(position), chest(position) + dir * distance, api.color(), 0.6)
		E.Elemento(chest(position), "Trueno", 1)
		E.Elemento(chest(position) + dir * distance, "Trueno", 1)
		api.shake(0.25)
	end
	effects.Relampago = function(data, color)
		E.Rayo(chest(data.origin), chest(data.finish), color, 0.6)
	end

	casts.Pararrayos = function(spec)
		local t, position, look = sample()
		local point = api.aimPoint(spec.range)
		local toPoint = point - position
		api.commitFacing(api.flat(toPoint), 0.3)
		api.fire("pararrayos", t, position, look, toPoint)
		api.playClip("EcoLevante")
		E.Totem(point, api.color(), spec.duration)
		api.shake(0.2)
	end
	effects.Pararrayos = function(data, color)
		E.Totem(data.center, color, data.duration or skills.Pararrayos.duration)
	end
	effects.Chispazo = function(data, color)
		E.Rayo(data.origin, data.finish, color, 0.3)
	end

	casts.Juicio = function(spec)
		local t, position, look = sample()
		api.fire("juicio", t, position, look, look)
		api.playClip("EcoTempestad")
		E.Nube(position, api.color(), spec.strikes * spec.interval + 0.3)
		api.shake(0.3)
	end
	effects.Juicio = function(data, color)
		E.Nube(data.center, color, skills.Juicio.strikes * skills.Juicio.interval + 0.3)
	end
	effects.Rayazo = function(data, color)
		local top = data.finish + Vector3.new(math.random(-3, 3), 30, math.random(-3, 3))
		E.Rayo(top, data.finish, color, 0.8)
		E.Explosion(data.finish, 3, color)
		E.Elemento(data.finish, "Trueno", 1)
	end

	-- Los efectos de otros jugadores que se ven igual que los propios se reutilizan
	effects.Explosion = function() end -- la explosión ya la pinta el orbe al llegar (en todas las pantallas)

	return { casts = casts, recasts = recasts, effects = effects }
end
