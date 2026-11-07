-- Texto: utilidades de texto compartidas.
-- Mayusculas(s): como string.upper, pero también con tildes y eñe (string.upper de Luau solo cambia letras ASCII:
-- "Ciclón" salía "CICLóN").

local Texto = {}

local ACCENTS = {
	["á"] = "Á",
	["é"] = "É",
	["í"] = "Í",
	["ó"] = "Ó",
	["ú"] = "Ú",
	["ü"] = "Ü",
	["ñ"] = "Ñ",
}

function Texto.Mayusculas(s)
	local upper = string.upper(tostring(s))
	for lower, capital in pairs(ACCENTS) do
		upper = string.gsub(upper, lower, capital)
	end
	return upper
end

return Texto
