# Task 0022: Estructura Mxwll — líneas externas sólidas, internas entrecortadas

## Origen
- ORDEN 10 de `tasks/0021-volatility-and-choch-noise.md`.
- Nota WhatsApp profe (29/06): "Líneas externas fijas, líneas internas entrecortadas".

## Objetivo
Diferenciar visualmente estructura externa vs interna por estilo de línea:
externa = línea SÓLIDA (fija), interna = línea ENTRECORTADA (dashed). Aplica a
BOS/CHoCH/I-BoS/I-CHoCH del Mxwll y, por coherencia, a EQH/EQL vs I-EQH/I-EQL.

## Estado verificado (02/07)
- `Market/Overlays/Mxwll_Suite.pm`, bloque STRUCTURE: TODA la estructura (ext e
  int) se dibuja con `-dash => [4,4]` (entrecortada). No hay distinción de estilo.
- La diferenciación actual ext/int es solo por fuente (Helvetica 8 bold vs 7).
- EQH/EQL en `Market/Overlays/Liquidity.pm` (`_draw_pair_line`): ambos con
  `-dash => [2,3]`; internos ya usan width 1 (ORDEN 6/7), pero mismo patrón dash.

## Diseño
- En el render de STRUCTURE del Mxwll: si `$s->{internal}` → `-dash => [4,4]`;
  si externo → sin `-dash` (línea sólida), manteniendo el color por dirección.
- En `_draw_pair_line` (Liquidity): externo EQH/EQL sólido, interno I-EQH/I-EQL
  dashed. Mantener el resaltado de largos (width 3) de la ORDEN 7.
- No cambiar colores ni etiquetas literales ya existentes.

## Criterios de aceptación
- BOS/CHoCH (externos) se dibujan con línea sólida; I-BoS/I-CHoCH con dashed.
- EQH/EQL sólidos; I-EQH/I-EQL dashed.
- Se conserva la etiqueta literal (I- para internos) y el color por dirección.
- Suite `prove -l t` verde (ajustar/añadir asserts de `-dash` en t/15 y, si aplica,
  un test de render de estructura Mxwll).

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '<repo>' && perl -I. -c Market/Overlays/Mxwll_Suite.pm && perl -I. -c Market/Overlays/Liquidity.pm && prove -l t/15-overlay-liquidity-render.t t/22-mxwll-suite.t"
```

## Qué no tocar
- No cambiar el cálculo (indicadores). Solo estilo de render.
- No romper la diferenciación por texto literal (I-CHoCH/I-EQH) ya existente.
