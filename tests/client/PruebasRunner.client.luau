-- Ejecuta las suites de pruebas del cliente en orden (solo en build/UMBRAL-Pruebas.rbxlx).
-- Cada suite corre aislada: si una falla con un error, las demás siguen.

local Pruebas = script.Parent:WaitForChild("Pruebas")
local ctx = require(Pruebas:WaitForChild("Util"))

local SUITES = {
	{ "Movimiento", "Movimiento" },
	{ "Paredes", "Paredes" },
	{ "Combate", "Combate" },
	{ "Defensa", "Defensa" },
	{ "Auditoria", "Auditoria" },
	{ "Habilidad", "Habilidad" },
	{ "Enemigos", "Enemigos" },
	{ "Eco", "Eco" },
	{ "RevisionCodex", "RevisionCodex" },
}

if ctx.start() then
	for _, suite in ipairs(SUITES) do
		-- Cada suite se carga por separado: un error en una (incluso de sintaxis) no detiene las demás
		local ok, err = pcall(function()
			require(Pruebas:WaitForChild(suite[2]))(ctx)
		end)
		if not ok then
			ctx.record("Suite " .. suite[1], false, "error: " .. tostring(err))
		end
	end
else
	ctx.record("Arranque", false, "los controladores no prepararon al personaje")
end

ctx.finish()
