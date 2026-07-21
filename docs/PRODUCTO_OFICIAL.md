# Producto oficial (canónico)

**Última actualización:** 2026-07-20
**Política:** solo este stack se carga en runtime. Todo lo demás está **fuera del repo** (`docs/LEGACY.md`).

> **Dirección del proyecto (meta = entrenar modelos):**  
> **`docs/PLAN_DEFINITIVO.md`** — léelo antes de añadir capas. Este archivo solo lista
> **qué hay cargado hoy** en la app.

## Capas e indicadores oficiales

| Pieza | Módulos | Validación |
|--------|---------|------------|
| Chart OHLC + TF + Replay + Escala + ATR | `MarketData`, `ChartEngine`, panels, `ReplayController`, `ATR` | Replay causal: slots vacíos, paridad X en zoom extremo, overscan, escala manual y rewind de indicadores (`t/38`, 52 checks) |
| **SMC Pro** | `Indicators/Overlays/SMC_Pro.pm` | Captura Neon TV |
| **Structures + FVG** | `Indicators/Overlays/SMC_Structures_FVG.pm` | Captura LudoGH |
| **HLD (4h/D)** | `Indicators/Overlays/HLD.pm` | Video profe ~40–46 min |
| **Parallel Channel** | `Drawing/Overlays/ParallelChannel.pm` | Herramienta TV 3 clics |
| **ZigZag ext + int** | `Indicators/Overlays/ZigZag.pm` | ChartPrime + ZZMTF |
| **Fib Retracement** | `Drawing/Overlays/FibRetracement.pm` | Clone TV |
| **Liquidity v2** | `Indicators/Overlays/Liquidity.pm` | PDF §4 FSM + profe (docs/LIQUIDITY_V2.md) |

## Runtime

`ChartEngine->new` registra:  
`smc_pro`, `smc_fvg`, `hld`, `pchan`, `zigzag`, `fib`, **`liq`**.

Dataset predeterminado: `Data/2026_07_20.csv` (NQ1! 1m, `UTC-5`, volumen real;
18.658 velas entre `2026-07-01T00:00:00-05:00` y `2026-07-20T15:58:00-05:00`).
`market.pl` agrega desde esta base las temporalidades superiores bajo demanda.

No existen en el árbol del repo (legacy):

- `Market/Indicators/Mxwll_Suite.pm`  
- `Market/Indicators/Strategy_Builder.pm`  
- `Market/Indicators/VolumeProfile.pm`  
- `Market/Indicators/AnchoredVWAP.pm`  
- `Market/Indicators/SMC_Structures.pm` (viejo unificado)  

(y sus Overlays homólogos). Liquidity v1 del archive **no** se reutiliza.

## Tests oficiales (suite de producto)

Entre otros: `t/00`, `t/24`, `t/27`, `t/28`, `t/29`, `t/30`, `t/31`, `t/32` (Liquidity v2), `t/38` (geometría causal Replay), `t/14`,  
eje/replay base (`t/01`–`t/07`, `t/11`–`t/13`, `t/25`–`t/26`, `t/37`).

## Regla de oro

**Liquidity v2** se implementó desde cero (FSM + pivotes k-swing + export hacia modelos).  
No se reactiva el Liquidity del archive. Ver `docs/LIQUIDITY_V2.md`.
