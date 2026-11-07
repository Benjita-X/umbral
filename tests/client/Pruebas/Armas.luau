-- Suite de armas y golpes especiales (EXPERIMENTAL): Q cambia Puños ↔ Espada; golpe tras el Paso; picada.
-- Mide lo que decide el servidor (daño confirmado, rechazos) y que la espada se vea en la mano.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

return function(ctx)
	local Config, Input, Combat = ctx.CombatConfig, ctx.Input, ctx.Combat
	local record, waitUntil = ctx.record, ctx.waitUntil
	local player = ctx.player
	local attacks = Config.Attacks

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
		ctx.skip("[Armas] Suite de armas", "faltan los muñecos del Dojo")
		return
	end
	local function healthy(model)
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart")
		waitUntil(function()
			return humanoid.Health >= humanoid.MaxHealth and root.AssemblyLinearVelocity.Magnitude < 0.5
		end, 9)
		return humanoid, root
	end
	local function standFacing(model, distance)
		local root = model:WaitForChild("HumanoidRootPart")
		local look = root.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z).Unit
		local position = root.Position + flatLook * distance
		ctx.waitForCharges()
		ctx.teleport(Vector3.new(position.X, root.Position.Y + 0.5, position.Z), -flatLook)
		task.wait(Config.ComboResetTime + 0.1)
		return root
	end
	local function rejections()
		return player:GetAttribute("GolpesRechazados") or 0
	end

	-- ---------- 1. Q: a la Espada (el servidor la pone en la mano) ----------
	ctx.settle()
	Input.Trigger("Arma")
	local equipped = waitUntil(function()
		return player:GetAttribute("Arma") == "Espada" and player.Character:FindFirstChild("UmbralEspadaHoja") ~= nil
	end, 2)
	record("[Armas] Q cambia a la Espada (se ve en la mano)", equipped and Combat.State.weapon == "Espada", string.format("arma del servidor %s · hoja en la mano %s · arma del cliente %s", tostring(player:GetAttribute("Arma")), tostring(player.Character:FindFirstChild("UmbralEspadaHoja") ~= nil), tostring(Combat.State.weapon)))
	task.wait(Config.Weapons.SwitchTime + 0.1)

	-- ---------- 2. Combo de espada: Tajo → Revés → Estocada, desde más lejos que los puños ----------
	local h = healthy(m2)
	standFacing(m2, 6)
	local before = h.Health
	local r0 = rejections()
	Input.Trigger("Atacar")
	task.wait(0.12)
	Input.Trigger("Atacar")
	task.wait(0.14)
	Input.Trigger("Atacar")
	local expected = attacks.Tajo.damage + attacks.Reves.damage + attacks.Estocada.damage
	waitUntil(function()
		return before - h.Health >= expected - 0.05
	end, 2)
	task.wait(0.2)
	record("[Armas] Combo de espada: Tajo, Revés y Estocada", math.abs((before - h.Health) - expected) < 0.05 and rejections() == r0, string.format("%.1f de daño (objetivo %d) · rechazados %d · último %s", before - h.Health, expected, rejections() - r0, tostring(player:GetAttribute("UltimoRechazo"))))

	-- ---------- 3. Un golpe de otra arma se rechaza (el servidor sabe qué arma llevas) ----------
	ctx.settle()
	r0 = rejections()
	local start = ReplicatedStorage.Remotes:WaitForChild("InicioAtaque")
	local fakeSeq = Combat.State.sequence + 400
	start:FireServer(fakeSeq, "Jab", Workspace:GetServerTimeNow())
	waitUntil(function()
		return rejections() > r0
	end, 1.5)
	record("[Armas] Un golpe de otra arma se rechaza", player:GetAttribute("UltimoRechazo") == "golpe de otra arma", "motivo: " .. tostring(player:GetAttribute("UltimoRechazo")))
	Combat.State.sequence = fakeSeq + 10 -- la secuencia del cliente sigue por delante de la usada en la prueba

	-- ---------- 4. Volver a los Puños ----------
	Input.Trigger("Arma")
	local fists = waitUntil(function()
		return player:GetAttribute("Arma") == "Punos" and player.Character:FindFirstChild("UmbralEspadaHoja") == nil
	end, 2)
	record("[Armas] Q vuelve a los Puños (la espada se guarda)", fists and Combat.State.weapon == "Punos", string.format("arma %s", tostring(player:GetAttribute("Arma"))))
	task.wait(Config.Weapons.SwitchTime + 0.1)

	-- ---------- 5. Patada voladora: atacar justo después de un Paso ----------
	local hk, rootK = healthy(m1)
	standFacing(m1, 18)
	before = hk.Health
	r0 = rejections()
	local toward = Vector3.new(rootK.Position.X - ctx.root.Position.X, 0, rootK.Position.Z - ctx.root.Position.Z).Unit
	ctx.humanoid:Move(toward)
	task.wait()
	Input.Trigger("Paso")
	task.wait(0.16)
	Input.Trigger("Atacar")
	local kicked = Combat.State.attack and Combat.State.attack.name
	ctx.humanoid:Move(Vector3.zero)
	waitUntil(function()
		return hk.Health < before
	end, 1.5)
	task.wait(0.2)
	record("[Armas] Atacar tras el Paso: Patada voladora", kicked == "PatadaVoladora" and math.abs((before - hk.Health) - attacks.PatadaVoladora.damage) < 0.05 and rejections() == r0, string.format("golpe %s · %.1f de daño (objetivo %d) · rechazados %d (%s)", tostring(kicked), before - hk.Health, attacks.PatadaVoladora.damage, rejections() - r0, tostring(player:GetAttribute("UltimoRechazo"))))
	ctx.settle()

	-- ---------- 6. Patada en picada: atacar cayendo desde altura ----------
	local hp = healthy(m3)
	standFacing(m3, 3)
	before = hp.Health
	r0 = rejections()
	ctx.humanoid.Jump = true
	waitUntil(function()
		return not ctx.grounded() and ctx.root.AssemblyLinearVelocity.Y <= 2
	end, 1.5)
	Input.Trigger("Atacar")
	local plunged = Combat.State.attack and Combat.State.attack.name
	waitUntil(function()
		return hp.Health < before
	end, 1.5)
	task.wait(0.2)
	record("[Armas] Atacar cayendo desde altura: Patada en picada", plunged == "PatadaPicada" and math.abs((before - hp.Health) - attacks.PatadaPicada.damage) < 0.05 and rejections() == r0, string.format("golpe %s · %.1f de daño (objetivo %d) · rechazados %d (%s)", tostring(plunged), before - hp.Health, attacks.PatadaPicada.damage, rejections() - r0, tostring(player:GetAttribute("UltimoRechazo"))))
	ctx.settle()
	ctx.teleport(Vector3.new(0, 4, 30), Vector3.new(0, 0, 1))
end
