# Producto oficial (canónico)

**Última actualización:** 2026-07-18  
**Política:** solo este stack se carga en runtime. Todo lo demás está **fuera del repo** (`docs/LEGACY.md`).

## Capas e indicadores oficiales

| Pieza | Módulos | Validación |
|--------|---------|------------|
| Chart OHLC + TF + Replay + Escala + ATR | `MarketData`, `ChartEngine`, panels, `ReplayController`, `ATR` | Base |
| **SMC Pro** | `Indicators/Overlays/SMC_Pro.pm` | Captura Neon TV |
| **Structures + FVG** | `Indicators/Overlays/SMC_Structures_FVG.pm` | Captura LudoGH |
| **HLD (4h/D)** | `Indicators/Overlays/HLD.pm` | Video profe ~40–46 min |
| **Parallel Channel** | `Drawing/Overlays/ParallelChannel.pm` | Herramienta TV 3 clics |
| **ZigZag ext + int** | `Indicators/Overlays/ZigZag.pm` | ChartPrime + ZZMTF |
| **Fib Retracement** | `Drawing/Overlays/FibRetracement.pm` | Clone TV |

## Runtime

`ChartEngine->new` registra únicamente:  
`smc_pro`, `smc_fvg`, `hld`, `pchan`, `zigzag`, `fib`.

No existen en el árbol del repo:

- `Market/Indicators/Liquidity.pm`  
- `Market/Indicators/Mxwll_Suite.pm`  
- `Market/Indicators/Strategy_Builder.pm`  
- `Market/Indicators/VolumeProfile.pm`  
- `Market/Indicators/AnchoredVWAP.pm`  
- `Market/Indicators/SMC_Structures.pm` (viejo unificado)  

(y sus Overlays homólogos).

## Tests oficiales (suite de producto)

Entre otros: `t/00`, `t/24`, `t/27`, `t/28`, `t/29`, `t/30`, `t/31`, `t/14`,  
eje/replay base (`t/01`–`t/07`, `t/11`–`t/13`, `t/25`–`t/26`).

## Regla de oro

**Liquidity y el resto del legacy no se “activan”.**  
Se reimplementan desde cero cuando toque el plan maestro (PDF + FSM + pivotes oficiales).
