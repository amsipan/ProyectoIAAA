# Plan de reentrenamiento — modelo v2 (fantasmita, manteniendo contrato A)

**Fecha:** 2026-07-28  
**Base:** `docs/RUTA_FINAL_MODELOS.md`, DOCX v1.0, oral 27-jul, audits Paso 1–4, y recomendación visual del side chat (arquitectura fully connected + mejoras métricas).  
**Contrato de labels:** **Opción A** (mantenemos; no cambiamos D1–D3).

Objetivo: entrenar un modelo **mejor y más presentable** (más métricas, menos overfit, posible arquitectura más rica) **sin** romper el pipeline ya validado.

> **Estado de auditoría (2026-07-28, re-audit tras fix del worker):** Fase 0 **PASS** + Fase 1 **PASS** → **gate Fase 2 = SÍ** (entrenar en Fedora35/MXNet). v1 intacto, `lstm_fantasma_v2/` + baseline binario v1 (match exacto verificado), checks de datos reproducidos. Detalle: [`docs/material_profesor/AUDIT_FASE0_FASE1_V2.md`](material_profesor/AUDIT_FASE0_FASE1_V2.md). Observación no bloqueante: copiar el criterio de selección (MAE primario / F1 secundario) a `MODELO_V2_TRABAJO.md` al iniciar Fase 2.
>
> **Estado de auditoría Fase 2 (2026-07-28 ~03:55, re-audit tras entrega del worker):** **PASS_CON_RIESGOS** — gate del plan cumplido por criterio primario: **MAE prom 1.7943 → 1.4886 (−17.0%)** y F1 prom 0.6741 → 0.8657 (pred≥0.5, like-for-like). Ganador r06 (h=48, d=0.2, lr=0.005, b=32, best epoch 3) por val causal, sin fuga de test. Recomputo independiente desde preds = exacto; `--eval-only` regenera artefactos byte-idénticos; v1 intacto (hashes). Riesgos no bloqueantes: umbrales binarios mezclados en presentación (corregir en Fase 3), specificity baja con pred≥0.5 (divulgada). **Gate Fase 3 = SÍ.** Detalle: [`docs/material_profesor/AUDIT_FASE2_V2.md`](material_profesor/AUDIT_FASE2_V2.md). (La pasada de las ~03:05 fue prematura — el worker entregó 03:26–03:37 — y queda superada.)
>
> **Fase 3 (2026-07-28): HECHA.** `binary_metrics_test_v2.json` materializado con convención única (label ≥1, pred ≥0.5) + AUC; riesgo de umbrales resuelto (baseline v1 era pred≥1.0, no 0.5; comparación corregida like-for-like: F1 prom 0.8111 → **0.8657**, AUC 0.6017 → **0.6451**, v2 gana en las 4 ventanas). Sin re-entrenamiento; v1 intacto. Detalle: [`docs/material_profesor/METRICAS_BINARIAS_V2.md`](material_profesor/METRICAS_BINARIAS_V2.md).
>
> **Estado de auditoría Fase 3 (2026-07-28 ~04:15):** **PASS** — **gate Fase 4 = SÍ**. Recomputo independiente del auditor (script propio) reproduce `binary_metrics_test_v2.json` exacto (confusiones, métricas, AUC, f1_avg 0.8657) y confirma el **hallazgo del umbral v1**: el baseline v1 publicado usaba **pred≥1.0** (su texto "pred>=0.5" era etiqueta falsa hardcodeada en el script v1; recomputo @1.0 = 4/4 confusiones exactas, @0.5 = 0/4). La comparación F2 (0.6741 → 0.8657) mezclaba umbrales; la corregida like-for-like @0.5 es **F1 prom 0.8111 → 0.8657 (+0.0546)**, v2 gana las 4 ventanas en F1/acc/recall/AUC. v1 intacto (mtimes + contenido reproducible); script v1 no modificado por el worker F3. Observaciones no bloqueantes: specificity baja (ya divulgada), Youden solo informativo in-sample. Detalle: [`docs/material_profesor/AUDIT_FASE3_V2.md`](material_profesor/AUDIT_FASE3_V2.md).
>
> **Estado de auditoría Fase 4 (2026-07-28 ~04:45):** **PASS** — **gate Fase 5 = SÍ**. Recomputo independiente desde `preds_test_v2b.csv` exacto a 6 decimales (MAE prom **1.4975** vs v2 **1.4886**, F1 0.8664 vs 0.8657); `--eval-only` reproduce métricas y artefactos **byte-idénticos** (SHA256); scripts v2b y v2 compilan; v1 y v2 intactos (mtimes + contenido reproducido). Veredicto confirmado: variante v2b **DESCARTADA** (pierde en MAE test y también en val: d32 1.5467 vs r06 1.5419); **v2 simple (r06) queda como candidato a `lstm_fantasma_final`** para Fase 5. Detalle: [`docs/material_profesor/AUDIT_FASE4_V2.md`](material_profesor/AUDIT_FASE4_V2.md).
>
> **Fase 5 (2026-07-28 ~05:15): HECHA.** Modelo final = **v2 simple (r06)** por criterio fijo: primario MAE prom **1.4886** (< 1.4975 v2b, < 1.7943 v1); secundario F1 prom **0.8657** (> 0.8111 v1 like-for-like; empate práctico con v2b 0.8664 que no desempata al perder el primario). `Data/ml_out/lstm_fantasma_final/` materializado con nombres finales sin `_v2` (5 copias **byte-idénticas** SHA256); `--eval-only` contra `lstm_fantasma_final/fantasma_lstm.params` reproduce **MAE 1.4886 / RMSE 1.8359 / F1 0.8657** exactos (preds regeneradas byte-idénticas). v1, v2 y v2b intactos como historial; sin re-entrenamiento. Detalle: [`docs/material_profesor/MODELO_FINAL_V2.md`](material_profesor/MODELO_FINAL_V2.md).
>
> **Fase 6 (2026-07-28 ~05:30): HECHA.** Slides regeneradas (`PRESENTACION_FINAL_ML.pptx`/`.pdf`/`.html`, 9 slides, mismo diseño) con las cifras del modelo final — MAE prom **1.49**, F1 prom **0.87** — verificadas contra `lstm_fantasma_final/*.json`; demo con el mismo comando apuntando al params final (defaults del script, hidden 48, `perl -c` OK); guion y checklist actualizados; sin deudas internas en slides. Detalle: §Fase 6 abajo.
>
> **Fase 7 (2026-07-28 ~06:00): CERRADO.** Auditoría de cierre con verificación propia (no solo cadena): `--eval-only` sobre el params final ejecutado por el auditor → MAE 1.4886 / RMSE 1.8359 / F1 0.8657 exactos, preds **byte-idénticas** (SHA256); v1 intacto (contenido + mtimes); métricas completas presentes; slides HTML/PDF leídas completas y PPTX cruzado vía checker + script fuente (cifras == JSON finales, sin rastros v1 reales); contrato A respetado (extractor y datos congelados 27-jul); cadena F0–F4 coherente; v2b descartada documentada; sin commits no pedidos. Observaciones menores: RMSE prom 1.84 solo en guion (no en slides), 2 falsos positivos del checker `_check_fase6.py` documentados. Detalle: [`docs/material_profesor/AUDIT_CIERRE_V2.md`](material_profesor/AUDIT_CIERRE_V2.md).

---

## Decisiones congeladas antes de empezar

| Punto | Decisión |
|---|---|
| Labels y3/y5/y10/y15 | Mismo extractor + contrato **A** (no re-extraer salvo bug). |
| Datos | Mismo train abr–jun / test julio ya normalizados (`fantasma_*_norm.csv`). |
| Salida | 4 salidas numéricas + **vista binaria** (≥1 rastro) con **accuracy, precision, recall, specificity, F1, matriz de confusión**. |
| Arquitectura | Empezar **LSTM solo** (sin CNN) como pide DOCX; si sobra tiempo, **variante experimental** CNN/Dense más rica (opcional, no bloqueante). |
| Entrega | Nuevo directorio de artefactos + slides regeneradas con las **nuevas** cifras. |

---

## Fases (orden estricto)

### Fase 0 — Congelar scope y ramificar trabajo (30 min) - **HECHA (2026-07-28)**

1. Copiar/branch lógico de trabajo: **no** sobrescribir `Data/ml_out/lstm_fantasma/` v1.
2. Nuevo directorio objetivo: `Data/ml_out/lstm_fantasma_v2/` (o similar).
3. Documentar en la ruta: “v2 = mejora métricas + presentación; v1 queda como baseline”.

**Gate:** v1 intacto + espacio de trabajo v2 limpio. **CUMPLIDO:** hashes SHA256 de `Data/ml_out/lstm_fantasma/` verificados pre/post sin cambios; `Data/ml_out/lstm_fantasma_v2/` creado; nota en `docs/material_profesor/MODELO_V2_TRABAJO.md`.

### Fase 1 — Higiene de datos y reproducibilidad (0.5–1 h) - **HECHA (2026-07-28)**

1. Re-correr checks rápidos:
   - `fantasma_norm_stats.json` (86 features)
   - `fantasma_train_norm.csv` / `fantasma_test_norm.csv`
   - distribución de labels y3–y15 (masa 0…3)
2. Confirmar `seq_len=5`, seed, splits.
3. (Opcional barato) regenerar **solo** métricas binarias v1 con el script ya existente para tener baseline idéntico de comparación.

**Gate:** baseline v1 reproducible + dataset estable. **CUMPLIDO:** 86 features / 7649 train / 2391 test / masa labels 0..3 reproducida / `seq_len=5` / seed 42; baseline binario v1 regenerado en `lstm_fantasma_v2/baseline_v1_binary_metrics.json` (match exacto). Evidencia: `docs/material_profesor/CHECK_FASE0_FASE1_V2.md`.

### Fase 2 — Entrenamiento v2: combate al overfit (1–3 h de cómputo) — **HECHA (2026-07-28 ~03:35) — re-audit ~03:55: PASS_CON_RIESGOS, gate F3 SÍ**

Problema v1: smoke 1-epoch a veces mejor en test que 20 epochs → overfit.

Acciones:
1. **Early stopping** (paciencia ~3–5) o **grid pequeño** sobre:
   - `epochs ∈ {5, 10, 15, 20}`
   - `hidden ∈ {16, 32, 48}`
   - `dropout ∈ {0.1, 0.2, 0.3}`
   - `lr ∈ {0.005, 0.01}`
   - `batch ∈ {32, 64}`
2. Mantener `L2Loss` (regresión) y **evaluar siempre** en test julio.
3. Guardar **mejor checkpoint por MAE total** (o por F1 binario si decides priorizar binario).

**Salida:** `fantasma_lstm_v2.params` + `train_config_v2.json` + `metrics_test_v2.json`.

**Gate:** v2 con MAE total ≤ v1 o, si sube, F1/bin_acc claramente mejor (definir criterio antes). **Resultado re-auditoría 2026-07-28 ~03:55:** **PASS_CON_RIESGOS** — gate **cumplido** (MAE prom 1.4886 ≤ 1.7943 v1; F1 prom 0.8657 > 0.6741, like-for-like pred≥0.5), verificado con recomputo independiente desde preds (exacto a 6 decimales) + `--eval-only` byte-idéntico + v1 intacto (SHA256). **Gate Fase 3 = SÍ.** Riesgos no bloqueantes: umbrales binarios mezclados en la presentación (corregir etiquetado en Fase 3), specificity baja con pred≥0.5 (divulgada). Detalle: `docs/material_profesor/AUDIT_FASE2_V2.md`.

**Historial:** auditoría 2026-07-28 ~03:05 **FAIL** por entregable ausente (auditó estado intermedio
pre-entrega; ver `docs/material_profesor/AUDIT_FASE2_V2.md`). **Entrega worker ~03:35** cubriendo
las 6 correcciones exigidas:

- Script nuevo `scripts/train_fantasma_lstm_v2.pl` (`perl -c` OK en Fedora35; v1 intacto):
  validación en cola causal del train (15% = 1147 filas), early stop (paciencia 4, min_delta 5e-4)
  con **mejor checkpoint por MAE val**, dropout explícito pre-Dense (el dropout LSTM con 1 capa era
  inerte) y grid de 8 runs (~8 min).
- Artefactos en `Data/ml_out/lstm_fantasma_v2/`: `fantasma_lstm_v2.params`, `train_config_v2.json`
  (8 runs con historial por epoch), `metrics_test_v2.json`, `preds_test_v2.csv`, `train_v2.log`.
- Ganador **r06** (h=48, d=0.2, lr=0.005, b=32, best epoch 3, val_MAE=1.5419) por menor MAE val.
- **MAE promedio test: 1.4886 vs 1.7943 v1 (−17.0%, mejora en las 4 ventanas); F1 promedio
  0.8657 vs 0.6741** → gate cumplido por criterio primario y secundario.
- `--eval-only` verificado (reproduce métricas exactas; conserva config). Doc:
  [`docs/material_profesor/LSTM_FANTASMA_V2.md`](material_profesor/LSTM_FANTASMA_V2.md).
- Nota para Fase 3: specificity con pred≥0.5 baja (recall ~0.99); revisar umbrales.
- Nota operativa (del audit): copia Fedora35 `~/Documents/ProyectoIA/ProyectoIAAA` sigue
  desincronizada; esta entrega se hizo contra el working tree canónico (`/mnt/c/...`).

**Estado: re-auditoría Fase 2 completada (~03:55): PASS_CON_RIESGOS — autorizado a proceder a Fase 3.**

### Fase 3 — Métricas completas de exposición (0.5 h) — **HECHA (2026-07-28) — auditoría ~04:15: PASS, gate F4 SÍ**

Generar para v2, por cada ventana y3/y5/y10/y15:

- **Regresión:** MAE, RMSE
- **Binaria (umbral ≥1 rastro, pred ≥0.5):** accuracy, precision, recall (sensibilidad), specificity, F1, **matriz de confusión** TP/FP/TN/FN

Reutilizar/ajustar el script de métricas binarias (hoy Python; opcional reescribir en Perl para consistencia).

**Salida:** `binary_metrics_test_v2.json` + `preds_test_v2.csv`.

**Resultado (2026-07-28):** `Data/ml_out/lstm_fantasma_v2/binary_metrics_test_v2.json` generado con
`scripts/compute_fantasma_binary_metrics_v2.py` (sin re-entrenar; v1 y `.params` intactos).
Convención única: label `true≥1`, pred `≥0.5`; el JSON reproduce exactamente las confusiones del
bloque `binary_full` ya verificado por la auditoría F2.

- **Binaria v2 (pred≥0.5):** acc 0.7067/0.7545/0.8140/0.8316, F1 0.8121/0.8511/0.8935/0.9061
  (prom **0.8657**), AUC 0.6345/0.6469/0.6505/0.6484 (prom 0.6451); specificity 0.11–0.21 (divulgado).
- **Riesgo de umbrales resuelto:** el baseline v1 publicado usaba en realidad **pred≥1.0** (su texto
  "pred>=0.5" era etiqueta incorrecta; recomputo desde `preds_test.csv` reproduce sus confusiones
  exactas solo con ≥1.0). Comparación corregida **like-for-like @0.5**: F1 prom v1 0.8111 → v2
  **0.8657** (+0.0546); acc prom 0.7119 → 0.7767; AUC prom 0.6017 → 0.6451 — v2 gana en las 4
  ventanas en F1/acc/recall/AUC (specificity menor, divulgado). Con umbrales mezclados (v1@1.0 vs
  v2@0.5) el F1 0.6741 → 0.8657 sobreestimaba la mejora.
- **Youden:** sin preds de val disponibles (y sin re-entrenar), se reporta el óptimo in-sample en
  test solo como discusión (J≤0.27; no mejora accuracy) — se mantiene 0.5 como convención fija.
- Detalle y tablas: [`docs/material_profesor/METRICAS_BINARIAS_V2.md`](material_profesor/METRICAS_BINARIAS_V2.md).
- **Auditoría (2026-07-28 ~04:15): PASS — gate Fase 4 = SÍ.** Recomputo independiente exacto;
  hallazgo del umbral v1 confirmado (v1 usaba pred≥1.0, no 0.5); comparación corregida
  like-for-like F1 prom 0.8111 → 0.8657; v1 intacto.
  Detalle: [`docs/material_profesor/AUDIT_FASE3_V2.md`](material_profesor/AUDIT_FASE3_V2.md).

### Fase 4 — Variante arquitectónica (opcional, 1–2 h) — **HECHA (2026-07-28): Opción 4a DESCARTADA, se mantiene v2 simple — auditoría ~04:45: PASS, gate F5 SÍ**

La imagen sugiere una red más “profunda”/fully connected. Hacer **una** variante controlada, no diez:

- **Opción 4a (ejecutada):** LSTM + 1 capa Dense intermedia (relu) antes de las 4 salidas.
- **Opción 4b:** CNN 1D ligera + LSTM — **omitida** (no trivial; 4a ya respondió la pregunta arquitectónica).
- Evaluar igual que Fase 3; si no mejora claramente, **descartar** y quedarse con el v2 simple.

**Gate:** variante solo se usa si supera a v2 simple en la misma métrica elegida.

**Resultado (2026-07-28):** script nuevo `scripts/train_fantasma_lstm_v2b.pl` (`perl -c` OK en
Fedora35; v1 y v2 intactos), artefactos en `Data/ml_out/lstm_fantasma_v2b/`. Arquitectura:
LSTM(48) → Dropout(0.2) → **Dense(N, relu)** → Dense(4); receta idéntica a v2 (misma data,
seq_len=5, seed=42, L2Loss+adam, val causal 15%, early stop, selección por MAE val, test solo se
reporta). Grid de 2 runs con los hiperparámetros del ganador v2: d24 (best ep 5, val 1.5488,
test 1.5091) y d32 (best ep 4, val 1.5467, test 1.4975) → ganador **d32**.

- **MAE prom test: v2b 1.4975 vs v2 1.4886 (+0.0089, peor)**; F1 prom 0.8664 vs 0.8657
  (empate práctico). Por ventana (MAE v2 → v2b): y3 0.8161→0.8316, y5 1.1479→1.1678,
  y10 1.7474→1.7577, y15 2.2430→2.2328 (solo y15 mejora).
- **Gate NO cumplido → variante DESCARTADA.** Recomendación para Fase 5: quedarse con **v2 simple
  (r06)** como `lstm_fantasma_final`; la Dense intermedia no aporta mejora fuera de muestra.
- `--eval-only` reproduce métricas exactas; v1 y v2 intactos (comparación del log en solo lectura).
  Doc: [`docs/material_profesor/LSTM_FANTASMA_V2B.md`](material_profesor/LSTM_FANTASMA_V2B.md).
- **Auditoría (2026-07-28 ~04:45): PASS — gate Fase 5 = SÍ.** Recomputo independiente exacto
  (MAE 1.497499, F1 0.866438, 4/4 confusiones); `--eval-only` byte-idéntico (SHA256); v1 y v2
  intactos; v2b pierde también en val (d32 1.5467 vs r06 1.5419) → veredicto robusto, no ruido
  de test. **v2 simple (r06) confirmado como candidato final.**
  Detalle: [`docs/material_profesor/AUDIT_FASE4_V2.md`](material_profesor/AUDIT_FASE4_V2.md).

### Fase 5 — Selección del modelo final (criterio fijo) — **HECHA (2026-07-28): modelo final = v2 simple (r06)**

Definir **antes** de mirar números bonitos:
- Criterio primario: **menor MAE promedio** en las 4 ventanas.
- Criterio secundario (desempate o prioridad si el profe insiste en binario): **mayor F1 promedio** en y3–y15.

Elegir: `lstm_fantasma_final` = el mejor entre v1 / v2 / variante.

**Resultado (2026-07-28):** ganador **v2 simple (r06)** — MAE prom **1.4886** (v2b 1.4975, v1
1.7943) y F1 prom **0.8657** (v2b 0.8664 empate práctico, v1 0.8111 like-for-like @0.5); gana
también en val (r06 1.5419 vs d32 1.5467). Materializado en `Data/ml_out/lstm_fantasma_final/`
con nombres finales (`fantasma_lstm.params`, `metrics_test.json`, `binary_metrics_test.json`,
`preds_test.csv`, `train_config.json`): copias **byte-idénticas** (SHA256) de los artefactos v2 y
`--eval-only` sobre el params final reproduce las métricas exactas. v1/v2/v2b quedan intactos como
historial; sin re-entrenamiento. Tabla comparativa y verificación:
[`docs/material_profesor/MODELO_FINAL_V2.md`](material_profesor/MODELO_FINAL_V2.md).

### Fase 6 — Regenerar diapositivas y guion (0.5–1 h) — **HECHA (2026-07-28 ~05:30)**

1. Actualizar `PRESENTACION_FINAL_ML.pptx` (y HTML/PDF) con **solo** las cifras del modelo final.
2. Asegurar que ya existen slides de: regresión, vista binaria (accuracy/precision/recall/F1), matriz de confusión.
3. Actualizar `guia.md` y `GUION_PRESENTACION.md` con nuevas cifras y nueva demo (mismo comando, nuevo `.params`).
4. Mantener audits internos separados (no meter deudas en slides salvo pregunta del profe).

**Resultado (2026-07-28 ~05:30):**

- **Slides regeneradas** (9, mismo diseño monocromo editorial, solo número de página):
  `PRESENTACION_FINAL_ML.pptx` + `.pdf` vía `_gen_presentacion_pptx.py` / `_gen_presentacion_pdf.py`
  actualizados; `.html` actualizado in situ (sin re-correr `_strip_html_chrome.py`, que ya estaba aplicado).
  Cifras nuevas verificadas contra `lstm_fantasma_final/metrics_test.json` y `binary_metrics_test.json`:
  MAE 0.82/1.15/1.75/2.24 (prom **1.49**), RMSE 1.01/1.41/2.15/2.77, binaria acc 0.71/0.75/0.81/0.83,
  F1 0.81/0.85/0.89/0.91 (prom **0.87**), confusión TP/FP/TN/FN 1513·668·174·32 … 1939·380·46·22,
  entrenamiento h=48/dropout 0.2/early stopping, cierre con MAE prom 1.49 / F1 prom 0.87.
  Slide 5 incluye la mejora presentable: −17% MAE prom vs primera versión. Sin deudas internas en slides
  (overfit, umbral v1, specificity quedan solo en audits).
- **Demo:** mismo comando (`perl -I. scripts/demo_fantasma_predict.pl --n 8`); defaults del script
  apuntan ahora a `lstm_fantasma_final/fantasma_lstm.params` + `metrics_test.json` y `hidden 48`
  (`perl -c` OK en Fedora35). Backup eval-only documentado con `train_fantasma_lstm_v2.pl --eval-only`
  y `--out-dir /tmp/fantasma_final_eval` para no tocar el directorio final.
- **Guion y checklist** actualizados: tabla §5 con MAE/RMSE/acc/F1 + promedios, narrativa recall
  98–99% y F1 0.87, límites §7 sin las deudas ya resueltas (overfit/F1), paths a `lstm_fantasma_final/`,
  frase de emergencia F1 con la cifra nueva.
- **`guia.md`: no existe** en el árbol (ni raíz ni paquete de exposición); solo había que actualizar
  GUION + CHECKLIST, hecho.
- Pendiente para Fase 7: slides/guion alineados a artefactos ✔ (verificación textual PPTX/PDF contra JSON).

### Fase 7 — Auditor de cierre v2 — **CERRADO (2026-07-28 ~06:00)**

Checklist:
- [x] v1 no roto — **PASS**
- [x] v2 reproduce `--eval-only` — **PASS** (ejecutado por el auditor: MAE 1.4886 / RMSE 1.8359 / F1 0.8657; preds byte-idénticas SHA256)
- [x] métricas completas presentes — **PASS** (`lstm_fantasma_final/metrics_test.json` + `binary_metrics_test.json`: 4 ventanas, confusión, AUC)
- [x] slides/guion alineados a artefactos — **PASS** (HTML/PDF leídos completos; PPTX vía checker + fuente; MAE prom 1.49 / F1 prom 0.87; sin cifras v1)
- [x] contrato A respetado — **PASS** (extractor y dataset congelados desde 27-jul; sin re-extracción)

**Veredicto del auditor de cierre: CERRADO.** Detalle, evidencia y observaciones menores:
[`docs/material_profesor/AUDIT_CIERRE_V2.md`](material_profesor/AUDIT_CIERRE_V2.md).

---

## Entregables finales v2

| Artefacto | Ruta típica |
|---|---|
| Modelo final | `Data/ml_out/lstm_fantasma_final/fantasma_lstm.params` |
| Métricas regresión | `metrics_test.json` |
| Métricas binarias + confusión | `binary_metrics_test.json` |
| Predicciones | `preds_test.csv` |
| Config | `train_config.json` |
| Slides actualizadas | `docs/material_profesor/PRESENTACION_FINAL_ML.*` |
| Guía / guion actualizados | `docs/material_profesor/` + `guia.md` del paquete de exposición |

---

## Lo que NO se hace en este plan

- No cambiar a Opción B (literal Pine).
- No t-SNE / GMM / HMM (sigue paralelo).
- No re-extraer CSV completo salvo bug del extractor.

## Riesgos y mitigación

- **Overfit persiste:** early stop + menos epochs + dropout; elegir mejor checkpoint en test.
- **F1 sigue flojo en y3:** aceptar y presentar MAE como principal; mencionar binario como complemento.
- **Tiempo corto:** cortar Fase 4 (variante) y quedarse con v2 simple si ya mejora.

---

## Orden de ejecución sugerido (resumen en una línea)

`baseline v1 → early-stop/grid v2 → métricas completas → (opcional) variante → elegir final → slides nuevas → auditor cierre`.
