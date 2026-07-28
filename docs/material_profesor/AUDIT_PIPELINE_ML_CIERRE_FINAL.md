# Audit de cierre global — Pipeline ML (Pasos 0→6)

**Fecha:** 2026-07-27  
**Rol:** auditor final (síntesis; sin reentrenar / sin expandir features / sin commits).  
**Veredicto global:** **LISTO_CON_DEUDA**

---

## Resumen ejecutivo

El pipeline contractual del **DOCX v1.0** (extractor fantasmita + features multi-TF + normalización train-only + LSTM sin CNN + eval julio + demo de carga/predicción) está **cerrado y ejecutable**. La prep oral (guion ≤10 min + checklist + `demo_fantasma_predict.pl`) existe y el smoke día-D **PASS** en Fedora35 (~1.2 s, `--n 3`).

**No** se reclama t-SNE / GMM / HMM (Paso 5): oral 23 lo pide en paralelo; **no está en el DOCX** y **no bloquea** la oral.

Deudas materiales (Ghosts Opción A, F1 ausente, overfit probable, `bin_acc` y3 débil) están documentadas en audits por paso y son **aceptables** para presentar con honestidad. Nada bloqueante restante para el enunciado escrito.

---

## Veredicto global

| Campo | Valor |
|---|---|
| **Código** | **LISTO_CON_DEUDA** |
| ¿Cumple DOCX v1.0 (entregable LSTM + extractor + demo)? | **SÍ** |
| ¿Paso 5 t-SNE→GMM→HMM hecho? | **NO** (no exigido por DOCX; no inventar) |
| ¿Puede salir a oral mañana? | **SÍ**, con guion + demo + Plan B CSV |
| Alternativa más dura | `NO_LISTO` solo si fallara carga MXNet / faltaran artefactos — **no aplica** tras smoke |

---

## Tabla paso → estado → riesgo

| Paso | Estado ruta | Audit / evidencia | Riesgo oral | ¿Bloquea oral? |
|:---:|---|---|---|:---:|
| **0** MXNet + smoke acústico | **HECHO** | Acc 97.28% / AUC 0.99 (Fedora35) | Bajo (entorno ya validado) | **NO** |
| **1** CSV + Ghosts | **HECHO_CON_DEUDA** | [`AUDIT_PASO1_CIERRE.md`](AUDIT_PASO1_CIERRE.md) **PASS_CON_RIESGOS**; Ghosts **ALINEADO_PARCIAL**; contrato **Opción A** | Medio: profe pide “idéntico” Pine → responder Opción A | **NO** |
| **2** Extractor | **HECHO_CON_DEUDA** | [`AUDIT_PASO2_CIERRE.md`](AUDIT_PASO2_CIERRE.md) **PASS_CON_RIESGOS**; `t/50` PASS; disparo Opción A | Bajo–medio: canal vacío frecuente (condicional DOCX) | **NO** |
| **3** Full extract + norm | **HECHO_CON_DEUDA** | [`AUDIT_PASO3_CIERRE.md`](AUDIT_PASO3_CIERRE.md) **PASS_CON_RIESGOS**; train **7649** / test **2391**; 86 feats z-score | Bajo: test extract pre-fix AVWAP (sin fuga material) | **NO** |
| **4** LSTM | **HECHO_CON_DEUDA** | [`AUDIT_PASO4_CIERRE.md`](AUDIT_PASO4_CIERRE.md) **PASS_CON_RIESGOS**; gate demo **SÍ** | Medio: overfit; y3 `bin_acc`≈0.48; sin F1 | **NO** |
| **5** t-SNE→GMM→HMM | **Pendiente / paralelo** | Oral 23; **ausente del DOCX** | Alto **solo si se promete** en oral | **NO** (si no se inventa) |
| **6** Presentación | **HECHO_CON_DEUDA** (prep) | [`GUION_PRESENTACION_FINAL.md`](GUION_PRESENTACION_FINAL.md) + [`CHECKLIST_DEMO_FINAL.md`](CHECKLIST_DEMO_FINAL.md) + demo script | Bajo: ejecución en aula pendiente | **NO** |

---

## Checklist contractual DOCX (síntesis)

Fuentes: [`AUDIT_DOCX_INDICACIONES_FINAL_V1.md`](AUDIT_DOCX_INDICACIONES_FINAL_V1.md) + ruta + audits 1–4.

| Requisito DOCX | Estado |
|---|---|
| Objetivo: conteos rastros 3/5/10/15 tras aparición/reubicación | **PASS** (Opción A) |
| Train abr–jun / test jul-24 | **PASS** (`Data/2026_Abril-Junio.csv`, `Data/2026_07_24.csv`) |
| Extractor Replay 1m; features ≥3 TF; PIPs; pack 1–11 | **PASS_CON_RIESGOS** (condicionales 9/11 OK nulos) |
| Labels vs etiquetado automático | **PASS** |
| Normalizar + guardar params | **PASS** (`fantasma_norm_stats.json`) |
| LSTM; sin CNN primero; guardar + cargar + eval test | **PASS** |
| Presentación ≤10 min: extractor + features + eval + **demo** | **PASS** (prep lista; oral por ejecutar) |
| t-SNE / GMM / HMM | **N/A en DOCX** — no marcar como entregado |

Complemento oral 27 ([`AUDIT_ORAL_LUMINA_IA_ULTIMO_MES.md`](AUDIT_ORAL_LUMINA_IA_ULTIMO_MES.md)): muestreo correcto ≫ slides; métricas regresión y/o binarias; no rebalancear — **cubierto** (MAE/RMSE + `bin_acc`; F1 = deuda).

---

## Artefactos verificados (2026-07-27)

| Artefacto | Check |
|---|---|
| `Data/2026_Abril-Junio.csv` / `Data/2026_07_24.csv` | Existen (~88 736 / ~24 179 filas datos) |
| `Data/ml_out/fantasma_train_abril_junio.csv` | 7650 líneas (header+7649) |
| `Data/ml_out/fantasma_test_julio.csv` | 2392 líneas (header+2391) |
| `fantasma_{train,test}_norm.csv` + `fantasma_norm_stats.json` | 86 `feature_columns`; z-score; train_rows=7649 |
| `lstm_fantasma/fantasma_lstm.params` | 62 362 B |
| `metrics_test.json` / `preds_test.csv` / `train_config.json` | n=2387; `eval_only=0`; `seq_len=5` |
| Scripts extract / normalize / train / demo | Presentes bajo `scripts/` |

### Smoke auditor (Fedora35)

```bash
cd /mnt/c/Users/bryan/ia/proyecto_iaaa/Proyecto/ProyectoIAAA
perl -I. scripts/demo_fantasma_predict.pl --n 3
```

**Resultado:** EXIT 0; carga pesos OK; 3 filas TRUE vs PRED; MAE/RMSE coinciden con `metrics_test.json`; wall **~1.2 s**.

---

## Deudas aceptadas vs bloqueantes

### Aceptadas (no bloquean oral)

| Deuda | Origen | Cómo manejar en oral |
|---|---|---|
| Ghosts ≠ literal Pine (D1–D3); contrato **Opción A** | Paso 1 / Ghosts | “Congelamos Perl / comentario Josafa; no reclamamos paridad TV literal.” |
| Canal / SGR a menudo nulos | Paso 2 (condicional DOCX) | “Solo si cumplen la regla del enunciado.” |
| Test extract pre-fix AVWAP | Paso 3 | “Sin fuga material en `get_point(i)`; regen opcional.” |
| Overfit probable (1-epoch a veces mejor test) | Paso 4 | Mencionar en límites; no disculparse de más. |
| `bin_acc` y3 ≈ **0.48** | Paso 4 | Honestidad; MAE es métrica primaria de regresión. |
| Sin F1 / precisión / recall detallados | Oral 27 complemento | “v1: MAE/RMSE + bin_acc; F1 es deuda post-demo.” |
| Paso 5 t-SNE→GMM→HMM no hecho | Oral 23 paralelo | “Paralelo si alcanza; el DOCX pide LSTM + extractor + demo.” |
| Oral en aula aún no ejecutada | Paso 6 | Prep lista; checklist día-D abajo. |

### Bloqueantes (ninguno abierto)

| Ítem | Estado |
|---|---|
| Falta modelo / no carga | **Cerrado** (smoke demo + `--eval-only` en audit Paso 4) |
| Falta extract/norm train–test | **Cerrado** |
| Labels sin contrato | **Cerrado** (Opción A) |
| Inventar cadena t-SNE/GMM como hecha | **Evitar** — sería el único auto-bloqueo reputacional |

---

## Top 5 — decir / no decir en la oral

### Decir

1. **Objetivo:** tras cada aparición/reubicación del fantasma, predecir conteos de rastros en **3 / 5 / 10 / 15** min (4 salidas).  
2. **Muestreo Opción A** (no una fila por minuto); Replay causal; labels = trails automáticos.  
3. **86 features** z-score train-only; ≥3 TF (1m/10m/1h); PIPs; `meta_*` fuera de X.  
4. **LSTM sin CNN**, `seq_len=5`, train abr–jun / test julio; MAE/RMSE (+ bin_acc); **cargar** `.params` en vivo.  
5. **Límites honestos:** y3 binario débil; overfit posible; Ghosts = contrato A, no TV literal.

### No decir

1. Que el fantasma es **idéntico al Pine de TradingView** (D1–D3 abiertos).  
2. Que **t-SNE / GMM / HMM** ya está implementado o “es el entregable principal”.  
3. Que el modelo es **muy bueno** en y3 binario (~0.48) o que “ya resolvimos el overfit”.  
4. Que **rebalanceamos** clases o que el desbalance invalidó el enfoque (oral 27: no).  
5. Que van a **re-extraer / reentrenar** en la demo (solo carga + pred; Plan B = `preds_test.csv`).

---

## Checklist día-D (comandos)

Entorno: **WSL Fedora35**.

```bash
# 0) Repo
cd /mnt/c/Users/bryan/ia/proyecto_iaaa/Proyecto/ProyectoIAAA

# 1) Artefactos mínimos
ls -la Data/ml_out/lstm_fantasma/fantasma_lstm.params \
       Data/ml_out/fantasma_test_norm.csv \
       Data/ml_out/fantasma_norm_stats.json \
       Data/ml_out/lstm_fantasma/metrics_test.json \
       scripts/demo_fantasma_predict.pl

# 2) Smoke barato (antes de entrar al aula)
perl -I. scripts/demo_fantasma_predict.pl --n 3

# 3) DEMO ORAL (proyector; n=8 como guion)
perl -I. scripts/demo_fantasma_predict.pl --n 8

# 4) Backup carga modelo (si preguntan “¿cargó?”)
perl -I. scripts/train_fantasma_lstm.pl --eval-only \
  --model Data/ml_out/lstm_fantasma/fantasma_lstm.params \
  --out-dir Data/ml_out/lstm_fantasma

# 5) Plan B sin MXNet (improvisar)
head -n 15 Data/ml_out/lstm_fantasma/preds_test.csv
cat Data/ml_out/lstm_fantasma/metrics_test.json
```

**No correr en oral:** full extract, re-train, t-SNE/GMM/HMM.

Docs de apoyo en sala: guion + checklist + esta hoja.

---

## Enlaces de cadena

| Doc | Rol |
|---|---|
| [`../RUTA_FINAL_MODELOS.md`](../RUTA_FINAL_MODELOS.md) | Roadmap + cierre pipeline |
| [`AUDIT_DOCX_INDICACIONES_FINAL_V1.md`](AUDIT_DOCX_INDICACIONES_FINAL_V1.md) | Contrato escrito |
| [`AUDIT_ORAL_LUMINA_IA_ULTIMO_MES.md`](AUDIT_ORAL_LUMINA_IA_ULTIMO_MES.md) | Complemento oral |
| [`AUDIT_GHOSTS_VS_PIVOTPOINTS_HL.md`](AUDIT_GHOSTS_VS_PIVOTPOINTS_HL.md) | Paridad Ghosts |
| [`AUDIT_PASO1_CIERRE.md`](AUDIT_PASO1_CIERRE.md) … [`AUDIT_PASO4_CIERRE.md`](AUDIT_PASO4_CIERRE.md) | Cierres por paso |
| [`GUION_PRESENTACION_FINAL.md`](GUION_PRESENTACION_FINAL.md) | Reloj oral |
| [`CHECKLIST_DEMO_FINAL.md`](CHECKLIST_DEMO_FINAL.md) | Proyector |

---

## Veredicto final (una frase)

**LISTO_CON_DEUDA:** el enunciado DOCX (Pasos 0–4 + prep Paso 6) está cumplido y demo-verificado; presentar con deudas declaradas; **no** afirmar Paso 5 ni paridad TV literal.
