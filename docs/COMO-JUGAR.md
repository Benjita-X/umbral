# Cómo jugar el prototipo (rama `experimental/habilidades-v2`)

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
