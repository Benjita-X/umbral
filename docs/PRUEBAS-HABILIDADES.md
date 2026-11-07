# Pruebas de habilidades, armas y movimiento (rama `experimental/habilidades-v2`)

## Automáticas (Studio, `tools/ejecutar-pruebas.ps1`)
| Suite | Qué mide (lo decide el servidor) |
|---|---|
| `Eco` | Viento: Cuchilla (daño a distancia, sin costo, se frena en la pared), enfriamiento por tecla, barra, Ciclón (atrae, aturde), sinergia REMOLINO CORTANTE, Levante (lanza y flota), Ascenso, Descenso, Tempestad (costo y golpes), cancelar un golpe con una habilidad, menú |
| `Ecos` | Agua (Burbuja atrapa, Géiser lanza, Oleaje arrastra, Diluvio daña y cura), Oscuridad (Paso Sombrío ida y vuelta, Daga marca y Fauces detona y recarga Z, Eclipse), Fuego (Bola explota y quema, Puño empuja, Meteoro, Infierno), Trueno (Rayo salta, Relámpago cruza, Pararrayos, Juicio), habilidad de otro Eco rechazada |
| `Armas` | Q a la Espada (se ve en la mano), combo de espada, golpe de otra arma rechazado, vuelta a Puños, patada voladora tras el Paso, patada en picada |
| `GanchoYGracia` | Gancho a un orbe (llega e impulsa) y a un enemigo (abre la patada voladora, aceptada por el servidor), postura que se llena, QUEBRADO y Golpe de Gracia, fijar enemigo (cámara y encarar) |
| `RevisionCodex` | Dos definitivas en el mismo cuadro cobran una vez, Descenso desde el suelo rechazado, Levante en el aire rechazado sin gastar el enfriamiento |

## Para una persona (lo que las pruebas no pueden juzgar)
Marca cada punto: ✔ bien · ✘ mal (y por qué).

**Sensación**
- [ ] Las habilidades salen al instante al pulsar, sin quedarse quieto.
- [ ] Se entiende qué hace cada habilidad al verla (efecto, sonido, animación).
- [ ] La barra deja claro cuándo está lista cada tecla y por qué no sale.
- [ ] Los combos con nombre se descubren y se sienten premiados.
- [ ] Los combos aéreos (Levante → C otra vez → golpes en el aire → Descenso) se pueden hacer sin pelear con la cámara.
- [ ] La espada se ve bien en la mano y en los golpes (la hoja apunta hacia donde corta).

**Movimiento y cámara**
- [ ] La cámara fija (Ctrl) es cómoda: el personaje mira hacia la mira y apuntar es fácil.
- [ ] Fijar enemigo (R) ayuda en las peleas y cambiar de enemigo con un tirón del ratón funciona.
- [ ] El gancho (E) se entiende (círculo sobre el orbe) y se encadena con saltos y paredes.
- [ ] El Paso, el doble salto y las paredes siguen sintiéndose bien con la cámara fija.

**Equilibrio (números en `CombatConfig.Eco.Skills` y `CombatConfig.Attacks`)**
- [ ] Ningún Eco es claramente mejor que los demás.
- [ ] Los enemigos de la Grieta siguen siendo un reto (las habilidades aturden mucho).
- [ ] La definitiva (60 de Resonancia) llega a un ritmo razonable.

**Celular y mando** (no probado todavía)
- [ ] Los botones de habilidades, ARMA, GANCHO y FIJAR no se tapan y se alcanzan con el pulgar.
- [ ] Con mando: Y, L1, L2, R2, cruceta y R3 hacen lo que dice el menú.
