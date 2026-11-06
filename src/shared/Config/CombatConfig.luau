-- CombatConfig: única fuente de verdad del combate corporal (Fase 2).
-- La usan el cliente (golpes, animaciones, efectos) y el servidor (validación y daño).
-- Todos los valores son HIPÓTESIS DE DISEÑO: se ajustan probando. Tiempos en segundos, distancias en studs.
--
-- Cada golpe tiene tres momentos:
--   startup  · preparación: el rival puede leer la intención
--   active   · impacto: aquí se buscan los golpes
--   recovery · recuperación: el atacante queda expuesto
-- Las animaciones se generan con estos mismos tiempos, así que siempre van sincronizadas.

local CombatConfig = {
	-- Entradas
	HoldThreshold = 0.22, -- mantener Atacar este tiempo convierte el combo en golpe fuerte
	HeavyMaxCharge = 0.65, -- carga máxima del golpe fuerte (sale solo al llegar)
	ComboResetTime = 0.6, -- sin atacar este tiempo después de un golpe, el combo vuelve al primero

	-- Ritmo
	WhiffRecoveryMultiplier = 1.35, -- fallar alarga la recuperación (y no deja cancelar)
	AttackMoveMultiplier = 0.35, -- velocidad mientras golpeas
	ChargeMoveMultiplier = 0.3, -- velocidad mientras cargas el golpe fuerte
	GuardMoveMultiplier = 0.45, -- velocidad en guardia

	-- Orientación y acercamiento (iguales en PC, mando y celular: solo orientan, no aciertan por ti)
	SoftTargetRange = 12, -- distancia a la que busca rival al golpear
	SoftTargetAngle = 75, -- grados a cada lado de hacia donde apuntas
	IdealDistance = 3.2, -- distancia a la que el golpe conecta mejor
	MaxLunge = 3.5, -- lo máximo que un golpe te acerca al rival
	LungeWithoutTarget = 1, -- avance de cada golpe al aire

	-- Validación en el servidor
	Validation = {
		ExtraRange = 4, -- margen por latencia y movimiento
		LagWindow = 0.35, -- si el golpe parece lejano, se espera esto a que llegue la posición real
		MinSequenceInterval = 0.08, -- tiempo mínimo entre dos golpes distintos del mismo jugador
		MaxHitsPerSecond = 14,
	},

	-- Muñecos de práctica
	Dummy = {
		MaxHealth = 120,
		ToughMaxHealth = 500, -- el muñeco de aguante, para combos largos
		RegenDelay = 2.5, -- sin recibir golpes este tiempo, empieza a recuperarse
		RegenPerSecond = 80,
		ResetDelay = 2, -- vuelve a su sitio tras este tiempo quieto
		KnockbackTime = 0.12, -- duración del empuje
	},

	-- Respuesta visual y sonora (accesibilidad: se pueden bajar)
	Feedback = {
		ScreenShake = 1, -- 0 desactiva la vibración de cámara
		MaxShakeOffset = 0.45,
		Flashes = true, -- destello blanco del objetivo al recibir el golpe
		DamageNumbers = true,
	},

	-- Combo básico: pulsar Atacar encadena estos golpes en orden
	LightChain = { "Jab", "Cross", "Patada" },

	Attacks = {
		Jab = {
			label = "Jab",
			startup = 0.07,
			active = 0.06,
			recovery = 0.14,
			damage = 4,
			range = 4.2, -- profundidad de la zona de golpe delante del personaje
			hitboxSize = Vector3.new(4.5, 5, 4.2),
			hitstop = 0.05, -- congelamiento breve al conectar: hace que el golpe "pese"
			knockback = 6, -- empuje del objetivo (studs/s)
			knockUp = 0,
			limb = "LeftHand", -- extremidad que deja estela
			shake = 0,
		},
		Cross = {
			label = "Directo",
			startup = 0.08,
			active = 0.06,
			recovery = 0.16,
			damage = 5,
			range = 4.4,
			hitboxSize = Vector3.new(4.5, 5, 4.4),
			hitstop = 0.055,
			knockback = 8,
			knockUp = 0,
			limb = "RightHand",
			shake = 0.08,
		},
		Patada = {
			label = "Patada",
			finisher = true, -- cierra el combo: no se cancela, empuja fuerte
			startup = 0.11,
			active = 0.08,
			recovery = 0.25,
			damage = 7,
			range = 4.8,
			hitboxSize = Vector3.new(5, 5, 4.8),
			hitstop = 0.08,
			knockback = 38,
			knockUp = 10,
			limb = "RightFoot",
			shake = 0.25,
		},
		Fuerte = {
			label = "Golpe fuerte",
			heavy = true,
			finisher = true,
			startup = 0.06, -- la preparación real es la carga
			active = 0.1,
			recovery = 0.35,
			damage = 10, -- daño con carga mínima
			chargeBonus = 8, -- daño extra con carga completa
			range = 5,
			hitboxSize = Vector3.new(5, 5.5, 5),
			hitstop = 0.11,
			knockback = 55,
			knockUp = 22,
			limb = "RightHand",
			shake = 0.45,
		},
	},

	-- ---------- Fase 3: defensa ----------
	-- Defender es una sola tecla: al pulsarla se abre una ventana de desvío; si se mantiene, es guardia.
	Defense = {
		DeflectWindow = 0.18, -- el golpe se desvía si llega hasta este tiempo después de pulsar
		PerfectWindow = 0.1, -- si llega dentro de este tiempo: desvío PERFECTO
		DeflectCooldown = 0.35, -- pulsar de nuevo antes de esto no abre ventana (machacar no sirve)
		GuardAngle = 100, -- grados del frente que cubre la guardia
		GuardDamageMultiplier = 0.2,
		DeflectPostureChip = 10, -- un desvío normal desgasta un poco la postura
		PostureMax = 100,
		PostureRegenDelay = 1.5,
		PostureRegenPerSecond = 25,
		GuardBreakStun = 0.9, -- aturdimiento al romperse la guardia
		ContrapasoWindow = 0.25, -- el Paso debe salir a lo sumo este tiempo antes del impacto
		ContrapasoMinAngle = 45, -- y en diagonal o de lado respecto al atacante (entre estos ángulos)
		ContrapasoMaxAngle = 135,
		PreciseDodgeWindow = 0.3, -- Paso que saca del golpe justo a tiempo: esquiva precisa
		CounterWindow = 0.8, -- tras desvío perfecto o Contrapaso, el siguiente golpe es Contraataque
		CounterDamageMultiplier = 1.3,
		CounterStartupMultiplier = 0.5, -- el Contraataque sale el doble de rápido
		CounterTargetRange = 18, -- y llega más lejos (vuelves al rival tras esquivar de lado)
		CounterMaxLunge = 12,
		HitStun = 0.35, -- aturdimiento al recibir un golpe
		HitKnockback = 18,
		JumpClearance = 1.5, -- studs sobre la altura normal para saltar por encima de un barrido
		LagCompensationMax = 0.25, -- lo máximo que el servidor espera por latencia antes de resolver
		TimestampSlack = 0.15, -- margen extra al validar los tiempos que manda el cliente
	},

	-- Resonancia: recurso que se gana jugando bien. Fase 3: se gana y se gasta en un Paso extra.
	Resonance = {
		Max = 100,
		Gains = { Golpe = 5, Desvio = 5, DesvioPerfecto = 15, Esquiva = 10, Contrapaso = 20 },
		MaxGainPerSecond = 40, -- límite para que no se pueda "farmear"
		DecayDelay = 5, -- sin combate este tiempo, empieza a apagarse
		DecayPerSecond = 8,
		DashCost = 30, -- sin cargas de Paso, gastar esto da un Paso extra
	},

	-- Compañero de combate: muñeco que ataca para practicar la defensa
	Sparring = {
		MaxHealth = 300,
		AggroRange = 12, -- empieza a atacar si hay un jugador a esta distancia
		TurnSpeed = 7, -- radianes por segundo
		TrackingStop = 0.15, -- deja de girar este tiempo antes del impacto (se puede esquivar de lado)
		Pause = 1.2, -- pausa entre ataques
		Pattern = { "Golpe", "Golpe", "Barrido" },
		StaggerOnPerfect = 0.8, -- aturdido tras un desvío perfecto
		StaggerOnInterrupt = 0.5, -- aturdido si un golpe fuerte lo interrumpe al preparar
		Attacks = {
			Golpe = {
				label = "Golpe",
				windup = 0.5,
				active = 0.1,
				recovery = 0.5,
				damage = 12,
				posture = 25,
				shape = "box",
				range = 5.5,
				hitboxSize = Vector3.new(5, 6, 5.5),
				deflectable = true,
				guardable = true,
				contrapaso = true,
			},
			Barrido = {
				label = "Barrido",
				windup = 0.7,
				active = 0.12,
				recovery = 0.7,
				damage = 15,
				posture = 0,
				shape = "ring", -- área alrededor: no se desvía ni se bloquea; se salta o se sale
				radius = 7,
				deflectable = false,
				guardable = false,
				contrapaso = false,
			},
		},
	},

	-- IDs de animaciones publicadas en Roblox (rbxassetid://...). Vacío = se usan las generadas
	-- por código (solo funcionan en Studio). Antes de publicar el juego hay que subirlas y ponerlas aquí.
	AnimationIds = {},
}

return CombatConfig
