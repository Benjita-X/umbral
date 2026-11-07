-- EcoService: las habilidades del Eco (EXPERIMENTAL, v2). Eco del Viento, una habilidad por tecla:
--   Z · Cuchilla: proyectil que vuela recto, atraviesa enemigos y se frena en las paredes. Aturde un instante.
--   X · Ciclón: atrae a los cercanos hasta tu frente y los aturde. En el aire: los sube hasta ti y flotan.
--   C · Levante: columna que lanza al aire (combo aéreo). En el aire, C es Descenso: picada que estampa a los
--       que flotan cerca y, al aterrizar, una onda que rebota a los enemigos hacia arriba.
--   V · Tempestad (definitiva): tornado que atrae, sostiene y golpea; al terminar estalla. Gasta Resonancia.
-- Las básicas (Z, X, C) solo tienen enfriamiento: salen siempre que estén listas.
--
-- Sinergias: una habilidad que conecta poco después de otra técnica en el MISMO enemigo forma un combo con
-- nombre (CombatConfig.Eco.Synergies): más daño, más lanzamiento o más aturdimiento, y da Resonancia.
--
-- Autoridad del servidor: el cliente solo pide la habilidad con su hora, su posición y hacia dónde apunta. El
-- servidor comprueba hora, aturdimiento, enfriamiento (por tecla, medido con la hora validada del pedido),
-- Resonancia (solo V), posición confirmada (PositionService) y suelo/aire, y calcula él mismo a quién alcanza
-- (cajas estándar y el historial observado: los enemigos donde los veía el jugador) y qué le pasa.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(shared:WaitForChild("Config"):WaitForChild("CombatConfig"))
local Hurtbox = require(shared:WaitForChild("Combat"):WaitForChild("Hurtbox"))
local services = script.Parent
local PositionService = require(services:WaitForChild("PositionService"))
local DefenseService = require(services:WaitForChild("DefenseService"))
local ResonanceService = require(services:WaitForChild("ResonanceService"))
local DamageService = require(services:WaitForChild("DamageService"))

local EcoService = {}

local eco = CombatConfig.Eco
local skills = eco.Skills
local COOLDOWN_SLACK = 0.05 -- s de margen al comparar horas de pedidos (las horas ya están validadas)
-- Suelo o aire, por la altura de los PIES sobre el suelo. El cliente elige la variante con 2,2 studs; el
-- servidor acepta con margen a cada lado (la posición confirmada puede diferir un poco de la del cliente):
-- así nunca se rechaza una habilidad bien pedida justo en el límite.
local AIR_FEET = 1 -- desde aquí se acepta una variante aérea
local GROUND_FEET = 3 -- hasta aquí se acepta una variante de suelo
local records = {} -- [player] = { cooldowns = { [tecla] = hora }, descent, lastHits = { [modelo] = { name, t } } }
local effectRemote = nil

-- Sinergias por habilidad que las completa
local SYNERGIES = {}
for _, synergy in ipairs(eco.Synergies) do
	SYNERGIES[synergy.next] = SYNERGIES[synergy.next] or {}
	table.insert(SYNERGIES[synergy.next], synergy)
end

local function now()
	return Workspace:GetServerTimeNow()
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function flatUnit(v, fallback)
	local f = flat(v)
	if f.Magnitude > 0.01 then
		return f.Unit
	end
	return fallback or Vector3.new(0, 0, -1)
end

local function recordFor(player)
	local r = records[player]
	if not r then
		r = { cooldowns = {}, descent = nil, swapUntil = nil, lastHits = setmetatable({}, { __mode = "k" }) }
		records[player] = r
	end
	return r
end

local function refuse(player, reason)
	player:SetAttribute("EcoRechazado", reason)
	player:SetAttribute("EcosRechazados", (player:GetAttribute("EcosRechazados") or 0) + 1)
end

-- "EcoCuchilla" → "Cuchilla"; los golpes del combo quedan igual ("Patada")
local function baseName(attackName)
	if type(attackName) ~= "string" then
		return ""
	end
	if string.sub(attackName, 1, 3) == "Eco" then
		return string.sub(attackName, 4)
	end
	return attackName
end

-- Eco que lleva puesto el jugador (kit de CombatConfig.Eco.Kits)
local function kitOf(player)
	local name = player:GetAttribute("Eco")
	return eco.Kits[name] or eco.Kits[eco.Default], name
end

-- ¿La habilidad está en el Eco que lleva puesto (en su tecla o como variante en el aire)?
local function equipped(player, skillName)
	local kit = kitOf(player)
	local slot = skills[skillName] and skills[skillName].slot
	return kit ~= nil and slot ~= nil and (kit.slots[slot] == skillName or (kit.air ~= nil and kit.air[slot] == skillName))
end

-- Comprobaciones comunes antes de usar una habilidad
-- Clave del enfriamiento: la tecla; las variantes en el aire (air = true) llevan el suyo ("Caire")
local function cooldownKey(spec)
	return if spec.air then spec.slot .. "aire" else spec.slot
end

local function canUse(player, skillName, t)
	local spec = skills[skillName]
	local r = recordFor(player)
	if not spec or not equipped(player, skillName) then
		return false, "habilidad de otro Eco"
	end
	if not PositionService.ValidTime(player, t) then
		return false, "hora inválida"
	end
	if r.swapUntil and t < r.swapUntil - COOLDOWN_SLACK then
		return false, "cambiando de Eco"
	end
	if DefenseService.IsStunned(player, DefenseService.Ping(player) + 0.1) then
		return false, "aturdido"
	end
	-- Enfriamiento por tecla, medido entre las horas (validadas) de los pedidos: la variación de la red no
	-- rechaza un uso legítimo justo al terminar el enfriamiento
	local last = r.cooldowns[cooldownKey(spec)]
	if last and t - last < spec.cooldown - COOLDOWN_SLACK then
		return false, "enfriamiento"
	end
	if (spec.cost or 0) > 0 and ResonanceService.Get(player) < spec.cost then
		return false, "Resonancia insuficiente"
	end
	return true
end

-- Reserva el enfriamiento ANTES de cualquier espera: dos pedidos en el mismo cuadro no pasan los dos
-- (hallazgo #1 de Codex). Devuelve una función para devolver la reserva si luego se rechaza.
local function reserve(player, slot, t)
	local r = recordFor(player)
	local previous = r.cooldowns[slot]
	r.cooldowns[slot] = t
	return function()
		if r.cooldowns[slot] == t then
			r.cooldowns[slot] = previous
		end
	end
end

-- Altura del centro del cuerpo sobre el suelo según el servidor (para saber si alguien está en el aire)
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true
local function heightAboveGround(character, position)
	groundParams.FilterDescendantsInstances = { character }
	local hit = Workspace:Raycast(position, Vector3.new(0, -60, 0), groundParams)
	return if hit then position.Y - hit.Position.Y else math.huge
end

-- Altura de los pies sobre el suelo (0 = de pie)
local function feetHeight(character, position)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local standing = (humanoid and humanoid.HipHeight or 2) + (root and root.Size.Y / 2 or 1)
	return heightAboveGround(character, position) - standing
end

local function floorBelow(model, position)
	groundParams.FilterDescendantsInstances = { model }
	local hit = Workspace:Raycast(position, Vector3.new(0, -80, 0), groundParams)
	return hit and hit.Position
end

local function attackerAt(player, t)
	local cframe = PositionService.ConfirmedAt(player, t)
	if not cframe and PositionService.Teleporting(player) and player.Character then
		cframe = PositionService.ObservedAt(player.Character, t)
	end
	return cframe
end

-- Objetivo válido: con raíz y, si es un enemigo, sin estar vencido
local function targetRoot(model)
	local root = model:IsDescendantOf(Workspace) and model:FindFirstChild("HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return nil
	end
	if humanoid.Health <= 0 and model:HasTag("Sparring") then
		return nil
	end
	return root
end

-- Quiénes cumplen `test` en el instante `t` (posiciones como las veía el jugador)
local function targetsIn(player, test, t)
	local list = {}
	local oneWay = PositionService.OneWay(player)
	for _, model in ipairs(CollectionService:GetTagged("Objetivo")) do
		local root = targetRoot(model)
		if root then
			local cframe = PositionService.ObservedAt(model, t - oneWay) or root.CFrame
			if test(cframe) then
				table.insert(list, model)
			end
		end
	end
	return list
end

-- Dirección de apuntado validada: unitaria y con la inclinación vertical acotada
local function aimDirection(aim, fallbackLook, maxPitchDegrees)
	local horizontalFallback = flatUnit(fallbackLook)
	if typeof(aim) ~= "Vector3" or aim ~= aim or aim.Magnitude < 0.01 then
		return horizontalFallback
	end
	local dir = aim.Unit
	local horizontal = flatUnit(dir, horizontalFallback)
	local limit = math.rad(maxPitchDegrees or 0)
	local pitch = math.clamp(math.asin(math.clamp(dir.Y, -1, 1)), -limit, limit)
	return (horizontal * math.cos(pitch) + Vector3.new(0, math.sin(pitch), 0)).Unit
end

local function synergyFor(player, model, skillName)
	local last = recordFor(player).lastHits[model]
	if not last then
		return nil
	end
	for _, synergy in ipairs(SYNERGIES[skillName] or {}) do
		if last.name == synergy.first and os.clock() - last.t <= synergy.window then
			return synergy
		end
	end
	return nil
end

-- Reacciones entre elementos (se definen más abajo, junto a la quemadura y las zonas)
local reactionFor, react

-- Aplica el golpe de una habilidad (con su sinergia, si la hay, y la reacción entre elementos). Devuelve el daño.
local function strike(player, model, skillName, spec, synergy)
	spec.attackName = "Eco" .. skillName
	local element = player:GetAttribute("Eco") or eco.Default
	local reaction = if reactionFor and not spec.dot then reactionFor(element, model) else nil
	if reaction and reaction.boost then
		spec.damage *= reaction.boost
		spec.stun = (spec.stun or 0) + (reaction.stun or 0)
	end
	if synergy then
		spec.damage *= synergy.damage or 1
		if spec.knockUp then
			spec.knockUp *= synergy.launch or 1
		end
		if spec.stun then
			spec.stun *= synergy.stun or 1
		end
		spec.synergy = synergy.name
	end
	if model:HasTag("Guardian") and spec.knockUp then
		spec.knockUp *= eco.GuardianLaunchScale
	end
	if reaction and not spec.synergy then
		spec.synergy = reaction.name -- se muestra igual que un combo con nombre
	end
	local dealt = DamageService.ApplyExternalHit(player, model, spec)
	if dealt > 0 and react and not spec.dot then
		react(player, model, element, reaction)
	end
	if synergy and dealt > 0 then
		player:SetAttribute("UltimaSinergia", synergy.name)
		player:SetAttribute("Sinergias", (player:GetAttribute("Sinergias") or 0) + 1)
		if model:HasTag("Sparring") then
			ResonanceService.Gain(player, "Sinergia", model, synergy.name)
		end
	end
	return dealt
end

-- Los demás jugadores ven la habilidad (quien la usa ya la vio al instante en su pantalla)
local function broadcast(player, skillName, data)
	if effectRemote then
		data.player = player
		data.skill = skillName
		effectRemote:FireAllClients(data)
	end
end

-- Prepara un pedido: comprobaciones, reserva, posición confirmada. Devuelve origen, altura de los pies, devolver
local function begin(player, skillName, t, position, look)
	local spec = skills[skillName]
	local ok, why = canUse(player, skillName, t)
	if not ok then
		refuse(player, why)
		return nil
	end
	local release = reserve(player, cooldownKey(spec), t)
	PositionService.Report(player, t, position, look)
	local origin = attackerAt(player, t)
	local character = player.Character
	if not origin or not character then
		release()
		refuse(player, "posición no confirmada")
		return nil
	end
	return origin, feetHeight(character, origin.Position), release
end

-- ---------- Herramientas comunes de los kits ----------
local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude
wallParams.RespectCanCollide = true

-- Primera pared (no un personaje) entre `from` y `from + segment`
local function wallBetween(character, from, segment)
	local ignore = { character }
	for _ = 1, 6 do
		wallParams.FilterDescendantsInstances = ignore
		local hit = Workspace:Raycast(from, segment, wallParams)
		if not hit then
			return nil
		end
		local model = hit.Instance:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChildOfClass("Humanoid") then
			table.insert(ignore, model) -- los personajes no frenan proyectiles ni embestidas: se atraviesan
		else
			return hit
		end
	end
	return nil
end

-- Proyectil simulado por el servidor desde la hora `t` del pedido: primero alcanza lo que ya recorrió mientras se
-- confirmaba la posición (con el historial: los enemigos donde los veía el jugador) y luego vuela cuadro a cuadro.
-- Se frena en las paredes. opts: start, dir, t, speed, range, reachX, reachY, pierce (atraviesa enemigos),
-- onHit(model) (al tocar a cada uno). Devuelve recorrido, posición final, si chocó con pared, si tocó a alguien.
local function projectile(player, opts)
	local character = player.Character
	local oneWay = PositionService.OneWay(player)
	local hitSet = {}
	local touched = false
	local function sweep(from, to, tFrom, tTo)
		local segment = to - from
		local wall = wallBetween(character, from, segment)
		local hitWall = false
		if wall then
			to = wall.Position - segment.Unit * 0.3
			segment = to - from
			hitWall = true
		end
		local lengthSq = segment:Dot(segment)
		local firstAlpha, firstModel = math.huge, nil
		for _, model in ipairs(CollectionService:GetTagged("Objetivo")) do
			local root = not hitSet[model] and targetRoot(model)
			if root then
				local alpha = if lengthSq > 1e-4 then math.clamp((root.Position - from):Dot(segment) / lengthSq, 0, 1) else 0
				local seen = PositionService.ObservedAt(model, tFrom + (tTo - tFrom) * alpha - oneWay)
				local position = if seen then seen.Position else root.Position
				alpha = if lengthSq > 1e-4 then math.clamp((position - from):Dot(segment) / lengthSq, 0, 1) else 0
				local offset = position - (from + segment * alpha)
				if flat(offset).Magnitude <= opts.reachX and math.abs(offset.Y) <= opts.reachY then
					if opts.pierce then
						hitSet[model] = true
						touched = true
						opts.onHit(model)
					elseif alpha < firstAlpha then
						firstAlpha, firstModel = alpha, model
					end
				end
			end
		end
		if firstModel then
			-- El primero que toca lo detiene ahí
			hitSet[firstModel] = true
			touched = true
			opts.onHit(firstModel)
			return from + segment * firstAlpha, true, false
		end
		return to, hitWall, hitWall
	end
	local start, dir, t = opts.start, opts.dir, opts.t
	local traveled = 0
	local position = start
	local stopped, hitWall = false, false
	local catchUp = math.clamp((now() - t) * opts.speed, 0, opts.range)
	if catchUp > 0 then
		position, stopped, hitWall = sweep(start, start + dir * catchUp, t, t + catchUp / opts.speed)
		traveled = (position - start).Magnitude
	end
	while not stopped and traveled < opts.range - 1e-3 and player.Parent do
		local dt = RunService.Heartbeat:Wait()
		local step = math.min(opts.speed * dt, opts.range - traveled)
		local tFrom = t + traveled / opts.speed
		local to
		to, stopped, hitWall = sweep(position, position + dir * step, tFrom, tFrom + step / opts.speed)
		traveled += (to - position).Magnitude
		position = to
	end
	return traveled, position, hitWall, touched
end

-- Quiénes están a lo largo de un tramo (embestidas): a menos de width/2 de la línea, en el instante t
local function pathTargets(player, from, to, width, t)
	local segment = flat(to - from)
	local lengthSq = segment:Dot(segment)
	return targetsIn(player, function(cframe)
		local p = cframe.Position
		local ap = flat(p - from)
		local alpha = if lengthSq > 1e-4 then math.clamp(ap:Dot(segment) / lengthSq, 0, 1) else 0
		local height = from.Y + (to.Y - from.Y) * alpha
		return (ap - segment * alpha).Magnitude <= width / 2 + Hurtbox.Size.X / 2 and math.abs(p.Y - height) <= 6
	end, t)
end

-- Quiénes están en un cono horizontal al frente
local function coneTargets(player, origin, forward, range, angleDegrees, t)
	local cosLimit = math.cos(math.rad(angleDegrees))
	return targetsIn(player, function(cframe)
		local offset = flat(cframe.Position - origin)
		local distance = offset.Magnitude
		if distance > range + Hurtbox.Size.X / 2 or math.abs(cframe.Position.Y - origin.Y) > 8 then
			return false
		end
		return distance < 2.5 or offset.Unit:Dot(forward) >= cosLimit
	end, t)
end

local function radiusTargets(player, center, radius, height, t)
	return targetsIn(player, function(cframe)
		return Hurtbox.InRadius(center, radius, cframe.Position, height or 6)
	end, t)
end

-- Final de una embestida de `distance` studs: se acorta antes de una pared (nunca la atraviesa)
local function dashEnd(character, from, dir, distance)
	local wall = wallBetween(character, from, dir * distance)
	if wall then
		distance = math.max(0, wall.Distance - 1.5)
	end
	return from + dir * distance, distance
end

-- Punto del suelo apuntado (aim = vector hacia el punto; su largo es la distancia), acotado al alcance y
-- nunca detrás de una pared
local function aimPoint(character, origin, aim, range)
	local dir = flatUnit(if typeof(aim) == "Vector3" and aim == aim then aim else origin.LookVector, flatUnit(origin.LookVector))
	local distance = if typeof(aim) == "Vector3" and aim == aim then math.clamp(flat(aim).Magnitude, 2, range) else range * 0.6
	local wall = wallBetween(character, origin.Position, dir * distance)
	if wall then
		distance = math.max(1, wall.Distance - 1.5)
	end
	local point = origin.Position + dir * distance
	local floor = floorBelow(character, point + Vector3.new(0, 2, 0))
	return (floor or point - Vector3.new(0, 3, 0)), dir
end

-- ---------- Estados y formas ----------
-- Quemadura: daño cada medio segundo mientras dure (sin empuje ni interrupción)
local burning = setmetatable({}, { __mode = "k" }) -- [modelo] = { untilTime, owner }
local function burn(player, model, duration)
	local entry = burning[model]
	if entry then
		entry.untilTime = math.max(entry.untilTime, os.clock() + duration)
		entry.owner = player
		model:SetAttribute("ArdeHasta", now() + (entry.untilTime - os.clock()))
		return
	end
	burning[model] = { untilTime = os.clock() + duration, owner = player }
	model:SetAttribute("ArdeHasta", now() + duration)
	task.spawn(function()
		while true do
			task.wait(eco.Burn.tick)
			local current = burning[model]
			if not current or os.clock() > current.untilTime or not targetRoot(model) or not current.owner.Parent then
				burning[model] = nil
				if model.Parent then
					model:SetAttribute("ArdeHasta", nil)
				end
				return
			end
			DamageService.ApplyExternalHit(current.owner, model, {
				attackName = "EcoQuemadura",
				damage = eco.Burn.damage,
				direction = Vector3.new(0, 0, -1),
				knockback = 0,
				knockUp = 0,
				ignoreModifier = true,
				dot = true,
				noResonance = true,
			})
		end
	end)
end

-- Marca de la Daga: el siguiente golpe del mismo jugador la detona
local marks = setmetatable({}, { __mode = "k" }) -- [modelo] = { owner, untilTime }
-- ---------- Reacciones entre elementos ----------
-- Agua deja al enemigo MOJADO (4 s) y Trueno, CARGADO (3 s); Fuego lo deja ARDIENDO (quemadura). Golpearlo con otro
-- elemento provoca una reacción con nombre: así cambiar de Eco a mitad de un combo tiene premio.
local REACTIONS = {
	Trueno = { state = "MojadoHasta", name = "ELECTROCUCIÓN", boost = 1.6, stun = 0.6, consume = true },
	Fuego = { state = "MojadoHasta", name = "VAPOR", consume = true },
	Viento = { state = "ArdeHasta", name = "TORMENTA ÍGNEA" },
	Oscuridad = { state = "CargadoHasta", name = "PULSO UMBRÍO", consume = true },
	Agua = { state = "CargadoHasta", name = "CONDUCCIÓN", consume = true },
}

reactionFor = function(element, model)
	local reaction = REACTIONS[element]
	if reaction and (model:GetAttribute(reaction.state) or 0) > now() then
		return reaction
	end
	return nil
end

react = function(player, model, element, reaction)
	local root = targetRoot(model)
	if not root then
		return
	end
	local t = now()
	if reaction then
		if reaction.consume then
			model:SetAttribute(reaction.state, nil)
		end
		player:SetAttribute("UltimaReaccion", reaction.name)
		player:SetAttribute("Reacciones", (player:GetAttribute("Reacciones") or 0) + 1)
		local center = root.Position
		broadcast(player, "Reaccion", { name = reaction.name, center = center, serverDriven = true })
		local function hit(target, damage, extra)
			local targetRootPart = targetRoot(target)
			if not targetRootPart then
				return
			end
			local spec = { attackName = "EcoReaccion", damage = damage, direction = flatUnit(targetRootPart.Position - center, Vector3.new(0, 0, -1)), knockback = 0, stun = 0.4, noResonance = true }
			for key, value in pairs(extra or {}) do
				spec[key] = value
			end
			DamageService.ApplyExternalHit(player, target, spec)
		end
		local others = {}
		for _, other in ipairs(radiusTargets(player, center, 10, 8, t)) do
			if other ~= model then
				table.insert(others, other)
			end
		end
		if reaction.name == "ELECTROCUCIÓN" then
			-- Un rayo salta al enemigo más cercano
			local nearest, best = nil, math.huge
			for _, other in ipairs(others) do
				local d = (targetRoot(other).Position - center).Magnitude
				if d < best then
					nearest, best = other, d
				end
			end
			if nearest then
				broadcast(player, "ReaccionRayo", { origin = center, finish = targetRoot(nearest).Position, serverDriven = true })
				hit(nearest, 5, { stun = 0.6 })
			end
		elseif reaction.name == "VAPOR" then
			-- Explosión de vapor: daña y empuja a todos los de alrededor (también al golpeado)
			hit(model, 4, { knockback = 26 })
			for _, other in ipairs(others) do
				if (targetRoot(other).Position - center).Magnitude <= 7 then
					hit(other, 6, { knockback = 30 })
				end
			end
		elseif reaction.name == "TORMENTA ÍGNEA" then
			-- El viento contagia el fuego a los cercanos
			for _, other in ipairs(others) do
				if (targetRoot(other).Position - center).Magnitude <= 9 then
					hit(other, 3, { stun = 0.3 })
					burn(player, other, 2.5)
				end
			end
		elseif reaction.name == "PULSO UMBRÍO" then
			-- Implosión: más daño al golpeado y los cercanos caen hacia él
			hit(model, 8, { stun = 0.8 })
			for index, other in ipairs(others) do
				if (targetRoot(other).Position - center).Magnitude <= 8 then
					local angle = index * 2.1
					hit(other, 3, { stun = 0.8, dragTo = center + Vector3.new(math.cos(angle) * 2.2, 0, math.sin(angle) * 2.2), dragTime = 0.2 })
				end
			end
		elseif reaction.name == "CONDUCCIÓN" then
			-- El agua reparte la carga: chispazos a todos los cercanos
			for _, other in ipairs(others) do
				broadcast(player, "ReaccionRayo", { origin = center, finish = targetRoot(other).Position, serverDriven = true })
				hit(other, 6, { stun = 0.6 })
			end
		end
	end
	-- Estados que deja cada elemento
	if element == "Agua" then
		model:SetAttribute("MojadoHasta", t + 4)
	elseif element == "Trueno" then
		model:SetAttribute("CargadoHasta", t + 3)
	end
end

local function mark(player, model, duration)
	marks[model] = { owner = player, untilTime = os.clock() + duration }
	model:SetAttribute("MarcadoHasta", now() + duration)
end

-- Formas temporales del jugador (definitivas): atributo <Nombre>Hasta con la hora del servidor
local function formActive(player, name)
	local untilTime = player:GetAttribute(name .. "Hasta")
	return type(untilTime) == "number" and now() <= untilTime
end

-- Curar al jugador poco a poco
local function healOverTime(player, amount, duration)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	task.spawn(function()
		local elapsed = 0
		while elapsed < duration and humanoid.Parent and humanoid.Health > 0 and player.Character == character do
			local dt = RunService.Heartbeat:Wait()
			elapsed += dt
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount / duration * dt)
		end
	end)
end

-- Zona que dura: llama a tick(i) cada `interval` s durante `duration` s (se corta si el jugador se va)
local function zone(player, duration, interval, tick)
	task.spawn(function()
		local count = math.floor(duration / interval + 1e-3)
		for i = 1, count do
			task.wait(interval)
			if not player.Parent then
				return
			end
			tick(i)
		end
	end)
end

-- ---------- Z · Cuchilla ----------
local function cuchilla(player, t, position, look, aim)
	local spec = skills.Cuchilla
	local origin, feet = begin(player, "Cuchilla", t, position, look)
	if not origin then
		return
	end
	local dir = aimDirection(aim, origin.LookVector, if feet >= AIR_FEET then spec.airMaxPitch else spec.maxPitch)
	local start = origin.Position + Vector3.new(0, 0.3, 0)
	broadcast(player, "Cuchilla", { origin = start, dir = dir })
	player:SetAttribute("UltimoEco", "Cuchilla:0")
	local knockDir = flatUnit(dir, flatUnit(origin.LookVector))
	local hits = 0
	local traveled = projectile(player, {
		start = start,
		dir = dir,
		t = t,
		speed = spec.speed,
		range = spec.range,
		reachX = spec.radius + Hurtbox.Size.X / 2, -- alcance horizontal desde la línea de vuelo
		reachY = spec.radius * 0.6 + Hurtbox.Size.Y / 2, -- alcance vertical (la cuchilla es más ancha que alta)
		pierce = true,
		onHit = function(model)
			hits += 1
			strike(player, model, "Cuchilla", {
				damage = spec.damage,
				direction = knockDir,
				knockback = spec.knockback,
				knockUp = spec.knockUp,
				stun = spec.stun,
			}, synergyFor(player, model, "Cuchilla"))
		end,
	})
	player:SetAttribute("UltimaCuchilla", math.floor(traveled * 10 + 0.5) / 10) -- recorrido (pruebas)
	player:SetAttribute("UltimoEco", string.format("Cuchilla:%d", hits))
	player:SetAttribute("CuchillasTerminadas", (player:GetAttribute("CuchillasTerminadas") or 0) + 1)
end

-- ---------- X · Ciclón ----------
local function ciclon(player, t, position, look, aim, wantsAir)
	local spec = skills.Ciclon
	local origin, feet = begin(player, "Ciclon", t, position, look)
	if not origin then
		return
	end
	-- Variante pedida por el cliente si es coherente con lo que ve el servidor; si no, la que ve el servidor
	local inAir
	if wantsAir == true then
		inAir = feet >= AIR_FEET
	else
		inAir = feet > GROUND_FEET
	end
	local forward = aimDirection(aim, origin.LookVector, 0)
	local center
	local targets
	if inAir then
		-- En el aire: los sube hasta ti (delante) y los deja flotando
		center = origin.Position + forward * 2.5
		targets = targetsIn(player, function(cframe)
			local offset = cframe.Position - origin.Position
			return flat(offset).Magnitude <= spec.radius + Hurtbox.Size.X / 2 and math.abs(offset.Y) <= spec.airHeight
		end, t)
	else
		center = origin.Position + forward * spec.pullTo
		targets = targetsIn(player, function(cframe)
			return Hurtbox.InRadius(origin.Position, spec.radius, cframe.Position, 7)
		end, t)
	end
	broadcast(player, "Ciclon", { center = center, air = inAir })
	for index, model in ipairs(targets) do
		local root = model:FindFirstChild("HumanoidRootPart")
		-- Quedan juntos frente a ti, un poco separados entre ellos (no encimados)
		local side = origin.RightVector * ((index - 1) % 3 - 1) * 1.6
		local point = center + side
		if not inAir then
			point = Vector3.new(point.X, root.Position.Y, point.Z) -- en el suelo solo los atrae (no los levanta)
		end
		local toCaster = flatUnit(origin.Position - root.Position, -forward)
		strike(player, model, "Ciclon", {
			damage = spec.damage,
			direction = toCaster,
			knockback = 0,
			knockUp = 0,
			ignoreModifier = true, -- el viento lo arrastra igual, con o sin coraza
			stun = if inAir then spec.airStun else spec.stun,
			dragTo = point,
			dragTime = 0.18,
			suspend = if inAir then spec.airSuspend else nil,
			suspendDelay = if inAir then 0.18 else nil,
			juggle = if inAir then spec.airSuspend + 0.6 else nil,
		}, synergyFor(player, model, "Ciclon"))
	end
	player:SetAttribute("UltimoEco", string.format("Ciclon:%d", #targets))
end

-- ---------- C · Levante ----------
local function levante(player, t, position, look, aim)
	local spec = skills.Levante
	local origin, feet, release = begin(player, "Levante", t, position, look)
	if not origin then
		return
	end
	-- Técnica de suelo: el servidor comprueba que estaba en el suelo (hallazgo #8 de Codex)
	if feet > GROUND_FEET then
		release()
		return refuse(player, "levante en el aire")
	end
	local forward = aimDirection(aim, origin.LookVector, 0)
	local aimCFrame = CFrame.lookAt(origin.Position, origin.Position + forward)
	local targets = targetsIn(player, function(cframe)
		return Hurtbox.AttackHits(aimCFrame, spec.range, spec.hitboxSize, cframe, CombatConfig.Validation.Tolerance)
	end, t)
	broadcast(player, "Levante", { center = origin.Position + forward * (spec.range * 0.5 + 0.5) })
	for _, model in ipairs(targets) do
		local synergy = synergyFor(player, model, "Levante")
		local launch = spec.knockUp * (synergy and synergy.launch or 1) * (if model:HasTag("Guardian") then eco.GuardianLaunchScale else 1)
		strike(player, model, "Levante", {
			damage = spec.damage,
			direction = forward,
			knockback = 0,
			knockUp = spec.knockUp,
			launch = true,
			stun = spec.stun,
			juggle = spec.juggle,
			suspend = spec.suspend,
			suspendDelay = launch / Workspace.Gravity, -- flota al llegar arriba
		}, synergy)
	end
	player:SetAttribute("UltimoEco", string.format("Levante:%d", #targets))
end

-- ---------- C en el aire · Descenso ----------
local function descenso(player, t, position, look)
	local spec = skills.Descenso
	local r = recordFor(player)
	r.pending = { kind = "descent", t = t, clock = os.clock() }
	local origin, feet, release = begin(player, "Descenso", t, position, look)
	if not origin then
		r.pending = nil
		return
	end
	-- Hay que estar en el aire (posición confirmada y lejos del suelo según el servidor): hallazgo #2
	if feet < spec.minHeight then
		r.pending = nil
		release()
		return refuse(player, "descenso sin estar en el aire")
	end
	r.pending = nil
	r.descent = { t = t, untilTime = t + spec.window, startY = origin.Position.Y, character = player.Character }
	broadcast(player, "Descenso", { origin = origin.Position })
	-- Los enemigos que flotan cerca caen contigo: se estampan contra el suelo. También el que golpeaste hace
	-- nada si sigue en el aire (aunque su "malabar" ya haya terminado): el remate del combo aéreo no falla por poco
	local lastHits = recordFor(player).lastHits
	for _, model in ipairs(CollectionService:GetTagged("Objetivo")) do
		local root = targetRoot(model)
		local distance = root and (root.Position - origin.Position).Magnitude or math.huge
		local recent = lastHits[model] ~= nil and os.clock() - lastHits[model].t <= 1.5
		local airborne = root ~= nil and heightAboveGround(model, root.Position) > 4
		if root and ((distance <= spec.spikeRadius and DamageService.IsJuggled(model)) or (recent and airborne and distance <= spec.spikeRadius * 1.6)) then
			local floor = floorBelow(model, root.Position)
			if floor then
				DamageService.Release(root)
				local humanoid = model:FindFirstChildOfClass("Humanoid")
				local standing = (humanoid and humanoid.HipHeight or 2) + root.Size.Y / 2
				DamageService.DragTo(root, Vector3.new(root.Position.X, floor.Y + standing, root.Position.Z), 0.2)
			end
		end
	end
end

-- Espera (acotado) a que termine de validarse un inicio de picada pendiente de ese tipo
local function awaitPending(r, kind, field)
	local deadline = os.clock() + 0.8
	while not r[field] and r.pending and r.pending.kind == kind and os.clock() < deadline do
		RunService.Heartbeat:Wait()
	end
	return r[field]
end
EcoService.AwaitPending = awaitPending

local function impacto(player, t, position, look)
	local spec = skills.Descenso
	local r = recordFor(player)
	local descent = r.descent or awaitPending(r, "descent", "descent")
	if not descent or type(t) ~= "number" or t < descent.t or t > descent.untilTime or not PositionService.ValidTime(player, t) then
		return refuse(player, "impacto sin descenso")
	end
	r.descent = nil
	if player.Character ~= descent.character then
		return refuse(player, "impacto con otro personaje")
	end
	PositionService.Report(player, t, position, look)
	local landing = attackerAt(player, t)
	if not landing then
		return refuse(player, "posición no confirmada")
	end
	-- Tiene que haber caído de verdad y estar en el suelo (no vale una onda en pleno aire ni sin bajar)
	if descent.startY - landing.Position.Y < spec.minHeight * 0.5 or feetHeight(player.Character, landing.Position) > GROUND_FEET then
		return refuse(player, "impacto sin aterrizaje")
	end
	local targets = targetsIn(player, function(cframe)
		return Hurtbox.InRadius(landing.Position, spec.radius, cframe.Position, 8)
	end, t)
	broadcast(player, "Impacto", { origin = landing.Position })
	for _, model in ipairs(targets) do
		local root = model:FindFirstChild("HumanoidRootPart")
		local away = flatUnit(root.Position - landing.Position, flatUnit(landing.LookVector))
		strike(player, model, "Descenso", {
			damage = spec.damage,
			direction = away,
			knockback = spec.knockback,
			knockUp = spec.knockUp,
			launch = true,
			stun = spec.stun,
			juggle = spec.juggle,
		}, synergyFor(player, model, "Descenso"))
	end
	player:SetAttribute("UltimoEco", string.format("Descenso:%d", #targets))
end

-- ---------- V · Tempestad ----------
local function tempestad(player, t, position, look, aim)
	local spec = skills.Tempestad
	local origin, _, release = begin(player, "Tempestad", t, position, look)
	if not origin then
		return
	end
	if not ResonanceService.Spend(player, spec.cost) then
		release()
		return refuse(player, "Resonancia insuficiente")
	end
	local forward = aimDirection(aim, origin.LookVector, 0)
	-- El tornado nace delante, pero nunca detrás de una pared
	local distance = spec.distance
	local wall = wallBetween(player.Character, origin.Position, forward * spec.distance)
	if wall then
		distance = math.max(0, wall.Distance - 2)
	end
	local center = origin.Position + forward * distance
	broadcast(player, "Tempestad", { center = center })
	player:SetAttribute("UltimoEco", "Tempestad:0")

	local touched = {} -- [modelo] = sinergia (o false): se decide al primer contacto y vale para todo el tornado
	local order = {} -- [modelo] = orden de llegada (su lugar en el anillo)
	local count = 0
	local function inside(model)
		local root = targetRoot(model)
		if not root then
			return nil
		end
		local offset = root.Position - center
		if flat(offset).Magnitude <= spec.radius + Hurtbox.Size.X / 2 and offset.Y > -6 and offset.Y < spec.holdHeight + 10 then
			return root
		end
		return nil
	end
	local ticks = math.floor(spec.duration / spec.tick)
	for i = 1, ticks do
		task.wait(spec.tick)
		if not player.Parent then
			return
		end
		for _, model in ipairs(CollectionService:GetTagged("Objetivo")) do
			local root = inside(model)
			if root then
				if touched[model] == nil then
					touched[model] = synergyFor(player, model, "Tempestad") or false
					count += 1
					order[model] = count
				end
				-- Giran alrededor del centro, sostenidos en el aire
				local angle = (i * 0.9) + (order[model] % 4) * (math.pi / 2)
				local ring = Vector3.new(math.cos(angle), 0, math.sin(angle)) * 2
				strike(player, model, "Tempestad", {
					damage = spec.tickDamage,
					direction = flatUnit(center - root.Position),
					knockback = 0,
					ignoreModifier = true,
					stun = spec.stun,
					dragTo = center + ring + Vector3.new(0, spec.holdHeight, 0),
					dragTime = 0.2,
					suspend = spec.tick + 0.15,
					suspendDelay = 0.2,
					juggle = 0.6,
					noResonance = true,
				}, touched[model] or nil)
			end
		end
	end
	-- Estallido final: los lanza hacia afuera y arriba
	for _, model in ipairs(CollectionService:GetTagged("Objetivo")) do
		local root = inside(model)
		if root then
			if touched[model] == nil then
				touched[model] = false
				count += 1
			end
			strike(player, model, "Tempestad", {
				damage = spec.finalDamage,
				direction = flatUnit(root.Position - center, forward),
				knockback = spec.finalKnockback,
				knockUp = spec.finalKnockUp,
				launch = true,
				ignoreModifier = true,
				stun = 0.8,
				juggle = 1.2,
				noResonance = true,
			}, touched[model] or nil)
		end
	end
	player:SetAttribute("UltimoEco", string.format("Tempestad:%d", count))
end

local ACTIONS = {
	cuchilla = cuchilla,
	ciclon = ciclon,
	levante = levante,
	descenso = descenso,
	impacto = impacto,
	tempestad = tempestad,
}

-- Lo que reciben los kits de EcoKits/ (cada módulo devuelve function(api) → { acción = función })
local api = {
	eco = eco,
	skills = skills,
	now = now,
	flat = flat,
	flatUnit = flatUnit,
	recordFor = recordFor,
	refuse = refuse,
	begin = begin,
	strike = strike,
	synergyFor = synergyFor,
	broadcast = broadcast,
	targetRoot = targetRoot,
	targetsIn = targetsIn,
	radiusTargets = radiusTargets,
	pathTargets = pathTargets,
	coneTargets = coneTargets,
	aimDirection = aimDirection,
	aimPoint = aimPoint,
	dashEnd = dashEnd,
	wallBetween = wallBetween,
	floorBelow = floorBelow,
	feetHeight = feetHeight,
	projectile = projectile,
	zone = zone,
	burn = burn,
	mark = mark,
	formActive = formActive,
	healOverTime = healOverTime,
	awaitPending = awaitPending,
	AIR_FEET = AIR_FEET,
	GROUND_FEET = GROUND_FEET,
	DamageService = DamageService,
	ResonanceService = ResonanceService,
	PositionService = PositionService,
	Hurtbox = Hurtbox,
	CombatConfig = CombatConfig,
}
EcoService.Api = api

local function loadKits()
	local folder = script.Parent:FindFirstChild("EcoKits")
	if not folder then
		return
	end
	for _, module in ipairs(folder:GetChildren()) do
		if module:IsA("ModuleScript") then
			local ok, handlers = pcall(function()
				return require(module)(api)
			end)
			if ok and type(handlers) == "table" then
				for action, handler in pairs(handlers) do
					ACTIONS[action] = handler
				end
			else
				warn("[UMBRAL] No se pudo cargar el kit " .. module.Name .. ": " .. tostring(handlers))
			end
		end
	end
end

-- Reacciones a los golpes: marcas que se detonan y formas que suman daño a los golpes del combo
local function onHitApplied(attacker, target, attackName)
	local entry = marks[target]
	local base = baseName(attackName)
	if entry and entry.owner == attacker and base ~= "Daga" and base ~= "Detonacion" and base ~= "Quemadura" and base ~= "CorteSombrio" and base ~= "Llamarada" then
		marks[target] = nil
		if target.Parent then
			target:SetAttribute("MarcadoHasta", nil)
		end
		if os.clock() <= entry.untilTime then
			task.defer(function()
				local root = targetRoot(target)
				if root then
					strike(attacker, target, "Detonacion", {
						damage = skills.Daga.detonate,
						direction = Vector3.new(0, 0, -1),
						knockback = 0,
						ignoreModifier = true,
						stun = 0.4,
					}, nil)
					-- Detonar la marca recarga el Paso Sombrío
					local r = recordFor(attacker)
					r.cooldowns.Z = nil
					attacker:SetAttribute("RecargasZ", (attacker:GetAttribute("RecargasZ") or 0) + 1)
				end
			end)
		end
	end
	if CombatConfig.Attacks[attackName] then
		if formActive(attacker, "Eclipse") then
			task.defer(strike, attacker, target, "CorteSombrio", { damage = skills.Eclipse.cut, direction = Vector3.new(0, 0, -1), knockback = 0, dot = true, ignoreModifier = true, noResonance = true }, nil)
		end
		if formActive(attacker, "Infierno") then
			burn(attacker, target, 2)
			task.defer(strike, attacker, target, "Llamarada", { damage = skills.Infierno.extra, direction = Vector3.new(0, 0, -1), knockback = 0, dot = true, ignoreModifier = true, noResonance = true }, nil)
		end
	end
end

-- Para pruebas y depuración: enfriamientos del servidor
function EcoService.ResetCooldowns(player)
	local r = records[player]
	if r then
		table.clear(r.cooldowns)
		r.descent = nil
		r.swapUntil = nil
	end
end

-- Cambia el Eco del jugador. Las 4 teclas quedan en espera SwapCooldown, contada desde `t` (la hora
-- sincronizada en que el jugador pulsó, si es válida; si no, desde que pulsó según su latencia).
-- Los enfriamientos son por tecla y se comparten entre Ecos: cambiar no da habilidades extra. Devuelve true si cambió.
function EcoService.Equip(player, name, t)
	if type(name) ~= "string" or not eco.Kits[name] then
		return false
	end
	if player:GetAttribute("Eco") == name then
		return true
	end
	local r = recordFor(player)
	local pressed = if PositionService.ValidTime(player, t) then math.min(t, now()) else now() - PositionService.OneWay(player)
	r.swapUntil = pressed + eco.SwapCooldown
	r.descent = nil
	player:SetAttribute("Eco", name)
	return true
end

function EcoService.Start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remote = Instance.new("RemoteEvent")
	remote.Name = "Eco"
	remote.Parent = remotes
	effectRemote = Instance.new("RemoteEvent")
	effectRemote.Name = "EcoEfecto"
	effectRemote.Parent = remotes
	local equipRemote = Instance.new("RemoteEvent")
	equipRemote.Name = "ElegirEco"
	equipRemote.Parent = remotes
	local lastEquip = {}
	equipRemote.OnServerEvent:Connect(function(player, name, t)
		local clock = os.clock()
		if clock - (lastEquip[player] or -math.huge) < 0.25 then
			return -- tope: cambiar de Eco no es algo que se haga 4 veces por segundo (el cliente los junta)
		end
		lastEquip[player] = clock
		EcoService.Equip(player, name, t)
	end)
	local function setup(player)
		if not eco.Kits[player:GetAttribute("Eco") or ""] then
			player:SetAttribute("Eco", eco.Default)
		end
	end
	Players.PlayerAdded:Connect(setup)
	for _, player in ipairs(Players:GetPlayers()) do
		setup(player)
	end

	loadKits()

	-- Último golpe de cada jugador a cada objetivo (combo o habilidad): base de las sinergias. Los daños de
	-- estado (quemadura, cortes extra) no cuentan: no rompen ni arman combos.
	DamageService.HitApplied:Connect(function(attacker, target, attackName, extra)
		if typeof(attacker) == "Instance" and attacker:IsA("Player") and typeof(target) == "Instance" then
			if not (type(extra) == "table" and extra.dot) then
				recordFor(attacker).lastHits[target] = { name = baseName(attackName), t = os.clock() }
			end
			onHitApplied(attacker, target, attackName)
		end
	end)

	local rate = {} -- [player] = { windowStart, count }
	remote.OnServerEvent:Connect(function(player, action, t, position, look, aim, wantsAir)
		-- Tope de mensajes: las habilidades tienen enfriamiento de segundos; más de 8 por segundo es basura
		local clock = os.clock()
		local rr = rate[player]
		if not rr or clock - rr.windowStart >= 1 then
			rr = { windowStart = clock, count = 0 }
			rate[player] = rr
		end
		rr.count += 1
		if rr.count > 8 then
			return
		end
		local handler = type(action) == "string" and ACTIONS[action]
		if handler then
			task.spawn(handler, player, t, position, look, aim, wantsAir)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		records[player] = nil
		rate[player] = nil
	end)
end

return EcoService
