-- MoveSchema: el formato común de TODOS los movimientos del juego (del jugador y de los enemigos).
-- Validate() revisa CombatConfig y devuelve la lista de problemas (vacía = todo coherente).
-- Lo ejecutan las pruebas automáticas: un movimiento mal definido falla antes de llegar al juego.

local MoveSchema = {}

-- campo = tipo esperado
MoveSchema.Required = {
	label = "string",
	startup = "number", -- preparación (s)
	active = "number", -- impacto (s)
	recovery = "number", -- recuperación (s)
	damage = "number",
	posture = "number", -- desgaste de postura al bloquearlo
	shape = "string", -- "box" (caja delante) o "ring" (área alrededor)
	deflectable = "boolean",
	guardable = "boolean",
	contrapaso = "boolean", -- se puede esquivar con Contrapaso
}

local SHAPES = { box = true, ring = true }

local function check(problems, name, move)
	for field, kind in pairs(MoveSchema.Required) do
		if type(move[field]) ~= kind then
			table.insert(problems, string.format("%s: falta %s (%s)", name, field, kind))
		end
	end
	if type(move.startup) == "number" and move.startup <= 0 then
		table.insert(problems, name .. ": la preparación debe ser > 0 (todo golpe se puede leer)")
	end
	if type(move.active) == "number" and move.active <= 0 then
		table.insert(problems, name .. ": el impacto debe durar > 0")
	end
	if not SHAPES[move.shape] then
		table.insert(problems, name .. ": forma desconocida " .. tostring(move.shape))
	elseif move.shape == "box" then
		if type(move.range) ~= "number" or typeof(move.hitboxSize) ~= "Vector3" then
			table.insert(problems, name .. ": una caja necesita range y hitboxSize")
		end
	elseif type(move.radius) ~= "number" then
		table.insert(problems, name .. ": un área necesita radius")
	end
	if move.perfectOnly and not move.deflectable then
		table.insert(problems, name .. ": perfectOnly exige deflectable")
	end
	-- Todo movimiento debe tener alguna respuesta (desvío, guardia, Contrapaso o salir del área)
	if not move.deflectable and not move.guardable and not move.contrapaso and move.shape ~= "ring" then
		table.insert(problems, name .. ": no tiene ninguna respuesta posible")
	end
end

function MoveSchema.Validate(combatConfig)
	local problems = {}
	local count = 0
	for name, move in pairs(combatConfig.Attacks) do
		check(problems, "Jugador." .. name, move)
		count += 1
	end
	for name, move in pairs(combatConfig.Sparring.Attacks) do
		check(problems, "Enemigo." .. name, move)
		count += 1
	end
	for profileName, profile in pairs(combatConfig.Sparring.Profiles) do
		for _, step in ipairs(profile.pattern) do
			if step ~= "Amague" and not combatConfig.Sparring.Attacks[step] then
				table.insert(problems, string.format("Perfil %s: ataque desconocido %s", profileName, step))
			end
		end
	end
	return problems, count
end

return MoveSchema
