-- Eco de la Oscuridad (EXPERIMENTAL): asesino, saltos de sombra y marcas.
--   Z Paso Sombrío: salto de sombra hacia donde apuntas (nunca atraviesa paredes); corta a quien cruzas.
--     Z otra vez en 2,5 s: vuelves a tu sombra (solo movimiento, en tu pantalla).
--   X Daga Marcada: proyectil que marca 4 s; el siguiente golpe tuyo al marcado lo detona (EcoService) y recarga Z.
--   C Fauces: cono al frente que inmoviliza; baja a los que flotan.
--   V Eclipse (definitiva): forma sombría; los ataques enemigos te atraviesan (SparringService), cada golpe del
--     combo suma un corte (EcoService) y al terminar estalla a tu alrededor.

return function(api)
	local skills = api.skills
	local Hurtbox = api.Hurtbox
	local DamageService = api.DamageService
	local H = {}

	-- ---------- Z · Paso Sombrío (ida) ----------
	H.paso_sombrio = function(player, t, position, look, aim)
		local spec = skills.PasoSombrio
		local origin = api.begin(player, "PasoSombrio", t, position, look)
		if not origin then
			return
		end
		local dir = api.aimDirection(aim, origin.LookVector, 0)
		local finish = api.dashEnd(player.Character, origin.Position, dir, spec.distance)
		api.broadcast(player, "PasoSombrio", { origin = origin.Position, finish = finish })
		local targets = api.pathTargets(player, origin.Position, finish, spec.width, t)
		for _, model in ipairs(targets) do
			api.strike(player, model, "PasoSombrio", {
				damage = spec.damage,
				direction = dir,
				knockback = 0,
				stun = spec.stun,
			}, api.synergyFor(player, model, "PasoSombrio"))
		end
		player:SetAttribute("UltimoEco", string.format("PasoSombrio:%d", #targets))
	end

	-- ---------- X · Daga Marcada ----------
	H.daga = function(player, t, position, look, aim)
		local spec = skills.Daga
		local origin, feet = api.begin(player, "Daga", t, position, look)
		if not origin then
			return
		end
		local dir = api.aimDirection(aim, origin.LookVector, if feet >= api.AIR_FEET then spec.airMaxPitch else spec.maxPitch)
		local start = origin.Position + Vector3.new(0, 0.3, 0)
		api.broadcast(player, "Daga", { origin = start, dir = dir })
		local marked = 0
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
				marked += 1
				api.strike(player, model, "Daga", {
					damage = spec.damage,
					direction = api.flatUnit(dir),
					knockback = 6,
					stun = spec.stun,
				}, api.synergyFor(player, model, "Daga"))
				api.mark(player, model, spec.mark)
			end,
		})
		player:SetAttribute("UltimoEco", string.format("Daga:%d", marked))
	end

	-- ---------- C · Fauces ----------
	H.fauces = function(player, t, position, look, aim)
		local spec = skills.Fauces
		local origin = api.begin(player, "Fauces", t, position, look)
		if not origin then
			return
		end
		local dir = api.aimDirection(aim, origin.LookVector, 0)
		api.broadcast(player, "Fauces", { origin = origin.Position, dir = dir })
		local targets = api.coneTargets(player, origin.Position, dir, spec.range, spec.angle, t)
		for _, model in ipairs(targets) do
			local root = model:FindFirstChild("HumanoidRootPart")
			-- A los que flotan, las fauces los bajan al suelo
			local dragTo = nil
			if DamageService.IsJuggled(model) then
				local floor = api.floorBelow(model, root.Position)
				local humanoid = model:FindFirstChildOfClass("Humanoid")
				if floor then
					DamageService.Release(root)
					dragTo = Vector3.new(root.Position.X, floor.Y + (humanoid and humanoid.HipHeight or 2) + root.Size.Y / 2, root.Position.Z)
				end
			end
			api.strike(player, model, "Fauces", {
				damage = spec.damage,
				direction = dir,
				knockback = 0,
				stun = spec.stun,
				dragTo = dragTo,
				dragTime = 0.18,
			}, api.synergyFor(player, model, "Fauces"))
		end
		player:SetAttribute("UltimoEco", string.format("Fauces:%d", #targets))
	end

	-- ---------- V · Eclipse ----------
	H.eclipse = function(player, t, position, look)
		local spec = skills.Eclipse
		local origin, _, release = api.begin(player, "Eclipse", t, position, look)
		if not origin then
			return
		end
		if not api.ResonanceService.Spend(player, spec.cost) then
			release()
			return api.refuse(player, "Resonancia insuficiente")
		end
		local untilTime = api.now() + spec.duration
		local caster = player.Character -- la forma pertenece a ESTE personaje (si muere y reaparece, se anula)
		player:SetAttribute("EclipseHasta", untilTime)
		api.broadcast(player, "Eclipse", { duration = spec.duration })
		player:SetAttribute("UltimoEco", "Eclipse:0")
		task.delay(spec.duration, function()
			local stillMine = player:GetAttribute("EclipseHasta") == untilTime
			if stillMine then
				player:SetAttribute("EclipseHasta", nil)
			end
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			-- Sin estallido si reapareció (otro personaje), murió o la forma se anuló o se renovó entretanto
			if not root or character ~= caster or not stillMine or not humanoid or humanoid.Health <= 0 then
				return
			end
			-- Estallido de sombra al terminar
			local center = root.Position
			api.broadcast(player, "EclipseFin", { center = center, serverDriven = true })
			local targets = api.radiusTargets(player, center, spec.burstRadius, 7, api.now())
			for _, model in ipairs(targets) do
				local targetRootPart = model:FindFirstChild("HumanoidRootPart")
				api.strike(player, model, "Eclipse", {
					damage = spec.burstDamage,
					direction = api.flatUnit(targetRootPart.Position - center),
					knockback = 35,
					knockUp = 12,
					launch = true,
					ignoreModifier = true,
					stun = spec.burstStun,
					noResonance = true,
				}, nil)
			end
			player:SetAttribute("UltimoEco", string.format("Eclipse:%d", #targets))
		end)
	end

	return H
end
