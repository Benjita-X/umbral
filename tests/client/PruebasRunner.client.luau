-- Ejecuta las suites de pruebas del cliente en orden (solo en build/UMBRAL-Pruebas.rbxlx).
-- Cada suite corre aislada: si una falla con un error, las demás siguen.

local Pruebas = script.Parent:WaitForChild("Pruebas")
local ctx = require(Pruebas:WaitForChild("Util"))

local SUITES = {
	{ "Movimiento", require(Pruebas:WaitForChild("Movimiento")) },
	{ "Combate", require(Pruebas:WaitForChild("Combate")) },
	{ "Defensa", require(Pruebas:WaitForChild("Defensa")) },
	{ "Auditoria", require(Pruebas:WaitForChild("Auditoria")) },
	{ "Habilidad", require(Pruebas:WaitForChild("Habilidad")) },
}

if ctx.start() then
	for _, suite in ipairs(SUITES) do
		local ok, err = pcall(suite[2], ctx)
		if not ok then
			ctx.record("Suite " .. suite[1], false, "error: " .. tostring(err))
		end
	end
else
	ctx.record("Arranque", false, "los controladores no prepararon al personaje")
end

ctx.finish()
