# Pruebas de la Fase 3: defensa, Contrapaso y Resonancia

## Automáticas
`powershell -ExecutionPolicy Bypass -File tools/ejecutar-pruebas.ps1` (cierra antes cualquier otra ventana de Roblox Studio).

Las suites, por tipo:
| Tipo | Suite | Qué cubre |
|---|---|---|
| A. Reglas (unitarias) | `Auditoria` | Esquema de movimientos, detector de esquemas rotos, geometría de la Hurtbox (frente, lados, espalda, alturas de avatar, giros, alcance fijo) |
| B. Integración cliente-servidor | `Combate`, `Defensa` | Golpes confirmados, combo, golpe fuerte, desvío, guardia, ruptura, barrido, Contrapaso, esquiva, interrupción, Contraataque, Resonancia, baja tasa de cuadros |
| C. Adversarial | `Combate` (§9), `Defensa` (§11), `Auditoria`, `Habilidad` | Golpes lejanos, inventados, repetidos, sin inicio, fuera de orden, demasiado rápidos, hora manipulada, posición falsa; bots Lector / Machacador / Solo guardia / Reloj fijo |
| D. Rendimiento | — | **No ejecutado.** Pendiente: MicroProfiler con 8 jugadores y medir el costo de los historiales |
| E. Humanas | este documento | **Pendientes** |

Resultados de la última ejecución: ver `ESTADO.md`.

### No ejecutado todavía (no cuenta como aprobado)
- Red adversa simulada (150 ms, jitter, 1 % de pérdida) en Studio.
- Avatares reales de escala 0,7 y 1,3 (la regla geométrica sí está probada).
- Dos atacantes simultáneos y desconexiones (`ExecuteMultiplayerTestAsync`).
- Emulador de dispositivos (botones táctiles) y un teléfono real.

## Humanas (las decide una persona jugando)
Abre `build/UMBRAL-Desarrollo.rbxlx`, F5, y ve al **Ring** (atrás a la izquierda).

| # | Qué probar | Cómo | Aprobado si… | ✔ |
|---|---|---|---|---|
| H1 | Leer el Golpe | Mira la preparación sin pulsar nada 5 veces | Sabes cuándo va a pegar antes de que pegue | ☐ |
| H2 | Leer el Rápido y el Pesado | Perfil técnico (`Perfil = "tecnico"` en el modelo) | Distingues los tres golpes por pose/color/sonido, no solo por color | ☐ |
| H3 | Desvío perfecto | Pulsa F justo antes del impacto | Se siente rápido y satisfactorio; ≥ 7 de 10 a propósito tras practicar | ☐ |
| H4 | Machacar no sirve | Pulsa F sin parar | Notas que te pegan más que leyendo | ☐ |
| H5 | Contrapaso | Shift de lado justo antes del Golpe | Se siente como esquivar con intención, no como suerte; el Contraataque te devuelve al rival | ☐ |
| H6 | Barrido | Salta o sal del anillo | El anillo se entiende; saltar a tiempo es posible | ☐ |
| H7 | Retrasos y amague | Perfil técnico | Te engañan a veces, pero sientes que podrías haberlo leído | ☐ |
| H8 | Guardia | Mantén F contra varios Golpes | La ruptura llega y se entiende por qué (barra de postura) | ☐ |
| H9 | Hitstop | Golpea al compañero | El golpe pesa, sin sentirse lento | ☐ |
| H10 | Con lag | Studio → Configuración → Red: 150 ms | Los desvíos siguen siendo justos (sin perder los correctos) | ☐ |
| H11 | Celular | Emulador de dispositivos y un teléfono | Los botones se alcanzan y responden igual | ☐ |
| H12 | Accesibilidad | `Feedback.ScreenShake = 0`, `Flashes = false` | Se puede jugar sin vibración ni destellos | ☐ |

Hasta que estos puntos estén marcados, la Fase 3 queda **PROBADA** pero **no VALIDADA**.
