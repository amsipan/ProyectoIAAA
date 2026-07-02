# Task 0026: Etiquetar los Order Blocks como "OB"

## Estado: HECHO (2026-07-02, commit tras 792 tests PASS)
- `_draw_block` recibe un `$label` y dibuja `createText` en la caja: high_blocks
  → "Bear OB" (color bear), low_blocks → "Bull OB" (azul #2157f3).
- Test nuevo en t/22 (bloque 11): verifica etiquetas "Bear OB"/"Bull OB" y que se
  dibujan las 2 cajas. Suite 792 PASS.

## Origen
- ORDEN 14 de `tasks/0021-volatility-and-choch-noise.md`.
- Notas WhatsApp profe (29/06): "Falta indicar Order Block"; "Falta identificar
  líneas azules con OB (Order Block)".

## Objetivo
Las cajas de order block del Mxwll deben llevar una etiqueta de texto "OB" (y
opcionalmente distinguir Bull/Bear) para que se identifiquen como Order Blocks.

## Estado verificado (02/07)
- `Market/Overlays/Mxwll_Suite.pm`, `_draw_block`: dibuja las cajas de order block
  (high_blocks en color bear, low_blocks en azul #2157f3) SIN ningún `createText`.
- Las "líneas azules" que menciona el profe son los `low_blocks` (bordes azules).
- El indicador ya produce `high_blocks`/`low_blocks` con `index`, `top`, `bottom`.

## Diseño
- En `_draw_block`, añadir un `createText` con etiqueta literal "OB" cerca de la
  caja (p.ej. esquina izquierda). Color acorde al tipo (bear/azul).
- Opcional (confirmar con usuario): distinguir "Bull OB" (demand, azul) vs
  "Bear OB" (supply, rojo/bear). El .pine usa colores distintos para bullish/
  bearish OB; el texto puede ser solo "OB" o "OB↑"/"OB↓".
- Respetar el clip al borde derecho real (x_right, ORDEN sobre TradingView parity)
  ya implementado.

## Criterios de aceptación
- Cada order block dibujado muestra la etiqueta "OB".
- Se distingue bull (azul) de bear por color (ya existe) y, si se decide, por texto.
- Toggle OB del Mxwll (ORDEN 9) sigue encendiendo/apagando cajas + etiqueta juntas.
- Suite `prove -l t` verde; añadir assert de etiqueta "OB" en t/22.

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '<repo>' && perl -I. -c Market/Overlays/Mxwll_Suite.pm && prove -l t/22-mxwll-suite.t"
```

## Qué no tocar
- No cambiar la detección de order blocks (indicador). Solo añadir etiqueta.
- No romper el clip al último candle real ni el toggle OB.
