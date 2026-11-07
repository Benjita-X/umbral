# UMBRAL: Despierta tu Eco

Juego original de acción y combate para Roblox (PC, celular y mando).

## Estado
**Fases 1-3 consolidadas** (movimiento, combate corporal, defensa/Contrapaso/Resonancia) con validación en el servidor y pruebas automáticas. En la rama experimental: **5 Ecos con 20+ habilidades** (una tecla por habilidad, sinergias, combos aéreos), **espada**, patadas especiales, **gancho** y **postura enemiga con Golpe de Gracia**. Al apretar Play apareces en **La Grieta**, una mazmorra de muestra con ambiente; el laboratorio gris de pruebas, el Dojo, el Ring y la arena de duelo siguen en la superficie. Detalle en [docs/ESTADO.md](docs/ESTADO.md).

## Jugar (lo más fácil)
Doble clic en **`JUGAR.cmd`** (en esta carpeta): construye el juego con lo último y lo abre en Roblox Studio. Ahí presiona **F5**.

## Cómo se arma
El código vive en `src/` y el mapa en `tools/mapa.mjs`. Un solo comando genera el archivo que abre Roblox Studio:

```bash
node tools/construir.mjs
```

Resultado: `build/UMBRAL-Desarrollo.rbxlx`. Ábrelo con doble clic (o desde Studio) y presiona **F5** para jugar. Para ver el panel de números de depuración, pon `DebugHUD = true` en `MovementConfig.luau`.

> Los cambios hechos a mano dentro de Studio **no** vuelven a `src/`. Lo que vale es lo que está en los archivos; el `.rbxlx` se regenera.

## Pruebas automáticas
```bash
powershell -ExecutionPolicy Bypass -File tools/ejecutar-pruebas.ps1
```
Arma `build/UMBRAL-Pruebas.rbxlx`, instala el plugin local `UmbralPruebas` en Studio, abre una ventana nueva, entra en Play solo, ejecuta `tests/` y muestra los resultados (~1 minuto). Cierra solo la ventana que abrió.

- El plugin **solo actúa** en el lugar de pruebas (busca `ReplicatedStorage.UmbralPruebasAutomaticas`); en tus otros lugares no hace nada.
- Guarda lo que imprimen las pruebas con `plugin:SetSetting`, porque Studio no escribe los `print` en sus registros.
- Para quitarlo: borra `%LOCALAPPDATA%\Roblox\Plugins\UmbralPruebas.rbxmx`.

## Estructura (convenciones de Rojo)
| Carpeta | Va a | Tipo |
|---|---|---|
| `src/shared` | `ReplicatedStorage.Shared` | Configuración compartida |
| `src/server` | `ServerScriptService` | `*.server.luau` → Script |
| `src/client` | `StarterPlayer.StarterPlayerScripts` | `*.client.luau` → LocalScript, `*.luau` → ModuleScript |

Por usar las mismas convenciones de Rojo, se puede pasar a Rojo más adelante sin mover archivos.

## Controles
| Acción | PC | Celular | Mando |
|---|---|---|---|
| Moverse | WASD | Joystick | Stick izquierdo |
| Atacar (pulsar: combo · mantener: golpe fuerte) | Clic izquierdo | Botón ATACAR | X |
| Defender (mantener: guardia) | F | Botón DEFENDER | R1 / RB |
| Paso (dash) | Shift | Botón PASO | B |
| Saltar / doble salto | Espacio | Botón saltar | A |
| **Menú** (controles y ajustes) · *experimental* | M | Botón MENÚ | Select |

### Experimental (no está en `main`: rama `experimental/habilidades-v2`)
| Acción | PC | Celular | Mando |
|---|---|---|---|
| **Habilidad 1 · 2 · 3** del Eco puesto (salen al pulsar, sin quedarte quieto) | Z · X · C | Botones Z X C | Y · L1 · L2 |
| **Definitiva** (gasta Resonancia) | V | Botón V | R2 |
| **Cambiar de Eco** (Viento, Agua, Oscuridad, Fuego infernal, Trueno) | 1-5 o el menú | Menú | Cruceta izq./der. |
| **Arma**: Puños ↔ Espada | Q | Botón ARMA | Cruceta arriba |
| **Gancho** al orbe brillante o al enemigo marcado | E | Botón GANCHO | Cruceta abajo |
| **Cámara fija** (el personaje mira hacia la mira; viene activada en PC) / ratón libre | Ctrl | — | — |
| **Fijar enemigo** (la cámara lo sigue; tirón del ratón: cambiar de enemigo) | R | — | R3 |
| Golpe tras el Paso (patada voladora / estocada en carrera) | Atacar justo después de un Paso | | |
| Golpe en picada (cayendo desde alto) | Atacar en el aire, alto | | |
| Golpe de Gracia (enemigo QUEBRADO: postura llena) | Atacar cerca de él | | |
| Salto de pared (en el aire, junto a un muro) | Espacio | Botón saltar | A |
| Correr por la pared (en sprint, saltar junto a un muro avanzando a lo largo de él) | automático | automático | automático |

**Los 5 Ecos (20 habilidades + variantes):** cada uno pone sus 4 habilidades en Z X C V. Detalle en
[docs/HABILIDADES-V2.md](docs/HABILIDADES-V2.md).

| Eco | Z | X | C | V (definitiva) |
|---|---|---|---|---|
| Viento | Cuchilla (proyectil) | Ciclón (atrae) | Levante (lanza; C otra vez: subir) · aire: Descenso | Tempestad (tornado) |
| Agua | Burbuja (atrapa) | Oleaje (surfeas) | Géiser (lanza) | Diluvio (ola + cura) |
| Oscuridad | Paso Sombrío (Z otra vez: volver) | Daga Marcada (marca y recarga Z) | Fauces (inmoviliza) | Eclipse (te atraviesan) |
| Fuego infernal | Bola Infernal (explota y quema) | Estela Ardiente (rastro de fuego) | Puño Volcánico · aire: Meteoro | Infierno (anillo de fuego) |
| Trueno | Rayo (salta entre enemigos) | Relámpago (cruzas) | Pararrayos (tótem) | Juicio (rayos del cielo) |

**Combos:** una habilidad que conecta justo después de otra técnica en el mismo enemigo forma una **sinergia**
con nombre (más daño, más lanzamiento o aturdimiento, y Resonancia). Golpear en el aire te sostiene flotando
para seguir el combo.

Ayudas automáticas (experimentales): si te faltan unos pocos studs para llegar a un borde, el personaje sube solo; empujando contra un muro mientras caes, te deslizas despacio.

El clic derecho queda libre porque en Roblox gira la cámara.

## Documentos
- **[docs/COMO-JUGAR.md](docs/COMO-JUGAR.md): cómo jugar el prototipo, teclas, Ecos y combos para probar.**
- [docs/HABILIDADES-V2.md](docs/HABILIDADES-V2.md): diseño de las habilidades, armas y movimiento (y su estado).
- [docs/PRUEBAS-HABILIDADES.md](docs/PRUEBAS-HABILIDADES.md): pruebas automáticas y lista para una persona (habilidades, armas, cámara).
- **[docs/MANUAL.md](docs/MANUAL.md): cómo seguir por tu cuenta (empieza aquí).**
- [docs/ESTADO.md](docs/ESTADO.md): lo que llevamos y lo que vamos a usar.
- [docs/DECISIONES.md](docs/DECISIONES.md): qué se decidió y por qué.
- [docs/PRUEBAS-FASE1.md](docs/PRUEBAS-FASE1.md): lista para aprobar el movimiento.
- [docs/PRUEBAS-FASE2.md](docs/PRUEBAS-FASE2.md): lista para aprobar el combate.
- [docs/PRUEBAS-FASE3.md](docs/PRUEBAS-FASE3.md): pruebas de defensa (automáticas y humanas).
- [docs/ARQUITECTURA.md](docs/ARQUITECTURA.md): módulos, eventos cliente-servidor, flujo de ataque y defensa.
- [docs/AUDITORIA-FASE3.md](docs/AUDITORIA-FASE3.md): hallazgos de la auditoría y cómo se corrigieron.
- [docs/REVISION-CODEX.md](docs/REVISION-CODEX.md): canal de revisión cruzada con otro asistente.
- [docs/AUDITORIA-2-AMENAZA.md](docs/AUDITORIA-2-AMENAZA.md): segunda auditoría crítica y diseño de Amenaza Asimétrica (hipótesis, sin implementar).
- [docs/REFERENCIAS-JUEGOS.md](docs/REFERENCIAS-JUEGOS.md): qué aprender (y qué evitar) de otros juegos del género.
