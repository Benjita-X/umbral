-- Suite de movilidad en paredes (EXPERIMENTAL): salto de pared, misma pared no dos veces, deslizamiento,
-- agarre de borde y carrera por la pared. Mide la física real del personaje.

local Workspace = game:GetService("Workspace")

return function(ctx)
	local Config, Input, Movement = ctx.MovementConfig, ctx.Input, ctx.Movement
	local record, waitUntil = ctx.record, ctx.waitUntil

	local wallJumps, wallRuns, mantles = 0, 0, 0
	local connections = {
		Movement.WallJumped:Connect(function()
			wallJumps += 1
		end),
		Movement.WallRunStarted:Connect(function()
			wallRuns += 1
		end),
		Movement.Mantled:Connect(function()
			mantles += 1
		end),
	}
	local function jumpFromGround()
		ctx.humanoid.Jump = true
		waitUntil(function()
			return not ctx.grounded()
		end, 1)
	end

	-- ---------- 1. Salto de pared (muro del laboratorio: cara en z = 69, mirando a -Z) ----------
	ctx.settle()
	ctx.teleport(Vector3.new(-60, 4, 66), Vector3.new(0, 0, 1))
	local towardWall = Vector3.new(0, 0, 1)
	ctx.humanoid:Move(towardWall)
	jumpFromGround()
	waitUntil(function()
		return ctx.root.Position.Z >= 67.4 or ctx.grounded()
	end, 1)
	local w0 = wallJumps
	Input.Trigger("Saltar")
	task.wait(0.06)
	local v = ctx.root.AssemblyLinearVelocity
	record(
		"[Paredes] Salto de pared: arriba y lejos del muro",
		wallJumps == w0 + 1 and v.Z < -10 and v.Y > 5,
		string.format("saltos de pared %d · velocidad lejos del muro %.1f · hacia arriba %.1f", wallJumps - w0, -v.Z, v.Y)
	)
	record("[Paredes] El salto de pared devuelve el Paso aéreo", Movement.State.airDashesLeft == Config.AirDashesPerJump, string.format("%d de %d", Movement.State.airDashesLeft, Config.AirDashesPerJump))

	-- 2. La misma pared no vale dos veces seguidas (no se trepa un muro solo)
	ctx.humanoid:Move(towardWall)
	waitUntil(function()
		return ctx.root.Position.Z >= 67.4 or ctx.grounded()
	end, 1.5)
	local w1 = wallJumps
	if not ctx.grounded() then
		Input.Trigger("Saltar")
		task.wait(0.06)
	end
	record("[Paredes] La misma pared no se repite sin tocar otra cosa", wallJumps == w1, string.format("saltos de pared extra: %d", wallJumps - w1))
	ctx.humanoid:Move(Vector3.zero)
	ctx.settle()

	-- ---------- 3. Deslizamiento: cayendo y empujando contra el muro se cae más lento ----------
	ctx.teleport(Vector3.new(-60, 4, 67.4), Vector3.new(0, 0, 1))
	ctx.remote:FireServer("teletransporte")
	task.wait(0.05)
	ctx.root.CFrame = CFrame.lookAt(Vector3.new(-60, 24, 67.4), Vector3.new(-60, 24, 70))
	ctx.root.AssemblyLinearVelocity = Vector3.zero
	ctx.humanoid:Move(towardWall)
	local fastest = 0
	local t0 = os.clock()
	while os.clock() - t0 < 0.9 and not ctx.grounded() do
		fastest = math.max(fastest, -ctx.root.AssemblyLinearVelocity.Y)
		task.wait()
	end
	record(
		"[Paredes] Deslizarse por la pared frena la caída",
		fastest <= Config.WallSlideSpeed + 2.5,
		string.format("caída máxima %.1f studs/s (tope %.0f; caída libre llega a %.0f)", fastest, Config.WallSlideSpeed, Config.MaxFallSpeed)
	)
	ctx.humanoid:Move(Vector3.zero)
	ctx.settle()

	-- ---------- 4. Agarre de borde: bloque de 10,5 (un salto llega a 8,5) ----------
	ctx.teleport(Vector3.new(150, 4, -6.6), Vector3.new(0, 0, 1))
	local m0 = mantles
	ctx.humanoid:Move(Vector3.new(0, 0, 1))
	jumpFromGround()
	-- Esperar el agarre y un aterrizaje de verdad (rozar la arista del muro también marca "suelo" un
	-- instante); recién ahí soltar la dirección, para no cruzar el bloque antes de medir
	waitUntil(function()
		return mantles > m0
	end, 1.5)
	waitUntil(function()
		return ctx.grounded() and math.abs(ctx.root.AssemblyLinearVelocity.Y) < 1 and ctx.root.Position.Y > 8
	end, 2)
	ctx.humanoid:Move(Vector3.zero)
	local feet = ctx.root.Position.Y - (ctx.humanoid.HipHeight + ctx.root.Size.Y / 2)
	record(
		"[Paredes] Agarre de borde: sube a un borde que el salto no alcanza",
		mantles == m0 + 1 and feet > 10,
		string.format("agarres %d · pies a %.1f studs (borde a 10,5; salto normal 8,5)", mantles - m0, feet)
	)
	ctx.settle()

	-- ---------- 5. Carrera por la pared (muro este de la arena: cara en x = 54) ----------
	ctx.waitForCharges()
	ctx.teleport(Vector3.new(52.3, 4, -150), Vector3.new(0, 0, -1))
	local r0 = wallRuns
	ctx.humanoid:Move(Vector3.new(0, 0, -1))
	task.wait(Config.SprintDelay + Config.SprintRampTime + 0.15) -- entrar en sprint
	local startY = ctx.root.Position.Y
	local startZ = ctx.root.Position.Z
	jumpFromGround()
	local ran = waitUntil(function()
		return wallRuns > r0
	end, 0.8)
	local lowest = math.huge
	local t1 = os.clock()
	while os.clock() - t1 < 0.5 do
		lowest = math.min(lowest, ctx.root.Position.Y)
		task.wait()
	end
	local covered = startZ - ctx.root.Position.Z
	ctx.humanoid:Move(Vector3.zero)
	record(
		"[Paredes] Carrera por la pared: avanza pegado al muro sin caer",
		ran and lowest > startY - 0.5 and covered > 15,
		string.format("carrera %s · recorrió %.1f studs · altura mínima %.1f sobre el inicio", tostring(ran), covered, lowest - startY)
	)
	ctx.settle()

	for _, c in ipairs(connections) do
		c:Disconnect()
	end
	ctx.teleport(Vector3.new(0, 4, 30), Vector3.new(0, 0, 1))
end
