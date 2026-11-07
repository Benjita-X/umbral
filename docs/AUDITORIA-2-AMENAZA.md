# Segunda auditoría crítica y diseño de Amenaza Asimétrica

Fecha: 2026-11-07. Estado: **documento de diseño**. Nada de "Amenaza Asimétrica" ni del "Instinto del Último Recuerdo" está implementado. Los enemigos Latido, Centinela y Gemelos viven solo en la rama `experimental/enemigos-grieta`.

Leyenda: **APROBADO** (probado y aceptado) · **EXPERIMENTAL** (implementado en una rama aislada) · **HIPÓTESIS** (diseño sin probar) · **DESCARTADO**.

---

## A. Estado real del proyecto y sus ramas
| Rama / referencia | Qué contiene | Estado |
|---|---|---|
| `main` (`7dde3d8`) | Fases 1-3 consolidadas, auditoría integrada, La Grieta jugable, sensación del combate. **95/95 pruebas** (ejecución del 2026-11-07) | Estable |
| `experimental/enemigos-grieta` | Latido, Centinela, Gemelos, Desvío Reflejado, modificador de daño en `DamageService` | EXPERIMENTAL |
| `auditoria-fase3` | Rama original de la auditoría, ya integrada en `main` | Histórica (no borrar: respaldo) |
| `respaldo/main-pre-consolidacion`, `respaldo/auditoria-fase3-wip` | Etiquetas del estado anterior | Respaldo |

**Sobre "las cuatro pruebas de defensa sin evidencia":** hay evidencia de ejecución (registros de Studio de cada ronda; la línea base dio 79/82 y la última 95/95). **Pero** todas esas pruebas las escribí yo, así que demuestran que el código cumple **mis** criterios, no que el combate sea justo o divertido. La Fase 3 queda **PROBADA, no VALIDADA**: falta que personas la jueguen ([PRUEBAS-FASE3.md](PRUEBAS-FASE3.md)).

## B. Auditoría crítica de mis propias decisiones
| # | Decisión mía | Problema que resolvía | ¿Lo resuelve? | Riesgo que introduce | Gravedad |
|---|---|---|---|---|---|
| 1 | Confirmar posiciones informadas contra lo observado | Juzgar golpes en su instante sin confiar a ciegas | En parte: impide informar puntos por los que no pasaste | **No da legitimidad**: el cliente es dueño de su física y puede moverse distinto dentro de los límites. Un cliente modificado puede seguir haciendo trampa con su movimiento real | **Crítico** (conocido y documentado; ver C) |
| 2 | Margen 2,25 + v × 0,04 | Golpes legítimos rechazados con 1,5 | Sí, en Studio sin latencia | No medido con latencia real ni en celulares. Durante un Paso el margen llega a ~5,4 studs | Alto |
| 3 | `InicioAtaque` (secuencia legal) | El cliente declaraba el ataque más fuerte | Sí para el orden del combo | La carga del golpe fuerte sigue siendo declarada si no hubo ataque reciente (≤ +8 de daño) | Medio |
| 4 | Retroceso máximo 0,3 s | Ping alto compraba ventana | Sí | Con más de 150 ms de ida, el jugador desvía "tarde" sin saberlo | Medio (ajustable) |
| 5 | Teletransporte autorizado con varias posiciones observadas | Golpes rechazados alrededor de teletransportes | Sí en las pruebas | Durante 1 s tras un teletransporte la validación es más permisiva | Bajo (solo lo dispara el servidor) |
| 6 | Luchadores sin colisión entre sí | El compañero salía disparado | Sí | En PvP dos jugadores se atraviesan: no se puede bloquear un pasillo con el cuerpo (decisión de diseño a confirmar) | Medio |
| 7 | 80 % de velocidad atacando y cancelar con Paso | El personaje se sentía pesado | Pendiente de una persona | Golpear y huir es más fácil; en PvP puede favorecer el "pegar y escapar" que critiqué en otros juegos | Alto (vigilar en PvP) |
| 8 | Desvío Reflejado (experimental) | Grupos de enemigos aburridos | Pendiente | Contra 5 enemigos un desvío perfecto daña a todos: puede volver triviales las peleas en grupo | Medio (limitar objetivos) |
| 9 | Todo el compañero en un `Heartbeat` por NPC | Simplicidad | Sí con 1-5 NPC | Con decenas de NPC el costo crece lineal; sin activación por distancia | Medio (ver I) |
| 10 | Pruebas que miden mis propios criterios | Evitar regresiones | Sí | Riesgo de "aprobar lo que yo diseñé". Mitigado en parte con bots adversariales | Alto |

**Con varios jugadores:** el juicio de defensa ya corre un hilo por jugador y ataque (acotado). Sin probar con `ExecuteMultiplayerTestAsync`. **Con latencia y FPS bajos:** probado a ~35 FPS; latencia real **no probada**. **Sensación ligera:** se mantuvo (valores de movimiento intactos; ataque más móvil).

## C. Comparación técnica de modelos de red
Fuente: documentación oficial de Roblox, *Server authority* y *Server authority techniques* (consultadas el 2026-11-07).

| Aspecto | Modelo actual (cliente dueño + validación del servidor) | Autoridad del servidor de Roblox (predicción y reconciliación) |
|---|---|---|
| Quién mueve al personaje | El cliente (network ownership) | El servidor; el cliente predice unos cuadros y se corrige |
| Trampas de movimiento | Se **detectan** (velocidades imposibles) pero no se impiden | Se **impiden**: el cliente solo envía entradas |
| Respuesta de controles | Inmediata, sin correcciones | Inmediata con predicción; correcciones visibles al fallar la predicción |
| Requisitos | Ninguno nuevo | `AuthorityMode = Server`, `UseFixedSimulation`, `SignalBehavior = Deferred`, StreamingEnabled, **Input Action System** (no `UserInputService`), lógica en `RunService:BindToSimulation()` en un módulo compartido, solo APIs con "Simulation Access", `time()` en vez de `os.clock()`, no guardar `AnimationTrack` entre cuadros, estado en atributos (máx. 64 por instancia) |
| Herramientas | Contadores propios en atributos | Visualizador oficial (tasa de predicción, aceptación de entradas, desfase cliente-servidor) |
| Compatibilidad con nuestro código | Total | **Baja hoy**: `MovementController` y `CombatController` usan `os.clock()`, `ContextActionService`, `LinearVelocity` fuera de una simulación determinista y guardan pistas de animación. Habría que reescribirlos. El Paso (78 studs/s) y los avances del Contraataque generarían correcciones visibles con ping alto |

**Recomendación (HIPÓTESIS hasta medir):** mantener el modelo actual para seguir desarrollando, y hacer un **prototipo aislado** del Paso y el salto bajo autoridad del servidor en otra rama, para medir con el visualizador oficial la tasa de predicción y si las correcciones arruinan la sensación. Decidir en la Fase 4 (PvP) con esos datos. No migrar "porque es más seguro" sin medir: si la sensación se rompe, el juego pierde su identidad.

**Canal `Posicion` (UnreliableRemoteEvent):** ya tolera pérdidas, duplicados y desorden (inserción ordenada, duplicados ignorados, vecinos comprobados, tasa limitada). Con el modelo de autoridad del servidor este canal dejaría de existir.

## D. Propuesta de balance por niveles (HIPÓTESIS: no hay sistema de niveles todavía)
Principio: **el nivel decide cuánto poder tienes; la habilidad, cuánto aprovechas; la inteligencia del enemigo, cómo puede castigarte.**

Fórmulas configurables (en un futuro `CombatConfig.Levels`):
- Vida del enemigo: `V(L) = V0 · (1 + kV · (L − 1))`, con kV = 0,08.
- Daño del jugador: `D(Lj) = D0 · (1 + kD · (Lj − 1))`, con kD = 0,05.
- Daño recibido de un enemigo: `R = R0 · (1 + kE · (Le − 1)) · clamp(1 − kR · (Lj − Le), mínimo, máximo)`, con kE = 0,05, kR = 0,012, mínimo 0,35 y máximo 1,25.
- Golpe de oportunidad: **no escala con la diferencia de nivel**. Su efecto principal es postura e interrupción, y su daño tiene un tope relativo a la vida del jugador: 5 % si el enemigo es inferior, 10 % si es igual, 15 % si es élite.

Estimaciones con V0 = 100 (enemigo base), D0 = 6 por golpe, R0 = 12 y vida del jugador 100 + 5 por nivel:
| Escenario | Golpes para vencerlo | Daño que recibes por golpe normal | Golpe de oportunidad (tope) | Lectura |
|---|---|---|---|---|
| J10 vs E10 | ~23 golpes (≈ 8 combos) | 18,5 de 145 (13 %) | 14,5 (10 %) | Pelea pareja: hay que defender |
| J30 vs E10 | ~13 golpes (≈ 4-5 combos) | 18,5 × 0,76 = 14,1 de 245 (6 %) | 12,2 (5 %) | Claramente superior; un error duele un poco |
| J50 vs E10 | ~9 golpes (≈ 3 combos) | 18,5 × 0,52 = 9,6 de 345 (3 %) | 17 (5 %) | Muy superior; el castigo es sobre todo ritmo y postura |
| J80 vs E10 | ~6 golpes (≈ 2 combos) | 18,5 × 0,35 = 6,5 de 495 (1,3 %) | 25 (5 %), con un tope absoluto de 20 recomendado | Cae rápido, pero puede romperte el combo y empujarte |
| J10 vs élite E20 | ~31 golpes ×1,5 de vida élite (≈ 16 combos) | 24,6 × 1,12 = 27,5 de 145 (19 %) | 21,7 (15 %) | Desafío real: exige técnica |

Riesgos a vigilar con simulaciones: el tope del 5 % con mucha vida da números grandes (25), así que hace falta también un **tope absoluto**; y la vida élite no debe convertirse en "esponja" (más de ~12 combos aburre).

## E. Amenaza Asimétrica (HIPÓTESIS)
Tres dimensiones independientes por enemigo, configurables en su ficha:
| Dimensión | Qué es | Dónde vive hoy |
|---|---|---|
| **Poder** | Vida, daño, resistencia de postura | `CombatConfig.Sparring.Types` (vida) y `Attacks` (daño, postura) |
| **Técnica** | Qué respuestas sabe usar (desvío, amague, retraso, castigo de recuperación) | Perfiles (`pattern`, `maxDelay`, `Amague`) |
| **Peligro situacional** | Qué error concreto puede castigar y con qué | Nuevo: lista de "oportunidades" por tipo (ver F) |

**Golpes de Oportunidad: comparación de alternativas**
| Alternativa | Conserva la superioridad del jugador | Mantiene relevante al enemigo | Riesgo |
|---|---|---|---|
| A. Daño extra | Mal: escala con números y puede matar injustamente | Sí | Alto |
| B. Postura | Bien: castiga sin matar | Sí, si la postura importa | Bajo |
| C. Interrumpir una técnica vulnerable | Bien | Sí | Bajo |
| D. Reposicionar (empuje) | Bien | Medio | Bajo; peligroso cerca del abismo |
| **E. B + C + D con daño acotado** | **Bien** | **Sí** | Medio (más reglas que explicar) |

**Recomendación: E.** Un golpe de oportunidad interrumpe, desgasta postura y empuja, con daño acotado (tope de D). Se activa por una **condición verificable**, nunca por azar. Ejemplos: castigar un golpe fuerte fallado, una guardia mantenida más de 1,5 s o un Paso cuyas dos cargas ya se gastaron.

**Evitar cadenas de aturdimiento (Aguante)**
- Cada aturdimiento dentro de una ventana de 2 s dura 40 % menos que el anterior.
- Después del tercero, 0,8 s de **Aguante**: inmune a nuevos aturdimientos (no al daño), con un borde visual claro.
- **Fichas de ataque por jugador:** como mucho 2 enemigos atacan a la vez a un mismo jugador; los demás se reposicionan o amagan. No hacen fila de forma artificial: rodean y presionan.
- Los golpes de oportunidad consumen una ficha extra y tienen enfriamiento por enemigo.

**PvE / PvP**
| Modo | Niveles | Críticos y oportunidades |
|---|---|---|
| PvE | Progresión vertical real (D) | Oportunidades acotadas por tipo de enemigo |
| PvP libre | Diferencia de poder limitada (escala comprimida, p. ej. ±15 % máx.) y protección de principiantes | Solo por ejecución (los Contraataques ya lo son) |
| PvP clasificatorio | Estadísticas normalizadas; los Ecos y sus rarezas sin ventaja | Sin azar en el daño |

## F. Instinto del Último Recuerdo (HIPÓTESIS)
Una técnica excepcional por arquetipo, con condición verificable, aviso y respuesta posible:
| Arquetipo | Condición observada (solo eventos del servidor) | Técnica | Aviso | Respuesta |
|---|---|---|---|---|
| Acechador | Golpe del jugador **fallado** con recuperación larga (Patada o Fuerte) | Desplazamiento rápido y golpe corto | Destello y sonido agudo 0,25 s antes | Paso guardado, no fallar golpes pesados |
| Bastión | Guardia mantenida > 1,5 s | Golpe que rompe la postura | Pose levantada y anillo de postura | Soltar la guardia, esquivar o interrumpir |
| Duelista | Mismo golpe 3 veces en 4 s, con confianza ≥ 0,6 | Desvía ese golpe y responde corto (empuje + postura) | Cambia de postura al "leerte" | Variar el combo, retrasar o amagar |
| Coronado | Fases por vida: combina las anteriores | Secuencias reconocibles | Cambio de fase anunciado | Aprender el patrón |

**Memoria táctica limitada:** contadores por acción observada (inicio de ataque, defensa, dirección del Paso) con decaimiento exponencial (vida media de 6 s). Solo reacciona por encima de un umbral de confianza y con probabilidad 50-70 %, para que se pueda engañar. Tiempo de reacción mínimo de 0,25 s. **Nunca lee entradas futuras:** solo usa eventos que el servidor ya recibió. Presupuesto: una técnica excepcional cada 8-12 s por enemigo, y nunca dos enemigos a la vez sobre el mismo jugador.

**La versión "¿qué acaba de hacer este desgraciado?":** un Raído de nivel bajo que desvía un golpe descuidado no te quita una barbaridad de vida. Te **rompe el ritmo** (te interrumpe, te empuja y te gasta postura) con una animación y un sonido espectaculares. El momento es memorable sin ser injusto.

## G. Matriz de pruebas
| # | Prueba | Estado |
|---|---|---|
| 1 | Jugador de alto nivel vence fácil a enemigos inferiores jugando bien | PENDIENTE (no hay niveles) |
| 2 | Un inferior castiga ocasionalmente un error real | PENDIENTE (prototipo de un enemigo) |
| 3 | El castigo respeta los topes de daño | PENDIENTE |
| 4 | No existe una estrategia universal que garantice contraataques | **PARCIAL: probado** con los bots (Machacador 0 %, Reloj fijo 0 %, Solo guardia pierde) |
| 5 | Los amagues engañan a enemigos técnicos | PENDIENTE |
| 6 | La IA no lee entradas futuras | PENDIENTE (prueba: la reacción nunca precede al evento del servidor) |
| 7 | No hay cadenas infinitas de aturdimiento | PENDIENTE (requiere el Aguante) |
| 8 | Cinco enemigos sin carga excesiva de CPU | PENDIENTE (MicroProfiler) |
| 9 | Las defensas válidas se resuelven bien con latencia | PENDIENTE (simulador de red de Studio) |
| 10 | La IA no genera Resonancia ilimitada | **Probado en parte**: topes por rival y por segundo; falta medir contra los nuevos enemigos |
| 11 | Los enemigos pueden perder la oportunidad de contraatacar | PENDIENTE |
| 12 | Mismas reglas a distintos FPS | **Probado** a ~35 FPS (Paso, salto, combo, desvío) |
| 13 | El PvP no depende de la rareza | PENDIENTE (Ecos no implementados) |

## H. Autoevaluación: riesgos y alternativas
**Cinco razones por las que podría fracasar:** (1) los jugadores no perciben la "lectura" del enemigo y lo sienten como azar; (2) demasiadas reglas especiales vuelven el combate ilegible; (3) los topes mal calibrados anulan la progresión o la amenaza; (4) la IA reactiva se siente "tramposa" aunque no lo sea; (5) el costo de programar y balancear arquetipos frena el resto del juego.

**Tres formas de explotarlo:** (1) "entrenar" a un Duelista con un patrón falso para provocar su reacción y castigarla siempre; (2) usar el Aguante para atravesar grupos sin riesgo; (3) farmear Resonancia con Desvío Reflejado en grupos grandes.

**Tres problemas de rendimiento:** (1) memoria táctica por jugador × enemigo; (2) hilos de juicio por ataque × jugador; (3) consultas espaciales de las ondas y del área de los barridos.

**Tres contradicciones con la progresión:** (1) topes de oportunidad que en niveles altos siguen pesando; (2) enemigos que escapan a tu poder por técnica = sensación de esponja; (3) el Aguante protege más a quien juega peor.

**Tres problemas de claridad:** (1) muchos avisos visuales a la vez; (2) lectura difícil en celular (pantalla chica); (3) daltonismo: los avisos no deben depender solo del color (ya hay pose y sonido).

**Alternativas más sencillas:** en vez de memoria táctica, patrones fijos con variación pequeña (ya funciona: perfil técnico); en vez de fichas de ataque, enfriamientos globales por jugador.

**Lo que no se puede validar sin jugadores:** si se siente justo, si la lectura es posible a tiempo, si la progresión emociona y si los momentos excepcionales se recuerdan como buenos.

## I. Qué se reaprovecha de lo existente
- `SparringService` ya es una máquina de estados (Quieto → Preparando → Atacando → Recuperando, más Aturdido) con perfiles, retrasos y amagues: el Instinto se agrega como **decisión en Quieto/Preparando**, no como sistema paralelo.
- `DefenseService` ya registra pulsaciones, guardias y Pasos con hora: es la **memoria observada** del jugador.
- `DamageService.SetModifier` (experimental) ya permite reglas por enemigo (coraza): sirve para los golpes de oportunidad.
- `MoveSchema` puede validar las fichas de "oportunidad" igual que valida los ataques.
- `ResonanceService` ya tiene topes por rival.
- Rendimiento: pasar el `Heartbeat` de cada enemigo a una frecuencia de decisión por distancia (cerca: cada cuadro; lejos: 5 por segundo; muy lejos: dormido).

## J. Tareas priorizadas
1. Validación humana de las fases 1-3 (listas H1-H12).
2. Probar los enemigos experimentales en la Grieta; decidir si se integran.
3. Red adversa en Studio (150 ms, 1 %) y `ExecuteMultiplayerTestAsync` con 2 jugadores.
4. Prototipo de **un** golpe de oportunidad (Acechador castiga un golpe fuerte fallado) en una rama experimental.
5. Aguante (anticadena) antes de poner grupos grandes de enemigos.
6. Prototipo de autoridad del servidor solo para el Paso, para medir.
7. Sistema de niveles (D) cuando haya progresión que lo use.

## K. Recomendación por mecánica
| Mecánica | Recomendación |
|---|---|
| Latido (ritmo) | **Experimentar**: enseña el desvío perfecto; se integra si los jugadores lo entienden |
| Centinela (coraza frontal) | **Experimentar**: enseña el Contrapaso |
| Gemelos (vida compartida) | **Experimentar**; simplificar si confunde |
| Desvío Reflejado | **Experimentar con límite** (máx. 3 objetivos) |
| Golpes de Oportunidad (E) | **Experimentar** con un solo enemigo |
| Instinto con memoria táctica | **Simplificar** primero: arrancar con condiciones fijas (sin memoria) y agregar memoria solo si aporta |
| Aguante (anticadena) | **Implementar** antes de grupos grandes |
| Críticos aleatorios de 15-20 % | **Descartar** |
| Migrar a autoridad del servidor | **Experimentar** (prototipo medido), no migrar todavía |

## L. Registro de decisiones de esta revisión
| # | Decisión | Estado |
|---|---|---|
| 54 | Las mecánicas nuevas de enemigos se desarrollan en ramas experimentales, no en `main` | APROBADO |
| 55 | Críticos aleatorios grandes como regla general | DESCARTADO |
| 56 | Golpes de oportunidad = interrupción + postura + empuje, daño acotado, condición verificable | HIPÓTESIS |
| 57 | Fórmulas de nivel de la sección D | HIPÓTESIS |
| 58 | Aguante (anticadena) y fichas de ataque | HIPÓTESIS (prioridad alta) |
| 59 | Mantener el modelo de red actual hasta medir un prototipo de autoridad del servidor | APROBADO (provisional) |
| 60 | La IA solo usa eventos ya recibidos por el servidor; nunca entradas futuras | APROBADO (regla de diseño) |
