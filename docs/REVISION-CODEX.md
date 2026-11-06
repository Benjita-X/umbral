# Revisión cruzada: Codex ↔ Claude

Canal de trabajo entre dos asistentes que **no se comunican directamente**. Todo pasa por este archivo y por Git.

## Reglas
1. **Claude trabaja en `main`.** Codex **no edita archivos en `main`**.
2. Si Codex quiere proponer código, lo hace en la rama `revision-codex` (creada desde `main`) y lo menciona aquí con el commit.
3. Cada hallazgo va en la tabla de abajo, con un **escenario concreto** que falla (entradas o estado → resultado incorrecto). Sin escenario, es una opinión, no un hallazgo.
4. Nada de contraseñas, cookies ni tokens en este archivo.
5. Claude responde en la columna "Respuesta" y cambia el estado. Se aplica solo lo que pase las pruebas (`tools/ejecutar-pruebas.ps1`).
6. Estados: `ABIERTO` · `ACEPTADO` · `CORREGIDO (commit)` · `RECHAZADO (motivo)` · `DUDA`.

## Antes de revisar, leer
- `docs/AUDITORIA-FASE3.md`: hallazgos ya encontrados y corregidos (no repetirlos).
- `docs/ARQUITECTURA.md`: módulos, remotes, flujos de ataque y defensa, Contrapaso.
- `docs/DECISIONES.md`: lo ya decidido y por qué (#35-#47 son de esta auditoría).

## Prioridades de revisión
1. `src/server/Services/PositionService.luau`: confirmación de posiciones, retroceso acotado, límites de tasa.
2. `src/server/Services/DamageService.luau`: `InicioAtaque` (secuencia legal) y validación de golpes.
3. `src/server/Services/DefenseService.luau` y `SparringService.luau`: juicio de desvío, Contrapaso, guardia, expuesto.
4. `tests/client/Pruebas/*.luau`: pruebas que aprueben algo sin medirlo de verdad.

## Hallazgos

| # | Autor | Archivo:línea | Problema | Escenario que falla | Propuesta | Estado | Respuesta |
|---|---|---|---|---|---|---|---|
| | | | | | | | |
