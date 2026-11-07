-- Utilidades comunes de las pruebas automáticas del cliente.
-- Las suites reciben este contexto: ctx.record(nombre, ok, detalle), ctx.teleport(...), ctx.humanoid...

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local shared = ReplicatedStorage:WaitForChild("Shared")
local controllers = player:WaitForChild("PlayerScripts"):WaitForChild("Controllers")

local ctx = {
	player = player,
	results = {},
	MovementConfig = require(shared:WaitForChild("Config"):WaitForChild("MovementConfig")),
	CombatConfig = require(shared:WaitForChild("Config"):WaitForChild("CombatConfig")),
	Input = require(controllers:WaitForChild("InputController")),
	Movement = require(controllers:WaitForChild("MovementController")),
	Combat = require(controllers:WaitForChild("CombatController")),
	remote = ReplicatedStorage:WaitForChild("UmbralPruebas", 30),
	humanoid = nil,
	root = nil,
	controls = nil,
}

function ctx.record(name, ok, detail)
	table.insert(ctx.results, { name = name, ok = ok == true, detail = detail })
	print(string.format("[UMBRAL-PRUEBAS] %s · %s · %s", if ok then "OK" else "FALLA", name, detail))
end

-- Prueba que no se puede medir en este entorno (no cuenta como superada ni como fallida)
function ctx.skip(name, reason)
	table.insert(ctx.results, { name = name, ok = true, skipped = true, detail = reason })
	print(string.format("[UMBRAL-PRUEBAS] OMITIDA · %s · %s", name, reason))
end

-- ¿La ventana de Studio está dibujando? (si está en segundo plano, RenderStepped no corre)
function ctx.isRendering()
	local frames = 0
	local connection = game:GetService("RunService").RenderStepped:Connect(function()
		frames += 1
	end)
	task.wait(0.3)
	connection:Disconnect()
	return frames >= 3
end

-- Baja la tasa de cuadros a ~30 FPS con una carga en Heartbeat (corre aunque la ventana no dibuje).
-- Devuelve una función para quitarla y otra que mide los FPS reales.
function ctx.artificialLoad(seconds)
	local RunService = game:GetService("RunService")
	local connection = RunService.Heartbeat:Connect(function()
		local t = os.clock()
		while os.clock() - t < seconds do
			-- carga artificial
		end
	end)
	local function measure()
		local frames, t0 = 0, os.clock()
		local counter = RunService.Heartbeat:Connect(function()
			frames += 1
		end)
		task.wait(1)
		counter:Disconnect()
		return math.floor(frames / (os.clock() - t0))
	end
	return function()
		connection:Disconnect()
	end, measure
end

function ctx.near(value, target, tolerance)
	return math.abs(value - target) <= tolerance
end

function ctx.waitUntil(condition, timeout)
	local start = os.clock()
	while not condition() do
		if os.clock() - start > timeout then
			return false
		end
		task.wait()
	end
	return true
end

function ctx.bindCharacter(character)
	ctx.humanoid = character:WaitForChild("Humanoid")
	ctx.root = character:WaitForChild("HumanoidRootPart")
end

function ctx.grounded()
	return ctx.humanoid.FloorMaterial ~= Enum.Material.Air
end

function ctx.flatSpeed()
	local v = ctx.root.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

function ctx.settle()
	ctx.humanoid:Move(Vector3.zero)
	ctx.waitUntil(function()
		return ctx.grounded()
			and ctx.root.AssemblyLinearVelocity.Magnitude < 0.5
			and not ctx.Movement.State.dashing
			and ctx.Combat.State.mode == "Libre"
	end, 3)
	task.wait(0.2)
end

function ctx.teleport(position, look)
	-- Nunca teletransportar en medio de un golpe: el golpe en vuelo se juzgaría con el personaje ya movido
	-- (un jugador no puede hacer eso; los teletransportes del juego no ocurren a mitad de un golpe)
	if ctx.Combat.State.mode == "Ataque" or ctx.Combat.State.mode == "Carga" then
		ctx.waitUntil(function()
			return ctx.Combat.State.mode ~= "Ataque" and ctx.Combat.State.mode ~= "Carga"
		end, 1.5)
		task.wait(0.35) -- que el servidor termine de juzgar el último golpe
	end
	ctx.humanoid:Move(Vector3.zero)
	ctx.root.AssemblyLinearVelocity = Vector3.zero
	if ctx.remote then
		ctx.remote:FireServer("teletransporte") -- el servidor no lo cuenta como movimiento imposible
		task.wait(0.05)
		ctx.humanoid:Move(Vector3.zero)
		ctx.root.AssemblyLinearVelocity = Vector3.zero
	end
	ctx.root.CFrame = CFrame.lookAt(position, position + look)
	ctx.settle()
end

function ctx.waitForCharges()
	ctx.waitUntil(function()
		return ctx.Movement.State.charges >= ctx.Movement.MaxCharges
	end, 3)
end

-- Sigue un salto: altura máxima, cuándo llegó arriba y cuándo aterrizó
function ctx.trackJump(maxTime, onFrame)
	local root = ctx.root
	local startY = root.Position.Y
	local peakY, peakTime = startY, 0
	local t0 = os.clock()
	local leftGround, landTime = false, nil
	while os.clock() - t0 < maxTime do
		task.wait()
		local t = os.clock() - t0
		local y = root.Position.Y
		if y > peakY then
			peakY, peakTime = y, t
		end
		if not ctx.grounded() then
			leftGround = true
		end
		if onFrame then
			onFrame(t, y - startY)
		end
		if leftGround and ctx.grounded() and t > 0.1 then
			landTime = t
			break
		end
	end
	return peakY - startY, peakTime, landTime
end

-- Prepara al personaje: listo, sin controles de teclado (para que no pisen la dirección de prueba)
function ctx.start()
	ctx.bindCharacter(player.Character or player.CharacterAdded:Wait())
	local ready = ctx.waitUntil(function()
		return ctx.Movement.State.ready and ctx.Movement.CurrentCharacter == player.Character and ctx.Combat.State.ready
	end, 15)
	ctx.controls = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()
	ctx.controls:Disable()
	ctx.settle()
	return ready
end

function ctx.finish()
	if ctx.controls then
		ctx.controls:Enable()
	end
	local passed, skipped = 0, 0
	for _, r in ipairs(ctx.results) do
		if r.skipped then
			skipped += 1
		elseif r.ok then
			passed += 1
		end
	end
	print(string.format("[UMBRAL-PRUEBAS] RESUMEN: %d/%d OK · %d omitidas", passed, #ctx.results - skipped, skipped))
	if ctx.remote then
		ctx.remote:FireServer("fin", ctx.results)
	end
end

return ctx
