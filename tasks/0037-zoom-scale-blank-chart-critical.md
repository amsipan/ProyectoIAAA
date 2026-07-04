# Task 0037: [CRÍTICO] Zoom/Replay deja el eje Y corrupto → velas desaparecen

## Estado
✅ **Hecho** (2026-07-04)

## Origen
- Reporte del usuario (04/07) con captura: movió el zoom y las velas desaparecieron;
  la pantalla quedó casi en blanco con el eje Y en ~20163-29986 aunque los datos de
  junio están en ~29500 (Precio y ATR en Manual en ese momento).
- Confirmado por auditoría de arquitecto (3 subagentes + lectura directa).

## Causa raíz (cadena de 3 defectos que convergen)
El eje 20000-30000 es el FALLBACK de `PricePanel::get_y_range` (líneas 53,56) que
se devuelve cuando la ventana visible no tiene velas reales (todo undef).

### 1A. La ventana visible puede quedar TOTALMENTE vacía y el fallback contamina `last_auto`
- `ChartEngine::compute_window` (~223, 228-234): el offset se clampa con
  `_clamp_offset` → `_max_offset_for_visible` (355-362) usando `market_data->size()`
  (total COMPLETO), NO el `effective_total` de replay (231). Bajo Replay con offset
  heredado grande + replay_idx bajo → `end_idx` negativo → `start(0) > end` →
  `get_slice` devuelve `[]` → `get_y_range` devuelve (20000,30000).
- `render` (488-491, rama auto): graba ese fallback en `manual_min_y/max_y` Y en
  `last_auto_min_y/max_y`. Queda ENVENENADO.

### 1B. El fallback envenenado se propaga a MANUAL
- `_capture_price_y_range` (1720-1734) devuelve `last_auto_*` con máxima prioridad.
  Al pulsar "Manual" (`set_scale_mode('manual')`, 1789-1793) captura 20000-30000 y
  los fija en `manual_*`. El eje queda pegado aunque se recuperen datos reales.

### 1C. `set_scale_mode('auto')` NO limpia `ctrl_zoom_y_lock_*` → Auto queda ignorado
- Orden de ramas en render (484-491): la rama del lock (486-487) se evalúa ANTES
  que la rama auto (488) y SIN comprobar `is_auto_scale`.
- `_ctrl_horizontal_zoom` en manual setea `ctrl_zoom_y_lock_min/max` (1293-1297).
- `set_scale_mode('auto')` (1781-1784) NO toca esos locks → el chart queda clavado
  en el rango del ctrl-zoom ignorando el modo auto. Solo "Reset Vista" lo cura
  (llama `_clear_ctrl_zoom_state`); el doble-click en el eje NO.

## Fix requerido (los 3, son independientes)
1. **compute_window**: clampar el offset contra `effective_total` (no el total
   completo) cuando Replay está activo, para que la ventana nunca quede vacía.
   Además, guarda defensiva: si `start > end`, forzar una ventana válida (p.ej.
   end = último índice real, start = end - visible_bars + 1).
2. **render (488-491)**: NO escribir `manual_*` ni `last_auto_*` cuando el slice
   visible está vacío / todo undef. Detectar ese caso y CONSERVAR el último rango
   Y bueno (o recalcular sobre las velas reales aunque estén parcialmente fuera).
   El fallback (20000,30000) solo debe usarse para dibujar ese frame, nunca
   persistirse como estado.
3. **set_scale_mode('auto')**: limpiar `ctrl_zoom_y_lock_min/max` (igual que hace
   reset_view). Y/o en render: la rama del lock (486) debe condicionarse a
   `!is_auto_scale`.

## Criterios de aceptación
- Hacer zoom (rueda y ctrl+rueda) hasta llevar la vista al whitespace o fuera de
  rango y volver: las velas SIEMPRE reaparecen con su escala correcta; nunca queda
  el eje pegado en 20000-30000.
- Alternar Auto↔Manual tras un ctrl+zoom respeta el modo elegido.
- Doble-click en el eje de precio (auto) recupera la autoescala igual que Reset Vista.
- Replay arrancado con cualquier offset previo muestra velas (no blanco).
- Suite `prove -l t` verde; añadir test que simule ventana vacía y verifique que
  `last_auto_*`/`manual_*` NO se envenenan con el fallback, y que
  `set_scale_mode('auto')` limpia el lock.

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c Market/ChartEngine.pm && prove -l t"
```
Validación visual obligatoria: zoom agresivo + Auto/Manual + Replay en WSLg.

## Qué no tocar
- No romper el zoom con anclaje (ctrl+rueda ancla la vela bajo el crosshair).
- No romper el modo Manual normal (drag vertical del eje) ni el reset a auto en TF.
