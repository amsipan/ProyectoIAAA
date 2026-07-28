# Métricas binarias completas — modelo LSTM v2 (test julio)

**Fecha:** 2026-07-28
**Fase:** 3 del `PLAN_REENTRENAMIENTO_MODELO_V2.md` (solo materialización de métricas; **sin re-entrenamiento**).
**Insumos:** `Data/ml_out/lstm_fantasma_v2/preds_test_v2.csv` (n=2387 secuencias, split `test_julio`).
**Salida:** `Data/ml_out/lstm_fantasma_v2/binary_metrics_test_v2.json`.
**Reproducir:**

```powershell
python scripts/compute_fantasma_binary_metrics_v2.py
```

## 1. Convención única de umbral (resuelve el riesgo 1 de la auditoría F2)

| Elemento | Regla |
|---|---|
| Label binario | **positivo = `true >= 1`** (≥1 rastro/fantasma en la ventana) |
| Predicción binaria | **positivo = `pred >= 0.5`** (el score continuo redondea a "al menos 1 rastro") |
| Métricas | accuracy, precision, recall, specificity, F1, TP/FP/TN/FN, AUC |

Una sola regla, igual a la prescrita por el plan Fase 3 ("Binaria: umbral ≥1 rastro, pred ≥0.5") e
idéntica a la del bloque `binary_full` de `metrics_test_v2.json`: este JSON **reproduce esas
confusiones y métricas exactamente** (verificado al generarlo).

**Aclaración sobre el baseline v1 (hallazgo de esta fase).** El `binary_metrics_test.json` de v1
(y su copia `baseline_v1_binary_metrics.json`) dice en su texto "pred>=0.5 -> pos", pero su campo
`threshold: 1.0` es el que se aplicó de verdad: el recomputo desde
`Data/ml_out/lstm_fantasma/preds_test.csv` con **pred≥1.0** reproduce sus 4 confusiones de forma
exacta (p. ej. y3: TP=494, FP=201, TN=641, FN=1051), y con pred≥0.5 no. Es decir, el baseline v1
publicado usó **pred≥1.0** y su etiqueta textual era incorrecta — origen del "umbral mezclado"
señalado en `AUDIT_FASE2_V2.md` §riesgo 1 (que asumió lo contrario a partir del texto). Aquí se
corrige la presentación: v2 se reporta con pred≥0.5 y la comparación like-for-like contra v1 se
hace **recomputando v1 con el mismo umbral 0.5** (§4).

## 2. Resultados v2 (convención oficial: pred ≥ 0.5)

| Ventana | n_pos | Accuracy | Precision | Recall | Specificity | F1 | AUC |
|---|---|---|---|---|---|---|---|
| y3  | 1545 | 0.7067 | 0.6937 | 0.9793 | 0.2067 | 0.8121 | 0.6345 |
| y5  | 1698 | 0.7545 | 0.7484 | 0.9865 | 0.1829 | 0.8511 | 0.6469 |
| y10 | 1879 | 0.8140 | 0.8135 | 0.9910 | 0.1594 | 0.8935 | 0.6505 |
| y15 | 1961 | 0.8316 | 0.8361 | 0.9888 | 0.1080 | 0.9061 | 0.6484 |
| **prom** | — | **0.7767** | **0.7729** | **0.9864** | **0.1643** | **0.8657** | **0.6451** |

Matrices de confusión (TP / FP / TN / FN):

| Ventana | TP | FP | TN | FN |
|---|---|---|---|---|
| y3  | 1513 | 668 | 174 | 32 |
| y5  | 1675 | 563 | 126 | 23 |
| y10 | 1862 | 427 |  81 | 17 |
| y15 | 1939 | 380 |  46 | 22 |

El AUC usa el score continuo de la predicción (Mann-Whitney, sin umbral). Valores 0.59–0.65:
señal real pero modesta en la vista binaria, coherente con que el modelo se entrenó para
**regresión** (L2Loss) y su métrica principal es el MAE.

## 3. Umbral óptimo Youden (solo discusión, NO adoptado)

No existe artefacto de predicciones sobre el split de validación y **no se re-entrenó nada**, así
que el barrido Youden se hizo sobre el propio test: es un óptimo **in-sample**, informativo, y por
eso no puede usarse para reportar métricas (sería seleccionar el umbral mirando el test).

| Ventana | Umbral óptimo | J (rec+spec−1) | Accuracy | F1 |
|---|---|---|---|---|
| y3  | 0.762 | 0.2115 | 0.6946 | 0.7937 |
| y5  | 1.340 | 0.2266 | 0.7118 | 0.8069 |
| y10 | 2.372 | 0.2515 | 0.7285 | 0.8235 |
| y15 | 2.308 | 0.2638 | 0.8148 | 0.8905 |

Lectura para la defensa: subiendo el umbral se recupera specificity (0.30–0.45) a costa de recall,
pero el accuracy no mejora respecto a 0.5 (en y3/y5/y10 empeora) y el J máximo sigue siendo bajo
(≤0.27). Se mantiene **0.5 como convención fija a priori** por interpretación directa (≥0.5 → ≥1
rastro) y por comparabilidad con el baseline.

## 4. Comparación v2 vs v1

### 4a. Cifras publicadas (referencia; umbrales distintos, NO like-for-like)

v1 con su umbral publicado (pred≥1.0) vs v2 (pred≥0.5): F1 prom 0.6741 → 0.8657. Es la comparación
que circulaba hasta la auditoría F2; **sobreestima la mejora** porque los umbrales difieren.

### 4b. Like-for-like (ambos con pred≥0.5, mismo script y mismo test)

v1 recomputado desde `preds_test.csv` con la convención oficial:

| Ventana | F1 v1@0.5 | F1 v2@0.5 | Acc v1@0.5 | Acc v2@0.5 | AUC v1 | AUC v2 |
|---|---|---|---|---|---|---|
| y3  | 0.7569 | **0.8121** | 0.6598 | **0.7067** | 0.6111 | **0.6345** |
| y5  | 0.8010 | **0.8511** | 0.6988 | **0.7545** | 0.6073 | **0.6469** |
| y10 | 0.8342 | **0.8935** | 0.7336 | **0.8140** | 0.5959 | **0.6505** |
| y15 | 0.8524 | **0.9061** | 0.7553 | **0.8316** | 0.5924 | **0.6484** |
| **prom** | **0.8111** | **0.8657** | **0.7119** | **0.7767** | **0.6017** | **0.6451** |

**v2 gana like-for-like en las 4 ventanas** en F1, accuracy, recall y AUC: F1 prom
0.8111 → 0.8657 (**+0.0546**), acc prom 0.7119 → 0.7767, AUC prom 0.6017 → 0.6451. A cambio, la
specificity de v2 es menor (0.11–0.21 vs 0.27–0.37 de v1@0.5): v2 predice positivo con más
frecuencia. Divulgado, no oculto.

### 4c. Contra el clasificador trivial "siempre ≥1"

| Ventana | Trivial (n_pos/n) | Acc v2@0.5 |
|---|---|---|
| y3  | 0.6473 | **0.7067** |
| y5  | 0.7114 | **0.7545** |
| y10 | 0.7872 | **0.8140** |
| y15 | 0.8215 | **0.8316** |

v2 supera al trivial en las 4 ventanas; en y15 el margen es estrecho (+0.010), como ya señalaban
las auditorías Fase 0/1 y F2.

## 5. Notas honestas para la presentación

- La vista binaria es **complemento**; la métrica principal del modelo es regresión
  (MAE prom 1.4886 vs 1.7943 de v1, −17.0%).
- Con pred≥0.5 el modelo casi siempre predice "habrá rastro" (recall 0.98–0.99, specificity
  0.11–0.21): útil si el costo de perderse un fantasma es alto; limitado como discriminador.
- El dataset está desbalanceado hacia positivos (65–82% según ventana), lo que infla accuracy y F1;
  por eso se reportan también specificity, AUC y la comparación trivial.
- v1 intacto: nada bajo `Data/ml_out/lstm_fantasma/` fue modificado; el recomputo de §4b solo lee
  `preds_test.csv`.
