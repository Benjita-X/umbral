# Registro de decisiones

## 2026-11-06 · Fase 1

| # | Decisión | Por qué |
|---|---|---|
| 1 | Código en archivos (`src/`) y un generador propio del `.rbxlx`, con convenciones de Rojo | Sin instalar programas extra; todo queda versionable y se puede pasar a Rojo después |
| 2 | Una sola fuente de configuración: `MovementConfig.luau` | Ajustar el movimiento sin buscar números por todo el código |
| 3 | Humanoid estándar de Roblox + `LinearVelocity` solo durante el Paso | El Humanoid ya frena y acelera al instante; el Paso necesita velocidad exacta y distancia medible |
| 4 | Sprint automático tras 0,4 s moviéndose, sin botón | Menos botones en el celular (diseño de 5 acciones) |
| 5 | El Paso deja al jugador directo en sprint | Conservar el impulso: que la velocidad dependa de encadenar bien |
| 6 | 2 cargas de Paso que se recargan de a una (0,8 s) | Movimiento explosivo sin poder spamearlo |
| 7 | Paso aéreo: 1 por salto y mantiene la altura | Cruzar brechas y reposicionarse en el aire, con límite claro |
| 8 | Coyote time (0,1 s) y búfer de salto (0,12 s) | El salto responde aunque la pulsación sea un poco temprana o tardía |
| 9 | Gravedad 230 y caída 1,35 veces más rápida | Saltos secos, sin sensación de flotar |
| 10 | Doble salto que redirige el impulso hacia el joystick | Cambiar de dirección en el aire (el "impulso aéreo" del diseño) |
| 11 | Shift es el Paso; el bloqueo del mouse con Shift queda desactivado | Evitar el choque con el atajo de Roblox |
| 12 | El botón PASO del celular se ubica junto al de salto, medido en pantalla | Cómodo para el pulgar en cualquier tamaño de teléfono |
| 13 | FOV dinámico: +6° en sprint y +8° de golpe al iniciar un Paso | Sentir la velocidad sin marear |
| 14 | En Fase 1 el cliente controla su movimiento | Así funciona Roblox por defecto; la validación del servidor llega en la Fase 4 |
| 15 | El Paso termina por **distancia** (con tope de tiempo ×1,5), no por tiempo | Medido por tiempo recorría 12,6-13 studs y menos a bajos FPS; por distancia recorre 14,0 a 30 y a 60 FPS: justo entre PC y celular |
| 16 | Pruebas automáticas con `StudioTestService` y un plugin local | Comprobar cada cambio en ~1 minuto sin depender de nadie mirando la pantalla |
| 17 | El plugin guarda la salida con `plugin:SetSetting` | Studio no escribe los `print` de los scripts en sus registros |
| 18 | Cada ejecución de pruebas lleva un identificador único | Evita leer resultados viejos de una ejecución anterior |

## 2026-11-06 · Fase 2 (combate corporal)

| # | Decisión | Por qué |
|---|---|---|
| 19 | Todo el combate sale de `CombatConfig.luau`, compartido por cliente y servidor | Un solo lugar para equilibrar; animaciones, detección y validación usan los mismos tiempos |
| 20 | Cada golpe: preparación → impacto → recuperación | Legible para el rival y con consecuencias para quien ataca |
| 21 | Pulsar = combo Jab → Directo → Patada; mantener = golpe fuerte con carga (sale solo al cargar del todo) | Respeta las 5 acciones: sin botón extra de golpe fuerte |
| 22 | Encadenar solo si el golpe **conecta**; fallar alarga la recuperación ×1,35 y no se cancela | Premia acertar, castiga lanzar golpes al aire |
| 23 | Hitstop (congelamiento de 0,05-0,11 s al conectar) | Es lo que hace que un golpe "pese" |
| 24 | Orientación asistida (cono de 75°, 12 studs) y acercamiento de hasta 3,5 studs, **iguales en todos los aparatos** | En celular y mando no se puede apuntar fino; orienta pero no acierta por ti |
| 25 | Paso y salto cancelan la recuperación, nunca la preparación ni el impacto; el Paso también cancela la carga (amague) | Fluidez tipo Rock Lee con reglas claras |
| 26 | El cliente detecta el golpe y muestra el impacto al instante; el **servidor valida y aplica el daño** | Respuesta inmediata sin que el cliente decida el daño |
| 27 | Validación: ataque válido, cuerpos vivos, distancia posible, sin repetidos, máx. 14 golpes/s | Bloquea golpes falsos (probado con golpes inventados, lejanos y repetidos) |
| 28 | Tolerancia al lag: si un golpe parece lejano, el servidor reintenta 0,35 s con la posición actualizada | Sin esto, golpear justo después de un Paso con lag se rechazaba |
| 29 | Animaciones generadas por código (`AnimationLibrary`) con `RegisterKeyframeSequence` | Sin subir assets ni inventar IDs; quedan sincronizadas con los tiempos. **Solo funcionan en Studio** (ver pendientes) |
| 30 | Articulaciones `AnimationConstraint` en modo **cinemático** (`Rig.MakeKinematic`) | Las articulaciones físicas de Roblox no alcanzaban la pose a tiempo; para un futuro ragdoll basta desactivarlo |
| 31 | Sonidos provisionales con los de Studio (`rbxasset://sounds/...`) afinados de tono | No hay sonidos de golpes incluidos; los definitivos se suben y se cambian en `EffectsController` |
| 32 | Vibración de cámara con `Humanoid.CameraOffset` y ajuste de accesibilidad (`Feedback.ScreenShake`) | No pelea con la cámara de Roblox y se puede apagar |
| 33 | Muñecos R15 que no mueren (estado Dead desactivado), se curan y vuelven a su sitio | Practicar combos sin interrupciones |
| 34 | Pruebas que no se pueden medir (ventana sin dibujar) quedan **omitidas** con motivo, no aprobadas | Un resultado honesto: nada pasa "en verde" sin medirse |

## Auditoría y consolidación de la Fase 3 (2026-11-06)
| # | Decisión | Por qué |
|---|---|---|
| 35 | Se integra `auditoria-fase3` en `main` con merge manual (sin commit automático), revisión archivo por archivo y pruebas antes del commit | No perder trabajo y no meter una rama sin conectar |
| 36 | Golpes juzgados **en su instante** con historial de posiciones, en vez de reintentar 0,35 s (reemplaza la #28) | Sin esperas fijas; espera acotada por cuadros |
| 37 | Retroceso temporal máximo `MaxRewind = 0,3 s` | Una conexión lenta no compra más ventana; ajustable |
| 38 | Confirmación de posición con margen `2,25 + velocidad × 0,04` (medido: con 1,5 se rechazaban golpes legítimos) contra **segmentos** observados (antes 4 studs fijos) | El margen fijo regalaba hasta ~4 studs de alcance a quien falsificara su posición |
| 39 | La posición observada de un jugador **no** se trata como prueba de legitimidad (la produce su cliente). Velocidades imposibles solo se **registran** | Honestidad técnica: sancionar exige datos de juego real y revisión humana |
| 40 | Remote `InicioAtaque`: el servidor valida la **secuencia** del combo y la ventana activa de cada golpe | El cliente ya no puede declarar el ataque que más daño hace (caso Nexus Battles D) |
| 41 | Límites de tasa: 45 posiciones/s, 30 defensas/s, 12 inicios/s, 14 golpes/s | Inundar remotes no da ventaja ni consume el servidor |
| 42 | Paso extra con Resonancia: enfriamiento también **en el servidor** | La regla vale aunque el cliente la ignore |
| 43 | La recarga de Pasos **sigue** corriendo durante el Paso | Es el valor medido (0,8 s por carga). No se encontró un problema concreto que justifique cambiarlo |
| 44 | Contrapaso: dirección medida respecto al vector **atacante → defensor** | El punto de impacto adelantado daba un vector diminuto de cerca (bug de la rama) |
| 45 | El compañero publica `Ataque` y `FaseFin` **antes** que `FaseInicio` y `Estado` | Quien escucha un cambio leía tiempos de la fase anterior |
| 46 | Las pruebas se separan en reglas, integración, adversariales, rendimiento y humanas | Un bot que conoce el instante del impacto no demuestra legibilidad humana |
| 47 | La acción de pruebas `teletransporte` vive solo en `tests/server` | Nunca existe en el lugar de desarrollo ni en uno publicable |

## Sensación del combate (2026-11-06, pedido del jugador)
| # | Decisión | Por qué |
|---|---|---|
| 48 | Animaciones: guardia de pelea como base, curva que **acelera** hacia el impacto (antes frenaba al llegar), pequeño exceso (×1,08) con retroceso y vuelta suave | Los golpes se veían blandos y robóticos: partían con los brazos colgando y frenaban justo en el impacto |
| 49 | Movilidad al atacar: 80 % de velocidad (antes 35 %), 60 % cargando (antes 30 %); el Paso y el salto solo se bloquean en el impacto (0,06 s) y cancelan la preparación; se puede girar en la recuperación | "Moverse mientras atacas": el personaje se sentía pesado |
| 50 | El avance de un golpe llega a mitad de la ventana activa; si el tramo es largo (Contraataque tras Contrapaso) la preparación se alarga lo justo, como mucho a 120 studs/s | El Contraataque llegaba al alcance justo cuando la ventana se cerraba y salía al aire |
| 51 | Servidor: entre dos inicios se exige solo la preparación del anterior (margen 0,02 s, horas del cliente) | Permite cancelar con Paso y volver a atacar sin rechazos; las ráfagas imposibles se siguen rechazando |
| 52 | Muñecos y enemigos sin estados FallingDown ni Ragdoll | Un compañero tumbado tras chocar con el jugador dejaba de atacar |
| 53 | Guardián de la Grieta: ojos, cristales y núcleo de neón soldados (sin masa ni colisión) | Que se lea como enemigo; no cambia la Hurtbox estándar |

## Choques y caídas (2026-11-07, reporte del jugador: un Paso contra una pared lo hundió en el suelo)
| # | Decisión | Por qué |
|---|---|---|
| 66 | Fuerza de las restricciones de velocidad 4e5 (antes 1e7) en jugador, enemigos y empujes | Con 1e7 la física resolvía los choques metiendo al personaje en la pared o hundiéndolo en el suelo |
| 67 | El Paso, los avances de golpes, el empuje del salto de pared, la carrera por la pared y la salida del Paso se detienen al tocar una pared (esfera del ancho del cuerpo) | Antes seguían empujando hasta 0,27 s contra el muro |
| 68 | Los enemigos acortan su lanzamiento y los empujes se acortan si hay una pared | No quedan metidos en muros |
| 69 | Suelos de 8 studs de grosor (laboratorio y Grieta) | Ni una caída a 140 studs/s ni la picada del Descenso los atraviesan, aun a 30 FPS |
| 70 | Red de seguridad (`PersonajeService`): caer 40 studs por debajo del último suelo firme o quedar 1 s metido en una pieza sólida devuelve al último suelo firme, sin morir | Ningún fallo de la física debe matar al jugador |
| 71 | El personaje del jugador no tropieza (FallingDown y Ragdoll desactivados) | Chocar fuerte lo tumbaba |
| 72 | Si un personaje reaparece sin ropa ni accesorios, el servidor le vuelve a aplicar la apariencia de su cuenta | El jugador reapareció sin su avatar (Roblox no terminó de cargarlo) |

## Habilidades v2, armas y movimiento Sekiro (2026-11-07, pedido del jugador tras probar el prototipo)
El jugador encontró el sistema de habilidades "básico, raro y que a veces no salía", y pidió un sistema al estilo de
los juegos de peleas de Roblox (una tecla por habilidad, combos combinando habilidades), mínimo 20 poderes, kits de
viento, agua, oscuridad y fuego infernal, armas (espada), patadas y movimiento con sensación de Sekiro / Elden Ring.
Diseño completo: [HABILIDADES-V2.md](HABILIDADES-V2.md). Rama `experimental/habilidades-v2`.

| # | Decisión | Por qué |
|---|---|---|
| 73 | Una tecla por habilidad (Z X C V; mando Y L1 L2 R2; un botón por habilidad en el celular) que sale AL PULSAR | El botón único contextual (tocar/mantener/tras Paso/aire) sacaba otra cosa o nada |
| 74 | Las básicas (Z, X, C) no cuestan Resonancia; solo la definitiva (V) | Costar Resonancia desde 0 hacía que "a veces no saliera" sin aviso claro |
| 75 | Barra de habilidades con tecla, nombre, enfriamiento con segundos, destello al quedar lista y sacudida roja si no está lista | El jugador no sabía por qué no salía |
| 76 | Se lanzan sin quedarte quieto (animación solo del tronco) y cortan la preparación y la recuperación de tus golpes; el combo no se reinicia | "Que se puedan tirar rápido y moverse mientras se tiran" |
| 77 | Enfriamiento por tecla medido entre las horas validadas de los pedidos (margen 0,05 s); reserva antes de cualquier espera | La variación de la red no rechaza un uso legítimo; dos pedidos en el mismo cuadro no salen dos veces (Codex #1) |
| 78 | Suelo/aire por la altura de los pies con márgenes que se solapan (el cliente pide la variante aérea a 2,2; el servidor acepta aire desde 1 y suelo hasta 3) | Antes cliente y servidor discrepaban en el límite y la habilidad se rechazaba en silencio |
| 79 | 5 Ecos intercambiables (teclas 1-5 o menú), 4 habilidades cada uno; cambiar de Eco deja las teclas 2 s en enfriamiento | 20+ poderes sin 20 teclas; no se encadenan definitivas cambiando |
| 80 | Proyectiles simulados por el servidor desde la hora del pedido (primero lo ya recorrido, con el historial; luego cuadro a cuadro) y frenados por las paredes | Justo con la latencia y sin atravesar paredes |
| 81 | Arrastrar (atraer, subir, estampar) y sostener en el aire con restricciones propias, con barrido de esfera antes de mover | Nada mete a un enemigo dentro de una pared |
| 82 | Combos aéreos: un enemigo lanzado queda "en el aire"; cada golpe lo sostiene flotando; quien golpea en el aire flota un instante | Los combos de los juegos del género viven en el aire |
| 83 | Sinergias con nombre (14) entre técnicas en el mismo enemigo: más daño/lanzamiento/aturdimiento y Resonancia | "Combos combinando habilidades" con premio visible |
| 84 | Quemadura y cortes extra son daño de estado: sin física, sin interrumpir, no cuentan para sinergias | Si no, cada tic interrumpía al enemigo y rompía los combos |
| 85 | Armas: Q cambia Puños ↔ Espada; el servidor valida que cada golpe sea del arma que llevas | Variedad de combate sin abrir trampas de daño |
| 86 | Golpe tras el Paso (exige un Paso registrado) y golpe en picada (exige altura en la física observada, con ventana corta) | Patadas nuevas validadas por el servidor |
| 87 | Gancho (E) a orbes del mapa y a enemigos; al llegar a un orbe, impulso y saltos recargados; a un enemigo, abre el golpe tras el Paso | Movimiento con sensación de Sekiro |
| 88 | Postura enemiga: desvíos y golpes la llenan; llena = QUEBRADO 2,6 s; atacar cerca = Golpe de Gracia (35 % de la vida, Guardián 22 %) | El ciclo desviar → quebrar → rematar de los juegos de duelo con espada |
| 89 | Las embestidas de habilidad frenan en seco al terminar | El impulso las alargaba al doble de lo previsto |
| 90 | Cámara fija en PC (Ctrl): ratón al centro con mira, cámara sobre el hombro, el personaje mira hacia la cámara; golpes y habilidades salen hacia la mira; el menú suelta el ratón | "Muy incómodo" jugar con la cámara libre; es lo habitual en los juegos de pelea |
| 91 | Fijar enemigo (R / R3): cámara que lo sigue (Scriptable mientras dura), el personaje lo encara, tirón del ratón para cambiar; se suelta si cae, se aleja o queda tapado | Comodidad de los juegos de acción con espada en peleas movidas |
| 92 | Polvo y sacudida al caer desde alto, silueta fantasma en el Paso, golpe de FOV en gancho y definitivas | Que el movimiento "se sienta" |
| 93 | El golpe tras el Paso también vale al llegar con el gancho (el servidor registra la hora del gancho); la picada usa la posición informada con el inicio, comprobada contra lo observado | La física replicada llega con décimas de retraso: el servidor veía al jugador todavía en el suelo |
| 94 | Más vida a los enemigos de la Grieta: comunes ×1,4 (Latido 110, Centinela 125, Acechador 85, Gemelos 100) y Guardián 400 | Con 20 habilidades, sinergias y Golpe de Gracia caían en segundos |
| 95 | Mayúsculas con tildes y eñe en la interfaz (`Shared/Texto`); el círculo del gancho solo sobre enemigos a más de 14 studs | Revisión visual: "CICLóN"; el círculo estorbaba en pleno combate |

## Pendiente de decidir
- ¿La experiencia será de tu cuenta o de un grupo? (importa si después entran socios)
- **Antes de publicar:** subir las animaciones a Roblox (o reemplazarlas por otras de un animador) y poner sus IDs en `CombatConfig.AnimationIds`; las generadas por código no funcionan fuera de Studio.
- **Fase 4:** ¿autoridad del movimiento en el servidor (Pasos validados contra cargas, o física del servidor) según lo que muestren las pruebas de PvP real?
- **Fase 4:** avisar también el inicio de la carga del golpe fuerte para cerrar la carga declarada por el cliente.
- Sonidos definitivos de golpes (subir audio propio o con licencia).
