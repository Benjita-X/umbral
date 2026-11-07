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

	-- Combo básico: pulsar Atacar encadena estos golpes en orden (Puños; cada arma tiene el suyo en Weapons)
	LightChain = { "Jab", "Cross", "Patada" },

	-- Armas (EXPERIMENTAL): Q cambia entre Puños y Espada. Cada arma tiene su combo (pulsar Atacar), su golpe
	-- fuerte (mantener), un golpe tras el Paso (atacar justo después de un Paso) y uno en picada (atacar cayendo
	-- desde altura). El servidor valida que el golpe sea del arma que llevas y que se cumpla su condición.
	Weapons = {
		Order = { "Punos", "Espada" },
		Punos = { label = "Puños", chain = { "Jab", "Cross", "Patada" }, heavy = "Fuerte", dash = "PatadaVoladora", plunge = "PatadaPicada" },
		Espada = { label = "Espada", chain = { "Tajo", "Reves", "Estocada" }, heavy = "TajoFuerte", dash = "EstocadaCarrera", plunge = "Clavada" },
		DashWindow = 0.4, -- s tras un Paso en los que atacar sale como golpe tras el Paso
		PlungeMinHeight = 5, -- altura mínima de los pies para el golpe en picada
		SwitchTime = 0.25, -- s sin poder atacar al cambiar de arma
	},

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
		-- ---------- Puños: golpes especiales ----------
		PatadaVoladora = {
			label = "Patada voladora",
			weapon = "Punos",
			special = "dash", -- atacar justo después de un Paso
			finisher = true,
			startup = 0.06,
			active = 0.1,
			recovery = 0.3,
			damage = 8,
			range = 5,
			hitboxSize = Vector3.new(5, 5, 5),
			hitstop = 0.08,
			knockback = 45,
			knockUp = 12,
			lunge = 9, -- studs extra hacia adelante (sale del impulso del Paso)
			limb = "RightFoot",
			shake = 0.25,
			posture = 20,
			hitstun = 0.5,
			shape = "box",
			deflectable = true,
			guardable = true,
			contrapaso = true,
			cancelOnHit = false,
			cancelInto = { "Paso", "Salto" },
		},
		PatadaPicada = {
			label = "Patada en picada",
			weapon = "Punos",
			special = "plunge", -- atacar cayendo desde altura
			finisher = true,
			startup = 0.08,
			active = 0.4,
			recovery = 0.3,
			damage = 10,
			range = 4.5,
			hitboxSize = Vector3.new(6, 10, 5), -- alta: alcanza a los de abajo mientras cae
			hitstop = 0.07,
			knockback = 18,
			knockUp = 28,
			plungeSpeed = 75,
			limb = "RightFoot",
			shake = 0.35,
			posture = 22,
			hitstun = 0.5,
			shape = "box",
			deflectable = true,
			guardable = true,
			contrapaso = false,
			cancelOnHit = false,
			cancelInto = { "Paso", "Salto" },
		},

		-- ---------- Espada: más alcance y daño, algo más lenta ----------
		Tajo = {
			label = "Tajo",
			weapon = "Espada",
			startup = 0.09,
			active = 0.07,
			recovery = 0.16,
			damage = 7,
			range = 7,
			hitboxSize = Vector3.new(8, 5, 7),
			idealDistance = 5, -- se acerca menos: la espada llega lejos
			hitstop = 0.06,
			knockback = 8,
			knockUp = 0,
			limb = "UmbralEspadaHoja",
			shake = 0.05,
			posture = 12,
			hitstun = 0.32,
			shape = "box",
			deflectable = true,
			guardable = true,
			contrapaso = true,
			cancelOnHit = true,
			cancelInto = { "Paso", "Salto", "Guardia" },
		},
		Reves = {
			label = "Revés",
			weapon = "Espada",
			startup = 0.09,
			active = 0.07,
			recovery = 0.18,
			damage = 8,
			range = 7,
			hitboxSize = Vector3.new(8, 5, 7),
			idealDistance = 5,
			hitstop = 0.065,
			knockback = 10,
			knockUp = 0,
			limb = "UmbralEspadaHoja",
			shake = 0.1,
			posture = 14,
			hitstun = 0.34,
			shape = "box",
			deflectable = true,
			guardable = true,
			contrapaso = true,
			cancelOnHit = true,
			cancelInto = { "Paso", "Salto", "Guardia" },
		},
		Estocada = {
			label = "Estocada",
			weapon = "Espada",
			finisher = true,
			startup = 0.13,
			active = 0.09,
			recovery = 0.3,
			damage = 12,
			range = 8.5,
			hitboxSize = Vector3.new(4.5, 5, 8.5),
			idealDistance = 5.5,
			hitstop = 0.09,
			knockback = 42,
			knockUp = 8,
			limb = "UmbralEspadaHoja",
			shake = 0.3,
			posture = 22,
			hitstun = 0.5,
			shape = "box",
			deflectable = true,
			guardable = true,
			contrapaso = true,
			cancelOnHit = false,
			cancelInto = { "Paso", "Salto" },
		},
		TajoFuerte = {
			label = "Tajo cargado",
			weapon = "Espada",
			heavy = true,
			finisher = true,
			startup = 0.06,
			active = 0.12,
			recovery = 0.4,
			damage = 14,
			chargeBonus = 12,
			range = 8,
			hitboxSize = Vector3.new(9, 6, 8),
			idealDistance = 5,
			hitstop = 0.12,
			knockback = 60,
			knockUp = 25,
			limb = "UmbralEspadaHoja",
			shake = 0.5,
			posture = 40,
			hitstun = 0.75,
			shape = "box",
			deflectable = true,
			guardable = true,
			contrapaso = true,
			cancelOnHit = false,
			cancelInto = { "Paso", "Salto" },
		},
		EstocadaCarrera = {
			label = "Estocada en carrera",
			weapon = "Espada",
			special = "dash",
			finisher = true,
			startup = 0.06,
			active = 0.1,
			recovery = 0.3,
			damage = 10,
			range = 8,
			hitboxSize = Vector3.new(4.5, 5, 8),
			idealDistance = 5,
			hitstop = 0.08,
			knockback = 40,
			knockUp = 6,
			lunge = 10,
			limb = "UmbralEspadaHoja",
			shake = 0.25,
			posture = 22,
			hitstun = 0.5,
			shape = "box",
			deflectable = true,
			guardable = true,
			contrapaso = true,
			cancelOnHit = false,
			cancelInto = { "Paso", "Salto" },
		},
		Clavada = {
			label = "Clavada",
			weapon = "Espada",
			special = "plunge",
			finisher = true,
			startup = 0.08,
			active = 0.4,
			recovery = 0.32,
			damage = 13,
			range = 5,
			hitboxSize = Vector3.new(6, 10, 5.5),
			hitstop = 0.08,
			knockback = 20,
			knockUp = 30,
			plungeSpeed = 80,
			limb = "UmbralEspadaHoja",
			shake = 0.4,
			posture = 26,
			hitstun = 0.55,
			shape = "box",
			deflectable = true,
			guardable = true,
			contrapaso = false,
			cancelOnHit = false,
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

	-- Postura enemiga y Golpe de Gracia (EXPERIMENTAL, inspirado en los juegos de duelos con espada): desviar y
	-- golpear llena la postura de un enemigo; si se llena, queda QUEBRADO unos segundos y atacar cerca de él hace un
	-- Golpe de Gracia (mucho daño). La postura baja sola si se le deja respirar.
	EnemyPosture = {
		Max = 100,
		GuardianMax = 170,
		DecayDelay = 2.5, -- sin recibir presión este tiempo, empieza a recuperarse...
		DecayPerSecond = 14, -- ...a este ritmo
		BreakTime = 2.6, -- s quebrado (abierto al Golpe de Gracia)
		Gains = { DesvioPerfecto = 35, Desvio = 16, Eco = 8, ComboScale = 0.6 }, -- ComboScale × postura del golpe
		Execute = { range = 9, damageRatio = 0.35, guardianRatio = 0.22, minDamage = 30 },
	},

	-- Resonancia: recurso que se gana jugando bien. Fase 3: se gana y se gasta en un Paso extra.
	-- Anti-abuso: los muñecos que no pelean NO dan Resonancia; repetir el mismo golpe al mismo rival da
	-- cada vez menos; y cada rival da como máximo SourceCap cada SourceWindow segundos.
	Resonance = {
		Max = 100,
		Gains = { Golpe = 5, Desvio = 5, DesvioPerfecto = 15, Esquiva = 10, Contrapaso = 20, Contratiempo = 25, VencerComun = 20, VencerGuardian = 40, Sinergia = 10, GolpeDeGracia = 30 },
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
		Guardian = { MaxHealth = 400, Profile = "tecnico", RiseAfter = 8 },
		-- Enemigos comunes de la Grieta. Cada uno enseña una mecánica y castiga un hábito:
		--   Latido    · ataca a ritmo fijo (corazón de luz). 3 desvíos perfectos seguidos = CONTRATIEMPO
		--               (aturdido largo y Resonancia). Con menos vida, el ritmo se acelera.
		--   Centinela · coraza frontal: de frente no hace daño; por la espalda ×1,5 (el Contrapaso lleva ahí).
		--               No se gira al recibir un golpe. Aturdido, la coraza no protege.
		--   Gemelo    · dos que comparten una sola vida.
		-- Regla de todos: DESVÍO REFLEJADO. Un desvío perfecto lanza una onda que daña (el daño del ataque
		-- desviado) y aturde a los otros enemigos a menos de ReflectRadius del jugador.
		Types = {
			Latido = { label = "Latido", maxHealth = 110, profile = "latido", body = Color3.fromRGB(120, 34, 52), legs = Color3.fromRGB(60, 18, 28), glow = Color3.fromRGB(255, 70, 110), riseAfter = 20, rhythmStreak = 3, rhythmStun = 2.5 },
			Centinela = { label = "Centinela", maxHealth = 125, profile = "centinela", body = Color3.fromRGB(58, 68, 92), legs = Color3.fromRGB(34, 40, 56), glow = Color3.fromRGB(120, 200, 255), riseAfter = 20, frontArmor = true, frontAngle = 70, backMultiplier = 1.5 },
			-- Acechador: GOLPE DE OPORTUNIDAD. Si fallas un remate o un golpe fuerte a menos de opportunityRange,
			-- te castiga con una Embestida durante tu recuperación (como mucho una cada opportunityCooldown s).
			Acechador = { label = "Acechador", maxHealth = 85, profile = "acechador", body = Color3.fromRGB(70, 60, 30), legs = Color3.fromRGB(40, 34, 16), glow = Color3.fromRGB(255, 230, 120), riseAfter = 20, opportunityRange = 16, opportunityCooldown = 6 },
			-- Instructor del tutorial: lento, predecible, se cura solo (para practicar sin prisa)
			Instructor = { label = "Instructor", maxHealth = 150, profile = "instructor", body = Color3.fromRGB(200, 200, 210), legs = Color3.fromRGB(120, 120, 135), glow = Color3.fromRGB(150, 255, 230), riseAfter = 4, regen = true, aggroRange = 7 }, -- solo ataca si te acercas a golpearlo
			Gemelo = { label = "Gemelo de Eco", maxHealth = 100, profile = "gemelo", body = Color3.fromRGB(34, 86, 78), legs = Color3.fromRGB(18, 46, 42), glow = Color3.fromRGB(90, 255, 200), riseAfter = 20, linked = true },
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
			instructor = { pattern = { "Golpe" }, pause = 1.8, maxDelay = 0 }, -- tutorial: lento y siempre igual
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

	-- Recuperación de vida (decisión del hallazgo #10 de Codex, EXPERIMENTAL). Reemplaza la regeneración
	-- automática de Roblox (que curaba siempre, sin costo):
	--   PvE: "Respiro" — tras OutOfCombat s sin recibir ni hacer daño, se recupera RegenPerSecond por segundo.
	--        Punto seguro (aparición): cura entera al tocarlo.
	--   PvP: sin regeneración en combate (los duelos se juegan con la vida que hay).
	Recovery = {
		OutOfCombat = 6,
		RegenPerSecond = 10,
		SafeZoneRadius = 10, -- studs alrededor de una aparición (SpawnLocation) que curan entero
		-- Red de seguridad: si un jugador cae más de esto por debajo del último suelo firme que pisó
		-- (un fallo de la física, atravesar el suelo, salirse del mapa), vuelve a ese suelo sin morir
		SafetyDrop = 40,
	},

	-- Habilidades del Eco (EXPERIMENTAL, v2). Cada habilidad tiene SU tecla y un enfriamiento visible en la barra.
	-- Las básicas (Z, X, C) no cuestan nada: salen siempre que estén listas. La definitiva (V) gasta Resonancia,
	-- que se carga peleando bien (golpes, defensas y sinergias). Se lanzan al pulsar, sin quedarte quieto, y
	-- cortan tus golpes. El servidor decide alcance, daño y efectos (EcoService); el cliente solo los muestra.
	Eco = {
		-- Kits: cada Eco pone sus 4 habilidades en Z X C V (y alguna variante en el aire, con su PROPIO enfriamiento:
		-- Levante → subir → golpes en el aire → Descenso es un combo completo). Se elige en el menú o
		-- con las teclas 1-5. Al cambiar de Eco, las 4 teclas esperan SwapCooldown (corto: se puede cambiar a
		-- mitad de un combo). Los enfriamientos son por TECLA y se comparten entre Ecos, así que cambiar no da
		-- más habilidades seguidas: solo elige cuál sale en cada tecla.
		Default = "Viento",
		SwapCooldown = 0.6,
		PvP = false, -- habilidades contra jugadores: apagado hasta que resuelvan desvío, guardia y Contrapaso
		-- Liberación (Paso estando aturdido): sales del aturdimiento, apartas a los cercanos y quedas un instante
		-- inmune a otro aturdimiento. Cuesta Resonancia: es una decisión (gastar la definitiva o aguantar).
		Release = { cost = 40, cooldown = 6, immunity = 0.6, radius = 9, knockback = 45, stun = 0.6 },
		SlotOrder = { "Z", "X", "C", "V" },
		Gamepad = { Z = "Y", X = "L1", C = "L2", V = "R2" }, -- botón del mando de cada tecla
		Order = { "Viento", "Agua", "Oscuridad", "Fuego", "Trueno" },
		Kits = {
			-- Control y combos aéreos
			Viento = {
				name = "Eco del Viento",
				role = "Control y combos aéreos",
				reacts = "Sobre un enemigo ardiendo: TORMENTA ÍGNEA",
				color = Color3.fromRGB(150, 255, 230),
				slots = { Z = "Cuchilla", X = "Ciclon", C = "Levante", V = "Tempestad" },
				air = { C = "Descenso" },
			},
			-- Fluir, atrapar y sostener la vida
			Agua = {
				name = "Eco del Agua",
				role = "Atrapar, arrastrar y curarse",
				reacts = "Moja 4 s · sobre uno cargado: CONDUCCIÓN",
				color = Color3.fromRGB(80, 175, 255),
				slots = { Z = "Burbuja", X = "Oleaje", C = "Geiser", V = "Diluvio" },
			},
			-- Asesino: saltos de sombra y marcas
			Oscuridad = {
				name = "Eco de la Oscuridad",
				role = "Saltos de sombra y marcas",
				reacts = "Sobre un enemigo cargado: PULSO UMBRÍO",
				color = Color3.fromRGB(175, 95, 255),
				slots = { Z = "PasoSombrio", X = "Daga", C = "Fauces", V = "Eclipse" },
			},
			-- Daño sostenido y explosiones
			Fuego = {
				name = "Eco del Fuego Infernal",
				role = "Explosiones y quemaduras",
				reacts = "Quema · sobre uno mojado: VAPOR",
				color = Color3.fromRGB(255, 110, 40),
				slots = { Z = "BolaInfernal", X = "EstelaArdiente", C = "PunoVolcanico", V = "Infierno" },
				air = { C = "Meteoro" },
			},
			-- Velocidad, cadenas y torretas
			Trueno = {
				name = "Eco del Trueno",
				role = "Rayos en cadena y aturdir",
				reacts = "Carga 3 s · sobre uno mojado: ELECTROCUCIÓN",
				color = Color3.fromRGB(255, 235, 90),
				slots = { Z = "Rayo", X = "Relampago", C = "Pararrayos", V = "Juicio" },
			},
		},
		Skills = {
			-- Z · proyectil: una cuchilla de viento que vuela recto hacia donde apuntas, atraviesa enemigos (cada uno
			-- recibe un corte) y se detiene en las paredes. Aturde un instante e interrumpe preparaciones.
			-- En el aire puede apuntar hacia abajo y te sostiene un instante (airStall).
			Cuchilla = { slot = "Z", retreat = true, label = "Cuchilla", desc = "Corte de viento a distancia que atraviesa enemigos.", cooldown = 3, damage = 9, speed = 120, range = 60, radius = 2.5, knockback = 14, knockUp = 0, stun = 0.45, maxPitch = 50, airMaxPitch = 75, airStall = 0.25 },
			-- X · atrae a los cercanos hasta tu frente y los aturde. En el aire: los sube hasta ti y los deja flotando.
			Ciclon = { slot = "X", label = "Ciclón", desc = "Atrae a los cercanos hasta tu frente. En el aire, los sube contigo.", cooldown = 6, damage = 7, radius = 12, pullTo = 3.5, airHeight = 14, stun = 0.9, airStun = 1.2, airSuspend = 0.7 },
			-- C · columna que lanza al aire (≈10 studs). Pulsar C otra vez enseguida: Ascenso (subes tras el lanzado).
			Levante = { slot = "C", label = "Levante", desc = "Columna que lanza al aire. C otra vez: subes tras él.", cooldown = 5, damage = 8, range = 8, hitboxSize = Vector3.new(7, 8, 8), knockUp = 68, stun = 1.1, suspend = 0.6, juggle = 1.8, recastWindow = 1.2 },
			-- C en el aire · picada; al aterrizar, onda que rebota a los enemigos hacia arriba. Antes arrastra consigo a
			-- los enemigos que flotan cerca (los estampa contra el suelo).
			Descenso = { slot = "C", air = true, label = "Descenso", desc = "En el aire: picada que rebota a los enemigos hacia arriba.", cooldown = 5, damage = 11, radius = 9, knockback = 25, knockUp = 34, stun = 0.7, window = 1.5, plungeSpeed = 90, minHeight = 1.6, spikeRadius = 9, juggle = 1.0 }, -- minHeight: pies sobre el suelo (el cliente pide 2,2)
			-- V · definitiva: un tornado frente a ti que atrae, sostiene y golpea a todos los de adentro; al terminar
			-- estalla y los lanza. Mientras dura puedes moverte y seguir golpeando.
			Tempestad = { slot = "V", label = "Tempestad", desc = "Tornado que atrapa y golpea a los de dentro; al final estalla.", cooldown = 15, cost = 60, distance = 7, radius = 11, duration = 2.2, tick = 0.25, tickDamage = 2.5, holdHeight = 3, finalDamage = 12, finalKnockUp = 60, finalKnockback = 40, stun = 0.45 },

			-- ---------- Agua ----------
			-- Z · burbuja lenta: atrapa al primer enemigo y lo sube flotando dentro (combo aéreo)
			Burbuja = { slot = "Z", retreat = true, label = "Burbuja", desc = "Burbuja lenta que atrapa al primero y lo eleva.", cooldown = 4, damage = 6, speed = 70, range = 45, radius = 2.2, lift = 4, trap = 1.3, stun = 1.4, maxPitch = 40, airMaxPitch = 70 },
			-- X · surfeas sobre una ola: arrastras a los del camino y los sueltas al final
			Oleaje = { slot = "X", label = "Oleaje", desc = "Surfeas una ola y arrastras a los del camino.", cooldown = 6, damage = 8, distance = 16, duration = 0.32, width = 4.5, carry = 2.5, stun = 0.6, knockUp = 14 },
			-- C · géiser en el punto apuntado: aviso y erupción que lanza
			Geiser = { slot = "C", label = "Géiser", desc = "Géiser donde apuntas: tras un aviso, lanza al aire.", cooldown = 6, damage = 10, range = 18, radius = 5, delay = 0.45, knockUp = 62, stun = 1.0, suspend = 0.5, juggle = 1.6 },
			-- V · gran ola frontal que barre y empuja, y lluvia que te cura
			Diluvio = { slot = "V", label = "Diluvio", desc = "Gran ola que barre al frente y lluvia que te cura.", cooldown = 15, cost = 60, damage = 18, length = 22, width = 11, delay = 0.3, knockback = 70, knockUp = 16, stun = 0.8, heal = 32, healTime = 4 },

			-- ---------- Oscuridad ----------
			-- Z · salto de sombra (nunca atraviesa paredes): cortas a quien cruzas; Z otra vez: vuelves a tu sombra
			PasoSombrio = { slot = "Z", label = "Paso Sombrío", desc = "Saltas por la sombra cortando al pasar. Z otra vez: vuelves.", cooldown = 5, damage = 5, distance = 16, duration = 0.12, width = 3.5, stun = 0.4, recastWindow = 2.5, returnMax = 34 },
			-- X · daga que marca 4 s: golpear al marcado lo detona (daño extra) y recarga el Paso Sombrío
			Daga = { slot = "X", retreat = true, label = "Daga Marcada", desc = "Marca 4 s. Golpear al marcado lo detona y recarga Z.", cooldown = 5, damage = 6, speed = 140, range = 40, radius = 1.6, mark = 4, detonate = 12, stun = 0.3, maxPitch = 40, airMaxPitch = 70 },
			-- C · fauces de sombra en un cono al frente: inmovilizan y bajan a los que flotan
			Fauces = { slot = "C", label = "Fauces", desc = "Cono de sombra que inmoviliza y baja a los que flotan.", cooldown = 6, damage = 9, range = 11, angle = 50, stun = 1.3 },
			-- V · forma sombría: los ataques te atraviesan, corres más y cada golpe suma un corte; estalla al final
			Eclipse = { slot = "V", label = "Eclipse", desc = "Forma sombría: te atraviesan, corres más y cortas extra.", cooldown = 16, cost = 60, duration = 4, speedBoost = 1.3, cut = 4, burstDamage = 15, burstRadius = 9, burstStun = 0.8 },

			-- ---------- Fuego infernal ----------
			-- Z · bola que explota al chocar y deja el suelo ardiendo
			BolaInfernal = { slot = "Z", retreat = true, label = "Bola Infernal", desc = "Bola que explota al chocar y deja el suelo ardiendo.", cooldown = 4, damage = 10, speed = 90, range = 50, radius = 2, blast = 6, burn = 3, groundTime = 2, groundRadius = 5, knockback = 30, knockUp = 10, stun = 0.4, maxPitch = 40, airMaxPitch = 75 },
			-- X · Paso de fuego que deja un rastro ardiente
			EstelaArdiente = { slot = "X", label = "Estela Ardiente", desc = "Paso de fuego que deja un rastro que quema.", cooldown = 6, damage = 6, distance = 14, duration = 0.24, width = 3.5, trailTime = 2.5, burn = 2, stun = 0.3 },
			-- C · embestida corta y puñetazo que explota
			PunoVolcanico = { slot = "C", label = "Puño Volcánico", desc = "Embestida y puñetazo que explota y empuja lejos.", cooldown = 6, damage = 14, lunge = 7, duration = 0.16, range = 6, hitboxSize = Vector3.new(7, 6, 7), knockback = 75, knockUp = 20, burn = 3, stun = 0.7 },
			-- C en el aire · picada en diagonal hacia donde apuntas; cráter ardiente
			Meteoro = { slot = "C", air = true, label = "Meteoro", desc = "En el aire: picada en diagonal que deja un cráter ardiente.", cooldown = 6, damage = 16, speed = 110, radius = 9, knockUp = 30, burn = 3, craterTime = 3, craterRadius = 7, stun = 0.7, window = 1.5, minHeight = 1.6, maxPitch = 80 },
			-- V · anillo de fuego: quema a los de adentro; tus golpes arden
			Infierno = { slot = "V", label = "Infierno", desc = "Anillo que quema a los de dentro; tus golpes arden.", cooldown = 16, cost = 60, duration = 4.5, radius = 10, tick = 0.5, tickDamage = 4, extra = 3 },

			-- ---------- Trueno ----------
			-- Z · rayo instantáneo al enemigo apuntado que salta a 2 más cercanos
			Rayo = { slot = "Z", retreat = true, label = "Rayo", desc = "Rayo instantáneo que salta a 2 enemigos más.", cooldown = 3, damage = 8, range = 26, cone = 30, jumps = 2, jumpRange = 13, falloff = 0.75, stun = 0.5 },
			-- X · te vuelves rayo y cruzas: daña y aturde a todos en el camino
			Relampago = { slot = "X", label = "Relámpago", desc = "Cruzas como un rayo y aturdes a los del camino.", cooldown = 6, damage = 9, distance = 16, duration = 0.12, width = 3.5, stun = 0.8 },
			-- C · tótem que electrocuta al más cercano cada medio segundo
			Pararrayos = { slot = "C", label = "Pararrayos", desc = "Tótem que electrocuta al enemigo más cercano.", cooldown = 8, range = 14, duration = 4, tick = 0.5, radius = 9, damage = 3, stun = 0.3 },
			-- V · rayos que caen sobre los enemigos a tu alrededor
			Juicio = { slot = "V", label = "Juicio", desc = "Rayos que caen sobre los enemigos a tu alrededor.", cooldown = 15, cost = 60, strikes = 6, interval = 0.25, radius = 18, damage = 8, knockUp = 25, stun = 0.6 },
		},
		-- Estados: quemadura (daño cada medio segundo) y marca de la Daga
		Burn = { tick = 0.5, damage = 2 },
		-- Combos con nombre: una habilidad que conecta poco después de otra técnica en el MISMO enemigo.
		-- `first` puede ser un golpe del combo (Jab, Cross, Patada, Fuerte) o una habilidad.
		Synergies = {
			{ first = "Ciclon", next = "Cuchilla", window = 2, name = "REMOLINO CORTANTE", damage = 1.5 },
			{ first = "Cuchilla", next = "Ciclon", window = 2, name = "VENDAVAL", stun = 1.5 },
			{ first = "Patada", next = "Levante", window = 1.2, name = "ALZADA", damage = 1.25, launch = 1.15 },
			{ first = "Ciclon", next = "Levante", window = 2, name = "TROMBA", damage = 1.2, launch = 1.1 },
			{ first = "Levante", next = "Descenso", window = 3, name = "CAÍDA DEL CIELO", damage = 1.6 },
			{ first = "Ciclon", next = "Tempestad", window = 2.5, name = "OJO DE LA TORMENTA", damage = 1.4 },
			-- Agua
			{ first = "Burbuja", next = "Geiser", window = 2, name = "MAREA ALTA", damage = 1.3, launch = 1.25 },
			{ first = "Oleaje", next = "Burbuja", window = 2, name = "RESACA", damage = 1.5 },
			{ first = "Geiser", next = "Oleaje", window = 2.5, name = "CASCADA", damage = 1.4 },
			-- Oscuridad
			{ first = "Daga", next = "PasoSombrio", window = 4, name = "EMBOSCADA", damage = 2.5 },
			{ first = "Fauces", next = "Daga", window = 2, name = "PRESA", damage = 1.5 },
			{ first = "PasoSombrio", next = "Fauces", window = 2, name = "SOMBRA VORAZ", stun = 1.5, damage = 1.2 },
			-- Fuego
			{ first = "BolaInfernal", next = "PunoVolcanico", window = 2, name = "ESTALLIDO", damage = 1.5 },
			{ first = "EstelaArdiente", next = "BolaInfernal", window = 2.5, name = "LLAMARADA", damage = 1.4 },
			{ first = "PunoVolcanico", next = "Meteoro", window = 3, name = "CAÍDA ÍGNEA", damage = 1.4 },
			-- Trueno
			{ first = "Relampago", next = "Rayo", window = 2, name = "SOBRECARGA", damage = 1.5 },
			{ first = "Pararrayos", next = "Relampago", window = 2.5, name = "DESCARGA", stun = 1.5, damage = 1.2 },
			{ first = "Rayo", next = "Juicio", window = 2.5, name = "TORMENTA PERFECTA", damage = 1.3 },
		},
		-- Combos aéreos: un enemigo lanzado queda "en el aire" (juggle) y cada golpe que recibe así lo sostiene
		-- flotando un instante. Quien golpea en el aire también flota un instante (AirStall) para seguir el combo.
		Juggle = { HitSuspend = 0.4, HitStun = 0.5, HitKnockbackScale = 0.3, HitKnockUp = 3, AirStall = 0.3, MinHeight = 2 },
		GuardianStunScale = 0.5, -- el Guardián resiste: aturdimientos a la mitad...
		GuardianLaunchScale = 0.6, -- ...y lo lanzan más bajo
	},

	-- IDs de animaciones publicadas en Roblox (rbxassetid://...). Vacío = se usan las generadas
	-- por código (solo funcionan en Studio). Antes de publicar el juego hay que subirlas y ponerlas aquí.
	AnimationIds = {},
}

return CombatConfig
