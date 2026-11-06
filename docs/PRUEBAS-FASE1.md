# Pruebas de la Fase 1: laboratorio de movimiento

## Automáticas (23 de 23 superadas el 2026-11-06)
`powershell -ExecutionPolicy Bypass -File tools/ejecutar-pruebas.ps1` comprueba todo lo de la tabla de abajo con números, incluido el Paso y el salto a 30 FPS. Los valores medidos están en [ESTADO.md](ESTADO.md).

## Manuales
Lo que una prueba automática no puede juzgar es la **sensación** y los **controles reales** (teclado, mando, pantalla táctil). Abre `build/UMBRAL-Desarrollo.rbxlx`, presiona **F5** y usa el panel de arriba a la izquierda para medir.

## Comprobaciones con número
| Prueba | Dónde | Resultado esperado |
|---|---|---|
| Velocidad al caminar | Cualquier lado | Panel ≈ 22 |
| Sprint automático | Pista de Paso | Tras ~0,4 s moviéndote, "Sprint: sí" y ≈ 34 |
| Distancia del Paso | Pista de Paso (marcas cada 10) | "Último paso" ≈ 14 studs |
| Cargas | Shift tres veces seguidas | El tercero no sale; vuelven de a una cada 0,8 s |
| Altura de salto | Pilares de altura | Un salto sube al pilar 8; con doble salto, al 14 |
| Paso aéreo | Brechas | Salto + Paso + doble salto cruza la brecha 22 |
| Coyote time | Borde de una plataforma | Puedes saltar justo después de salir del borde |
| Doble salto con giro | Cualquier lado | El segundo salto sale hacia donde apunta el joystick o WASD |

## Sensación (responder sí o no)
- [ ] El personaje responde al instante al cambiar de dirección (slalom).
- [ ] Se siente ligero, sin patinar como en hielo.
- [ ] El Paso permite ponerse justo donde quieres.
- [ ] Es fácil pasar de correr a saltar y de saltar a dar un Paso.
- [ ] La cámara se lee bien en giros bruscos y dentro del túnel.
- [ ] Chocar con el muro o subir la escalera no traba al personaje.
- [ ] Tras morir y reaparecer, todo sigue funcionando (prueba saltando desde lo alto).
- [ ] En celular (Studio → Prueba → Emulador de dispositivos), el botón PASO queda cómodo junto al de salto.
- [ ] Dan ganas de seguir moviéndose aunque no haya nada que hacer.

Si algo se siente mal, se cambia el número en `src/shared/Config/MovementConfig.luau` y se vuelve a ejecutar `node tools/construir.mjs`.
