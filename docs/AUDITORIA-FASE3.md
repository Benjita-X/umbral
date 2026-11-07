# Registro de hallazgos de la auditoría (Fase 3)

Fecha: 2026-11-06. Alcance: código real de `main` (`3308bc8`) y de la rama `auditoria-fase3` (`9b4edd0`), leído archivo por archivo, más una ejecución independiente de las pruebas automáticas.

Leyenda de estados: **IMPLEMENTADO** (existe código) · **INTEGRADO** (conectado al proyecto) · **PROBADO** (una prueba concreta se ejecutó y pasó) · **VALIDADO** (cumple criterios, incluidos los humanos) · **PENDIENTE** · **BLOQUEADO**.

## 0. Estado de partida verificado
| Dato del manual | Realidad verificada |
|---|---|
| `main` en `74a9942` | `main` estaba en `3308bc8` (un commit encima: el propio manual). `74a9942` es su padre |
| `auditoria-fase3` en `9b4edd0` | Correcto |
| 78 de 82 pruebas en `main` | Ejecución independiente: **79 de 82**. "Saltar el barrido" pasó esta vez → es una prueba **intermitente**, no un fallo fijo |
| Árbol de trabajo | Limpio, sin cambios sin guardar |

Puntos de recuperación creados antes de tocar nada: etiquetas `respaldo/main-pre-consolidacion` y `respaldo/auditoria-fase3-wip`, y un bundle completo fuera del repositorio (`JUEGOSCLAUDE/umbral-respaldo-2026-11-06.bundle`).

## 1. Hallazgos críticos

### C1. La "confirmación" de posiciones no era una prueba de legitimidad — CORREGIDO (parcial, por diseño de Roblox)
- **Qué había:** el servidor aceptaba la posición que informa el cliente si la física observada pasaba a menos de **4 studs** de ella.
- **Problema 1:** la física observada de un jugador también la produce su cliente (network ownership). Comparar dos datos del mismo cliente demuestra coherencia, no legitimidad.
- **Problema 2 (explotable):** con 4 studs fijos, un cliente modificado podía informar un punto **hasta ~4 studs más cerca** del rival por el que nunca pasó y quedar confirmado: alcance extra sumado a la tolerancia de 1,5.
- **Corrección:** margen adaptativo `ConfirmRadius 2,25 + velocidad × 0,04` medido como distancia a los **segmentos** de la trayectoria observada (quieto 2,25 studs; Paso a 78 studs/s ≈ 5,4). Se empezó con 1,5 + v × 0,025 y las pruebas mostraron golpes legítimos rechazados al avanzar golpeando (la trayectoria replicada se separa hasta ~2 studs): se amplió con ese dato. Vigilancia aparte de velocidades observadas imposibles (atributo `VelocidadObservadaImposible`, solo registro).
- **Prueba:** `[Adversarial] Posición falsa no da alcance` (informa 3,5 studs más cerca de un muñeco fuera de alcance).
- **Límite que queda:** un cliente modificado puede mover su personaje de verdad (dentro de las velocidades permitidas). Eso no se resuelve con historiales; se mitiga con validación de movimiento y, si hiciera falta, física del servidor. Documentado en §5.

### C2. Retroceso temporal sin tope efectivo — CORREGIDO
- **Qué había:** la hora del cliente se aceptaba hasta `ping + márgenes` en el pasado. Con ping alto (o un "lag switch") la ventana crecía sin límite real.
- **Corrección:** `MaxRewind = 0,3 s`: retroceso = `min(ping, 0,3) + 0,15`. Lo usan `PositionService`, `DefenseService` y `SparringService` (la latencia de ida tiene tope 0,15 s).
- **Coste conocido:** con ping de ida > 150 ms el jugador ve el impacto algo después de lo que el servidor le reconoce: sus desvíos deben ser un poco más tempranos. Es el compromiso elegido para no favorecer conexiones lentas; `MaxRewind` es ajustable.
- **Prueba:** `Rechaza tiempos de defensa falsos`, `Rechaza golpes con hora manipulada`.

### C3. El cliente elegía qué ataque declarar (caso Nexus Battles D) — CORREGIDO
- **Qué había:** el servidor aceptaba cualquier nombre de ataque válido. Un cliente podía declarar "Patada" (7) o "Fuerte" con carga completa (18) en lugar de "Jab" (4), hasta 14 veces por segundo.
- **Corrección:** nuevo remote `InicioAtaque`. El servidor guarda la secuencia: Jab → Directo → Patada (Jab siempre permitido), mínimo entre inicios = preparación + impacto del anterior, el fuerte necesita tiempo de mantener y su carga se limita al tiempo libre disponible, ≤ 12 inicios/s, no aturdido. Cada golpe debe pertenecer a un inicio aceptado del **mismo** ataque y caer en **su** ventana activa.
- **Pruebas:** `Rechaza combos fuera de orden`, `Rechaza ataques más rápidos que posible`, `Rechaza golpes sin inicio de ataque`.
- **Límite:** la carga del golpe fuerte después de un rato sin atacar sigue siendo declarada por el cliente (como mucho +8 de daño, una vez por golpe fuerte, que ya exige mantener). Cerrarlo del todo requiere avisar también el inicio de la carga (pendiente, Fase 4).

### C4. Rama de auditoría sin conectar — INTEGRADO
La rama tenía `PositionService` y `PositionReporter` escritos pero **no arrancados**: con la rama tal cual, todos los golpes se habrían rechazado ("posición no confirmada"). Integración hecha a mano (merge sin commit automático, revisión y cableado), ver §3.

## 2. Hallazgos altos y medios
| # | Hallazgo | Estado |
|---|---|---|
| A1 | `DefenseService`: un `defender_inicio` que llegaba desordenado (más viejo) hacía **retroceder** el reloj del enfriamiento de desvío (podía habilitar desvíos extra) | CORREGIDO: `lastPress = max(...)`, pulsaciones ordenadas, duplicados ignorados |
| A2 | Sin límite de tasa en `Posicion` (Unreliable) ni en `Defensa` | CORREGIDO: 45/s y 30/s; exceso se cuenta en atributos |
| A3 | `Report` solo comparaba la velocidad con la muestra anterior; una muestra insertada desordenada no se comparaba con la siguiente | CORREGIDO: compara con ambas vecinas |
| A4 | El Paso extra con Resonancia no tenía enfriamiento en el **servidor** (solo una nota) | CORREGIDO: `ExtraDashCooldown` en cliente y servidor (margen 0,15 s de red) |
| A5 | Las cargas de Paso se recargaban **durante** el propio Paso | REVERTIDO: se probó pausar la recarga, pero cambiaba el valor medido de 0,8 s sin un problema concreto. Decisión final: la recarga sigue corriendo durante el Paso (DECISIONES #43) |
| A6 | `EnemyController` no conocía el Rápido ni el Pesado, no reaccionaba al amague ni a los retrasos | CORREGIDO: clip desde `attack.clip`, colores naranja/rojo oscuro, escucha `FaseInicio`, congela la pose `holdAt` durante el retraso |
| A7 | `DummyService` no registraba muñecos en el historial y devolvía al compañero a su sitio a la fuerza | CORREGIDO: `PositionService.Track` + opción `noReset` |
| A8 | Teletransportes de las pruebas marcados como trampa | CORREGIDO: acción `teletransporte` **solo en `tests/server`** (no existe en el lugar de desarrollo) |
| A9 | `ejecutar-pruebas.ps1`: con otra ventana de Studio abierta, la nueva instancia no abre el lugar de pruebas y no hay resultados (pasó en esta auditoría) | MITIGADO: el script avisa; la causa está documentada |
| M1 | Los atributos `FaseInicio/FaseFin` del enemigo se pueden leer desde un cliente modificado | ACEPTADO: ningún sistema de seguridad depende de que sean secretos. En PvP un bot podría leer los tiempos del rival igual que lee la animación; lo que se protege es el juicio, no la información |
| M2 | Contrapaso: la dirección se evalúa respecto al vector atacante → defensor (la amenaza), no a la cámara | VERIFICADO en `SparringService.isLateral` |
| M3 | `ResonanceService` guarda límites por rival con el modelo como clave | ACEPTADO: se libera al salir el jugador |
| M4 | `overlapParams` sin uso en `CombatController` | ELIMINADO |

## 3. Integración de `auditoria-fase3`
1. `git merge --no-ff --no-commit auditoria-fase3` sobre `main`: sin conflictos (la rama solo diverge en código; el manual de `main` se conserva).
2. Revisados los 11 archivos que cambian, uno por uno.
3. Cableado faltante (lista del manual §8, puntos 1-7): `ServerBootstrap`, `ClientBootstrap`, `DummyService`, `EnemyController`, `CombatController`, `MovementController`, pruebas.
4. Correcciones de esta auditoría (§1 y §2).
5. Pruebas completas. Ver resultados en `ESTADO.md` y `PRUEBAS-FASE3.md`.

Ningún cambio de la rama fue rechazado.

## 4. Análisis de movilidad (sin cambiar números)
- Huida sostenida: con 2 cargas y 0,8 s por carga, tras gastar las dos el ritmo es 1 Paso cada 0,8 s (≈ 17,5 studs/s extra de promedio) sobre el sprint de 34 studs/s. El Paso extra con Resonancia cuesta 30 y como mucho uno cada 2 s, y la Resonancia **no se gana huyendo** (solo golpeando, desviando o esquivando ataques reales) y se apaga fuera de combate.
- Como perseguidor y perseguido tienen el **mismo** movimiento, en campo abierto e infinito nadie alcanza a quien solo huye. **La respuesta no está en los números del Paso sino en la arena** (límites, pilares que cortan la huida, esquinas sin trampas) y en un futuro objetivo de ronda. Se deja para la arena gris de la Fase 4 y las pruebas humanas.
- A 20 informes/s un Paso recorre ≈ 3,9 studs entre dos informes. El nuevo margen (2,25 + v × 0,04 ≈ 5,4 en pleno Paso, medido contra segmentos observados a 60 Hz, ≈ 1,3 studs entre muestras) cubre ese caso sin regalar alcance quieto.

## 5. Límites conocidos (no resueltos, documentados)
1. **Autoridad del movimiento:** el cliente simula su personaje. Un cliente modificado puede moverse distinto dentro de las velocidades vigiladas. Opciones futuras: validación de Pasos contra cargas en el servidor, o física del servidor para el personaje (más latencia percibida). Decisión pendiente para la Fase 4 con datos de PvP real.
2. **Carga del golpe fuerte** tras un rato sin atacar (ver C3).
3. **Lectura humana:** el bot Lector lee `FaseFin`; demuestra que las reglas premian leer, no que una persona alcance a leer la animación. **Pendiente de validación humana.**
4. **Red adversa simulada** (150 ms, 1 % de pérdida), **avatares 0,7 / 1,3** con personajes reales y **multijugador** (`ExecuteMultiplayerTestAsync`): no ejecutados todavía. La geometría de alturas se probó como regla pura (Hurtbox).
5. **Móvil físico:** no probado.

## 6. Casos de estudio de Nexus Battles
**Importante:** en esta sesión no se descargó ni se leyó el código de Nexus Battles. Los hallazgos A-F vienen de una revisión anterior hecha por otra persona; aquí se usan como **lista de riesgos a comprobar en UMBRAL**, no como hallazgos verificados por mí.

| Riesgo | En UMBRAL |
|---|---|
| A. Atribución de eliminaciones (máximo de daño sin actualizar) | No aplica todavía (no hay eliminaciones). Al crear rondas: prueba con varios atacantes |
| B. Compras sin idempotencia | No hay compras. Regla para la Fase 12: `ProcessReceipt` con registro de `PurchaseId` antes de entregar |
| C. Conexiones por ronda sin limpiar | No hay rondas. Los servicios conectan una sola vez y limpian por jugador; regla para la Fase 4 |
| D. El cliente elige un modo con más daño | **Corregido** (C3) |
| E. Estado de ataque enviado antes de reiniciarlo | El combo se valida en el servidor (C3); el reinicio por inactividad no puede dar un ataque ilegal |
| F. Detección con `Touched` | UMBRAL no usa `Touched`: cajas orientadas en cliente y servidor |

Las licencias de Nexus Battles, Ruddev's Battle Royale y Crossovers **no se verificaron** en esta sesión; no se copió código ni recursos de ninguno.
