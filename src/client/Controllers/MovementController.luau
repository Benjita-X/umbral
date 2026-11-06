-- MovementController: locomoción del jugador local (Fase 1).
-- Carrera, sprint automático, Paso (dash) con cargas, salto con coyote time y búfer,
-- doble salto con cambio de dirección y caída más rápida que la subida.
-- En Roblox el cliente simula su propio personaje; la validación en el servidor llega en la Fase 4.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("MovementConfig"))

local FORCE = 1e7
local player = Players.LocalPlayer

local MovementController = {}

local dashedEvent = Instance.new("BindableEvent")
MovementController.Dashed = dashedEvent.Event

-- Estado de solo lectura para la cámara y el panel de depuración
local state = {
	speed = 0,
	sprinting = false,
	dashing = false,
	grounded = true,
	charges = Config.DashCharges,
	airJumpsLeft = Config.AirJumps,
	airDashesLeft = Config.AirDashesPerJump,
	lastDashDistance = 0,
	humanoidState = "-",
	ready = false, -- true cuando el personaje actual ya está preparado
}
MovementController.State = state
MovementController.MaxCharges = Config.DashCharges
MovementController.CurrentCharacter = nil

local humanoid, root, dashVelocity = nil, nil, nil
local connections = {}

local moveHeldTime = 0
local noInputTime = 0
local chargeTimer = 0
local lastDashTime = -math.huge
local lastGroundedTime = -math.huge
local jumpedSinceGrounded = false
local bufferedJumpTime = -math.huge
local dash = nil -- { dir, speed, elapsed, startPos, holdHeight }
local exitBlend = nil -- { from, elapsed }
local lunge = nil -- { velocity, remaining, hold }: avance corto de un golpe
local baseSpeed = Config.RunSpeed -- velocidad de carrera/sprint antes de multiplicadores

-- Bloqueos y multiplicadores que piden otros sistemas (combate, menús...), por clave
local extraDashProvider = nil -- función que devuelve true si paga un Paso extra sin cargas
local speedMultipliers = {}
local dashBlockers = {}
local jumpBlockers = {}
local rotateBlockers = {}

local function log(...)
	if Config.DebugPrints then
		print("[UMBRAL]", ...)
	end
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function jumpVelocity(height)
	return math.sqrt(2 * Workspace.Gravity * height)
end

local function resetAir()
	state.airJumpsLeft = Config.AirJumps
	state.airDashesLeft = Config.AirDashesPerJump
	jumpedSinceGrounded = false
end

local function speedMultiplier()
	local m = 1
	for _, value in pairs(speedMultipliers) do
		m = math.min(m, value)
	end
	return m
end

local function applyBlockers()
	if not humanoid then
		return
	end
	humanoid.JumpHeight = if next(jumpBlockers) then 0 else Config.JumpHeight
	humanoid.AutoRotate = next(rotateBlockers) == nil
end

local function stopDashForces()
	dash = nil
	exitBlend = nil
	lunge = nil
	state.dashing = false
	if dashVelocity then
		dashVelocity.Enabled = false
	end
end

local function disconnectAll()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function endDash()
	if not dash then
		return
	end
	local distance = flat(root.Position - dash.startPos).Magnitude
	state.lastDashDistance = distance
	log(string.format("Paso: %.1f studs en %.2f s (objetivo %.1f)", distance, dash.elapsed, Config.DashDistance))
	dash = nil
	state.dashing = false

	-- Conservar el impulso: al salir del Paso se entra directo en sprint
	moveHeldTime = math.max(moveHeldTime, Config.SprintDelay)
	noInputTime = 0
	state.sprinting = true
	baseSpeed = Config.SprintSpeed
	humanoid.WalkSpeed = baseSpeed * speedMultiplier()

	if Config.DashExitBlendTime > 0 then
		exitBlend = { from = dashVelocity.VectorVelocity, elapsed = 0 }
		dashVelocity.MaxAxesForce = Vector3.new(FORCE, 0, FORCE)
	else
		dashVelocity.Enabled = false
	end
end

local function startDash()
	if not humanoid or not root or humanoid.Health <= 0 or dash then
		return
	end
	local now = os.clock()
	if now - lastDashTime < Config.DashMinInterval or next(dashBlockers) then
		return
	end
	local airborne = not state.grounded
	if airborne and state.airDashesLeft <= 0 then
		return
	end

	-- Dirección: la que pide el jugador; si no pide ninguna, hacia donde mira
	local dir = flat(humanoid.MoveDirection)
	if dir.Magnitude < 0.1 then
		dir = flat(root.CFrame.LookVector)
	end
	if dir.Magnitude < 0.01 then
		return
	end
	dir = dir.Unit

	-- Sin cargas: un Paso extra si otro sistema lo paga (la Resonancia)
	if state.charges <= 0 then
		if not (extraDashProvider and extraDashProvider()) then
			return
		end
	else
		state.charges -= 1
	end
	if airborne then
		state.airDashesLeft -= 1
	end
	lastDashTime = now
	exitBlend = nil
	lunge = nil

	local holdHeight = airborne and Config.AirDashHoldsHeight
	local speed = Config.DashDistance / Config.DashDuration
	dash = { dir = dir, speed = speed, elapsed = 0, startPos = root.Position, holdHeight = holdHeight }
	state.dashing = true

	dashVelocity.MaxAxesForce = Vector3.new(FORCE, holdHeight and FORCE or 0, FORCE)
	dashVelocity.VectorVelocity = dir * speed
	dashVelocity.Enabled = true
	if holdHeight then
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
	end

	-- El cuerpo gira al instante hacia el Paso
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	dashedEvent:Fire(dir)
end

local function onJumpPressed()
	if not humanoid or not root or humanoid.Health <= 0 or next(jumpBlockers) then
		return
	end
	if state.grounded then
		return -- en el suelo salta el sistema normal de Roblox (y puede saltar durante un Paso)
	end
	local now = os.clock()

	-- Un salto corta el Paso aéreo
	if dash then
		endDash()
	end

	-- Coyote time: acabas de salir de un borde sin haber saltado
	if not jumpedSinceGrounded and now - lastGroundedTime <= Config.CoyoteTime then
		jumpedSinceGrounded = true
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(v.X, jumpVelocity(Config.JumpHeight), v.Z)
		log("Salto coyote")
		return
	end

	-- Doble salto: también redirige el impulso horizontal hacia donde apunta el jugador
	if state.airJumpsLeft > 0 then
		state.airJumpsLeft -= 1
		local v = root.AssemblyLinearVelocity
		local horizontal = flat(v)
		local dir = flat(humanoid.MoveDirection)
		if dir.Magnitude > 0.1 then
			horizontal = dir.Unit * math.max(horizontal.Magnitude, humanoid.WalkSpeed)
		end
		root.AssemblyLinearVelocity = horizontal + Vector3.new(0, jumpVelocity(Config.AirJumpHeight), 0)
		log("Doble salto")
		return
	end

	-- Sin saltos disponibles: se recuerda para cuando aterrice
	bufferedJumpTime = now
end

local function onStateChanged(_, newState)
	if newState == Enum.HumanoidStateType.Jumping then
		jumpedSinceGrounded = true
	elseif newState == Enum.HumanoidStateType.Landed then
		resetAir()
		if os.clock() - bufferedJumpTime <= Config.JumpBufferTime and not next(jumpBlockers) then
			bufferedJumpTime = -math.huge
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			log("Salto del búfer")
		end
	end
end

local function setupCharacter(character)
	disconnectAll()
	stopDashForces()
	humanoid, root, dashVelocity = nil, nil, nil
	state.ready = false

	local newHumanoid = character:WaitForChild("Humanoid")
	local newRoot = character:WaitForChild("HumanoidRootPart")
	newHumanoid.UseJumpPower = false
	newHumanoid.JumpHeight = Config.JumpHeight
	newHumanoid.WalkSpeed = Config.RunSpeed

	local attachment = Instance.new("Attachment")
	attachment.Name = "UmbralMovimiento"
	attachment.Parent = newRoot

	local constraint = Instance.new("LinearVelocity")
	constraint.Name = "UmbralPaso"
	constraint.Attachment0 = attachment
	constraint.RelativeTo = Enum.ActuatorRelativeTo.World
	constraint.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	constraint.ForceLimitsEnabled = true
	constraint.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	constraint.MaxAxesForce = Vector3.zero
	constraint.VectorVelocity = Vector3.zero
	constraint.Enabled = false
	constraint.Parent = newRoot

	moveHeldTime, noInputTime, chargeTimer = 0, 0, 0
	baseSpeed = Config.RunSpeed
	state.charges = Config.DashCharges
	state.sprinting = false
	resetAir()

	humanoid, root, dashVelocity = newHumanoid, newRoot, constraint
	applyBlockers()
	table.insert(connections, newHumanoid.StateChanged:Connect(onStateChanged))
	table.insert(connections, newHumanoid.Died:Connect(stopDashForces))
	MovementController.CurrentCharacter = character
	state.ready = true
	log("Personaje listo")
end

local function update(dt)
	if not humanoid or not root or not root.Parent or humanoid.Health <= 0 then
		return
	end
	local now = os.clock()
	local velocity = root.AssemblyLinearVelocity

	-- Suelo
	state.grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	if state.grounded then
		lastGroundedTime = now
		if velocity.Y <= 1 and not dash then
			resetAir()
		end
	end

	-- Recarga de Pasos, de una carga a la vez (sigue corriendo durante el Paso: es el valor medido
	-- de 0,8 s por carga; ver DECISIONES.md)
	if state.charges < Config.DashCharges then
		chargeTimer += dt
		if chargeTimer >= Config.DashRechargeTime then
			chargeTimer -= Config.DashRechargeTime
			state.charges += 1
		end
	else
		chargeTimer = 0
	end

	-- Paso en curso y fundido de salida.
	-- Termina por DISTANCIA, no por tiempo: así recorre lo mismo a 30 o a 60 FPS (justo en PvP).
	-- El tope de tiempo corta el Paso si choca con algo.
	if dash then
		dash.elapsed += dt
		local remaining = Config.DashDistance - flat(root.Position - dash.startPos).Magnitude
		if remaining <= 0.05 or dash.elapsed >= Config.DashDuration * 1.5 then
			endDash()
		elseif remaining < dash.speed * dt then
			-- Último tramo: frenar lo justo para no pasarse de la distancia
			dashVelocity.VectorVelocity = dash.dir * (remaining / math.max(dt, 1 / 240))
		end
	elseif lunge then
		-- Avance de un golpe; durante el hitstop se congela
		if lunge.hold > 0 then
			lunge.hold -= dt
			dashVelocity.VectorVelocity = Vector3.zero
		else
			lunge.remaining -= dt
			dashVelocity.VectorVelocity = lunge.velocity
			if lunge.remaining <= 0 then
				lunge = nil
				dashVelocity.Enabled = false
			end
		end
	elseif exitBlend then
		exitBlend.elapsed += dt
		local alpha = math.clamp(exitBlend.elapsed / Config.DashExitBlendTime, 0, 1)
		local moveDir = flat(humanoid.MoveDirection)
		local target = if moveDir.Magnitude > 0.1 then moveDir.Unit * Config.SprintSpeed else Vector3.zero
		dashVelocity.VectorVelocity = exitBlend.from:Lerp(target, alpha)
		if alpha >= 1 then
			exitBlend = nil
			dashVelocity.Enabled = false
		end
	end

	-- Sprint automático
	if humanoid.MoveDirection.Magnitude > 0.1 then
		moveHeldTime += dt
		noInputTime = 0
	else
		noInputTime += dt
		if noInputTime >= Config.SprintGraceTime then
			moveHeldTime = 0
		end
	end
	local sprinting = moveHeldTime >= Config.SprintDelay
	if sprinting and not state.sprinting then
		log(string.format("Sprint tras %.2f s", moveHeldTime))
	end
	state.sprinting = sprinting

	local targetSpeed = if sprinting then Config.SprintSpeed else Config.RunSpeed
	local rampRate = (Config.SprintSpeed - Config.RunSpeed) / math.max(Config.SprintRampTime, 1e-3)
	if baseSpeed < targetSpeed then
		baseSpeed = math.min(targetSpeed, baseSpeed + rampRate * dt)
	else
		baseSpeed = targetSpeed
	end
	humanoid.WalkSpeed = baseSpeed * speedMultiplier()

	-- Caída más rápida que la subida
	if not state.grounded and velocity.Y < 0 and not (dash and dash.holdHeight) then
		local extra = Workspace.Gravity * (Config.FallGravityMultiplier - 1) * dt
		local newY = math.max(velocity.Y - extra, -Config.MaxFallSpeed)
		root.AssemblyLinearVelocity = Vector3.new(velocity.X, newY, velocity.Z)
	end

	state.speed = flat(root.AssemblyLinearVelocity).Magnitude
	state.humanoidState = humanoid:GetState().Name
end

-- ---------- API para otros sistemas (combate) ----------

-- Multiplica la velocidad de carrera mientras la clave esté activa (nil la quita). Se usa la menor.
function MovementController.SetSpeedMultiplier(key, value)
	speedMultipliers[key] = value
end

function MovementController.SetDashBlocked(key, blocked)
	dashBlockers[key] = if blocked then true else nil
end

function MovementController.SetJumpBlocked(key, blocked)
	jumpBlockers[key] = if blocked then true else nil
	applyBlockers()
end

function MovementController.SetAutoRotateBlocked(key, blocked)
	rotateBlockers[key] = if blocked then true else nil
	applyBlockers()
end

-- Quita todos los bloqueos y multiplicadores de una clave (al terminar un golpe, al reaparecer...)
function MovementController.ClearKey(key)
	speedMultipliers[key] = nil
	dashBlockers[key] = nil
	jumpBlockers[key] = nil
	rotateBlockers[key] = nil
	applyBlockers()
end

-- Termina el Paso en curso (por ejemplo, para golpear desde él)
function MovementController.CancelDash()
	if dash then
		endDash()
	end
end

-- Avance horizontal corto (los golpes se acercan al rival)
function MovementController.Lunge(direction, speed, duration)
	if not dashVelocity or dash then
		return
	end
	local dir = flat(direction)
	if dir.Magnitude < 0.01 or speed <= 0 or duration <= 0 then
		return
	end
	exitBlend = nil
	lunge = { velocity = dir.Unit * speed, remaining = duration, hold = 0 }
	dashVelocity.MaxAxesForce = Vector3.new(FORCE, 0, FORCE)
	dashVelocity.VectorVelocity = lunge.velocity
	dashVelocity.Enabled = true
end

-- Empuje al recibir un golpe (lo aplica este cliente: es quien simula su propio personaje)
function MovementController.Knockback(direction, speed, duration)
	MovementController.CancelDash()
	MovementController.Lunge(direction, speed, duration)
end

-- Diagnóstico: bloqueos activos y estado (para pruebas)
function MovementController.Debug()
	local function keys(t)
		local list = {}
		for k in pairs(t) do
			table.insert(list, tostring(k))
		end
		return if #list > 0 then table.concat(list, "+") else "-"
	end
	return string.format(
		"bloqueos paso[%s] salto[%s] giro[%s] · JumpHeight %.1f · cargas %d · paso %s · avance %s · %s",
		keys(dashBlockers),
		keys(jumpBlockers),
		keys(rotateBlockers),
		if humanoid then humanoid.JumpHeight else -1,
		state.charges,
		tostring(dash ~= nil),
		tostring(lunge ~= nil),
		if humanoid then humanoid:GetState().Name else "-"
	)
end

-- Quién paga un Paso extra cuando no quedan cargas (nil = nadie)
function MovementController.SetExtraDashProvider(provider)
	extraDashProvider = provider
end

-- Congela el avance durante el hitstop
function MovementController.HoldLunge(duration)
	if lunge then
		lunge.hold = math.max(lunge.hold, duration)
	end
end

function MovementController.StopLunge()
	if lunge then
		lunge = nil
		if dashVelocity and not dash and not exitBlend then
			dashVelocity.Enabled = false
		end
	end
end

-- Gira el cuerpo al instante hacia una dirección horizontal
function MovementController.Face(direction)
	if not root then
		return
	end
	local dir = flat(direction)
	if dir.Magnitude > 0.01 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + dir.Unit)
	end
end

-- Hacia dónde quiere ir el jugador (o hacia donde mira si no pulsa nada)
function MovementController.DesiredDirection()
	if not humanoid or not root then
		return Vector3.new(0, 0, -1)
	end
	local move = flat(humanoid.MoveDirection)
	if move.Magnitude > 0.1 then
		return move.Unit
	end
	local look = flat(root.CFrame.LookVector)
	return if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
end

function MovementController.Start(input)
	input.ActionBegan:Connect(function(action)
		if action == "Paso" then
			startDash()
		elseif action == "Saltar" then
			onJumpPressed()
		end
	end)
	player.CharacterAdded:Connect(setupCharacter)
	if player.Character then
		task.spawn(setupCharacter, player.Character)
	end
	RunService.Heartbeat:Connect(update)
end

return MovementController
