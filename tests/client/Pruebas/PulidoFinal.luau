-- Pruebas de la fase de pulido final (movimiento y combate definitivos):
--   1. Búfer del Paso: pulsado en plena fase activa de un golpe sale al terminarla, con la dirección de la PULSACIÓN.
--   2. Intenciones: la última pulsada manda (el Paso reemplaza una habilidad guardada; Atacar reemplaza un Paso
--      guardado) y nada guardado sale por sorpresa.
--   3. Paso de combate: con un enemigo cerca delante, el Paso atrás no te gira; sin nadie cerca, sí.
--   4. Paredes: un Paso de refilón se desliza a lo largo de la pared; de frente se detiene sin atravesarla y el control
--      vuelve en el acto.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

return function(ctx)
	local Input, Combat, Movement = ctx.Input, ctx.Combat, ctx.Movement
	local record, waitUntil = ctx.record, ctx.waitUntil
	local controllers = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Controllers")
	local Eco = require(controllers:WaitForChild("EcoController"))
	local Intenciones = require(controllers:WaitForChild("Intenciones"))
	local OPEN = Vector3.new(0, 4, 150) -- zona abierta, sin enemigos cerca
	local function flat(v)
		return Vector3.new(v.X, 0, v.Z)
	end
	local function byName(name)
		for _, model in ipairs(CollectionService:GetTagged("Objetivo")) do
			if model.Name == name then
				return model
			end
		end
		return nil
	end
	local dashes = {}
	local used = {}
	local started = 0
	local connections = {
		Movement.Dashed:Connect(function(dir)
			table.insert(dashes, { dir = dir, t = os.clock() })
		end),
		Eco.Used:Connect(function(name)
			table.insert(used, name)
		end),
		Combat.AttackStarted:Connect(function()
			started += 1
		end),
	}
	local function waitActive()
		return waitUntil(function()
			local a = Combat.State.attack
			return a ~= nil and a.phase == "active"
		end, 0.5)
	end
	local function reset()
		ctx.humanoid:Move(Vector3.zero)
		ctx.remote:FireServer("reiniciar_eco")
		table.clear(Eco.State.cooldownEnd)
		table.clear(Eco.State.recast)
		ctx.waitForCharges()
		ctx.teleport(OPEN, Vector3.new(0, 0, 1))
		task.wait(0.35)
		ctx.settle()
	end

	-- ---------- 1. Búfer del Paso ----------
	reset()
	ctx.humanoid:Move(Vector3.new(1, 0, 0))
	task.wait()
	Input.Trigger("Atacar")
	local inActive = waitActive()
	local d0 = #dashes
	Input.Trigger("Paso") -- en plena fase activa: el Paso no puede salir todavía
	local dashedDuringActive = #dashes > d0
	ctx.humanoid:Move(Vector3.new(0, 0, 1)) -- la dirección cambia mientras espera: no debe importar
	waitUntil(function()
		return #dashes > d0
	end, 0.4)
	local dash = dashes[d0 + 1]
	ctx.humanoid:Move(Vector3.zero)
	record("[Pulido] Un Paso pulsado en la fase activa sale al terminarla, hacia donde apuntabas al pulsar",
		inActive and not dashedDuringActive and dash ~= nil and dash.dir:Dot(Vector3.new(1, 0, 0)) > 0.95,
		string.format("en fase activa %s · salió durante la fase %s · salió después %s · dirección %s", tostring(inActive), tostring(dashedDuringActive), tostring(dash ~= nil), if dash then string.format("(%.2f, %.2f)", dash.dir.X, dash.dir.Z) else "-"))
	task.wait(0.5)

	-- ---------- 2. Intenciones: la última pulsada manda ----------
	reset()
	local u0, d1 = #used, #dashes
	Input.Trigger("Atacar")
	waitActive()
	Input.Trigger("HabilidadZ") -- espera en cola (golpe en fase activa)
	local skillQueued = Eco.BufferedSlot() == "Z"
	Input.Trigger("Paso") -- decisión más nueva: el Paso (también espera)
	local replaced = Eco.BufferedSlot() == nil and Intenciones.Held() == "Paso"
	task.wait(0.6)
	local skillCast = false
	for i = u0 + 1, #used do
		if used[i] == Eco.SkillFor("Z", false) then
			skillCast = true
		end
	end
	record("[Pulido] Pulsar el Paso después de una habilidad en cola la reemplaza (la habilidad no sale por sorpresa)",
		skillQueued and replaced and not skillCast and #dashes > d1,
		string.format("habilidad en cola %s · reemplazada %s · salió igual %s · Paso dado %s", tostring(skillQueued), tostring(replaced), tostring(skillCast), tostring(#dashes > d1)))
	task.wait(0.4)

	reset()
	local d2, s0 = #dashes, started
	Input.Trigger("Atacar")
	waitActive()
	Input.Trigger("Paso") -- espera
	local dashQueued = Intenciones.Held() == "Paso"
	Input.Trigger("Atacar") -- decisión más nueva: otro golpe
	local attackHeld = Intenciones.Held() == "Atacar"
	task.wait(0.6)
	record("[Pulido] Pulsar Atacar después de un Paso en cola lo reemplaza",
		dashQueued and attackHeld and #dashes == d2 and started - s0 >= 2,
		string.format("Paso en cola %s · golpe guardado %s · Pasos dados %d · golpes %d", tostring(dashQueued), tostring(attackHeld), #dashes - d2, started - s0))
	task.wait(0.5)

	-- ---------- 3. Paso de combate ----------
	local dummy = byName("Muneco1")
	if dummy then
		local dummyRoot = dummy:WaitForChild("HumanoidRootPart")
		local look = flat(dummyRoot.CFrame.LookVector).Unit
		ctx.waitForCharges()
		ctx.teleport(Vector3.new(dummyRoot.Position.X, dummyRoot.Position.Y + 0.5, dummyRoot.Position.Z) + look * 6, -look)
		task.wait(0.35)
		ctx.settle()
		local start = ctx.root.Position
		ctx.humanoid:Move(look) -- atrás, alejándose del muñeco
		task.wait()
		Input.Trigger("Paso")
		task.wait(0.25)
		ctx.humanoid:Move(Vector3.zero)
		local facing = flat(ctx.root.CFrame.LookVector).Unit:Dot(flat(dummyRoot.Position - ctx.root.Position).Unit)
		local moved = flat(ctx.root.Position - start):Dot(look)
		record("[Pulido] Con un enemigo delante, el Paso atrás no te gira (sigues mirándolo)", facing > 0.85 and moved > 9,
			string.format("mira al muñeco %.2f · retrocedió %.1f studs", facing, moved))
		task.wait(0.4)
	else
		ctx.skip("[Pulido] Paso de combate", "falta Muneco1")
	end
	reset()
	ctx.humanoid:Move(Vector3.new(0, 0, -1)) -- atrás (mira a +Z), sin nadie cerca
	task.wait()
	Input.Trigger("Paso")
	task.wait(0.25)
	ctx.humanoid:Move(Vector3.zero)
	local turned = flat(ctx.root.CFrame.LookVector).Unit:Dot(Vector3.new(0, 0, -1))
	record("[Pulido] Sin enemigos cerca, el Paso atrás gira el cuerpo hacia donde vas", turned > 0.85, string.format("mira hacia el Paso %.2f", turned))
	task.wait(0.4)

	-- ---------- 4. Paredes ----------
	local WALL_FACE = 69 -- cara del muro del laboratorio (mira a -Z; va de x=-80 a x=-40)
	ctx.waitForCharges()
	ctx.teleport(Vector3.new(-60, 4, WALL_FACE - 6), Vector3.new(0, 0, 1))
	task.wait(0.35)
	ctx.settle()
	local before = ctx.root.Position
	ctx.humanoid:Move(Vector3.new(1, 0, 1).Unit) -- 45° contra el muro
	task.wait()
	Input.Trigger("Paso")
	task.wait(0.05)
	waitUntil(function()
		return not Movement.State.dashing
	end, 0.5)
	ctx.humanoid:Move(Vector3.zero) -- al terminar el Paso se suelta (si no, sigue caminando contra el muro)
	task.wait(0.1)
	local slid = ctx.root.Position.X - before.X
	record("[Pulido] Un Paso de refilón contra una pared se desliza a lo largo de ella",
		Movement.State.lastDashDistance >= 11 and slid >= 8 and ctx.root.Position.Z < WALL_FACE - 0.1,
		string.format("recorrió %.1f studs · avanzó %.1f en x · z final %.1f (muro en %d)", Movement.State.lastDashDistance, slid, ctx.root.Position.Z, WALL_FACE))
	task.wait(0.4)

	ctx.waitForCharges()
	ctx.teleport(Vector3.new(-60, 4, WALL_FACE - 6), Vector3.new(0, 0, 1))
	task.wait(0.35)
	ctx.settle()
	ctx.humanoid:Move(Vector3.new(0, 0, 1)) -- de frente
	task.wait()
	Input.Trigger("Paso")
	local free = waitUntil(function()
		return not Movement.State.dashing
	end, 0.4)
	ctx.humanoid:Move(Vector3.new(0, 0, -1)) -- y enseguida, alejarse
	local away = waitUntil(function()
		return ctx.root.AssemblyLinearVelocity.Z < -10
	end, 0.4)
	ctx.humanoid:Move(Vector3.zero)
	record("[Pulido] De frente contra una pared, el Paso se detiene sin atravesarla y el control vuelve en el acto",
		free and away and ctx.root.Position.Z < WALL_FACE - 0.3,
		string.format("Paso terminado %s · se alejó enseguida %s · z %.1f", tostring(free), tostring(away), ctx.root.Position.Z))
	task.wait(0.3)
	ctx.settle()

	-- ---------- 5. Cámara fijada con la espalda contra un muro ----------
	-- La cámara quiere ir detrás del jugador (dentro del muro): debe quedarse de este lado y sin nada en medio
	local Fijar = require(controllers:WaitForChild("FijarObjetivoController"))
	local m2 = byName("Muneco2")
	if m2 then
		local r2 = m2:WaitForChild("HumanoidRootPart")
		ctx.waitForCharges()
		ctx.teleport(Vector3.new(-60, 4, WALL_FACE - 3), Vector3.new(0, 0, -1))
		task.wait(0.2)
		-- El muñeco se coloca justo antes de fijarlo (si se queda quieto un rato, vuelve solo a su sitio)
		ctx.remote:FireServer("mover_muneco", "Muneco2", Vector3.new(-60, r2.Position.Y, WALL_FACE - 13))
		waitUntil(function()
			return (r2.Position - Vector3.new(-60, r2.Position.Y, WALL_FACE - 13)).Magnitude < 2
		end, 1)
		Fijar.LockOn(m2)
		local worst = -math.huge
		local blockedFrames = 0
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.RespectCanCollide = true
		local t0 = os.clock()
		while os.clock() - t0 < 0.6 do
			task.wait()
			local camPos = workspace.CurrentCamera.CFrame.Position
			worst = math.max(worst, camPos.Z)
			params.FilterDescendantsInstances = { ctx.player.Character, m2 }
			local pivot = ctx.root.Position + Vector3.new(0, 2.5, 0)
			if workspace:Raycast(pivot, camPos - pivot, params) then
				blockedFrames += 1
			end
		end
		local stillLocked = Fijar.Target() == m2
		Fijar.LockOn(nil)
		record("[Pulido] Con el enemigo fijado y la espalda contra un muro, la cámara nunca se mete en la pared",
			stillLocked and worst < WALL_FACE - 0.3 and blockedFrames == 0,
			string.format("fijado %s · cámara como mucho en z=%.2f (muro en %d) · cuadros con pared en medio %d", tostring(stillLocked), worst, WALL_FACE, blockedFrames))
		task.wait(0.3)
	else
		ctx.skip("[Pulido] Cámara contra un muro", "falta Muneco2")
	end

	-- ---------- 6. Golpe a una coraza: bloqueado al instante (misma regla que el servidor) ----------
	-- Un Centinela de mentira solo en esta pantalla: coraza delante, nada detrás, y aturdido no protege
	if Combat.PredictBlocked then
		local fake = Instance.new("Model")
		fake.Name = "CentinelaDePrueba"
		local fakeRoot = Instance.new("Part")
		fakeRoot.Name = "HumanoidRootPart"
		fakeRoot.Anchored = true
		fakeRoot.CanCollide = false
		fakeRoot.Transparency = 1
		fakeRoot.Size = Vector3.new(2, 2, 1)
		fakeRoot.Parent = fake
		Instance.new("Humanoid").Parent = fake
		fake:SetAttribute("Perfil", "centinela")
		fake.PrimaryPart = fakeRoot
		fake.Parent = workspace
		local me = ctx.root.Position
		fakeRoot.CFrame = CFrame.lookAt(me + Vector3.new(0, 0, -4), me) -- me mira a mí: estoy delante de su coraza
		local front = Combat.PredictBlocked(fake)
		fakeRoot.CFrame = CFrame.lookAt(me + Vector3.new(0, 0, -4), me + Vector3.new(0, 0, -10)) -- de espaldas a mí
		local back = Combat.PredictBlocked(fake)
		fakeRoot.CFrame = CFrame.lookAt(me + Vector3.new(0, 0, -4), me)
		fake:SetAttribute("Estado", "Aturdido")
		local stunned = Combat.PredictBlocked(fake)
		fake:Destroy()
		record("[Pulido] Un golpe a la coraza frontal se ve bloqueado al instante (de espaldas o aturdido, no)",
			front and not back and not stunned,
			string.format("de frente %s · por la espalda %s · aturdido %s", tostring(front), tostring(back), tostring(stunned)))
	end

	-- ---------- 7. Calidad de efectos ----------
	local Efectos = require(controllers:WaitForChild("EcoEfectos"))
	local previous = Efectos.Calidad
	local results = {}
	for _, level in ipairs({ "Alta", "Equilibrada", "Rendimiento" }) do
		Efectos.Calidad = level
		local ok = pcall(function()
			Efectos.Burst(ctx.root.Position + Vector3.new(0, 3, 0), Color3.new(1, 1, 1), 16, 0.6, 20)
		end)
		table.insert(results, string.format("%s: partículas ×%.1f · luces %s · recortado %s · %s", level, Efectos.Escala(), tostring(Efectos.Luces()), tostring(Efectos.Saturado()), if ok then "sin errores" else "ERROR"))
		results[level] = { scale = Efectos.Escala(), lights = Efectos.Luces(), saturated = Efectos.Saturado(), ok = ok }
	end
	Efectos.Calidad = previous
	record("[Pulido] Calidad de efectos: Alta, Equilibrada y Rendimiento recortan solo lo decorativo",
		results.Alta.scale == 1 and results.Alta.lights and results.Equilibrada.scale < 1 and results.Rendimiento.scale < results.Equilibrada.scale
			and not results.Rendimiento.lights and results.Rendimiento.saturated and results.Alta.ok and results.Equilibrada.ok and results.Rendimiento.ok,
		table.concat(results, " | "))

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
end
