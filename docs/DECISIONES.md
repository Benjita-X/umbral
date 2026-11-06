# Registro de decisiones

## 2026-11-06 · Fase 1

| # | Decisión | Por qué |
|---|---|---|
| 1 | Código en archivos (`src/`) y un generador propio del `.rbxlx`, con convenciones de Rojo | Sin instalar programas extra; todo queda versionable y se puede pasar a Rojo después |
| 2 | Una sola fuente de configuración: `MovementConfig.luau` | Ajustar el movimiento sin buscar números por todo el código |
| 3 | Humanoid estándar de Roblox + `LinearVelocity` solo durante el Paso | El Humanoid ya frena y acelera al instante; el Paso necesita velocidad exacta y distancia medible |
| 4 | Sprint automático tras 0,4 s moviéndose, sin botón | Menos botones en el celular (diseño de 5 acciones) |
| 5 | El Paso deja al jugador directo en sprint | Conservar el impulso: que la velocidad dependa de encadenar bien |
| 6 | 2 cargas de Paso que se recargan de a una (0,8 s) | Movimiento explosivo sin poder spamearlo |
| 7 | Paso aéreo: 1 por salto y mantiene la altura | Cruzar brechas y reposicionarse en el aire, con límite claro |
| 8 | Coyote time (0,1 s) y búfer de salto (0,12 s) | El salto responde aunque la pulsación sea un poco temprana o tardía |
| 9 | Gravedad 230 y caída 1,35 veces más rápida | Saltos secos, sin sensación de flotar |
| 10 | Doble salto que redirige el impulso hacia el joystick | Cambiar de dirección en el aire (el "impulso aéreo" del diseño) |
| 11 | Shift es el Paso; el bloqueo del mouse con Shift queda desactivado | Evitar el choque con el atajo de Roblox |
| 12 | El botón PASO del celular se ubica junto al de salto, medido en pantalla | Cómodo para el pulgar en cualquier tamaño de teléfono |
| 13 | FOV dinámico: +6° en sprint y +8° de golpe al iniciar un Paso | Sentir la velocidad sin marear |
| 14 | En Fase 1 el cliente controla su movimiento | Así funciona Roblox por defecto; la validación del servidor llega en la Fase 4 |
| 15 | El Paso termina por **distancia** (con tope de tiempo ×1,5), no por tiempo | Medido por tiempo recorría 12,6-13 studs y menos a bajos FPS; por distancia recorre 14,0 a 30 y a 60 FPS: justo entre PC y celular |
| 16 | Pruebas automáticas con `StudioTestService` y un plugin local | Comprobar cada cambio en ~1 minuto sin depender de nadie mirando la pantalla |
| 17 | El plugin guarda la salida con `plugin:SetSetting` | Studio no escribe los `print` de los scripts en sus registros |
| 18 | Cada ejecución de pruebas lleva un identificador único | Evita leer resultados viejos de una ejecución anterior |

## 2026-11-06 · Fase 2 (combate corporal)

| # | Decisión | Por qué |
|---|---|---|
| 19 | Todo el combate sale de `CombatConfig.luau`, compartido por cliente y servidor | Un solo lugar para equilibrar; animaciones, detección y validación usan los mismos tiempos |
| 20 | Cada golpe: preparación → impacto → recuperación | Legible para el rival y con consecuencias para quien ataca |
| 21 | Pulsar = combo Jab → Directo → Patada; mantener = golpe fuerte con carga (sale solo al cargar del todo) | Respeta las 5 acciones: sin botón extra de golpe fuerte |
| 22 | Encadenar solo si el golpe **conecta**; fallar alarga la recuperación ×1,35 y no se cancela | Premia acertar, castiga lanzar golpes al aire |
| 23 | Hitstop (congelamiento de 0,05-0,11 s al conectar) | Es lo que hace que un golpe "pese" |
| 24 | Orientación asistida (cono de 75°, 12 studs) y acercamiento de hasta 3,5 studs, **iguales en todos los aparatos** | En celular y mando no se puede apuntar fino; orienta pero no acierta por ti |
| 25 | Paso y salto cancelan la recuperación, nunca la preparación ni el impacto; el Paso también cancela la carga (amague) | Fluidez tipo Rock Lee con reglas claras |
| 26 | El cliente detecta el golpe y muestra el impacto al instante; el **servidor valida y aplica el daño** | Respuesta inmediata sin que el cliente decida el daño |
| 27 | Validación: ataque válido, cuerpos vivos, distancia posible, sin repetidos, máx. 14 golpes/s | Bloquea golpes falsos (probado con golpes inventados, lejanos y repetidos) |
| 28 | Tolerancia al lag: si un golpe parece lejano, el servidor reintenta 0,35 s con la posición actualizada | Sin esto, golpear justo después de un Paso con lag se rechazaba |
| 29 | Animaciones generadas por código (`AnimationLibrary`) con `RegisterKeyframeSequence` | Sin subir assets ni inventar IDs; quedan sincronizadas con los tiempos. **Solo funcionan en Studio** (ver pendientes) |
| 30 | Articulaciones `AnimationConstraint` en modo **cinemático** (`Rig.MakeKinematic`) | Las articulaciones físicas de Roblox no alcanzaban la pose a tiempo; para un futuro ragdoll basta desactivarlo |
| 31 | Sonidos provisionales con los de Studio (`rbxasset://sounds/...`) afinados de tono | No hay sonidos de golpes incluidos; los definitivos se suben y se cambian en `EffectsController` |
| 32 | Vibración de cámara con `Humanoid.CameraOffset` y ajuste de accesibilidad (`Feedback.ScreenShake`) | No pelea con la cámara de Roblox y se puede apagar |
| 33 | Muñecos R15 que no mueren (estado Dead desactivado), se curan y vuelven a su sitio | Practicar combos sin interrupciones |
| 34 | Pruebas que no se pueden medir (ventana sin dibujar) quedan **omitidas** con motivo, no aprobadas | Un resultado honesto: nada pasa "en verde" sin medirse |

## Pendiente de decidir
- ¿La experiencia será de tu cuenta o de un grupo? (importa si después entran socios)
- **Antes de publicar:** subir las animaciones a Roblox (o reemplazarlas por otras de un animador) y poner sus IDs en `CombatConfig.AnimationIds`; las generadas por código no funcionan fuera de Studio.
- **Fase 4:** tamaño de avatar justo en PvP. Un avatar chico tiene menos superficie para recibir golpes; habrá que usar una caja de impacto estándar o fijar la escala del cuerpo.
- Sonidos definitivos de golpes (subir audio propio o con licencia).
