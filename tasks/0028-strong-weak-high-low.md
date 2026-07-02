# Task 0028: Strong/Weak High/Low

## Origen
- ORDEN 16 de `tasks/0021-volatility-and-choch-noise.md`.
- Nota WhatsApp profe (29/06): "Strong High es cuando coincide lo de arriba con el
  value de abajo".

## Objetivo
Portar el concepto Strong/Weak High y Strong/Weak Low de LuxAlgo: los extremos
trailing del swing se etiquetan como "Strong High"/"Weak High" (y Low) según el
sesgo de tendencia del swing.

## Estado verificado (02/07)
- NO existe Strong/Weak High/Low en el código actual (ni Mxwll ni SMC ni Liquidity).
- El .pine de LuxAlgo SÍ lo tiene (`drawHighLowSwings` + `updateTrailingExtremes`):
  * `trailing.top`/`trailing.bottom` = extremos trailing.
  * Etiqueta "Strong High" si `swingTrend.bias == BEARISH`, si no "Weak High"
    (y análogo para Low con BULLISH).
- Referencia guardada en `docs/material_profesor/LuxAlgo_SMC_reference.pine`.

## Interpretación de la nota del profe
"Strong High cuando coincide lo de arriba con el value de abajo" — probablemente
se refiere a la definición LuxAlgo: un High es "fuerte" cuando el mercado está en
tendencia bajista (el máximo resistió), "débil" cuando sigue subiendo. Confirmar
con el profe si su definición coincide con la de LuxAlgo.

## Diseño
- Rastrear trailing extremes (máximo y mínimo corrido) como en LuxAlgo.
- Al actualizar la estructura swing, etiquetar el extremo superior como
  "Strong High"/"Weak High" según el bias de tendencia vigente, e inferior como
  "Strong Low"/"Weak Low".
- Exponer en `get_values` (Mxwll o SMC) y dibujar en el overlay como línea+etiqueta
  del extremo, con toggle propio.

## Criterios de aceptación
- Se dibujan las etiquetas Strong/Weak High y Strong/Weak Low según el bias.
- Toggle para encender/apagar (integrar con sub-toggles ORDEN 9 si va en Mxwll).
- Determinista; test nuevo verificando la etiqueta según el bias.

## Pendiente de confirmar
- Definición exacta de "Strong/Weak" que quiere el profe (¿la de LuxAlgo?).
- ¿En qué indicador va (Mxwll, SMC)?

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '<repo>' && perl -I. -c Market/Indicators/Mxwll_Suite.pm && prove -l t/22-mxwll-suite.t"
```

## Qué no tocar
- No romper la estructura HH/HL/LH/LL ni el trailing existente de SMC.
