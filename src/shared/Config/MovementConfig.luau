-- MovementConfig: única fuente de verdad del movimiento (Fase 1: laboratorio de movimiento).
-- Todos los valores son HIPÓTESIS DE DISEÑO: se ajustan probando, no son definitivos.
-- Unidades: studs y segundos. Como referencia, Roblox camina por defecto a 16 studs/s.
-- tools/construir.mjs también lee RunSpeed, JumpHeight y Gravity de este archivo.

local MovementConfig = {
	-- Carrera y sprint automático
	RunSpeed = 22, -- velocidad al empezar a moverse
	SprintSpeed = 34, -- velocidad de sprint
	SprintDelay = 0.4, -- segundos manteniendo una dirección para entrar en sprint
	SprintRampTime = 0.15, -- segundos para pasar de RunSpeed a SprintSpeed
	SprintGraceTime = 0.12, -- segundos sin dirección antes de perder el sprint

	-- Paso (dash)
	DashDistance = 14, -- studs recorridos por un Paso (se cumple por distancia, igual a cualquier FPS)
	DashDuration = 0.18, -- duración ideal: fija la velocidad (distancia / duración ≈ 78 studs/s); tope = ×1,5
	DashCharges = 2, -- cargas disponibles
	DashRechargeTime = 0.8, -- segundos por carga (se recargan de una en una)
	DashMinInterval = 0.08, -- segundos mínimos entre dos Pasos
	DashExitBlendTime = 0.06, -- segundos para fundir la salida del Paso con el sprint
	AirDashesPerJump = 1, -- Pasos en el aire antes de volver a tocar el suelo
	AirDashHoldsHeight = true, -- el Paso aéreo mantiene la altura (no cae mientras dura)

	-- Salto
	Gravity = 230, -- workspace.Gravity (Roblox por defecto: 196.2). Más gravedad = saltos más secos
	JumpHeight = 8.5, -- altura del salto normal
	AirJumps = 1, -- saltos extra en el aire (doble salto)
	AirJumpHeight = 7, -- altura del doble salto
	CoyoteTime = 0.1, -- segundos para saltar aún después de salir de un borde
	JumpBufferTime = 0.12, -- segundos que se recuerda un salto pulsado antes de aterrizar
	FallGravityMultiplier = 1.35, -- gravedad extra al caer (menos sensación de flotar)
	MaxFallSpeed = 140, -- velocidad máxima de caída

	-- Cámara
	BaseFOV = 70,
	SprintFOV = 76,
	DashFOVKick = 8, -- grados extra de campo de visión al iniciar un Paso
	FOVResponsiveness = 12, -- qué tan rápido sigue la cámara al FOV objetivo

	-- Depuración
	DebugHUD = false, -- panel con velocidad, cargas y estado (true para medir; las pruebas no lo necesitan)
	DebugPrints = true, -- mensajes [UMBRAL] en Output
}

return MovementConfig
