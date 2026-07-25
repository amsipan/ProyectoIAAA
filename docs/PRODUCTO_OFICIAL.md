# Producto oficial (canónico)

**Última actualización:** 2026-07-24  
**Cola de correcciones vigente:** `docs/FEEDBACK_PROFESOR_REVISION_2026-07-24.md`

## Capas e indicadores en runtime

| Pieza | Notas |
|--------|--------|
| Chart OHLC + TF + Replay + Escala + ATR | Optimizar precarga TF (`MarketData`) según feedback §1 |
| SMC Pro | Toggles BOS/CHoCH int/ext + EQH/EQL (feedback §5, hecho) |
| Structures + FVG | Toggle FVG independiente del BOS/CHoCH interno (feedback §4, hecho) |
| HLD 4h / HLD D | MTF: R/S desde vectores 4h|D; visible si chart TF ≤ fuente (feedback §2) |
| Parallel Channel / Trendline manual | Mediana punteada en canal (feedback §10) |
| Trendline auto / Canal auto | Pestaña Auto |
| ZigZag ext + int + Fib | — |
| Liquidity | BSL/SSL + Sweep/Grab/Run; **sin** EQH/EQL (feedback §6, hecho; EQ en SMC Pro) |
| DIY, AVP, AVWAP, Pivots/Fantasmas | Anclas más visibles; AVWAP auto estilos/colores (feedback §7–§9) |

Dataset predeterminado: `Data/2026_07_20.csv` (NQ1! 1m, UTC-5).

## Política

- Cálculo en `Indicators/` / `Drawing/` (sin Tk); render en `Overlays/` / paneles.
- Replay causal: cero fuga de futuro.
- Docs de proceso históricos están fuera del árbol (`_archive_.../docs_proceso/`).
