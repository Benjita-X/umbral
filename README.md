# UMBRAL: Despierta tu Eco

Juego original de acción y combate para Roblox (PC, celular y mando).

## Estado
**Fase 2: combate corporal.** Movimiento (Fase 1) + combo de 3 golpes, golpe fuerte con carga, guardia, muñecos de práctica en el Dojo y daño validado en el servidor. Sin Ecos ni historia todavía.

## Cómo se arma
El código vive en `src/` y el mapa en `tools/mapa.mjs`. Un solo comando genera el archivo que abre Roblox Studio:

```bash
node tools/construir.mjs
```

Resultado: `build/UMBRAL-Desarrollo.rbxlx`. Ábrelo con doble clic (o desde Studio) y presiona **F5** para jugar.

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
- [docs/ESTADO.md](docs/ESTADO.md): lo que llevamos y lo que vamos a usar.
- [docs/DECISIONES.md](docs/DECISIONES.md): qué se decidió y por qué.
- [docs/PRUEBAS-FASE1.md](docs/PRUEBAS-FASE1.md): lista para aprobar el movimiento.
- [docs/PRUEBAS-FASE2.md](docs/PRUEBAS-FASE2.md): lista para aprobar el combate.
