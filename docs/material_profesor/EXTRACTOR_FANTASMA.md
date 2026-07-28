# Extractor fantasmita — Paso 2 (Opción A)

**Estado:** HECHO_CON_DEUDA (cierre 2026-07-27 — `AUDIT_PASO2_CIERRE.md`)  
**Contrato labels:** Opción A — comportamiento actual de `Market::Indicators::PivotPointsHL` / comentario Josafa (rastro `"1"` solo si la punta provisional se mueve; marca en punta **previa**). Ver `AUDIT_PASO1_CIERRE.md`.

## Qué hace

Script headless (sin Tk) que recorre un CSV OHLCV 1m en modo Replay causal y, en cada **aparición o reubicación** del fantasma provisional, emite una fila:

| Bloque | Contenido |
|---|---|
| Metadata (NO entrenar) | `meta_time`, `meta_date`, `meta_hour`, `meta_minute`, índices, punta, contrato `A` |
| Labels | `y3 y5 y10 y15` = nº de trails creados en `(event_bar, event_bar+H]` |
| Features | distancias en **PIPs** a niveles + ATR/vol (pack `full`) |

**PIP NQ:** `1 PIP = 0.25` (1 tick).  
**Precio de referencia:** media `(high+low)/2` de la vela donde está la punta del fantasma.  
**Vela de predicción:** `feature_bar = event_bar + 1` (siguiente a la aparición), con estructura causal ≤ `event_bar`.

## Cómo correr (Fedora35 / WSL)

```bash
cd /mnt/c/Users/bryan/ia/proyecto_iaaa/Proyecto/ProyectoIAAA

# Smoke (~1ª semana abril, máx. 80 muestras)
perl -I. scripts/extract_fantasma_dataset.pl --smoke

# Solo núcleo (disparo + labels + ATR/vol; más rápido)
perl -I. scripts/extract_fantasma_dataset.pl --smoke --pack core

# Train completo (puede tardar mucho)
perl -I. scripts/extract_fantasma_dataset.pl \
  --csv Data/2026_Abril-Junio.csv \
  --out Data/ml_out/fantasma_train_abril_junio.csv --pack full

# Test julio
perl -I. scripts/extract_fantasma_dataset.pl \
  --csv Data/2026_07_24.csv \
  --out Data/ml_out/fantasma_test_julio.csv --pack full
```

Salida por defecto del smoke: `Data/ml_out/fantasma_smoke_abril_w1.csv`.

## Módulo / CLI

| Path | Rol |
|---|---|
| `Market/ML/ExtractFantasmaDataset.pm` | Carga CSV, feed causal, features, labels, write CSV |
| `scripts/extract_fantasma_dataset.pl` | CLI |
| `t/50-extract-fantasma-dataset.t` | Test sintético Opción A (core) |

## Features pack `full` (por TF `1m` / `10m` / `1h`)

- OB (nivel + espesor), FVG (nivel + rango)
- Fib ZZ ext (0.236…0.786 + nearest)
- AVWAP anclado al fantasmita (+ bandas) y al último pivot regular
- AVP POC / VAH / VAL (ancla ZZ ext consolidado)
- BOS / CHoCH, EQH / EQL
- DIY supply/demand
- Canal auto (si hay canal activo)
- S/G/R (`pip_sgr_*` + `sgr_kind_*`) si Liquidity resolvió eventos; si no, vacío
- Extra 1m: `atr_1m`, `vol_1m`, `vol_ema9_1m`
- HLD 4h/D + S/R semanal (high/low/mid de W cerrada)

Pack `core`: solo ATR/vol/EMA vol + labels + metadata (útil para validar muestreo).

## MarketData `10m`

Se agregó TF `10m` a `Market::MarketData` (DOCX mediana). La GUI no cambia el default CSV.

## Deuda / riesgos (auditor Paso 2)

Cierre: **`AUDIT_PASO2_CIERRE.md`** → **PASS_CON_RIESGOS**; gate Paso 3 **SÍ**.

1. **Canal auto** puede salir nulo con frecuencia (condicional DOCX: 3 toques ≥2h + ATR bajo); en smoke 1ª semana abril quedó vacío.
2. **Fib 1m** usa `swing_length=150` (producto): al inicio de serie no hay pierna consolidada → columnas vacías hasta calentamiento (~cientos de velas). HTF usa ZZ más corto (10m:40, 1h:20).
3. **AVP** batch usa `row_size=200` (más ligero que 1000 TV).
4. **Paridad TV del fantasma** no reclamada (D2/D3 deuda Paso 1.5); labels = Opción A.
5. Full run abr–jun (~88k × indicadores multi-TF): tras fix `AnchoredVWAP::set_anchor` (sin preload `size()`), train full ~38 min / test ~51 min (test fue pre-fix). Progreso STDERR cada 1000 barras. Tip I/O: `scripts/run_fantasma_full_extracts.sh` (CSV en `/tmp`). Tras `max_samples` el feed continúa `+15` barras para no truncar labels.
6. No hay campos nuevos en `Market/Debug/`; el test no usa IndicatorSnapshot.
7. **EQH en 1h** a veces vacío (pocos equal highs en serie corta).
8. **Normalización:** [`NORMALIZACION_FANTASMA.md`](NORMALIZACION_FANTASMA.md) — z-score train-only; 86 feats; excluye `meta_*`, `y*`, `sgr_kind_*`, `ref_mid_pips`. Corrida 2026-07-27: train 7649 / test 2391.
