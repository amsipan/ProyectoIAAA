# Auditoría Fase 3 — métricas binarias completas v2 (test julio)

**Fecha:** 2026-07-28 (~04:15)
**Auditor:** independiente (no el worker F3)
**Objeto:** `Data/ml_out/lstm_fantasma_v2/binary_metrics_test_v2.json` + `scripts/compute_fantasma_binary_metrics_v2.py` + doc `METRICAS_BINARIAS_V2.md`, contra `docs/PLAN_REENTRENAMIENTO_MODELO_V2.md` §Fase 3.
**Método:** recomputo **independiente** del auditor (script propio, sin reutilizar código del worker) directamente desde `preds_test_v2.csv` y `preds_test.csv`; cruce contra ambos JSON, contra `metrics_test_v2.json` y contra cada tabla del doc. Sin re-entrenamiento, sin tocar `.params`.

## Veredicto

**PASS** — los 6 ítems del encargo verificados, con recomputo exacto (tolerancia solo por redondeo a 4 decimales, ≤6e-5).
**Gate Fase 4: SÍ** (Fase 4 es variante opcional según el plan; queda autorizada).

**Corrección clave de esta fase (hallazgo del worker, CONFIRMADO):** el baseline binario v1
publicado (`lstm_fantasma/binary_metrics_test.json`) se computó en realidad con **pred≥1.0**,
aunque su propio texto decía "pred>=0.5 -> pos". La comparación que circuló en la auditoría
Fase 2 ("F1 0.6741 → 0.8657, like-for-like pred≥0.5") **mezclaba umbrales**. La comparación
correcta, ambos modelos con pred≥0.5, es:

**F1 promedio: v1 0.8111 → v2 0.8657 (+0.0546)** — v2 sigue ganando en las 4 ventanas.

## Verificación por ítem

| # | Ítem | Resultado | Evidencia |
|---|---|---|---|
| 1 | `binary_metrics_test_v2.json` existe, bien formado, 4 ventanas completas + AUC | **PASS** | JSON válido; y3/y5/y10/y15 con accuracy/precision/recall/specificity/F1/TP/FP/TN/FN + `auc` + `n_pos`; `f1_avg=0.8657`; bloque Youden separado y marcado como informativo; campos explícitos `label_threshold: 1.0` y `pred_threshold: 0.5`. |
| 2 | Recomputo independiente desde `preds_test_v2.csv` | **PASS** | n=2387 filas. Las 4 confusiones **exactas** (y3 1513/668/174/32; y5 1675/563/126/23; y10 1862/427/81/17; y15 1939/380/46/22); accuracy/precision/recall/specificity/F1 y AUC (Mann-Whitney con empates, implementación propia) coinciden con el JSON a 4 decimales; `f1_avg` recomputado = 0.8657. |
| 3 | Hallazgo del umbral v1 | **CONFIRMADO** | Detalle en §"El hallazgo" abajo: el JSON v1 se reproduce con pred≥1.0 (4/4 confusiones exactas) y **no** con pred≥0.5 (0/4). |
| 4 | v1 intacto + script v1 no modificado | **PASS** | Todo `Data/ml_out/lstm_fantasma/` con mtime 7/27 23:50–23:59 (params, preds, metrics, logs, config), salvo `binary_metrics_test.json` (7/28 00:31:27, regenerado por el propio script v1 en Fase 1, **contenido idéntico verificado**: mi recomputo @1.0 desde `preds_test.csv` lo reproduce entero). Nada fue tocado después de la auditoría F2 (~03:55). Script v1 `compute_fantasma_binary_metrics.py` con mtime 7/28 **00:30:59**, anterior a la F2 y muy anterior al script v2 (04:04:29): el worker F3 no lo modificó. (Ambos scripts están untracked en git; la evidencia es mtime + reproducibilidad contenido.) |
| 5 | Doc `METRICAS_BINARIAS_V2.md` completo y coherente; plan actualizado | **PASS** | Todas las cifras del doc cruzadas contra recomputo: §2 (v2 @0.5) exacta; §3 Youden exacta (umbrales y J reproducidos: 0.7622/1.3401/2.3717/2.3082, J 0.2115–0.2638); §4a (0.6741 → 0.8657, umbrales mezclados, marcada como NO like-for-like) correcta; §4b like-for-like exacta (ver abajo); §4c trivial exacta (0.6473/0.7114/0.7872/0.8215; margen y15 = +0.010); §5 notas honestas correctas (MAE 1.4886 vs 1.7943 recomputados desde preds: −17.0%; rangos recall/specificity/desbalance correctos). Plan §Fase 3 marcado HECHA con las mismas cifras verificadas. |
| 6 | Convención única clara (label≥1, pred≥0.5) | **PASS** | Una sola regla declarada y aplicada: label `true≥1`, pred `≥0.5`. Idéntica a la prescrita por el plan Fase 3 y al bloque `binary_full` de `metrics_test_v2.json` (que el JSON v2 reproduce exactamente — verificado). El JSON v2 la hace inequívoca con campos `label_threshold`/`pred_threshold` separados. |

## El hallazgo del umbral v1 — evidencia del auditor

Tres hechos independientes, todos verificados:

1. **El script v1 lo dice en código** (`scripts/compute_fantasma_binary_metrics.py`, línea 8:
   `THRESH = 1.0`, aplicado a `true_` **y** a `pred_` en las líneas 16–17). Su cadena de salida
   `"definition": "...pred>=0.5 -> pos"` está hardcodeada (línea 28) y **contradice al código**.
   El propio JSON v1 ya contenía la pista: `"threshold": 1.0`.
2. **El recomputo lo demuestra:** desde `preds_test.csv` (v1, mtime 7/27, intacto) con pred≥1.0
   se reproducen las 4 confusiones del JSON v1 **exactamente** (p. ej. y3: TP=494, FP=201,
   TN=641, FN=1051). Con pred≥0.5 no coincide ninguna (y3 daría 1264/531/311/281).
3. **La cronología descarta fabricación:** script v1 00:30:59 y JSON v1 00:31:27 del 7/28 son
   **anteriores** a la auditoría F2 (~03:05/03:55), que ya citó estas mismas cifras
   (F1 prom 0.6741), y al trabajo F3 (script v2 04:04:29). El "hallazgo" es un hecho
   matemático sobre datos de 7/27, no una narrativa del worker F3.

**Consecuencia sobre la auditoría F2:** su §riesgo 1 asumió lo contrario a la realidad (creyó
que v1 usaba pred≥0.5 "según su propia definición" y que el bloque raro era el `binary_accuracy`
de v2 con pred≥1.0). Su comparación "like-for-like" (F1 0.6741 → 0.8657) era en verdad
v1@1.0 vs v2@0.5: **umbrales mezclados que sobreestimaban la mejora**. El F2 había detectado
el olor (riesgo 1) pero asignó al revés qué lado estaba mal etiquetado. No invalida el gate F2:
el criterio primario era MAE (1.7943 → 1.4886, recomputado aquí de nuevo: exacto).

## Comparación corregida v2 vs v1 (like-for-like, ambos pred≥0.5)

Recomputada por el auditor; coincide con §4b del doc en las 12 celdas:

| Ventana | F1 v1@0.5 | F1 v2@0.5 | Acc v1@0.5 | Acc v2@0.5 | AUC v1 | AUC v2 |
|---|---|---|---|---|---|---|
| y3  | 0.7569 | **0.8121** | 0.6598 | **0.7067** | 0.6111 | **0.6345** |
| y5  | 0.8010 | **0.8511** | 0.6988 | **0.7545** | 0.6073 | **0.6469** |
| y10 | 0.8342 | **0.8935** | 0.7336 | **0.8140** | 0.5959 | **0.6505** |
| y15 | 0.8524 | **0.9061** | 0.7553 | **0.8316** | 0.5924 | **0.6484** |
| **prom** | **0.8111** | **0.8657** | **0.7119** | **0.7767** | **0.6017** | **0.6451** |

v2 gana en las 4 ventanas en F1, accuracy, recall y AUC (recall v1@0.5: 0.818/0.852/0.852/0.860
vs v2 0.979/0.986/0.991/0.989). A cambio, specificity v2 es menor (0.11–0.21 vs 0.27–0.37 de
v1@0.5): divulgado en el doc. Mejora real pero **más modesta** de lo que la comparación con
umbral mezclado sugería (ΔF1 +0.0546, no +0.19).

Cross-checks adicionales del auditor (todos exactos): `baseline_v1_binary_metrics.json` ≡ JSON
v1; JSON v2 ≡ bloque `binary_full` de `metrics_test_v2.json`; MAE prom desde preds (v2 1.4886,
v1 1.7943); clasificador trivial superado por v2 en las 4 ventanas (y15 por +0.010).

## Observaciones (no bloquean)

1. **Specificity baja con pred≥0.5** (0.11–0.21; recall 0.98–0.99) y AUC modesto (0.63–0.65):
   propiedad del modelo ya aceptada en el gate F2; el doc la divulga con honestidad y la métrica
   primaria sigue siendo MAE. Para la defensa: binario = complemento sensible al umbral.
2. **Youden solo informativo:** el barrido es in-sample sobre el propio test (no existen preds
   de validación y no se re-entrenó). Correctamente segregado en bloque aparte, no usado en las
   métricas reportadas, y J máximo bajo (≤0.27) sin mejora de accuracy: se mantiene 0.5 fijo.
   Recomendado para Fase 4/5: si se entrena la variante, guardar preds de **val** para elegir
   umbral fuera de test.
3. **Etiqueta falsa persiste en el script v1** (su `definition` impresa dice "pred>=0.5" pero
   aplica 1.0). Correcto **no** tocarlo (v1 congelado); la corrección quedó documentada aquí y
   en `METRICAS_BINARIAS_V2.md` §1. Si en Fase 6/7 se limpia, hacerlo con nota explícita.
4. Detalle menor del doc: §2 dice "AUC 0.59–0.65" para v2 cuando el rango v2 es 0.63–0.65
   (0.59 corresponde al rango de v1). Cota exterior válida; precisión mejorable en slides.

## Qué NO se hizo

Sin commits, sin re-entrenar, sin tocar `.params` ni nada bajo `Data/ml_out/lstm_fantasma/`.
El recomputo del auditor solo lee CSV/JSON (script propio de un solo uso, fuera del árbol de
artefactos, eliminado tras la pasada).
