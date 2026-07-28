# Check Fase 0 + Fase 1 - modelo v2 (2026-07-28)

Verificacion ejecutada sobre el working tree Windows (datos en `Data/ml_out/`).
Resultado global: **FASE 0 OK / FASE 1 OK - listo para Fase 2 (entrenamiento, en Fedora35).**

## Fase 0 - baseline congelado

- `Data/ml_out/lstm_fantasma/` **intacto**: hashes SHA256 de los 9 artefactos tomados
  antes y despues del trabajo de Fase 0/1; **identicos** (ningun archivo modificado).
- Workspace v2 creado: `Data/ml_out/lstm_fantasma_v2/`.
- Nota de trabajo: `docs/material_profesor/MODELO_V2_TRABAJO.md`.
- Baseline binario v1 regenerado desde `preds_test.csv` (equivalente parametrizado de
  `scripts/compute_fantasma_binary_metrics.py`, sin reentrenar):
  `Data/ml_out/lstm_fantasma_v2/baseline_v1_binary_metrics.json`.
  - **MATCH exacto** con `lstm_fantasma/binary_metrics_test.json` (metricas y confusiones
    de y3/y5/y10/y15 verificadas campo a campo).

### Baseline v1 (referencia de comparacion, test julio, n=2387)

| Target | acc | prec | rec | spec | F1 | TP/FP/TN/FN |
|---|---:|---:|---:|---:|---:|---|
| y3 | 0.4755 | 0.7108 | 0.3197 | 0.7613 | 0.4411 | 494/201/641/1051 |
| y5 | 0.5689 | 0.7682 | 0.5642 | 0.5806 | 0.6506 | 958/289/400/740 |
| y10 | 0.6778 | 0.8276 | 0.7461 | 0.4252 | 0.7848 | 1402/292/216/477 |
| y15 | 0.7151 | 0.8533 | 0.7889 | 0.3756 | 0.8198 | 1547/266/160/414 |

Regresion v1 (de `metrics_test.json`): MAE y3 0.91 / y5 1.31 / y10 2.15 / y15 2.81.

## Fase 1 - higiene de datos + reproducibilidad

### `fantasma_norm_stats.json`

- `feature_columns`: **86** (coincide con `n_features=86` y con train_config v1).
- `stats.columns`: 86 entradas con `mean/std/n` por feature (n=7649 = fit solo train). OK.
- `method`: zscore; `missing_as_zero=1`; `sgr_kind_encoding=excluded_v1`;
  `include_ref_mid_pips=0`; excluidos `meta_*`, `y*`, `sgr_kind_*`, `ref_mid_pips`. OK.
- `train_rows=7649`, `test_rows=2391` (coincide con los CSV). OK.

### CSVs normalizados

| Archivo | Filas datos | Esperado | Estado |
|---|---:|---:|---|
| `fantasma_train_norm.csv` | 7649 | 7649 | OK |
| `fantasma_test_norm.csv` | 2391 | 2391 | OK |

Headers identicos en ambos: 10 `meta_*` + 4 labels (`y3,y5,y10,y15`) + `atr_1m, vol_1m,
vol_ema9_1m, ref_mid_pips` + 86 features normalizadas + 3 `sgr_kind_*` (string). OK.

### Distribucion de labels (conteo por valor)

**Train (n=7649):**

| Label | 0 | 1 | 2 | 3 | 4+ | masa 0..3 | P(>=1) |
|---|---:|---:|---:|---:|---:|---:|---:|
| y3 | 2953 | 2214 | 1628 | 854 | - | **100%** | 61.4% |
| y5 | 2503 | 1757 | 1460 | 1135 | 794 | **89.6%** | 67.3% |
| y10 | 1911 | 1377 | 1192 | 1028 | 2141 | **72.0%** | 75.0% |
| y15 | 1611 | 1151 | 1059 | 961 | 2867 | **62.5%** | 78.9% |

**Test (n=2391):**

| Label | 0 | 1 | 2 | 3 | 4+ | masa 0..3 | P(>=1) |
|---|---:|---:|---:|---:|---:|---:|---:|
| y3 | 846 | 688 | 546 | 311 | - | **100%** | 64.6% |
| y5 | 693 | 527 | 490 | 379 | 302 | **87.4%** | 71.0% |
| y10 | 512 | 393 | 361 | 341 | 784 | **67.2%** | 78.6% |
| y15 | 430 | 312 | 298 | 280 | 1071 | **55.2%** | 82.0% |

La masa 0..3 de train **reproduce exactamente** los numeros documentados en el cierre del
Paso 3 (y3 100%, y5 89.6%, y10 72.0%, y15 62.5%). El test muestra la misma forma con
sesgo algo mayor a conteos altos (coherente con julio mas activo). Maximos observados:
y3 <=3; y5 <=5; y10 <=10; y15 <=14 (train) / <=12 (test).

### Reproducibilidad (de `train_config.json` v1)

- `seq_len=5` **confirmado**; secuencias resultantes: train 7645 (=7649-5+1) y test
  2387 (=2391-5+1) - aritmetica consistente con ventana deslizante de 5.
- `seed=42` **confirmado**; optimizer adam, loss L2Loss, hidden=32, dropout=0.2,
  lr=0.01, batch=64, epochs=20, num_layers=1.
- Split: train abr-jun / test julio, ya normalizados; el mismo par de CSVs es la entrada
  de v2 (no se re-extrae).

## Riesgos / notas para Fase 2

1. **Prevalencia positiva alta en ventanas largas** (y15: 78.9% train / 82.0% test):
   un predictor trivial "siempre >=1" ya logra acc ~0.82 en y15. Exigir a v2 mejorar
   **F1 y specificity**, no solo accuracy, en y10/y15.
2. **Desbalance inverso en y3** (38.6% ceros): es la ventana mas dificil para v1
   (acc 0.4755, F1 0.4411); esperable mejora acotada - el plan ya prioriza MAE como
   criterio primario.
3. Dataset **estable y congelado**: cualquier mejora de v2 sera atribuible al modelo,
   no a los datos (mismos CSVs, mismo stats JSON, mismo seq_len/seed de partida).
4. Entrenamiento v2 debe correr en **Fedora35 (MXNet)**; este check solo valida datos.

## Gate

- [x] v1 intacto (hashes verificados pre/post)
- [x] Workspace v2 limpio creado
- [x] Baseline binario v1 reproducible (MATCH exacto)
- [x] Dataset estable: filas, 86 features, labels y masa 0..3 verificadas
- [x] `seq_len=5` y `seed=42` confirmados

**Listo para auditor de Fase 0/1 y para iniciar Fase 2 (early stopping / grid).**