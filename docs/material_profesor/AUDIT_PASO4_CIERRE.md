# Audit de cierre — Paso 4 (LSTM fantasmita)

**Fecha:** 2026-07-27  
**Rol:** auditor de cierre Paso 4 → gate demo/presentación.  
**Veredicto Paso 4:** **PASS_CON_RIESGOS**  
**Gate demo/presentación:** **SÍ**  
*(En `RUTA_FINAL_MODELOS.md`: demo = **Paso 6**; t-SNE/GMM/HMM = Paso 5 paralelo, no bloquea.)*

---

## Resumen

| Ítem | Resultado |
|---|---|
| Código train + data loader | **PASS** — `scripts/train_fantasma_lstm.pl` + `Market/ML/FantasmaLSTMData.pm` (`perl -c` OK) |
| Artefactos `Data/ml_out/lstm_fantasma/` | **PASS** — params, metrics, preds, config, train.log |
| `seq_len=5`, 86 feats, 4 salidas | **PASS** — shapes `7645×5×86` / `2387×5×86` → `y ∈ R^4` |
| Sin CNN | **PASS** — `hyperparams.cnn=0`; Dense lineal sobre último paso LSTM |
| Train-only fit (abr–jun) / eval julio | **PASS** — train CSV + test `fantasma_test_norm.csv` |
| No `time` / `meta_*` en X | **PASS** — features = `feature_columns` del stats (86) |
| Guardar + cargar modelo | **PASS** — `--eval-only` carga `.params` y reproduce métricas |
| Métricas DOCX (evaluar + comparar labels) | **PASS** — MAE/RMSE + preds `true_*`/`pred_*` |
| F1 / precisión / recall | **DEUDA** — oral 27 lo eleva; DOCX no fija lista; no bloquea |
| Overfit / bin_acc y3 débil | **RIESGO** — no bloquea demo |
| Doc `LSTM_FANTASMA.md` | **PASS** — alineado con corrida v1 |
| Gate demo (DOCX § presentación) | **SÍ** |

Estado en ruta: **HECHO_CON_DEUDA** (`docs/RUTA_FINAL_MODELOS.md`).

---

## Checklist contrato técnico

| Check | Esperado | Observado | Resultado |
|---|---|---|---|
| LSTM Gluon NTC sin CNN | lab / DOCX | `FantasmaLSTM` + Dense; `cnn: 0` | **PASS** |
| `seq_len` | ≈5 | 5 (CLI + JSON + log) | **PASS** |
| Features | 86 de stats | `n_features=86`; lista = `fantasma_norm_stats.json` | **PASS** |
| Targets | `y3,y5,y10,y15` | 4 salidas; labels sin normalizar | **PASS** |
| X sin tiempo | no entrenar meta/time | 0 cols `meta_*` / `time` / `y*` en features | **PASS** |
| Split | train abr–jun / test jul | paths norm + `split=test_julio` | **PASS** |
| Secuencias | orden CSV; label = última fila ventana | `make_sequences` + `end_idx` | **PASS** |
| Persistencia | guardar modelo | `fantasma_lstm.params` (62 362 B) | **PASS** |
| Carga | `--eval-only` | métricas idénticas a train.log (Fedora35) | **PASS** |
| Predicciones | comparar vs auto | `preds_test.csv` 2387 filas + meta | **PASS** |

---

## Checklist artefactos

| Archivo | Rol | Resultado |
|---|---|---|
| `fantasma_lstm.params` | pesos Gluon | **PASS** |
| `metrics_test.json` | MAE/RMSE + bin_acc | **PASS** (n=2387) |
| `preds_test.csv` | true/pred + meta | **PASS** |
| `train_config.json` | hiperparams + feats | **PASS** (auditor restauró `eval_only:0` tras smoke de carga) |
| `train.log` | corrida epochs=20 | **PASS** (~156 s; EXIT:0) |
| `smoke.log` / `smoke_eval.log` | evidencia overfit 1-epoch | **INFO** |

### Métricas test julio (corrida v1, epochs=20)

| Target | MAE | RMSE | bin_acc (≥1) | n_pos |
|---|---:|---:|---:|---:|
| y3 | 0.91 | 1.14 | **0.48** | 1545/2387 |
| y5 | 1.31 | 1.67 | 0.57 | 1698/2387 |
| y10 | 2.15 | 2.75 | 0.68 | 1879/2387 |
| y15 | 2.81 | 3.58 | 0.72 | 1961/2387 |

Train L2: 1.87 → 1.10 (20 epochs). Shapes: train `7645×5×86`, test `2387×5×86`.

### Spot-check `--eval-only` (auditor, Fedora35)

```text
perl -I. scripts/train_fantasma_lstm.pl --eval-only \
  --model Data/ml_out/lstm_fantasma/fantasma_lstm.params \
  --out-dir Data/ml_out/lstm_fantasma
```

Carga OK; MAE/RMSE/bin_acc **idénticos** a `train.log` / `metrics_test.json`. Cumple DOCX: entrenar → guardar → cargar → evaluar.

---

## Checklist DOCX / oral (alcance Paso 4)

| Requisito | Fuente | Resultado |
|---|---|---|
| LSTM numérico; sin CNN primero | DOCX | **PASS** |
| Entrenar + guardar + cargar + evaluar julio | DOCX | **PASS** |
| Comparar vs etiquetado automático | DOCX | **PASS** (`preds_test.csv`) |
| Lista fija de scores (F1, etc.) | DOCX | **N/A** — no fija |
| Regresión y/o clasificación | Oral 27 | **PARCIAL** — MAE/RMSE + bin_acc; falta F1/P/R |
| No rebalancear | Oral 27 | **PASS** |
| Normalización train-only ya hecha | Paso 3 | **PASS** (stats reutilizados) |

---

## Deuda / riesgos (¿bloquean demo?)

| Deuda | ¿Bloquea demo? | Nota |
|---|---|---|
| **Overfit probable** | **NO** | Smoke 1 epoch (`smoke_eval.log`): MAE test mejor (y3 0.88 vs 0.91; bin_acc y3 0.69 vs 0.48). Train L2 baja sin val-split formal. Tuning/early-stop = post-demo opcional. |
| **bin_acc y3 ≈ 0.48** | **NO** | Débil vs baseline mayoría (~0.65 si siempre “≥1”). Reportar con honestidad; MAE sigue siendo métrica primaria de regresión. |
| **Sin F1 / precision / recall** | **NO** | Oral 27 los nombra; DOCX no los exige. Complemento demo opcional (calcular offline desde preds). |
| Test extract pre-fix AVWAP | **NO** | Deuda Paso 3; sin fuga material documentada. |
| CNN / cabezas binarias / one-hot `sgr_kind` | **NO** | Fuera de v1. |
| t-SNE → GMM → HMM | **NO** | Paso 5 paralelo; no en DOCX. |

**Conclusión deuda:** **PASS_CON_RIESGOS** — no bloquea gate demo.

---

## Qué debe mostrar la demo (mínimo DOCX)

Presentación grupal **≤10 min**. Orden contractual:

1. **Extractor** — disparo por aparición/reubicación del fantasma (Opción A); Replay 1m; labels `y3/y5/y10/y15`.
2. **Features** — 86 cols z-score (stats train); ≥3 TF (1m/10m/1h); PIP a niveles; metadata **no** en X.
3. **Evaluación julio** — tabla MAE/RMSE (+ bin_acc); mencionar overfit posible y y3 binario débil sin disculparse de más.
4. **Demo final (obligatoria):**  
   - cargar `fantasma_lstm.params`;  
   - cargar tabla ya extraída (`fantasma_test_norm.csv` o `preds_test.csv`);  
   - mostrar predicciones vs labels auto (unas filas con `meta_time`).

Comando demo de carga (sin reentrenar):

```bash
perl -I. scripts/train_fantasma_lstm.pl --eval-only \
  --model Data/ml_out/lstm_fantasma/fantasma_lstm.params \
  --out-dir Data/ml_out/lstm_fantasma
```

Complemento oral: **muestreo correcto ≫ slides**. No hace falta cadena t-SNE/GMM/HMM para cerrar el escrito.

---

## Gate demo / presentación

| Pregunta | Respuesta |
|---|---|
| ¿Modelo entrenado y guardado? | **SÍ** |
| ¿Eval julio con comparación a labels? | **SÍ** |
| ¿Carga de modelo verificada? | **SÍ** (`--eval-only`) |
| ¿Contrato seq_len/86/4/sin time/sin CNN? | **SÍ** |
| ¿F1 o re-tune obligatorio antes de demo? | **NO** |
| ¿Abrir preparación de slides + demo en vivo? | **SÍ** |

**Gate: SÍ.**

### Siguiente (agente / humano)

```text
Paso 6 (demo/presentación): armar guion ≤10 min con extractor + features +
métricas julio + demo --eval-only / preds_test.csv.
Paso 5 t-SNE/GMM/HMM: solo si alcanza tiempo; no bloquea.
Opcional post-demo: early-stop / epochs↓ / F1 desde preds.
```

---

## Veredicto final

**PASS_CON_RIESGOS**

- LSTM v1 contractual listo (sin CNN, seq_len=5, 86→4, train-only, eval julio, save/load OK).  
- Riesgos: overfit (1-epoch mejor en test), bin_acc y3 débil, sin F1 — **no bloquean**.  
- **Gate demo/presentación abierto.**
