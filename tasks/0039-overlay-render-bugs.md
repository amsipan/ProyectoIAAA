# Task 0039: [MEDIO] Bugs de render en overlays (SuperTrend, whitespace, elementos no dibujados)

## Origen
- Auditoría de arquitecto (04/07), overlays en `Market/Overlays/`.

## Bugs a corregir

### A. Strategy_Builder: SuperTrend une bandas en cada reversión (ALTO visual)
`Market/Overlays/Strategy_Builder.pm` líneas 87-103: dibuja el segmento
`st[$i] → st[$i+1]` sin comprobar cambio de dirección. En un flip, `st[$i].value`
está en la banda superior y `st[$i+1].value` salta a la inferior → línea casi
vertical cruzando el precio en cada reversión.
FIX: no dibujar el segmento cuando `st[$i]->{dir} != st[$i+1]->{dir}` (romper la
línea en el flip, como TradingView).

### B. Dibujos que se extienden al whitespace derecho (varios overlays)
Patrón repetido: cortan en el borde del canvas `$w` en vez de en la última vela
real (`_last_real_index`), como SÍ hace Mxwll_Suite. Cuando hay whitespace a la
derecha, cajas/líneas se pintan sobre la zona sin velas.
- `Strategy_Builder.pm` 116-117, 137-138: zonas Supply/Demand (`$x1 = $w_total`).
- `SMC_Structures.pm` 244-251: cajas FVG hasta `$w`.
- `Liquidity.pm` 245, 417-446: bandas y líneas BSL/SSL hasta `$w`/`_draw_end_idx`.
FIX: clampar el borde derecho a `min(x_del_indice, x_de_last_real_index)`. Reusar
el patrón de `Market/Overlays/Mxwll_Suite.pm` (`_last_real_index` guardado en
`compute_visible`). NOTA: para líneas horizontales de NIVEL (BSL/SSL puros que se
extienden como referencia) puede ser aceptable llegar al borde; aplicar el corte
sobre todo a CAJAS (FVG, zonas, bandas).

### C. Elementos declarados en toggles pero nunca dibujados (funcional)
- `Strategy_Builder.pm`: `_elements` incluye HALFTREND y RANGEFILTER (22-23) y el
  indicador los calcula, pero `draw` solo pinta SuperTrend y Supply/Demand. Los
  toggles no hacen nada. FIX: renderizar HalfTrend y Range Filter, o quitar sus
  toggles si se decide no mostrarlos.
- `VolumeProfile.pm`: `_elements{HISTOGRAM}` en 1, el indicador retorna `bins`,
  `draw` los exige (línea 72) pero NO los dibuja (solo POC/VAH/VAL). FIX: dibujar
  el histograma de barras horizontales, o quitar el toggle HISTOGRAM.
- `AnchoredVWAP.pm`: `draw` (66-99) nunca consulta `is_element_visible('VWAP_LINE')`
  → apagar ese elemento no oculta la curva. FIX: respetar el toggle.

### D. Guardas de robustez (BAJO)
- `Strategy_Builder.pm` y `VolumeProfile.pm`: `draw` sin guarda
  `return unless $scales->{height} > 0` (los otros overlays sí). Añadirla.
- `SMC_Structures.pm` 258/274 y `Liquidity.pm` ~556: `price undef → y=0` (etiqueta
  pegada al techo). Cambiar a `next unless defined $price`.
- `ZigZag.pm` 113-131: precios de segmento sin guarda `defined`. Añadir.

## Criterios de aceptación
- SuperTrend se rompe en los flips (sin líneas verticales espurias).
- Cajas FVG/zonas/bandas cortan en la última vela real (no en whitespace).
- Toggles HALFTREND/RANGEFILTER/HISTOGRAM/VWAP_LINE hacen efecto (o se retiran).
- Sin dibujos en y=0 por precio undef.
- Suite `prove -l t` verde; reforzar t/14 (SMC), t/15 (Liquidity), t/19 (Strategy),
  t/20 (VolumeProfile), t/21 (VWAP) con los casos correspondientes.

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && prove -l t"
```
Validación visual recomendada por capa.

## Qué no tocar
- No cambiar el cálculo de los indicadores (solo render).
- No romper el corte al último candle que ya funciona en Mxwll.
