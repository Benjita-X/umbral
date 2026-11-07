-- RecoveryService: recuperación de vida de los jugadores (EXPERIMENTAL; decisión del hallazgo #10 de Codex).
--   · "Respiro" (PvE): tras CombatConfig.Recovery.OutOfCombat segundos sin recibir ni hacer daño, se
--     recupera RegenPerSecond de vida por segundo. Pelear no cura: el riesgo de cada encuentro se mantiene.
--   · Punto seguro: cerca de una aparición (SpawnLocation) se cura entero.
--   · PvP (Fase 4): sin regeneración en combate (la vida que tienes es la que juegas).
-- Reemplaza la regeneración automática de Roblox: el personaje trae un script "Health" vacío
-- (tools/construir.mjs), así que la única curación es esta, decidida por el servidor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("CombatConfig"))
local DamageService = require(script.Parent:WaitForChild("DamageService"))

local RecoveryService = {}

local recovery = CombatConfig.Recovery
local lastCombat = {} -- [player] = os.clock() del último daño recibido o hecho
local lastHealth = {} -- [player] = vida en el cuadro anterior

function RecoveryService.Touch(player)
	lastCombat[player] = os.clock()
end

local function spawns()
	local list = {}
	for _, item in ipairs(Workspace:GetDescendants()) do
		if item:IsA("SpawnLocation") and item.Enabled then
			table.insert(list, item)
		end
	end
	return list
end

function RecoveryService.Start()
	-- Hacer daño cuenta como estar en combate
	DamageService.HitApplied:Connect(function(attacker)
		RecoveryService.Touch(attacker)
	end)
	local safeSpots = spawns()
	Players.PlayerRemoving:Connect(function(player)
		lastCombat[player] = nil
		lastHealth[player] = nil
	end)
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if humanoid and root and humanoid.Health > 0 then
				-- Recibir daño cuenta como estar en combate
				local previous = lastHealth[player]
				if previous and humanoid.Health < previous - 0.01 then
					lastCombat[player] = now
				end
				-- Punto seguro: cura entera
				local safe = false
				for _, spot in ipairs(safeSpots) do
					if spot.Parent and (spot.Position - root.Position).Magnitude <= recovery.SafeZoneRadius then
						safe = true
						break
					end
				end
				if safe then
					humanoid.Health = humanoid.MaxHealth
				elseif humanoid.Health < humanoid.MaxHealth and now - (lastCombat[player] or -math.huge) >= recovery.OutOfCombat then
					humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + recovery.RegenPerSecond * dt)
				end
				lastHealth[player] = humanoid.Health
			end
		end
	end)
end

return RecoveryService
