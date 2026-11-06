# Estado del proyecto UMBRAL

Actualizado: 2026-11-06

## Lo que llevamos

### Fase 0 · Proyecto ✅
- Código en archivos (`src/`) con las convenciones de Rojo; un comando arma el lugar de Roblox (`tools/construir.mjs`).
- Documentos: README, registro de decisiones, lista de pruebas y este estado.

### Fase 1 · Laboratorio de movimiento ✅ en números · ⏳ falta aprobar la sensación
| Mecánica | Valor medido en Studio | Objetivo |
|---|---|---|
| Carrera | 22,0 studs/s | 22 |
| Sprint automático | entra a los 0,38-0,42 s, 34,0 studs/s | 0,4 s, 34 |
| Frenado | 0,10 s hasta detenerse | inmediato |
| Paso (suelo y aire) | 14,0 studs, pico 78 studs/s | 14 |
| Cargas de Paso | 2, la 1ª vuelve a los 0,80 s y todas a los 1,60 s | 2 · 0,8 s c/u |
| Salto | 8,62 studs | 8,5 |
| Doble salto | 15,50 studs en total | 15,5 |
| Caída | 0,25 s (subida 0,27 s) | más rápida que la subida |
| Paso aéreo | mantiene la altura (velocidad vertical 0,0) | sin caer |
| Coyote time y búfer de salto | funcionan | — |
| Reaparecer | todo sigue funcionando | — |
| A 30 FPS | Paso 14,0 · salto 8,62 | igual que a 60 FPS |

**23 de 23 pruebas automáticas superadas.** Lo que ninguna prueba automática puede medir es si *se siente* bien: eso lo decide una persona jugando ([PRUEBAS-FASE1.md](PRUEBAS-FASE1.md)).

### Fase 2 · Combate corporal ✅ en números · ⏳ falta aprobar la sensación
| Mecánica | Estado |
|---|---|
| Combo Jab → Directo → Patada (pulsar) | 16 de daño, confirmado por el servidor |
| Golpe fuerte (mantener), con carga | 10 a 18 de daño; sale solo al cargar del todo |
| Hitstop, chispas, onda, destello, estela, sonido, vibración, números de daño | funcionando |
| Encadenar solo al conectar; fallar alarga la recuperación | 0,18 s vs 0,32 s |
| Orientación asistida y acercamiento (iguales en todos los aparatos) | funcionando |
| Cancelar con Paso / salto la recuperación; amague cancelando la carga | funcionando |
| Guardia (mantener Defender) | funcionando; el desvío y la postura llegan en la Fase 3 |
| Daño validado en el servidor, con tolerancia al lag | 0 golpes legítimos rechazados; falsos, lejanos y repetidos rechazados |
| Muñecos de práctica en el Dojo (3 normales + 1 de aguante) | funcionando |
| Animaciones provisionales generadas por código | poses verificadas (10°-27° del frente) |

### Pruebas automáticas ✅ 55 de 55
`tools/ejecutar-pruebas.ps1` abre Studio, entra en Play solo, prueba movimiento y combate por código, mide y cierra (~1,5 minutos). Lo que no se puede medir en el momento queda "omitido" con su motivo.

## Lo que vamos a utilizar

### En uso hoy
| Herramienta | Para qué |
|---|---|
| **Roblox Studio** | Motor, editor y pruebas en modo Play |
| **Luau** | Lenguaje del juego |
| **Node.js** + `tools/construir.mjs` | Arma `.rbxlx` desde los archivos (sin programas extra) |
| **StudioTestService** + plugin local `UmbralPruebas` | Pruebas automáticas en Play |
| **PowerShell** (`tools/ejecutar-pruebas.ps1`) | Ejecuta las pruebas y muestra los resultados |
| Servicios de Roblox: `ContextActionService`, `UserInputService`, `LinearVelocity`, `Humanoid`, `RunService` | Controles y movimiento |

### Próximas fases
| Fase | Herramientas y servicios de Roblox |
|---|---|
| 2 · Combate corporal | **Editor de animaciones** de Studio, máquina de estados de combate, sonido (`SoundService`) |
| 3 · Defensa y Contrapaso | Mismo sistema de estados; ventanas de desvío medidas por pruebas automáticas |
| 4 · PvP seguro | `RemoteEvent`, validación en el servidor, **`ExecuteMultiplayerTestAsync`** para probar con 2-8 jugadores simulados y el simulador de red de Studio |
| 5 · Celular y rendimiento | **Emulador de dispositivos**, **MicroProfiler**, pruebas en un teléfono real |
| 6 · Prólogo "El Eco que fuiste" | Escenas cortas jugables, tutorial contextual |
| 7 · Ecos y rarezas | Pesos enteros sobre 10.000 (tabla V1.1), `HttpService:GenerateGUID` para cada Eco |
| 9 · Guardado | `DataStoreService` con `UpdateAsync`, versiones de esquema |
| 10 · Social y competitivo | `MemoryStoreService` (colas), `SocialService` (invitar amigos) |
| 12 · Negocio | `AnalyticsService` (embudos, retención D1/D7/D30), `MarketplaceService` + `ProcessReceipt` |
| Siempre | **Git** para versiones (pendiente de activar) |

## Pendiente
- Aprobar la sensación del movimiento y del combate jugando ([PRUEBAS-FASE1.md](PRUEBAS-FASE1.md), [PRUEBAS-FASE2.md](PRUEBAS-FASE2.md)).
- Probar los botones táctiles en el Emulador de dispositivos y en un celular real.
- Antes de publicar: subir las animaciones (las generadas solo funcionan en Studio) y los sonidos definitivos.
- Fase 4: caja de impacto estándar para que el tamaño del avatar no dé ventaja.
- Activar Git para guardar versiones.

## Siguiente: Fase 3 · Defensa y Contrapaso
Desvío al pulsar Defender en el momento justo, postura y ruptura de guardia, Contrapaso (Paso lateral durante un ataque enemigo) y Resonancia, con un muñeco que ataca de forma lenta y visible.
