# Módulo predictivo — Fantasma / LSTM

---

## 1. Objetivo

Predecir, tras cada aparición o reubicación del fantasma, el número de rastros en ventanas de **3, 5, 10 y 15 minutos** (`y3`, `y5`, `y10`, `y15`).

Modelo: **LSTM** de regresión, 1 capa, 48 unidades, sin CNN. 
Muestreo por evento del fantasma (no una observación por minuto).

---



## 2. Pipeline

```text
CSV OHLCV → extract → normalize (86 features, z-score train-only)
 → LSTM (seq_len=5) → evaluación / demo
```


| Split | Fuente | Filas → secuencias |
| ----- | ---------- | ------------------ |
| Train | abr–jun | 7649 → 7645 |
| Test | julio 1–24 | 2391 → 2387 |


---



## 3. Features (86)

Lista completa: `features_86.txt` (igual que en el DOCX).

Familias: ATR/volumen; distancias en PIPs a AVWAP, BOS/CHoCH, EQH/EQL, canal, DIY, Fib, FVG, HLD, OB, POC/VAH/VAL, S/G/R; timeframes **1m, 10m, 1h** (HLD 4h/D donde aplica).

---



## 4. Comandos

```bash
# Demo (carga pesos y muestra TRUE vs PRED; --n = número de muestras)
perl -I. scripts/demo_fantasma_predict.pl --n 8

# Evaluación del modelo guardado
perl -I. scripts/train_fantasma_lstm.pl --eval-only \
 --model Data/ml_out/lstm_fantasma/fantasma_lstm.params \
 --out-dir /tmp/fantasma_eval \
 --hidden 48 --dropout 0.2 --batch-size 32 --seq-len 5
```

Scripts de pipeline: `extract_fantasma_dataset.pl`, `normalize_fantasma_dataset.pl`,
`train_fantasma_lstm.pl`, `demo_fantasma_predict.pl`.

---



## 5. Modelo y resultados (test julio)

**Artefactos:** `Data/ml_out/lstm_fantasma/`


| Archivo | Contenido |
| -------------------------- | ------------------------------------------ |
| `fantasma_lstm.params` | Pesos |
| `metrics_test.json` | MAE / RMSE |
| `binary_metrics_test.json` | Accuracy, F1, matriz de confusión, AUC |
| `preds_test.csv` | Predicciones (`meta_time`, true_*, pred_*) |
| `train_config.json` | Hiperparámetros |


**Configuración:** hidden 48, dropout 0.2, lr 0.005, batch 32, seq_len 5, early stopping.


| Ventana | MAE | RMSE | Acc (≥1 rastro) | F1 |
| --------- | -------- | -------- | --------------- | -------- |
| y3 | 0.82 | 1.01 | 0.71 | 0.81 |
| y5 | 1.15 | 1.41 | 0.75 | 0.85 |
| y10 | 1.75 | 2.15 | 0.81 | 0.89 |
| y15 | 2.24 | 2.77 | 0.83 | 0.91 |
| **prom.** | **1.49** | **1.84** | **0.78** | **0.87** |


Binario: positivo si hay ≥1 rastro; umbral de predicción 0.5.

---



