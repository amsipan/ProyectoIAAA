# Auditoría de cierre — reentrenamiento modelo v2 (Fase 7)

**Fecha:** 2026-07-28 (~06:00 UTC-5)
**Auditor:** independiente (no el worker; sin re-entrenar, sin tocar params/datos).
**Objeto:** cierre integral de `docs/PLAN_REENTRENAMIENTO_MODELO_V2.md` — checklist §Fase 7
contra el estado real del repo.

## Veredicto global

# **CERRADO**

Los 5 ítems del checklist de cierre verificados con evidencia propia del auditor (no solo
cadena documental): ejecución real de `--eval-only` sobre el params final, comparación
byte a byte de preds, lectura completa de HTML/PDF de slides, cruce de cifras contra los
JSON finales y verificación de integridad de v1 por contenido + timestamps.

## Checklist Fase 7

|| Ítem | Veredicto | Evidencia del auditor |
|---|---|---|---|
|| 1 | **v1 no roto** — `Data/ml_out/lstm_fantasma/` intacto | **PASS** | Los 9 artefactos presentes; mtimes 27-jul 23:50–23:59 (+ `binary_metrics_test.json` aditivo 28-jul 00:31, ya documentado en F0/F1 §0.1) idénticos a lo registrado por los audits F3 (ítem 4) y F4 (ítem 4). Contenido de `metrics_test.json` v1 leído hoy: MAE y3 0.9091 / y5 1.3106 / y10 2.1489 / y15 2.8087 (prom **1.7943**) = baseline documentado en `CHECK_FASE0_FASE1_V2.md`. Integridad confirmada además por los audits F2/F3/F4 (hashes/mtimes) en tres momentos intermedios. |
|| 2 | **v2 reproduce `--eval-only`** — `lstm_fantasma_v2/` y `lstm_fantasma_final/` reproducen métricas (MAE 1.4886, F1 0.8657) | **PASS** (ejecutado por este auditor) | En Fedora35: `train_fantasma_lstm_v2.pl --eval-only --model Data/ml_out/lstm_fantasma_final/fantasma_lstm.params --out-dir /tmp/fantasma_cierre_eval --hidden 48 --dropout 0.2 --batch-size 32 --seq-len 5` → **PROMEDIO MAE=1.4886, RMSE=1.8359, F1=0.8657**; MAE por ventana 0.8161/1.1479/1.7474/2.2430 y confusiones 1513/668/174/32, 1675/563/126/23, 1862/427/81/17, 1939/380/46/22 — exactas a `lstm_fantasma_final/metrics_test.json` y `binary_metrics_test.json`. Preds regeneradas **byte-idénticas** (SHA256 `97e3bf07…` igual, `cmp` limpio). Además `lstm_fantasma_final/fantasma_lstm.params` tiene SHA256 idéntico a `lstm_fantasma_v2/fantasma_lstm_v2.params` (copia final íntegra). Escritura solo en `/tmp`; directorios de modelos sin tocar. Es la 4ª reproducción independiente documentada (F2, F4, F5, cierre). |
|| 3 | **Métricas completas presentes** — `lstm_fantasma_final/metrics_test.json` + `binary_metrics_test.json` (4 ventanas, confusión, AUC) | **PASS** | Los 5 entregables finales presentes con nombres sin `_v2` (params, metrics, binary_metrics, preds, config). `metrics_test.json`: regresión MAE/RMSE × 4 ventanas + `binary_full` (acc/precision/recall/specificity/F1/confusión) + hiperparams + `selection` (r06, historial 8 runs). `binary_metrics_test.json`: 4 ventanas completas + AUC (0.6345/0.6469/0.6505/0.6484, prom 0.6451) + convención explícita (`label_threshold: 1.0`, `pred_threshold: 0.5`) + Youden in-sample marcado como informativo. |
|| 4 | **Slides/guion alineados a artefactos** — cifras == `lstm_fantasma_final/*.json`; spot-check MAE prom 1.49, F1 prom 0.87; sin rastros v1 en slides | **PASS** (2 observaciones menores, abajo) | HTML y PDF leídos **completos** por el auditor: regresión (0.82/1.15/1.75/2.24 · 1.01/1.41/2.15/2.77), binaria (acc 0.71/0.75/0.81/0.83, precision 0.69/0.75/0.81/0.84, recall 0.98–0.99, F1 0.81/0.85/0.89/0.91), confusión exacta (4×4), entrenamiento (48 unidades, dropout 0.2, parada temprana, grid de 8), cierre (7649/2391, 86, **1.49**, **0.87**). PPTX verificado con `_check_fase6.py` ejecutado por el auditor + lectura del script fuente `_gen_presentacion_pptx.py`: las "ausencias" que reporta el checker son artefactos (ver obs. 2). Sin cifras v1 en slides: ni 1.79 ni 0.67; la mejora se expresa como "un 17% menos" sin número viejo. Guion §5 y checklist: tabla correcta, paths a `lstm_fantasma_final/`, comando demo con defaults ya apuntando al params final y `hidden 48` (verificado en `scripts/demo_fantasma_predict.pl`). |
|| 5 | **Contrato A respetado** — labels D1–D3 sin cambiar; mismo extractor | **PASS** | `Market/ML/ExtractFantasmaDataset.pm` mtime 27-jul 21:31 (anterior a todo el trabajo v2); CSVs y stats congelados 27-jul 23:45; sin re-extracción en todo el plan (Fase 1 verificó filas 7649/2391, 86 features y distribuciones == Paso 3). Guion y slides mantienen la narrativa Opción A con D1–D3 como deuda declarada, sin reclamos nuevos. |

## Verificaciones adicionales del encargo

|| Punto | Veredicto | Detalle |
|---|---|---|---|
|| Cadena de auditorías F0–F4 existe y es coherente | **PASS** | `AUDIT_FASE0_FASE1_V2.md` (F0 PASS / F1 PASS → gate F2 SÍ), `AUDIT_FASE2_V2.md` (PASS_CON_RIESGOS → gate F3 SÍ; riesgos umbrales/specificity divulgados), `AUDIT_FASE3_V2.md` (PASS → gate F4 SÍ; hallazgo umbral v1 pred≥1.0 confirmado, comparación corregida like-for-like F1 0.8111 → 0.8657), `AUDIT_FASE4_V2.md` (PASS → gate F5 SÍ; v2b descartada con recomputo exacto). Gates encadenados; las pasadas prematuras (F0/F1 02:50, F2 03:05) quedaron marcadas como superadas con historial explícito. El riesgo de umbrales detectado en F2 quedó resuelto en F3; nada quedó arrastrado sin divulgar. |
|| Variante v2b descartada documentada; final = v2 simple justificado | **PASS** | `LSTM_FANTASMA_V2B.md`: "Veredicto: **DESCARTADA**" (MAE prom 1.4975 > 1.4886; pierde también en val). `MODELO_FINAL_V2.md`: selección con criterio fijo (primario MAE, secundario F1) definido antes de mirar números; final = **v2 simple r06**; copia byte-idéntica verificada entonces y re-verificada hoy (SHA256 params). |
|| Plan actualizado con todas las fases marcadas | **PASS** | Fases 0–6 marcadas HECHA con fecha/hora y resultado en el propio plan; esta Fase 7 queda marcada con el cierre. |
|| Sin commits pendientes que el usuario no pidiera | **PASS** | `git log`: último commit `86eff8f` (cierre feedback indicadores, previo al trabajo v2). Todo el trabajo v2 (artefactos, scripts, docs, slides) está **untracked/modified** en el working tree; ningún commit del worker. Rama actual `feature/liq-experiment` (preexistente). |

## Observaciones residuales (no bloqueantes)

1. **RMSE promedio (1.84) no aparece en las slides** (sí en el guion §5 y en los JSON): la
   tabla de regresión de slides muestra las 4 ventanas sin fila de promedio; decisión
   editorial coherente con MAE como métrica primaria. No es una cifra incorrecta.
2. **`_check_fase6.py` produce 2 falsos positivos** si se reusa: (a) reporta "ausentes" los
   TP ≥1000 porque el PPTX usa separador de miles ("1 513") y el checker aplana a tokens
   ("1", "513"); (b) marca "0.91" como rastro v1, pero el "0.91" presente es el **F1 y15 del
   modelo final** (0.9061), no el MAE y3 de v1 (0.9091) — que no aparece en ninguna slide.
   El MAE y3 v1 tampoco está en guion/checklist en contexto de regresión.
3. **Cosmético:** `lstm_fantasma_final/metrics_test.json` conserva `"model":
   "...lstm_fantasma_v2/fantasma_lstm_v2.params"` (copia byte-idéntica del v2). Sin impacto:
   el `--eval-only` contra el params final reproduce esas métricas exactas (verificado hoy).
4. **Riesgos ya divulgados en la cadena** (se mantienen, no son nuevos): specificity baja
   (0.11–0.21) con pred≥0.5 y acc y15 apenas sobre el trivial "siempre ≥1"; variabilidad de
   re-entrenamiento MXNet CPU (±0.01 MAE) si alguien re-entrena; copia Fedora35
   `~/Documents/ProyectoIA/ProyectoIAAA` desincronizada (todo el trabajo se hizo contra el
   árbol canónico `/mnt/c/...`).

## Resumen del estado final del modelo

Se entrega el modelo **v2 simple (run r06)**: LSTM de 1 capa (48 unidades, dropout 0.2,
lr 0.005, batch 32, `seq_len=5`, seed 42), seleccionado por validación causal con early
stopping entre 8 configuraciones, materializado en `Data/ml_out/lstm_fantasma_final/`.
Sobre el test de julio (n=2387 secuencias, datos nunca vistos): **MAE promedio 1.4886**
(0.82/1.15/1.75/2.24 por ventana; −17.0% vs v1 1.7943, mejor en las 4 ventanas), **RMSE
promedio 1.8359**, y vista binaria (≥1 rastro, pred ≥0.5) con **F1 promedio 0.8657**
(0.81→0.91), recall 98–99%, AUC prom 0.6451; like-for-like @0.5 contra v1: F1 0.8111 →
0.8657 con victoria en las 4 ventanas. La variante con Dense intermedia (v2b) fue
descartada por no superar el primario. Pipeline congelado bajo contrato A, reproducible
extremo a extremo (extractor → normalización → train → eval-only byte-idéntico), con
slides/guion/checklist alineados a los artefactos y cadena de auditorías F0–F4 cerrada.

## Cadena de gates (resumen)

| Gate | Resultado |
|---|---|
| Fase 0/1 → entrenar | SÍ (v1 intacto, dataset congelado, baseline reproducido) |
| Fase 2 → métricas completas | SÍ (PASS_CON_RIESGOS; MAE 1.7943 → 1.4886) |
| Fase 3 → variante opcional | SÍ (PASS; convención única + umbral v1 corregido) |
| Fase 4 → selección final | SÍ (PASS; v2b descartada) |
| Fase 5 → modelo final | v2 simple r06 en `lstm_fantasma_final/` (byte-idéntico, eval-only exacto) |
| Fase 6 → material de exposición | Slides/guion/checklist con cifras del final (verificado en este cierre) |
| **Fase 7 → cierre** | **CERRADO** |

**El trabajo v2 queda CERRADO.**
