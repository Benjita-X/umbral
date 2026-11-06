# Referencias de diseño: Sword Blox Online: Rebirth y Blox Fruits

Fecha: 2026-11-06. **Fuente:** conocimiento general de cómo funcionan estos juegos (no se jugaron ni se revisaron sus versiones actuales en esta sesión; los detalles cambian con sus actualizaciones). Sirve para entender **por qué enganchan** y qué principios adaptar. **Regla:** se toman principios de diseño, nunca nombres, personajes, arte, textos ni sistemas copiados tal cual.

## 1. Desglose

### Sword Blox Online: Rebirth (SBO:R)
| Pilar | Cómo funciona (en general) |
|---|---|
| Estructura | Una torre de **pisos**: cada piso es una zona con monstruos, misiones y un **jefe** que abre el siguiente |
| Bucle | Matar monstruos → experiencia y botín → subir de nivel → mejor equipo → piso siguiente |
| Combate | Espadas de distintos tipos, golpes con clic y **habilidades de espada** con enfriamiento; monstruos con ataques avisados |
| Progresión | Nivel, equipo (rareza, mejoras), habilidades por tipo de arma |
| Social | Grupos para jefes, comercio, gremios |
| Atractivo | Fantasía de "escalar la torre" con amigos; cada jefe es un hito visible |

### Blox Fruits (BF)
| Pilar | Cómo funciona (en general) |
|---|---|
| Estructura | Mundo de **islas** agrupadas en "mares"; cada isla tiene rango de nivel, misiones y jefe |
| Bucle | Misión de NPC (matar N enemigos) → experiencia y dinero → subir de nivel → **repartir puntos** de atributos → isla siguiente |
| Combate | 4 estilos (cuerpo a cuerpo, espada, arma, fruta) con **4-5 habilidades por tecla** (Z X C V F), cada una con enfriamiento; mucho daño en área y efectos vistosos |
| Poder especial | Las **frutas**: un set de habilidades con rareza (común → mítica), se consiguen por azar, compra o comercio, y se pueden despertar |
| Maestría | Usar un arma o fruta sube su **maestría** y desbloquea habilidades nuevas |
| Movilidad | Dash corto, salto aéreo extra, habilidades que también mueven |
| Defensa | Una "esquiva automática" limitada que se mejora y un recubrimiento que da daño o protección |
| Social y competitivo | PvP con recompensa (bounty), tripulaciones, comercio de frutas, eventos (incursiones, jefes de mar) |
| Atractivo | Progresión constante (subes de nivel muy seguido), **coleccionar frutas raras**, poder cada vez más vistoso, siempre hay un objetivo siguiente |

## 2. Por qué enganchan (lo que sí vale la pena adaptar)
1. **Siempre hay un siguiente objetivo visible:** la próxima isla o piso, el próximo jefe, la próxima habilidad.
2. **Progresión densa:** algo mejora cada pocos minutos (nivel, maestría, botín).
3. **Fantasía de poder que crece:** al principio golpes simples; después habilidades enormes.
4. **Colección con rareza:** la emoción de que te toque algo raro, y poder mostrarlo.
5. **Jefes como hitos:** eventos que se recuerdan y se hacen en grupo.
6. **Movilidad divertida por sí misma:** moverse rápido ya es entretenido.
7. **Acceso inmediato:** a los pocos segundos de entrar ya estás peleando.

## 3. Auditoría: lo que hacen mal (y UMBRAL debe evitar)
| Problema | En qué se nota | Cómo lo evita UMBRAL |
|---|---|---|
| Combate poco profundo | Gana quien tira habilidades primero o huye y vuelve (hit-and-run); poca lectura del rival | Desvío, Contrapaso, guardia y postura: **gana quien lee**, no quien aprieta más (ya probado con los bots) |
| Poder comprado o por azar en PvP | Una fruta mítica o un pase de pago pesan más que la habilidad | Ecos y rarezas **sin ventaja en PvP** (rareza = estilo y cosmético; decisión ya tomada en el plan) |
| Grind repetitivo | "Mata 8 iguales" durante horas | Misiones con variación: enemigos con patrones distintos, desafíos de técnica, jefes que exigen leer |
| Habilidades con poco aviso | Ataques en área instantáneos difíciles de leer | Todo ataque tiene preparación legible (MoveSchema obliga startup > 0) |
| Defensa automática | Esquivas pasivas que no dependen del jugador | Las esquivas son **acciones** (Contrapaso, desvío perfecto) |
| Hitboxes inconsistentes y el cliente decidiendo | Golpes que "no entran" o que entran de lejos | Hurtbox estándar y servidor con autoridad (auditoría de la Fase 3) |
| Diferencias entre PC y celular | Más teclas en PC = más opciones | 5 acciones en todas las plataformas; las técnicas salen del contexto |
| Exploits de autofarm | Bots que farmean solos | Validación en el servidor + recompensas que exigen técnica |

## 4. Qué se toma para UMBRAL (adaptado y propio)
| Principio | Versión UMBRAL | Fase |
|---|---|---|
| Torre de pisos / islas por rango | **Grietas** por profundidad: cada Grieta es una mazmorra con salas, enemigos propios y un Guardián que abre la siguiente (La Grieta de muestra ya es el prototipo) | 8 |
| Habilidades por tecla | Botón **Eco**: cada Eco da un set corto de técnicas (pulsar, mantener, en el aire, tras un Paso) que salen del contexto, sin 5 teclas | 7 |
| Maestría | Usar un Eco sube su resonancia personal y desbloquea variantes de sus técnicas (más estilo, no más daño en PvP) | 7 |
| Colección con rareza | Ecos con rarezas (pesos ya definidos) que cambian el **aspecto y el estilo**, no el poder competitivo | 7 |
| Jefes memorables | Guardianes con fases, patrones que se aprenden y ventanas de Contraataque claras | 8 |
| Movilidad divertida | Ya está: Paso de 14, doble salto, Paso aéreo; más adelante correr por paredes | 1 (hecho) |
| Siempre un objetivo siguiente | Mapa de Grietas, misiones cortas en Alba, desafíos de técnica ("desvía 5 perfectos seguidos") | 6-8 |
| Entrar y pelear ya | Al apretar Play estás en la Grieta en 15 segundos | 6 (ya se cumple en desarrollo) |

## 5. Siguiente paso concreto sugerido
Antes de copiar la amplitud de estos juegos, hacer **profunda una sola cosa**: que pelear en La Grieta sea divertido (Fase 3, validación humana). Después:
1. **Enemigos comunes** en las salas (versiones simples del compañero, 2-3 tipos) para que la mazmorra no esté vacía hasta el Guardián.
2. **Un primer Eco jugable** (botón Eco con 2-3 técnicas) para probar la fantasía de poder.
3. **Recompensa al vencer al Guardián** (Resonancia, un fragmento de Eco) para cerrar el bucle.
