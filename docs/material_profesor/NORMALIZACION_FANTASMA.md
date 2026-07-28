# Normalización fantasmita — Paso 3

**Estado:** HECHO (2026-07-27) — listo para LSTM (Paso 4).  
**Corrida:** train 7649 / test 2391 filas; **86** features z-score; stats en `Data/ml_out/fantasma_norm_stats.json`.

## Qué hace

1. Lee CSV del extractor (`fantasma_train_*.csv` / `fantasma_test_*.csv`).
2. Elige columnas numéricas de features (ver exclusiones).
3. **Fit solo en train** (z-score: media / desvío muestral).
4. Aplica los mismos parámetros a train y test.
5. Guarda CSVs normalizados + `fantasma_norm_stats.json`.

Método por defecto: **z-score**. Alternativa: `--method minmax`.

## Cómo correr (Fedora35)

```bash
cd /mnt/c/Users/bryan/ia/proyecto_iaaa/Proyecto/ProyectoIAAA

perl -I. scripts/normalize_fantasma_dataset.pl \
  --train Data/ml_out/fantasma_train_abril_junio.csv \
  --test  Data/ml_out/fantasma_test_julio.csv \
  --out-train Data/ml_out/fantasma_train_norm.csv \
  --out-test  Data/ml_out/fantasma_test_norm.csv \
  --stats     Data/ml_out/fantasma_norm_stats.json
```

## Paths de salida

| Archivo | Rol | Tamaño corrida |
|---|---|---|
| `Data/ml_out/fantasma_train_norm.csv` | Train normalizado (meta/labels intactos; features z-score) | ~12M / 7649 filas |
| `Data/ml_out/fantasma_test_norm.csv` | Test con **stats de train** | ~3.8M / 2391 filas |
| `Data/ml_out/fantasma_norm_stats.json` | `mean`/`std` por columna + lista de features | ~15K |

## Selección de columnas

| Grupo | Tratamiento |
|---|---|
| `meta_*`, `time` | **No** normalizar como feature de train; se copian tal cual (validación / debug) |
| `y3,y5,y10,y15` | Labels; se copian **sin** normalizar |
| `sgr_kind_1m/10m/1h` | Categoricos string → **excluidos** en v1 (no one-hot). Deuda LSTM si se quieren |
| `ref_mid_pips` | Precio mid absoluto / PIP → **excluido por defecto** (filtra nivel de precio; audit Paso 2). Flag `--include-ref-mid-pips` si se insiste |
| Resto numerico (`atr_*`, `vol_*`, `pip_*`, …) | Features normalizadas (**86** en pack full) |

Vacios en features → **0** antes de fit/apply (documentado en stats `missing_as_zero`).

Columnas constantes (`std≈0`): se fuerza `std=1` → z queda 0.

## Modulo / CLI

| Path | Rol |
|---|---|
| `Market/ML/NormalizeFantasmaDataset.pm` | Fit / apply / I/O CSV+JSON |
| `scripts/normalize_fantasma_dataset.pl` | CLI |

## Contrato para Paso 4 (LSTM)

- Matriz X = columnas listadas en `feature_columns` del JSON (orden estable; 86 cols).
- Targets = `y3,y5,y10,y15` (enteros; no normalizados).
- Cargar `fantasma_norm_stats.json` si se re-escala inferencia offline; los CSV `*_norm.csv` ya traen X lista.
- `seq_len≈5` (oral/lab) se arma en el trainer, no aqui.
- **No** rebalancear clases.

## Deuda aceptable

1. One-hot de `sgr_kind_*` no implementado (omitidos).
2. `ref_mid_pips` sigue en el CSV crudo/norm como columna passthrough, pero **no** entra en `feature_columns`.
3. Imputacion simple (vacio→0) puede sesgar distancias ausentes; alternativa futura: mascara / indicador de missing.
4. Test extract se corrió **antes** del fix AVWAP; train **después**. Audit Paso 3: `get_point(i)` = prefijo causal → regenerar test **opcional** (no bloquea LSTM). Ver [`AUDIT_PASO3_CIERRE.md`](AUDIT_PASO3_CIERRE.md).
