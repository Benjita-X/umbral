# Mapa completo del juego: todo lo que UMBRAL necesita

Fecha: 2026-11-07. Visión de conjunto de un juego de acción y combate en Roblox como UMBRAL, con el estado real de cada parte y su prioridad. Sirve para no olvidar nada y para decidir qué sigue.

Estado: ✅ hecho y probado · 🧪 experimental (rama aparte, probado) · 🟡 a medias · ⬜ falta · 🔒 bloqueado (necesita algo externo).
Prioridad: **P0** imprescindible para una primera versión jugable con gente · **P1** necesario para lanzar · **P2** después del lanzamiento.

## 1. Núcleo jugable (lo que se siente en las manos)
| Parte | Estado | Prioridad | Nota |
|---|---|---|---|
| Movimiento: carrera, sprint, Paso, salto, doble salto, coyote, búfer | ✅ | P0 | Falta la aprobación de una persona |
| Paredes: salto, deslizamiento, carrera, agarre de borde | 🧪 | P0 | `experimental/movilidad` |
| Combate: combo, golpe fuerte, guardia, desvío, Contrapaso, Contraataque | ✅ | P0 | Validación humana pendiente |
| Movilidad al atacar (80 %, cancelar con Paso o salto) | ✅ | P0 | |
| Aguante (anticadena de aturdimientos) | 🧪 | P0 | |
| **Ecos: poderes del jugador (botón Eco)** | 🧪 primer Eco (Eco del Viento) | **P0** | Ráfaga y Descenso, rama `experimental/eco`; faltan más Ecos, maestría y rarezas |
| Animaciones definitivas (subidas a Roblox) | ⬜ | P1 | Las de ahora solo funcionan en Studio |
| Sonido de golpes, pasos y ambiente | ⬜ | P1 | Hay que subir audio propio o con licencia |
| Celular: botones cómodos y probados en un teléfono | 🟡 | P0 | Funcionan en el emulador; falta un teléfono real |

## 2. Enemigos y desafío
| Parte | Estado | Prioridad |
|---|---|---|
| Compañero de entrenamiento con perfiles | ✅ | P0 |
| Enemigos comunes: Latido, Centinela, Gemelos, Acechador | 🧪 | P0 |
| Guardián (jefe) con fases | 🟡 (una fase) | P1 |
| Amenaza Asimétrica, Instinto del Último Recuerdo | ⬜ (diseñado) | P1 |
| Variedad de jefes por Grieta | ⬜ | P1 |
| IA que duerme lejos del jugador (rendimiento) | 🧪 | P0 |

## 3. Bucle principal y progresión
El bucle de un juego así: **entrar → pelear → ganar algo → hacerse más fuerte o más vistoso → un objetivo nuevo**.
| Parte | Estado | Prioridad | Nota |
|---|---|---|---|
| Recompensa al vencer (Resonancia) | 🧪 | P0 | |
| Niveles y experiencia | ⬜ (fórmulas en hipótesis) | P1 | Ver AUDITORIA-2-AMENAZA §D |
| Maestría por Eco (técnicas nuevas al usarlo) | ⬜ | P1 | |
| Botín: fragmentos de Eco, materiales | ⬜ | P1 | |
| Misiones cortas y desafíos de técnica | ⬜ | P1 | "Desvía 5 perfectos seguidos" |
| Logros e insignias de Roblox | ⬜ | P2 | |

## 4. Mundo
| Parte | Estado | Prioridad |
|---|---|---|
| La Grieta de muestra (mazmorra con ambiente) | ✅ | P0 |
| Más Grietas con profundidad creciente | ⬜ | P1 |
| Alba (zona central social), el Faro | ⬜ | P1 |
| Arte definitivo (modelos, texturas) | ⬜ | P1 |
| Teletransporte entre zonas | ⬜ | P1 |

## 5. Interfaz y experiencia
| Parte | Estado | Prioridad | Nota |
|---|---|---|---|
| Barras de vida, postura y Resonancia; avisos | ✅ | P0 | |
| **Menú de pausa y ajustes** (vibración, destellos, sensibilidad) | ⬜ | **P0** | Los ajustes existen en la configuración, falta la pantalla |
| Pantalla de inicio | ⬜ | P1 | |
| Tutorial integrado (aprender jugando) | ⬜ | P0 | Los carteles de la Grieta son un primer paso |
| Accesibilidad: daltonismo, tamaño de texto | 🟡 | P1 | Los avisos ya no dependen solo del color |

## 6. Datos y servicios
| Parte | Estado | Prioridad | Nota |
|---|---|---|---|
| Guardado del progreso (DataStore con UpdateAsync y versiones) | ⬜ | P0 | 🔒 Probarlo exige publicar el lugar y activar el acceso a la API en Studio (lo decide el dueño) |
| Métricas (retención, embudos) | ⬜ | P1 | |
| Anti-trampas: validación en el servidor | ✅ | P0 | Movimiento: detecta, no impide (ver auditoría) |

## 7. Multijugador
| Parte | Estado | Prioridad |
|---|---|---|
| Varios jugadores en la misma Grieta (cooperativo) | ⬜ | P1 |
| PvP 1v1 en la arena (Fase 4) | ⬜ (arena lista) | P1 |
| Clasificatorio con estadísticas normalizadas | ⬜ | P2 |
| Grupos, invitar amigos | ⬜ | P2 |

## 8. Negocio (siempre sin ventaja pagada en PvP)
| Parte | Estado | Prioridad |
|---|---|---|
| Cosméticos (auras, estelas, aspectos de Eco) | ⬜ | P2 |
| Pase de temporada | ⬜ | P2 |
| Compras seguras (ProcessReceipt idempotente) | ⬜ | P2 |

## 9. Orden recomendado (lo que sigue)
1. ~~Primer Eco jugable~~ (hecho en `experimental/eco`, 7 pruebas).
2. **Menú de pausa con ajustes**: necesario para que cualquiera juegue cómodo.
3. **Tutorial integrado** en la entrada de la Grieta.
4. Validación humana de todo lo experimental, para integrarlo a `main`.
5. Niveles y botín (con las fórmulas de la auditoría), luego guardado.
6. Cooperativo en la Grieta, después PvP en la arena.
7. Alba, más Grietas, arte y sonido definitivos.
