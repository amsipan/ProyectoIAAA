# Task 0035: Modo Manual de escala (Precio/ATR) fallando

## Origen
- Reporte del usuario (03/07): "el modo manual parece que está fallando y no está
  bien como antes estaba".

## Estado (a diagnosticar con detalle)
Codigo relevante en `Market/ChartEngine.pm`:
- `set_scale_mode('manual')` (linea ~1538): pone `is_auto_scale=0` pero NO fija
  `manual_min_y`/`manual_max_y` en ese momento. Quedan como esten (posiblemente
  undef si nunca hubo auto previo o tras un reset).
- En `render` (lineas ~453-459): el rango manual solo se usa si
  `!is_auto_scale && defined manual_min_y && defined manual_max_y`. Si estan
  undef, cae al `else` que los REESCRIBE con el rango auto calculado. O sea, al
  entrar en manual sin min/max definidos, se comporta como auto hasta el primer
  drag/zoom.
- Interaccion con `ctrl_zoom_y_lock_min/max` (linea ~453): tiene PRIORIDAD sobre
  el manual. Si quedo un lock de ctrl+zoom activo, el manual no se respeta.
- `reset_view` / `set_timeframe` limpian a auto (lineas ~1870-1893) y
  `_clear_ctrl_zoom_state`.

## Hipotesis del bug
1. Al pulsar "Manual" sin haber capturado antes un rango, `manual_min_y/max_y`
   estan undef → el render los sobrescribe con auto → el usuario no puede "fijar"
   la escala (parece que manual no hace nada). ANTES quizas se capturaba el rango
   visible al cambiar a manual.
2. Posible residuo de `ctrl_zoom_y_lock` que pisa el manual.
3. El rediseño de UI en pestañas (task 0032) NO deberia afectar (los callbacks
   son los mismos), pero verificar que el Radiobutton de Precio/ATR sigue ligado
   a `$scale_mode`/`$atr_scale_mode` y llama a `set_scale_mode`.

## Objetivo
Que al activar "Manual" la escala quede FIJA en el rango visible actual y se
pueda ajustar con drag/zoom vertical, como funcionaba antes; y que "Auto" vuelva
a autoescalar.

## Diseño (a confirmar tras reproducir)
- En `set_scale_mode('manual')`: capturar el rango visible actual en
  `manual_min_y/max_y` (del ultimo render) para que el manual arranque fijando lo
  que se ve, en vez de quedar undef.
- Igual para `set_atr_scale_mode('manual')` con `atr_manual_min_y/max_y`.
- Asegurar que `ctrl_zoom_y_lock` no pise el manual indebidamente.
- Guardar el ultimo rango auto calculado en el estado para poder capturarlo.

## Criterios de aceptación
- Al pasar a Manual, la escala se congela en el rango visible y no autoescala.
- Drag/zoom vertical ajustan el rango manual (precio y ATR por separado).
- Auto vuelve a autoescalar. Reset/cambio de TF vuelven a auto (como hoy).
- Tests de escala (si existen) verdes; añadir test del rango capturado al pasar
  a manual.

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '<repo>' && perl -I. -c Market/ChartEngine.pm && prove -l t"
```
Requiere confirmacion visual (arrastrar/zoom en manual, precio y ATR).

## Qué no tocar
- No romper el modo auto ni el ctrl+zoom que ancla la vela bajo el crosshair.
- No romper el reset a auto en cambio de TF / reset_view.
