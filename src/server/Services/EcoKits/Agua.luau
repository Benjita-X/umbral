-- Eco del Agua (EXPERIMENTAL): fluir, atrapar y sostener la vida.
--   Z Burbuja: proyectil lento que atrapa al primer enemigo y lo sube flotando dentro (combo aéreo).
--   X Oleaje: surfeas sobre una ola (te mueves tú, en tu pantalla) y arrastras a los del camino hasta el final.
--   C Géiser: en el punto apuntado; aviso y, un instante después, erupción que lanza.
--   V Diluvio (definitiva): gran ola frontal que barre y empuja; una lluvia te cura unos segundos.

return function(api)
	local skills = api.skills
	local Hurtbox = api.Hurtbox
	local H = {}

	local function guardianScale(model)
		return if model:HasTag("Guardian") then api.eco.GuardianLaunchScale else 1
	end

	-- ---------- Z · Burbuja ----------
	H.burbuja = function(player, t, position, look, aim)
		local spec = skills.Burbuja
		local origin, feet = api.begin(player, "Burbuja", t, position, look)
		if not origin then
			return
		end
		local dir = api.aimDirection(aim, origin.LookVector, if feet >= api.AIR_FEET then spec.airMaxPitch else spec.maxPitch)
		local start = origin.Position + Vector3.new(0, 0.3, 0)
		api.broadcast(player, "Burbuja", { origin = start, dir = dir })
		local caught = 0
		api.projectile(player, {
			start = start,
			dir = dir,
			t = t,
			speed = spec.speed,
			range = spec.range,
			reachX = spec.radius + Hurtbox.Size.X / 2,
			reachY = spec.radius + Hurtbox.Size.Y / 2,
			pierce = false,
			onHit = function(model)
				caught += 1
				local root = model:FindFirstChild("HumanoidRootPart")
				api.strike(player, model, "Burbuja", {
					damage = spec.damage,
					direction = api.flatUnit(dir),
					knockback = 0,
					ignoreModifier = true, -- la burbuja envuelve, con o sin coraza
					stun = spec.stun,
					dragTo = root.Position + Vector3.new(0, spec.lift, 0),
					dragTime = 0.25,
					suspend = spec.trap,
					suspendDelay = 0.25,
					juggle = spec.trap + 0.4,
				}, api.synergyFor(player, model, "Burbuja"))
			end,
		})
		player:SetAttribute("UltimoEco", string.format("Burbuja:%d", caught))
	end

	-- ---------- X · Oleaje ----------
	H.oleaje = function(player, t, position, look, aim)
		local spec = skills.Oleaje
		local origin = api.begin(player, "Oleaje", t, position, look)
		if not origin then
			return
		end
		local character = player.Character
		local dir = api.aimDirection(aim, origin.LookVector, 0)
		local finish = api.dashEnd(character, origin.Position, dir, spec.distance)
		api.broadcast(player, "Oleaje", { origin = origin.Position, finish = finish })
		local targets = api.pathTargets(player, origin.Position, finish, spec.width, t)
		-- Los arrastra hasta el final de la ola (un poco más allá de donde terminas tú)
		local drop = finish
		if not api.wallBetween(character, finish, dir * spec.carry) then
			drop = finish + dir * spec.carry
		end
		for index, model in ipairs(targets) do
			local root = model:FindFirstChild("HumanoidRootPart")
			local side = origin.RightVector * ((index - 1) % 3 - 1) * 1.8
			api.strike(player, model, "Oleaje", {
				damage = spec.damage,
				direction = dir,
				knockback = 0,
				ignoreModifier = true,
				stun = spec.stun,
				dragTo = Vector3.new(drop.X + side.X, root.Position.Y, drop.Z + side.Z),
				dragTime = spec.duration,
			}, api.synergyFor(player, model, "Oleaje"))
		end
		player:SetAttribute("UltimoEco", string.format("Oleaje:%d", #targets))
	end

	-- ---------- C · Géiser ----------
	H.geiser = function(player, t, position, look, aim)
		local spec = skills.Geiser
		local origin = api.begin(player, "Geiser", t, position, look)
		if not origin then
			return
		end
		local point = api.aimPoint(player.Character, origin, aim, spec.range)
		api.broadcast(player, "Geiser", { center = point })
		player:SetAttribute("UltimoEco", "Geiser:0")
		task.wait(spec.delay) -- el aviso: el círculo de agua antes de la erupción
		if not player.Parent then
			return
		end
		local targets = api.radiusTargets(player, point + Vector3.new(0, 3, 0), spec.radius, 7, api.now())
		for _, model in ipairs(targets) do
			local synergy = api.synergyFor(player, model, "Geiser")
			local launch = spec.knockUp * (synergy and synergy.launch or 1) * guardianScale(model)
			api.strike(player, model, "Geiser", {
				damage = spec.damage,
				direction = Vector3.new(0, 0, -1),
				knockback = 0,
				knockUp = spec.knockUp,
				launch = true,
				stun = spec.stun,
				juggle = spec.juggle,
				suspend = spec.suspend,
				suspendDelay = launch / workspace.Gravity,
			}, synergy)
		end
		player:SetAttribute("UltimoEco", string.format("Geiser:%d", #targets))
	end

	-- ---------- V · Diluvio ----------
	H.diluvio = function(player, t, position, look, aim)
		local spec = skills.Diluvio
		local origin, _, release = api.begin(player, "Diluvio", t, position, look)
		if not origin then
			return
		end
		if not api.ResonanceService.Spend(player, spec.cost) then
			release()
			return api.refuse(player, "Resonancia insuficiente")
		end
		local character = player.Character
		local dir = api.aimDirection(aim, origin.LookVector, 0)
		api.broadcast(player, "Diluvio", { origin = origin.Position, dir = dir })
		player:SetAttribute("UltimoEco", "Diluvio:0")
		api.healOverTime(player, spec.heal, spec.healTime)
		task.wait(spec.delay)
		if not player.Parent then
			return
		end
		local waveCFrame = CFrame.lookAt(origin.Position, origin.Position + dir)
		local size = Vector3.new(spec.width, 9, spec.length)
		local targets = api.targetsIn(player, function(cframe)
			return Hurtbox.AttackHits(waveCFrame, spec.length, size, cframe, 1)
				and api.wallBetween(character, origin.Position, cframe.Position - origin.Position) == nil
		end, api.now())
		for _, model in ipairs(targets) do
			api.strike(player, model, "Diluvio", {
				damage = spec.damage,
				direction = dir,
				knockback = spec.knockback,
				knockUp = spec.knockUp,
				launch = true,
				ignoreModifier = true,
				stun = spec.stun,
				noResonance = true,
			}, api.synergyFor(player, model, "Diluvio"))
		end
		player:SetAttribute("UltimoEco", string.format("Diluvio:%d", #targets))
	end

	return H
end
