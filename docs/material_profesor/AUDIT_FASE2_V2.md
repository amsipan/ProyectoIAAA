# Auditoría Fase 2 — Entrenamiento modelo v2

**Re-auditoría:** 2026-07-28 (~03:55 UTC-5), tras entrega del worker (artefactos 03:26–03:37).
**Primera pasada:** mismo día ~03:05 → FAIL. **Nota:** aquella pasada fue **prematura** — se
ejecutó ~20 min antes de que el worker terminara el grid y copiara los artefactos; el FAIL
era correcto para el estado del repo en ese instante, pero queda **superado** por esta
re-auditoría.
**Rol:** Auditor independiente (no entrena; solo verificó, incluido un `--eval-only` de
inferencia determinista que no altera el modelo).
**Base:** `docs/PLAN_REENTRENAMIENTO_MODELO_V2.md` §Fase 2 (acciones 1–3, salida y gate).

## Resumen ejecutivo

|| Veredicto |
|---|---|
| **Fase 2** — Entrenamiento v2 (combate al overfit) | **PASS_CON_RIESGOS** (7/7 criterios verificados; 3 riesgos no bloqueantes) |
| **Gate Fase 3** (métricas completas de exposición) | **SÍ** |

Gate del plan **cumplido por criterio primario**: MAE promedio v2 **1.4886** ≤ v1 **1.7943**
(−17.0%, mejora en las 4 ventanas); el secundario también mejora (F1 prom 0.6741 → 0.8657,
umbral comparable pred≥0.5). Verificación independiente: recomputo desde `preds_test_v2.csv`
reproduce las métricas entregadas a 6 decimales, y `--eval-only` en Fedora35 regenera
artefactos **byte-idénticos**.

---

## Detalle por criterio del checklist

| # | Criterio | Estado | Evidencia |
|---|---|---|---|
| 2.1 | Artefactos en `Data/ml_out/lstm_fantasma_v2/` (params, config, metrics, preds, log) | **PASS** | Los 5 presentes (03:34–03:37): `fantasma_lstm_v2.params` (105.626 B), `train_config_v2.json`, `metrics_test_v2.json`, `preds_test_v2.csv` (n=2387), `train_v2.log`. + `baseline_v1_binary_metrics.json` de Fase 1 conservado. |
| 2.2 | `scripts/train_fantasma_lstm_v2.pl` (sintaxis OK) | **PASS** | Existe (27.442 B, 03:26). `perl -I. -c` en Fedora35 → **syntax OK**. Script v1 intacto (sin cambios en git). |
| 2.3 | v1 intacto (`Data/ml_out/lstm_fantasma/`) | **PASS** | SHA256 de params/metrics/preds/config **idénticos** al snapshot de la pasada 1; timestamps sin cambios. |
| 2.4 | Comparación v2 vs v1 (MAE prom; F1 secundario) | **PASS** | MAE prom: 1.7943 → **1.4886** (−0.3057); mejora en y3/y5/y10/y15 (0.909→0.816 / 1.311→1.148 / 2.149→1.747 / 2.809→2.243). RMSE prom 2.286→1.836. F1 prom (pred≥0.5 en ambos): 0.6741 → **0.8657**. Recomputo independiente del auditor desde preds confirma cada cifra a 6 decimales. |
| 2.5 | Early stopping / grid / best checkpoint documentados | **PASS** | Grid de 8 runs (hidden/dropout/lr/batch, seed 42 fija) con early stop (paciencia 4, min_delta 0.0005, tope 25 epochs) y val causal 15% del tail de train; selección por **menor MAE de val** → r06 (h=48, d=0.2, lr=0.005, b=32, best epoch 3). Sin fuga de test: r06 elegido pese a que r03 tuvo test_MAE marginalmente menor (1.4839 vs 1.4886) — se seleccionó por val, no por test. Documentado en `train_v2.log`, `selection` de metrics/config y `LSTM_FANTASMA_V2.md`. |
| 2.6 | Doc `LSTM_FANTASMA_V2.md` | **PASS** | Existe y es completo: tabla v1↔v2 de cambios (dropout real, val causal, early stop), grid justificado, resultados, gate y "notas honestas" (specificity baja, determinismo MXNet). |
| 2.7 | (Opcional) `--eval-only` reproduce métricas | **PASS** | Ejecutado por el auditor en Fedora35: hereda config r06, carga params y reproduce exactamente MAE 1.4886 / RMSE 1.8359 / F1 0.8657 y confusiones. Hashes SHA256 de `metrics_test_v2.json` y `preds_test_v2.csv` **byte-idénticos** antes/después → inferencia determinista, entrega internamente consistente (`eval_only_recheck: true`). |

## Verificaciones independientes del auditor

1. **Recomputo desde `preds_test_v2.csv`** (n=2387): MAE/RMSE por ventana, accuracy,
   precision, recall, specificity, F1 y confusiones con pred≥0.5, y accuracy con pred≥1.0 —
   todo coincide con `metrics_test_v2.json` a 6 decimales. Confirmado además que el bloque
   `binary_accuracy` de v2 usa la regla **pred≥1.0** y `binary_full` la regla **pred≥0.5**.
2. **Integridad v1:** hashes SHA256 de los 4 artefactos clave idénticos a la pasada 1.
3. **Eval-only reproducible:** regenera artefactos byte-idénticos (hashes antes/después).
4. **Sin fuga de test en selección:** el ganador se eligió por MAE de val causal (ver 2.5).

## Riesgos (no bloquean el gate Fase 3)

1. **Presentación binaria con umbrales mezclados.** El bloque `binary_accuracy` v2 usa
   pred≥1.0, pero el `binary_accuracy` de v1 (según su propia definición "pred>=0.5 -> pos")
   usaba pred≥0.5: la tabla del doc "bin_acc(≥1) v1 | v2" yuxtapone reglas distintas y el
   `train_v2.log` imprime en la misma línea el acc(pred≥1) junto a la confusión(pred≥0.5).
   **A favor del worker:** like-for-like v2 gana igualmente — con pred≥0.5 en ambos, acc
   0.707/0.755/0.814/0.832 vs v1 0.476/0.569/0.678/0.715 y F1 0.866 vs 0.674. Corrección
   barata en Fase 3: generar `binary_metrics_test_v2.json` con la **misma** regla del
   baseline v1 (pred≥0.5) y ajustar etiquetas del doc/slides.
2. **Specificity baja con pred≥0.5** (0.11–0.21; recall 0.98–0.99): la vista binaria de v2
   predice positivo casi siempre; en y15 el acc (0.832) apenas supera al trivial
   "siempre ≥1" (0.8215). Riesgo ya señalado en la auditoría Fase 0/1 y divulgado con
   honestidad por el worker. El criterio primario (MAE) no se ve afectado; para la defensa,
   presentar MAE como principal y binario como complemento sensible al umbral.
3. **Determinismo de entrenamiento MXNet (CPU)** divulgado por el worker: un re-run del
   grid podría elegir r03/r07 (todos test_MAE ≈ 1.48–1.51). Los artefactos entregados son
   internamente consistentes y la inferencia es determinista (verificado); solo aplica si
   alguien re-entrena.
4. **Cosmético:** el doc dice "val 1147 filas / sub-train 6502" y el log "val=1143 /
   subtrain=6498 secuencias" — filas vs secuencias (seq_len−1 = 4) + purga causal de
   frontera; sin impacto material, aclarar en Fase 6 si se citan cifras.

## Gate Fase 3 (métricas completas): **SÍ**

Insumos verificados: `preds_test_v2.csv` (n=2387), métricas binarias completas ya dentro de
`metrics_test_v2.json` (`binary_full`: accuracy/precision/recall/specificity/F1/confusión
por ventana) y el script `compute_fantasma_binary_metrics.py` parametrizado en Fase 1.
Fase 3 = materializar `binary_metrics_test_v2.json` (regla pred≥0.5, comparable al baseline
v1) — sin re-entrenamiento. Aprovechar para corregir el riesgo 1 (etiquetado de umbrales).

## Historial de esta auditoría

- **Pasada 1 (~03:05):** FAIL — prematura: el worker aún no copiaba los artefactos
  (llegaron 03:26–03:37). Correcta para el repo de ese instante; **superada** por la
  pasada 2.
- **Pasada 2 (~03:55):** 7/7 criterios verificados con recomputo independiente →
  **PASS_CON_RIESGOS**; **gate F3 = SÍ**.
