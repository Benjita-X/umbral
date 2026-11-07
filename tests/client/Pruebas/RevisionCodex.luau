-- Pruebas de los hallazgos de la revisión de Codex (docs/REVISION-CODEX.md, #1-#4).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

return function(ctx)
	local Config = ctx.CombatConfig
	local record, waitUntil = ctx.record, ctx.waitUntil
	local player = ctx.player
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local ecoRemote = remotes:FindFirstChild("Eco")
	local defenseRemote = remotes:WaitForChild("Defensa")
	local function now()
		return Workspace:GetServerTimeNow()
	end
	local function query(kind)
		player:SetAttribute("PruebaDefensa", nil)
		ctx.remote:FireServer("consulta_defensa", kind)
		waitUntil(function()
			return player:GetAttribute("PruebaDefensa") ~= nil
		end, 1.5)
		return player:GetAttribute("PruebaDefensa")
	end
	local function setResonance(value)
		ctx.remote:FireServer("resonancia", value)
		waitUntil(function()
			return math.abs((player:GetAttribute("Resonancia") or 0) - value) < 0.5
		end, 1)
	end

	ctx.waitForCharges()
	ctx.teleport(Vector3.new(0, 4, 150), Vector3.new(0, 0, 1)) -- zona abierta, sin enemigos cerca
	task.wait(3.2) -- que venzan los enfriamientos del Eco de pruebas anteriores

	-- #1: dos Ráfagas en el mismo cuadro cobran una sola vez
	if ecoRemote then
		setResonance(100)
		local before = player:GetAttribute("Resonancia") or 0
		local root = ctx.root
		local t = now()
		ecoRemote:FireServer("rafaga", t, root.Position, root.CFrame.LookVector)
		ecoRemote:FireServer("rafaga", t, root.Position, root.CFrame.LookVector)
		task.wait(0.8)
		local spent = before - (player:GetAttribute("Resonancia") or 0)
		local cost = Config.Eco.Techniques.Rafaga.cost
		record("[Codex #1] Dos Ráfagas simultáneas cobran una sola vez", spent >= cost - 0.5 and spent < cost * 2 - 1, string.format("cobró %.1f (una = %d, dos = %d)", spent, cost, cost * 2))

		-- #2: el Descenso desde el suelo se rechaza
		task.wait(Config.Eco.Techniques.Descenso.cooldown + 0.2)
		ctx.settle()
		setResonance(100)
		ecoRemote:FireServer("descenso", now(), ctx.root.Position, ctx.root.CFrame.LookVector)
		waitUntil(function()
			return player:GetAttribute("EcoRechazado") == "descenso sin estar en el aire"
		end, 1.5)
		record("[Codex #2] El Descenso desde el suelo se rechaza", player:GetAttribute("EcoRechazado") == "descenso sin estar en el aire", "motivo: " .. tostring(player:GetAttribute("EcoRechazado")))
		setResonance(0)
	end

	-- #8: la Ráfaga en el aire se rechaza sin cobrar
	if ecoRemote then
		task.wait(Config.Eco.Techniques.Rafaga.cooldown + 0.2)
		ctx.settle()
		setResonance(100)
		ctx.humanoid.Jump = true
		waitUntil(function()
			return not ctx.grounded() and ctx.root.AssemblyLinearVelocity.Y <= 3
		end, 1.5)
		local before = player:GetAttribute("Resonancia") or 0
		ecoRemote:FireServer("rafaga", now(), ctx.root.Position, ctx.root.CFrame.LookVector)
		waitUntil(function()
			return player:GetAttribute("EcoRechazado") == "ráfaga en el aire"
		end, 1.5)
		local after = player:GetAttribute("Resonancia") or 0
		record("[Codex #8] La Ráfaga en el aire se rechaza sin cobrar", player:GetAttribute("EcoRechazado") == "ráfaga en el aire" and after >= before - 2.5, string.format("motivo: %s · Resonancia %.0f → %.0f", tostring(player:GetAttribute("EcoRechazado")), before, after))
		setResonance(0)
		ctx.settle()
	end

	-- #10: recuperación de vida — nada en combate, Respiro después, punto seguro entero
	local humanoid = ctx.humanoid
	local recovery = Config.Recovery
	ctx.remote:FireServer("vida_jugador", 50)
	waitUntil(function()
		return humanoid.Health <= 50.5
	end, 1)
	task.wait(recovery.OutOfCombat * 0.5)
	local during = humanoid.Health
	task.wait(recovery.OutOfCombat * 0.5 + 1.2)
	local after = humanoid.Health
	record(
		"[Codex #10] Sin curación en combate; Respiro después",
		during <= 50.5 and after > 52,
		string.format("vida a los %.0f s: %.1f (sin cambio) · a los %.1f s: %.1f (se recupera)", recovery.OutOfCombat * 0.5, during, recovery.OutOfCombat + 1.2, after)
	)
	ctx.remote:FireServer("vida_jugador", 40)
	task.wait(0.2)
	ctx.teleport(Vector3.new(0, 4, 2), Vector3.new(0, 0, 1)) -- junto a la aparición del laboratorio
	local healed = waitUntil(function()
		return humanoid.Health >= humanoid.MaxHealth - 0.01
	end, 2)
	record("[Codex #10] El punto seguro cura entero", healed, string.format("vida %.0f de %.0f", humanoid.Health, humanoid.MaxHealth))

	-- #3: una pulsación no desvía dos ataques
	ctx.remote:FireServer("reiniciar_defensa")
	task.wait(Config.Defense.DeflectCooldown + 0.1)
	defenseRemote:FireServer("defender_inicio", now())
	task.wait(0.05)
	local double = query("desvio_doble")
	defenseRemote:FireServer("defender_fin", now())
	local first, second = string.match(tostring(double), "^(%a+),(%a+)$")
	record("[Codex #3] Una pulsación no desvía dos ataques", first ~= nil and first ~= "nil" and second == "nil", "primero, segundo: " .. tostring(double))

	-- #4: un inicio de guardia atrasado no reabre una guardia ya soltada
	task.wait(0.4)
	local t2 = now()
	defenseRemote:FireServer("defender_fin", t2)
	defenseRemote:FireServer("defender_inicio", t2 - 0.1)
	task.wait(0.15)
	local guarding = query("guardia")
	record("[Codex #4] Un inicio de guardia atrasado no reabre la guardia", guarding == "false", "en guardia según el servidor: " .. tostring(guarding))
	ctx.remote:FireServer("reiniciar_defensa")
end
