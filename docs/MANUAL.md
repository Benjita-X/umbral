# Manual de UMBRAL: cómo seguir por tu cuenta

Este manual es para que sigas desarrollando UMBRAL **tú mismo**, con otra IA como profesora o revisora (que te explique y te proponga cambios), pero haciendo tú los cambios.

> Regla de oro: **los cambios se hacen en los archivos de `src/`, nunca dentro de Roblox Studio.** Studio solo sirve para jugar y mirar. Cada vez que armas el lugar, se rehace desde los archivos y lo que hayas cambiado en Studio se pierde.

---

## Índice
1. [En qué punto está el proyecto](#1-en-qué-punto-está-el-proyecto)
2. [Herramientas que necesitas](#2-herramientas-que-necesitas)
3. [Mapa del proyecto: qué hay en cada archivo](#3-mapa-del-proyecto-qué-hay-en-cada-archivo)
4. [Cómo funciona por dentro](#4-cómo-funciona-por-dentro)
5. [Tu rutina de trabajo](#5-tu-rutina-de-trabajo)
6. [Recetario: "quiero cambiar X"](#6-recetario-quiero-cambiar-x)
7. [Cómo trabajar con otra IA sin que lo haga por ti](#7-cómo-trabajar-con-otra-ia-sin-que-lo-haga-por-ti)
8. [Terminar la auditoría (rama `auditoria-fase3`)](#8-terminar-la-auditoría-rama-auditoria-fase3)
9. [Pruebas automáticas](#9-pruebas-automáticas)
10. [Problemas conocidos](#10-problemas-conocidos)
11. [Lo que viene: fases 4 a 13](#11-lo-que-viene-fases-4-a-13)
12. [Git en 5 minutos](#12-git-en-5-minutos)
13. [Glosario](#13-glosario)

---

## 1. En qué punto está el proyecto

| Parte | Estado |
|---|---|
| **Fase 1 · Movimiento** | ✅ Terminada y probada (carrera, sprint automático, Paso, salto, doble salto, coyote time, búfer de salto) |
| **Fase 2 · Combate corporal** | ✅ Terminada y probada (combo Jab → Directo → Patada, golpe fuerte con carga, guardia, hitstop, efectos, muñecos, daño validado en el servidor) |
| **Fase 3 · Defensa** | ✅ Integrada y probada (ver `docs/ESTADO.md` para los defectos conocidos) |
| **Auditoría de la Fase 3** | ✅ Integrada en `main` el 2026-11-06 (ver `docs/AUDITORIA-FASE3.md`). La sección 8 queda como historia |
| Mundo, historia, Ecos, tienda | ⏳ No empezado (a propósito: primero el combate) |

**Versiones guardadas en Git:**
- `main`: versión consolidada (fases 1-3 + auditoría + arena + La Grieta).
- `respaldo/main-pre-consolidacion` y `respaldo/auditoria-fase3-wip`: etiquetas con el estado anterior, por si hay que volver.

**Dónde está todo:** `C:\Users\bxnjvv\JUEGOSCLAUDE\umbral`

**Controles actuales:**

| Acción | PC | Mando | Celular |
|---|---|---|---|
| Moverse | WASD | Stick izq. | Joystick |
| Atacar (tocar: combo · mantener: golpe fuerte) | Clic izquierdo | X | ATACAR |
| Defender (tocar a tiempo: desvío · mantener: guardia) | F | R1/RB | DEFENDER |
| Paso (dash) · de lado justo antes de un golpe: Contrapaso | Shift | B | PASO |
| Saltar / doble salto | Espacio | A | Saltar |

**Zonas del mapa** (apareces en el centro mirando a la pista):

| Zona | Dónde | Para qué |
|---|---|---|
| Pista de Paso | Al frente | Medir velocidad y distancia (marcas cada 10 studs) |
| Slalom | A la izquierda | Cambios de dirección |
| Pilares de altura | A la derecha | Altura de salto (números en los pilares) |
| Brechas | Atrás | Saltos con Paso y doble salto |
| Rampas y escalera | Adelante a la derecha | Pendientes |
| Túnel y muro | Adelante a la izquierda | Cámara en lugares cerrados |
| **Dojo** | Atrás a la derecha | Muñecos para practicar golpes |
| **Ring** | Atrás a la izquierda | Compañero de combate que ataca: practicar la defensa |

---

## 2. Herramientas que necesitas

Ya las tienes instaladas en este PC:

| Herramienta | Para qué | Comprobar que está |
|---|---|---|
| **Roblox Studio** | Jugar y mirar el juego | Abrirlo desde el menú Inicio |
| **Node.js** | Armar el lugar de Roblox desde los archivos | `node --version` |
| **Git** | Guardar versiones y volver atrás | `git --version` |
| **VS Code** (recomendado) | Editar los archivos `.luau` con colores | Abrir la carpeta `umbral` |
| **PowerShell** | Ejecutar las pruebas automáticas | Viene con Windows |

Consejo: en VS Code instala la extensión **"Luau Language Server"**. Marca errores mientras escribes.

---

## 3. Mapa del proyecto: qué hay en cada archivo

```
umbral/
├── src/                      ← EL JUEGO (lo que editas)
│   ├── shared/               ← lo usan cliente y servidor (va a ReplicatedStorage.Shared)
│   │   ├── Config/
│   │   │   ├── MovementConfig.luau   ← TODOS los números del movimiento
│   │   │   └── CombatConfig.luau     ← TODOS los números del combate, defensa, enemigo
│   │   └── Combat/
│   │       ├── AnimationLibrary.luau ← las animaciones, hechas con poses por código
│   │       └── Rig.luau              ← pone las articulaciones en modo exacto (cinemático)
│   ├── client/               ← corre en la pantalla de cada jugador (StarterPlayerScripts)
│   │   ├── ClientBootstrap.client.luau ← arranca todo en orden
│   │   └── Controllers/
│   │       ├── InputController.luau    ← teclado, mando y botones táctiles → acciones
│   │       ├── MovementController.luau ← correr, Paso, saltos, gravedad
│   │       ├── CombatController.luau   ← golpes, combo, golpe fuerte, guardia, desvío, aturdimiento
│   │       ├── CameraController.luau   ← campo de visión y vibración de cámara
│   │       ├── EffectsController.luau  ← chispas, destellos, estelas, sonidos, números de daño
│   │       ├── EnemyController.luau    ← cómo se ve y avisa el compañero de combate
│   │       ├── CombatHUD.luau          ← contador de combo y avisos ("¡DESVÍO PERFECTO!")
│   │       ├── VitalsHUD.luau          ← barras de vida, postura y Resonancia
│   │       └── DebugHUD.luau           ← panel de números arriba a la izquierda
│   └── server/               ← corre en el servidor (ServerScriptService)
│       ├── ServerBootstrap.server.luau ← arranca los servicios en orden
│       └── Services/
│           ├── DamageService.luau      ← valida los golpes del jugador y aplica daño
│           ├── DefenseService.luau     ← desvíos, guardia, postura, aturdimiento
│           ├── ResonanceService.luau   ← la Resonancia (ganar, gastar, apagarse)
│           ├── DummyService.luau       ← muñecos de práctica (vida, curarse, volver a su sitio)
│           └── SparringService.luau    ← el compañero de combate que ataca y su juicio
├── tests/                    ← pruebas automáticas (solo en el lugar de pruebas)
│   ├── client/PruebasRunner.client.luau ← ejecuta las suites en orden
│   ├── client/Pruebas/Util.luau         ← herramientas comunes de las pruebas
│   ├── client/Pruebas/Movimiento.luau   ← 23 pruebas de movimiento
│   ├── client/Pruebas/Combate.luau      ← pruebas de combate
│   ├── client/Pruebas/Defensa.luau      ← pruebas de defensa
│   └── server/PruebasServidor.server.luau ← ayudas del servidor para las pruebas
├── tools/                    ← herramientas (no son parte del juego)
│   ├── construir.mjs         ← arma build/UMBRAL-Desarrollo.rbxlx desde src/
│   ├── mapa.mjs              ← el MAPA: todas las zonas, piezas y carteles
│   ├── ejecutar-pruebas.ps1  ← abre Studio, ejecuta las pruebas y muestra resultados
│   └── plugin/UmbralPruebas.server.luau ← plugin de Studio que inicia las pruebas solo
├── build/                    ← GENERADO (no editar; Git lo ignora)
│   └── UMBRAL-Desarrollo.rbxlx ← el lugar que abres en Studio
└── docs/                     ← documentación (este manual, decisiones, estado, pruebas)
```

**Cómo se nombra cada archivo** (la misma convención que usa Rojo):
- `*.server.luau` → Script (corre en el servidor)
- `*.client.luau` → LocalScript (corre en el cliente)
- `*.luau` → ModuleScript (un módulo que otros cargan con `require`)
- carpeta → Folder

---

## 4. Cómo funciona por dentro

### Cliente y servidor
- El **cliente** (la pantalla de cada jugador) lee los controles, mueve al personaje, anima y muestra los efectos **al instante**.
- El **servidor** **decide lo importante**: el daño, si un desvío valió, la vida, la postura y la Resonancia.
- Así el juego responde rápido y nadie puede hacer trampa decidiendo el daño desde su pantalla.

### Un golpe, paso a paso
1. Pulsas **Atacar** → `InputController` emite la acción "Atacar".
2. `CombatController` empieza el golpe con tres momentos: **preparación → impacto → recuperación** (los tiempos están en `CombatConfig.Attacks`).
3. En el impacto busca rivales delante de ti. Si encuentra uno, aplica el **hitstop** y los efectos (`EffectsController`).
4. Le avisa al servidor por `ReplicatedStorage.Remotes.SolicitudGolpe`.
5. `DamageService` valida el golpe: que el ataque exista, que estés vivo, la distancia, que no sea repetido y que no haya demasiados por segundo. Si todo cuadra, aplica el daño y avisa a todos por `GolpeConfirmado`.

### Una defensa, paso a paso
1. El compañero de combate (`SparringService`) **prepara** un ataque. Publica su estado en atributos (`Estado`, `Ataque`, `FaseFin`…).
2. Tu pantalla (`EnemyController`) lo anima y te avisa: brillo de color, anillo en el suelo y sonido.
3. Pulsas **Defender** o das un **Paso**, y tu pantalla le manda al servidor **la hora exacta** (`Remotes.Defensa`).
4. En el impacto, el servidor decide en este orden: **desvío → Contrapaso → esquiva/salto → guardia → golpe**. Avisa con `ResultadoDefensa`.
5. Tu pantalla muestra el resultado ("¡DESVÍO PERFECTO!") y, si te pegaron, te aturde y te empuja.

### Dónde viven los números
**Casi todo lo que quieras ajustar es un número en `MovementConfig.luau` o en `CombatConfig.luau`.** El código lee de ahí. Cambias el número, armas y pruebas.

---

## 5. Tu rutina de trabajo

Abre una terminal (PowerShell) en la carpeta del proyecto:
```bash
cd C:\Users\bxnjvv\JUEGOSCLAUDE\umbral
```

**1. Antes de empezar, mira en qué versión estás:**
```bash
git status
```

**2. Haz tu cambio** en un archivo de `src/` (por ejemplo, un número de `MovementConfig.luau`).

**3. Arma el lugar:**
```bash
node tools/construir.mjs
```

**4. Ábrelo en Studio:** doble clic en `build\UMBRAL-Desarrollo.rbxlx` (si ya estaba abierto, ciérralo antes y ábrelo de nuevo). Presiona **F5** para jugar y **Mayús+F5** para parar.

**5. Si algo falla:** en Studio abre **Ventana → Salida** (Output). Ahí salen los errores en rojo, con el archivo y la línea.

**6. Ejecuta las pruebas automáticas** (unos 3 minutos; Studio se abre y se cierra solo):
```bash
powershell -ExecutionPolicy Bypass -File tools/ejecutar-pruebas.ps1
```

**7. Si todo está bien, guarda una versión:**
```bash
git add -A
```
```bash
git commit -m "Ajusto la distancia del Paso a 16"
```

> Haz **un cambio a la vez**: cambiar, armar, probar y guardar. Si cambias diez cosas juntas y algo se rompe, no vas a saber cuál fue.

---

## 6. Recetario: "quiero cambiar X"

### Movimiento → `src/shared/Config/MovementConfig.luau`
| Quiero… | Cambia |
|---|---|
| Correr más rápido | `RunSpeed` (ahora 22) |
| Sprint más rápido o que entre antes | `SprintSpeed` (34) · `SprintDelay` (0,4 s) |
| Un Paso más largo | `DashDistance` (14 studs) |
| Un Paso más explosivo | `DashDuration` (0,18 s: menos = más rápido) |
| Más cargas de Paso o recarga más rápida | `DashCharges` (2) · `DashRechargeTime` (0,8 s) |
| Saltar más alto | `JumpHeight` (8,5) · `AirJumpHeight` (7, el doble salto) |
| Saltos más "secos" | `Gravity` (230) · `FallGravityMultiplier` (1,35) |
| Más o menos margen al saltar desde un borde | `CoyoteTime` (0,1 s) |
| Más o menos sensación de velocidad en la cámara | `SprintFOV` (76) · `DashFOVKick` (8) |
| Apagar el panel de números | `DebugHUD = false` |

### Ataques del jugador → `CombatConfig.luau`, sección `Attacks`
Cada golpe (`Jab`, `Cross`, `Patada`, `Fuerte`) tiene:

| Campo | Qué es |
|---|---|
| `startup` | Preparación: cuánto tarda en salir el golpe |
| `active` | Impacto: cuánto dura la zona que golpea |
| `recovery` | Recuperación: cuánto quedas expuesto después |
| `damage` | Daño |
| `range` · `hitboxSize` | Alcance y tamaño de la zona que golpea |
| `hitstop` | El congelamiento al conectar (el "peso" del golpe) |
| `knockback` · `knockUp` | Empuje y levantamiento del rival |
| `shake` | Vibración de cámara |
| `limb` | Qué mano o pie deja estela |

Otros ajustes de la misma sección:

| Quiero… | Cambia |
|---|---|
| Que haga falta mantener más o menos para el golpe fuerte | `HoldThreshold` (0,22 s) |
| Más daño con la carga completa | `Attacks.Fuerte.chargeBonus` (8) |
| Otro orden del combo | `LightChain` |
| Que fallar se pague más o menos | `WhiffRecoveryMultiplier` (1,35) |
| Más o menos ayuda para apuntar | `SoftTargetRange` (12) · `SoftTargetAngle` (75°) · `MaxLunge` (3,5) |
| Moverse más rápido mientras golpeas | `AttackMoveMultiplier` (0,35) |
| Menos vibración de cámara (accesibilidad) | `Feedback.ScreenShake` (0 = apagada) |

> Las **animaciones se ajustan solas** a los tiempos (`startup`, `active`, `recovery`), porque se generan con esos mismos números.

### Defensa → `CombatConfig.luau`, sección `Defense`
| Quiero… | Cambia |
|---|---|
| Un desvío más fácil o más difícil | `DeflectWindow` (0,18 s) · `PerfectWindow` (0,1 s) |
| Castigar más o menos el machacar Defender | `DeflectCooldown` (0,35 s) |
| Que la guardia proteja más o menos | `GuardDamageMultiplier` (0,2 = recibes el 20 %) |
| Que la guardia se rompa antes o después | `PostureMax` (100) y la postura de cada ataque enemigo |
| Un Contrapaso más permisivo | `ContrapasoWindow` (0,25 s) · `ContrapasoMinAngle`/`MaxAngle` (45°-135°) |
| Un Contraataque más fuerte o más rápido | `CounterDamageMultiplier` (1,3) · `CounterStartupMultiplier` (0,5) |
| Aturdir más o menos al recibir un golpe | `HitStun` (0,35 s) · `GuardBreakStun` (0,9 s) |

### Resonancia → `CombatConfig.luau`, sección `Resonance`
| Quiero… | Cambia |
|---|---|
| Cuánto da cada acción | `Gains` (Golpe 5, Desvío 5, Desvío perfecto 15, Esquiva 10, Contrapaso 20) |
| Cuánto cuesta el Paso extra | `DashCost` (30) |
| Que se apague más rápido o más lento | `DecayDelay` (5 s) · `DecayPerSecond` (8) |

### Compañero de combate → `CombatConfig.luau`, sección `Sparring`
| Quiero… | Cambia |
|---|---|
| Otro orden de ataques | `Pattern` (ahora Golpe, Golpe, Barrido) |
| Más o menos pausa entre ataques | `Pause` (1,2 s) |
| Que avise más o menos antes | `Attacks.Golpe.windup` (0,5 s) · `Attacks.Barrido.windup` (0,7 s) |
| Más o menos daño | `Attacks.Golpe.damage` (12) · `Attacks.Barrido.damage` (15) |
| Que se pueda esquivar de lado más fácil | `TrackingStop` (0,15 s: cuándo deja de girar antes del impacto) |

> En la rama `auditoria-fase3`, `windup` se llama `startup` y hay más ataques (Rápido, Pesado, Amague) y perfiles. Ver sección 8.

### Otras cosas
| Quiero… | Archivo · dónde |
|---|---|
| Cambiar las teclas | `InputController.luau` → función `InputController.Start` (líneas `bind(...)`) |
| Mover los botones del celular | `InputController.luau` → tabla `TOUCH_BUTTONS` (dx, dy y scale relativos al botón de salto) |
| Cambiar sonidos | `EffectsController.luau` → tabla `SOUNDS` (cuando tengas audios propios subidos, pon su `rbxassetid://`) |
| Cambiar chispas y colores de efectos | `EffectsController.luau` → `EffectsController.Impact` y `DEFENSE_STYLE` |
| Cambiar una pose (cómo se ve un golpe) | `AnimationLibrary.luau` → tabla `POSES`. Ángulos en grados `{ x, y, z }`: X+ lleva el brazo o la pierna hacia adelante |
| Cambiar el mapa (mover zonas, agregar piezas) | `tools/mapa.mjs` (cada zona es un bloque con `part({...})`) |
| Vida de los muñecos | `CombatConfig.luau` → `Dummy.MaxHealth` (120) · `ToughMaxHealth` (500) |
| Textos del HUD | `CombatHUD.luau` (avisos), `VitalsHUD.luau` (barras) |
| Qué valida el servidor en un golpe | `DamageService.luau` → función `handleHit` |
| Cómo se decide una defensa | `SparringService.luau` → función `resolve` |

---

## 7. Cómo trabajar con otra IA sin que lo haga por ti

La idea: la IA es tu **profesora y revisora**. Tú entiendes, decides y escribes el cambio.

### Cómo darle contexto
La IA no ve tu PC ni Studio. Al empezar una conversación, pégale esto:

```
Estoy haciendo UMBRAL, un juego de combate para Roblox (Luau).
El código está en archivos (convenciones de Rojo): src/shared (Config y Combat),
src/client/Controllers, src/server/Services. Lo armo con "node tools/construir.mjs"
y lo abro en Roblox Studio. Todos los números están en
src/shared/Config/MovementConfig.luau y CombatConfig.luau.
No me des el trabajo hecho: explícame y dime exactamente qué cambiar y por qué.
Yo hago el cambio.
```

Después pega **solo el archivo o la parte** de la que vas a hablar, y la sección de este manual que corresponda.

### Plantillas de preguntas

**Entender un archivo:**
```
Explícame qué hace este archivo, parte por parte, como si estuviera aprendiendo
Luau. No lo cambies. [pego el archivo]
```

**Planear un cambio:**
```
Quiero que [el Paso sea más largo pero sin que se sienta lento]. ¿Qué números de
MovementConfig debería tocar, cuánto y por qué? Dame 2 opciones con sus
ventajas y desventajas.
```

**Que te guíe a escribirlo tú:**
```
Quiero agregar [un tercer golpe al combo]. Dime los pasos y en qué archivos va
cada cosa. Escribo yo el código y te lo muestro para que lo revises.
```

**Revisar lo que escribiste:**
```
Escribí esto para [qué]. Revísalo: ¿tiene errores?, ¿rompe algo de lo que ya
existe?, ¿se puede hacer más simple? No lo reescribas: señálame los problemas.
[pego mi código]
```

**Arreglar un error:**
```
Al presionar F5 sale este error en Salida (Output): [pego el error completo, en
rojo, con archivo y línea]. Este es el archivo: [pego]. ¿Qué significa y cómo
lo arreglo?
```

**Una prueba que falla:**
```
La prueba "[nombre]" falló con este detalle: [pego la línea del resultado].
Este es el código de la prueba y el del sistema que prueba: [pego]. ¿Es un
problema del juego o de la prueba?
```

### Reglas para no romper nada
1. **Un cambio a la vez:** cambiar, armar, probar y hacer commit.
2. **Antes de aplicar un cambio que te propone la IA**, pídele que te explique cada línea. Si no la entiendes, no la pongas.
3. **Ejecuta las pruebas automáticas** antes de cada commit.
4. **Si algo se rompe y no sabes qué**, vuelve a la última versión buena (sección 12).
5. **Nunca pegues contraseñas, cookies ni claves** en una IA.
6. **No copies código de otros juegos de Roblox** ni uses herramientas para sacarlo: viola los términos de Roblox y te pueden cerrar la cuenta. Sí puedes estudiar cómo se *sienten* (jugando, mirando videos) y usar código abierto con licencia libre.
7. **Todo lo del juego debe ser tuyo** (nombres, personajes, arte, música) si algún día quieres cobrar un pase.

---

## 8. Terminar la auditoría (rama `auditoria-fase3`) — HECHO el 2026-11-06

> Todo lo de esta sección ya se hizo (salvo red adversa, avatares reales y multijugador, que siguen pendientes). Se conserva como registro.

La auditoría corrige el problema de fondo de las 4 pruebas que fallan y suma profundidad. Está guardada a medias.

### Cambiar a la rama
```bash
git switch auditoria-fase3
```
Para volver a la estable:
```bash
git switch main
```

### Lo que ya está hecho en la rama
| Archivo | Qué hace |
|---|---|
| `src/shared/Combat/Hurtbox.luau` | **Cajas de impacto estándar** (3 × 5,5 × 2,4 studs): el tamaño del avatar no da ventaja |
| `src/server/Services/PositionService.luau` | **Historial de posiciones con hora.** El cliente informa dónde está 20 veces por segundo; el servidor solo lo acepta si su propia física lo confirma (a menos de 4 studs, dentro de 0,25 s más la latencia) |
| `src/client/Controllers/PositionReporter.luau` | Manda esas posiciones (`UnreliableRemoteEvent` "Posicion") |
| `DamageService.luau` | Juzga cada golpe **en su instante**, con las cajas estándar. Reemplaza la espera de 0,35 s |
| `CombatConfig.luau` | Esquema común (`startup`, `active`, `recovery`, `posture`, `shape`, `cancelInto`…). Enemigo con **Rápido, Pesado (solo desvío perfecto, se lanza 9 studs), Barrido y Amague**, retrasos y perfiles (básico, técnico, agresivo). **Desvío fallido = expuesto.** Resonancia con límites anti-abuso |
| `src/shared/Combat/MoveSchema.luau` | Revisa que todos los movimientos estén bien definidos |
| `SparringService.luau` | Reescrito con todo lo anterior |
| `DefenseService.luau`, `ResonanceService.luau`, `AnimationLibrary.luau` | Adaptados (expuesto, límites, animaciones del Rápido y del Pesado) |

### Lo que falta, en este orden
1. **`ServerBootstrap.server.luau`:** cargar `PositionService` y llamar `PositionService.Start()` justo después de `DamageService.Start()`. Después llamar `DefenseService.SetPositionService(PositionService)`.
2. **`ClientBootstrap.client.luau`:** cargar `PositionReporter` y llamar `PositionReporter.Start()`.
3. **`DummyService.luau`**, en la función `Spawn`:
   - Llamar `PositionService.Track(model)`, para que el servidor guarde el historial de cada muñeco.
   - Si `options.noReset` es verdadero, no meter al modelo en la vuelta automática a su sitio (el compañero de combate vuelve por su cuenta).
4. **`EnemyController.luau`:**
   - Escuchar también el atributo `FaseInicio`. Un amague reinicia la preparación sin cambiar `Estado`.
   - Tomar el clip de `attack.clip` en lugar de la tabla `TELEGRAPH`, y agregar colores para Rápido (naranja) y Pesado (rojo oscuro).
   - Para los retrasos: si `FaseFin - FaseInicio` es mayor que `attack.startup`, pausar la animación en `attack.holdAt` el tiempo de diferencia (`AdjustSpeed(0)` y luego `AdjustSpeed(1)`).
5. **`CombatController.luau`:** la variable `overlapParams` ya no se usa; se puede borrar.
6. **`MovementController.luau`:**
   - Que las cargas de Paso **no se recarguen mientras dura un Paso**.
   - En `CombatController`, el Paso extra con Resonancia como mucho uno cada `Resonance.ExtraDashCooldown` (2 s).
7. **Pruebas:**
   - En `PruebasServidor.server.luau`, agregar la acción `"teletransporte"` que llama `PositionService.AllowTeleport(player)`. En `Util.luau`, que `ctx.teleport` la dispare antes de mover al personaje. Si no, el servidor marca los teletransportes de las pruebas como trampa.
   - Actualizar `Defensa.luau`: en el compañero de combate, `windup` pasó a llamarse `startup`.
   - Prueba del esquema: `MoveSchema.Validate(CombatConfig)` debe devolver 0 problemas.
   - Pruebas de **"habilidad y no machacar"**, con el perfil técnico y 4 jugadores-robot de prueba:
     - **Lector:** desvía en el momento justo según `FaseFin`. Meta: acertar más del 90 %.
     - **Machacador:** pulsa Defender cada 0,3 s. Meta: menos del 30 %.
     - **Solo guardia:** mantiene la guardia siempre. Debe perder contra el Barrido y el Pesado.
     - **Reloj fijo:** desvía siempre 0,45 s después del aviso. Debe fallar contra los retrasos, los amagues y el Rápido.
   - **Red adversa:** el plugin puede poner `settings().Network.InboundNetworkMinDelayMs`, `OutboundNetworkMinDelayMs`, `...JitterMs` y `...LossPercent` antes de `ExecutePlayModeAsync`. Repetir las suites de combate y defensa con 150 ms y 1 % de pérdida.
   - **Avatares de distinto tamaño:** muñecos con `HumanoidDescription.HeightScale` de 0,7 y 1,3. Los golpes deben conectar igual.
   - **Multijugador:** `StudioTestService:ExecuteMultiplayerTestAsync(2, args)`. Dos jugadores golpean el mismo muñeco a la vez, y ningún golpe legítimo debe rechazarse.
   - **Medir siempre:** golpes legítimos rechazados (debe ser 0), golpes falsos aceptados (debe ser 0), tiempo de respuesta, y pruebas omitidas o pendientes de una persona.
8. **Arena competitiva (solo geometría gris)** en `tools/mapa.mjs`, con medidas que salen del movimiento:
   - Salto: 8,5. Doble salto: 15,5. Paso: 14. Paso + salto: unos 22.
   - Plataformas de 4 (paso fácil), 7 (un salto) y 12 (doble salto).
   - Huecos de 14 (Paso) o 22 (Paso + salto).
   - Muros de 12 para correr por paredes en el futuro.
   - Pilares para cortar persecuciones, y el centro despejado.
9. **Cuando todas las pruebas pasen**, juntar con la estable:
```bash
git switch main
```
```bash
git merge auditoria-fase3
```

---

## 9. Pruebas automáticas

### Cómo funcionan
- `tools/ejecutar-pruebas.ps1`:
  1. Arma `build/UMBRAL-Pruebas.rbxlx`, que trae además la carpeta `tests/`.
  2. Instala el plugin `UmbralPruebas` en Studio.
  3. Abre una ventana nueva de Studio.
- El plugin detecta el lugar de pruebas y entra en **Play solo**, con `StudioTestService`.
- `PruebasRunner` corre las suites en orden (Movimiento → Combate → Defensa). Cada prueba mueve al personaje por código y **mide**.
- Los resultados se guardan con `plugin:SetSetting`, porque Studio no escribe los `print` en sus registros. El script los lee y cierra **solo la ventana que abrió**.

### Cómo leer los resultados
- **OK:** se midió y cumple.
- **FALLA:** se midió y no cumple. El detalle dice el valor medido y el esperado.
- **OMITIDA:** no se pudo medir en este momento. Por ejemplo, el FOV necesita que la ventana de Studio esté a la vista. **No cuenta como aprobada.**
- **Pendiente de validación humana:** lo que ninguna prueba puede juzgar ("¿se siente bien?"). Está en `docs/PRUEBAS-FASE1.md` y `PRUEBAS-FASE2.md`.

### Cómo agregar una prueba
En el archivo de la suite (por ejemplo, `tests/client/Pruebas/Combate.luau`):
```lua
-- 1. Preparar
ctx.teleport(Vector3.new(0, 4, 150), Vector3.new(0, 0, 1))
-- 2. Hacer
Input.Trigger("Atacar")
task.wait(0.5)
-- 3. Medir y registrar (solo si de verdad se midió)
record("Nombre claro de la prueba", valorMedido == esperado, "detalle con el valor medido")
```

Herramientas útiles de `ctx` (en `Util.luau`):
- `ctx.teleport`, `ctx.settle`, `ctx.waitUntil`, `ctx.trackJump`.
- `ctx.artificialLoad`: baja los FPS para probar como en un celular modesto.
- `ctx.skip(nombre, motivo)`: marca una prueba como omitida, con su motivo.

### Quitar el plugin de pruebas
Borra `%LOCALAPPDATA%\Roblox\Plugins\UmbralPruebas.rbxmx`. Solo actúa en el lugar de pruebas, así que no molesta en tus otros juegos.

---

## 10. Problemas conocidos

| Problema | Por qué pasa | Solución |
|---|---|---|
| **4 pruebas de defensa fallan en `main`:** Saltar el barrido, Contraataque vuelve al rival, El barrido no admite Contrapaso y Esquiva precisa | El servidor ve tu posición con retraso (la física replicada llega atrasada) y juzga esquivas legítimas con posiciones viejas | Ya está resuelto en la rama `auditoria-fase3` con el historial de posiciones. Hay que terminar la sección 8 |
| Las animaciones solo funcionan en Studio | Se generan con `RegisterKeyframeSequence`, que es solo para pruebas locales | Antes de publicar: subir las animaciones a Roblox o hacerlas con un animador, y poner sus IDs en `CombatConfig.AnimationIds` |
| Sonidos provisionales | Studio no trae sonidos de golpes; se usan aterrizaje y viento afinados | Subir audios propios o con licencia y cambiarlos en `EffectsController.SOUNDS` |
| En `main`, un avatar chico es más difícil de golpear | Los golpes se comprueban contra las piezas del cuerpo | En la rama ya se usan cajas estándar (`Hurtbox`) |
| Los botones táctiles no están probados en un teléfono real | — | Probar con el Emulador de dispositivos de Studio (pestaña Prueba) y en un celular |
| Al abrir el lugar, la ventana vieja de Studio sigue con la versión anterior | El archivo se rehace al armar | Cerrar y abrir de nuevo `build/UMBRAL-Desarrollo.rbxlx` |
| PowerShell corta mensajes de commit con comillas | Así trata los argumentos PowerShell 5.1 | Usar comillas simples, o escribir el mensaje en un archivo y usar `git commit -F archivo.txt` |

---

## 11. Lo que viene: fases 4 a 13

| Fase | Qué | Clave |
|---|---|---|
| 4 | **PvP 1v1 seguro** | Los golpes del jugador contra otros jugadores pasan por la misma defensa del servidor. Probar con `ExecuteMultiplayerTestAsync` |
| 5 | **Celular y rendimiento** | Botones cómodos y 60 FPS (o 30 estables) en teléfonos modestos. MicroProfiler |
| 6 | **Prólogo "El Eco que fuiste"** | Pelear en menos de 15 segundos tras apretar Play |
| 7 | **Ecos y rarezas** | Pesos sobre 10.000 (50 / 30 / 15 / 4 / 0,9 / 0,09 / 0,01 %); que la rareza no dé ventaja en PvP |
| 8 | **Enemigos, jefes y Grietas** | Reusar el oponente configurable como base |
| 9 | **Guardado** | `DataStoreService` con `UpdateAsync` y versiones de los datos |
| 10 | **Competitivo y social** | Duelos en el mismo servidor, revancha, espectadores |
| 11 | **Mundo y arte** | Alba, el Faro y las Grietas, construidos alrededor del combate |
| 12 | **Métricas y economía** | Retención D1/D7/D30; cosméticos sin pay-to-win |
| 13 | **Beta y lanzamiento** | Pruebas con jugadores reales |

> No avanzar al mundo, la economía ni la tienda antes de que el combate sea consistente y se sienta bien.

---

## 12. Git en 5 minutos

| Quiero… | Comando |
|---|---|
| Ver qué cambié | `git status` · `git diff` |
| Guardar una versión | `git add -A` y luego `git commit -m "qué hice"` |
| Ver el historial | `git log --oneline` |
| Deshacer cambios en un archivo (sin guardar) | `git restore ruta/del/archivo.luau` |
| Volver a la última versión guardada (¡borra lo no guardado!) | `git restore .` |
| Crear una rama para probar algo | `git switch -c nombre-de-la-rama` |
| Cambiar de rama | `git switch main` |
| Juntar una rama terminada en main | `git switch main` y luego `git merge nombre-de-la-rama` |

---

## 13. Glosario

| Término | Qué es |
|---|---|
| **Paso** | El dash. 14 studs, 2 cargas |
| **Desvío** | Pulsar Defender justo antes del golpe. **Perfecto** si es en los últimos 0,1 s: aturde al rival y abre el Contraataque |
| **Contrapaso** | Paso de lado (45° a 135°) justo antes de un golpe. Esquiva y abre el Contraataque |
| **Contraataque** | El golpe después de un desvío perfecto o de un Contrapaso: sale el doble de rápido y hace ×1,3 de daño |
| **Postura** | Se gasta al bloquear. Llena = guardia rota y aturdido |
| **Resonancia** | Recurso que se gana jugando bien y paga un Paso extra |
| **Hitstop** | El congelamiento breve al conectar un golpe |
| **Startup / active / recovery** | Preparación / impacto / recuperación de un golpe |
| **Hurtbox** | La zona donde un personaje recibe golpes (estándar en la rama de la auditoría) |
| **Cliente / servidor** | La pantalla de cada jugador / la computadora de Roblox que decide |
| **Remote** | Mensaje entre cliente y servidor (`RemoteEvent`) |
| **Studs** | La unidad de distancia de Roblox |
| **Greybox** | Mapa gris de pruebas, sin arte |
| **Rama (branch)** | Una línea de trabajo separada en Git |
