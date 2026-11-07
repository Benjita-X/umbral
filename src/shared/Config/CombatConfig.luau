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
	-- Movilidad al atacar (2026-11-06, pedido del jugador: "moverse mientras atacas"): antes 0,35 y 0,3
	AttackMoveMultiplier = 0.8, -- velocidad mientras golpeas
	ChargeMoveMultiplier = 0.6, -- velocidad mientras cargas el golpe fuerte
	GuardMoveMultiplier = 0.45, -- velocidad en guardia

	-- Orientación y acercamiento (iguales en PC, mando y celular: solo orientan, no aciertan por ti)
	SoftTargetRange = 12, -- distancia a la que busca rival al golpear
	SoftTargetAngle = 75, -- grados a cada lado de hacia donde apuntas
	IdealDistance = 3.2, -- distancia a la que el golpe conecta mejor
	MaxLunge = 3.5, -- lo máximo que un golpe te acerca al rival
	LungeWithoutTarget = 1, -- avance de cada golpe al aire

	-- Validación en el servidor
	Validation = {
		Tolerance = 1.5, -- studs extra al comprobar un golpe en el servidor (sincronización)
		MinSequenceInterval = 0.08, -- tiempo mínimo entre dos golpes distintos del mismo jugador
		MaxHitsPerSecond = 14,
		MaxStartsPerSecond = 12, -- inicios de ataque por segundo (el combo más rápido da ~7)
		StartTimeSlack = 0.02, -- margen al comparar horas de inicio (son del reloj del cliente: sin desfase de red)
		HitWindowSlack = 0.25, -- margen sobre la ventana activa al juzgar la hora de un golpe (hitstop, red)
	},

	-- Red: historial de posiciones con hora del servidor (ver PositionService y docs/AUDITORIA-FASE3.md)
	Network = {
		ReportRate = 20, -- posiciones por segundo que manda cada cliente
		MaxReportsPerSecond = 45, -- tope de informes por jugador (incluye los que van con golpes y defensas)
		HistorySeconds = 1.5, -- cuánto historial se guarda
		MaxRewind = 0.3, -- retroceso temporal MÁXIMO (s): con más ping no se compra más ventana
		-- Medido: al avanzar golpeando, la trayectoria replicada se separa hasta ~2 studs de la real; con 1,5
		-- se rechazaban golpes legítimos. 2,25 sigue rechazando una posición falsa de 3,5 studs (prueba).
		ConfirmRadius = 2.25, -- la trayectoria observada debe pasar a esta distancia de lo informado...
		ConfirmSpeedFactor = 0.04, -- ...más velocidad × esto (en un Paso a 78 studs/s: +3,1 studs)
		ConfirmWindow = 0.25, -- ...dentro de este tiempo (más la latencia de ida)
		MaxSpeed = 160, -- studs/s horizontales: lo más rápido posible (Paso 78, empuje fuerte ~83, Contraataque)
		ObservedSpeedWindow = 0.1, -- s: tramo sobre el que se mide la velocidad observada de cada jugador
		ClockSlack = 0.15, -- margen al validar la hora que manda el cliente
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
			posture = 8, -- desgaste de postura si el rival bloquea (PvP, Fase 4)
			hitstun = 0.3, -- aturdimiento del rival al recibirlo (PvP, Fase 4)
			shape = "box",
			deflectable = true,
			guardable = true,
			contrapaso = true,
			cancelOnHit = true, -- al conectar se encadena desde la recuperación
			cancelInto = { "Paso", "Salto", "Guardia" }, -- qué cancela su recuperación
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
			posture = 10,
			hitstun = 0.32,
			shape = "box",
			deflectable = true,
			guardable = true,
			contrapaso = true,
			cancelOnHit = true,
			cancelInto = { "Paso", "Salto", "Guardia" },
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
			posture = 18,
			hitstun = 0.5,
			shape = "box",
			deflectable = true,
			guardable = true,
			contrapaso = true,
			cancelOnHit = false, -- remate: no se encadena
			cancelInto = { "Paso", "Salto" },
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
			posture = 35,
			hitstun = 0.7,
			shape = "box",
			deflectable = true,
			guardable = true,
			contrapaso = true,
			cancelOnHit = false,
			cancelInto = { "Paso", "Salto" },
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
		-- AGUANTE (anticadena): cada aturdimiento dentro de StunChainWindow dura ×StunChainFactor respecto al
		-- anterior; al llegar a StunChainMax, AguanteTime segundos sin nuevos aturdimientos (el daño sí entra).
		-- Así varios enemigos no pueden dejarte inmóvil sin oportunidad de responder.
		StunChainWindow = 2,
		StunChainFactor = 0.6,
		StunChainMax = 3,
		AguanteTime = 0.8,
		HitKnockback = 18,
		JumpClearance = 1.5, -- studs sobre la altura normal para saltar por encima de un barrido
		TimestampSlack = 0.15, -- margen extra al validar los tiempos que manda el cliente
		-- Desvío fallido: si pulsas (sin mantener) y no llega ningún golpe en la ventana, quedas EXPUESTO
		-- un instante: la guardia no funciona y el golpe que llegue hace más daño. Desviar a ciegas se paga.
		WhiffPenalty = 0.3,
		ExposedDamageMultiplier = 1.25,
	},

	-- Resonancia: recurso que se gana jugando bien. Fase 3: se gana y se gasta en un Paso extra.
	-- Anti-abuso: los muñecos que no pelean NO dan Resonancia; repetir el mismo golpe al mismo rival da
	-- cada vez menos; y cada rival da como máximo SourceCap cada SourceWindow segundos.
	Resonance = {
		Max = 100,
		Gains = { Golpe = 5, Desvio = 5, DesvioPerfecto = 15, Esquiva = 10, Contrapaso = 20, Contratiempo = 25, VencerComun = 20, VencerGuardian = 40 },
		MaxGainPerSecond = 40,
		RepeatDecay = 0.5, -- el mismo golpe seguido al mismo rival: ×0,5 cada repetición
		RepeatWindow = 3,
		SourceWindow = 5,
		SourceCap = 25,
		DecayDelay = 5, -- sin combate este tiempo, empieza a apagarse
		DecayPerSecond = 8,
		DashCost = 30, -- sin cargas de Paso, gastar esto da un Paso extra...
		ExtraDashCooldown = 2, -- ...como mucho uno cada este tiempo
	},

	-- Compañero de combate: oponente de entrenamiento configurable (Fase 3).
	-- Perfil (atributo "Perfil"): básico, técnico o agresivo. Las pruebas fijan "Patron" y "Retraso".
	-- "Amague" en un patrón: empieza a preparar un Golpe, lo corta en FeintRestartAt y prepara el real.
	Sparring = {
		MaxHealth = 300,
		AggroRange = 12, -- empieza a atacar si hay un jugador a esta distancia
		TurnSpeed = 7, -- radianes por segundo
		TrackingStop = 0.15, -- deja de girar este tiempo antes del impacto (se puede esquivar de lado)
		ReturnSpeed = 12, -- vuelve a su sitio tras lanzarse
		StaggerOnPerfect = 0.8, -- aturdido tras un desvío perfecto
		StaggerOnInterrupt = 0.5, -- aturdido si un golpe fuerte lo interrumpe al preparar
		FeintRestartAt = 0.3,
		DefaultProfile = "basico",
		-- Guardián de la Grieta (mazmorra de muestra, solo en el lugar de desarrollo): mismo oponente, más
		-- exigente; no se cura solo y al vencerlo se levanta tras RiseAfter segundos
		Guardian = { MaxHealth = 220, Profile = "tecnico", RiseAfter = 8 },
		-- Enemigos comunes de la Grieta. Cada uno enseña una mecánica y castiga un hábito:
		--   Latido    · ataca a ritmo fijo (corazón de luz). 3 desvíos perfectos seguidos = CONTRATIEMPO
		--               (aturdido largo y Resonancia). Con menos vida, el ritmo se acelera.
		--   Centinela · coraza frontal: de frente no hace daño; por la espalda ×1,5 (el Contrapaso lleva ahí).
		--               No se gira al recibir un golpe. Aturdido, la coraza no protege.
		--   Gemelo    · dos que comparten una sola vida.
		-- Regla de todos: DESVÍO REFLEJADO. Un desvío perfecto lanza una onda que daña (el daño del ataque
		-- desviado) y aturde a los otros enemigos a menos de ReflectRadius del jugador.
		Types = {
			Latido = { label = "Latido", maxHealth = 80, profile = "latido", body = Color3.fromRGB(120, 34, 52), legs = Color3.fromRGB(60, 18, 28), glow = Color3.fromRGB(255, 70, 110), riseAfter = 20, rhythmStreak = 3, rhythmStun = 2.5 },
			Centinela = { label = "Centinela", maxHealth = 90, profile = "centinela", body = Color3.fromRGB(58, 68, 92), legs = Color3.fromRGB(34, 40, 56), glow = Color3.fromRGB(120, 200, 255), riseAfter = 20, frontArmor = true, frontAngle = 70, backMultiplier = 1.5 },
			-- Acechador: GOLPE DE OPORTUNIDAD. Si fallas un remate o un golpe fuerte a menos de opportunityRange,
			-- te castiga con una Embestida durante tu recuperación (como mucho una cada opportunityCooldown s).
			Acechador = { label = "Acechador", maxHealth = 60, profile = "acechador", body = Color3.fromRGB(70, 60, 30), legs = Color3.fromRGB(40, 34, 16), glow = Color3.fromRGB(255, 230, 120), riseAfter = 20, opportunityRange = 16, opportunityCooldown = 6 },
			Gemelo = { label = "Gemelo de Eco", maxHealth = 70, profile = "gemelo", body = Color3.fromRGB(34, 86, 78), legs = Color3.fromRGB(18, 46, 42), glow = Color3.fromRGB(90, 255, 200), riseAfter = 20, linked = true },
		},
		ReflectRadius = 10, -- alcance de la onda del Desvío Reflejado
		ReflectStun = 0.6,
		ActiveRange = 80, -- rendimiento: sin jugadores a esta distancia, el enemigo duerme
		SleepCheck = 4, -- veces por segundo que un enemigo dormido revisa si alguien se acerca
		ReflectMaxTargets = 3, -- tope: un solo desvío no debe vaciar un grupo grande (AUDITORIA-2-AMENAZA.md)
		Profiles = {
			basico = { pattern = { "Golpe", "Golpe", "Barrido" }, pause = 1.2, maxDelay = 0 },
			tecnico = { pattern = { "Golpe", "Rapido", "Fuerte", "Barrido", "Amague", "Golpe" }, pause = 1.0, maxDelay = 0.3 },
			agresivo = { pattern = { "Rapido", "Rapido", "Golpe", "Fuerte", "Barrido", "Amague" }, pause = 0.6, maxDelay = 0.2 },
			-- Enemigos comunes de la Grieta (ver Types)
			latido = { pattern = { "Rapido" }, pause = 0.7, maxDelay = 0, rhythm = true }, -- ritmo fijo: se aprende
			centinela = { pattern = { "Golpe", "Golpe", "Fuerte" }, pause = 1.1, maxDelay = 0.2 },
			gemelo = { pattern = { "Golpe", "Rapido", "Barrido" }, pause = 1.4, maxDelay = 0.3 },
			acechador = { pattern = { "Rapido", "Golpe" }, pause = 1.6, maxDelay = 0.2 }, -- tranquilo... hasta que fallas
		},
		-- Mismo esquema que los golpes del jugador (ver MoveSchema): preparación, impacto, recuperación,
		-- daño, postura, forma y alcance, y qué defensas admite.
		Attacks = {
			Golpe = {
				label = "Golpe",
				startup = 0.5,
				active = 0.1,
				recovery = 0.5,
				damage = 12,
				posture = 25,
				shape = "box",
				range = 5.5,
				hitboxSize = Vector3.new(5, 6, 5.5),
				lunge = 3, -- studs que se lanza hacia adelante al golpear
				deflectable = true,
				guardable = true,
				contrapaso = true,
				delayable = true, -- puede quedarse armado más tiempo (variación de ritmo)
				clip = "SparringGolpe",
				holdAt = 0.375, -- instante del clip en que queda armado (donde se alarga el retraso)
			},
			Rapido = {
				label = "Golpe rápido",
				startup = 0.28,
				active = 0.08,
				recovery = 0.35,
				damage = 7,
				posture = 15,
				shape = "box",
				range = 5,
				hitboxSize = Vector3.new(4.5, 6, 5),
				lunge = 2,
				deflectable = true,
				guardable = true,
				contrapaso = true,
				delayable = false,
				clip = "SparringRapido",
			},
			Fuerte = {
				label = "Golpe pesado",
				startup = 0.85,
				active = 0.12,
				recovery = 0.8,
				damage = 22,
				posture = 60,
				shape = "box",
				range = 6,
				hitboxSize = Vector3.new(5.5, 6, 6),
				lunge = 9, -- se lanza: alejarse antes de tiempo no basta
				deflectable = true,
				perfectOnly = true, -- solo el desvío PERFECTO lo detiene
				guardable = true,
				contrapaso = true,
				delayable = true,
				clip = "SparringFuerte",
				holdAt = 0.6,
			},
			-- Golpe de Oportunidad del Acechador: solo castiga un golpe pesado fallado (ver Types.Acechador).
			-- Rápido pero avisado (brillo blanco), desviable, bloqueable y esquivable; daño acotado: lo que
			-- importa es la interrupción, la postura y el empuje.
			Embestida = {
				label = "Embestida",
				startup = 0.24,
				active = 0.08,
				recovery = 0.7,
				damage = 9,
				posture = 30,
				shape = "box",
				range = 5,
				hitboxSize = Vector3.new(4.5, 6, 5),
				lunge = 8,
				deflectable = true,
				guardable = true,
				contrapaso = true,
				delayable = false,
				opportunity = true, -- no está en ningún patrón: solo la dispara su condición
				clip = "SparringRapido",
			},
			Barrido = {
				label = "Barrido",
				startup = 0.7,
				active = 0.12,
				recovery = 0.7,
				damage = 15,
				posture = 0,
				shape = "ring", -- área alrededor: no se desvía ni se bloquea; se salta o se sale
				radius = 7,
				lunge = 0,
				deflectable = false,
				guardable = false,
				contrapaso = false,
				delayable = false,
				clip = "SparringBarrido",
			},
		},
	},

	-- Ecos del jugador (Fase 7, EXPERIMENTAL). Primer Eco: Eco del Viento (botón Eco: Q / Y / ECO).
	-- Cuestan Resonancia y no la devuelven. El servidor decide alcance y daño (EcoService).
	Eco = {
		Name = "Eco del Viento",
		Techniques = {
			-- En el suelo: onda frontal. Atraviesa corazas e interrumpe al enemigo que prepara un ataque.
			Rafaga = { cost = 35, cooldown = 2.5, damage = 12, range = 12, hitboxSize = Vector3.new(7, 6, 12), knockback = 45, knockUp = 8 },
			-- En el aire: picada y onda circular al aterrizar.
			Descenso = { cost = 35, cooldown = 3, damage = 14, radius = 8, knockback = 30, knockUp = 18, window = 1.5, plungeSpeed = 110 },
		},
	},

	-- IDs de animaciones publicadas en Roblox (rbxassetid://...). Vacío = se usan las generadas
	-- por código (solo funcionan en Studio). Antes de publicar el juego hay que subirlas y ponerlas aquí.
	AnimationIds = {},
}

return CombatConfig
