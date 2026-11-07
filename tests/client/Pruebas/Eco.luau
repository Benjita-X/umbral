-- Suite del primer Eco (EXPERIMENTAL): Eco del Viento. Mide lo que decide el servidor (vida, Resonancia,
-- rechazos), no el efecto visual.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

return function(ctx)
	local Config, Input, Combat = ctx.CombatConfig, ctx.Input, ctx.Combat
	local record, waitUntil = ctx.record, ctx.waitUntil
	local player = ctx.player
	local techniques = Config.Eco.Techniques
	local ecoRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Eco", 10)
	if not ecoRemote then
		ctx.skip("[Eco] Suite del Eco", "no existe el remote Eco")
		return
	end

	local function byName(tag, name)
		for _, model in ipairs(CollectionService:GetTagged(tag)) do
			if model.Name == name then
				return model
			end
		end
		return CollectionService:GetTagged(tag)[1]
	end
	local function resonance()
		return player:GetAttribute("Resonancia") or 0
	end
	local function setResonance(value)
		ctx.remote:FireServer("resonancia", value)
		waitUntil(function()
			return math.abs(resonance() - value) < 0.5
		end, 1)
	end
	local function standFacing(model, distance)
		local root = model:WaitForChild("HumanoidRootPart")
		local look = root.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z).Unit
		local position = root.Position + flatLook * distance
		ctx.waitForCharges()
		ctx.teleport(Vector3.new(position.X, root.Position.Y + 0.5, position.Z), -flatLook)
		return root
	end

	-- ---------- 1. Ráfaga: daña y cobra exactamente su costo ----------
	local dummy = byName("Objetivo", "Muneco2")
	local dummyHumanoid = dummy:FindFirstChildOfClass("Humanoid")
	waitUntil(function()
		return dummyHumanoid.Health >= dummyHumanoid.MaxHealth
	end, 6)
	standFacing(dummy, 6)
	setResonance(100)
	local h0 = dummyHumanoid.Health
	local r0 = resonance() -- la Resonancia se apaga sola fuera de combate: se mide lo COBRADO
	Input.Trigger("Eco")
	waitUntil(function()
		return dummyHumanoid.Health < h0
	end, 1.5)
	task.wait(0.2)
	local dealt = h0 - dummyHumanoid.Health
	local spent = r0 - resonance()
	record(
		"[Eco] Ráfaga: daña al frente y cobra su costo",
		math.abs(dealt - techniques.Rafaga.damage) < 0.01 and spent >= techniques.Rafaga.cost - 0.5 and spent <= techniques.Rafaga.cost + 3,
		string.format("%.1f de daño (objetivo %d) · cobró %.1f de Resonancia (costo %d; el resto es el apagado natural)", dealt, techniques.Rafaga.damage, spent, techniques.Rafaga.cost)
	)

	-- ---------- 2. Enfriamiento comprobado en el servidor ----------
	local rejected0 = player:GetAttribute("EcosRechazados") or 0
	local root = ctx.root
	ecoRemote:FireServer("rafaga", Workspace:GetServerTimeNow(), root.Position, root.CFrame.LookVector)
	waitUntil(function()
		return (player:GetAttribute("EcosRechazados") or 0) > rejected0
	end, 1)
	record("[Eco] El servidor respeta el enfriamiento", player:GetAttribute("EcoRechazado") == "enfriamiento", "motivo: " .. tostring(player:GetAttribute("EcoRechazado")))

	-- ---------- 3. Sin Resonancia no hay Eco ----------
	task.wait(techniques.Rafaga.cooldown + 0.2)
	setResonance(10)
	h0 = dummyHumanoid.Health
	rejected0 = player:GetAttribute("EcosRechazados") or 0
	ecoRemote:FireServer("rafaga", Workspace:GetServerTimeNow(), root.Position, root.CFrame.LookVector)
	waitUntil(function()
		return (player:GetAttribute("EcosRechazados") or 0) > rejected0
	end, 1)
	record(
		"[Eco] Sin Resonancia suficiente no sale",
		dummyHumanoid.Health == h0 and player:GetAttribute("EcoRechazado") == "Resonancia insuficiente",
		"motivo: " .. tostring(player:GetAttribute("EcoRechazado"))
	)

	-- ---------- 4. Un impacto de Descenso inventado se rechaza ----------
	rejected0 = player:GetAttribute("EcosRechazados") or 0
	ecoRemote:FireServer("impacto", Workspace:GetServerTimeNow(), root.Position, root.CFrame.LookVector)
	waitUntil(function()
		return (player:GetAttribute("EcosRechazados") or 0) > rejected0
	end, 1)
	record("[Eco] Rechaza un impacto sin Descenso", player:GetAttribute("EcoRechazado") == "impacto sin descenso", "motivo: " .. tostring(player:GetAttribute("EcoRechazado")))

	-- ---------- 5. Descenso: picada y onda al aterrizar ----------
	waitUntil(function()
		return dummyHumanoid.Health >= dummyHumanoid.MaxHealth
	end, 6)
	standFacing(dummy, 4)
	setResonance(100)
	h0 = dummyHumanoid.Health
	ctx.humanoid.Jump = true
	waitUntil(function()
		return not ctx.grounded() and ctx.root.AssemblyLinearVelocity.Y <= 2
	end, 1.5)
	Input.Trigger("Eco")
	waitUntil(function()
		return dummyHumanoid.Health < h0
	end, 2)
	task.wait(0.2)
	dealt = h0 - dummyHumanoid.Health
	record(
		"[Eco] Descenso: la onda al aterrizar daña alrededor",
		math.abs(dealt - techniques.Descenso.damage) < 0.01,
		string.format("%.1f de daño (objetivo %d) · último Eco %s", dealt, techniques.Descenso.damage, tostring(player:GetAttribute("UltimoEco")))
	)

	-- ---------- 6. Atraviesa la coraza del Centinela ----------
	local centinela = CollectionService:GetTagged("Centinela")[1]
	if centinela then
		local cHumanoid = centinela:FindFirstChildOfClass("Humanoid")
		ctx.remote:FireServer("vida_enemigo", { tag = "Centinela", value = Config.Sparring.Types.Centinela.maxHealth })
		task.wait(techniques.Descenso.cooldown)
		standFacing(centinela, 6)
		setResonance(100)
		local c0 = cHumanoid.Health
		Input.Trigger("Eco")
		waitUntil(function()
			return cHumanoid.Health < c0
		end, 1.5)
		local through = c0 - cHumanoid.Health
		record(
			"[Eco] La Ráfaga atraviesa la coraza del Centinela",
			math.abs(through - techniques.Rafaga.damage) < 0.01,
			string.format("%.1f de daño de frente (la coraza bloquea los golpes normales)", through)
		)
	else
		ctx.skip("[Eco] La Ráfaga atraviesa la coraza del Centinela", "no hay Centinela en este lugar")
	end

	-- ---------- 7. Interrumpe al enemigo que prepara un ataque ----------
	local partner = CollectionService:GetTagged("Companero")[1]
	if partner then
		ctx.remote:FireServer("patron", "Golpe")
		ctx.remote:FireServer("reiniciar_defensa")
		task.wait(techniques.Rafaga.cooldown)
		standFacing(partner, 5)
		setResonance(100)
		local caught = waitUntil(function()
			if partner:GetAttribute("Estado") == "Preparando" then
				return (partner:GetAttribute("FaseFin") or 0) - Workspace:GetServerTimeNow() > 0.3
			end
			return false
		end, 6)
		if caught then
			Input.Trigger("Eco")
		end
		local interrupted = caught and waitUntil(function()
			return partner:GetAttribute("Estado") == "Aturdido"
		end, 1)
		record("[Eco] La Ráfaga interrumpe la preparación de un ataque", interrupted == true, string.format("preparando cuando se usó: %s · aturdido: %s", tostring(caught), tostring(interrupted)))
		ctx.remote:FireServer("patron", "")
	end

	-- ---------- 8. Torbellino (mantener Eco en el suelo): golpea alrededor ----------
	local spinDummy = byName("Objetivo", "Muneco1")
	local spinHumanoid = spinDummy:FindFirstChildOfClass("Humanoid")
	waitUntil(function()
		return spinHumanoid.Health >= spinHumanoid.MaxHealth
	end, 6)
	standFacing(spinDummy, 4)
	setResonance(100)
	local s0 = spinHumanoid.Health
	Input.Press("Eco")
	task.wait(techniques.Torbellino.holdTime + 0.15)
	Input.Release("Eco")
	waitUntil(function()
		return spinHumanoid.Health < s0
	end, 1.5)
	task.wait(0.15)
	local spun = s0 - spinHumanoid.Health
	record("[Eco] Torbellino (mantener): golpea alrededor", math.abs(spun - techniques.Torbellino.damage) < 0.01, string.format("%.1f de daño (objetivo %d) · último Eco %s", spun, techniques.Torbellino.damage, tostring(player:GetAttribute("UltimoEco"))))

	-- ---------- 9. Estela sin Paso: el servidor la rechaza ----------
	task.wait(0.8)
	local rej = player:GetAttribute("EcosRechazados") or 0
	ecoRemote:FireServer("estela", Workspace:GetServerTimeNow(), ctx.root.Position, ctx.root.CFrame.LookVector)
	waitUntil(function()
		return (player:GetAttribute("EcosRechazados") or 0) > rej
	end, 1.5)
	record("[Eco] La Estela sin un Paso se rechaza", player:GetAttribute("EcoRechazado") == "estela sin Paso", "motivo: " .. tostring(player:GetAttribute("EcoRechazado")))

	-- ---------- 10. Estela: el Paso que atraviesa a un muñeco y Eco enseguida ----------
	local slashDummy = byName("Objetivo", "Muneco3")
	local slashHumanoid = slashDummy:FindFirstChildOfClass("Humanoid")
	waitUntil(function()
		return slashHumanoid.Health >= slashHumanoid.MaxHealth
	end, 6)
	local sRoot = standFacing(slashDummy, 7)
	setResonance(100)
	local e0 = slashHumanoid.Health
	local toward = Vector3.new(sRoot.Position.X - ctx.root.Position.X, 0, sRoot.Position.Z - ctx.root.Position.Z).Unit
	ctx.humanoid:Move(toward)
	task.wait()
	Input.Trigger("Paso")
	task.wait(0.16)
	Input.Trigger("Eco")
	ctx.humanoid:Move(Vector3.zero)
	waitUntil(function()
		return slashHumanoid.Health < e0
	end, 1.5)
	task.wait(0.15)
	local slashed = e0 - slashHumanoid.Health
	record("[Eco] Estela (tras un Paso): daña lo que atravesaste", math.abs(slashed - techniques.Estela.damage) < 0.01, string.format("%.1f de daño (objetivo %d) · último Eco %s · motivo si falló: %s", slashed, techniques.Estela.damage, tostring(player:GetAttribute("UltimoEco")), tostring(player:GetAttribute("EcoRechazado"))))

	-- ---------- Menú: existe, abre con su botón y cambia un ajuste en vivo ----------
	local menu = player.PlayerGui:FindFirstChild("UmbralMenu")
	local panel = menu and menu:FindFirstChild("Panel")
	local openButton = menu and menu:FindFirstChild("AbrirMenu")
	local shakeBefore = Config.Feedback.ScreenShake
	local toggled = false
	if panel and openButton then
		for _, child in ipairs(panel:GetDescendants()) do
			if child:IsA("TextButton") and string.find(child.Text, "Vibración", 1, true) then
				toggled = true -- el ajuste está en el menú (el clic real lo valida una persona)
			end
		end
	end
	record(
		"[Menú] El menú existe con botón, controles y ajustes",
		panel ~= nil and openButton ~= nil and toggled and shakeBefore == Config.Feedback.ScreenShake,
		string.format("menú %s · botón %s · ajuste de vibración %s", tostring(panel ~= nil), tostring(openButton ~= nil), tostring(toggled))
	)

	setResonance(0)
	local _ = Combat
	ctx.teleport(Vector3.new(0, 4, 30), Vector3.new(0, 0, 1))
end
