# UMBRAL: Despierta tu Eco

Juego original de acción y combate para Roblox (PC, celular y mando).

## Estado
**Fases 1-3 consolidadas** (movimiento, combate corporal, defensa/Contrapaso/Resonancia) con validación en el servidor y pruebas automáticas. Al apretar Play apareces en **La Grieta**, una mazmorra de muestra con ambiente; el laboratorio gris de pruebas, el Dojo, el Ring y la arena de duelo siguen en la superficie. Detalle en [docs/ESTADO.md](docs/ESTADO.md).

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

El clic derecho queda libre porque en Roblox gira la cámara.

## Documentos
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
