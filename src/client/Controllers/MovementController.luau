-- MovementController: locomoción del jugador local (Fase 1).
-- Carrera, sprint automático, Paso (dash) con cargas, salto con coyote time y búfer,
-- doble salto con cambio de dirección y caída más rápida que la subida.
-- En Roblox el cliente simula su propio personaje; la validación en el servidor llega en la Fase 4.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("MovementConfig"))

-- Fuerza de las restricciones de velocidad (Paso, avances, paredes). Alcanza de sobra para acelerar al
-- personaje en un cuadro, pero NO aplasta la geometría: con 1e7 un Paso contra una pared metía al personaje
-- en el muro o lo hundía en el suelo (y caía al vacío).
local FORCE = 4e5
local player = Players.LocalPlayer

local MovementController = {}

local dashedEvent = Instance.new("BindableEvent")
MovementController.Dashed = dashedEvent.Event
-- Paredes: salto de pared, inicio de carrera por pared y agarre de borde (efectos y pruebas)
local wallJumpedEvent = Instance.new("BindableEvent")
MovementController.WallJumped = wallJumpedEvent.Event
local wallRunEvent = Instance.new("BindableEvent")
MovementController.WallRunStarted = wallRunEvent.Event
local mantledEvent = Instance.new("BindableEvent")
MovementController.Mantled = mantledEvent.Event

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
local wallPush = nil -- { velocity, remaining }: empuje de un salto de pared
local wallRun = nil -- { tangent, speed, remaining, normal }: corriendo por una pared
local lastWallNormal = nil -- última pared usada para saltar (no se repite la misma sin tocar otra cosa)
local wallRunUsed = false -- una carrera por pared por salto
local mantleUsed = false -- un agarre de borde por salto
local sliding = false -- deslizándose por una pared (fuerza vertical constante)
local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude
local blockParams = RaycastParams.new()
blockParams.FilterType = Enum.RaycastFilterType.Exclude
blockParams.RespectCanCollide = true
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
	lastWallNormal = nil
	wallRunUsed = false
	mantleUsed = false
end

-- ---------- Choques ----------
-- ¿Hay un obstáculo sólido (no un personaje) en esa dirección horizontal, a menos de `distance`? Se usa una
-- esfera del ancho del cuerpo a la altura del torso (los escalones bajos y el suelo no cuentan).
local function obstacleAhead(direction, distance)
	if not root then
		return nil
	end
	local dir = flat(direction)
	if dir.Magnitude < 0.01 or distance <= 0 then
		return nil
	end
	blockParams.FilterDescendantsInstances = { root.Parent, Workspace.CurrentCamera }
	local ok, hit = pcall(Workspace.Spherecast, Workspace, root.Position, 0.9, dir.Unit * distance, blockParams)
	if not ok or not hit or math.abs(hit.Normal.Y) > 0.6 then
		return nil
	end
	local model = hit.Instance:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then
		return nil -- los luchadores se atraviesan entre sí
	end
	return hit
end

-- Quita la parte de la velocidad que va contra la pared (para no seguir empujando)
local function stopAgainst(normal)
	local n = flat(normal)
	if n.Magnitude < 0.01 then
		return
	end
	n = n.Unit
	local v = root.AssemblyLinearVelocity
	local into = v:Dot(n)
	if into < 0 then
		root.AssemblyLinearVelocity = v - n * into
	end
end

-- ---------- Paredes ----------
-- ¿Hay una pared (superficie casi vertical, que no sea otro personaje) en esa dirección horizontal?
local function wallIn(direction)
	if not root then
		return nil
	end
	local dir = flat(direction)
	if dir.Magnitude < 0.1 then
		return nil
	end
	wallParams.FilterDescendantsInstances = { root.Parent, Workspace.CurrentCamera }
	local hit = Workspace:Raycast(root.Position, dir.Unit * Config.WallDetectDistance, wallParams)
	if not hit or math.abs(hit.Normal.Y) > 0.3 or not hit.Instance.CanCollide then
		return nil
	end
	local model = hit.Instance:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then
		return nil -- los luchadores no son paredes
	end
	return hit
end

-- La pared más útil cerca: primero hacia donde empuja el jugador, luego al frente y a los lados
local function nearbyWall()
	if not root or not humanoid then
		return nil
	end
	local look = flat(root.CFrame.LookVector)
	local right = flat(root.CFrame.RightVector)
	for _, dir in ipairs({ humanoid.MoveDirection, look, right, -right, -look }) do
		local hit = wallIn(dir)
		if hit then
			return hit
		end
	end
	return nil
end

local function sameWall(normal)
	return lastWallNormal ~= nil and flat(normal).Unit:Dot(lastWallNormal) > 0.85
end

local function endWallRun()
	if wallRun then
		wallRun = nil
		if dashVelocity and not dash and not lunge and not exitBlend and not wallPush then
			dashVelocity.Enabled = false
		end
	end
end

-- Salto de pared: arriba y lejos del muro, con el Paso aéreo devuelto. No vale la misma pared dos veces
-- seguidas (hay que tocar otra pared o el suelo): se puede zigzaguear entre dos muros, no trepar uno solo.
local function tryWallJump()
	local hit = (wallRun and { Normal = wallRun.normal }) or nearbyWall()
	if not hit or sameWall(hit.Normal) then
		return false
	end
	local normal = flat(hit.Normal).Unit
	endWallRun()
	lastWallNormal = normal
	state.airDashesLeft = Config.AirDashesPerJump
	local push = normal * Config.WallJumpPush
	root.AssemblyLinearVelocity = push + Vector3.new(0, jumpVelocity(Config.WallJumpHeight), 0)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + normal)
	wallPush = { velocity = push, remaining = Config.WallJumpPushTime }
	dashVelocity.MaxAxesForce = Vector3.new(FORCE, 0, FORCE)
	dashVelocity.VectorVelocity = push
	dashVelocity.Enabled = true
	wallJumpedEvent:Fire(normal)
	log("Salto de pared")
	return true
end

-- Agarre de borde: si al saltar contra un obstáculo su borde superior queda a menos de MantleReach por
-- encima de los pies, el personaje sube solo (perdona los saltos casi perfectos)
local function tryMantle(moveDir)
	if mantleUsed or not root or not humanoid then
		return
	end
	local dir = flat(moveDir)
	if dir.Magnitude < 0.5 then
		return
	end
	dir = dir.Unit
	local front = wallIn(dir)
	if not front then
		return
	end
	local feetY = root.Position.Y - (humanoid.HipHeight + root.Size.Y / 2)
	local probe = root.Position + dir * Config.MantleCheckDistance + Vector3.new(0, Config.MantleReach + 3, 0)
	wallParams.FilterDescendantsInstances = { root.Parent, Workspace.CurrentCamera }
	local top = Workspace:Raycast(probe, Vector3.new(0, -(Config.MantleReach + 6), 0), wallParams)
	if not top or top.Normal.Y < 0.7 then
		return
	end
	local rise = top.Position.Y - feetY
	if rise < 0.6 or rise > Config.MantleReach then
		return
	end
	-- Espacio libre arriba del borde (no meterse bajo un techo)
	local head = Workspace:Raycast(top.Position + Vector3.new(0, 0.2, 0), Vector3.new(0, 5, 0), wallParams)
	if head then
		return
	end
	mantleUsed = true
	if sliding then
		sliding = false
		dashVelocity.Enabled = false
	end
	local v = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(v.X, jumpVelocity(rise + 1.2), v.Z) + dir * 8
	mantledEvent:Fire(rise)
	log(string.format("Agarre de borde (%.1f studs)", rise))
	return true
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
	sliding = false
	dash = nil
	exitBlend = nil
	lunge = nil
	wallPush = nil
	wallRun = nil
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
	wallPush = nil
	wallRun = nil -- un Paso sale de la pared

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

	-- Un salto corta el Paso aéreo y el deslizamiento (su fuerza vertical anularía el impulso)
	if dash then
		endDash()
	end
	if sliding then
		sliding = false
		dashVelocity.Enabled = false
	end

	-- Coyote time: acabas de salir de un borde sin haber saltado
	if not jumpedSinceGrounded and now - lastGroundedTime <= Config.CoyoteTime and not wallRun then
		jumpedSinceGrounded = true
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(v.X, jumpVelocity(Config.JumpHeight), v.Z)
		log("Salto coyote")
		return
	end

	-- Salto de pared (antes que el doble salto: junto a un muro es lo que el jugador quiere)
	if tryWallJump() then
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
	-- El personaje no tropieza ni cae al chocar fuerte (un Paso contra una pared lo tumbaba)
	newHumanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	newHumanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
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
		local wall = obstacleAhead(dash.dir, dash.speed * dt * 1.5 + 0.4)
		if wall then
			-- Choque: el Paso termina en la pared, sin seguir empujando (así no se atraviesa nada)
			endDash()
			exitBlend = nil
			dashVelocity.Enabled = false
			stopAgainst(wall.Normal)
		elseif remaining <= 0.05 or dash.elapsed >= Config.DashDuration * 1.5 then
			endDash()
		elseif remaining < dash.speed * dt then
			-- Último tramo: frenar lo justo para no pasarse de la distancia
			dashVelocity.VectorVelocity = dash.dir * (remaining / math.max(dt, 1 / 240))
		end
	elseif wallPush then
		-- Empuje del salto de pared: unos instantes sin que el control lo anule
		wallPush.remaining -= dt
		dashVelocity.VectorVelocity = wallPush.velocity
		local wall = obstacleAhead(wallPush.velocity, wallPush.velocity.Magnitude * dt * 1.5 + 0.4)
		if wall then
			wallPush.remaining = 0
			stopAgainst(wall.Normal)
		end
		if wallPush.remaining <= 0 then
			wallPush = nil
			dashVelocity.Enabled = false
		end
	elseif wallRun then
		-- Correr por la pared: sigue el muro a la velocidad que traía, bajando despacio
		wallRun.remaining -= dt
		local still = wallIn(-wallRun.normal)
		local corner = obstacleAhead(wallRun.tangent, wallRun.speed * dt * 1.5 + 0.6)
		if corner then
			stopAgainst(corner.Normal)
		end
		if wallRun.remaining <= 0 or not still or state.grounded or corner then
			endWallRun()
		else
			dashVelocity.VectorVelocity = wallRun.tangent * wallRun.speed + Vector3.new(0, -Config.WallRunSink, 0)
		end
	elseif lunge then
		-- Avance de un golpe; durante el hitstop se congela
		if lunge.hold > 0 then
			lunge.hold -= dt
			dashVelocity.VectorVelocity = Vector3.zero
		else
			lunge.remaining -= dt
			dashVelocity.VectorVelocity = lunge.velocity
			local wall = obstacleAhead(lunge.velocity, lunge.velocity.Magnitude * dt * 1.5 + 0.4)
			if wall then
				lunge.remaining = 0
				stopAgainst(wall.Normal)
			end
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
		local wall = obstacleAhead(dashVelocity.VectorVelocity, dashVelocity.VectorVelocity.Magnitude * dt * 1.5 + 0.4)
		if wall then
			alpha = 1
			stopAgainst(wall.Normal)
		end
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

	-- Paredes en el aire: carrera por la pared, agarre de borde y deslizamiento
	local moveDir = flat(humanoid.MoveDirection)
	local wantSlide = false
	if not state.grounded and not dash and not lunge and not wallPush then
		-- Carrera por la pared: en sprint, con un muro al costado y avanzando a lo largo de él
		if not wallRun and not wallRunUsed and baseSpeed >= Config.WallRunMinSpeed and moveDir.Magnitude > 0.5 and velocity.Y > -8 then
			local right = flat(root.CFrame.RightVector)
			for _, side in ipairs({ right, -right }) do
				local hit = wallIn(side)
				if hit then
					local normal = flat(hit.Normal).Unit
					local along = moveDir.Unit - normal * moveDir.Unit:Dot(normal)
					if along.Magnitude > 0.6 and math.abs(moveDir.Unit:Dot(normal)) < 0.5 then
						wallRunUsed = true
						wallRun = { tangent = along.Unit, speed = math.max(flat(velocity).Magnitude, Config.WallRunMinSpeed), remaining = Config.WallRunTime, normal = normal }
						dashVelocity.MaxAxesForce = Vector3.new(FORCE, FORCE, FORCE)
						dashVelocity.VectorVelocity = wallRun.tangent * wallRun.speed
						dashVelocity.Enabled = true
						root.CFrame = CFrame.lookAt(root.Position, root.Position + wallRun.tangent)
						wallRunEvent:Fire(normal)
						log("Carrera por la pared")
						break
					end
				end
			end
		end
		if not wallRun then
			local mantled = tryMantle(moveDir)
			-- Deslizamiento: cayendo y empujando contra un muro, se cae más lento
			if not mantled and velocity.Y < 0 and moveDir.Magnitude > 0.5 then
				local hit = wallIn(moveDir)
				if hit and moveDir.Unit:Dot(flat(hit.Normal).Unit) < -0.5 then
					wantSlide = true
				end
			end
		end
	end
	-- Deslizamiento con una fuerza solo vertical y constante: caída suave y exacta (corregir la velocidad
	-- cuadro a cuadro dejaba que la gravedad acelerara entre correcciones)
	if wantSlide and not dash and not lunge and not wallPush and not wallRun and not exitBlend then
		sliding = true
		dashVelocity.MaxAxesForce = Vector3.new(0, FORCE, 0)
		dashVelocity.VectorVelocity = Vector3.new(0, -Config.WallSlideSpeed, 0)
		dashVelocity.Enabled = true
	elseif sliding then
		sliding = false
		if not dash and not lunge and not wallPush and not wallRun and not exitBlend then
			dashVelocity.Enabled = false
		end
	end
	state.wallRunning = wallRun ~= nil
	state.wallSliding = sliding

	-- Caída más rápida que la subida
	if not state.grounded and velocity.Y < 0 and not (dash and dash.holdHeight) and not sliding and not wallRun then
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
