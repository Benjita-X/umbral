-- Suite de la auditoría de la Fase 3: reglas puras (sin red) y un intento de trampa real.
--   A. Pruebas unitarias de reglas: MoveSchema y geometría de Hurtbox.
--   C. Simulación adversarial: informar una posición falsa más cerca del rival para ganar alcance.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

return function(ctx)
	local Config, Combat = ctx.CombatConfig, ctx.Combat
	local record, waitUntil = ctx.record, ctx.waitUntil
	local player = ctx.player
	local shared = ReplicatedStorage:WaitForChild("Shared")
	local MoveSchema = require(shared:WaitForChild("Combat"):WaitForChild("MoveSchema"))
	local Hurtbox = require(shared:WaitForChild("Combat"):WaitForChild("Hurtbox"))

	-- ---------- A1. Esquema de movimientos ----------
	local problems, count = MoveSchema.Validate(Config)
	record("[Unitaria] Esquema de movimientos coherente", #problems == 0, string.format("%d movimientos revisados · %s", count, if #problems == 0 then "0 problemas" else table.concat(problems, " | ")))

	-- El validador detecta definiciones rotas (no aprueba cualquier cosa)
	local broken = {
		Attacks = { Malo = { label = "Malo", startup = 0, active = 0.1, recovery = 0.1, damage = 1, posture = 1, shape = "box", deflectable = false, guardable = false, contrapaso = false } },
		Sparring = { Attacks = {}, Profiles = { x = { pattern = { "NoExiste" } } } },
	}
	local brokenProblems = MoveSchema.Validate(broken)
	record("[Unitaria] El esquema detecta movimientos mal definidos", #brokenProblems >= 3, string.format("%d problemas detectados en un movimiento roto a propósito", #brokenProblems))

	-- ---------- A2. Geometría de la Hurtbox (independiente del avatar) ----------
	local jab = Config.Attacks.Jab
	local origin = CFrame.lookAt(Vector3.zero, Vector3.new(0, 0, -1))
	local function hits(targetPosition, targetLook, tolerance)
		local target = CFrame.lookAt(targetPosition, targetPosition + (targetLook or Vector3.new(0, 0, 1)))
		return Hurtbox.AttackHits(origin, jab.range, jab.hitboxSize, target, tolerance)
	end
	local cases = {
		{ "de frente a 3,2 studs", hits(Vector3.new(0, 0, -3.2)), true },
		{ "de frente a 9 studs", hits(Vector3.new(0, 0, -9)), false },
		{ "a la espalda", hits(Vector3.new(0, 0, 3)), false },
		{ "de lado dentro del ancho", hits(Vector3.new(2.5, 0, -3)), true },
		{ "de lado fuera del ancho", hits(Vector3.new(5, 0, -3)), false },
		{ "más bajo (avatar chico, raíz 1,5 studs abajo)", hits(Vector3.new(0, -1.5, -3.2)), true },
		{ "más alto (avatar grande, raíz 1,5 studs arriba)", hits(Vector3.new(0, 1.5, -3.2)), true },
		{ "muy por encima (salto de 8 studs)", hits(Vector3.new(0, 8, -3.2)), false },
		{ "objetivo girado 90° (misma distancia)", hits(Vector3.new(0, 0, -3.2), Vector3.new(1, 0, 0)), true },
	}
	local wrong = {}
	for _, case in ipairs(cases) do
		if case[2] ~= case[3] then
			table.insert(wrong, case[1])
		end
	end
	record("[Unitaria] Hurtbox estándar: frente, lados, alturas y giros", #wrong == 0, if #wrong == 0 then string.format("%d casos geométricos correctos", #cases) else "incorrectos: " .. table.concat(wrong, ", "))

	-- El alcance máximo NO depende del avatar: lo fija la caja estándar (sin tolerancia del servidor)
	local maxReach = 0
	for d = 2, 12, 0.05 do
		if hits(Vector3.new(0, 0, -d)) then
			maxReach = d
		end
	end
	local expectedReach = 0.5 + jab.range + Hurtbox.Size.Z / 2
	record("[Unitaria] Alcance del Jab fijado por la caja estándar", math.abs(maxReach - expectedReach) <= 0.06, string.format("%.2f studs (esperado %.2f = 0,5 + alcance + medio fondo)", maxReach, expectedReach))

	-- ---------- C1. Posición falsificada para ganar alcance ----------
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local request = remotes:WaitForChild("SolicitudGolpe")
	local startRemote = remotes:WaitForChild("InicioAtaque")
	local dummy = nil
	for _, model in ipairs(CollectionService:GetTagged("Objetivo")) do
		if model.Name == "Muneco3" then
			dummy = model
		end
	end
	if not dummy then
		ctx.skip("[Adversarial] Posición falsa no da alcance", "no se encontró el muñeco 3")
		return
	end
	local dummyRoot = dummy:WaitForChild("HumanoidRootPart")
	local dummyHumanoid = dummy:FindFirstChildOfClass("Humanoid")
	local reach = 0.5 + jab.range + Hurtbox.Size.Z / 2 + Config.Validation.Tolerance -- lo máximo que acepta el servidor
	local away = Vector3.new(0, 0, 1)
	local realDistance = reach + 1.5 -- de verdad, fuera de alcance
	local position = dummyRoot.Position + away * realDistance
	ctx.teleport(Vector3.new(position.X, dummyRoot.Position.Y + 0.5, position.Z), -away)
	task.wait(0.6) -- que el historial observado registre la posición real

	local seq = Combat.State.sequence + 500
	local rejected0 = player:GetAttribute("GolpesRechazados") or 0
	local health0 = dummyHumanoid.Health
	startRemote:FireServer(seq, "Jab", Workspace:GetServerTimeNow())
	task.wait(jab.startup + 0.02)
	-- Dice estar 3,5 studs más cerca (dentro del alcance): con el radio fijo anterior (4 studs) se aceptaba
	local spoofed = ctx.root.Position - away * 3.5
	request:FireServer({ attack = "Jab", seq = seq, target = dummy, charge = 0, t = Workspace:GetServerTimeNow(), pos = spoofed, look = -away })
	waitUntil(function()
		return (player:GetAttribute("GolpesRechazados") or 0) > rejected0
	end, 1.5)
	local reason = tostring(player:GetAttribute("UltimoRechazo"))
	record(
		"[Adversarial] Posición falsa no da alcance",
		(player:GetAttribute("GolpesRechazados") or 0) == rejected0 + 1 and dummyHumanoid.Health == health0,
		string.format("real a %.1f studs, informó %.1f · motivo: %s", realDistance, realDistance - 3.5, reason)
	)
	Combat.State.sequence = seq + 10
	task.wait(0.4)
end
