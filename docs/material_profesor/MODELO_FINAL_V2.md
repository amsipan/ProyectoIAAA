# Modelo final — selección Fase 5 (fantasmita LSTM)

**Fecha:** 2026-07-28
**Base:** `docs/PLAN_REENTRENAMIENTO_MODELO_V2.md` §Fase 5 (criterio fijo definido antes de mirar
números), auditorías Fase 2/3/4 (`AUDIT_FASE2_V2.md`, `AUDIT_FASE3_V2.md`, `AUDIT_FASE4_V2.md`).
**Test:** julio 2026, n=2387 secuencias (seq_len=5), contrato de labels **A** (y3/y5/y10/y15).

## Criterio de selección (fijo)

1. **Primario:** menor **MAE promedio** en las 4 ventanas (test julio).
2. **Secundario:** mayor **F1 promedio** en y3–y15 (binaria: pos = ≥1 rastro en la ventana,
   pred ≥ 0.5, convención única de Fase 3).

## Tabla comparativa (promedios, test julio)

| Candidato | MAE prom ↓ | RMSE prom | F1 prom ↑ | Notas |
|---|---:|---:|---:|---|
| v1 (`lstm_fantasma/`) | 1.7943 | 2.2864 | 0.8111 | F1 recomputado @0.5 like-for-like (Fase 3); el v1 publicado usaba pred≥1.0 (F1 0.6741, no comparable) |
| **v2 simple r06 (`lstm_fantasma_v2/`)** | **1.4886** | **1.8359** | 0.8657 | h=48, dropout=0.2, lr=0.005, batch=32, best epoch 3 (val causal) |
| v2b LSTM+Dense (`lstm_fantasma_v2b/`) | 1.4975 | 1.8721 | 0.8664 | Variante arquitectónica 4a; DESCARTADA en Fase 4 |

Detalle por ventana:

| Ventana | MAE v1 | MAE v2 | MAE v2b | F1 v1@0.5 | F1 v2 | F1 v2b |
|---|---:|---:|---:|---:|---:|---:|
| y3  | 0.9091 | **0.8161** | 0.8316 | 0.7569 | **0.8121** | 0.8111 |
| y5  | 1.3106 | **1.1479** | 1.1678 | 0.8010 | 0.8511 | **0.8517** |
| y10 | 2.1489 | **1.7474** | 1.7577 | 0.8342 | **0.8935** | 0.8920 |
| y15 | 2.8087 | 2.2430 | **2.2328** | 0.8524 | 0.9061 | **0.9109** |
| **prom.** | 1.7943 | **1.4886** | 1.4975 | 0.8111 | 0.8657 | **0.8664** |

## Ganador: v2 simple (r06)

- **Criterio primario (MAE prom):** v2 = **1.4886**, mejor que v2b (1.4975, +0.0089 peor) y que
  v1 (1.7943, **−17.0%**). Mejora en las 4 ventanas contra v1 y en 3 de 4 contra v2b.
- **Criterio secundario (F1 prom):** v2 = **0.8657**, mejor que v1 (0.8111, +0.0546 like-for-like);
  contra v2b (0.8664) es empate práctico (+0.0007), que no compensa perder el criterio primario.
- **Robustez:** v2 gana también en **validación** (r06 val_MAE=1.5419 vs d32 1.5467), así que la
  decisión no depende de ruido de test (audit F4). Selección de run hecha por MAE de val causal,
  sin fuga de test.
- **Simplicidad:** la Dense intermedia de v2b no aporta mejora fuera de muestra; se mantiene la
  arquitectura más simple (LSTM → Dropout → Dense).

## Ruta final y entregables

`Data/ml_out/lstm_fantasma_final/` (nombres finales sin sufijo `_v2`, según plan §Entregables):

| Archivo | Contenido |
|---|---|
| `fantasma_lstm.params` | Pesos del modelo final (copia de `fantasma_lstm_v2.params`, run r06) |
| `metrics_test.json` | MAE/RMSE por ventana + binaria completa (confusión, F1) |
| `binary_metrics_test.json` | Métricas binarias + AUC, convención única (label ≥1, pred ≥0.5) |
| `preds_test.csv` | Predicciones test julio (n=2387) |
| `train_config.json` | Config elegida + historial de los 8 runs del grid |

## Verificación de la copia (2026-07-28)

1. **Hashes SHA256:** los 5 archivos de `lstm_fantasma_final/` son **byte-idénticos** a sus
   originales en `lstm_fantasma_v2/` (params, metrics, binary metrics, preds, config).
2. **`--eval-only` reproduce métricas:** `scripts/train_fantasma_lstm_v2.pl --eval-only`
   `--model Data/ml_out/lstm_fantasma_final/fantasma_lstm.params` (hiperparámetros r06 explícitos:
   hidden=48, dropout=0.2, batch=32, seq_len=5; salida dirigida a `/tmp` para no tocar el directorio
   final) → **PROMEDIO MAE=1.4886, RMSE=1.8359, F1=0.8657**, idéntico a las cifras de v2, con las
   mismas 4 matrices de confusión. Las preds regeneradas son **byte-idénticas** a
   `lstm_fantasma_final/preds_test.csv`.
3. **Historial intacto:** v1 (`lstm_fantasma/`), v2 (`lstm_fantasma_v2/`) y v2b
   (`lstm_fantasma_v2b/`) no fueron modificados ni borrados; solo se copió hacia
   `lstm_fantasma_final/`. Sin re-entrenamiento.

**Decisión Fase 5: modelo final = v2 simple (r06), materializado en
`Data/ml_out/lstm_fantasma_final/`.** Siguiente paso: Fase 6 (regenerar slides y guion con estas
cifras).
