# Task: Fantasma rastro + AVWAP automático (clase 2026-07-21)

## Objetivo
- Rastro `"1"` cuando salta el fantasma provisional (toggle UI, Replay-safe).
- AVWAP Auto-1 = último pivot REGULAR consolidado (high **o** low).
- AVWAP Auto-2 = fantasma provisional (sigue `x_last`).
- Manual opcional y **adicional**; Manual+Auto puede mostrar hasta 3 líneas.
- Auto máximo 2; **sin** tope duro de 2 totales.

## Archivos relevantes
- `Market/Indicators/PivotPointsHL.pm`
- `Market/Overlays/PivotPointsHL.pm`
- `Market/Indicators/AnchoredVWAP.pm` / `Market/Overlays/AnchoredVWAP.pm`
- `Market/ChartEngine.pm`
- `market.pl` (pestaña Volumen)
- `t/42-pivot-points-hl.t`, `t/43-avwap-auto.t`

## Qué no tocar
- Fib ZZ automático / modelos / `Market/Debug/`
