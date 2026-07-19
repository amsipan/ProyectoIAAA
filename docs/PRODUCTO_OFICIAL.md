# Producto oficial (canónico)

**Última actualización:** 2026-07-18 (post Fib Retracement + limpieza legacy).  
**Rama de trabajo típica:** `feature/fib-retracement-tv-tool` / `chore/producto-oficial-cleanup`.

Solo lo listado aquí se considera **comprobado** con capturas/video del profe o uso validado en esta fase.  
Todo lo demás es **legacy** (ver `docs/LEGACY.md`) y **no debe reactivarse** sin rediseño.

## Capas e indicadores oficiales

| Pieza | Módulos | Validación |
|--------|---------|------------|
| Chart OHLC + TF + Replay + Escala + ATR | `MarketData`, `ChartEngine`, panels, `ReplayController`, `ATR` | Base del proyecto |
| **SMC Pro** | `Indicators/Overlays/SMC_Pro.pm` | Captura Neon TV |
| **Structures + FVG** | `Indicators/Overlays/SMC_Structures_FVG.pm` | Captura LudoGH |
| **HLD (4h/D)** | `Indicators/Overlays/HLD.pm` | Video profe ~40–46 min |
| **Parallel Channel** | `Drawing/Overlays/ParallelChannel.pm` | Herramienta TV 3 clics |
| **ZigZag externo** | `ZigZag.pm` (EXTERNAL) | ChartPrime captura, Length 150 |
| **ZigZag interno** | `ZigZag.pm` (INTERNAL) | ZZMTF captura, res 15/30/60, period 2 |
| **Fib Retracement** | `Drawing/Overlays/FibRetracement.pm` | Clone TV + ancla ZZ consolidado |

## Runtime

`ChartEngine->new` registra únicamente:  
`smc_pro`, `smc_fvg`, `hld`, `pchan`, `zigzag`, `fib`.

## Tests oficiales (deben mantenerse verdes)

`t/00-load-and-syntax.t`, `t/24-zigzag.t`, `t/27-smc-structures-fvg.t`, `t/14-overlay-smc-render.t` (si aplica Pro),  
`t/28-base-tf-15m.t`, `t/29-parallel-channel.t`, `t/30-hld.t`, `t/31-fib-retracement.t`,  
más tests de eje/replay base (`t/01`–`t/07`, `t/11`–`t/13`, `t/25`–`t/26`) según no dependan de legacy.

## Regla de oro

**Liquidity, Mxwll, Strategy, VP, VWAP y el SMC_Structures unificado viejo no son producto oficial.**  
Si se necesita Liquidity de nuevo: **implementar desde el PDF del profe** y pivotes del stack oficial (ZZ / SMC Pro), no reactivar el módulo en `legacy/`.
