# LSTM Fantasma v2 — entrenamiento anti-overfit (Fase 2)

**Fecha:** 2026-07-28
**Plan maestro:** `docs/PLAN_REENTRENAMIENTO_MODELO_V2.md` (Fase 2)
**Script nuevo:** `scripts/train_fantasma_lstm_v2.pl` (v1 `scripts/train_fantasma_lstm.pl` intacto)
**Artefactos:** `Data/ml_out/lstm_fantasma_v2/`

## Qué cambió vs v1

| Aspecto | v1 (baseline) | v2 |
|---|---|---|
| Validación | No había; se entrenaba fijo 20 epochs | Cola causal del train (15% = 1147 filas) **nunca** se entrena |
| Parada | Epochs fijas | **Early stopping**: paciencia 4, min_delta 0.0005 sobre MAE promedio de val |
| Checkpoint | Estado final (epoch 20) | **Mejor checkpoint** por MAE de val de cada run |
| Dropout | 0.2 declarado pero inerte (dropout interno LSTM solo aplica entre capas; con 1 capa no hace nada) | Capa `Dropout` **explícita** sobre el último estado oculto, antes del Dense |
| Hiperparámetros | Una sola config | Grid corto de 8 runs (hidden/dropout/lr/batch), selección por menor MAE de val |
| Epochs | 20 fijas | Tope 25; early stop corta cuando val deja de mejorar |

El diagnóstico que motiva v2: en v1 el smoke de 1 epoch a veces ganaba en test al modelo de
20 epochs → overfit claro. En los runs v2 se ve la curva clásica: val/test MAE tocan fondo
hacia epoch 3–6 y luego suben mientras train_L2 sigue bajando (ver `train_v2.log`).

## Diseño del grid (búsqueda corta justificada)

- `epochs ∈ {5,10,15,20}` **no** se barre a ciegas: se reemplaza por tope 25 + early stop
  (paciencia 4), que encuentra el punto óptimo de parada por sí solo en cada run.
- 8 configs balanceadas cubriendo `hidden ∈ {16,32,48}`, `dropout ∈ {0.1,0.2,0.3}`,
  `lr ∈ {0.005,0.01}`, `batch ∈ {32,64}`:

| Run | hidden | dropout | lr | batch |
|---|---:|---:|---:|---:|
| r01 | 32 | 0.2 | 0.01 | 64 |  (config ≈ v1 + early stop + dropout real)
| r02 | 16 | 0.2 | 0.01 | 64 |
| r03 | 48 | 0.3 | 0.01 | 64 |
| r04 | 32 | 0.3 | 0.005 | 64 |
| r05 | 16 | 0.3 | 0.005 | 64 |
| r06 | 48 | 0.2 | 0.005 | 32 |
| r07 | 32 | 0.1 | 0.01 | 32 |
| r08 | 16 | 0.1 | 0.005 | 64 |

- Misma semilla (42) en todos los runs para aislar el efecto de hiperparámetros.
- Selección del run ganador: **menor MAE promedio en validación** (criterio primario del
  plan); test julio solo se reporta, no se usa para elegir (sin fuga de test).

## Cómo correr (WSL Fedora35)

```bash
wsl -d Fedora35 -- bash -lc "cd /mnt/c/Users/bryan/ia/proyecto_iaaa/Proyecto/ProyectoIAAA && \
  perl scripts/train_fantasma_lstm_v2.pl \
    --grid 'r01:32:0.2:0.01:64,r02:16:0.2:0.01:64,r03:48:0.3:0.01:64,r04:32:0.3:0.005:64,r05:16:0.3:0.005:64,r06:48:0.2:0.005:32,r07:32:0.1:0.01:32,r08:16:0.1:0.005:64' \
    --epochs 25 --patience 4 --min-delta 0.0005 --val-frac 0.15 --seed 42 \
    2>&1 | tee Data/ml_out/lstm_fantasma_v2/train_v2.log"
```

Formato del grid: `nombre:hidden:dropout:lr:batch` separado por comas.
Run individual (sin `--grid`): usar `--hidden/--dropout/--lr/--batch-size` como en v1.

Re-evaluar el modelo final sin reentrenar (hereda la config elegida de
`train_config_v2.json`):

```bash
perl scripts/train_fantasma_lstm_v2.pl --eval-only
```

## Artefactos producidos

| Archivo | Contenido |
|---|---|
| `fantasma_lstm_v2.params` | Mejor checkpoint del run ganador |
| `train_config_v2.json` | Config elegida + tabla de los 8 runs con historial por epoch |
| `metrics_test_v2.json` | MAE/RMSE por y3–y15 + bin_acc (≥1, comparable v1) + confusión completa (pred≥0.5) |
| `preds_test_v2.csv` | Predicciones vs reales en test julio (n=2387) |
| `train_v2.log` | Log completo del grid |

## Resultados (test julio, n=2387)

**Run ganador: r06** (`hidden=48, dropout=0.2, lr=0.005, batch=32`), mejor epoch **3**
(val_MAE=1.5419; early stop en epoch 7). Selección por **validación**, no por test.

| Run | h | d | lr | b | epochs | best_ep | val_MAE | test_MAE@best |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **r06** | 48 | 0.2 | 0.005 | 32 | 7 | 3 | **1.5419** | 1.4886 |
| r07 | 32 | 0.1 | 0.01 | 32 | 5 | 1 | 1.5444 | 1.5101 |
| r03 | 48 | 0.3 | 0.01 | 64 | 6 | 2 | 1.5477 | 1.4839 |
| r04 | 32 | 0.3 | 0.005 | 64 | 8 | 4 | 1.5485 | 1.5208 |
| r01 | 32 | 0.2 | 0.01 | 64 | 5 | 1 | 1.5533 | 1.4984 |
| r02 | 16 | 0.2 | 0.01 | 64 | 5 | 1 | 1.5551 | 1.5127 |
| r05 | 16 | 0.3 | 0.005 | 64 | 6 | 2 | 1.5698 | 1.5255 |
| r08 | 16 | 0.1 | 0.005 | 64 | 6 | 2 | 1.5720 | 1.5273 |

Todos los runs hicieron early stop entre epoch 5 y 8 (best epoch 1–4): el overfit de v1
(20 epochs fijas) queda confirmado en las 8 curvas — val/test MAE empeoran mientras
train_L2 sigue bajando (ver historiales en `train_config_v2.json`).

### Métricas del modelo v2 final (r06, mejor checkpoint)

| Ventana | MAE v1 | MAE v2 | RMSE v1 | RMSE v2 | bin_acc(≥1) v1 | bin_acc(≥1) v2 | F1 v1 | F1 v2 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| y3  | 0.9091 | **0.8161** | 1.1430 | **1.0114** | 0.4755 | **0.5894** | 0.4411 | **0.8121** |
| y5  | 1.3106 | **1.1479** | 1.6686 | **1.4127** | 0.5689 | **0.7520** | 0.6506 | **0.8511** |
| y10 | 2.1489 | **1.7474** | 2.7528 | **2.1511** | 0.6778 | **0.8157** | 0.7848 | **0.8935** |
| y15 | 2.8087 | **2.2430** | 3.5809 | **2.7682** | 0.7151 | **0.8395** | 0.8198 | **0.9061** |
| **prom.** | 1.7943 | **1.4886** | 2.2863 | **1.8359** | 0.6093 | **0.7492** | 0.6741 | **0.8657** |

**Gate Fase 2: CUMPLIDO** — MAE promedio v2 (1.4886) ≤ v1 (1.7943), −17.0%; y además el
criterio secundario (F1 promedio) mejora de 0.6741 a 0.8657. MAE y RMSE mejoran en las
4 ventanas.

Notas honestas para la defensa:

- **Specificity baja con pred≥0.5** (y3 0.21 / y15 0.11): v2 tiene recall altísimo
  (0.98–0.99), es decir predice "rastro" casi siempre; el F1 sube pero a costa de
  falsos positivos. La vista binaria depende mucho del umbral; con el umbral v1
  (pred≥1) el bin_acc también mejora en las 4 ventanas (0.59/0.75/0.82/0.84).
  El criterio primario del plan (MAE) no se ve afectado por esta elección de umbral.
- **Reproducibilidad:** la semilla está fija (42), pero MXNet en CPU no es 100%
  determinista entre procesos; un re-run del grid puede cambiar el ganador dentro del
  grupo cabecero (r03/r06/r07, todos con test_MAE ≈ 1.48–1.51). Los artefactos
  entregados son internamente consistentes (params + config + metrics del mismo run)
  y `--eval-only` los reproduce exactamente.

## Datos (congelados, mismos que v1)

- Train: `fantasma_train_norm.csv` (7649 filas) → sub-train 6502 + val 1147 (cola causal).
- Test: `fantasma_test_norm.csv` (2391 filas, julio) — jamás usado en entrenamiento ni selección.
- 86 features, `seq_len=5`, seed 42, L2Loss + adam (igual que v1).
