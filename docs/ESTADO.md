# Estado del proyecto UMBRAL

Actualizado: 2026-11-06 (consolidación de las fases 1-3).

Leyenda: **IMPLEMENTADO** (hay código) · **INTEGRADO** (conectado) · **PROBADO** (una prueba concreta pasó) · **VALIDADO** (cumple criterios, también humanos) · **PENDIENTE** · **BLOQUEADO**.

## Resumen
| Parte | Estado |
|---|---|
| Fase 1 · Movimiento | PROBADO (pruebas automáticas). Sensación: PENDIENTE de una persona ([PRUEBAS-FASE1.md](PRUEBAS-FASE1.md)) |
| Fase 2 · Combate corporal | PROBADO. Sensación: PENDIENTE ([PRUEBAS-FASE2.md](PRUEBAS-FASE2.md)) |
| Fase 3 · Defensa, Contrapaso, Resonancia | INTEGRADO y PROBADO salvo los defectos conocidos de abajo. Sensación y legibilidad: PENDIENTE ([PRUEBAS-FASE3.md](PRUEBAS-FASE3.md)) |
| Auditoría (`auditoria-fase3`) | INTEGRADA en `main` con correcciones ([AUDITORIA-FASE3.md](AUDITORIA-FASE3.md)) |
| Compensación de latencia | AUDITADA y corregida; red adversa simulada PENDIENTE |
| Integridad del servidor (combo, golpes, defensas, posiciones, Resonancia) | REVISADA; pruebas adversariales PROBADAS |
| Arena gris de duelo | IMPLEMENTADA (`tools/mapa.mjs`, al final de la línea amarilla). Duelos PvP: PENDIENTE (Fase 4) |
| La Grieta (mazmorra de muestra con ambiente) | IMPLEMENTADA solo en el lugar de desarrollo (`tools/mazmorra.mjs`). Revisada a ojo en Studio; no es el mundo definitivo |
| PvP real entre jugadores | PENDIENTE (Fase 4) |
| Celular físico | PENDIENTE |
| Mundo, Ecos, tienda, guardado | PENDIENTE a propósito |

## Pruebas automáticas
Línea base de `main` antes de la consolidación (ejecución independiente): **79 de 82** (falla Contraataque vuelve al rival, El barrido no admite Contrapaso, Esquiva precisa; "Saltar el barrido" es intermitente).

Después de la consolidación: **95 pruebas** (13 nuevas). Resultado de la última ejecución: ver la sección "Última ejecución" al final.

## Defectos conocidos
| Defecto | Estado |
|---|---|
| "Contraataque vuelve al rival" falla (ya fallaba en la línea base): tras el Contrapaso el Contraataque no conecta en la prueba | PENDIENTE: investigar el acercamiento del Contraataque (`CounterTargetRange`/`CounterMaxLunge`) contra el compañero que vuelve a su sitio |
| Pruebas de defensa con resultados intermitentes (el compañero a veces tarda en volver a atacar) | MITIGADO (deja de esperar si el jugador le bloquea el camino); vigilar |
| El compañero empieza a atacar a 12 studs pero su golpe llega a ~10 | PENDIENTE de diseño: acercarse antes de atacar o bajar `AggroRange` |
| Animaciones solo funcionan en Studio (generadas por código) | PENDIENTE antes de publicar |
| Sonidos provisionales | PENDIENTE antes de publicar |

## Lo que vamos a utilizar
| Herramienta | Para qué |
|---|---|
| Roblox Studio | Motor, editor y pruebas en Play |
| Luau | Lenguaje del juego |
| Node.js + `tools/construir.mjs` | Arma los `.rbxlx` desde los archivos |
| StudioTestService + plugin `UmbralPruebas` | Pruebas automáticas |
| PowerShell (`tools/ejecutar-pruebas.ps1`) | Ejecuta las pruebas |
| Git | Versiones (etiquetas `respaldo/*` como puntos de recuperación) |

## Siguiente
1. Una persona juega y marca las listas humanas (fases 1-3).
2. Arreglar "Contraataque vuelve al rival" y el alcance de ataque del compañero.
3. Red adversa (150 ms, 1 % de pérdida), avatares 0,7 / 1,3 reales y `ExecuteMultiplayerTestAsync`.
4. Fase 4: PvP 1v1 en la arena con la misma defensa del servidor.

## Última ejecución (2026-11-07, Studio sin otras ventanas abiertas)
**95 superadas · 0 fallidas · 0 omitidas · de 95.** No ejecutadas todavía: red adversa simulada, avatares reales 0,7/1,3, multijugador, rendimiento (ver PRUEBAS-FASE3.md). La sensación sigue PENDIENTE de una persona.

Cómo se cerraron las últimas fallas (ver DECISIONES #48-#53 y el historial de Git):
| Falla | Causa real | Corrección |
|---|---|---|
| Contraataque vuelve al rival | El avance llegaba al alcance justo al cerrarse la ventana activa | El avance llega a mitad de la ventana; la preparación se alarga si el tramo es largo |
| El compañero se quedaba quieto tras el Pesado | Chocaba con el jugador a ~75 studs/s y la física lo sacaba disparado | Luchadores sin colisión entre sí; muñecos sin tropiezos |
| Golpes legítimos rechazados junto a teletransportes | Mezcla de posiciones de antes y después del salto, y pruebas que teletransportaban a mitad de golpe | Corte de muestras en el teletransporte, historial observado como respaldo, y las pruebas esperan a que termine el golpe |
