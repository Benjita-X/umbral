-- Suite de choques y caídas: nada atraviesa paredes ni suelos, y nadie muere por caer al vacío.
-- (Reporte del jugador 2026-11-07: un Paso contra una pared lo hundió en el suelo y murió.)

return function(ctx)
	local Input = ctx.Input
	local record, waitUntil = ctx.record, ctx.waitUntil
	local player = ctx.player
	local WALL_FACE = 69 -- cara del muro del laboratorio (mira a -Z)

	local function alive()
		return ctx.humanoid and ctx.humanoid.Health > 0 and ctx.root and ctx.root.Parent ~= nil
	end

	-- ---------- 1. Paso en el suelo contra una pared ----------
	ctx.settle()
	ctx.waitForCharges()
	ctx.teleport(Vector3.new(-60, 4, WALL_FACE - 6), Vector3.new(0, 0, 1))
	local startY = ctx.root.Position.Y
	ctx.humanoid:Move(Vector3.new(0, 0, 1))
	task.wait()
	Input.Trigger("Paso")
	task.wait(0.6)
	ctx.humanoid:Move(Vector3.zero)
	local z, y = ctx.root.Position.Z, ctx.root.Position.Y
	record(
		"[Choques] El Paso contra una pared no la atraviesa ni se hunde",
		alive() and z < WALL_FACE - 0.3 and math.abs(y - startY) < 2,
		string.format("frente del muro en z=%d · quedó en z=%.1f · altura %.1f (inicio %.1f)", WALL_FACE, z, y, startY)
	)
	ctx.settle()

	-- ---------- 2. Paso aéreo contra la pared ----------
	ctx.waitForCharges()
	ctx.teleport(Vector3.new(-60, 4, WALL_FACE - 6), Vector3.new(0, 0, 1))
	ctx.humanoid.Jump = true
	waitUntil(function()
		return not ctx.grounded()
	end, 1)
	task.wait(0.12)
	ctx.humanoid:Move(Vector3.new(0, 0, 1))
	Input.Trigger("Paso")
	task.wait(0.6)
	ctx.humanoid:Move(Vector3.zero)
	waitUntil(function()
		return ctx.grounded()
	end, 2)
	z, y = ctx.root.Position.Z, ctx.root.Position.Y
	record(
		"[Choques] El Paso aéreo contra una pared no la atraviesa",
		alive() and z < WALL_FACE - 0.3 and y > 1.5,
		string.format("quedó en z=%.1f · altura %.1f", z, y)
	)
	ctx.settle()

	-- ---------- 3. Caída desde muy alto: no atraviesa el suelo ----------
	local rescues0 = player:GetAttribute("Rescates") or 0
	ctx.teleport(Vector3.new(0, 4, 40), Vector3.new(0, 0, 1))
	task.wait(0.4) -- que el servidor registre este suelo como firme
	ctx.remote:FireServer("teletransporte")
	task.wait(0.05)
	ctx.root.AssemblyLinearVelocity = Vector3.zero
	ctx.root.CFrame = CFrame.lookAt(Vector3.new(0, 120, 40), Vector3.new(0, 120, 50))
	waitUntil(function()
		return ctx.grounded()
	end, 4)
	task.wait(0.2)
	y = ctx.root.Position.Y
	record(
		"[Choques] Caer desde 120 studs no atraviesa el suelo",
		alive() and y > 1.5 and y < 7 and (player:GetAttribute("Rescates") or 0) == rescues0,
		string.format("aterrizó a %.1f studs (de pie ≈ 3) · rescates %d", y, (player:GetAttribute("Rescates") or 0) - rescues0)
	)

	-- ---------- 4. Red de seguridad: debajo del suelo, vuelve vivo ----------
	ctx.settle()
	task.wait(0.4)
	rescues0 = player:GetAttribute("Rescates") or 0
	ctx.remote:FireServer("teletransporte")
	task.wait(0.05)
	ctx.root.AssemblyLinearVelocity = Vector3.zero
	ctx.root.CFrame = CFrame.new(0, -60, 40) -- bajo el suelo del laboratorio, cayendo al vacío
	local rescued = waitUntil(function()
		return (player:GetAttribute("Rescates") or 0) > rescues0 and ctx.root.Position.Y > 1
	end, 3)
	record(
		"[Choques] Red de seguridad: quien cae al vacío vuelve vivo al último suelo",
		rescued and alive(),
		string.format("rescatado %s · altura %.1f · vida %.0f", tostring(rescued), ctx.root.Position.Y, ctx.humanoid.Health)
	)
	ctx.settle()

	ctx.teleport(Vector3.new(0, 4, 30), Vector3.new(0, 0, 1))
end
