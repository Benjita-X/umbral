# UMBRAL · Beta cerrada (candidato de lanzamiento)

Estado del contenido: **congelado**. Solo se corrigen fallos P0/P1, el guardado mínimo, verificaciones
indispensables y el flujo de publicación y pruebas.

## Archivo del candidato

```
node tools/construir.mjs --beta
```

Genera `build/UMBRAL-Beta.rbxlx`. La construcción se detiene si falta algún ID de animación publicada o si se colaran
las pruebas automáticas. El archivo tiene el mismo árbol que el lugar de desarrollo, sin `tests/` ni la marca del
plugin de pruebas. Solo en Studio se activan el diagnóstico, los mensajes `[UMBRAL]` en Output, el modo práctica y los
ajustes de desarrollo; en un servidor publicado quedan apagados (`RunService:IsStudio()`). El PvP sigue apagado
(`CombatConfig.Eco.PvP = false`, y los golpes cuerpo a cuerpo solo alcanzan modelos con la etiqueta `Objetivo`).

## Progreso permanente (PerfilService)

Solo dos datos:

| Dato | Qué es |
| --- | --- |
| `ExpedicionesCompletadas` | Expediciones de la Grieta terminadas, es decir, con el Guardián vencido. Cuenta cualquier dificultad. |
| `NivelGlobal` | `1 + ExpedicionesCompletadas // 2`, con tope 50. |

`NivelGlobal` no es el atributo `Nivel`: ese es el nivel temporal de la expedición en curso (BalanceService), que se
reinicia en cada partida junto con la experiencia y las mejoras.

Seguridad del guardado:

- **Clave:** `u_<UserId>` en el DataStore `UmbralPerfiles`.
- **Perfil versionado:** `{ v = 1, NivelGlobal, ExpedicionesCompletadas, meta }`.
- **Toda escritura usa `UpdateAsync`, con reintentos limitados (`pcall`).**
- **Cerrojo de sesión:**
  - El servidor que carga el perfil queda como dueño (`meta.sesion = JobId`).
  - Si otro servidor sigue siendo dueño (el jugador saltó de servidor y el anterior aún guarda), se espera.
  - Un cerrojo sin renovar durante 150 s se da por abandonado.
  - Un servidor desplazado nunca sobrescribe un perfil más nuevo.
- **Si la carga falla:** el jugador recibe un aviso, el HUD muestra "Progreso permanente sin cargar" y esa sesión no
  escribe nada. Nunca se pisa un perfil real con valores iniciales.
- **Escrituras por jugador ordenadas:** una a la vez. Si se pide otra mientras se guarda, se repite al terminar.
- **Una victoria cuenta una sola vez:** `meta.ultimaPartida` guarda el id de la última expedición contada (metadato
  técnico).
- **Cuándo se guarda:** al completar una expedición, al salir, cada 90 s si hay cambios y al cerrar el servidor
  (`BindToClose`, hasta 25 s).
- **El cliente no puede cambiar nada:** no hay remoto de perfil y los atributos los pone solo el servidor.
- **Studio sin publicar (PlaceId 0):** se usa una tienda simulada en memoria y el estado dice "simulado". La suite
  `Beta` prueba la lógica con esa simulación, que no sustituye a la prueba con el DataStore real (ver abajo).

## Expedición (cambios para la beta)

- **Abandonar a mitad de partida** saca solo a quien lo pide. La partida sigue para los demás y solo se reinicia si
  era el último participante.
- **Quien entra con una partida en curso** se une a ella: empieza en nivel 1 y aparece en el último punto de control.
- **Si cae todo el grupo:**
  - El encuentro se reinicia: sus enemigos vuelven al entrar otra vez en su sala.
  - Aparece el panel "El grupo ha caído" con las opciones Reintentar y Abandonar.
- **Repetir** solo lo puede pedir un participante. Una partida se completa una sola vez.
- **Todos los remotos tienen tope de mensajes por jugador** (`RemoteGuard`). Las validaciones de cada servicio siguen
  mandando.

Limitación conocida, por diseño: hay una sola expedición compartida por servidor, sin grupos ni instancias. Si una
partida está en curso, nadie puede empezar otra hasta que termine o la abandonen todos.

## Beta cerrada gratuita: pasos (los hace el dueño)

Nada de esto lo hace Claude: publicar y cambiar permisos requieren tu aprobación explícita.

1. **Experiencia de pruebas separada para el DataStore.**
   1. En Studio, abre `build/UMBRAL-Beta.rbxlx` y elige Archivo → Publicar en Roblox como… → experiencia nueva.
      Llámala, por ejemplo, "UMBRAL Pruebas DataStore". No es la experiencia definitiva.
   2. Ajustes del juego → Seguridad → activa "Permitir el acceso de Studio a los servicios de API".
   3. Juega en Studio y completa una expedición. Sal, vuelve a entrar y comprueba que el contador se mantuvo (abajo a la
      izquierda: "Nivel global N · N expediciones").
2. **Acceso.** Deja la experiencia privada (no pública) e invita a los testers. Roblox permite compartirla con
   colaboradores o miembros de tu grupo, y existe la función de testers anticipados o "betas de experiencia". Revisa
   en el Creator Hub cuál está disponible para tu cuenta.
3. **Cuestionario de madurez y cumplimiento.** Roblox lo pide para las betas, porque pueden llegar a jugadores
   públicos. Sin calificación, la experiencia queda restringida.
4. **Identificación.** El nombre o la descripción deben decir "BETA DE PRUEBAS". El HUD ya lo muestra en pantalla.

## Beta pública de pago (25 Robux): requisitos actuales

- El precio va de 25 a 1000 Robux.
- La cuenta debe tener el correo verificado y al menos 30 días de antigüedad.
- La experiencia debe ser **pública** y no puede tener servidores privados.
- Hay que avisar claramente de que se compra una versión beta.
- Pago en moneda local: hace falta ser mayor de 13 años con identidad verificada, y la experiencia pasa una revisión
  de moderación.
- No se activa nada de esto sin tu aprobación.

Fuentes:

- [Paid access in Robux](https://create.roblox.com/docs/production/monetization/paid-access-robux)
- [Paid access in local currency](https://create.roblox.com/docs/production/monetization/paid-access-local-currency)
- [Private servers](https://create.roblox.com/docs/production/monetization/private-servers)
- [Content maturity and compliance](https://create.roblox.com/docs/production/promotion/content-maturity)
- [Experience Betas (DevForum)](https://devforum.roblox.com/t/a-new-way-to-test-before-launch-experience-betas/4144485)
- [Invite early testers (DevForum)](https://devforum.roblox.com/t/a-simpler-path-to-publish-plus-invite-early-testers/4930524)

## Pendiente de validación humana

Estas pruebas no se pueden automatizar en el laboratorio:

1. **Expedición completa en solitario (1 → 5 + Guardián → resumen → repetir) en `UMBRAL-Beta.rbxlx`.** Lo automático
   prueba encuentros sueltos, no el recorrido entero por el mapa.
2. **Expedición con dos clientes:**
   1. Uno muere y el otro sigue.
   2. Uno abandona a mitad de partida.
   3. Alguien entra con la partida en curso.
   4. Caen todos.
   5. Se repite tras completarla.

   Para hacerlo: Studio → Prueba → Clientes y servidores → 2 jugadores.
3. **DataStore real** en la experiencia de pruebas publicada:
   1. Guardar, salir y volver.
   2. Saltar rápido a otro servidor.
   3. Cerrar el servidor.
4. **Permisos de las 40 animaciones en la experiencia publicada.** Deben pertenecer a la misma cuenta o grupo que
   publica.
5. **Rendimiento con varios enemigos y efectos en equipos reales (PC y móvil).** La suite `Estres` solo mide en el PC
   de desarrollo.
6. **Interfaz en móvil y en resoluciones pequeñas.**
