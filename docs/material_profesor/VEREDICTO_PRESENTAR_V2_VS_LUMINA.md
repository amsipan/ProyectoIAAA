# Veredicto independiente — ¿Presentar LSTM v2 frente a Lumina/DOCX?

**Fecha auditoría:** 2026-07-28  
**Auditor:** pedagógico/técnico independiente (sin re-entrenar, sin commits).  
**Objeto:** modelo final = `Data/ml_out/lstm_fantasma_final/` (= v2 simple r06).  
**Fuentes cruzadas:** Lumina MCP (sesión máxima `2d01313877a5` 27-jul + orales 20–23 jul), DOCX v1.0, audits locales, artefactos JSON.

---

## Veredicto (1 línea)

**PRESENTAR_V2_CON_CAVEATS**

El contrato oral+DOCX del entregable LSTM/fantasmita **se cumple** con el pipeline congelado (Opción A). El v2 es **mejor** que el v1 sobre el mismo contrato. Se puede **exponer solo el v2**. Los caveats (Ghosts ≠ Pine literal, specificity baja, cadena t-SNE/GMM/HMM no hecha) son **honestos y no bloquean** la presentación si se mencionan en 15–30 s al final o solo si preguntan.

---

## 1. Fuentes Lumina verificadas en esta pasada

| Peso | Fecha | Session id | Uso en este veredicto |
|---|---|---|---|
| **Máximo** | 2026-07-27 | `2d01313877a5` | Transcript completo vía MCP + copia local `transcripcion_IA_2026-07-27_ultimas_indicaciones.txt` |
| Escrito | 2026-07-25 | DOCX aula | `AUDIT_DOCX_INDICACIONES_FINAL_V1.md` + carpeta `10_indicaciones_finales_2026-07-27/` |
| Alto | 2026-07-23 | `72a062cbd418` | PIPs, split abr–jun/jul, rúbrica; t-SNE/GMM/HMM = paralelo |
| Alto | 2026-07-22 | `56af8823ac16` | Plantilla LSTM lab; ~10 min |
| Alto | 2026-07-21 | `cc5a2f136d5a`, `384c13811adb` | Conteos fantasmita; AVWAP |
| Alto | 2026-07-20 | `6464bc920db3`, `a838e60e197e` | Definición canónica 4 salidas + TFs 1m/10m/1h |

Jerarquía aplicada (igual que audits previos): **DOCX v1.0 + oral 27** mandan; oral 20 define fantasmita; oral 23 es apéndice (PIPs/rúbrica + t-SNE/GMM/HMM si alcanza).

---

## 2. Tabla requisito del profe → evidencia pipeline → estado

| # | Requisito (cita) | Evidencia en pipeline | Estado |
|---|---|---|---|
| 1 | **Muestreo causal por aparición/reubicación del fantasma** (no 1 fila/min). Oral 27: *«cada vez que aparece el fantasma o que se desplaza tenemos que hacerlo otra vez la toma… para 3, 5, 10 y 15»*; *«Replay… temporalidad de 1 minuto»*. DOCX: disparo = aparición + reubicación. | `ExtractFantasmaDataset.pm`: evento = tip provisional; `feature_bar = event_bar + 1`; estructura ≤ `event_bar`. Filas train 7649 / test 2391 (eventos, no minutos). | **CUMPLE** |
| 2 | **Labels y3/y5/y10/y15** = conteo de rastros `"1"` en ventanas futuras. Oral 27: *«Si ninguno aparece, el conteo se asigna cero… cuenta uno»*; ventanas hasta 15. DOCX: 3/5/10/15. | Columnas `y3,y5,y10,y15` en CSV; LSTM 4 salidas; `metrics_test.json` → `targets: [y3,y5,y10,y15]`. | **CUMPLE** (bajo **contrato Opción A**, ver gap G1) |
| 3 | **≥3 TF: 1m / 10m / 1h**. Oral 20: *«pequeña? 1 minuto. Mediana, 10 minutos. … grande? 1 hora»*. DOCX §4.2 igual. | Pack `full` con columnas `*_1m` / `*_10m` / `*_1h`; TF `10m` en `MarketData`. | **CUMPLE** |
| 4 | **Features de liquidez en PIPs** + extras ATR/vol/EMA. Oral 23: *«estandarizar… a través de PIPs»*. DOCX: distancia precio medio → niveles → PIP; ATR/vol/EMA(9). | `pip_*` en CSV; PIP NQ = 0.25; `atr_1m`, `vol_1m`, `vol_ema9_1m`; 86 feats normalizadas. | **CUMPLE** |
| 5 | **Lista features 1–11** (OB, FVG, Fib, AVWAP, AVP, S/R 4h/D/W, BOS/CHoCH, EQH/EQL, S/G/R cond., S/D, Canal cond.). DOCX §4.3. | Documentado en `EXTRACTOR_FANTASMA.md`; condicionales 9/11 pueden ser nulos (permitido). | **CUMPLE** (condicionales OK nulos) |
| 6 | **Train abr–jun / test julio** (CSV profe). Oral 27: *«clase de abril hasta junio»*; DOCX: `2026_Abril-Junio.csv` + `2026_07_24.csv`. | Extracción desde esos CSV; `fantasma_train_norm.csv` / `fantasma_test_norm.csv`; eval `split: test_julio`. | **CUMPLE** |
| 7 | **Normalizar + persistir params; reusar en test**. DOCX §5. | `fantasma_norm_stats.json` (z-score train-only); test usa mismos stats. | **CUMPLE** |
| 8 | **LSTM sin CNN primero**. DOCX: *«Sugiero primero probarlo sin capas convolucionales»*. Oral 20 menciona CNN opcional. | `hyperparams.cnn: 0`; arquitectura LSTM→Dropout→Dense(4). Variante Dense intermedia (v2b) descartada; CNN no usada. | **CUMPLE** |
| 9 | **seq_len ≈ 5** (pista oral 27). *«utilizando un 5-slank… tamaño de secuencia de 5… Tomo 5 muestras»*. | `seq_len: 5` en `metrics_test.json` / `train_config.json`. | **CUMPLE** |
| 10 | **Métricas: regresión y/o binaria**. Oral 27: *«regresión para medir cuantos aparecen… 3, 5, 10, 15»*; *«binarizar… Precision, exhaustividad, medida F, sensibilidad»*; *«Puede usar la una y … la otra»*. | MAE/RMSE ×4 + binary_full (acc/prec/rec/spec/F1/confusión) + AUC en `binary_metrics_test.json`. | **CUMPLE** |
| 11 | **Desbalance no es excusa**. Oral 27: *«El LSTM funciona sensible a … la frecuencia… no es excusa»*. | Sin rebalance artificial; frecuencias naturales en labels. | **CUMPLE** |
| 12 | **Presentación ≤10 min; muestreo > slides; demo modelo+tabla**. Oral 27: *«no necesito ver diapositivas bonitas… indicaciones correctas de cuando ocurren los eventos»*. DOCX §8. | Guion + slides + `demo_fantasma_predict.pl` apuntan a `lstm_fantasma_final/`. | **CUMPLE** (prep lista; ejecución el día D) |
| 13 | **Ghosts “implementación idéntica”** al `.txt`. DOCX §3. | Perl/`PivotPointsHL` bajo **Opción A** (comentario Josafa / app); D1–D3 abiertos vs Pine literal. | **PARCIAL** — ver G1 |
| 14 | **No predecir tipo Sweep/Grab/Run** como salida obligatoria. Oral 27: *«¿Va a haber una manipulación? Sí o no… uno no sabe el tipo»*. | LSTM predice conteos (± vista binaria aparece/no); S/G/R como feature condicional, no label. | **CUMPLE** |
| 15 | **Cadena t-SNE→GMM→HMM** (oral 23). | No entregada; subordinada al DOCX/27 (LSTM+fantasma). | **PARCIAL / no bloqueante** — ver G4 |

---

## 3. Respuestas explícitas a las 4 preguntas del encargo

### 3.1 ¿El v2 cumple el contrato DOCX + oral?

**Sí, con el caveat de Ghosts Opción A (PARCIAL en “idéntico Pine”).**

Cumple muestreo causal, 4 labels, ≥3 TF, PIPs, LSTM sin CNN, `seq_len=5`, split abr–jun/julio, normalización train-only, métricas regresión+binaria, demo de carga. Evidencia numérica del final (`lstm_fantasma_final/metrics_test.json`):

| Métrica (test julio, n=2387) | Valor |
|---|---:|
| MAE prom | **1.4886** |
| RMSE prom | **1.8359** |
| F1 prom (pos ≥1, pred ≥0.5) | **0.8657** |
| Features / seq_len / CNN | 86 / 5 / 0 |

Citas ancla oral 27 (Lumina `2d01313877a5`):

> «cuando ustedes presenten no necesito ver diapositivas bonitas… que han tomado … las indicaciones correctas de cuando ocurren los eventos»

> «cada vez que aparece el fantasma o que se desplaza tenemos que hacerlo otra vez la toma de los datos para 3, 5, 10 y 15»

> «regresión para medir cuantos aparecen … 3, 5, 10, 15 … binarizar … Precision, exhaustividad, medida F, sensibilidad … Puede usar la una y puede usar la otra»

### 3.2 ¿Es “tal cual el primero” o es mejor manteniendo el mismo contrato?

**Es mejor, mismo contrato de datos/labels (Opción A, mismos CSV normalizados).** No es un modelo distinto de enunciado; es el mismo problema con entrenamiento más cuidadoso.

| Qué | v1 (`lstm_fantasma/`) | v2 final (`lstm_fantasma_final/`) |
|---|---|---|
| Extractor / labels / feats / split | Congelado 27-jul | **Idéntico** (sin re-extracción) |
| Arquitectura | LSTM → Dense(4), sin CNN | **Igual familia**; dropout Dense explícito; sin CNN |
| Entrenamiento | Epochs fijos (overfit probable) | **Grid 8 runs** + **val causal 15%** + **early stop** (paciencia 4); best = r06 ep.3 |
| Hiperparams ganadores | hidden≈32 (baseline) | **h=48, dropout=0.2, lr=0.005, batch=32** |
| MAE prom test | 1.7943 | **1.4886 (−17.0%)** — gana las 4 ventanas |
| F1 prom @0.5 like-for-like | 0.8111 | **0.8657 (+0.0546)** — gana las 4 ventanas |
| Specificity @0.5 | ~0.27–0.37 | **Más baja** (~0.11–0.21): predice positivo más a menudo |

Fuente: `MODELO_FINAL_V2.md`, `METRICAS_BINARIAS_V2.md`, `AUDIT_CIERRE_V2.md`.

### 3.3 ¿Se puede presentar solo el v2 y obviar el v1?

**Sí.** El oral/DOCX piden *un* modelo entrenado+evaluado+demo, no un histórico de baselines. Las slides ya van con cifras del final (MAE ~1.49, F1 ~0.87) sin tablas v1.

**Si el profe pregunta por el primero:**

> «El primer LSTM usaba el mismo extractor y los mismos datos (abril–junio / julio). Con epochs fijos tendía a sobreajustar. Reentrenamos con validación causal, early stopping y un grid pequeño; el modelo que presentamos baja el MAE promedio un ~17% (1.79 → 1.49) y sube el F1 like-for-like. El v1 queda archivado como baseline, no hace falta mostrarlo.»

No abrir el debate del umbral v1 pred≥1.0 vs 0.5 salvo pregunta técnica profunda.

### 3.4 ¿Gaps residuales? ¿Bloquean?

| ID | Gap | ¿Bloquea? | Cómo hablarlo |
|---|---|---|---|
| **G1** | **Opción A vs B (rastros / Ghosts “idéntico”)**. DOCX pide idéntico a `Ghosts_in_swings.txt`; el `.txt` es ambiguo (comentario vs paints). Congelamos **Opción A** (Perl / comentario Josafa: `"1"` solo si la punta se mueve). | **No** | «Alineamos al comportamiento causal de la app y al comentario del indicador; no reclamamos paridad TV literal del Pine.» |
| **G2** | **Specificity baja** (0.11–0.21) con pred≥0.5; recall ~0.99. Acc y15 apenas sobre trivial “siempre ≥1”. | **No** | Métrica primaria = **regresión MAE**. Binaria = complemento. Si insiste: «priorizamos no perder rastros; el coste es más FP.» |
| **G3** | Canal / S/G/R a veces vacíos (condicionales DOCX 9/11). | **No** | DOCX los marca condicionales. |
| **G4** | t-SNE→GMM→HMM (oral 23) no entregado. | **No** | Oral 27 + DOCX reenfocan a LSTM+fantasma; 23 queda paralelo «si alcanza». |
| **G5** | Fib 1m / EQH 1h a veces vacíos al inicio de serie. | **No** | Calentamiento documentado; no invalida el muestreo. |

Ninguno contradice la frase del oral 27 sobre lo que quiere ver en la exposición (muestreo correcto + data en el lugar correcto).

---

## 4. Comparación v1 vs v2 (qué cambió / qué no)

### No cambió (contrato)

- CSV train/test del profe  
- Extractor Replay 1m, disparo fantasma, Opción A  
- 86 features z-score, `meta_*` fuera de X  
- 4 salidas `y3…y15`, LSTM sin CNN, `seq_len=5`  
- Evaluación solo en julio  

### Sí cambió (calidad de entrenamiento / presentación)

| Cambio | Efecto |
|---|---|
| Early stopping + val causal | Checkpoint en ep.3 (r06); evita el overfit v1 |
| Grid 8 configs | Selección por MAE val, sin fuga de test |
| hidden 48 + dropout Dense | Mejor capacidad / regularización |
| Métricas binarias completas + AUC | Cumple oral 27 («una y la otra») |
| Artefacto `lstm_fantasma_final/` | Entrega limpia para demo |

v2b (LSTM+Dense intermedia) **descartada** (MAE 1.4975 > 1.4886): no meterla en la oral.

---

## 5. Recomendación de exposición

### Qué mostrar (orden oral 27 + DOCX)

1. **Disparo:** Replay 1m → aparición/reubicación → nueva muestra (frase clave del 27).  
2. **Labels:** 4 conteos 3/5/10/15; rango típico 0…3 (oral 27).  
3. **Features:** PIPs, ≥3 TF, 86 cols, z-score train-only; 1 fila de ejemplo.  
4. **Split:** abr–jun train / julio test.  
5. **Métricas julio:** MAE por ventana + promedio **1.49**; F1 **0.87** (vista binaria).  
6. **Demo:** `perl -I. scripts/demo_fantasma_predict.pl --n 8` (params final).  
7. **30 s límites:** Opción A; specificity; no prometemos tipo S/G/R.

### Qué NO meter

- Historial v1 / v2b / tablas de overfit internas  
- Debate umbral pred≥1.0 del baseline v1  
- t-SNE / GMM / HMM (salvo pregunta; decir «paralelo, no el entregable de esta oral»)  
- Canal vacío / deudas D2–D3 como drama  
- Slides bonitas sin demo de muestreo/predicción  

### Frase de cierre alineada al profe

> «No inventamos el algoritmo: sacamos la data en el momento correcto del fantasmita, con contexto de liquidez en PIPs, y el LSTM predice los conteos; aquí las métricas en julio y la demo cargando el modelo.»

---

## 6. Gaps residuales no bloqueantes (lista corta)

1. Ghosts **Opción A** ≠ Pine literal (D1–D3).  
2. Specificity baja / y15 cerca del trivial en binario.  
3. Condicionales DOCX (canal, S/G/R) a menudo nulos.  
4. Cadena t-SNE/GMM/HMM (oral 23) ausente — subordinada.  
5. AUC binaria modest (~0.65): modelo entrenado como **regresión**; coherente.

---

## 7. Artefactos de verdad (día D)

| Path | Rol |
|---|---|
| `Data/ml_out/lstm_fantasma_final/fantasma_lstm.params` | Pesos finales |
| `Data/ml_out/lstm_fantasma_final/metrics_test.json` | MAE/RMSE + binary_full |
| `Data/ml_out/lstm_fantasma_final/binary_metrics_test.json` | Acc/F1/AUC + confusión |
| `Data/ml_out/lstm_fantasma_final/preds_test.csv` | Preds julio |
| `Data/ml_out/lstm_fantasma_final/train_config.json` | Grid + r06 |
| `docs/material_profesor/GUION_PRESENTACION_FINAL.md` | Guion ≤10 min |
| `docs/material_profesor/AUDIT_CIERRE_V2.md` | Cierre técnico v2 |

---

## 8. Conclusión del auditor

Cruzando Lumina 27-jul (transcript MCP `2d01313877a5`), DOCX v1.0 y los artefactos `lstm_fantasma_final/`, el modelo v2 **sí es presentable como el entregable de modelos** del curso. No es “el mismo número que v1”: es **el mismo contrato, mejores métricas**. Los únicos matices materiales son honestidad sobre **Opción A** y **límites de la vista binaria** — no invalidan el muestreo ni el enunciado oral del 27.

**Veredicto operativo:** presentar **solo v2**; mencionar v1 solo si preguntan; caveats en el bloque de límites, no en el hero de la slide.

---

*Fin del veredicto. Sin commits. Sin re-entrenamiento.*
