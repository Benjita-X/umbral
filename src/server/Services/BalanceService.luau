-- BalanceService: una sola fórmula, con límites, para todo el daño y el progreso (CombatConfig.Balance).
--
--   daño final = base × PODER (nivel y mejoras del jugador: moderado y con tope)
--                     × EJECUCIÓN (contraataque, por la espalda, contra la pared, combo largo: lo decide el combate)
--                     × RESISTENCIA del objetivo × SITUACIÓN (dificultad y ronda del encuentro)
--
-- El nivel y las mejoras se notan, pero nunca vuelven irrelevante la técnica: el poder tiene tope (PowerCap) y la
-- ejecución multiplica más que cualquier nivel. En PvP el poder se IGUALA (decide quién pelea mejor, no quién jugó
-- más horas). Los enemigos de una expedición escalan por dificultad y ronda, sobre todo por COMPOSICIÓN (otros
-- enemigos, élites) y solo un poco en vida y daño: una pelea no dura más porque sí.
--
-- El nivel y la experiencia son de la expedición en curso (atributos del jugador "Nivel", "Experiencia",
-- "Mejoras"); empiezan de cero en cada partida (no hay datos guardados todavía).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("CombatConfig"))

local BalanceService = {}

local balance = CombatConfig.Balance
local BASE_HEALTH = 100

-- ¿Tiene esta mejora de la expedición?
function BalanceService.HasUpgrade(player, name)
	local list = typeof(player) == "Instance" and player:GetAttribute("Mejoras")
	return type(list) == "string" and string.find("," .. list .. ",", "," .. name .. ",", 1, true) ~= nil
end

function BalanceService.Level(player)
	return math.clamp(math.floor(player:GetAttribute("Nivel") or 1), 1, balance.Levels.Max)
end

-- Poder del jugador (multiplica el daño que hace): nivel y mejoras, con tope
function BalanceService.Power(player)
	local power = 1 + (BalanceService.Level(player) - 1) * balance.Levels.DamagePerLevel
	if BalanceService.HasUpgrade(player, "Filo") then
		power *= 1.12
	end
	return math.min(power, balance.PowerCap)
end

-- Multiplicador del daño que RECIBE el jugador (defensa por nivel y mejoras)
function BalanceService.Incoming(player)
	local taken = 1 / (1 + (BalanceService.Level(player) - 1) * balance.Levels.DefensePerLevel)
	if BalanceService.HasUpgrade(player, "Coraza") then
		taken *= 0.85
	end
	return taken
end

-- Multiplicador del daño de un jugador a un objetivo: su poder × la resistencia del objetivo. Contra otro jugador,
-- 1 (en PvP el poder se iguala)
function BalanceService.Outgoing(player, target)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return 1
	end
	if typeof(target) == "Instance" and Players:GetPlayerFromCharacter(target) then
		return 1
	end
	local resistance = typeof(target) == "Instance" and target:GetAttribute("Resistencia") or 1
	return BalanceService.Power(player) * resistance
end

-- Vida máxima del jugador según su nivel y mejoras (se aplica al subir de nivel y al reaparecer)
function BalanceService.ApplyHealth(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local maxHealth = BASE_HEALTH + (BalanceService.Level(player) - 1) * balance.Levels.HealthPerLevel + (if BalanceService.HasUpgrade(player, "Coraza") then 20 else 0)
	if math.abs(humanoid.MaxHealth - maxHealth) > 0.01 then
		local ratio = if humanoid.MaxHealth > 0 then humanoid.Health / humanoid.MaxHealth else 1
		humanoid.MaxHealth = maxHealth
		humanoid.Health = math.min(maxHealth, ratio * maxHealth)
	end
end

local function notice(player, title, subtitle)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = remotes and remotes:FindFirstChild("AvisoGrieta")
	if remote then
		remote:FireClient(player, { title = title, subtitle = subtitle or "", small = true })
	end
end

-- Experiencia: al llenar XpPerLevel × nivel se sube (aviso, un poco de vida y la vida máxima nueva)
function BalanceService.GainXp(player, amount)
	if typeof(player) ~= "Instance" or not player.Parent or amount <= 0 then
		return
	end
	local level = BalanceService.Level(player)
	local xp = (player:GetAttribute("Experiencia") or 0) + amount
	local leveled = false
	while level < balance.Levels.Max and xp >= balance.Levels.XpPerLevel * level do
		xp -= balance.Levels.XpPerLevel * level
		level += 1
		leveled = true
	end
	player:SetAttribute("Experiencia", xp)
	player:SetAttribute("Nivel", level)
	if leveled then
		BalanceService.ApplyHealth(player)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * 0.25)
		end
		notice(player, string.format("¡NIVEL %d!", level), string.format("+%d %% de daño · más vida", math.floor((BalanceService.Power(player) - 1) * 100 + 0.5)))
	end
end

-- Partida nueva: nivel 1, sin experiencia ni mejoras
function BalanceService.ResetProgress(player)
	player:SetAttribute("Nivel", 1)
	player:SetAttribute("Experiencia", 0)
	player:SetAttribute("Mejoras", "")
	BalanceService.ApplyHealth(player)
end

function BalanceService.AddUpgrade(player, name)
	if BalanceService.HasUpgrade(player, name) then
		return
	end
	local list = player:GetAttribute("Mejoras")
	player:SetAttribute("Mejoras", if type(list) == "string" and list ~= "" then list .. "," .. name else name)
	BalanceService.ApplyHealth(player)
end

-- Escala de un enemigo de expedición: (vida, daño) según dificultad, ronda (0 = la primera), jugadores y élite
function BalanceService.EnemyScales(difficultyName, round, playerCount, elite)
	local difficulty = balance.Difficulties[difficultyName] or balance.Difficulties[balance.DefaultDifficulty]
	local health = difficulty.health * (1 + round * balance.RoundGrowth.health) * (1 + math.max(0, (playerCount or 1) - 1) * balance.PartyHealth)
	local damage = difficulty.damage * (1 + round * balance.RoundGrowth.damage)
	if elite then
		health *= balance.Elite.health
		damage *= balance.Elite.damage
	end
	return health, damage
end

function BalanceService.Start()
	-- La vida máxima de cada jugador sigue a su nivel también tras reaparecer
	local function watch(player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Humanoid", 10)
			task.defer(BalanceService.ApplyHealth, player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
end

return BalanceService
