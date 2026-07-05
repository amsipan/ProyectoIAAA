# Task 0045: Replay — dropdowns de velocidad e intervalo cableados

## Referencia
- `docs/TRADINGVIEW_BAR_REPLAY_REFERENCE.md` §5, §19 capturas 4 y 5.
- Depende de 0041 (backend speed/interval) y 0043 (panel con botones `1x` y `D`).

## Objetivo
Calcar los dropdowns "REPLAY SPEED" (captura 4) y "UPDATE INTERVAL" (captura 5), cableados al
backend de 0041, de modo que cambien el ritmo real del autoplay.

## Estado actual
- Autoplay a ~80ms fijo en `make_replay_play`. No hay dropdowns.

## Diseño
1. **Dropdown de velocidad** (disparado por el botón `1x` del panel):
   - Frame flotante con título "REPLAY SPEED" y 9 filas de `speed_options()` (0041):
     `10x / 7x / 5x / 3x / 1x / 0.5x / 0.3x / 0.2x / 0.1x` con su descripción `N upd per M sec`.
   - Resaltar la opción activa (fondo oscuro, como la captura).
   - Al elegir: `ReplayController::set_speed_label($label)`; el botón del panel muestra el label
     elegido; si hay autoplay activo, reprogramar el `after` con el nuevo `tick_ms()`.
2. **Dropdown de intervalo** (disparado por el botón `D`):
   - Frame flotante con título "UPDATE INTERVAL", opciones según TF disponibles del proyecto
     (mapear a lo que MarketData sirve; para el CSV 1m: `1 hour / 2 hours / 3 hours / 4 hours / 1 day`
     como en la captura 5, más el toggle **Auto select interval** ON por defecto).
   - Con "Auto select interval" ON: el intervalo sigue al TF del chart (comportamiento actual).
     Con OFF: usa el intervalo elegido → `set_replay_interval($velas)` (nº de velas del TF base que
     equivalen al intervalo elegido).
   - El botón del panel muestra el intervalo activo (`D`, `1h`, etc.).
3. **Reprogramación del autoplay:** `make_replay_play` debe usar `$rc->tick_ms()` en lugar del 80ms
   fijo y avanzar `advance_one_tick()` (respeta `replay_interval`). Al cambiar velocidad/intervalo en
   caliente, cancelar y reprogramar el `after`.

## Criterios de aceptación
- Elegir `5x` hace el autoplay ~5 velas/seg (tick 200ms); `0.1x` ~1 vela/10s.
- El label del botón refleja la velocidad/intervalo activos.
- "Auto select interval" ON = intervalo sigue al TF; OFF = usa el elegido.
- Cambiar velocidad durante Play tiene efecto inmediato (sin reiniciar el replay).
- `prove -l t` verde; test en `t/12-replay.t`/`t/17-ui-wiring.t`: mapeo label→ms correcto y que
  `make_replay_play` consume `tick_ms()` (inyectando un controller espía o verificando el intervalo).

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c market.pl && perl -I. -c Market/UI/Callbacks.pm && perl -I. -c Market/ReplayController.pm && prove -l t/12-replay.t t/17-ui-wiring.t t"
```
Validación visual en WSLg (comparar con capturas 4 y 5).

## Qué no tocar
- No romper el truncado por replay_idx ni el auto-pause al llegar al final.
- No cambiar el modelo de velocidades de 0041 (solo consumirlo).
