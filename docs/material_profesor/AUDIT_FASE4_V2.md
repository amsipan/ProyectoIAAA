# Auditoría Fase 4 — variante arquitectónica v2b (LSTM + Dense intermedia)

**Fecha:** 2026-07-28 (~04:45)
**Auditor:** independiente (no el worker F4)
**Objeto:** `Data/ml_out/lstm_fantasma_v2b/` + `scripts/train_fantasma_lstm_v2b.pl` + doc `LSTM_FANTASMA_V2B.md`, contra `docs/PLAN_REENTRENAMIENTO_MODELO_V2.md` §Fase 4.
**Método:** recomputo **independiente** del auditor (script propio, sin reutilizar código del worker) directamente desde `preds_test_v2b.csv`, `preds_test_v2.csv` y `preds_test.csv`; `perl -I. -c` en Fedora35; `--eval-only` con hashes SHA256 antes/después; cruce contra log/config/metrics y contra cada tabla del doc. Sin re-entrenamiento, sin tocar `.params`.

## Veredicto

**PASS** — los 6 ítems del encargo verificados, con recomputo exacto (coincidencia a 6 decimales).
**Gate Fase 5: SÍ** (selección del modelo final autorizada).

**Confirmación clave:** la variante v2b **no supera** a v2 simple en el criterio primario:
MAE prom v2b **1.4975** vs v2 **1.4886** (+0.0089 peor, +0.6%); F1 prom 0.8664 vs 0.8657
(empate práctico). v2 gana además en **validación** (r06 val_MAE=1.5419 vs d32 1.5467), así que
el veredicto no depende de ruido de test. **v2 simple (r06) queda confirmado como candidato a
`lstm_fantasma_final` para Fase 5**; la pregunta arquitectónica ("¿más capacidad fully-connected
ayuda?") queda respondida: no aquí. Opción 4b (CNN1D+LSTM) correctamente omitida.

## Verificación por ítem

| # | Ítem | Resultado | Evidencia |
|---|---|---|---|
| 1 | Artefactos en `Data/ml_out/lstm_fantasma_v2b/` (params, config, metrics, preds, log) | **PASS** | Los 5 presentes (7/28 04:34–04:35): `fantasma_lstm_v2b.params` (111.744 B), `train_config_v2b.json` (chosen=d32 + 2 runs con historial por epoch), `metrics_test_v2b.json`, `preds_test_v2b.csv` (n=2387 + header), `train_v2b.log` (grid completo + comparación vs v2). |
| 2 | Script v2b compila y no rompe el v2 | **PASS** | `perl -I. -c scripts/train_fantasma_lstm_v2b.pl` → **syntax OK** en Fedora35; `scripts/train_fantasma_lstm_v2.pl` también **syntax OK**. El script v2b escribe solo en su `out_dir` (metrics/preds/config con sufijo `_v2b`, checkpoints temporales `.ckpt_*.params` en el mismo dir, borrados al final) y **solo lee** `metrics_test_v2.json` de v2 para la comparación. |
| 3 | Recomputo MAE prom test v2b desde `preds_test_v2b.csv` = 1.4975 (peor que v2) | **PASS** | Recomputo propio: MAE y3=0.831602, y5=1.167846, y10=1.757708, y15=2.232837, **AVG=1.497499** (JSON: 1.49749850171724 — exacto). RMSE AVG=1.872104 (JSON: 1.87210439560411). F1 por ventana 0.811126/0.851730/0.891976/0.910919, **AVG=0.866438** (JSON: 0.866437744748061); las 4 confusiones **exactas** (1531/699/143/14; 1686/575/114/12; 1862/434/74/17; 1948/368/58/13). Confirma: **1.4975 > 1.4886 v2 → v2b peor**. |
| 4 | v1 (`lstm_fantasma/`) y v2 (`lstm_fantasma_v2/`) intactos | **PASS** | mtimes: v1 todo 7/27 23:50–7/28 00:31; v2 todo 7/28 02:50–04:04 — ambos **anteriores** al trabajo F4 (04:34). Integridad por contenido: recomputo propio desde preds reproduce las cifras publicadas de cada uno (v1: MAE AVG=1.794318, F1 AVG=0.811115 @pred≥0.5; v2: MAE AVG=1.488620, F1 AVG=0.865699, confusiones iguales a las verificadas en audit F3). El único acceso del script v2b a v2 es lectura de `metrics_test_v2.json`. |
| 5 | Doc `LSTM_FANTASMA_V2B.md` coherente + plan actualizado con recomendación | **PASS** | Todas las cifras del doc cruzadas contra log/config/metrics y mi recomputo: tabla de runs (d32 val 1.5467 / d24 val 1.5488, best_ep 4/5), tabla v2↔v2b por ventana (12 celdas exactas), deltas (+0.0089 MAE, +0.0007 F1), conteos val (1147 filas / 1143 seq) y subtrain (6502 / 6498) consistentes con train_rows=7649 y seq_len=5. Veredicto del doc = DESCARTADA + recomendación explícita "adoptar v2 simple (r06) como `lstm_fantasma_final`" — coincide con el gate del plan. Plan §Fase 4 marcado HECHA con las mismas cifras verificadas. |
| 6 | `--eval-only` del v2b reproduce métricas | **PASS** | Ejecutado por el auditor en Fedora35: hereda config elegida (d32: hidden=48 dense=32 dropout=0.2 seq_len=5), carga params y reproduce **exactamente** MAE 1.4975 / RMSE 1.8721 / F1 0.8664 y las 4 confusiones. Hashes SHA256 de `metrics_test_v2b.json`, `preds_test_v2b.csv`, `train_config_v2b.json` y `fantasma_lstm_v2b.params` **byte-idénticos** antes/después (config conservada con `eval_only_recheck: true`; params sin tocar). |

## Comparación verificada v2 vs v2b (test julio, n=2387)

Recomputada por el auditor desde ambos preds CSV; coincide con el doc y el log en las 12 celdas:

| Ventana | MAE v2 | MAE v2b | F1 v2 | F1 v2b |
|---|---:|---:|---:|---:|
| y3  | **0.8161** | 0.8316 | **0.8121** | 0.8111 |
| y5  | **1.1479** | 1.1678 | 0.8511 | **0.8517** |
| y10 | **1.7474** | 1.7577 | **0.8935** | 0.8920 |
| y15 | 2.2430 | **2.2328** | 0.9061 | **0.9109** |
| **prom.** | **1.4886** | 1.4975 | 0.8657 | **0.8664** |

- **Criterio primario (MAE prom):** v2b +0.0089 peor; solo y15 mejora (−0.010), y3/y5/y10 empeoran.
- **Criterio secundario (F1 prom):** empate práctico (+0.0007).
- **Validación (selección):** d32 val_MAE=1.5467 > r06 val_MAE=1.5419 → v2 gana también in-sample
  fuera del train; la brecha no es un artefacto del test.
- **Sin fuga de test:** d32 elegido por menor MAE de **val** (1.5467 < 1.5488 de d24), mismo
  criterio declarado que en v2; el test julio solo se reporta (history completa en config, donde
  consta que la selección usa `best_val_mae_avg`).

## Observaciones (no bloquean)

1. **Margen dentro de la variabilidad de re-entrenamiento, pero veredicto robusto:** el propio doc
   divulga que MXNet CPU puede mover ±0.01 MAE entre re-runs, y el delta es +0.0089. No cambia el
   gate: (a) la comparación se hace sobre los artefactos entregados con seed 42 fija, receta
   idéntica y misma data; (b) v2b también pierde en validación (1.5467 vs 1.5419), así que la
   conclusión no cuelga solo del test.
2. **Specificity baja se mantiene en v2b** (0.136–0.170 con pred≥0.5; recall ~0.99): propiedad ya
   aceptada en gates F2/F3 y divulgada; el binario sigue siendo complemento, MAE el primario.
3. **Opción 4b omitida, aceptable:** 4a ya respondió la pregunta arquitectónica (más capacidad FC
   ≠ mejor MAE con overfit ya controlado por early stop); el plan la marcaba como opcional.
4. Menor: el `train_config_v2b.json` deja `dense_hidden: 24` de nivel raíz (default del CLI) junto
   al `chosen.dense_hidden: 32` que manda; el `--eval-only` hereda correctamente del `chosen`
   (verificado), así que es solo ruido cosmético de procedencia.

## Qué NO se hizo

Sin commits, sin re-entrenar, sin tocar `.params` ni nada bajo `Data/ml_out/lstm_fantasma/` o
`Data/ml_out/lstm_fantasma_v2/`. El recomputo del auditor solo lee CSV/JSON (script propio de un
solo uso, fuera del árbol de artefactos). `--eval-only` regeneró metrics/preds v2b byte-idénticos
(verificado por SHA256) y conservó la config.
