-- Estrés (EXPERIMENTAL): machacar todas las teclas al azar durante un rato, como alguien nervioso o un niño con
-- el teclado, y comprobar que NADA se queda trabado: el personaje vuelve a estar libre, se mueve, golpea, lanza
-- habilidades y el servidor las acepta. También cuenta los errores de los scripts del cliente mientras tanto.

local Players = game:GetService("Players")
local ScriptContext = game:GetService("ScriptContext")
local Workspace = game:GetService("Workspace")

return function(ctx)
	local Input = ctx.Input
	local record, waitUntil = ctx.record, ctx.waitUntil
	local player = ctx.player
	local controllers = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Controllers")
	local Eco = require(controllers:WaitForChild("EcoController"))
	local okLock, Fijar = pcall(require, controllers:WaitForChild("FijarObjetivoController"))

	local errors = {}
	local errorConnection = ScriptContext.Error:Connect(function(message)
		table.insert(errors, tostring(message))
	end)

	ctx.remote:FireServer("resonancia", 100)
	ctx.teleport(Vector3.new(0, 4, 30), Vector3.new(0, 0, 1))
	local ACTIONS = {
		"Atacar", "Atacar", "Atacar", "HabilidadZ", "HabilidadX", "HabilidadC", "HabilidadV", "Paso", "Saltar",
		"Eco1", "Eco2", "Eco3", "Eco4", "Eco5", "Arma", "Gancho", "FijarObjetivo",
	}
	local random = Random.new(20261107)
	local stop = os.clock() + 12
	local defending = false
	while os.clock() < stop do
		local action = ACTIONS[random:NextInteger(1, #ACTIONS)]
		Input.Trigger(action)
		-- A veces se mantiene la guardia o el golpe fuerte un momento
		local roll = random:NextNumber()
		if roll < 0.08 and not defending then
			Input.Press("Defender")
			defending = true
		elseif roll < 0.16 and defending then
			Input.Release("Defender")
			defending = false
		elseif roll < 0.2 then
			Input.Press("Atacar")
			task.delay(0.5, function()
				Input.Release("Atacar")
			end)
		end
		local angle = random:NextNumber(0, math.pi * 2)
		ctx.humanoid:Move(Vector3.new(math.cos(angle), 0, math.sin(angle)))
		task.wait(random:NextNumber(0.04, 0.12))
	end
	if defending then
		Input.Release("Defender")
	end
	ctx.humanoid:Move(Vector3.zero)
	if okLock and Fijar.LockOn then
		Fijar.LockOn(nil)
	end

	-- Todo debe volver a la normalidad en poco tiempo
	local free = waitUntil(function()
		return ctx.Combat.State.mode == "Libre" and ctx.grounded()
	end, 4)
	local alive = ctx.humanoid.Health > 0
	local camera = Workspace.CurrentCamera
	local cameraOk = camera.CameraType == Enum.CameraType.Custom

	-- Se mueve
	ctx.settle()
	local before = ctx.root.Position
	ctx.humanoid:Move(Vector3.new(0, 0, 1))
	task.wait(0.6)
	ctx.humanoid:Move(Vector3.zero)
	local moved = (ctx.root.Position - before).Magnitude

	-- Lanza una habilidad y el servidor la acepta
	ctx.remote:FireServer("reiniciar_eco")
	table.clear(Eco.State.cooldownEnd)
	table.clear(Eco.State.recast)
	Eco.State.swapUntil = 0
	task.wait(0.4)
	local used = nil
	local usedConnection = Eco.Used:Connect(function(name)
		used = name
	end)
	local lastEco = player:GetAttribute("UltimoEco")
	local rejections = player:GetAttribute("EcosRechazados") or 0
	Input.Trigger("HabilidadX")
	local accepted = waitUntil(function()
		return player:GetAttribute("UltimoEco") ~= lastEco
	end, 1.5)
	usedConnection:Disconnect()
	local rejectedAfter = (player:GetAttribute("EcosRechazados") or 0) - rejections

	-- Golpea
	local attackStarted = false
	local phase = ctx.Combat.AttackStarted and ctx.Combat.AttackStarted:Connect(function()
		attackStarted = true
	end)
	Input.Trigger("Atacar")
	waitUntil(function()
		return attackStarted or ctx.Combat.State.mode == "Ataque"
	end, 0.6)
	local attacked = attackStarted or ctx.Combat.State.mode == "Ataque"
	if phase then
		phase:Disconnect()
	end

	errorConnection:Disconnect()
	record(
		"[Estrés] 12 s de teclas al azar: nada se queda trabado",
		free and alive and cameraOk and moved > 3 and used ~= nil and accepted and rejectedAfter == 0 and attacked and #errors == 0,
		string.format(
			"libre y en el suelo %s · vivo %s · cámara normal %s · se movió %.1f studs · habilidad %s aceptada %s (rechazos %d) · golpea %s · errores %d%s",
			tostring(free), tostring(alive), tostring(cameraOk), moved, tostring(used), tostring(accepted), rejectedAfter, tostring(attacked), #errors,
			if #errors > 0 then " (" .. string.sub(errors[1], 1, 120) .. ")" else ""
		)
	)
	ctx.settle()
end
