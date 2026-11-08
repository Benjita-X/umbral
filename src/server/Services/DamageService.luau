-- DamageService: valida en el servidor los golpes que informan los clientes y aplica daño y empuje.
-- El cliente nunca decide el daño: solo dice "golpeé a X con el ataque Y".
-- Fase 2: los objetivos válidos son los muñecos (etiqueta "Objetivo"). El PvP llega en la Fase 4.
--
-- Compensación de latencia acotada (ver PositionService): el golpe se juzga en su instante `t`.
--   · Atacante: la posición que informó en `t`, CONFIRMADA por la física que observa el servidor.
--   · Objetivo: dónde lo veía el atacante, es decir, el historial observado en `t - latencia de ida`.
--   · Alcance: caja del ataque contra la caja estándar del objetivo (Hurtbox), con 1,5 studs de margen.
-- La espera máxima está acotada; si la posición no se confirma, el golpe se rechaza.
--
-- Secuencia legal (autoridad del servidor sobre el combo): el cliente avisa cada INICIO de ataque
-- (remote "InicioAtaque": seq, nombre, hora). El servidor comprueba que el ataque sea legal según el
-- anterior (Jab → Directo → Patada; el combo puede volver a Jab), que no empiece antes de que el
-- anterior pudiera cancelarse, que el golpe fuerte haya podido cargarse, y luego que cada golpe
-- informado pertenezca a un inicio aceptado y caiga dentro de SU ventana activa. Así nadie pide
-- "Patada" o "Fuerte" con carga completa a voluntad para hacer más daño.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(shared:WaitForChild("Config"):WaitForChild("CombatConfig"))
local Hurtbox = require(shared:WaitForChild("Combat"):WaitForChild("Hurtbox"))
local DefenseService = require(script.Parent:WaitForChild("DefenseService"))
local ResonanceService = require(script.Parent:WaitForChild("ResonanceService"))
local PositionService = require(script.Parent:WaitForChild("PositionService"))
local BalanceService = require(script.Parent:WaitForChild("BalanceService"))

local RemoteGuard = require(script.Parent:WaitForChild("RemoteGuard"))

local DamageService = {}

-- Se dispara con cada golpe aplicado: (jugador, objetivo, nombreDelAtaque, extra)
-- extra: { stun = segundos } cuando el golpe aturde (habilidades, golpes a un enemigo en el aire)
local hitApplied = Instance.new("BindableEvent")
DamageService.HitApplied = hitApplied.Event

-- Se dispara cuando un golpe que deja una recuperación larga (remate o golpe fuerte) termina SIN conectar:
-- (jugador, nombreDelAtaque, horaFinDeLaRecuperación). Condición verificable para los Golpes de Oportunidad.
local attackWhiffed = Instance.new("BindableEvent")
DamageService.AttackWhiffed = attackWhiffed.Event

local FORCE = 4e5 -- suficiente para el empuje; con 1e7 los golpes metían al objetivo dentro de las paredes
local validation = CombatConfig.Validation
local records = {} -- [player] = { lastSeq, lastSeqTime, seqTargets = { [seq] = { [model] = true } }, recent = { tiempos }, starts = { [seq] = inicio }, lastStart }
local confirmedRemote
local rejectedRemote -- "GolpeRechazado": solo a quien golpeó, { seq, target, reason }
local modifier = nil -- función(player, target, attackName, bodies) → multiplicador, nota, conservarOrientación

-- Reglas de daño propias de un enemigo (p. ej. la coraza frontal del Centinela): las registra SparringService
function DamageService.SetModifier(fn)
	modifier = fn
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- `seq` y `target` (si se conocen): el cliente sabe QUÉ golpe no contó (su ✕ va sobre ese objetivo y, si era el
-- único contacto del ataque, ese ataque pasa a ser un golpe fallado también en su pantalla)
local function reject(player, reason, seq, target)
	player:SetAttribute("GolpesRechazados", (player:GetAttribute("GolpesRechazados") or 0) + 1)
	player:SetAttribute("UltimoRechazo", reason)
	if rejectedRemote and type(seq) == "number" then
		rejectedRemote:FireClient(player, { seq = seq, target = if typeof(target) == "Instance" then target else nil, reason = reason })
	end
	if RunService:IsStudio() then
		warn(string.format("[UMBRAL] Golpe rechazado de %s: %s", player.Name, reason))
	end
end

local function recordFor(player)
	local record = records[player]
	if not record then
		record = { lastSeq = -1, lastSeqTime = -math.huge, seqTargets = {}, recent = {}, starts = {}, lastStart = nil, startTimes = {}, pending = {}, claimed = {} }
		records[player] = record
	end
	return record
end

-- ---------- Combos aéreos (habilidades) ----------
-- Un enemigo lanzado queda "en el aire" un rato (juggle): cada golpe que recibe así lo sostiene flotando un
-- instante en vez de empujarlo lejos. Solo para personajes que simula el servidor (muñecos y enemigos).
local juggle = CombatConfig.Eco.Juggle
local juggles = setmetatable({}, { __mode = "k" }) -- [modelo] = os.clock() hasta el que sigue en el aire

local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Exclude
floorParams.RespectCanCollide = true

-- Altura de los pies sobre el suelo (0 = de pie; math.huge = no hay suelo debajo)
function DamageService.HeightAboveFloor(model)
	local root = model and model:FindFirstChild("HumanoidRootPart")
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return 0
	end
	floorParams.FilterDescendantsInstances = { model }
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -80, 0), floorParams)
	if not hit then
		return math.huge
	end
	return (root.Position.Y - hit.Position.Y) - (humanoid.HipHeight + root.Size.Y / 2)
end

-- Malabar con tope: tras MAX_JUGGLE s seguidos en el aire, el objetivo se suelta, cae y RESISTE nuevos
-- lanzamientos un rato (no hay combos aéreos infinitos)
local MAX_JUGGLE, RESIST_TIME = 4.5, 2
local juggleSince = setmetatable({}, { __mode = "k" })
local resistUntil = setmetatable({}, { __mode = "k" })

function DamageService.Resisting(model)
	return (resistUntil[model] or 0) > os.clock()
end

function DamageService.MarkJuggle(model, seconds)
	local clock = os.clock()
	if DamageService.Resisting(model) then
		return
	end
	local current = juggles[model]
	if not current or clock > current then
		juggleSince[model] = clock -- empieza un malabar nuevo
	elseif juggleSince[model] and clock - juggleSince[model] > MAX_JUGGLE then
		juggles[model] = nil
		resistUntil[model] = clock + RESIST_TIME
		model:SetAttribute("ResisteHasta", Workspace:GetServerTimeNow() + RESIST_TIME)
		local root = model:FindFirstChild("HumanoidRootPart")
		if root then
			DamageService.Release(root)
		end
		return
	end
	juggles[model] = math.max(juggles[model] or 0, clock + seconds)
end

-- ¿Está en el aire por un lanzamiento (y todavía lejos del suelo)?
function DamageService.IsJuggled(model)
	local untilTime = juggles[model]
	if not untilTime or os.clock() > untilTime then
		return false
	end
	return DamageService.HeightAboveFloor(model) > juggle.MinHeight
end

local function constraintOn(targetRoot, name, axes)
	local attachment = targetRoot:FindFirstChild("UmbralEmpujeA")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "UmbralEmpujeA"
		attachment.Parent = targetRoot
	end
	local constraint = targetRoot:FindFirstChild(name)
	if not constraint then
		constraint = Instance.new("LinearVelocity")
		constraint.Name = name
		constraint.Attachment0 = attachment
		constraint.RelativeTo = Enum.ActuatorRelativeTo.World
		constraint.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		constraint.ForceLimitsEnabled = true
		constraint.ForceLimitMode = Enum.ForceLimitMode.PerAxis
		constraint.Enabled = false
		constraint.Parent = targetRoot
	end
	constraint.MaxAxesForce = axes
	return constraint
end

-- Sostiene al objetivo en el aire durante duration s (sin gravedad; riseSpeed > 0 lo sube despacio)
function DamageService.Suspend(targetRoot, duration, riseSpeed)
	if not targetRoot or duration <= 0 or DamageService.Resisting(targetRoot.Parent) then
		return
	end
	local hold = constraintOn(targetRoot, "UmbralSuspension", Vector3.new(0, FORCE, 0))
	local token = (hold:GetAttribute("Token") or 0) + 1
	hold:SetAttribute("Token", token)
	hold.VectorVelocity = Vector3.new(0, riseSpeed or 0, 0)
	hold.Enabled = true
	task.delay(duration, function()
		if hold.Parent and hold:GetAttribute("Token") == token then
			hold.Enabled = false
		end
	end)
end

-- Suelta al objetivo (deja de flotar)
function DamageService.Release(targetRoot)
	local hold = targetRoot and targetRoot:FindFirstChild("UmbralSuspension")
	if hold then
		hold:SetAttribute("Token", (hold:GetAttribute("Token") or 0) + 1)
		hold.Enabled = false
	end
end

-- Lleva al objetivo hacia un punto en duration s (atraer, subir, estampar). Se acorta antes de una pared o
-- del suelo: nunca lo mete dentro de nada.
function DamageService.DragTo(targetRoot, point, duration)
	if not targetRoot or duration <= 0 then
		return
	end
	local offset = point - targetRoot.Position
	local distance = offset.Magnitude
	if distance < 0.2 then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { targetRoot.Parent }
	params.RespectCanCollide = true
	local ok, hit = pcall(Workspace.Spherecast, Workspace, targetRoot.Position, 1, offset, params)
	local blocker = "nada"
	if ok and hit then
		local model = hit.Instance:FindFirstAncestorOfClass("Model")
		if not (model and model:FindFirstChildOfClass("Humanoid")) then
			distance = math.max(0, hit.Distance - 1.2)
			blocker = hit.Instance:GetFullName()
		end
	end
	-- Diagnóstico (pruebas): cuánto se arrastra y qué lo frenó
	targetRoot:SetAttribute("UltimoArrastre", string.format("%.1f de %.1f · %s", distance, offset.Magnitude, blocker))
	if distance < 0.2 then
		return
	end
	local drag = constraintOn(targetRoot, "UmbralArrastre", Vector3.new(FORCE, FORCE, FORCE))
	local token = (drag:GetAttribute("Token") or 0) + 1
	drag:SetAttribute("Token", token)
	drag.VectorVelocity = offset.Unit * (distance / duration)
	drag.Enabled = true
	local startPosition = targetRoot.Position
	task.delay(duration, function()
		-- Cuánto lo movió de verdad el arrastre (pruebas: la pantalla lo ve con retraso variable)
		targetRoot:SetAttribute("ArrastreMovido", math.floor((targetRoot.Position - startPosition).Magnitude * 10 + 0.5) / 10)
		if drag.Parent and drag:GetAttribute("Token") == token then
			drag.Enabled = false
			targetRoot.AssemblyLinearVelocity = Vector3.new(0, math.min(targetRoot.AssemblyLinearVelocity.Y, 0), 0)
		end
	end)
end

local WALL_SPLAT_SPEED = 38 -- empujón (studs/s) desde el que estampa contra la pared
local WALL_SPLAT_TIME = 1 -- s con daño extra tras estamparse
local WALL_SPLAT_BONUS = 1.25

-- Combos muy largos: desde el golpe COMBO_FREE + 1 seguido sobre el mismo objetivo (sin pausas de más de
-- COMBO_GAP s), cada golpe hace COMBO_DECAY menos, hasta COMBO_FLOOR. Los golpes pequeños y repetidos (menos de
-- COMBO_MIN_DAMAGE: tornado, tótem, quemaduras) ni cuentan ni se reducen. Un combo infinito no basta para ganar.
local COMBO_FREE, COMBO_GAP, COMBO_DECAY, COMBO_FLOOR, COMBO_MIN_DAMAGE = 8, 1.6, 0.07, 0.5, 4
local comboChains = setmetatable({}, { __mode = "k" }) -- [objetivo] = { [atacante] = cadena }
local function comboScale(target, damage, attacker)
	if damage < COMBO_MIN_DAMAGE then
		return 1
	end
	-- Por pareja atacante-objetivo: dos jugadores contra el mismo jefe no se reducen el daño entre sí
	local byAttacker = comboChains[target]
	if not byAttacker then
		byAttacker = setmetatable({}, { __mode = "k" })
		comboChains[target] = byAttacker
	end
	local key = attacker or target
	local chain = byAttacker[key]
	local clock = os.clock()
	if not chain or clock - chain.last > COMBO_GAP then
		chain = { count = 0, last = clock }
		byAttacker[key] = chain
	end
	chain.count += 1
	chain.last = clock
	if chain.count <= COMBO_FREE then
		return 1
	end
	return math.max(COMBO_FLOOR, 1 - (chain.count - COMBO_FREE) * COMBO_DECAY)
end

-- ¿Hay algo sólido (no un personaje) entre el atacante y el objetivo? Un golpe no atraviesa paredes.
local function solidBetween(attackerCharacter, target, from, to)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local ignore = { target }
	if attackerCharacter then
		table.insert(ignore, attackerCharacter)
	end
	local start = from + Vector3.new(0, 1, 0)
	local segment = (to + Vector3.new(0, 1, 0)) - start
	for _ = 1, 4 do
		params.FilterDescendantsInstances = ignore
		local hit = Workspace:Raycast(start, segment, params)
		if not hit then
			return false
		end
		local model = hit.Instance:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChildOfClass("Humanoid") then
			table.insert(ignore, model) -- otro personaje en medio: no es una pared
		else
			return true
		end
	end
	return false
end

DamageService.SolidBetween = solidBetween

-- Daño extra contra un objetivo recién estampado en la pared
local function wallBonus(target)
	return if (target:GetAttribute("ParedHasta") or 0) > Workspace:GetServerTimeNow() then WALL_SPLAT_BONUS else 1
end

local function knockback(targetRoot, direction, speed, up)
	local attachment = targetRoot:FindFirstChild("UmbralEmpujeA")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "UmbralEmpujeA"
		attachment.Parent = targetRoot
	end
	local push = targetRoot:FindFirstChild("UmbralEmpuje")
	if not push then
		push = Instance.new("LinearVelocity")
		push.Name = "UmbralEmpuje"
		push.Attachment0 = attachment
		push.RelativeTo = Enum.ActuatorRelativeTo.World
		push.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		push.ForceLimitsEnabled = true
		push.ForceLimitMode = Enum.ForceLimitMode.PerAxis
		push.MaxAxesForce = Vector3.new(FORCE, 0, FORCE)
		push.Enabled = false
		push.Parent = targetRoot
	end
	-- Rebote: empujar contra el muro a un objetivo recién estampado lo devuelve hacia el atacante, un poco en el
	-- aire (una ruta de combo, no solo daño). Un rebote por estampado.
	local model = targetRoot.Parent
	local wallNormal = model:GetAttribute("ParedNormal")
	if speed > 0 and typeof(wallNormal) == "Vector3" and (model:GetAttribute("ParedHasta") or 0) > Workspace:GetServerTimeNow() and direction:Dot(wallNormal) < -0.3 then
		model:SetAttribute("ParedHasta", nil)
		model:SetAttribute("RebotaHasta", Workspace:GetServerTimeNow() + 0.6)
		direction = (direction - 2 * direction:Dot(wallNormal) * wallNormal)
		direction = Vector3.new(direction.X, 0, direction.Z)
		direction = if direction.Magnitude > 0.01 then direction.Unit else Vector3.new(wallNormal.X, 0, wallNormal.Z).Unit
		speed *= 0.6
		up = math.max(up, 24)
	end
	-- El empuje se acorta si hay una pared detrás del objetivo (no lo mete dentro ni lo atraviesa). Si el empujón
	-- era fuerte, se estampa: queda pegado un instante y recibe más daño un rato (combo de pared)
	local wallHit = nil
	if speed > 0 and direction.Magnitude > 0.01 then
		local travel = speed * CombatConfig.Dummy.KnockbackTime
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { targetRoot.Parent }
		params.RespectCanCollide = true
		local ok, hit = pcall(Workspace.Spherecast, Workspace, targetRoot.Position, 0.9, direction.Unit * (travel + 1), params)
		if ok and hit and math.abs(hit.Normal.Y) < 0.6 then
			if speed >= WALL_SPLAT_SPEED then
				wallHit = hit
			end
			speed = math.max(0, hit.Distance - 1) / CombatConfig.Dummy.KnockbackTime
		end
	end
	if wallHit then
		model:SetAttribute("ParedPunto", wallHit.Position)
		model:SetAttribute("ParedNormal", wallHit.Normal)
		model:SetAttribute("ParedHasta", Workspace:GetServerTimeNow() + WALL_SPLAT_TIME)
		task.delay(CombatConfig.Dummy.KnockbackTime, function()
			if targetRoot.Parent then
				DamageService.Suspend(targetRoot, 0.4) -- pegado a la pared un instante
			end
		end)
	end
	local token = (push:GetAttribute("Token") or 0) + 1
	push:SetAttribute("Token", token)
	push.VectorVelocity = direction * speed
	push.Enabled = speed > 0
	if up > 0 then
		local v = targetRoot.AssemblyLinearVelocity
		targetRoot.AssemblyLinearVelocity = Vector3.new(v.X, up, v.Z)
	end
	task.delay(CombatConfig.Dummy.KnockbackTime, function()
		if push.Parent and push:GetAttribute("Token") == token then
			push.Enabled = false
		end
	end)
end

-- Partes vivas del golpe (se vuelven a leer al reintentar: el jugador pudo reaparecer)
local function bodies(player, target)
	local character = player.Character
	local attackerHumanoid = character and character:FindFirstChildOfClass("Humanoid")
	local attackerRoot = character and character:FindFirstChild("HumanoidRootPart")
	local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	if not attackerHumanoid or not attackerRoot or attackerHumanoid.Health <= 0 then
		return nil, "atacante sin personaje"
	end
	if not targetHumanoid or not targetRoot then
		return nil, "objetivo sin cuerpo"
	end
	if targetHumanoid.Health <= 0 and target:HasTag("Sparring") then
		return nil, "objetivo vencido"
	end
	return { attackerRoot = attackerRoot, targetHumanoid = targetHumanoid, targetRoot = targetRoot }
end


-- ---------- Inicios de ataque (secuencia legal) ----------
local LIGHT_NEXT = {} -- [ataque] = siguiente del combo
local CHAIN_START = {} -- [ataque] = true si empieza el combo de su arma
local PAUSE_NEXT = {} -- [ataque] = remate de su cadena (pausa en la cadena: tras una pausa, el golpe salta al remate)
local function addChain(chain)
	for i, name in ipairs(chain) do
		LIGHT_NEXT[name] = chain[i % #chain + 1]
		if i < #chain then
			PAUSE_NEXT[name] = chain[#chain]
		end
	end
	CHAIN_START[chain[1]] = true
end
addChain(CombatConfig.LightChain)
for key, weapon in pairs(CombatConfig.Weapons) do
	if key ~= "Order" and type(weapon) == "table" and type(weapon.chain) == "table" then
		addChain(weapon.chain)
	end
end
local FIRST_LIGHT = CombatConfig.LightChain[1]

-- Golpes especiales (EXPERIMENTAL): el golpe tras el Paso exige un Paso reciente y el golpe en picada exige
-- estar en el aire con altura. Lo comprueba el servidor con SUS registros (Pasos informados, física observada).
local plungeParams = RaycastParams.new()
plungeParams.FilterType = Enum.RaycastFilterType.Exclude
plungeParams.RespectCanCollide = true
local function specialAllowed(player, def, t)
	if def.special == "dash" then
		local window = CombatConfig.Weapons.DashWindow
		-- Un Paso reciente, o LLEGAR con el gancho a un enemigo: un gancho que el servidor aceptó (enganche real, a
		-- alcance y a la vista; WeaponService) y, al empezar el golpe, estar junto a ESE enemigo. No vale "se movió
		-- mucho": un empujón o un sprint no son un gancho, y una llegada corta junto a una pared sí lo es.
		local grapple = CombatConfig.Weapons.Grapple
		local hooked = false
		local hook = DefenseService.FindGrapple(player, t - (grapple.EnemyRange + 6) / grapple.Speed - 0.35 - window - 0.3, t + 0.05)
		if hook and hook.enemy and hook.target.Parent then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local enemyRoot = hook.target:FindFirstChild("HumanoidRootPart")
			local reported = PositionService.ReportedAt(player, t)
			local me = if reported and root and (reported - root.Position).Magnitude <= 16 then reported elseif root then root.Position else nil
			local seen = enemyRoot and PositionService.ObservedAt(hook.target, t - PositionService.OneWay(player))
			local them = if seen then seen.Position elseif enemyRoot then enemyRoot.Position else nil
			hooked = me ~= nil and them ~= nil and flat(them - me).Magnitude <= grapple.ArriveDistance
		end
		if not hooked and not DefenseService.FindPaso(player, t - window - 0.12, t + 0.05) then
			return false, if hook and hook.enemy then "golpe tras el gancho sin llegar al enemigo" else "golpe tras el Paso sin Paso"
		end
	elseif def.special == "plunge" then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid then
			return false, "picada sin personaje"
		end
		-- La física replicada llega con retraso (décimas): se usa la posición que el cliente informó con el
		-- inicio, siempre que sea coherente con lo observado (a pocos studs), y también la mayor altura observada
		-- en un instante corto alrededor del inicio. El suelo es la geometría, no otros personajes.
		local standing = humanoid.HipHeight + root.Size.Y / 2
		local best = -math.huge
		local samples = {}
		local reported = PositionService.ReportedAt(player, t)
		if reported and (reported - root.Position).Magnitude <= 16 then
			table.insert(samples, reported)
		end
		for _, dt in ipairs({ 0, -0.08, -0.16, -0.24, 0.06 }) do
			local seen = PositionService.ObservedAt(character, t + dt)
			table.insert(samples, if seen then seen.Position else root.Position)
		end
		for _, position in ipairs(samples) do
			local ignore = { character }
			local feet = math.huge
			for _ = 1, 4 do
				plungeParams.FilterDescendantsInstances = ignore
				local hit = Workspace:Raycast(position, Vector3.new(0, -80, 0), plungeParams)
				if not hit then
					break
				end
				local model = hit.Instance:FindFirstAncestorOfClass("Model")
				if model and model:FindFirstChildOfClass("Humanoid") then
					table.insert(ignore, model)
				else
					feet = (position.Y - hit.Position.Y) - standing
					break
				end
			end
			best = math.max(best, feet)
		end
		if best < CombatConfig.Weapons.PlungeMinHeight - 2 then
			return false, string.format("picada sin altura (%.1f studs)", best)
		end
	end
	return true
end

-- Lo mínimo que dura un ataque antes de poder empezar otro: su preparación (un Paso o un salto la
-- cancelan, así que no se exige esperar el impacto). Las horas son del reloj del cliente: el desfase de
-- la red no las acerca, por eso el margen puede ser pequeño.
local function minBusy(def, counter)
	return if counter then def.startup * CombatConfig.Defense.CounterStartupMultiplier else def.startup
end

-- ¿Es legal empezar `attackName` en la hora `t`, viniendo de `previous`? Devuelve ok, motivo, cargaMáxima
local function legalStart(previous, attackName, def, t)
	if not previous then
		return CHAIN_START[attackName] == true or def.heavy == true or def.special ~= nil, "el combo empieza por " .. FIRST_LIGHT, 1
	end
	local elapsed = t - previous.t
	-- Se usa la duración mínima posible (como Contraataque): el servidor y el cliente pueden discrepar
	-- por un instante sobre si la ventana de Contraataque seguía abierta, y eso no debe rechazar nada
	local busy = minBusy(previous.def, true)
	if elapsed < busy - validation.StartTimeSlack then
		return false, string.format("empezó %.2f s después del anterior (mínimo %.2f)", elapsed, busy), 0
	end
	if def.heavy then
		-- Hay que mantener Atacar HoldThreshold; la carga extra cabe en el tiempo libre desde el anterior
		local free = elapsed - busy
		local maxCharge = math.clamp((free - CombatConfig.HoldThreshold) / CombatConfig.HeavyMaxCharge + 0.15, 0, 1)
		if free < CombatConfig.HoldThreshold * 0.5 - validation.StartTimeSlack then
			return false, "golpe fuerte sin tiempo de mantener", 0
		end
		return true, nil, maxCharge
	end
	-- Ligeros: Jab siempre (el combo se reinicia); los demás, solo después de su anterior en la cadena
	-- Los especiales (tras el Paso, en picada) pueden salir en cualquier momento libre: sus condiciones se
	-- comprueban aparte (specialAllowed)
	if def.special ~= nil or CHAIN_START[attackName] or LIGHT_NEXT[previous.name] == attackName then
		return true, nil, 0
	end
	-- Pausa en la cadena: el remate puede seguir a cualquier golpe anterior de su cadena tras una pausa real (el
	-- golpe anterior entero y luego la pausa; se admite media pausa de margen)
	local whole = previous.def.startup + previous.def.active + previous.def.recovery
	if PAUSE_NEXT[previous.name] == attackName and elapsed >= whole + CombatConfig.ChainPause.min * 0.5 - validation.StartTimeSlack then
		return true, nil, 0
	end
	return false, string.format("%s no puede seguir a %s", attackName, previous.name), 0
end

local function handleStart(player, seq, attackName, t, position, look)
	if not RemoteGuard.Allow(player, "InicioGolpe") then
		return
	end
	local def = type(attackName) == "string" and CombatConfig.Attacks[attackName]
	if not def or type(seq) ~= "number" or seq ~= seq then
		return reject(player, "inicio inválido")
	end
	-- Los golpes especiales mandan la posición del inicio (la picada la necesita: la física llega con retraso)
	if def.special and typeof(position) == "Vector3" then
		PositionService.Report(player, t, position, look)
	end
	-- Hora de inicio vieja (el cliente o el servidor se trabó un instante) o inválida: se usa la hora del
	-- servidor, que no da ventaja (solo hace más estricta la ventana del golpe, por eso se marca "clamped")
	local clamped = false
	if not PositionService.ValidTime(player, t) then
		if type(t) ~= "number" or t ~= t or t > Workspace:GetServerTimeNow() + 0.05 then
			return reject(player, "hora de inicio inválida")
		end
		t = Workspace:GetServerTimeNow()
		clamped = true
	end
	local record = recordFor(player)
	if record.lastStart and seq <= record.lastStart.seq then
		return reject(player, "inicio repetido o desordenado")
	end
	local clock = os.clock()
	local times = record.startTimes
	while times[1] and clock - times[1] > 1 do
		table.remove(times, 1)
	end
	if #times >= validation.MaxStartsPerSecond then
		return reject(player, "demasiados inicios por segundo")
	end
	if DefenseService.IsStunnedAt(player, t) then
		return reject(player, "inicio aturdido")
	end
	-- Cada golpe es de un arma: solo vale con el arma que lleva puesta
	if (def.weapon or "Punos") ~= (player:GetAttribute("Arma") or "Punos") then
		return reject(player, "golpe de otra arma")
	end
	if def.special then
		local allowed, reason = specialAllowed(player, def, t)
		if not allowed then
			return reject(player, reason)
		end
	end
	local ok, why, maxCharge = legalStart(record.lastStart, attackName, def, t)
	if not ok then
		return reject(player, "secuencia ilegal: " .. tostring(why))
	end
	table.insert(times, clock)
	local counterUntil = player:GetAttribute("ContraataqueHasta")
	local start = {
		seq = seq,
		name = attackName,
		def = def,
		t = t,
		maxCharge = maxCharge,
		clamped = clamped,
		counter = not def.heavy and counterUntil ~= nil and Workspace:GetServerTimeNow() <= counterUntil,
	}
	record.lastStart = start
	record.starts[seq] = start
	-- Remate o golpe fuerte: si al terminar su ventana activa no conectó, es un golpe fallado (castigable)
	if def.finisher then
		local activeEnd = def.startup + def.active + 0.1
		task.delay(activeEnd, function()
			if not start.hit and player.Parent then
				local recovery = def.recovery * CombatConfig.WhiffRecoveryMultiplier
				attackWhiffed:Fire(player, attackName, Workspace:GetServerTimeNow() + recovery)
			end
		end)
	end
	record.starts[seq - 12] = nil -- limpiar inicios viejos
end

-- Espera (acotada) el inicio de `seq`: llega por otro remote y puede adelantarse el golpe
local function startFor(player, seq)
	local record = recordFor(player)
	local deadline = os.clock() + 0.3
	while not record.starts[seq] and os.clock() < deadline do
		RunService.Heartbeat:Wait()
	end
	return record.starts[seq]
end

-- Ritmo (sin repetidos ni ráfagas imposibles) y aplicación del golpe
-- `geometry`: { attacker, target } = CFrames en el INSTANTE del golpe (las mismas que juzgaron el alcance)
-- `hitTime`: hora del golpe (del cliente, ya validada). El ritmo entre golpes se mide con ESA hora, no con
-- la de llegada: con la espera de confirmación y la latencia variable, dos golpes legítimos pueden
-- terminar de validarse en el mismo cuadro del servidor.
local function applyHit(player, attackName, def, seq, target, charge, b, geometry, hitTime)
	local record = recordFor(player)
	local now = os.clock()
	if seq < record.lastSeq - 8 then
		return reject(player, "secuencia vieja", seq, target)
	end
	if seq > record.lastSeq then
		local previousHit = record.lastSeqHitTime
		if previousHit and hitTime - previousHit < validation.MinSequenceInterval - validation.StartTimeSlack then
			return reject(player, "golpes demasiado seguidos", seq, target)
		end
		record.lastSeq = seq
		record.lastSeqTime = now
		record.lastSeqHitTime = hitTime
	end
	local targets = record.seqTargets[seq]
	if not targets then
		targets = {}
		record.seqTargets[seq] = targets
		record.seqTargets[seq - 10] = nil -- limpiar secuencias viejas
	end
	if targets[target] then
		return reject(player, "golpe repetido", seq, target)
	end
	local recent = record.recent
	while recent[1] and now - recent[1] > 1 do
		table.remove(recent, 1)
	end
	if #recent >= validation.MaxHitsPerSecond then
		return reject(player, "demasiados golpes por segundo", seq, target)
	end
	targets[target] = true
	if record.starts[seq] then
		record.starts[seq].hit = true
	end
	table.insert(recent, now)

	local damage = def.damage + (def.chargeBonus or 0) * charge
	-- Contraataque: el primer golpe tras un desvío perfecto o un Contrapaso hace más daño
	local counterUntil = player:GetAttribute("ContraataqueHasta")
	local counter = counterUntil ~= nil and Workspace:GetServerTimeNow() <= counterUntil
	if counter then
		damage *= CombatConfig.Defense.CounterDamageMultiplier
		player:SetAttribute("ContraataqueHasta", nil)
	end
	local note, keepFacing = nil, false
	if modifier then
		local multiplier
		multiplier, note, keepFacing = modifier(player, target, attackName, b, geometry)
		damage *= multiplier or 1
	end
	damage *= BalanceService.Outgoing(player, target) -- poder del jugador × resistencia del objetivo
	damage *= wallBonus(target)
	damage *= comboScale(target, damage, player)
	b.targetHumanoid.Health = math.max(0, b.targetHumanoid.Health - damage)
	-- Mejora "Resonancia viva": el remate del combo deja el estado del Eco que llevas (abre reacciones con los puños)
	if def.finisher and damage > 0 and BalanceService.HasUpgrade(player, "ResonanciaViva") then
		local element = player:GetAttribute("Eco")
		local t = Workspace:GetServerTimeNow()
		if element == "Agua" then
			target:SetAttribute("MojadoHasta", t + 4)
		elseif element == "Trueno" then
			target:SetAttribute("CargadoHasta", t + 3)
		elseif element == "Fuego" then
			target:SetAttribute("ArdeHasta", t + 2.5)
		else
			ResonanceService.Gain(player, "Golpe", target, "ResonanciaViva")
		end
	end
	-- Solo dan Resonancia los rivales que pelean (no los muñecos), con rendimiento decreciente si se
	-- repite el mismo golpe contra el mismo rival
	if damage > 0 and (target:HasTag("Sparring") or Players:GetPlayerFromCharacter(target)) then
		ResonanceService.Gain(player, "Golpe", target, attackName)
	end

	local direction = flat(b.targetRoot.Position - b.attackerRoot.Position)
	direction = if direction.Magnitude > 0.01 then direction.Unit else flat(b.attackerRoot.CFrame.LookVector).Unit
	local juggled = false
	if damage > 0 then
		if not keepFacing then
			b.targetRoot.CFrame = CFrame.lookAt(b.targetRoot.Position, b.targetRoot.Position - direction) -- mira al atacante
		end
		if DamageService.IsJuggled(target) then
			-- Combo aéreo: el golpe lo sostiene flotando (y aturdido) en vez de mandarlo lejos
			knockback(b.targetRoot, direction, def.knockback * juggle.HitKnockbackScale, 0)
			local v = b.targetRoot.AssemblyLinearVelocity
			b.targetRoot.AssemblyLinearVelocity = Vector3.new(v.X, juggle.HitKnockUp, v.Z)
			DamageService.Suspend(b.targetRoot, juggle.HitSuspend)
			DamageService.MarkJuggle(target, juggle.HitSuspend + 0.3)
			juggled = true
		else
			knockback(b.targetRoot, direction, def.knockback * (1 + charge * 0.5), def.knockUp * (1 + charge * 0.5))
		end
	end

	confirmedRemote:FireAllClients({
		attacker = player,
		target = target,
		attack = attackName,
		seq = seq,
		damage = damage,
		position = b.targetRoot.Position + Vector3.new(0, 1, 0),
		health = b.targetHumanoid.Health,
		counter = counter,
		note = note, -- texto corto para quien golpea ("¡POR LA ESPALDA!", "BLOQUEADO")
	})
	if damage > 0 then
		hitApplied:Fire(player, target, attackName, if juggled then { stun = juggle.HitStun } else nil)
	end
end

-- Daño que no viene de un golpe del combo (habilidades del Eco). Ya validado por quien lo llama (EcoService):
-- aplica daño, empuje y aviso igual que un golpe. Devuelve el daño aplicado.
-- spec: attackName, damage, direction, knockback, knockUp, ignoreModifier, y opcionales:
--   stun (s: el enemigo queda aturdido) · launch (true: el knockUp lanza aunque ya esté en el aire)
--   juggle (s: queda "en el aire" para un combo aéreo) · suspend (s flotando) · suspendDelay (s antes de flotar)
--   dragTo (Vector3) + dragTime (s): lo lleva a ese punto · synergy (nombre del combo, se muestra)
--   dot (true: daño de estado, sin física ni interrupciones) · noResonance (no da Resonancia)
function DamageService.ApplyExternalHit(player, target, spec)
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	local root = target:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return 0
	end
	if humanoid.Health <= 0 and target:HasTag("Sparring") then
		return 0 -- vencido: ya no recibe nada
	end
	-- Seguro PvP: las habilidades no pasan por desvío, guardia ni Contrapaso de un JUGADOR; hasta que lo hagan,
	-- no lo dañan (hoy solo apuntan a muñecos y enemigos, marcados "Objetivo")
	if Players:GetPlayerFromCharacter(target) and not CombatConfig.Eco.PvP then
		return 0
	end
	local damage = spec.damage
	local note = nil
	if modifier and not spec.ignoreModifier then
		local multiplier
		multiplier, note = modifier(player, target, spec.attackName, { attackerRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart") or root, targetRoot = root, targetHumanoid = humanoid })
		damage *= multiplier or 1
	end
	damage *= BalanceService.Outgoing(player, target)
	if not spec.dot then
		damage *= wallBonus(target)
		damage *= comboScale(target, damage, player)
	end
	humanoid.Health = math.max(0, humanoid.Health - damage)
	local stun = spec.stun or 0
	if damage > 0 then
		local direction = spec.direction
		if typeof(direction) ~= "Vector3" or direction.Magnitude < 0.01 then
			direction = Vector3.new(0, 0, -1)
		end
		local juggledNow = not spec.dot and not spec.launch and not spec.dragTo and DamageService.IsJuggled(target)
		if spec.dot then
			-- Daño de estado (quemadura, cortes extra): sin empuje ni cambios en el aire
		elseif spec.dragTo then
			DamageService.DragTo(root, spec.dragTo, spec.dragTime or 0.18)
		elseif juggledNow then
			-- En pleno combo aéreo: lo sostiene en vez de mandarlo lejos
			knockback(root, direction, (spec.knockback or 0) * juggle.HitKnockbackScale, 0)
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(v.X, juggle.HitKnockUp, v.Z)
			DamageService.Suspend(root, math.max(juggle.HitSuspend, spec.suspend or 0))
			DamageService.MarkJuggle(target, juggle.HitSuspend + 0.3)
			stun = math.max(stun, juggle.HitStun)
		else
			DamageService.Release(root)
			local up = spec.knockUp or 0
			if DamageService.Resisting(target) then
				up = math.min(up, 8)
			end
			knockback(root, direction, spec.knockback or 0, up)
		end
		if spec.juggle then
			DamageService.MarkJuggle(target, spec.juggle)
		end
		if spec.suspend and spec.suspend > 0 and not juggledNow then
			if spec.suspendDelay and spec.suspendDelay > 0 then
				task.delay(spec.suspendDelay, function()
					if root.Parent then
						DamageService.Suspend(root, spec.suspend)
					end
				end)
			else
				DamageService.Suspend(root, spec.suspend)
			end
		end
		-- Los enemigos que pelean dan Resonancia por los golpes de habilidad igual que por los del combo
		-- (con el mismo rendimiento decreciente); la definitiva la gasta y no la devuelve
		if target:HasTag("Sparring") and not spec.noResonance then
			ResonanceService.Gain(player, "Golpe", target, spec.attackName)
		end
		hitApplied:Fire(player, target, spec.attackName, { stun = stun, dot = spec.dot == true })
	end
	confirmedRemote:FireAllClients({
		attacker = player,
		target = target,
		attack = spec.attackName,
		damage = damage,
		position = root.Position + Vector3.new(0, 1, 0),
		health = humanoid.Health,
		counter = false,
		note = note,
		synergy = spec.synergy,
		element = spec.element, -- elemento del lanzamiento (no el Eco que lleve ahora): color y sonido coherentes
	})
	return damage
end

-- Juicio de un golpe (puede esperar a que la física observada confirme la posición): ventana activa, alcance y
-- paredes. Cada rechazo lleva el seq y el objetivo.
local function judgeHit(player, attackName, def, seq, target, charge, t)
	local function refuse(reason)
		return reject(player, reason, seq, target)
	end
	-- 4a. El golpe pertenece a un inicio aceptado del mismo ataque, y cae en su ventana activa
	local start = startFor(player, seq)
	if not start or start.name ~= attackName then
		return refuse("golpe sin inicio válido")
	end
	local minStartup = def.startup * CombatConfig.Defense.CounterStartupMultiplier
	local offset = t - start.t
	local tooEarly = offset < minStartup - validation.StartTimeSlack and not start.clamped
	if tooEarly or offset > def.startup + def.active + validation.HitWindowSlack then
		return refuse(string.format("golpe fuera de su ventana activa (%.2f s tras el inicio)", offset))
	end
	charge = math.min(charge, start.maxCharge)
	local attackerCFrame, whyNot = PositionService.ConfirmedAt(player, t)
	-- Alrededor de un teletransporte autorizado por el servidor (reaparecer, pruebas, la Grieta) lo
	-- informado puede mezclar el lugar viejo y el nuevo: se usa lo que el SERVIDOR observó en el
	-- instante del golpe (su historial), no la posición de ahora
	local teleportCandidates = nil
	if not attackerCFrame and PositionService.Teleporting(player) and player.Character then
		-- La replicación del salto llega unos cuadros tarde al historial: se prueban el instante del golpe,
		-- unos cuadros después y la posición actual (solo dentro del segundo autorizado)
		local root = player.Character:FindFirstChild("HumanoidRootPart")
		teleportCandidates = {
			PositionService.ObservedAt(player.Character, t),
			PositionService.ObservedAt(player.Character, t + 0.1),
			PositionService.ObservedAt(player.Character, t + 0.25),
			root and root.CFrame,
		}
		attackerCFrame = teleportCandidates[1] or teleportCandidates[4]
	end
	if not attackerCFrame then
		return refuse("posición no confirmada por la física observada (" .. tostring(whyNot) .. ")")
	end
	local current, problemNow = bodies(player, target)
	if not current then
		return refuse(problemNow)
	end
	-- El atacante veía al objetivo como estaba hace (latencia de ida + interpolación) aprox.
	local targetCFrame = PositionService.ObservedAt(target, t - PositionService.OneWay(player)) or current.targetRoot.CFrame
	if teleportCandidates then
		for _, candidate in ipairs(teleportCandidates) do
			if candidate and Hurtbox.AttackHits(candidate, def.range, def.hitboxSize, targetCFrame, validation.Tolerance) then
				attackerCFrame = candidate
				break
			end
		end
	end
	if not Hurtbox.AttackHits(attackerCFrame, def.range, def.hitboxSize, targetCFrame, validation.Tolerance) then
		return refuse(string.format(
			"fuera de alcance (%.1f studs) · %s seq %d contra %s · atacante en (%.0f, %.0f) · %.2f s tras el inicio",
			flat(targetCFrame.Position - attackerCFrame.Position).Magnitude,
			attackName,
			seq,
			target.Name,
			attackerCFrame.Position.X,
			attackerCFrame.Position.Z,
			t - start.t
		))
	end
	if solidBetween(player.Character, target, attackerCFrame.Position, targetCFrame.Position) then
		return refuse("golpe a través de una pared")
	end
	applyHit(player, attackName, def, seq, target, charge, current, { attacker = attackerCFrame, target = targetCFrame }, t)
end

local function handleHit(player, payload)
	if not RemoteGuard.Allow(player, "Golpe") then
		return
	end
	-- 1. Forma de la petición
	if type(payload) ~= "table" then
		return reject(player, "formato")
	end
	local attackName, seq, target, charge = payload.attack, payload.seq, payload.target, payload.charge
	local def = type(attackName) == "string" and CombatConfig.Attacks[attackName]
	if not def then
		return reject(player, "ataque desconocido")
	end
	if type(seq) ~= "number" or seq ~= seq then
		return reject(player, "secuencia inválida")
	end
	-- Este ataque tuvo contacto en la pantalla del jugador (aunque luego no cuente): su recuperación allí es la
	-- normal, no la alargada por fallar (lo usa WhiffRecoveryAt)
	local claims = recordFor(player).claimed
	claims[seq] = true
	claims[seq - 12] = nil
	if typeof(target) ~= "Instance" or not target:IsA("Model") or not target:HasTag("Objetivo") or not target:IsDescendantOf(workspace) then
		return reject(player, "objetivo inválido", seq)
	end
	charge = if type(charge) == "number" and charge == charge then math.clamp(charge, 0, 1) else 0

	-- 2. Cuerpos vivos y atacante en condiciones (aturdido no golpea; se perdona lo que mandó antes de
	-- enterarse del aturdimiento)
	local b, problem = bodies(player, target)
	if not b then
		return reject(player, problem, seq, target)
	end
	if DefenseService.IsStunnedAt(player, payload.t) then
		return reject(player, "aturdido", seq, target)
	end

	-- 3. El instante del golpe: hora coherente con el ping y posición informada en ese instante
	local t = payload.t
	if not PositionService.ValidTime(player, t) then
		return reject(player, "hora inválida", seq, target)
	end
	PositionService.Report(player, t, payload.pos, payload.look)

	-- 4. Alcance en ese instante (espera acotada a que la física observada confirme la posición). Mientras se
	-- juzga, el golpe queda PENDIENTE: una habilidad que corte la recuperación de este ataque espera el veredicto
	local record = recordFor(player)
	record.pending[seq] = (record.pending[seq] or 0) + 1
	task.spawn(function()
		local ok, problem = pcall(judgeHit, player, attackName, def, seq, target, charge, t)
		local left = (record.pending[seq] or 1) - 1
		record.pending[seq] = if left > 0 then left else nil
		if not ok then
			reject(player, "error al juzgar el golpe", seq, target)
			warn("[UMBRAL] " .. tostring(problem))
		end
	end)
end

-- ---------- Castigo al fallar, del lado del servidor ----------
-- Lo que vio la pantalla del jugador no basta: un golpe que el servidor rechazó es un golpe FALLADO, y su
-- recuperación no se corta con una habilidad (auditoría externa). ¿En la hora `t` el jugador seguía en la
-- recuperación de un ataque que no conectó? Ventana prudente, para no castigar nunca de más: desde el fin MÁS
-- TARDÍO posible de la fase activa (el avance puede alargar la preparación) hasta el fin MÁS TEMPRANO de la
-- recuperación que tuvo en su pantalla: la alargada por fallar si no hubo ningún contacto, la normal si lo hubo
-- (aunque el servidor lo rechazara). Un Paso, un gancho o un aturdimiento en medio ya cortaron el ataque. Si
-- quedan golpes de ese ataque por juzgar, espera su veredicto (acotado; casi siempre ya llegó). Devuelve true +
-- segundos que faltan.
local MAX_LUNGE_SPEED = 120 -- el mismo tope que usa el cliente para el avance de los golpes
local PHASE_SLACK = 0.05
-- Preparación más corta y más larga posibles en la pantalla del jugador. El Contraataque se toma en los dos
-- sentidos: cliente y servidor pueden discrepar justo en el borde de su ventana, y la duda favorece al jugador.
local function startupRange(def)
	local function range(counter)
		local fastest = if counter then def.startup * CombatConfig.Defense.CounterStartupMultiplier else def.startup
		local reach = if counter then math.max(CombatConfig.Defense.CounterMaxLunge, def.lunge or 0) else math.max(CombatConfig.MaxLunge, CombatConfig.LungeWithoutTarget, def.lunge or 0)
		return fastest, math.max(fastest, reach / MAX_LUNGE_SPEED - def.active * 0.5)
	end
	local fastest, slowest = range(false)
	if not def.heavy then
		local counterFastest, counterSlowest = range(true)
		fastest, slowest = math.min(fastest, counterFastest), math.max(slowest, counterSlowest)
	end
	return fastest, slowest
end

function DamageService.WhiffRecoveryAt(player, t)
	local record = records[player]
	local start = record and record.lastStart
	if not start or start.hit or start.clamped or type(t) ~= "number" or t ~= t then
		return false
	end
	local def = start.def
	local fastest, slowest = startupRange(def)
	local recovery = if record.claimed[start.seq] then def.recovery else def.recovery * CombatConfig.WhiffRecoveryMultiplier
	local from = start.t + slowest + def.active + PHASE_SLACK
	local to = start.t + fastest + def.active + recovery - PHASE_SLACK
	if t < from or t > to then
		return false
	end
	if DefenseService.FindPaso(player, start.t, t) or DefenseService.FindGrapple(player, start.t, t) or DefenseService.StunnedSince(player, start.t) then
		return false
	end
	local deadline = os.clock() + 0.5
	while not start.hit and (record.pending[start.seq] or 0) > 0 and os.clock() < deadline do
		RunService.Heartbeat:Wait()
	end
	if start.hit or record.lastStart ~= start then
		return false
	end
	return true, to - t
end

function DamageService.Start()
	local remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	local request = Instance.new("RemoteEvent")
	request.Name = "SolicitudGolpe"
	request.Parent = remotes
	confirmedRemote = Instance.new("RemoteEvent")
	confirmedRemote.Name = "GolpeConfirmado"
	confirmedRemote.Parent = remotes
	rejectedRemote = Instance.new("RemoteEvent")
	rejectedRemote.Name = "GolpeRechazado"
	rejectedRemote.Parent = remotes
	remotes.Parent = ReplicatedStorage

	local startRemote = Instance.new("RemoteEvent")
	startRemote.Name = "InicioAtaque"
	startRemote.Parent = remotes

	request.OnServerEvent:Connect(handleHit)
	startRemote.OnServerEvent:Connect(handleStart)
	Players.PlayerRemoving:Connect(function(player)
		records[player] = nil
	end)
end

return DamageService
