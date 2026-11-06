-- Hurtbox: la zona en que un personaje RECIBE golpes, igual para todos los avatares.
--
-- El tamaño visual del avatar (alto, bajo, delgado, Rthro...) no puede dar ventaja en un juego
-- competitivo. Por eso los golpes no se comprueban contra las piezas del cuerpo, sino contra una caja
-- estándar centrada en el HumanoidRootPart y orientada como él (solo el giro horizontal).
-- Lo usan el cliente (detección) y el servidor (validación), así que ambos juzgan igual.

local Hurtbox = {}

Hurtbox.Size = Vector3.new(3, 5.5, 2.4) -- ancho, alto, fondo (studs)

-- Orientación horizontal de una CFrame (sin inclinación)
function Hurtbox.Flat(cframe)
	local look = Vector3.new(cframe.LookVector.X, 0, cframe.LookVector.Z)
	if look.Magnitude < 1e-3 then
		look = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(cframe.Position, cframe.Position + look.Unit)
end

-- ¿Se solapan dos cajas orientadas (solo giro horizontal)? Separación de ejes en 2D + altura.
-- `boxA`/`boxB`: CFrame del centro; `sizeA`/`sizeB`: tamaños.
function Hurtbox.BoxesOverlap(boxA, sizeA, boxB, sizeB)
	local delta = boxB.Position - boxA.Position
	if math.abs(delta.Y) > (sizeA.Y + sizeB.Y) / 2 then
		return false
	end
	local function axes(cf)
		local r = Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z)
		local f = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
		return (if r.Magnitude > 1e-3 then r.Unit else Vector3.xAxis), (if f.Magnitude > 1e-3 then f.Unit else Vector3.zAxis)
	end
	local aR, aF = axes(boxA)
	local bR, bF = axes(boxB)
	local d = Vector3.new(delta.X, 0, delta.Z)
	for _, axis in ipairs({ aR, aF, bR, bF }) do
		local radiusA = math.abs(aR:Dot(axis)) * sizeA.X / 2 + math.abs(aF:Dot(axis)) * sizeA.Z / 2
		local radiusB = math.abs(bR:Dot(axis)) * sizeB.X / 2 + math.abs(bF:Dot(axis)) * sizeB.Z / 2
		if math.abs(d:Dot(axis)) > radiusA + radiusB then
			return false
		end
	end
	return true
end

-- Caja de un ataque delante de quien golpea: `range` de fondo empezando 0,5 studs por delante
function Hurtbox.AttackBox(attackerCFrame, range)
	return Hurtbox.Flat(attackerCFrame) * CFrame.new(0, 0, -(range / 2 + 0.5))
end

-- ¿El ataque (caja `size` delante de `attackerCFrame`) alcanza a un objetivo con raíz en `targetCFrame`?
-- `tolerance`: studs extra (el servidor la usa para absorber diferencias pequeñas de sincronización)
function Hurtbox.AttackHits(attackerCFrame, range, size, targetCFrame, tolerance)
	local grow = tolerance or 0
	return Hurtbox.BoxesOverlap(
		Hurtbox.AttackBox(attackerCFrame, range),
		size + Vector3.new(grow * 2, grow * 2, grow * 2),
		Hurtbox.Flat(targetCFrame),
		Hurtbox.Size
	)
end

-- ¿El objetivo está dentro de un área circular (barridos)? Usa el borde de su caja, no solo el centro.
function Hurtbox.InRadius(center, radius, targetPosition, maxHeight)
	local offset = targetPosition - center
	local flatDistance = Vector3.new(offset.X, 0, offset.Z).Magnitude
	return flatDistance <= radius + Hurtbox.Size.X / 2 and math.abs(offset.Y) <= (maxHeight or 6)
end

return Hurtbox
