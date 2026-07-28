# LSTM fantasmita — Paso 4

**Estado:** HECHO_CON_DEUDA (2026-07-27). Cierre: [`AUDIT_PASO4_CIERRE.md`](AUDIT_PASO4_CIERRE.md) → **PASS_CON_RIESGOS**; gate demo **SÍ**.  
Regresión MSE multi-salida `y3/y5/y10/y15`, **sin CNN**.  
**Entorno:** WSL Fedora35 + MXNet parcheado (Paso 0).

## Corrida v1 (referencia)

- Hiperparams: `seq_len=5`, `batch=64`, `hidden=32`, `layers=1`, `dropout=0.2`, `lr=0.01`, `epochs=20`, Adam + L2Loss.
- Train: 7649 filas → 7645 secuencias; test: 2391 → 2387 secuencias.
- Train time ~156 s; L2 train 1.87 → 1.10.
- Test julio (`metrics_test.json`):

| Target | MAE | RMSE | bin_acc (≥1) |
|---|---:|---:|---:|
| y3 | 0.91 | 1.14 | 0.48 |
| y5 | 1.31 | 1.67 | 0.57 |
| y10 | 2.15 | 2.75 | 0.68 |
| y15 | 2.81 | 3.58 | 0.72 |

Smoke 1 epoch tuvo MAE de test algo mejor → sospecha de overfit; tuning = deuda.

## Qué hace

1. Lee CSVs normalizados (`fantasma_{train,test}_norm.csv`) + lista de features de `fantasma_norm_stats.json` (86 cols).
2. Arma ventanas secuenciales de longitud `seq_len` (default **5**, como el lab) sobre filas de muestras en **orden temporal del CSV**.
3. Entrena un LSTM Gluon (layout `NTC`) + Dense lineal a **4 salidas** (regresión).
4. Evalúa solo en test julio: **MAE / RMSE** por ventana; opcional **accuracy binaria** (`pred >= 1` vs `label >= 1`).
5. Guarda modelo, métricas, predicciones y config en `Data/ml_out/lstm_fantasma/`.

Label de cada ventana = targets de la **última fila** de la secuencia (mismo criterio que el lab acústico).

## Cómo entrenar (Fedora35)

```bash
cd /mnt/c/Users/bryan/ia/proyecto_iaaa/Proyecto/ProyectoIAAA

perl -I. scripts/train_fantasma_lstm.pl \
  --train Data/ml_out/fantasma_train_norm.csv \
  --test  Data/ml_out/fantasma_test_norm.csv \
  --stats Data/ml_out/fantasma_norm_stats.json \
  --out-dir Data/ml_out/lstm_fantasma \
  --seq-len 5 --batch-size 64 --hidden 32 --epochs 20
```

Log sugerido:

```bash
perl -I. scripts/train_fantasma_lstm.pl --epochs 20 \
  --out-dir Data/ml_out/lstm_fantasma \
  > Data/ml_out/lstm_fantasma/train.log 2>&1
```

Solo evaluar un modelo ya guardado:

```bash
perl -I. scripts/train_fantasma_lstm.pl --eval-only \
  --model Data/ml_out/lstm_fantasma/fantasma_lstm.params \
  --out-dir Data/ml_out/lstm_fantasma
```

## Paths de salida

| Archivo | Rol |
|---|---|
| `Data/ml_out/lstm_fantasma/fantasma_lstm.params` | Pesos Gluon (`save_parameters`) |
| `Data/ml_out/lstm_fantasma/metrics_test.json` | MAE/RMSE + bin_acc por `y3/y5/y10/y15` |
| `Data/ml_out/lstm_fantasma/preds_test.csv` | `true_*` / `pred_*` + meta de la fila final de cada ventana |
| `Data/ml_out/lstm_fantasma/train_config.json` | Hiperparámetros + n_features / secuencias |
| `Data/ml_out/lstm_fantasma/train.log` | Log de la corrida |

## Módulo / CLI

| Path | Rol |
|---|---|
| `Market/ML/FantasmaLSTMData.pm` | Carga CSV+stats, `make_sequences`, métricas, I/O JSON/CSV |
| `scripts/train_fantasma_lstm.pl` | Modelo LSTM Gluon, train/eval MXNet |

Referencia de lab:  
`docs/material_aula_virtual/09_mxnet_patches/lstm_prueba_acustica/LSTM/09_02_02-Concise_Implementation_of_LSTM.pl`

## Hiperparámetros por defecto

| Param | Default | Nota |
|---|---:|---|
| `seq_len` | 5 | Pista oral 27 / lab |
| `batch_size` | 64 | Bajar a 32 si OOM |
| `hidden` | 32 | Bajar a 16 si OOM |
| `num_layers` | 1 | |
| `dropout` | 0.2 | |
| `lr` | 0.01 | Adam |
| `epochs` | 20 | |
| loss | L2Loss | MSE (Gluon divide por 2 internamente) |
| CNN | no | DOCX: sin CNN primero |

## Contrato de datos

- **X:** columnas de `feature_columns` en `fantasma_norm_stats.json` (86; ya z-score).
- **y:** `y3,y5,y10,y15` enteros, **sin** normalizar.
- **No** entra `meta_*`, `sgr_kind_*`, `ref_mid_pips`.
- Train solo abr–jun; test solo julio.
- **No** rebalancear clases.

## Interpretación rápida de métricas

- **MAE / RMSE:** error de conteo de rastros por ventana (regresión).
- **bin_acc (≥1):** aparece/no aparece al menos un rastro en la ventana (complemento oral clasificación).
- Desbalance (muchos 0 en ventanas cortas) es esperado; no se rebalancea.

## Si falla

| Síntoma | Acción |
|---|---|
| OOM / crash MXNet | `--batch-size 32 --hidden 16` |
| Error de shapes | Verificar `*_norm.csv` + stats 86 feats; `seq_len` ≤ filas |
| MXNet no carga | Rehacer Paso 0 (patches) |
| `tolist` raro | El script usa `tolist` en **contexto lista** (escalar solo da el conteo) |

## Deuda / siguiente

Gate demo abierto (`AUDIT_PASO4_CIERRE.md`). Deuda **no** bloqueante:

1. Overfit posible (smoke 1-epoch mejor en test que epochs=20) → early-stop / menos epochs.
2. bin_acc y3 débil (~0.48); F1/P/R no reportados (oral 27; opcional desde `preds_test.csv`).
3. CNN opcional; cabezas binarias; one-hot `sgr_kind_*`.
4. Regenerar test extract post-fix AVWAP (opcional; `AUDIT_PASO3_CIERRE.md`).
5. **Ahora:** Paso 6 presentación — guion [`GUION_PRESENTACION_FINAL.md`](GUION_PRESENTACION_FINAL.md) + `scripts/demo_fantasma_predict.pl`; t-SNE→GMM→HMM = Paso 5 paralelo si alcanza.
