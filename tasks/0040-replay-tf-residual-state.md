# Task 0040: [MEDIO] Estado residual de Replay / Select Bar / cambio de TF

## Estado
✅ **Hecho** (2026-07-04; test 0040-D añadido en t/17-ui-wiring.t)

## Origen
- Auditoría de arquitecto (04/07): `ChartEngine.pm`, `ReplayController.pm`,
  `Market/UI/Callbacks.pm`.

## Bugs a corregir

### A. Salir del Replay no limpia el estado de Select Bar
`ReplayController::exit` (~94-100) y `make_replay_exit` (Callbacks ~273-285)
desactivan replay pero NO limpian `_selected_bar` ni `_replay_select_mode` del
ChartEngine. Consecuencias:
- El marcador de selección (`_draw_replay_select_marker`, ~849-883) se sigue
  dibujando.
- El próximo "Inicio" usa `replay_start_index` (~813-828) que prioriza
  `_selected_bar - 1` → arranca en la vela vieja, no donde el usuario espera.
FIX: al salir del replay, limpiar `_selected_bar` y `_replay_select_mode` (y
sincronizar la var UI `replay_select_mode`).

### B. Replay Start / step / play no resetean offset/visible_bars
`make_replay_start` y familia (Callbacks ~123-269) nunca resetean `offset`/
`visible_bars`. Combinado con task 0037-1A, arrancar replay con un offset heredado
grande produce ventana vacía → pantalla blanca. FIX: al iniciar replay, encuadrar
la vista al punto de inicio (offset/visible_bars razonables) para que siempre haya
velas visibles.

### C. Select Bar mode queda ON indefinidamente
`make_replay_select_bar` (Callbacks ~137-147) alterna el modo; si el usuario lo
activa y no clickea ni sale, queda ON y `_start_horizontal_drag` (~1397-1404)
interpreta cualquier click como "seleccionar barra" en vez de paneo — sorpresa
persistente entre pestañas. FIX: auto-desactivar el modo tras seleccionar (o al
iniciar replay / cambiar de pestaña), y reflejarlo en el botón.

### D. Cambio de TF no detiene Play ni limpia replay/selección
`set_timeframe` (~2076-2134) resetea escalas/indicadores/vista pero:
- NO detiene un Play en curso (`%_play_active` sigue 1; el `after()` sigue llamando
  step_forward+render sobre la serie nueva con un `replay_idx` de la serie vieja).
- NO limpia `_selected_bar` ni `_replay_select_mode`.
- No sincroniza los checkbuttons UI (`replay_on`, `replay_select_mode`).
FIX: al cambiar de TF, detener Play, salir/normalizar Replay, limpiar selección y
sincronizar las vars UI.

## Criterios de aceptación
- Salir del replay quita el marcador y el próximo "Inicio" no arranca en la vela
  vieja.
- Iniciar replay siempre muestra velas (nunca blanco por offset heredado).
- El modo Select Bar no queda activo "para siempre"; el click vuelve a panear tras
  seleccionar.
- Cambiar de TF con Play activo detiene el Play y deja estado coherente.
- Suite `prove -l t` verde; reforzar t/12 (replay) y t/25 (select bar) con estos
  casos de estado residual.

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c Market/ChartEngine.pm && perl -I. -c Market/ReplayController.pm && perl -I. -c Market/UI/Callbacks.pm && prove -l t/12-replay.t t/25-replay-select-bar.t t"
```

## Qué no tocar
- No romper el flujo normal de Replay (Inicio/Play/Pause/step/fast/Salir) ni el
  Select Bar recién añadido.
