-- Rig: ajustes del esqueleto de los personajes para combate.
--
-- Roblox usa AnimationConstraint como articulación por defecto del R15: mueve el cuerpo con física y
-- fuerza limitada (sirve para ragdoll o "fuerza de brazos"). En un juego de pelea eso hace que las poses
-- lleguen tarde e incompletas (el brazo de un Jab no alcanza a estirarse en 0,07 s).
-- En modo cinemático la articulación sigue la animación al instante, como un Motor6D clásico.
-- Para un ragdoll futuro (nocaut) basta volver a ponerlas en IsKinematic = false.

local Rig = {}

-- Pone en modo cinemático todas las articulaciones del personaje, también las que aparezcan después.
-- Devuelve la conexión (se limpia sola cuando el personaje se destruye).
function Rig.MakeKinematic(character)
	local function apply(instance)
		if instance:IsA("AnimationConstraint") then
			instance.IsKinematic = true
		end
	end
	for _, descendant in ipairs(character:GetDescendants()) do
		apply(descendant)
	end
	return character.DescendantAdded:Connect(apply)
end

-- Articulación que mueve una parte del cuerpo (AnimationConstraint o Motor6D), para diagnóstico
function Rig.JointOf(part)
	return part and (part:FindFirstChildOfClass("AnimationConstraint") or part:FindFirstChildOfClass("Motor6D"))
end

return Rig
