-- Eco del Trueno (EXPERIMENTAL): velocidad, cadenas y torretas.
--   Z Rayo: instantáneo al enemigo apuntado (con línea de visión); salta a los 2 más cercanos (cada salto, menos daño).
--   X Relámpago: te vuelves rayo y cruzas (te mueves tú); daña y aturde a todos en el camino.
--   C Pararrayos: tótem en el punto apuntado que electrocuta al enemigo más cercano cada medio segundo.
--   V Juicio (definitiva): rayos que caen sobre los enemigos a tu alrededor.

return function(api)
	local skills = api.skills
	local H = {}

	local function clearLine(character, from, to)
		return api.wallBetween(character, from, to - from) == nil
	end

	-- ---------- Z · Rayo en cadena ----------
	H.rayo = function(player, t, position, look, aim)
		local spec = skills.Rayo
		local origin = api.begin(player, "Rayo", t, position, look)
		if not origin then
			return
		end
		local character = player.Character
		local chest = origin.Position + Vector3.new(0, 0.3, 0)
		local dir = api.aimDirection(aim, origin.LookVector, 70)
		local oneWay = api.PositionService.OneWay(player)
		local cosLimit = math.cos(math.rad(spec.cone))
		-- Primer objetivo: el más cercano a la mira dentro del alcance (donde lo veía el jugador)
		local best, bestScore, bestPosition = nil, math.huge, nil
		local seen = {}
		for _, model in ipairs(game:GetService("CollectionService"):GetTagged("Objetivo")) do
			local root = api.targetRoot(model)
			if root then
				local cframe = api.PositionService.ObservedAt(model, t - oneWay) or root.CFrame
				seen[model] = cframe.Position
				local offset = cframe.Position - chest
				local distance = offset.Magnitude
				if distance <= spec.range and distance > 0.5 then
					local alignment = offset.Unit:Dot(dir)
					if alignment >= cosLimit and clearLine(character, chest, cframe.Position) then
						local score = (1 - alignment) * 40 + distance
						if score < bestScore then
							best, bestScore, bestPosition = model, score, cframe.Position
						end
					end
				end
			end
		end
		if not best then
			api.broadcast(player, "RayoFallido", { origin = chest, finish = chest + dir * spec.range * 0.6, serverDriven = true })
			player:SetAttribute("UltimoEco", "Rayo:0")
			return
		end
		local hitList = { [best] = true }
		local from = chest
		local current, currentPosition = best, bestPosition
		local damage = spec.damage
		local count = 0
		for jump = 0, spec.jumps do
			count += 1
			api.broadcast(player, "RayoSalto", { origin = from, finish = currentPosition, jump = jump, serverDriven = true })
			api.strike(player, current, "Rayo", {
				damage = damage,
				direction = api.flatUnit(currentPosition - from),
				knockback = 6,
				stun = spec.stun,
			}, if jump == 0 then api.synergyFor(player, current, "Rayo") else nil)
			damage *= spec.falloff
			-- Siguiente: el más cercano que no recibió el rayo
			local nextModel, nextPosition, nextDistance = nil, nil, spec.jumpRange
			for model, p in pairs(seen) do
				if not hitList[model] then
					local d = (p - currentPosition).Magnitude
					if d <= nextDistance and clearLine(character, currentPosition, p) then
						nextModel, nextPosition, nextDistance = model, p, d
					end
				end
			end
			if not nextModel then
				break
			end
			hitList[nextModel] = true
			from = currentPosition
			current, currentPosition = nextModel, nextPosition
		end
		player:SetAttribute("UltimoEco", string.format("Rayo:%d", count))
	end

	-- ---------- X · Relámpago ----------
	H.relampago = function(player, t, position, look, aim)
		local spec = skills.Relampago
		local origin = api.begin(player, "Relampago", t, position, look)
		if not origin then
			return
		end
		local dir = api.aimDirection(aim, origin.LookVector, 0)
		local finish = api.dashEnd(player.Character, origin.Position, dir, spec.distance)
		api.broadcast(player, "Relampago", { origin = origin.Position, finish = finish })
		local targets = api.pathTargets(player, origin.Position, finish, spec.width, t)
		for _, model in ipairs(targets) do
			api.strike(player, model, "Relampago", {
				damage = spec.damage,
				direction = dir,
				knockback = 10,
				stun = spec.stun,
			}, api.synergyFor(player, model, "Relampago"))
		end
		player:SetAttribute("UltimoEco", string.format("Relampago:%d", #targets))
	end

	-- ---------- C · Pararrayos ----------
	H.pararrayos = function(player, t, position, look, aim)
		local spec = skills.Pararrayos
		local origin = api.begin(player, "Pararrayos", t, position, look)
		if not origin then
			return
		end
		local character = player.Character
		local point = api.aimPoint(character, origin, aim, spec.range)
		local top = point + Vector3.new(0, 5, 0)
		api.broadcast(player, "Pararrayos", { center = point, duration = spec.duration })
		local zaps = 0
		player:SetAttribute("UltimoEco", "Pararrayos:0")
		api.zone(player, spec.duration, spec.tick, function()
			local best, bestDistance = nil, math.huge
			for _, model in ipairs(game:GetService("CollectionService"):GetTagged("Objetivo")) do
				local root = api.targetRoot(model)
				if root then
					local d = (root.Position - top).Magnitude
					if d <= spec.radius + 3 and d < bestDistance and clearLine(character, top, root.Position) then
						best, bestDistance = model, d
					end
				end
			end
			if best then
				zaps += 1
				local root = best:FindFirstChild("HumanoidRootPart")
				api.broadcast(player, "Chispazo", { origin = top, finish = root.Position, serverDriven = true })
				api.strike(player, best, "Pararrayos", {
					damage = spec.damage,
					direction = api.flatUnit(root.Position - top),
					knockback = 4,
					stun = spec.stun,
				}, api.synergyFor(player, best, "Pararrayos"))
				player:SetAttribute("UltimoEco", string.format("Pararrayos:%d", zaps))
			end
		end)
	end

	-- ---------- V · Juicio ----------
	H.juicio = function(player, t, position, look)
		local spec = skills.Juicio
		local origin, _, release = api.begin(player, "Juicio", t, position, look)
		if not origin then
			return
		end
		if not api.ResonanceService.Spend(player, spec.cost) then
			release()
			return api.refuse(player, "Resonancia insuficiente")
		end
		api.broadcast(player, "Juicio", { center = origin.Position })
		player:SetAttribute("UltimoEco", "Juicio:0")
		local struck = {}
		local count = 0
		local synergies = {}
		for _ = 1, spec.strikes do
			task.wait(spec.interval)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not root or not player.Parent then
				return
			end
			-- El enemigo cercano que menos rayos recibió. El rayo baja del nubarrón que está sobre ti: cae sobre quien
			-- se ve desde ti o desde la nube (por encima de una cobertura baja sí; dentro de otra sala techada, no)
			local best, bestScore = nil, math.huge
			local chest = root.Position + Vector3.new(0, 1, 0)
			local cloud = root.Position + Vector3.new(0, 14, 0)
			for _, model in ipairs(game:GetService("CollectionService"):GetTagged("Objetivo")) do
				local targetRootPart = api.targetRoot(model)
				if targetRootPart then
					local d = api.flat(targetRootPart.Position - root.Position).Magnitude
					if d <= spec.radius and (clearLine(character, chest, targetRootPart.Position) or clearLine(character, cloud, targetRootPart.Position)) then
						local score = (struck[model] or 0) * 100 + d
						if score < bestScore then
							best, bestScore = model, score
						end
					end
				end
			end
			if best then
				if struck[best] == nil then
					count += 1
					synergies[best] = api.synergyFor(player, best, "Juicio") or false
				end
				struck[best] = (struck[best] or 0) + 1
				local target = best:FindFirstChild("HumanoidRootPart").Position
				api.broadcast(player, "Rayazo", { finish = target, serverDriven = true })
				api.strike(player, best, "Juicio", {
					damage = spec.damage,
					direction = api.flatUnit(target - root.Position),
					knockback = 8,
					knockUp = spec.knockUp,
					launch = true,
					ignoreModifier = true,
					stun = spec.stun,
					noResonance = true,
				}, synergies[best] or nil)
				player:SetAttribute("UltimoEco", string.format("Juicio:%d", count))
			end
		end
	end

	return H
end
