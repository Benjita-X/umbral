-- Suite del gancho (E) y de la postura enemiga con Golpe de Gracia (EXPERIMENTAL).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

return function(ctx)
	local Config, Input, Combat = ctx.CombatConfig, ctx.Input, ctx.Combat
	local record, waitUntil = ctx.record, ctx.waitUntil
	local player = ctx.player
	local controllers = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Controllers")
	local Gancho = require(controllers:WaitForChild("GanchoController"))

	local function byName(name)
		for _, model in ipairs(CollectionService:GetTagged("Objetivo")) do
			if model.Name == name then
				return model
			end
		end
		return nil
	end

	-- ---------- 1. Gancho a un punto de enganche ----------
	local anchor = nil
	for _, part in ipairs(Workspace:GetDescendants()) do
		if part:IsA("BasePart") and part.Name == "PuntoGancho" and (part.Position - Vector3.new(150, 18, 40)).Magnitude < 1 then
			anchor = part
		end
	end
	if anchor then
		ctx.waitForCharges()
		ctx.teleport(Vector3.new(150, 3.5, 20), Vector3.new(0, 0, 1))
		local y0 = ctx.root.Position.Y
		local ok = Gancho.GrappleTo(anchor)
		local closest, peak = math.huge, 0
		local t0 = os.clock()
		while os.clock() - t0 < 1.4 do
			task.wait()
			closest = math.min(closest, (ctx.root.Position - anchor.Position).Magnitude)
			peak = math.max(peak, ctx.root.Position.Y - y0)
		end
		record("[Gancho] E te lleva hasta el punto de enganche (y te impulsa al llegar)", ok and closest <= 4 and peak >= 12, string.format("enganchó %s · llegó a %.1f studs del punto · subió %.1f studs", tostring(ok), closest, peak))
		ctx.settle()
	else
		ctx.skip("[Gancho] Punto de enganche", "no hay punto de enganche en la zona de pruebas")
	end

	-- ---------- 2. Gancho a un enemigo: quedas frente a él y el siguiente golpe es la patada voladora ----------
	local dummy = byName("Muneco1")
	if dummy then
		local root = dummy:WaitForChild("HumanoidRootPart")
		local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
		task.wait(0.9) -- enfriamiento del gancho
		ctx.waitForCharges()
		local start = root.Position + look * 20
		ctx.teleport(Vector3.new(start.X, root.Position.Y + 0.5, start.Z), -look)
		local ok = Gancho.GrappleTo(dummy)
		waitUntil(function()
			return not ctx.Movement.State.grappling
		end, 1.5)
		task.wait(0.05)
		local distance = Vector3.new(ctx.root.Position.X - root.Position.X, 0, ctx.root.Position.Z - root.Position.Z).Magnitude
		local dummyHumanoid = dummy:FindFirstChildOfClass("Humanoid")
		local before = dummyHumanoid.Health
		local rejected0 = player:GetAttribute("GolpesRechazados") or 0
		local reasons = {}
		local reasonConnection = player:GetAttributeChangedSignal("UltimoRechazo"):Connect(function()
			table.insert(reasons, tostring(player:GetAttribute("UltimoRechazo")))
		end)
		Input.Trigger("Atacar")
		local attackName = Combat.State.attack and Combat.State.attack.name
		waitUntil(function()
			return dummyHumanoid.Health < before
		end, 1.2)
		local dealt = before - dummyHumanoid.Health
		local rejected = (player:GetAttribute("GolpesRechazados") or 0) - rejected0
		reasonConnection:Disconnect()
		record("[Gancho] Engancharse a un enemigo te deja frente a él y abre la patada voladora", ok and distance <= 4.5 and attackName == "PatadaVoladora" and math.abs(dealt - Config.Attacks.PatadaVoladora.damage) < 0.05 and rejected == 0, string.format("enganchó %s · quedaste a %.1f studs · golpe siguiente %s · %.1f de daño · rechazados %d (%s)", tostring(ok), distance, tostring(attackName), dealt, rejected, if #reasons > 0 then table.concat(reasons, " → ") else tostring(player:GetAttribute("UltimoRechazo"))))
		ctx.settle()
	end

	-- ---------- 3. Postura enemiga: los golpes la llenan ----------
	local partner = CollectionService:GetTagged("Companero")[1]
	if partner and partner:GetAttribute("PosturaMax") then
		local proot = partner:WaitForChild("HumanoidRootPart")
		local phum = partner:FindFirstChildOfClass("Humanoid")
		ctx.remote:FireServer("reiniciar_defensa")
		ctx.remote:FireServer("vida_enemigo", { tag = "Companero", value = phum.MaxHealth })
		ctx.remote:FireServer("postura", { tag = "Companero", value = 0 })
		task.wait(0.3)
		local plook = Vector3.new(proot.CFrame.LookVector.X, 0, proot.CFrame.LookVector.Z).Unit
		local near = proot.Position + plook * 3.2
		ctx.waitForCharges()
		ctx.teleport(Vector3.new(near.X, proot.Position.Y + 0.5, near.Z), -plook)
		local p0 = partner:GetAttribute("Postura") or 0
		Input.Trigger("Atacar")
		waitUntil(function()
			return (partner:GetAttribute("Postura") or 0) > p0
		end, 1.5)
		local gained = (partner:GetAttribute("Postura") or 0) - p0
		record("[Postura] Tus golpes llenan la postura del enemigo", gained >= Config.Attacks.Jab.posture * Config.EnemyPosture.Gains.ComboScale - 0.1, string.format("postura +%.1f (Jab: %.1f)", gained, Config.Attacks.Jab.posture * Config.EnemyPosture.Gains.ComboScale))
		ctx.settle()

		-- ---------- 4. Postura llena: QUEBRADO, y atacar cerca hace el Golpe de Gracia ----------
		ctx.remote:FireServer("reiniciar_defensa")
		ctx.remote:FireServer("vida_enemigo", { tag = "Companero", value = phum.MaxHealth })
		task.wait(0.2)
		ctx.remote:FireServer("postura", { tag = "Companero", value = partner:GetAttribute("PosturaMax") })
		local brokenOk = waitUntil(function()
			return (partner:GetAttribute("QuebradoHasta") or 0) > Workspace:GetServerTimeNow()
		end, 1.5)
		near = proot.Position + Vector3.new(proot.CFrame.LookVector.X, 0, proot.CFrame.LookVector.Z).Unit * 5
		ctx.teleport(Vector3.new(near.X, proot.Position.Y + 0.5, near.Z), Vector3.new(proot.Position.X - near.X, 0, proot.Position.Z - near.Z).Unit)
		local before = phum.Health
		local executions = player:GetAttribute("GolpesDeGracia") or 0
		Input.Trigger("Atacar")
		local mode = Combat.State.mode
		waitUntil(function()
			return (player:GetAttribute("GolpesDeGracia") or 0) > executions
		end, 1.5)
		task.wait(0.2)
		local dealt = before - phum.Health
		local expected = math.max(Config.EnemyPosture.Execute.minDamage, phum.MaxHealth * Config.EnemyPosture.Execute.damageRatio)
		record("[Postura] Postura llena: QUEBRADO y Golpe de Gracia al atacar cerca", brokenOk and mode == "Gracia" and math.abs(dealt - expected) < 0.5, string.format("quebrado %s · modo %s · %.1f de daño (objetivo %.0f) · rechazo %s", tostring(brokenOk), tostring(mode), dealt, expected, tostring(player:GetAttribute("UltimoRechazo"))))
		ctx.remote:FireServer("vida_enemigo", { tag = "Companero", value = phum.MaxHealth })
		ctx.remote:FireServer("reiniciar_defensa")
		ctx.settle()
	else
		ctx.skip("[Postura] Postura enemiga", "no hay compañero de combate con postura")
	end
	-- ---------- 5. Fijar enemigo (R): la cámara lo sigue y el personaje lo encara ----------
	local Fijar = require(controllers:WaitForChild("FijarObjetivoController"))
	local lockDummy = byName("Muneco2")
	if lockDummy then
		local lroot = lockDummy:WaitForChild("HumanoidRootPart")
		ctx.waitForCharges()
		-- De costado al muñeco, a 10 studs
		ctx.teleport(Vector3.new(lroot.Position.X - 10, lroot.Position.Y + 0.5, lroot.Position.Z), Vector3.new(0, 0, 1))
		local locked = Fijar.LockOn(lockDummy)
		task.wait(0.6)
		local toDummy = Vector3.new(lroot.Position.X - ctx.root.Position.X, 0, lroot.Position.Z - ctx.root.Position.Z).Unit
		local look = ctx.root.CFrame.LookVector
		local facing = Vector3.new(look.X, 0, look.Z).Unit:Dot(toDummy)
		local cameraType = Workspace.CurrentCamera.CameraType
		local desired = ctx.Movement.DesiredDirection():Dot(toDummy)
		Fijar.LockOn(nil)
		task.wait(0.1)
		record(
			"[Fijar] R fija al enemigo: la cámara lo sigue y el personaje lo encara",
			locked and facing > 0.95 and desired > 0.95 and cameraType == Enum.CameraType.Scriptable and Workspace.CurrentCamera.CameraType == Enum.CameraType.Custom,
			string.format("fijado %s · encarado %.2f · dirección de golpe %.2f · cámara %s → %s al soltar", tostring(locked), facing, desired, cameraType.Name, Workspace.CurrentCamera.CameraType.Name)
		)
	end
	ctx.teleport(Vector3.new(0, 4, 30), Vector3.new(0, 0, 1))
end
