-- Suite de pruebas del movimiento (Fase 1).

local Workspace = game:GetService("Workspace")

return function(ctx)
	local Config, Input, Movement = ctx.MovementConfig, ctx.Input, ctx.Movement
	local record, near, waitUntil = ctx.record, ctx.near, ctx.waitUntil
	local forward = Vector3.new(0, 0, 1)
	local camera = Workspace.CurrentCamera

	local dashCount = 0
	local dashConnection = Movement.Dashed:Connect(function()
		dashCount += 1
	end)

	record("Arranque", true, "personaje listo")
	record("Rig R15", ctx.humanoid.RigType == Enum.HumanoidRigType.R15, "RigType = " .. ctx.humanoid.RigType.Name)
	record("Gravedad", near(Workspace.Gravity, Config.Gravity, 0.01), string.format("%.1f (objetivo %.1f)", Workspace.Gravity, Config.Gravity))

	-- 1. Carrera, sprint automático y FOV
	ctx.teleport(Vector3.new(0, 4, 30), forward)
	ctx.humanoid:Move(forward)
	task.wait(0.25)
	local runSpeed = ctx.flatSpeed()
	record("Velocidad de carrera", near(runSpeed, Config.RunSpeed, 1.5), string.format("%.1f studs/s (objetivo %d)", runSpeed, Config.RunSpeed))
	local t0 = os.clock()
	waitUntil(function()
		return Movement.State.sprinting
	end, 2)
	local sprintAt = os.clock() - t0 + 0.25
	record("Sprint automático", Movement.State.sprinting and near(sprintAt, Config.SprintDelay, 0.1), string.format("entra a los %.2f s (objetivo %.2f)", sprintAt, Config.SprintDelay))
	task.wait(Config.SprintRampTime + 0.35)
	local sprintSpeed = ctx.flatSpeed()
	record("Velocidad de sprint", near(sprintSpeed, Config.SprintSpeed, 1.5), string.format("%.1f studs/s (objetivo %d)", sprintSpeed, Config.SprintSpeed))
	local fov = camera.FieldOfView
	if ctx.isRendering() then
		record("FOV en sprint", fov > Config.SprintFOV - 2, string.format("%.1f° (objetivo ~%d°)", fov, Config.SprintFOV))
	else
		ctx.skip("FOV en sprint", "la ventana de Studio no está dibujando (está en segundo plano)")
	end

	-- 2. Frenado
	ctx.humanoid:Move(Vector3.zero)
	local tStop = os.clock()
	waitUntil(function()
		return ctx.flatSpeed() < 1
	end, 1)
	local stopTime = os.clock() - tStop
	record("Frenado", stopTime < 0.15, string.format("se detiene en %.2f s", stopTime))

	-- 3. Paso en el suelo y salida en sprint
	ctx.settle()
	ctx.waitForCharges()
	ctx.teleport(Vector3.new(0, 4, 30), forward)
	ctx.humanoid:Move(forward)
	task.wait(0.3)
	local before = dashCount
	local peakDash = 0
	local tDash = os.clock()
	Input.Trigger("Paso")
	waitUntil(function()
		peakDash = math.max(peakDash, ctx.flatSpeed())
		return os.clock() - tDash > 0.05 and not Movement.State.dashing
	end, 1)
	record(
		"Paso en el suelo",
		dashCount == before + 1 and near(Movement.State.lastDashDistance, Config.DashDistance, 0.6),
		string.format("%.1f studs (objetivo %d), pico %.0f studs/s", Movement.State.lastDashDistance, Config.DashDistance, peakDash)
	)
	task.wait(0.15)
	record(
		"Salida del Paso en sprint",
		Movement.State.sprinting and near(ctx.flatSpeed(), Config.SprintSpeed, 3),
		string.format("sprint = %s, %.1f studs/s", tostring(Movement.State.sprinting), ctx.flatSpeed())
	)

	-- 4. Cargas y recarga
	ctx.settle()
	ctx.waitForCharges()
	ctx.teleport(Vector3.new(0, 4, 30), forward)
	before = dashCount
	local tFirst = os.clock()
	Input.Trigger("Paso")
	task.wait(0.25)
	Input.Trigger("Paso")
	task.wait(0.25)
	Input.Trigger("Paso")
	task.wait(0.1)
	local used = dashCount - before
	record("Cargas de Paso", used == Config.DashCharges, string.format("%d Pasos con %d cargas (el tercero no debe salir)", used, Config.DashCharges))
	waitUntil(function()
		return Movement.State.charges >= 1
	end, 3)
	local oneBack = os.clock() - tFirst
	waitUntil(function()
		return Movement.State.charges >= Movement.MaxCharges
	end, 3)
	local allBack = os.clock() - tFirst
	record(
		"Recarga de Pasos",
		near(oneBack, Config.DashRechargeTime, 0.12) and near(allBack, Config.DashRechargeTime * Config.DashCharges, 0.15),
		string.format("1 carga a los %.2f s, todas a los %.2f s", oneBack, allBack)
	)

	-- 5. Salto normal y caída
	ctx.settle()
	ctx.teleport(Vector3.new(0, 4, 120), forward)
	ctx.humanoid.Jump = true
	local rise, peakTime, landTime = ctx.trackJump(3)
	record("Altura del salto", near(rise, Config.JumpHeight, 0.6), string.format("sube %.2f studs (objetivo %.1f)", rise, Config.JumpHeight))
	if landTime then
		local fall = landTime - peakTime
		record("Caída más rápida que la subida", fall < peakTime * 0.95, string.format("sube en %.2f s, cae en %.2f s", peakTime, fall))
	else
		record("Caída más rápida que la subida", false, "no aterrizó a tiempo")
	end

	-- 6. Doble salto
	ctx.settle()
	ctx.humanoid.Jump = true
	local doubled = false
	local rise2 = ctx.trackJump(4, function(t)
		if not doubled and t > 0.15 and ctx.root.AssemblyLinearVelocity.Y <= 0 then
			doubled = true
			Input.Trigger("Saltar")
		end
	end)
	local expected2 = Config.JumpHeight + Config.AirJumpHeight
	record("Doble salto", doubled and near(rise2, expected2, 1), string.format("sube %.2f studs en total (objetivo %.1f)", rise2, expected2))
	ctx.settle()
	record("Saltos recuperados al aterrizar", Movement.State.airJumpsLeft == Config.AirJumps, string.format("%d de %d", Movement.State.airJumpsLeft, Config.AirJumps))

	-- 7. Paso aéreo: mantiene la altura
	ctx.settle()
	ctx.waitForCharges()
	ctx.humanoid.Jump = true
	before = dashCount
	local airDashed, maxVy = false, 0
	ctx.trackJump(4, function(t)
		if not airDashed and t > 0.15 and ctx.root.AssemblyLinearVelocity.Y <= 0 then
			airDashed = true
			Input.Trigger("Paso")
		elseif airDashed and Movement.State.dashing then
			maxVy = math.max(maxVy, math.abs(ctx.root.AssemblyLinearVelocity.Y))
		end
	end)
	record(
		"Paso aéreo",
		airDashed and dashCount == before + 1 and near(Movement.State.lastDashDistance, Config.DashDistance, 0.6) and maxVy < 3,
		string.format("%.1f studs, velocidad vertical máx. %.1f durante el Paso", Movement.State.lastDashDistance, maxVy)
	)

	-- 8. Solo un Paso aéreo por salto
	ctx.settle()
	ctx.waitForCharges()
	ctx.humanoid.Jump = true
	before = dashCount
	local first, second = false, false
	ctx.trackJump(4, function(t)
		if not first and t > 0.15 and ctx.root.AssemblyLinearVelocity.Y <= 0 then
			first = true
			Input.Trigger("Paso")
		elseif first and not second and not Movement.State.dashing and t > 0.5 and not ctx.grounded() then
			second = true
			Input.Trigger("Paso")
		end
	end)
	record("Un Paso aéreo por salto", second and dashCount == before + 1, string.format("%d Paso(s) en el mismo salto (debe ser 1)", dashCount - before))

	-- 9. Búfer de salto: pulsar justo antes de aterrizar
	ctx.settle()
	local groundY = ctx.root.Position.Y
	ctx.humanoid.Jump = true
	local spent, buffered, reJumped = false, false, false
	ctx.trackJump(4, function(t)
		local vy = ctx.root.AssemblyLinearVelocity.Y
		if not spent and t > 0.15 and vy <= 0 then
			spent = true
			Input.Trigger("Saltar") -- gasta el doble salto
		elseif spent and not buffered and vy < -5 and (ctx.root.Position.Y - groundY) / -vy < 0.06 then
			buffered = true
			Input.Trigger("Saltar") -- sin saltos disponibles: debe quedar en el búfer
		elseif buffered and vy > 20 then
			reJumped = true
		end
	end)
	if buffered and not reJumped then
		reJumped = waitUntil(function()
			return ctx.root.AssemblyLinearVelocity.Y > 20
		end, 0.4)
	end
	record("Búfer de salto", buffered and reJumped, if reJumped then "saltó al aterrizar" else "no saltó al aterrizar")

	-- 10. Coyote time: saltar justo después de salir de un borde
	ctx.settle()
	ctx.teleport(Vector3.new(0, 10, -33), Vector3.new(0, 0, -1))
	ctx.humanoid:Move(Vector3.new(0, 0, -1))
	local leftEdge = waitUntil(function()
		return not ctx.grounded()
	end, 2)
	task.wait(0.04)
	Input.Trigger("Saltar")
	local coyote = waitUntil(function()
		return ctx.root.AssemblyLinearVelocity.Y > 20
	end, 0.3)
	ctx.humanoid:Move(Vector3.zero)
	record("Coyote time", leftEdge and coyote, if coyote then "saltó tras salir del borde" else "no saltó tras salir del borde")

	-- 11. Reaparecer: todo debe seguir funcionando con el personaje nuevo
	ctx.settle()
	if ctx.remote then
		local oldCharacter = ctx.player.Character
		ctx.remote:FireServer("reaparecer")
		local respawned = waitUntil(function()
			local character = ctx.player.Character
			return character ~= oldCharacter
				and character ~= nil
				and Movement.CurrentCharacter == character
				and Movement.State.ready
				and ctx.Combat.State.ready
		end, 12)
		if respawned then
			ctx.bindCharacter(ctx.player.Character)
			ctx.controls:Disable()
			ctx.settle()
			ctx.teleport(Vector3.new(0, 4, 30), forward)
			before = dashCount
			Input.Trigger("Paso")
			task.wait(0.35)
			record(
				"Reaparecer",
				dashCount == before + 1 and near(Movement.State.lastDashDistance, Config.DashDistance, 0.6),
				string.format("Paso tras reaparecer: %.1f studs", Movement.State.lastDashDistance)
			)
		else
			record("Reaparecer", false, "el personaje nuevo no quedó preparado")
		end
	end

	-- 12. Lo mismo a ~30 FPS (celulares modestos)
	ctx.settle()
	ctx.waitForCharges()
	local removeLoad, measureFps = ctx.artificialLoad(0.026)
	local lowFps = measureFps()
	ctx.teleport(Vector3.new(0, 4, 30), forward)
	before = dashCount
	Input.Trigger("Paso")
	waitUntil(function()
		return dashCount > before and not Movement.State.dashing
	end, 1.5)
	local lowDash = Movement.State.lastDashDistance
	ctx.settle()
	ctx.humanoid.Jump = true
	local lowRise = ctx.trackJump(3)
	removeLoad()
	local isLow = lowFps <= 40
	record("Paso a baja tasa de cuadros", isLow and dashCount == before + 1 and near(lowDash, Config.DashDistance, 0.8), string.format("%.1f studs a %d FPS", lowDash, lowFps))
	record("Salto a baja tasa de cuadros", isLow and near(lowRise, Config.JumpHeight, 0.8), string.format("sube %.2f studs a %d FPS", lowRise, lowFps))

	dashConnection:Disconnect()
end
