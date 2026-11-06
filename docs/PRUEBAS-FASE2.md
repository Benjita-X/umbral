# Pruebas de la Fase 2: combate corporal

## Automáticas (55 de 55 superadas el 2026-11-06, junto con las de la Fase 1)
`powershell -ExecutionPolicy Bypass -File tools/ejecutar-pruebas.ps1`

| Prueba | Medido | Objetivo |
|---|---|---|
| Muñecos en el Dojo | 4 muñecos R15, 120/120 | — |
| Animaciones de combate | 6 de 6 cargadas | 6 |
| Golpe rápido | el servidor confirma 4 de daño (120 → 116) | 4 |
| Efectos de impacto | chispas, destello y sonido | los tres |
| Duración con hitstop | 0,32 s | 0,32 s |
| Encadenar al conectar | el Directo sale a los 0,18 s | 0,18 s |
| Fallar no se cancela | el siguiente sale a los 0,32 s | 0,32 s |
| Combo de 3 | Jab, Directo, Patada · 16 de daño | 16 |
| El remate empuja | 7,8 studs | ≥ 2,5 |
| El combo se reinicia | Jab, (pausa), Jab | Jab, Jab |
| Mantener = golpe fuerte | Jab, Fuerte · 14,5 de daño | entre 10 y 18 |
| El golpe fuerte empuja y levanta | 13,6 studs · sube 1,4 | ≥ 3 · ≥ 0,5 |
| Carga completa sale sola | sí · 18 de daño | 18 |
| Orientación asistida | girado 50°, conecta | conecta |
| Se acerca al rival | a 6,5 studs conecta | conecta |
| Fuera de alcance | a 13 studs no conecta | no conecta |
| Paso bloqueado al preparar | no sale | no sale |
| Paso cancela la recuperación | sale y termina el golpe | sí |
| Golpear desde el Paso | el Paso se corta y sale el golpe | sí |
| Guardia | 9,9 studs/s (al soltar, 28) | 9,9 |
| Golpear desde la guardia | sí | sí |
| Golpes legítimos rechazados | 0 | 0 |
| Golpe falso lejano / inventado / repetido | los tres rechazados | rechazados |
| Poses en el impacto | Jab 10° · Directo 14° · Patada 14° · Fuerte 27° del frente | < 41° |
| Combo a 35 FPS | 3 confirmados, 16 de daño | igual que a 60 FPS |

## Manuales (solo una persona puede juzgarlas)
Abre `build/UMBRAL-Desarrollo.rbxlx`, presiona **F5** y ve al **Dojo** (detrás a la derecha del punto de aparición).

- [ ] Pegar se siente con peso: el hitstop, el sonido y las chispas acompañan cada golpe.
- [ ] El combo de 3 se encadena solo pulsando, sin sentirse automático.
- [ ] Mantener para el golpe fuerte no retrasa el combo normal.
- [ ] Moverte, dar un Paso y golpear se siente como una sola maniobra.
- [ ] Fallar un golpe se nota, pero no frustra.
- [ ] La vibración de cámara no marea (se baja en `CombatConfig.Feedback.ScreenShake`).
- [ ] Las animaciones provisionales se leen bien (son placeholders hechos por código).
- [ ] En el Emulador de dispositivos, los botones ATACAR, DEFENDER y PASO quedan cómodos alrededor del de salto.
