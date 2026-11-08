-- Pegar en la Barra de comandos de Studio (pestaña Ver → Barra de comandos) con UMBRAL-Desarrollo abierto.
-- Crea en ServerStorage/AnimacionesParaSubir una KeyframeSequence por cada animación provisional del juego (las
-- mismas que hoy solo funcionan dentro de Studio). Para subir cada una: clic derecho → "Guardar en Roblox" →
-- copia el ID y ponlo en CombatConfig.AnimationIds, por ejemplo: Jab = "rbxassetid://123456789".
-- También se pueden abrir en el Editor de animaciones para mejorarlas antes de subirlas.
local AnimationLibrary = require(game:GetService("ReplicatedStorage").Shared.Combat.AnimationLibrary)
local storage = game:GetService("ServerStorage")
local folder = storage:FindFirstChild("AnimacionesParaSubir") or Instance.new("Folder")
folder.Name = "AnimacionesParaSubir"
folder.Parent = storage
folder:ClearAllChildren()
for _, name in ipairs(AnimationLibrary.Names()) do
	local sequence = AnimationLibrary.BuildSequence(name)
	sequence.Name = name
	sequence.Parent = folder
end
print(string.format("[UMBRAL] %d animaciones listas en ServerStorage/AnimacionesParaSubir", #folder:GetChildren()))
