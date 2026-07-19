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
| **ZigZag interno** | ZZMTF: **Resolution 30** (UI 15/30/60), **Period 2**, Show ZigZag ON, fib OFF |
| **Fib Retracement** | Herramienta nativa TV (2 clics): bandas de color, niveles **0…1**, anclas p1/p2 arrastrables, Ext←/Ext→, atajo **Desde ZZ ext** |

## Desactivado (código conservado)

- Fibonacci del panel ZZMTF (Show Fibonacci del script LonesomeTheBlue)
- Canal por pierna ZZ / Swing Channel ChartPrime
- Liquidity
- Strategy Builder
- Anchored VWAP / Volume Profile
- Mxwll (fuera de producto)

**Reactivar:** comentarios `FASE ACTUAL` / `PASO A PASO` en `market.pl` y `ChartEngine.pm`.

## Dataset

Base nativa **15m** (`Data/tv_nq1_15m.csv`). 4h/D se agregan desde 15m.

## Fib Retracement — uso

1. **Fib Retracement** → clic 1 (nivel 1) y clic 2 (nivel 0), p. ej. extremos de la pierna azul.
2. O **Desde ZZ ext** para anclar a la última pierna consolidada del ZigZag externo.
3. Arrastrar handles azules (p1/p2) o naranjas (bordes L/R) para mover/ampliar.
4. **Ext← / Ext→** extienden el rectángulo al borde de la vista.
5. **Borrar Fib** limpia el dibujo.

## HLD — recordatorio

- Video ~40:00–46:30; sin indicador TV.
- Elige vela pasada (rango que contiene el precio, o OHLC más cercano).
- Dibuja high=resistencia, low=soporte hasta la última vela.
- ATH → no dibuja (usar VWAP en fase posterior).
