# Habilidades v2: Ecos, poderes, armas y movimiento (EXPERIMENTAL)

Rama: `experimental/habilidades-v2` (sale de `experimental/eco`). Pedido del jugador tras probar el prototipo:
el sistema viejo (un botón contextual que cuesta Resonancia) era básico, raro y "a veces no salía". Se pidió un
sistema al estilo de los juegos de peleas de Roblox: **cada habilidad en su tecla**, combos combinando
habilidades, mínimo **20 poderes**, kits de **viento, agua, oscuridad, fuego infernal** y más, **armas
(espada)**, **patadas**, y un movimiento que dé ganas de jugar (referencias de sensación: Sekiro, Elden Ring).
Las habilidades son ORIGINALES: se toman ideas de mecánicas comunes del género (proyectiles que rebotan,
saltos de ida y vuelta, torretas, marcas, muros), nunca nombres, personajes ni aspecto de otro juego.

## Por qué fallaba el sistema viejo (causas)
1. Costaba Resonancia desde 0: al empezar no salía nada y no había aviso claro.
2. Un solo botón con significado según el contexto: tocar = Ráfaga **al soltar**, mantener = Torbellino,
   tras un Paso = Estela (ventana de 0,45 s), en el aire = Descenso. Era fácil sacar otra cosa o nada.
3. Sin enfriamientos visibles ni respuesta al pulsar cuando no estaba lista.
4. Cliente y servidor podían discrepar en "suelo o aire" justo en el límite → rechazo silencioso.

## Reglas del sistema nuevo
- **Una tecla por habilidad**: Z, X, C, V (mando: Y, L1, L2, R2; celular: un botón por habilidad).
- **Sale al pulsar**, al instante, sin quedarte quieto (solo la parte de arriba del cuerpo anima; las piernas
  siguen corriendo). Cortan la preparación y la recuperación de tus golpes.
- **Básicas (Z, X, C) sin costo**: solo enfriamiento. **Definitiva (V)** gasta Resonancia (se carga peleando:
  golpes, defensas, sinergias).
- **Barra de habilidades** con tecla, nombre, enfriamiento que baja y número de segundos; destello al quedar
  lista; sacudida roja si pulsas sin estar lista; V muestra la Resonancia que falta.
- **Variantes en el aire** donde tiene sentido (C del Viento = Descenso, C del Fuego = Meteoro).
- **Sinergias**: una habilidad que conecta poco después de otra técnica (o de un golpe concreto del combo) en el
  MISMO enemigo forma un combo con nombre (más daño / lanzamiento / aturdimiento) y da Resonancia.
- **Combos aéreos**: un enemigo lanzado queda "en el aire" (juggle) y cada golpe lo sostiene flotando; quien
  golpea en el aire flota un instante (AirStall). Ascenso (C otra vez tras Levante) sube tras el lanzado.
- **Servidor con autoridad**: el cliente pide (hora, posición, apuntado); el servidor valida hora,
  aturdimiento, enfriamiento por tecla (con la hora validada), Resonancia, posición confirmada, suelo/aire con
  margen, y calcula impactos (historial observado) y efectos. Los proyectiles los simula el servidor y se frenan
  en las paredes. Nada mete a un enemigo dentro de una pared (barridos con esfera antes de arrastrar).
- **Apuntado**: hacia el ratón (PC) con ayuda hacia el enemigo cercano a la mira; "al frente" en mando,
  celular y como ajuste del menú (las pruebas usan "al frente").

## Los Ecos (5 kits · 20 habilidades + variantes)
Se elige el Eco en el menú (M) o con las teclas 1-5. Cambiar de Eco pone las 4 habilidades en un enfriamiento
corto (no se puede encadenar definitivas cambiando).

### 1. Viento — control y combos aéreos (HECHO en servidor)
- Z **Cuchilla**: proyectil que atraviesa enemigos y se frena en paredes; aturde 0,45 s.
- X **Ciclón**: atrae a los cercanos frente a ti y aturde. Aire: los sube hasta ti y flotan.
- C **Levante**: lanza al aire ≈10 studs. C otra vez: **Ascenso** (subes tras él). Aire: **Descenso**
  (picada; estampa a los que flotan cerca; onda al aterrizar que rebota).
- V **Tempestad**: tornado que atrae, sostiene y golpea 2,2 s; estalla al final.

### 2. Agua — fluir, atrapar, sostener la vida
- Z **Burbuja**: proyectil lento; atrapa al primer enemigo en una burbuja que flota 1,2 s (combo).
- X **Oleaje**: surfeas 16 studs sobre una ola; arrastras a los enemigos del camino y los sueltas al final.
- C **Géiser**: círculo en el punto apuntado; 0,45 s después erupción que lanza.
- V **Diluvio**: gran ola frontal que barre y empuja + lluvia que te cura 4 s.

### 3. Oscuridad — asesino, saltos y marcas
- Z **Paso Sombrío**: te teletransportas hasta 16 studs (nunca a través de paredes) y dejas tu sombra;
  Z otra vez en 2,5 s: vuelves a la sombra. Aparecer a la espalda: el siguiente golpe es por la espalda.
- X **Daga Marcada**: proyectil; marca 4 s. Golpear a un marcado lo detona (daño extra) y recarga Z.
- C **Fauces**: fauces de sombra en un cono al frente que inmovilizan 1,2 s (y bajan a los que flotan).
- V **Eclipse**: 4 s de forma sombría: los ataques enemigos te atraviesan, corres más y cada golpe tuyo
  suma un corte de sombra; termina con un estallido.

### 4. Fuego infernal — daño sostenido y explosiones
- Z **Bola Infernal**: proyectil que explota al chocar (área) y deja suelo ardiente 2 s (quemadura).
- X **Estela Ardiente**: Paso de fuego de 14 studs que deja un rastro que quema.
- C **Puño Volcánico**: embestida corta con puñetazo que explota (empuje fuerte + quemadura).
  Aire: **Meteoro** (picada en diagonal hacia donde apuntas; cráter ardiente).
- V **Infierno**: anillo de fuego de 4 s a tu alrededor: quema a los de adentro, y tus golpes arden (+30 %).

### 5. Trueno — velocidad, cadenas y torretas
- Z **Rayo en Cadena**: rayo instantáneo al enemigo apuntado que salta a 2 más cercanos.
- X **Relámpago**: te vuelves rayo y cruzas 16 studs, dañando y aturdiendo a todos en el camino.
- C **Pararrayos**: tótem en el punto apuntado que electrocuta cada 0,5 s durante 4 s.
- V **Juicio de Tormenta**: 6 rayos sobre enemigos a tu alrededor en 1,5 s.

## Armas y patadas
- **Q** cambia de arma: **Puños** (Jab, Directo, Patada) ↔ **Espada** (Tajo, Revés, Estocada; más alcance y
  daño, algo más lenta; golpe fuerte cargado propio). Modelo de espada simple hecho con piezas.
- **Patada voladora** (Puños) / **Estocada en carrera** (Espada): atacar justo después de un Paso.
- **Patada en picada** / **Clavada**: atacar cayendo desde altura → picada con onda al aterrizar.

## Movimiento al estilo Sekiro / Elden Ring
- **Gancho (E)**: te engancha a puntos de anclaje del mapa (marcas PuntoGancho) o a un enemigo y te lleva
  hasta allí en el aire. Anclajes sobre el Abismo y en el Ascenso de la Grieta.
- **Postura enemiga y Golpe de Gracia**: desvíos y golpes llenan la postura del enemigo; al romperse queda
  quebrado y atacar cerca hace un Golpe de Gracia (gran daño, cámara y destello).
- Ataques en caída, ataques tras el Paso, combos aéreos con AirStall (arriba).

## Estado (2026-11-07, noche)
| Parte | Estado | Pruebas automáticas |
|---|---|---|
| Sistema base: teclas, barra, enfriamientos, cancelar golpes, sinergias, combos aéreos | ✔ | suite `Eco` |
| Viento (Cuchilla, Ciclón, Levante/Ascenso/Descenso, Tempestad) | ✔ | suite `Eco` |
| Agua, Oscuridad, Fuego infernal, Trueno (16 habilidades + Meteoro + vuelta a la sombra) | ✔ | suite `Ecos` |
| Elegir Eco (1-5, menú) y rechazo de habilidades de otro Eco | ✔ | suites `Eco` y `Ecos` |
| Espada (combo, golpe cargado, estocada en carrera, clavada) y patadas especiales | ✔ | suite `Armas` |
| Gancho (E) a orbes y a enemigos | ✔ | suite `GanchoYGracia` |
| Postura enemiga, QUEBRADO y Golpe de Gracia | ✔ | suite `GanchoYGracia` |
| Cámara fija (Ctrl) con mira y fijar enemigo (R) | ✔ | suite `GanchoYGracia` (fijar) |
| Efectos de movimiento (polvo al caer, silueta del Paso), sonidos de agua y viento, destello de definitivas | ✔ | — |
| Tutorial (pasos de habilidades, sinergia y espada), menú (Ecos, apuntado, cámara), README, DECISIONES #73-#93 | ✔ | — |

## Pendiente / ideas siguientes
- Probar a mano la sensación (apuntado con ratón, tiempos de enfriamiento, daño) y ajustar números en
  `CombatConfig.Eco.Skills`.
- Animaciones definitivas (un animador) y sonidos propios: lo de ahora es provisional, hecho por código.
- PvP de las habilidades (hoy solo afectan a muñecos y enemigos).
- Más armas (lanza, guadaña) con el mismo esquema de `CombatConfig.Weapons`.
