-- Ejecuta las suites de pruebas del cliente en orden (solo en build/UMBRAL-Pruebas.rbxlx).
-- Cada suite corre aislada: si una falla con un error, las demás siguen.

local Pruebas = script.Parent:WaitForChild("Pruebas")
local ctx = require(Pruebas:WaitForChild("Util"))

local SUITES = {
	{ "Movimiento", "Movimiento" },
	{ "Paredes", "Paredes" },
	{ "Choques", "Choques" },
	{ "Combate", "Combate" },
	{ "Defensa", "Defensa" },
	{ "Auditoria", "Auditoria" },
	{ "Habilidad", "Habilidad" },
	{ "Enemigos", "Enemigos" },
	{ "Eco", "Eco" },
	{ "Ecos", "Ecos" },
	{ "Armas", "Armas" },
	{ "GanchoYGracia", "GanchoYGracia" },
	{ "RevisionCodex", "RevisionCodex" },
	{ "AuditoriaMaxima", "AuditoriaMaxima" },
	{ "PulidoFinal", "PulidoFinal" },
	{ "Expedicion", "Expedicion" },
	{ "Combos", "Combos" },
	{ "Estres", "Estres" },
	{ "Vitrina", "Vitrina", manual = true }, -- solo si se pide: -Suites Vitrina (revisión a ojo)
}

-- Solo algunas suites (tools/ejecutar-pruebas.ps1 -Suites "Eco,Ecos"): la marca trae la lista
local marker = game:GetService("ReplicatedStorage"):FindFirstChild("UmbralPruebasAutomaticas")
local onlyValue = marker and marker:FindFirstChild("Suites")
local only = nil
if onlyValue and onlyValue.Value ~= "" then
	only = {}
	for name in string.gmatch(onlyValue.Value, "[^,%s]+") do
		only[name] = true
	end
end

if ctx.start() then
	for _, suite in ipairs(SUITES) do
		if (only and not only[suite[1]]) or (suite.manual and not (only and only[suite[1]])) then
			continue
		end
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
