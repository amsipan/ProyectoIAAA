# UI — fase actual (paso a paso)

## Activo

| Pieza | Notas |
|--------|--------|
| Chart OHLC + TF + Replay + Escala | Base |
| **SMC Pro** | Indicador 1 verificado |
| **SMC Structures+FVG** | Indicador 2 verificado |
| **Parallel Channel** | Herramienta TV (3 clics); un canal a la vez |
| **HLD (4h/D)** | S/R de vela HTF (algoritmo profe, sin Pine); solo TF **4h** y **D** |
| **ZigZag externo** | ChartPrime captura profe: **Length 150**, solo línea azul; VP/Channel/PoC **OFF** |
| **ZigZag interno** | ZZMTF (LonesomeTheBlue): **Resolution 30** (UI 15/30/60), **Period 2**, **Show ZigZag ON**, Fibonacci **OFF**, colores **verde/rojo** |
| **Fibonacci** | Anclado a la **última pierna consolidada del ZZ externo** (no el tip vivo; no SMC HH/HL). TF bajas: 0.382/0.5/0.618; TF altas: 5 niveles |

## Desactivado (código conservado)

- Fibonacci del panel ZZMTF interno (Show Fibonacci del script LonesomeTheBlue)
- Canal por pierna ZZ / Swing Channel ChartPrime
- Liquidity
- Strategy Builder
- Anchored VWAP / Volume Profile
- Mxwll (fuera de producto)

**Reactivar:** comentarios `FASE ACTUAL` / `PASO A PASO` en `market.pl` y `ChartEngine.pm`.

## Dataset

Base nativa **15m** (`Data/tv_nq1_15m.csv`). 4h/D se agregan desde 15m.

## HLD — recordatorio

- Video ~40:00–46:30; sin indicador TV.
- Elige vela pasada (rango que contiene el precio, o OHLC más cercano).
- Dibuja high=resistencia, low=soporte hasta la última vela.
- ATH → no dibuja (usar VWAP en fase posterior).
