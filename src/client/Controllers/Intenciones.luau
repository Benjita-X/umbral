-- Intenciones: entre el combate, el Paso y las habilidades solo puede haber UNA acción guardada a la vez (pulsada un
-- instante antes de poder salir), y la última pulsada manda. Si pulsas una habilidad que espera y luego Atacar o el
-- Paso, la habilidad ya no sale después por sorpresa: la reemplazó tu decisión más nueva (y lo mismo al revés).
-- Cambiar de objetivo fijado, de Eco o de personaje también la descarta.
--   · Hold(dueño, etiqueta, cancelar): un sistema guarda una acción; reemplaza la que hubiera guardado OTRO sistema.
--   · Pressed(dueño, etiqueta): una pulsación que salió al instante; lo guardado por otro sistema queda reemplazado.
--   · Clear(dueño): lo que guardó ese sistema salió, venció o se descartó.
--   · Cancel(motivo): un cambio de contexto descarta lo guardado.

local Intenciones = {}

local held = nil -- { owner, label, cancel }
local replacedEvent = Instance.new("BindableEvent")
Intenciones.Replaced = replacedEvent.Event -- (lo que estaba guardado, lo que lo reemplazó)

local function drop(newLabel)
	local old = held
	held = nil
	if old then
		old.cancel()
		replacedEvent:Fire(old.label, newLabel)
	end
end

function Intenciones.Hold(owner, label, cancel)
	if held and held.owner ~= owner then
		drop(label)
	end
	held = { owner = owner, label = label, cancel = cancel }
end

function Intenciones.Pressed(owner, label)
	if held and held.owner ~= owner then
		drop(label)
	end
end

function Intenciones.Clear(owner)
	if held and held.owner == owner then
		held = nil
	end
end

function Intenciones.Cancel(reason)
	if held then
		drop(reason)
	end
end

-- Etiqueta de lo guardado ahora (o nil)
function Intenciones.Held()
	return held and held.label or nil
end

return Intenciones
