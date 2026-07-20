# Investigación SMC — paridad TradingView (2026-07-17)

## Sources en repo

| Source | Estado |
|--------|--------|
| `docs/reference_indicators/smc_pro_neon.txt` | Copiado (antes faltaba) |
| `docs/reference_indicators/smc_structures_and_fvg_ludogh68.txt` | Copiado (antes faltaba) |
| `docs/reference_indicators/luxalgo_smc.txt` | Ya existía (v5 clásico) |

`C:\Users\bryan\Downloads\Proyecto` **no se modifica**.

## Eliminar del producto activo

- Capa **Mxwll** (UI, ChartEngine, densidad, tests de producto)
- Híbrido viejo `SMC_Structures` (causal k + fib major) como verdad de estructura
- Densidad SMC `PIVOTS/EVENTS/FVG/FIBS/MAJOR` y pestaña Mxwll
- FVG del SMC Pro (OFF en captura)
- Internal Order Blocks (OFF en captura)
- Structure Fibs LudoGH (OFF en captura)

## Conservar / reescribir

- Dos capas TV: **SMC Pro** + **Structures+FVG**
- Replay, multi-TF, Liquidity (pivotes externos desde SMC Pro swing)
- Sources de referencia

## Config captura (resumen)

Ver plan aprobado y `specs/0013-smc-tv-parity-neon-ludogh.md`.
