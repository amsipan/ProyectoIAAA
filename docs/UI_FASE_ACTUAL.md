# UI — fase actual (paso a paso)

## Activo

| Pieza | Notas |
|--------|--------|
| Chart OHLC + TF + Replay + Escala | Base |
| **SMC Pro** | Indicador 1 verificado |
| **SMC Structures+FVG** | Indicador 2 verificado |
| **Parallel Channel** | Herramienta TV (3 clics); un canal a la vez |

## Desactivado (código conservado)

No se muestran en pestañas ni se registran en ChartEngine en runtime de producto:

- ZigZag (+ “Canal” por pierna ZZ)
- Liquidity
- Strategy Builder
- Anchored VWAP / Volume Profile
- Mxwll (ya fuera de producto)

**Reactivar:** ver comentarios en `market.pl` y `ChartEngine.pm` (`FASE ACTUAL` / `PASO A PASO`).

## Dataset

Base nativa **15m** (`Data/tv_nq1_15m.csv` o export TV). TF superiores se agregan desde 15m.
