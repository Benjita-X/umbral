# Cómo jugar el prototipo (rama `experimental/habilidades-v2`)

## Lo último (pulido)
- **Las habilidades se ven mucho mejor**: arcos de corte en media luna con filo blanco, destellos en estrella y
  rayas al golpear, ondas de choque, estelas de color en manos y pies, partículas de cada elemento (gotas, brasas,
  humo, chispas) y un "cuadro de impacto" en los combos con nombre y las definitivas. La espada se tiñe del Eco y
  suelta su elemento al cortar.
- **La Grieta con más vida**: más luz y color, piedra con tonos, cristales en racimos, braseros, estandartes, runas
  que brillan, polvo de luz flotando y niebla azul en el abismo.
- **Alt + Z/X/C/V**: muestra qué hace esa habilidad (sin lanzarla). La tecla Fn no sirve: los juegos no la reciben.
  Con el ratón suelto (Ctrl), pasar por encima de una casilla también la muestra.
- **Ficha del Eco**: al cambiar de Eco (o al pulsar el número del que ya llevas) aparece qué hace cada tecla.
- **Combos entre Ecos**: cambiar de Eco tarda 0,6 s, así que se puede cambiar a mitad de un combo. Los
  enfriamientos son por tecla y se comparten entre Ecos.
- **Las variantes en el aire tienen su propio enfriamiento**: Levante → C (subir) → golpes → C en el aire
  (Descenso) ya se puede cerrar entero; igual Puño Volcánico → salto → Meteoro.
- **Las habilidades ya no se pierden**: pulsar un poco antes de tiempo (al final del enfriamiento, de un
  aturdimiento o de una picada) la guarda 0,3 s y sale sola. Con ping, la primera habilidad tras cambiar de Eco ya
  no se rechaza.

## Lo nuevo de la primera noche (resumen)
- **Habilidades rehechas**: una tecla por habilidad (Z X C V), salen al instante y sin quedarte quieto, cortan tus
  golpes, y la barra de abajo muestra cuándo vuelven a estar listas. Las básicas no gastan nada.
- **5 Ecos** (teclas 1-5): Viento, Agua, Oscuridad, Fuego infernal y Trueno, con 20 habilidades más variantes en
  el aire y relanzamientos.
- **Combos**: 14 sinergias con nombre entre habilidades (y golpes), y combos aéreos (los enemigos flotan con cada
  golpe; tú también).
- **Espada** (Q), **patada voladora** (atacar tras un Paso) y **patada en picada** (atacar cayendo desde alto).
- **Gancho** (E) a orbes del mapa y a enemigos.
- **Postura y Golpe de Gracia**: desvía y golpea hasta que el enemigo quede QUEBRADO; luego ataca cerca.
- **Cámara fija** (Ctrl, viene activada) y **fijar enemigo** (R).
- Voltereta al dar un Paso hacia adelante, líneas de velocidad, polvo al caer, sonidos nuevos.
- Muñecos de práctica en la primera sala y título de entrada.
- Enemigos con más vida (para que sigan siendo un reto con tantas herramientas).

## Abrirlo
1. Doble clic en **`JUGAR.cmd`** (carpeta del juego). Construye todo y abre Roblox Studio.
2. En Studio, **F5**. Apareces en **La Grieta**: el Instructor te espera en la primera sala (tutorial; T lo salta,
   el menú M lo repite).

## Controles (PC)
| Qué | Tecla |
|---|---|
| Moverse · saltar (doble salto, salto de pared) · Paso | WASD · Espacio · Shift |
| Atacar (pulsar: combo · mantener: golpe fuerte) | Clic izquierdo |
| Defender (a tiempo: desvío · mantener: guardia) | F |
| Habilidades del Eco | **Z · X · C**, definitiva **V** |
| Cambiar de Eco | **1-5** (o el menú, M) |
| Puños ↔ Espada | **Q** |
| Gancho (al orbe brillante o al enemigo marcado con el círculo) | **E** |
| Cámara fija (el personaje mira hacia la mira) / soltar el ratón | **Ctrl** |
| Fijar un enemigo (la cámara lo sigue; un tirón del ratón cambia de enemigo) | **R** |
| Ver qué hace una habilidad (sin lanzarla) | **Alt + Z/X/C/V** |
| Ver la ficha del Eco puesto | su número (**1-5**) |
| Menú (controles, Ecos, ajustes) | M |

La **cámara fija** viene activada: mueves la cámara con el ratón, el personaje mira hacia la mira y los golpes y
las habilidades salen hacia ella (con ayuda hacia el enemigo cercano). Ctrl suelta el ratón; el menú (M) también.

## Los 5 Ecos
| Eco | Z | X | C | V |
|---|---|---|---|---|
| 1 Viento | Cuchilla | Ciclón | Levante (C otra vez: subir) · en el aire: Descenso | Tempestad |
| 2 Agua | Burbuja | Oleaje | Géiser | Diluvio |
| 3 Oscuridad | Paso Sombrío (Z otra vez: volver) | Daga Marcada | Fauces | Eclipse |
| 4 Fuego infernal | Bola Infernal | Estela Ardiente | Puño Volcánico · en el aire: Meteoro | Infierno |
| 5 Trueno | Rayo | Relámpago | Pararrayos | Juicio |

V gasta 60 de Resonancia (se carga golpeando, desviando y haciendo sinergias). Z, X y C solo tienen enfriamiento:
la barra de abajo muestra cuándo vuelven a estar listas.

## Combos para probar
- **Viento:** X (Ciclón) → Z (Cuchilla) = **REMOLINO CORTANTE**. C (Levante) → C otra vez (subes) → clic, clic en el
  aire → C en el aire (Descenso) = **CAÍDA DEL CIELO**.
- **Agua:** Z (Burbuja) → C (Géiser) = **MAREA ALTA**. X (Oleaje) → Z = **RESACA**.
- **Oscuridad:** X (Daga: marca) → cualquier golpe la **detona** y recarga Z. X → Z (Paso Sombrío) = **EMBOSCADA**.
- **Fuego:** Z (Bola) → C (Puño) = **ESTALLIDO**. Puño → salto → C en el aire (Meteoro) = **CAÍDA ÍGNEA**.
- **Trueno:** X (Relámpago) → Z (Rayo) = **SOBRECARGA**. C (Pararrayos) → X = **DESCARGA**.
- **Combate a lo Sekiro:** desvía (F justo antes del golpe) para llenar la **postura** del enemigo (barra naranja).
  Cuando dice **¡QUEBRADO!**, ataca cerca: **Golpe de Gracia**.
- **Armas:** Q saca la espada (Tajo, Revés, Estocada). Atacar justo después de un Paso: golpe en carrera. Atacar
  cayendo desde alto: picada.
- **Gancho:** en el Abismo hay orbes sobre los saltos; en el Ascenso, atajos a las repisas altas. E con el círculo
  encima. Engancharte a un enemigo y atacar enseguida: patada voladora.

## Qué me sirve que me cuentes
Qué se siente mal (lento, raro, injusto), qué habilidad no se entiende, qué combo te salió y cuál no, y qué
números cambiarías (daño, enfriamiento, alcance). Todo se ajusta en `src/shared/Config/CombatConfig.luau`.
