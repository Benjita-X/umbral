# Arquitectura de UMBRAL (Fases 1-3 consolidadas)

Actualizado: 2026-11-06. Describe el código **real** de `main` después de la consolidación.

## 1. Piezas y responsabilidades

### Compartido (`src/shared` → `ReplicatedStorage.Shared`)
| Módulo | Responsabilidad | Lo usan |
|---|---|---|
| `Config/MovementConfig` | Todos los números del movimiento (carrera, Paso, saltos, cámara) | Cliente, `construir.mjs` |
| `Config/CombatConfig` | Todos los números del combate: ataques del jugador, defensa, Resonancia, enemigo, red, validación | Cliente y servidor (una sola tabla: no hay tablas contradictorias) |
| `Combat/MoveSchema` | Valida que cada movimiento tenga startup/active/recovery/daño/postura/forma/defensas coherentes | Pruebas (`Auditoria`) |
| `Combat/Hurtbox` | Caja estándar 3 × 5,5 × 2,4 studs en el `HumanoidRootPart`; solapamiento de cajas orientadas (SAT 2D + altura); áreas de barrido | Cliente (detección) y servidor (validación): juzgan igual |
| `Combat/AnimationLibrary` | Animaciones provisionales por código (`RegisterKeyframeSequence`, **solo Studio**) | Cliente |
| `Combat/Rig` | Articulaciones en modo cinemático (poses exactas) | Cliente y servidor (muñecos) |

### Cliente (`src/client` → `StarterPlayerScripts`)
| Módulo | Responsabilidad | Autoridad |
|---|---|---|
| `ClientBootstrap` | Arranca todo en orden | — |
| `InputController` | Teclado, mando y táctil → 5 acciones (Atacar, Defender, Paso, Saltar, Eco*) | Local |
| `MovementController` | Carrera, sprint, Paso (2 cargas), saltos, gravedad extra, coyote, búfer | **Cliente** (dueño de la física de su personaje). El servidor solo vigila velocidades (ver §4) |
| `CombatController` | Combo, golpe fuerte, guardia, desvío, aturdimiento visual, Contraataque, Paso extra con Resonancia | Predice y muestra; **el servidor decide** daño, defensa y Resonancia |
| `PositionReporter` | Manda posición + hora del servidor 20 veces/s (`UnreliableRemoteEvent`) y una muestra en cada golpe/defensa | Dato del cliente: nunca es autoridad por sí solo |
| `EnemyController` | Anima y avisa los ataques del compañero (color + pose + sonido + anillo del barrido); congela la pose en los retrasos; reinicia en el amague | Solo visual |
| `CameraController`, `EffectsController`, `CombatHUD`, `VitalsHUD`, `DebugHUD` | Cámara, efectos, avisos, barras, depuración | Solo visual |

\* "Eco" está reservado para la Fase 7; hoy no hace nada.

### Servidor (`src/server` → `ServerScriptService`)
| Módulo | Responsabilidad |
|---|---|
| `ServerBootstrap` | Gravedad y arranque: Damage → Position → (inyecta Position en Defense) → Defense → Resonance → Dummy → Sparring |
| `DamageService` | Valida **inicios de ataque** (secuencia legal) y **golpes** (inicio aceptado, ventana activa, posición confirmada, alcance con Hurtbox, repetidos, ritmo); aplica daño, empuje y Contraataque |
| `PositionService` | Historial observado (cada cuadro) e informado (del cliente); confirma posiciones; retroceso acotado; vigila velocidades imposibles |
| `DefenseService` | Pulsaciones de Defender, guardia, Pasos (con hora validada), postura, aturdimiento, ventana de Contraataque, "expuesto" tras desvío fallido |
| `ResonanceService` | Ganar (con topes por segundo, por rival y por repetición), gastar (Paso extra, con enfriamiento en el servidor), apagarse |
| `DummyService` | Muñecos R15 que no mueren, se curan y vuelven a su sitio; base del compañero |
| `SparringService` | Compañero de combate: perfiles, patrón, retrasos, amague; **juez de la defensa** contra sus ataques |

## 2. Mapa de eventos cliente ↔ servidor

| Remote (en `ReplicatedStorage.Remotes`) | Tipo | Dirección | Contenido | Validación en el servidor |
|---|---|---|---|---|
| `InicioAtaque` | RemoteEvent | C → S | `seq, ataque, t` | ataque existe, hora válida, `seq` creciente, ≤ 12/s, no aturdido, **secuencia legal** (Jab → Directo → Patada; Jab siempre; no antes de que el anterior pudiera cancelarse; el fuerte necesita tiempo de mantener; carga máxima posible) |
| `SolicitudGolpe` | RemoteEvent | C → S | `{attack, seq, target, charge, t, pos, look}` | forma, objetivo con etiqueta `Objetivo`, no aturdido, hora válida, **inicio aceptado del mismo ataque**, `t` dentro de su ventana activa, posición confirmada, alcance (Hurtbox + 1,5), no repetido, ≤ 14 golpes/s, carga ≤ la posible |
| `GolpeConfirmado` | RemoteEvent | S → todos | atacante, objetivo, ataque, daño, vida, Contraataque | — |
| `Defensa` | RemoteEvent | C → S | `acción, t, dir, pos, look` (`defender_inicio`, `defender_fin`, `paso`) | ≤ 30/s, hora válida (si no, se usa la actual: sin ventaja), duplicados ignorados, mensajes desordenados no abren ventana |
| `ResultadoDefensa` | RemoteEvent | S → todos | jugador, enemigo, ataque, id, resultado, daño, expuesto | — |
| `GastarResonancia` | RemoteEvent | C → S | `"paso"` | alcanza la Resonancia y pasó `ExtraDashCooldown` desde el anterior |
| `Posicion` | **Unreliable**RemoteEvent | C → S | `t, pos, look` (20/s) | ≤ 45/s, hora válida, velocidad posible respecto a las vecinas, duplicados ignorados |
| `UmbralPruebas` | RemoteEvent | C → S | acciones de prueba | **Solo existe en `build/UMBRAL-Pruebas.rbxlx`** (`tests/server`), nunca en el lugar de desarrollo ni en uno publicable |

**Atributos replicados**
- Jugador: `Resonancia`, `Postura`, `AturdidoHasta`, `ContraataqueHasta` (hora del servidor). Contadores de auditoría: `GolpesRechazados`, `UltimoRechazo`, `DefensasRechazadas`, `DefensasExcedidas`, `PosicionesRechazadas`, `PosicionesExcedidas`, `MovimientoSospechoso`, `VelocidadObservadaImposible`, `GastosRechazados`.
- Compañero: `Estado`, `Ataque`, `FaseInicio`, `FaseFin`, `AtaqueId`, `Perfil`, `Patron`, `Retraso`.
  > `FaseInicio`/`FaseFin` son legibles por cualquier cliente (también uno modificado). Eso está bien: **ningún sistema de seguridad depende de que sean secretos**. Sirven para sincronizar la animación; el juicio usa los tiempos del servidor.

## 3. Flujo de un ataque
1. Pulsar **Atacar** → `InputController` → `CombatController.startAttack(nombre)`.
2. El cliente suma `seq`, **avisa `InicioAtaque(seq, nombre, hora)`**, anima y empieza preparación → impacto → recuperación (tiempos de `CombatConfig.Attacks`).
3. En la ventana activa busca rivales con la `Hurtbox` estándar. Si conecta: hitstop y efectos **predictivos** (el número de daño definitivo llega con `GolpeConfirmado`).
4. Manda `SolicitudGolpe` con la hora y su posición en ese instante.
5. `DamageService`: comprobaciones baratas primero (forma, objetivo, aturdido, hora); después, en un hilo con espera **acotada por cuadros** (no un tiempo fijo):
   - espera el `InicioAtaque` de ese `seq` (≤ 0,3 s) y comprueba que el golpe caiga en su ventana activa;
   - confirma la posición del atacante en `t` (`PositionService.ConfirmedAt`);
   - toma al objetivo como lo veía el atacante (`ObservedAt(t − latencia de ida)`);
   - comprueba el alcance con la Hurtbox + 1,5 studs; repetidos y ritmo;
   - aplica daño (×1,3 si había Contraataque), Resonancia (solo rivales que pelean), empuje y `GolpeConfirmado`.

## 4. Flujo de una defensa (contra el compañero)
1. `SparringService` pone `Preparando` con `FaseInicio/FaseFin` (incluye el retraso). Deja de girar `TrackingStop` antes del impacto: ahí el ataque queda **comprometido** (dirección fija).
2. El cliente lo anima y avisa. El jugador pulsa Defender / da un Paso / salta → `Defensa(acción, hora, dir, pos)`.
3. En el impacto, por cada jugador, en su hilo: espera (acotada) a que lleguen sus defensas; toma su posición **confirmada** en el impacto que vio (`impacto + latencia de ida`, con tope) y al comprometerse el ataque.
4. Orden de decisión: **desvío** (el Pesado solo con perfecto) → **Contrapaso** → **salir del área / saltar el barrido** → **guardia** de frente (salvo "expuesto") → **golpe**.
5. Consecuencias: Resonancia, Contraataque, aturdimiento del rival (perfecto), postura, ruptura, aturdimiento propio.

## 5. Contrapaso
- Paso dado como mucho `ContrapasoWindow` (0,25 s) antes del impacto que vio el jugador, **estando amenazado** (dentro del área al comprometerse el ataque, o al empezar el Paso).
- Dirección del Paso entre 45° y 135° respecto al vector **atacante → defensor** (la amenaza), no respecto a la cámara.
- Solo contra ataques con `contrapaso = true`. El **Barrido** no lo admite (área alrededor): el Paso que sale del área cuenta como esquiva, sin Contraataque.
- Respuestas del atacante: el Pesado se lanza 9 studs (alejarse antes de tiempo no basta); los retrasos y el amague castigan el Contrapaso anticipado; el barrido castiga el Paso lateral. En PvP (Fase 4) el atacante también podrá esperar el Paso y castigar la recuperación.

## 6. Compensación de latencia (resumen; detalle en `AUDITORIA-FASE3.md`)
- Retroceso máximo: `min(ping, MaxRewind = 0,3 s)` + margen 0,15 s. Más ping no compra más ventana.
- Posición informada confirmada contra la trayectoria observada con margen **2,25 studs + velocidad × 0,04** (quieto 2,25; en un Paso ≈ 5,4), por distancia a segmentos.
- Límite: la física de un jugador la produce su cliente. La confirmación da coherencia, no legitimidad; los movimientos imposibles se **registran** (`VelocidadObservadaImposible`) para revisión.

## 7. Herramientas
| Archivo | Qué hace |
|---|---|
| `tools/construir.mjs` | Genera `build/UMBRAL-Desarrollo.rbxlx` desde `src/` y `tools/mapa.mjs`. Con `--pruebas` además `UMBRAL-Pruebas.rbxlx` (agrega `tests/`). Con `--instalar-plugin` instala el plugin de pruebas |
| `tools/mapa.mjs` | El mapa gris (pistas, Dojo, Ring) |
| `tools/ejecutar-pruebas.ps1` | Construye, abre Studio, espera los resultados del plugin y cierra **solo** la ventana que abrió |
| `tools/plugin/UmbralPruebas.server.luau` | Plugin local: solo actúa si existe `ReplicatedStorage.UmbralPruebasAutomaticas` (lugar de pruebas). Entra en Play, guarda los resultados con `plugin:SetSetting`. No toca otros lugares |

## 8. Recursos que se limpian
| Recurso | Dónde se limpia |
|---|---|
| Registros por jugador (golpes, inicios, defensas, posiciones, tasa, Resonancia) | `Players.PlayerRemoving` en cada servicio |
| Historial observado de modelos | Tabla de claves débiles; un modelo sin padre no se muestrea |
| Inicios y objetivos por `seq` | Se borran los de hace más de 10-12 secuencias |
| Avisos del enemigo (Highlight, anillo) | `EnemyController.cleanup` en cada cambio de estado y al salir el modelo |
| Conexiones de las pruebas | Cada suite desconecta las suyas al terminar |
