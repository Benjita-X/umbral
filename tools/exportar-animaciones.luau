-- Animaciones de UMBRAL para editarlas y publicarlas. Pegar en la Barra de comandos de Studio (Ver → Barra de
-- comandos) con build/UMBRAL-Desarrollo.rbxlx abierto, y pulsar Enter.
--   1. Crea un muñeco R15 "UmbralRig" en Workspace (si no está).
--   2. Deja TODAS las animaciones del juego en ServerStorage/RBX_ANIMSAVES/UmbralRig: el Editor de animaciones las
--      lista en "Cargar" (selecciona el muñeco → pestaña Avatar → Editor de animaciones → ⋯ → Cargar).
--   3. Abre una, mejórala si quieres y "Publicar en Roblox". Copia el ID en src/shared/Config/AnimacionesSubidas.luau
--      (o pásamelo y lo pongo yo). También sirve clic derecho sobre la animación en ServerStorage → "Guardar en Roblox".
-- Los tiempos de cada golpe ya coinciden con el combate (salen de CombatConfig): al editar, conserva la duración.
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local AnimationLibrary = require(game:GetService("ReplicatedStorage").Shared.Combat.AnimationLibrary)

local rig = workspace:FindFirstChild("UmbralRig")
if not rig then
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	end)
	if ok and model then
		rig = model
		rig.Name = "UmbralRig"
		rig:PivotTo(CFrame.new(0, 6, -12))
		rig.HumanoidRootPart.Anchored = true
		rig.Parent = workspace
	else
		warn("[UMBRAL] No se pudo crear el muñeco. Insértalo con Avatar → Constructor de rigs → R15 y llámalo UmbralRig; luego vuelve a pegar este comando.")
	end
end

local saves = ServerStorage:FindFirstChild("RBX_ANIMSAVES")
if not saves then
	saves = Instance.new("Model")
	saves.Name = "RBX_ANIMSAVES"
	saves.Parent = ServerStorage
end
local entry = saves:FindFirstChild("UmbralRig")
if not entry then
	entry = Instance.new("ObjectValue")
	entry.Name = "UmbralRig"
	entry.Parent = saves
end
entry.Value = rig

local names = AnimationLibrary.Names()
for _, name in ipairs(names) do
	local old = entry:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local sequence = AnimationLibrary.BuildSequence(name)
	sequence.Name = name
	sequence.Parent = entry
end
print(string.format("[UMBRAL] %d animaciones listas en ServerStorage/RBX_ANIMSAVES/UmbralRig:", #names))
print(table.concat(names, ", "))
