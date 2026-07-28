# Ruta final — Proyecto parte ML (DOCX v1.0 + oral)

## Jerarquía de fuentes (contractual)

| Prioridad | Fuente | Rol |
|:---:|---|---|
| **1** | **`Indicaciones-Proyecto-parte-final_v1.0.docx`** (25/07/2026 14:00) | **Referencia contractual #1.** Lo escribió el profesor. **Manda sobre lo oral** si hay duda. |
| **2** | Oral Lumina más reciente (**27-jul**, sesión `2d01313877a5`) | **Complementa** el DOCX (métricas, énfasis de demo, muestreo). Solo prevalece si es **más reciente** y **no contradice** el escrito. |
| **3** | Orales / apuntes del mes anteriores a 27-jul | Menos peso; contexto histórico. |
| — | Lab LSTM Unidad 5 + MXNet patches | Entorno técnico; smoke, no redefine el enunciado. |

**Rutas canónicas:**
- DOCX: `docs/material_aula_virtual/10_indicaciones_finales_2026-07-27/Indicaciones-Proyecto-parte-final_v1.0.docx`
- Audit exhaustivo DOCX:  
  **`docs/material_profesor/AUDIT_DOCX_INDICACIONES_FINAL_V1.md`**
- Audit oral Lumina (último mes):  
  **`docs/material_profesor/AUDIT_ORAL_LUMINA_IA_ULTIMO_MES.md`**
- **Cierre pipeline ML (auditor final):**  
  **`docs/material_profesor/AUDIT_PIPELINE_ML_CIERRE_FINAL.md`** → **LISTO_CON_DEUDA**
- Transcripción oral 27-jul: `docs/material_profesor/transcripcion_IA_2026-07-27_ultimas_indicaciones.txt`
- Plan visual: `docs/PLAN_SIGUIENTE_MODELOS.html`

### Complementos orales (Lumina, último mes) — mergeado 2026-07-27

Audits de referencia: [`AUDIT_DOCX_…`](material_profesor/AUDIT_DOCX_INDICACIONES_FINAL_V1.md) + [`AUDIT_ORAL_…`](material_profesor/AUDIT_ORAL_LUMINA_IA_ULTIMO_MES.md).  
Solo se incorporan aquí puntos del oral que **complementan** el DOCX sin contradecirlo.

| Peso | Fecha / fuente | Qué aporta a esta ruta |
|---|---|---|
| **Máximo** | Oral **27-jul** (`2d01313877a5`) | Muestreo por fantasmita; métricas regresión **y/o** binarias; tip. conteos **0…3**; desbalance OK (no rebalancear); `seq_len≈5` del lab; muestreo correcto ≫ slides; S/G/R no es label LSTM obligatoria |
| **Máximo (escrito)** | DOCX **25-jul** v1.0 | Spec contractual (objetivo, CSV, features 1–11, LSTM sin CNN primero, presentación) |
| **Alto** | Oral **22-jul** | Plantilla lab LSTM acústico → adaptar a CSV |
| **Alto** | Oral **20-jul** | Definición canónica del fantasmita + 4 salidas; techos 0…N por ventana → **subordinados** al tip. 0…3 del 27 |
| **Medio–alto** | Oral **23-jul** | Split abr–jun/jul; PIPs; rúbrica 20+15; cadena t-SNE→GMM→HMM **paralela** (no bloquea LSTM). Filas “cerca de liquidez” del 23 **no** mandan: el disparo canónico es el fantasmita |
| **Alto (features)** | Orales **21 / 14-jul** | AVWAP auto: ancla a pivote consolidado **y** al fantasmita en movimiento (≤2 auto) |

**Evoluciones a no reabrir como conflicto:**
- Techos label 20-jul (y3∈0…3 … y15∈0…15) vs tip. **0…3** del 27 → implementar conteo real; reportar masa en 0…3.
- Filas “cerca de liquidez” (23) vs filas por **aparición/reubicación del fantasma** (20/25/27) → disparo = fantasma; proximidad = features.
- P(sweep/grab/run) vía GMM (23) vs LSTM de conteos (20–27 + DOCX) → LSTM es el entregable; GMM/HMM si alcanza.
- HLD app ya cerrado en **4h/D**; features del modelo pueden incluir **W** vía niveles (DOCX) sin reabrir HLD de la GUI.

---

## Cierre pipeline (auditor final, 2026-07-27)

**Veredicto global:** **LISTO_CON_DEUDA**

| Campo | Valor |
|---|---|
| Entregable DOCX (extractor + LSTM + eval julio + demo) | **Listo** |
| Paso 5 t-SNE → GMM → HMM | **No hecho** — paralelo oral 23; **no** está en el DOCX; **no** inventar en oral |
| Audit formal | [`docs/material_profesor/AUDIT_PIPELINE_ML_CIERRE_FINAL.md`](material_profesor/AUDIT_PIPELINE_ML_CIERRE_FINAL.md) |
| Smoke demo (Fedora35) | `perl -I. scripts/demo_fantasma_predict.pl --n 3` → **PASS** (~1.2 s) |

Deudas aceptadas (no bloquean oral): Ghosts Opción A (≠ literal Pine), F1 ausente, overfit probable, `bin_acc` y3≈0.48, test extract pre-fix AVWAP.  
Día-D: guion [`GUION_PRESENTACION_FINAL.md`](material_profesor/GUION_PRESENTACION_FINAL.md) + checklist [`CHECKLIST_DEMO_FINAL.md`](material_profesor/CHECKLIST_DEMO_FINAL.md).

---

## Estado actual (2026-07-27)

| Paso | Estado |
|---|---|
| **Paso 0** — Patches MXNet + smoke LSTM acústico | **HECHO** |
| **Paso 1** — Preparar datos / CSV train–test | **HECHO_CON_DEUDA** (cierre: [`AUDIT_PASO1_CIERRE.md`](material_profesor/AUDIT_PASO1_CIERRE.md); CSV **PASS**; Ghosts **ALINEADO_PARCIAL**; contrato labels **Opción A**) |
| **Paso 2** — Extractor features + labels | **HECHO_CON_DEUDA** (cierre: [`AUDIT_PASO2_CIERRE.md`](material_profesor/AUDIT_PASO2_CIERRE.md); **PASS_CON_RIESGOS**; gate Paso 3 **SÍ**) |
| **Paso 3** — Full extract + normalización | **HECHO_CON_DEUDA** (cierre: [`AUDIT_PASO3_CIERRE.md`](material_profesor/AUDIT_PASO3_CIERRE.md); **PASS_CON_RIESGOS**; gate LSTM **SÍ**; train 7649 / test 2391; z-score 86 feats) |
| **Paso 4** — Entrenar LSTM (sin CNN) | **HECHO_CON_DEUDA** (cierre: [`AUDIT_PASO4_CIERRE.md`](material_profesor/AUDIT_PASO4_CIERRE.md); **PASS_CON_RIESGOS**; gate demo **SÍ**) |
| **Paso 5** — t-SNE → GMM → HMM | Pendiente / paralelo (no bloquea demo) |
| **Paso 6** — Presentación ≤10 min + demo | **HECHO_CON_DEUDA** (guion + checklist + script demo; gate desde Paso 4; **auditor final:** LISTO_CON_DEUDA) |

Evidencia Paso 0 (Fedora35, usuario `bryan`): raíz MXNet `/usr/local/share/perl5/5.34/`; 13 `.pm` aplicados (`chmod 644`); smoke `09_02_02-Concise_Implementation_of_LSTM.pl` OK — Accuracy **97.28%**, AUC **0.99**.

**Datasets ML (fuente profe + copia en `Data/`, verificados 2026-07-27):**
| Archivo | Uso | Path runtime | Rango (min→max) | Filas datos |
|---|---|---|---|---:|
| `2026_Abril-Junio.csv` | **TRAIN** | `Data/2026_Abril-Junio.csv` | 2026-04-01T00:00:00-05:00 → 2026-06-30T23:59:00-05:00 | 88 736 |
| `2026_07_24.csv` | **TEST** | `Data/2026_07_24.csv` | 2026-07-01T00:00:00-05:00 → 2026-07-24T15:59:00-05:00 | 24 179 |

Formato OHLCV 1m (`time,open,high,low,close,Volume`), UTC-5. Origen: `docs/material_aula_virtual/10_indicaciones_finales_2026-07-27/` (copia, no move).
**Nota:** `Data/2026_07_20.csv` sigue siendo el default de la GUI; no se sobrescribe ni se cambia el cableado de la app a abr–jun.

---

## Qué exige el DOCX (completo)

Checklist contractual íntegra en  
**[`AUDIT_DOCX_INDICACIONES_FINAL_V1.md`](material_profesor/AUDIT_DOCX_INDICACIONES_FINAL_V1.md)**.  
Resumen operativo (nada de esto es “opcional” salvo donde el propio DOCX lo marca):

### Objetivo y labels
- Predecir **cuántos rastros** dejará el fantasma en ventanas **3 / 5 / 10 / 15** min.
- Referencia: **vela siguiente a cada aparición**; cada **reubicación** = nueva estimación en las 4 ventanas.
- Ejemplo del doc: movimientos **hacia afuera del rango actual de precio**.
- Labels vía Replay: etiquetas **`1`** del indicador **idéntico** a `Ghosts_in_swings.txt`.
- Comparar predicciones vs **etiquetado automático**.

### Datos
- Train: `2026_Abril-Junio.csv` (abr–jun).
- Test: `2026_07_24.csv` (1–24 jul).
- Evaluar sobre test.

### Extractor (Replay 1m)
- Estructura **previa** a la vela actual.
- Distancia del **promedio de precio** de la vela del fantasma → niveles de liquidez **más cercanos**, en **PIP**.
- **≥3 TF:** 1m (pequeña), **10m** (mediana), **1h** (grande).
- Features 1–11:
  1. OB (nivel + espesor)  
  2. FVG (nivel + rango)  
  3. Fib anclado a trama/impulso consolidado del **ZZ externo**  
  4. Bandas **VWAP anclado auto** al penúltimo pivot (código Unidad 5); oral 20–21: también anclar/acompañar al **fantasmita** en movimiento (≤2 auto)  
  5. **POC / VAH / VAL** (perfil vol. anclado a ZZ ext; oral 27: volumen horizontal = interés institucional)  
  6. S/R **4h / diario / semanal** (DOCX; HLD de app ya cerrado en 4h/D — no reabrir GUI)  
  7. BOS / CHoCH  
  8. EQH / EQL  
  9. Sweep / Grab / Run (**solo si** bien implementados y justificados; **feature** de tablota, **no** label LSTM obligatoria)  
  10. Supply / Demand DIY  
  11. Canal / Trendline (**solo si** 3 mín. HL/LL alineados ≥2h, máx. HH/LH dentro, ATR bajo)
- Extra: ATR(1m), volumen 1m, EMA(9) volumen 1m, etc.
- Metadata fecha/hora/minuto: **no entrenar**; sí validar en test.
- **Optimizar** el extractor desde el principio.

### ML y entrega oral
- Normalizar/estandarizar + **guardar parámetros** para test.
- Entrenar + **guardar** modelo; **cargar** en test; comparar vs labels auto; evaluar.
- LSTM numérico; **CNN opcional** — sugerencia: **sin CNN primero**.
- Presentación grupal **≤10 min**: extractor + features + evaluación + **demo de predicciones** (modelo + tabla ya extraída).

### Lo que el DOCX no fija (complemento oral ya mergeado)
- **Métricas (oral 27):** regresión sobre conteos 3/5/10/15 **y/o** clasificación binarizando aparece/no por ventana (precisión, recall, F1, sensibilidad, etc.). Alternativa de primer nivel, no decorativa.
- Cadena t-SNE → GMM → HMM → no está en el escrito; oral 23 la pide en paralelo — **no bloquea** entrega LSTM.
- Definición exacta de “promedio de precio” y tamaño PIP NQ → documentar en implementación.

---

## Objetivo del modelo (una frase)

Predecir, **a partir de la vela siguiente a cada aparición/reubicación del fantasma**, cuántos **rastros (“1”)** dejará el fantasma en ventanas futuras de **3, 5, 10 y 15 minutos** (4 salidas numéricas; en el ejemplo del DOCX = movimientos fuera del rango actual).

Cada nueva reubicación del fantasma = **nueva muestra**.

---

## Qué ya tenemos en la app (aprovechable)

| Requisito del DOCX | Estado en ProyectoIAAA |
|---|---|
| Replay 1m causal | Sí |
| Fantasma + rastro “1” (PivotPointsHL / Ghosts_in_swings) | **ALINEADO_PARCIAL** — audit Ghosts + cierre Paso 1: contrato **Opción A** (Perl/comentario Josafa); deuda D2/D3 opcional |
| OB, FVG, Fib ZZ ext, AVWAP auto, AVP/POC/VAH/VAL, HLD 4h/D/W, BOS/CHoCH, EQH/EQL (SMC), Sweep/Grab/Run, DIY S/D, Canal/Trendline auto | Sí (calidad variable; 9 y 11 solo si cumplen el condicional del DOCX) |
| Extractor batch headless de tablota | **HECHO_CON_DEUDA** — `Market/ML/ExtractFantasmaDataset.pm` + CLI; cierre [`AUDIT_PASO2_CIERRE.md`](material_profesor/AUDIT_PASO2_CIERRE.md); doc [`EXTRACTOR_FANTASMA.md`](material_profesor/EXTRACTOR_FANTASMA.md) |
| CSV train/test del profe cargados en `Data/` | **HECHO** (2026-07-27; train 88 736 / test 24 179; GUI default intacto) |
| Patches MXNet + smoke LSTM acústico (Fedora35) | **HECHO** (2026-07-27) |

---

## Roadmap accionable (orden estricto)

### Paso 0 — Actualizar patches MXNet en Fedora35 y validar con LSTM acústico — **HECHO (2026-07-27)**

Instrucción del profe (Unidad 5): actualizar **todos** los `.pm` de `MXNet_patches` y probar con el script LSTM de data acústica. **Solo** como smoke test de que el entorno parcheado funciona; no hace falta un modelo bueno.

**Resultado en esta máquina:**
- Distro: `wsl -d Fedora35`; usuario real **`bryan`** (no existe `estudiante` → se usó `chown bryan`).
- Raíz MXNet: `/usr/local/share/perl5/5.34/` (`AI/MXNet.pm`; `sml.pm` también en `…/x86_64-linux-thread-multi/` y `…/5.34/`).
- 13 `.pm` de patches aplicados + permisos `644`.
- Smoke LSTM OK: Accuracy 97.28%, AUC 0.99 (log `/tmp/lstm_smoke_acustica.log`; el proceso puede seguir vivo por `show_plot`).
- Symlink: `LSTM/data/VAD_data` → `../VAD_data`.

**Material (ya archivado en el repo):**
| Zip (Downloads) | Destino en el repo |
|---|---|
| `MXNet_patches (1).zip` | `docs/material_aula_virtual/09_mxnet_patches/` (`AI/MXNet/**`, `sml.pm`) |
| `LSTM.zip` | `docs/material_aula_virtual/09_mxnet_patches/lstm_prueba_acustica/` |

**Archivos `.pm` a aplicar (todos):**
- `sml.pm`
- `AI/MXNet/Base.pm`, `LinAlg.pm`, `NDArray.pm`, `NS.pm`, `Types.pm`
- `AI/MXNet/NDArray/Base.pm`, `Slice.pm`
- `AI/MXNet/Gluon/Block.pm`, `Loss.pm`, `Parameter.pm`
- `AI/MXNet/Gluon/Data/Loader.pm`
- `AI/MXNet/Gluon/NN/BasicLayers.pm`

(El zip también trae `python/mxnet/gluon/block.py` de referencia; el runtime del curso es Perl.)

**Dónde viven en Fedora35 (localizar, no adivinar a ciegas):**

```bash
# Ruta real del módulo instalado (elige UNA y úsala como raíz):
perldoc -l AI::MXNet
# o:
perl -MAI::MXNet -e 'print $INC{"AI/MXNet.pm"}, "\n"'
```

**Ruta confirmada en esta Fedora35 (2026-07-27):**

| Qué | Ruta real |
|---|---|
| Árbol `AI/MXNet/*.pm` | `/usr/local/share/perl5/5.34/AI/MXNet/` |
| `sml.pm` | `/usr/local/share/perl5/5.34/` (y copia bajo `…/x86_64-linux-thread-multi/` si aplica) |

(Placeholders típicos del aula / otras máquinas: `/usr/share/perl5/vendor_perl/…` o `site_perl` — siempre confirmar con `perldoc -l AI::MXNet`.)

Copiar cada `.pm` del zip **sobre** el archivo homólogo en esa raíz (respetando la jerarquía `AI/MXNet/...`).

**Permisos, por cada archivo tocado:**

El profe indica `chown estudiante`; en **esta** máquina el usuario WSL es `bryan` (no existe `estudiante`). Usar el usuario real del sistema:

```bash
sudo chown bryan camino.pm   # en el aula del profe: estudiante
chmod 644 camino.pm
```

Ejemplo (ruta real de esta máquina):

```bash
sudo chown bryan /usr/local/share/perl5/5.34/AI/MXNet/Base.pm
chmod 644 /usr/local/share/perl5/5.34/AI/MXNet/Base.pm
# …repetir para TODOS los .pm del zip
```

**Smoke test (solo validar patches):**

```bash
cd docs/material_aula_virtual/09_mxnet_patches/lstm_prueba_acustica/LSTM
# (o la copia del script en el home del estudiante en Fedora)
perl 09_02_02-Concise_Implementation_of_LSTM.pl
```

Data acústica: subcarpeta `VAD_data/` junto al `.pl` (o symlink `LSTM/data/VAD_data` → `../VAD_data`). Criterio de éxito: el script **corre sin error de MXNet/patches** (carga módulos, entrená o al menos arranca el loop). No se exige calidad del modelo VAD. **Cumplido** (97.28% / AUC 0.99).

**Solo después de eso** → continuar con datos CSV, extractor headless, etc. → **siguiente: Paso 1**.

### Paso 1 — Preparar datos (~30 min) — **HECHO_CON_DEUDA** (cierre 2026-07-27)
1. [x] Copiar/usar los CSV del profe en `Data/` (no mezclar con otros rangos; GUI default `Data/2026_07_20.csv` intacto):
   - Train: `Data/2026_Abril-Junio.csv` (88 736 filas; 2026-04-01 → 2026-06-30)
   - Test: `Data/2026_07_24.csv` (24 179 filas; 2026-07-01 → 2026-07-24T15:59-05:00)
   - Header OK: `time,open,high,low,close,Volume`
2. [x] Verificar Ghosts vs `PivotPointsHL` (**requisito DOCX: idéntico**).  
   → **Audit:** **ALINEADO_PARCIAL** —  
   [`AUDIT_GHOSTS_VS_PIVOTPOINTS_HL.md`](material_profesor/AUDIT_GHOSTS_VS_PIVOTPOINTS_HL.md).  
   → **Cierre Paso 1:** [`AUDIT_PASO1_CIERRE.md`](material_profesor/AUDIT_PASO1_CIERRE.md) → **PASS_CON_RIESGOS**.  
   → **Contrato labels congelado: Opción A** (rastro solo si la punta se mueve; `"1"` en punta previa = Perl actual).  
   → Deuda opcional (no bloquea extractor bajo A): D2 ventana `px1` / D3 desempate (Paso 1.5 si se quiere punta más cercana a TV).  
   → Opción B (literal Pine + paints duplicados) **desaconsejada** sin validación del profe.

### Paso 2 — Extractor de features (bloque crítico, 1–2 días) — **HECHO_CON_DEUDA** (cierre 2026-07-27)

**Cierre:** [`AUDIT_PASO2_CIERRE.md`](material_profesor/AUDIT_PASO2_CIERRE.md) → **PASS_CON_RIESGOS**; gate full extract + normalización **SÍ**.

**Implementado:**
- Módulo `Market/ML/ExtractFantasmaDataset.pm` + CLI `scripts/extract_fantasma_dataset.pl`
- Disparo Opción A + labels `y3/y5/y10/y15` + features multi-TF (`1m`/`10m`/`1h`) pack `full|core`
- Smoke: `--smoke` (1ª semana abril); test `t/50-extract-fantasma-dataset.t` (**PASS**)
- Doc: [`docs/material_profesor/EXTRACTOR_FANTASMA.md`](material_profesor/EXTRACTOR_FANTASMA.md)
- `MarketData` agrega TF **`10m`** (DOCX mediana)
- Fix auditoría: `--max-samples` ya no trunca ventanas de label (feed +15 barras; drop fin de serie incompleto)

Script **headless** (sin Tk) que, en Replay 1m sobre todo el CSV:

**Disparo de muestra:** aparición o reubicación del fantasma (DOCX + orales 20/27).  
**Nota anti-confusión:** el oral 23 hablaba de filas “cerca de liquidez”; eso **no** redefine el muestreo. Proximidad a niveles entra como **features**, no como filtro exclusivo de filas.

**En esa vela (+ estructura previa, causal):**
Para **≥3 TF** (DOCX: 1m, **10m**, 1h) medir **distancia en PIPs** del precio medio de la vela del fantasma a los niveles más cercanos de:

1. Order Block (nivel + espesor)  
2. FVG (nivel + rango)  
3. Fib anclado a impulso ZZ externo consolidado  
4. Bandas AVWAP auto (penúltimo pivot / código Unidad 5; oral: también ancla al **fantasmita**)  
5. POC / VAH / VAL (AVP anclado a ZZ ext)  
6. Soportes/resistencias **4h / D / W** (features; no reabrir HLD-app 4h/D)  
7. BOS / CHoCH  
8. EQH / EQL  
9. Sweep / Grab / Run (**feature** condicional; **no** label LSTM obligatoria; si no justificables, omitir/nulo)  
10. Supply / Demand DIY  
11. Canal / Trendline (**solo si cumple regla 3 toques ≥2h + máximos dentro + ATR bajo**)

**Columnas extra:** ATR(1m), volumen 1m, EMA(9) volumen 1m, etc.

**Metadata (NO entrenar):** fecha/hora/minuto — solo para validar en test.

**Optimizar el extractor desde el principio** (DOCX): no recalcular todo el universo por vela si se puede incremental.

### Paso 3 — Full extract train+test + normalización — **HECHO_CON_DEUDA** (cierre 2026-07-27)

**Cierre:** [`AUDIT_PASO3_CIERRE.md`](material_profesor/AUDIT_PASO3_CIERRE.md) → **PASS_CON_RIESGOS**; gate Paso 4 LSTM **SÍ**.

Labels `y3/y5/y10/y15` salen del extractor Paso 2 (Opción A). Este paso = **full train+test** + **normalización train-only**.

**Resultados full (Fedora35, pack `full`, sin `--max-samples`):**

| Split | CSV fuente | Out | Barras | Muestras | Tiempo |
|---|---|---|---:|---:|---:|
| Train | `Data/2026_Abril-Junio.csv` | `Data/ml_out/fantasma_train_abril_junio.csv` | 88 736 | **7649** | ~2285 s (~38 min, post-fix AVWAP) |
| Test | `Data/2026_07_24.csv` | `Data/ml_out/fantasma_test_julio.csv` | 24 179 | **2391** | ~3075 s (~51 min, pre-fix) |

Masa labels train (tip oral 0…3): y3 100%, y5 89.6%, y10 72.0%, y15 62.5%.  
Logs: `Data/ml_out/fantasma_train_abril_junio.log`, `fantasma_test_julio.log`.  
Launcher/monitor: `scripts/run_fantasma_full_extracts.sh`, `monitor_fantasma_extracts.sh`, `finish_fantasma_paso3.sh`.

**Fix de rendimiento (mismo día):** `AnchoredVWAP::set_anchor` ya no precarga `0..size()-1` del MD (O(N) por ancla; en extract el MD ya tiene todo el CSV). Bench 5k: **124 s → 12 s**. Audit: `get_point(i)` = VWAP acumulativo `anchor..i` → **sin fuga material** en features; regenerar test extract = **opcional**. Tests: `t/43-avwap-auto`, `t/41-anchored-vwap`, `t/50-extract` **PASS**.

**Normalización:**
- Módulo `Market/ML/NormalizeFantasmaDataset.pm` + CLI `scripts/normalize_fantasma_dataset.pl`
- Doc: [`NORMALIZACION_FANTASMA.md`](material_profesor/NORMALIZACION_FANTASMA.md)
- Salidas: `fantasma_train_norm.csv` (12M), `fantasma_test_norm.csv` (3.8M), `fantasma_norm_stats.json`
- **86 features** z-score fit solo train; excluye `meta_*`, `y*`, `sgr_kind_*`, `ref_mid_pips`

### Paso 4 — Entrenar LSTM (lab → proyecto) — **HECHO_CON_DEUDA** (cierre 2026-07-27)

**Cierre:** [`AUDIT_PASO4_CIERRE.md`](material_profesor/AUDIT_PASO4_CIERRE.md) → **PASS_CON_RIESGOS**; **gate demo/presentación (Paso 6) SÍ**.

**Doc:** [`LSTM_FANTASMA.md`](material_profesor/LSTM_FANTASMA.md).  
**Código:** `scripts/train_fantasma_lstm.pl` + `Market/ML/FantasmaLSTMData.pm`.  
**Salidas:** `Data/ml_out/lstm_fantasma/` (`fantasma_lstm.params`, `metrics_test.json`, `preds_test.csv`, `train_config.json`, `train.log`).

**Corrida v1 (Fedora35, epochs=20, seq_len=5, hidden=32, batch=64):** train L2 1.87→1.10 (~156 s). Test julio (2387 secuencias):

| Target | MAE | RMSE | bin_acc (≥1) |
|---|---:|---:|---:|
| y3 | 0.91 | 1.14 | 0.48 |
| y5 | 1.31 | 1.67 | 0.57 |
| y10 | 2.15 | 2.75 | 0.68 |
| y15 | 2.81 | 3.58 | 0.72 |

Spot-check audit: shapes `7645×5×86` / `2387×5×86` → 4 salidas; sin `time`/`meta_*` en X; `--eval-only` carga modelo OK.  
Deuda (no bloquea): overfit probable (smoke 1-epoch mejor en test), bin_acc y3 débil, sin F1 — ver audit.

1. [x] Entorno MXNet validado en **Paso 0**.  
2. [x] I/O sobre `*_norm.csv` + 86 features de stats (**sin CNN**).  
3. [x] `seq_len=5` (lab/oral); ventanas sobre filas de muestras en orden CSV.  
4. [x] Regresión MSE multi-salida (`L2Loss` → `y3/y5/y10/y15`).  
5. [x] Guardar modelo + evaluar test julio (MAE/RMSE + bin_acc umbral ≥1).  
6. [x] Audit formal de cierre Paso 4 → [`AUDIT_PASO4_CIERRE.md`](material_profesor/AUDIT_PASO4_CIERRE.md).  
7. **No** rebalancear clases (oral 27).

**Comando:**

```bash
cd /mnt/c/Users/bryan/ia/proyecto_iaaa/Proyecto/ProyectoIAAA
perl -I. scripts/train_fantasma_lstm.pl --epochs 20 --out-dir Data/ml_out/lstm_fantasma
```

Solo cargar (demo):

```bash
perl -I. scripts/train_fantasma_lstm.pl --eval-only \
  --model Data/ml_out/lstm_fantasma/fantasma_lstm.params \
  --out-dir Data/ml_out/lstm_fantasma
```

**Métricas:**
- **DOCX:** evaluar + comparar vs etiquetado automático (sin lista fija de scores).  
- **Oral 27-jul (complemento):** (A) **regresión** sobre conteos 3/5/10/15; **y/o** (B) **clasificación** binarizando aparece/no por ventana → precisión, recall, F1, sensibilidad, etc.  
- **v1 implementada:** (A) MAE/RMSE por ventana + (B) accuracy binaria simple (`>=1`); F1/recall/precisión detallados = deuda opcional (no bloquea demo).

### Paso 5 — Cadena t-SNE → GMM → HMM (si alcanza tiempo / pizarra)
**No está en el DOCX v1.0.** Oral 23 la pide (GMM P(S)+P(G)+P(R)=1, umbral ~85%, HMM int/ext). Queda **paralela / si alcanza**; **no bloquea** la entrega LSTM + extractor del escrito.

### Paso 6 — Presentación (≤10 min, grupal) — **HECHO_CON_DEUDA** (prep 2026-07-27)

**Material oral (sin PowerPoint obligatorio):**
- Guion ≤10 min + tiempos + comandos: [`docs/material_profesor/GUION_PRESENTACION_FINAL.md`](material_profesor/GUION_PRESENTACION_FINAL.md)
- Checklist proyector: [`docs/material_profesor/CHECKLIST_DEMO_FINAL.md`](material_profesor/CHECKLIST_DEMO_FINAL.md)
- Script demo predicción (carga `.params` + N muestras true vs pred): `scripts/demo_fantasma_predict.pl`

Mostrar (DOCX):
1. Extractor de características (cómo/cuando dispara el fantasma).  
2. Features usadas (lista + ejemplo de fila).  
3. Resultados de evaluación en julio.  
4. **Demo en vivo al final:** cargar modelo + tabla ya extraída y mostrar predicciones.

```bash
cd /mnt/c/Users/bryan/ia/proyecto_iaaa/Proyecto/ProyectoIAAA
perl -I. scripts/demo_fantasma_predict.pl --n 8
# backup carga modelo:
perl -I. scripts/train_fantasma_lstm.pl --eval-only \
  --model Data/ml_out/lstm_fantasma/fantasma_lstm.params \
  --out-dir Data/ml_out/lstm_fantasma
```

Complemento oral (no sustituye al DOCX): **muestreo correcto > slides bonitas**.  
Deuda post-demo (no bloquea oral): F1/P/R, early-stop overfit, Paso 5 t-SNE/GMM/HMM.  
**Cierre pipeline:** [`AUDIT_PIPELINE_ML_CIERRE_FINAL.md`](material_profesor/AUDIT_PIPELINE_ML_CIERRE_FINAL.md) → **LISTO_CON_DEUDA**.

---

## Qué NO hacer ahora
- Reabrir polish visual / FSM liquidez “perfecta”.  
- Una fila por cada minuto (ni filtrar filas solo por “cerca de liquidez” del oral 23).  
- Meter `time` / índice de evento en la matriz de entrenamiento.  
- Rebalancear artificialmente clases / usar imbalance como coartada.  
- Inventar algoritmos nuevos: el valor está en **sacar data del lugar correcto** (énfasis oral; alineado con el DOCX).  
- Empezar con CNN: primero LSTM simple como el lab (**sugerencia explícita del DOCX**).  
- Exigir Sweep/Grab/Run como **label** LSTM (pueden ser feature; tipo se conoce con futuro).  
- Tratar el oral como si anulara el DOCX cuando chocan.

---

## Checklist mínima para “terminar lo solicitado”

- [x] **Paso 0:** patches MXNet aplicados en Fedora35 + smoke LSTM acústico OK (2026-07-27; Acc 97.28% / AUC 0.99)  
- [x] **Paso 1 (CSV):** train/test en `Data/2026_Abril-Junio.csv` + `Data/2026_07_24.csv` (header OHLCV OK; GUI default sin cambiar)
- [x] Fantasma + rastro “1” auditado vs `Ghosts_in_swings.txt` → **ALINEADO_PARCIAL**; cierre Paso 1 **PASS_CON_RIESGOS** / contrato **Opción A** ([`AUDIT_PASO1_CIERRE.md`](material_profesor/AUDIT_PASO1_CIERRE.md); deuda D2/D3 opcional)  
- [x] Extractor Replay 1m → tablota features (3 TF × niveles 1–11) en PIPs — **HECHO_CON_DEUDA** ([`AUDIT_PASO2_CIERRE.md`](material_profesor/AUDIT_PASO2_CIERRE.md); full CSV = Paso 3)  
- [x] Labels y3/y5/y10/y15 (etiquetado automático) — **en el mismo extractor** (contrato A; full run OK)  
- [x] Full extract train+test (`fantasma_train_abril_junio.csv` 7649 / `fantasma_test_julio.csv` 2391) — cierre [`AUDIT_PASO3_CIERRE.md`](material_profesor/AUDIT_PASO3_CIERRE.md)  
- [x] Normalización train-only persistida (`*_norm.csv` + `fantasma_norm_stats.json`; 86 feats)  
- [x] LSTM entrenado + guardado (sin CNN primero) — cierre [`AUDIT_PASO4_CIERRE.md`](material_profesor/AUDIT_PASO4_CIERRE.md) **PASS_CON_RIESGOS**; doc [`LSTM_FANTASMA.md`](material_profesor/LSTM_FANTASMA.md)  
- [x] Evaluación en julio + comparación vs labels auto (MAE/RMSE + bin_acc; ver `metrics_test.json`; `--eval-only` OK)  
- [x] Presentación 10 min preparada: guion + checklist + `demo_fantasma_predict.pl` (muestreo correcto ≫ slides) — oral pendiente de ejecutar en aula  
- [x] **Auditor final pipeline** → [`AUDIT_PIPELINE_ML_CIERRE_FINAL.md`](material_profesor/AUDIT_PIPELINE_ML_CIERRE_FINAL.md) — veredicto **LISTO_CON_DEUDA** (smoke demo `--n 3` PASS)

- [x] Merge oral Lumina → esta ruta (2026-07-27); audits DOCX + oral enlazados  

Checklist DOCX: `docs/material_profesor/AUDIT_DOCX_INDICACIONES_FINAL_V1.md`.  
Checklist oral: `docs/material_profesor/AUDIT_ORAL_LUMINA_IA_ULTIMO_MES.md`.

---

## Próximo paso inmediato

**Pipeline 0–4 + prep Paso 6 + auditor final cerrados.** Veredicto: **LISTO_CON_DEUDA** ([`AUDIT_PIPELINE_ML_CIERRE_FINAL.md`](material_profesor/AUDIT_PIPELINE_ML_CIERRE_FINAL.md)).

1. [x] CSV train/test en `Data/`.
2. [x] Ghosts Opción A; extractor + `t/50` PASS.
3. [x] Full extract: train **7649** / test **2391** filas → `Data/ml_out/fantasma_{train_abril_junio,test_julio}.csv`.
4. [x] Normalización z-score train-only → `fantasma_{train,test}_norm.csv` + `fantasma_norm_stats.json` (86 features).
5. [x] Fix AVWAP (`set_anchor` sin preload `size()`); `t/41`/`t/43`/`t/50` PASS; regen test opcional.
6. [x] LSTM: entrenado + guardado + eval julio + `--eval-only` OK (`Data/ml_out/lstm_fantasma/`).
7. [x] **Paso 6 prep:** guion [`GUION_PRESENTACION_FINAL.md`](material_profesor/GUION_PRESENTACION_FINAL.md) + checklist [`CHECKLIST_DEMO_FINAL.md`](material_profesor/CHECKLIST_DEMO_FINAL.md) + `scripts/demo_fantasma_predict.pl`.
8. [x] Auditor final de cierre de pipeline → **LISTO_CON_DEUDA**.
9. **Ahora:** ejecutar oral en aula (día-D: smoke `--n 3` + demo `--n 8`). Paso 5 (t-SNE/GMM/HMM) solo si alcanza — **no** afirmarlo como hecho.

---

## Actualizacion 2026-07-28 - trabajo v2 (reentrenamiento)

- Plan: `docs/PLAN_REENTRENAMIENTO_MODELO_V2.md`. Contrato de labels: **Opcion A** (sin cambios; no se re-extrae).
- **Fase 0 HECHA:** baseline v1 (`Data/ml_out/lstm_fantasma/`) congelado e **intacto** (hashes SHA256 verificados pre/post); workspace `Data/ml_out/lstm_fantasma_v2/` creado.
- **Fase 1 HECHA:** higiene de datos verificada (86 features, train 7649 / test 2391 filas, masa labels 0..3 reproducida, `seq_len=5`, seed 42); baseline binario v1 regenerado en `Data/ml_out/lstm_fantasma_v2/baseline_v1_binary_metrics.json` (**match exacto** con v1).
- Evidencia: [`MODELO_V2_TRABAJO.md`](material_profesor/MODELO_V2_TRABAJO.md) + [`CHECK_FASE0_FASE1_V2.md`](material_profesor/CHECK_FASE0_FASE1_V2.md).
- Siguiente: **Fase 2** - entrenamiento v2 (early stopping / grid pequeno) en Fedora35; v1 queda como baseline de comparacion.