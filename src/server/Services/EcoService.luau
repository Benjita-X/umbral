-- EcoService: los Ecos del jugador (Fase 7, EXPERIMENTAL). Primer Eco: Eco del Viento.
--   · Ráfaga (en el suelo): onda frontal que empuja y daña. Atraviesa corazas e interrumpe preparaciones.
--   · Descenso (en el aire): caída en picada; al aterrizar, onda circular que levanta.
-- Cuestan Resonancia: pelear bien carga el Eco. No dan Resonancia (sin bucles infinitos).
--
-- Autoridad del servidor: el cliente solo pide la técnica con su hora y posición. El servidor comprueba
-- Resonancia, enfriamiento, aturdimiento, hora coherente y posición confirmada (PositionService), y calcula
-- él mismo a quién alcanza con las cajas estándar (Hurtbox). La Resonancia se cobra al confirmar.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(shared:WaitForChild("Config"):WaitForChild("CombatConfig"))
local Hurtbox = require(shared:WaitForChild("Combat"):WaitForChild("Hurtbox"))
local services = script.Parent
local PositionService = require(services:WaitForChild("PositionService"))
local DefenseService = require(services:WaitForChild("DefenseService"))
local ResonanceService = require(services:WaitForChild("ResonanceService"))
local DamageService = require(services:WaitForChild("DamageService"))

local EcoService = {}

local eco = CombatConfig.Eco
local records = {} -- [player] = { cooldowns = { [técnica] = os.clock }, descent = { t, untilTime } }

local function now()
	return Workspace:GetServerTimeNow()
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function recordFor(player)
	local r = records[player]
	if not r then
		r = { cooldowns = {}, descent = nil }
		records[player] = r
	end
	return r
end

local function refuse(player, reason)
	player:SetAttribute("EcoRechazado", reason)
	player:SetAttribute("EcosRechazados", (player:GetAttribute("EcosRechazados") or 0) + 1)
end

-- Comprobaciones comunes antes de cobrar una técnica
local function canUse(player, technique, t)
	local spec = eco.Techniques[technique]
	local r = recordFor(player)
	if not PositionService.ValidTime(player, t) then
		return false, "hora inválida"
	end
	if DefenseService.IsStunned(player, player:GetNetworkPing() + 0.1) then
		return false, "aturdido"
	end
	-- Enfriamiento medido en el servidor, con un margen pequeño por la variación de la red
	if os.clock() - (r.cooldowns[technique] or -math.huge) < spec.cooldown - 0.15 then
		return false, "enfriamiento"
	end
	if ResonanceService.Get(player) < spec.cost then
		return false, "Resonancia insuficiente"
	end
	return true
end

-- Quiénes alcanza una forma en el instante `t` (posiciones como las veía el jugador)
local function targetsIn(player, test, t)
	local list = {}
	local oneWay = PositionService.OneWay(player)
	for _, model in ipairs(CollectionService:GetTagged("Objetivo")) do
		local root = model:IsDescendantOf(Workspace) and model:FindFirstChild("HumanoidRootPart")
		if root then
			local cframe = PositionService.ObservedAt(model, t - oneWay) or root.CFrame
			if test(cframe) then
				table.insert(list, model)
			end
		end
	end
	return list
end

local function attackerAt(player, t)
	local cframe = PositionService.ConfirmedAt(player, t)
	if not cframe and PositionService.Teleporting(player) and player.Character then
		cframe = PositionService.ObservedAt(player.Character, t)
	end
	return cframe
end

local function rafaga(player, t, position, look)
	local spec = eco.Techniques.Rafaga
	local ok, why = canUse(player, "Rafaga", t)
	if not ok then
		return refuse(player, why)
	end
	PositionService.Report(player, t, position, look)
	local attackerCFrame = attackerAt(player, t)
	if not attackerCFrame then
		return refuse(player, "posición no confirmada")
	end
	if not ResonanceService.Spend(player, spec.cost) then
		return refuse(player, "Resonancia insuficiente")
	end
	recordFor(player).cooldowns.Rafaga = os.clock()
	local hits = targetsIn(player, function(cframe)
		return Hurtbox.AttackHits(attackerCFrame, spec.range, spec.hitboxSize, cframe, CombatConfig.Validation.Tolerance)
	end, t)
	local forward = flat(attackerCFrame.LookVector)
	forward = if forward.Magnitude > 0.01 then forward.Unit else Vector3.new(0, 0, -1)
	for _, model in ipairs(hits) do
		DamageService.ApplyExternalHit(player, model, {
			attackName = "EcoRafaga",
			damage = spec.damage,
			direction = forward,
			knockback = spec.knockback,
			knockUp = spec.knockUp,
			ignoreModifier = true, -- el viento atraviesa la coraza
		})
	end
	player:SetAttribute("UltimoEco", string.format("Rafaga:%d", #hits))
end

local function descenso(player, t, position, look)
	local spec = eco.Techniques.Descenso
	local ok, why = canUse(player, "Descenso", t)
	if not ok then
		return refuse(player, why)
	end
	PositionService.Report(player, t, position, look)
	if not ResonanceService.Spend(player, spec.cost) then
		return refuse(player, "Resonancia insuficiente")
	end
	local r = recordFor(player)
	r.cooldowns.Descenso = os.clock()
	r.descent = { t = t, untilTime = t + spec.window }
end

local function impacto(player, t, position, look)
	local spec = eco.Techniques.Descenso
	local r = recordFor(player)
	local descent = r.descent
	if not descent or type(t) ~= "number" or t < descent.t or t > descent.untilTime or not PositionService.ValidTime(player, t) then
		return refuse(player, "impacto sin descenso")
	end
	r.descent = nil
	PositionService.Report(player, t, position, look)
	local landing = attackerAt(player, t)
	if not landing then
		return refuse(player, "posición no confirmada")
	end
	local hits = targetsIn(player, function(cframe)
		return Hurtbox.InRadius(landing.Position, spec.radius, cframe.Position, 6)
	end, t)
	for _, model in ipairs(hits) do
		local root = model:FindFirstChild("HumanoidRootPart")
		local away = root and flat(root.Position - landing.Position) or Vector3.zero
		DamageService.ApplyExternalHit(player, model, {
			attackName = "EcoDescenso",
			damage = spec.damage,
			direction = if away.Magnitude > 0.01 then away.Unit else flat(landing.LookVector).Unit,
			knockback = spec.knockback,
			knockUp = spec.knockUp,
			ignoreModifier = true,
		})
	end
	player:SetAttribute("UltimoEco", string.format("Descenso:%d", #hits))
end

function EcoService.Start()
	local remote = Instance.new("RemoteEvent")
	remote.Name = "Eco"
	remote.Parent = ReplicatedStorage:WaitForChild("Remotes")
	local rate = {} -- [player] = { windowStart, count }
	remote.OnServerEvent:Connect(function(player, action, t, position, look)
		-- Tope de mensajes: las técnicas tienen enfriamiento de segundos; más de 6 por segundo es basura
		local clock = os.clock()
		local rr = rate[player]
		if not rr or clock - rr.windowStart >= 1 then
			rr = { windowStart = clock, count = 0 }
			rate[player] = rr
		end
		rr.count += 1
		if rr.count > 6 then
			return
		end
		task.spawn(function()
			if action == "rafaga" then
				rafaga(player, t, position, look)
			elseif action == "descenso" then
				descenso(player, t, position, look)
			elseif action == "impacto" then
				impacto(player, t, position, look)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		records[player] = nil
		rate[player] = nil
	end)
end

return EcoService
