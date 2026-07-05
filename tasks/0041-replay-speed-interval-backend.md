# Task 0041: Replay — velocidad (9 multiplicadores) e intervalo de replay (backend)

## Referencia
- `docs/TRADINGVIEW_BAR_REPLAY_REFERENCE.md` §5 (velocidad vs intervalo), §19 capturas 4 y 5.

## Objetivo
Dar al `ReplayController` un modelo de **velocidad** (multiplicador que fija el periodo del autoplay
en ms) y de **intervalo de replay** (cuántas velas se añaden por tick), independientes entre sí.
Solo backend + tests; la UI se cablea en 0045.

## Estado actual
- `ReplayController` tiene `speed` (usado solo por `fast_forward` como `10*speed`) y `set_speed`.
- El autoplay real usa un intervalo fijo ~80ms en `Callbacks.pm` (`make_replay_play`).
- No existe concepto de "intervalo de replay".

## Diseño
En `Market/ReplayController.pm`:
1. Tabla de velocidades (etiqueta → ms por tick), EXACTA de la captura 4:
   | label | updates | ms/tick |
   |-------|---------|---------|
   | 10x | 10 upd/1s | 100 |
   | 7x  | 7 upd/1s  | 143 |
   | 5x  | 5 upd/1s  | 200 |
   | 3x  | 3 upd/1s  | 333 |
   | 1x  | 1 upd/1s  | 1000 |
   | 0.5x | 1 upd/2s | 2000 |
   | 0.3x | 1 upd/3s | 3000 |
   | 0.2x | 1 upd/5s | 5000 |
   | 0.1x | 1 upd/10s | 10000 |
   Exponer `speed_options()` (lista ordenada de {label, ms}) y `set_speed_label($label)`.
   Default `1x` (1000 ms).
2. `tick_ms()` → ms del tick actual según la velocidad seleccionada.
3. `replay_interval` (nº de velas por tick, default 1) + `set_replay_interval($n)` y
   `replay_interval()`. `step_forward` NO cambia; se añade `advance_one_tick()` que hace
   `replay_interval` pasos de `step_forward` (respetando clamp y pause al llegar al final).
4. Mantener retrocompat: `set_speed($n)` numérico sigue existiendo (no romper tests viejos).

## Criterios de aceptación
- `speed_options()` devuelve los 9 valores con sus ms correctos.
- `set_speed_label('5x')` → `tick_ms()==200`.
- `set_replay_interval(3)` + `advance_one_tick()` avanza replay_idx 3 (o hasta el tope, con pause).
- Al llegar al último índice, `advance_one_tick` deja `playing=0` (igual que step_forward hoy).
- `set_speed(2)` numérico sigue funcionando (no romper `t/12`).
- `prove -l t` verde; nuevo bloque en `t/12-replay.t` para velocidad e intervalo.

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c Market/ReplayController.pm && prove -l t/12-replay.t t"
```

## Qué no tocar
- No tocar el truncado por `replay_idx` (effective_end) ni la lógica de fuga de futuro.
- No cablear UI aquí (eso es 0045).
