# LSTM Fantasma v2b — variante arquitectónica (Fase 4, Opción 4a)

**Fecha:** 2026-07-28
**Plan maestro:** `docs/PLAN_REENTRENAMIENTO_MODELO_V2.md` (Fase 4)
**Script nuevo:** `scripts/train_fantasma_lstm_v2b.pl` (v1 y v2 intactos)
**Artefactos:** `Data/ml_out/lstm_fantasma_v2b/`
**Veredicto:** **DESCARTADA** — no supera a v2 simple en el criterio primario (MAE); se mantiene v2.

## Arquitectura (única diferencia vs v2)

| | v2 simple (r06) | v2b (Opción 4a) |
|---|---|---|
| Bloques | LSTM(48) → Dropout(0.2) → Dense(4) | LSTM(48) → Dropout(0.2) → **Dense(N, relu)** → Dense(4) |

Todo lo demás idéntico a v2: misma data normalizada, `seq_len=5`, seed 42, L2Loss + adam,
validación en cola causal del train (15% = 1147 filas, nunca se entrena con ella), early stop
(paciencia 4, min_delta 0.0005) por **MAE promedio de validación**, y test julio solo se reporta
(sin fuga de test en la selección).

## Runs (grid de 2, hiperparámetros del ganador v2: h=48, d=0.2, lr=0.005, b=32)

| Run | Dense intermedia | epochs | best_ep | val_MAE | test_MAE\@best |
|---|---:|---:|---:|---:|---:|
| **d32** | 32 | 8 | 4 | **1.5467** | 1.4975 |
| d24 | 24 | 9 | 5 | 1.5488 | 1.5091 |

Ganador **d32** por menor MAE de validación (mismo criterio que v2). Selección por validación,
no por test. Tiempo total del grid: ~3 min en Fedora35.

## Resultados test julio (n=2387) — v2b (d32) vs v2 simple (r06)

| Ventana | MAE v2 | MAE v2b | F1 v2 | F1 v2b |
|---|---:|---:|---:|---:|
| y3  | **0.8161** | 0.8316 | **0.8121** | 0.8111 |
| y5  | **1.1479** | 1.1678 | 0.8511 | **0.8517** |
| y10 | **1.7474** | 1.7577 | **0.8935** | 0.8920 |
| y15 | 2.2430 | **2.2328** | 0.9061 | **0.9109** |
| **prom.** | **1.4886** | 1.4975 | 0.8657 | **0.8664** |

- **Criterio primario (MAE prom):** v2b 1.4975 vs v2 1.4886 → **+0.0089 peor** (+0.6%).
  Solo y15 mejora (−0.010); y3/y5/y10 empeoran.
- **Criterio secundario (F1 prom):** 0.8664 vs 0.8657 → empate práctico (+0.0007).

## Veredicto

**Variante DESCARTADA.** El gate de Fase 4 exige que la variante supere a v2 simple en la métrica
elegida (MAE promedio): no lo hace. La capa Dense intermedia añade capacidad que no se traduce en
mejor generalización fuera de muestra; con el overfit ya controlado por early stop, el cuello de
botella no es la profundidad fully-connected. **Recomendación para Fase 5: adoptar v2 simple (r06)
como `lstm_fantasma_final`.**

Opción 4b (CNN1D+LSTM) **omitida**: no trivial y 4a ya respondió la pregunta arquitectónica (más
capacidad ≠ mejor MAE aquí).

## Notas

- `--eval-only` reproduce las métricas exactas (MAE 1.4975, F1 0.8664, mismas confusiones) y
  conserva `train_config_v2b.json` (procedencia del grid).
- MXNet en CPU no es 100% determinista entre procesos (igual que en v2): un re-run puede mover
  el resultado dentro de ±0.01 MAE, pero el margen no cambia el veredicto (v2 gana por val y test).
- v1 (`lstm_fantasma/`) y v2 (`lstm_fantasma_v2/`) intactos; la comparación del log solo lee
  `metrics_test_v2.json`.

## Cómo correr (WSL Fedora35)

```bash
wsl -d Fedora35 -- bash -lc "cd /mnt/c/Users/bryan/ia/proyecto_iaaa/Proyecto/ProyectoIAAA && \
  perl scripts/train_fantasma_lstm_v2b.pl \
    --grid 'd24:48:24:0.2:0.005:32,d32:48:32:0.2:0.005:32' \
    --epochs 25 --patience 4 --min-delta 0.0005 --val-frac 0.15 --seed 42 \
    2>&1 | tee Data/ml_out/lstm_fantasma_v2b/train_v2b.log"
```

Formato del grid v2b: `nombre:hidden:dense:dropout:lr:batch`. Re-evaluar sin reentrenar:
`perl scripts/train_fantasma_lstm_v2b.pl --eval-only`.

## Artefactos producidos

| Archivo | Contenido |
|---|---|
| `fantasma_lstm_v2b.params` | Mejor checkpoint del run ganador (d32, epoch 4) |
| `train_config_v2b.json` | Config elegida + 2 runs con historial por epoch |
| `metrics_test_v2b.json` | MAE/RMSE por y3–y15 + bin_acc (≥1) + confusión completa (pred≥0.5) |
| `preds_test_v2b.csv` | Predicciones vs reales en test julio (n=2387) |
| `train_v2b.log` | Log completo del grid + comparación vs v2 |
