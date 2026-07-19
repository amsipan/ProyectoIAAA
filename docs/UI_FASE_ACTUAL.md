# UI — producto oficial (paso a paso)

Lista canónica: **`docs/PRODUCTO_OFICIAL.md`**.  
Código viejo aislado: **`docs/LEGACY.md`** + carpeta `legacy/`.

## Activo (oficial)

| Pieza | Notas |
|--------|--------|
| Chart OHLC + TF + Replay + Escala | Base |
| **SMC Pro** | Neon TV |
| **SMC Structures+FVG** | LudoGH |
| **Parallel Channel** | 3 clics TV |
| **HLD (4h/D)** | Video profe |
| **ZigZag externo / interno** | ChartPrime + ZZMTF |
| **Fib Retracement** | Herramienta TV |

## No reactivar sin rediseño

- Liquidity (en `legacy/`) — no es paridad TV 1:1; rehacer desde PDF
- Mxwll, Strategy, VP, VWAP, SMC_Structures unificado — `legacy/`
- Placeholder HTF sobre LTF — eliminado

## Dataset

Base nativa **15m** (`Data/tv_nq1_15m.csv`). 4h/D se agregan desde 15m.

## Fib Retracement — uso

1. **Fib Retracement** → clic 1 (nivel **1**) y clic 2 (nivel **0**), como en TV.
2. **Desde ZZ ext** → modo “elige pierna”: clic en la **línea azul** del ZZ externo que quieras (no elige al azar). Impulso from→to = 1→0 (bajista: 1 arriba, 0 abajo).
3. Arrastrar handles **azules** (p1/p2): mueven precio **e** índice; la caja y las etiquetas se mueven con ellos (sin handles de ancho sueltos).
4. **Hasta última vela** → proyecta la caja solo hasta la última vela del dataset.
5. **Desde ZZ ext** también marca el checkbox **ZigZag externo** en Capas.
6. **Borrar Fib** / Esc cancela el modo.

## HLD — recordatorio

- Video ~40:00–46:30; sin indicador TV.
- Elige vela pasada (rango que contiene el precio, o OHLC más cercano).
- Dibuja high=resistencia, low=soporte hasta la última vela.
- ATH → no dibuja (usar VWAP en fase posterior).
