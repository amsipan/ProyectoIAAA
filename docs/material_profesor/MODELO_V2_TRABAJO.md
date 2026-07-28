# Modelo v2 - nota de trabajo (fases 0-1)

**Fecha inicio:** 2026-07-28
**Plan maestro:** `docs/PLAN_REENTRENAMIENTO_MODELO_V2.md`
**Contrato de labels:** Opcion A (sin cambios; no se re-extrae el dataset).

## Que se esta haciendo

Reentrenar el LSTM del fantasmita como **v2** con foco en:

- Combatir el overfit de v1 (early stopping / grid pequeno de hiperparametros).
- Metricas completas de exposicion: regresion (MAE/RMSE) + vista binaria
  (accuracy, precision, recall, specificity, F1, matriz de confusion) por y3/y5/y10/y15.
- Slides y guion regenerados al final con las cifras del modelo elegido.

v1 queda **congelado como baseline**: no se modifica ni se reentrena.

## Criterio de seleccion (congelado, copiado del plan maestro)

- **Primario:** menor MAE promedio de las 4 ventanas (y3/y5/y10/y15).
- **Secundario (desempate / prioridad si se insiste en binario):** mayor F1 promedio.
- **Gate Fase 2:** v2 con MAE total <= v1 o, si sube, F1/bin_acc claramente mejor.

## Rutas

| Que | Ruta |
|---|---|
| Baseline v1 (NO tocar) | `Data/ml_out/lstm_fantasma/` |
| Workspace v2 (artefactos nuevos) | `Data/ml_out/lstm_fantasma_v2/` |
| Baseline binario v1 regenerado | `Data/ml_out/lstm_fantasma_v2/baseline_v1_binary_metrics.json` |
| Datos normalizados (compartidos) | `Data/ml_out/fantasma_train_norm.csv`, `Data/ml_out/fantasma_test_norm.csv` |
| Stats de normalizacion | `Data/ml_out/fantasma_norm_stats.json` (86 features, zscore fit train) |
| Check fases 0-1 | `docs/material_profesor/CHECK_FASE0_FASE1_V2.md` |

## Estado

- **Fase 0 (congelar baseline + workspace): HECHA** (2026-07-28).
- **Fase 1 (higiene de datos + reproducibilidad): HECHA** (2026-07-28).
- **Fase 2 (entrenamiento v2): HECHA** (2026-07-28, Fedora35/MXNet) - pendiente de re-auditoria
  (el audit FAIL de ~03:05 fue previo a la entrega de ~03:35).
  Script nuevo `scripts/train_fantasma_lstm_v2.pl` (early stop + val causal + grid 8 runs);
  ganador r06 (h=48, d=0.2, lr=0.005, b=32); MAE prom test 1.4886 vs 1.7943 v1; F1 prom
  0.8657 vs 0.6741. Detalle en `docs/material_profesor/LSTM_FANTASMA_V2.md`.
- Fase 3 (metricas binarias completas): pendiente - insumo listo: `preds_test_v2.csv`
  (n=2387) ya generado; `metrics_test_v2.json` ya incluye confusion completa por ventana
  (convencion baseline: pos = >=1 rastro, pred>=0.5), reutilizable o regenerable con
  `scripts/compute_fantasma_binary_metrics.py`.