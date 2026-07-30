# Auditoría — Calidad final para entrega Unidad 5 (módulo predictivo)

**Fecha:** 2026-07-28
**Auditor:** independiente (post-limpieza, sin commits, sin re-entrenamiento).
**Encargo:** confirmar que código + docs candidatas a ir en el zip de Unidad 5 (pedido del profe,
audio post-oral: `TRANSCRIPCION_PROFE_2026-07-28_POST_ORAL.md`) están presentables.
**Referencia previa:** `AUDIT_LIMPIEZA_COMENTARIOS_ML.md` (PASS, 2026-07-28, 11 archivos).

---

## 1. Código del pipeline — ¿presentable?

### 1.1 Ya auditado (PASS previo, no se repite el detalle)

`AUDIT_LIMPIEZA_COMENTARIOS_ML.md` cubrió y dio **PASS**: `Market/ML/ExtractFantasmaDataset.pm`,
`Market/ML/FantasmaLSTMData.pm`, `Market/ChartEngine.pm` (no va al zip), `scripts/demo_fantasma_predict.pl`,
`scripts/extract_fantasma_dataset.pl`, `scripts/normalize_fantasma_dataset.pl`,
`scripts/train_fantasma_lstm.pl` (v1, no va al zip), `scripts/train_fantasma_lstm_v2b.pl` (descartado,
no va al zip), `scripts/finish_fantasma_paso3.sh` y `scripts/run_fantasma_full_extracts.sh` (operativos,
no van al zip). Sintaxis 11/11 OK, smoke demo OK, 0 restos de tono IA/proceso reales.

### 1.2 Verificación adicional de esta pasada (archivos que el audit previo NO cubrió)

El script que efectivamente entrenó el **modelo final** (`train_fantasma_lstm_v2.pl`) y el módulo de
normalización no estaban en el alcance del audit anterior. Se revisaron ahora línea por línea:

| Archivo | Va al zip | Hallazgo |
|---|---|---|
| `scripts/train_fantasma_lstm_v2.pl` | **Sí** (es el script del modelo final) | Comentarios de una línea, en español, sin banners `====`/`----` en comentarios (los `'=' x 100` que imprime son salida de consola, no comentarios). Sin tono IA, sin refs a "task/spec 00xx", sin "NO TOCAR". **PASS.** |
| `Market/ML/NormalizeFantasmaDataset.pm` | Sí | Mismo estilo limpio; comentarios cortos junto a reglas de negocio (exclusión `sgr_kind_*`, `ref_mid_pips`). **PASS.** |
| `scripts/compute_fantasma_binary_metrics_v2.py` | Sí | Único archivo con docstring/comentarios en **inglés** (resto del repo es español). No es tono IA ni narrativa de proceso — es documentación técnica normal (convención de umbral, definición de AUC/Youden). **No bloqueante**, pero si se quiere homogeneidad de idioma en el zip, es el único candidato a traducir (opcional, ver §5). |
| `scripts/demo_fantasma_predict.pl` | Sí | Recontado en esta pasada: consistente con el PASS previo. |
| `scripts/monitor_fantasma_extracts.sh`, `scripts/ensure_train_and_finish.sh` | **No** (no van al zip) | Scripts de operación puntual (PIDs, `/tmp`, rutas de esta máquina); no aportan a la guía y no son parte del contrato "comandos/features/detalles técnicos". Revisados solo para clasificar, sin objeciones de estilo. |

### 1.3 Sintaxis (repetida rápido para el subconjunto nuevo)

No se corrió `perl -c` en esta pasada (ya lo hizo el audit previo sobre los mismos módulos base); el
único archivo nuevo con lógica real (`train_fantasma_lstm_v2.pl`) es el que generó
`Data/ml_out/lstm_fantasma_final/` — su ejecución exitosa y reproducible (`--eval-only`, verificado
byte-idéntico en `MODELO_FINAL_V2.md` §Verificación de la copia) ya es evidencia indirecta de que
compila y corre en Fedora35/MXNet.

### 1.4 Veredicto código

**PRESENTABLE.** Cero hallazgos bloqueantes en el código que iría al zip (`Market/ML/*.pm`,
`scripts/extract_fantasma_dataset.pl`, `scripts/normalize_fantasma_dataset.pl`,
`scripts/train_fantasma_lstm_v2.pl`, `scripts/demo_fantasma_predict.pl`,
`scripts/compute_fantasma_binary_metrics_v2.py`). No se requiere ninguna limpieza adicional.

---

## 2. Docs candidatas — aptas vs internas

Criterio "apta": técnica, sin narrativa de proceso de agente (sin "Fase X", "auditor", "gate", "HECHO_CON_DEUDA",
refs a otros audits/veredictos internos, sesiones Lumina, citas de audios). Criterio "interna": todo lo
demás (audits, veredictos, transcripciones, notas de trabajo, checklists/guiones específicos del día del
oral).

### 2.1 Aptas (van al zip, algunas con edición menor)

| Doc | Estado | Nota |
|---|---|---|
| `EXTRACTOR_FANTASMA.md` | **APTA_CON_EDICIÓN** | Contenido técnico correcto (qué hace, cómo correr, features pack `full`/`core`). Tiene 2 rastros de proceso a limpiar antes de empaquetar: cabecera "Estado: HECHO_CON_DEUDA (cierre... `AUDIT_PASO2_CIERRE.md`)" y la sección final "Deuda / riesgos (auditor Paso 2)" que cita `AUDIT_PASO2_CIERRE.md` (doc interno que no va al zip). Sugerencia: quitar la palabra "auditor" del título de esa sección y no enlazar el audit inexistente en el zip (dejar la lista de riesgos técnicos, quitar la referencia rota). |
| `NORMALIZACION_FANTASMA.md` | **APTA_CON_EDICIÓN** | Igual patrón: cabecera "Estado: HECHO" está bien, pero §"Deuda aceptable" ítem 4 enlaza `AUDIT_PASO3_CIERRE.md` (interno). Quitar el enlace roto o convertirlo en nota sin link. |
| `LSTM_FANTASMA_V2.md` | **APTA_CON_EDICIÓN** | Es el doc técnico del entrenamiento que produjo el modelo final. Enlaza `docs/PLAN_REENTRENAMIENTO_MODELO_V2.md` (interno, no va al zip) — quitar o dejar como referencia sin link. El nombre del archivo usa "V2"; en el zip conviene renombrarlo a algo neutro (ver Parte B) ya que "v2" es jerga de proceso interno, no del contrato del profe. |
| `METRICAS_BINARIAS_V2.md` | **APTA_CON_EDICIÓN** | Contenido de métricas binarias completo y honesto (specificity baja, AUC modesto — bien documentado, no ocultar). Referencias a `AUDIT_FASE2_V2.md` (interno) en 2 puntos — quitar el link, mantener el texto explicativo. |
| `MODELO_FINAL_V2.md` | **APTA_CON_EDICIÓN** | Justificación de selección del modelo (criterio MAE→F1, tabla comparativa v1/v2/v2b) es exactamente lo que pide el profe como "detalle técnico". Referencias a `AUDIT_FASE2/3/4_V2.md` y `docs/PLAN_REENTRENAMIENTO_MODELO_V2.md` (internos) — quitar links rotos. |
| `ENTREGA_JUAN_86_FEATURES.md` | **APTA** | Explica el origen del `.txt`, sin narrativa de proceso relevante (solo dice "pedido (audio)", que es contexto legítimo y breve). |
| `ENTREGA_JUAN_86_FEATURES.txt` | **APTA** | Lista plana de 86 features, exactamente lo pedido por el profe. Sin cambios. |
| `PRESENTACION_FINAL_ML.pptx` / `.pdf` / `.html` | **APTA** | Diapositivas ya generadas con cifras del modelo final; van al zip en `presentacion/`. |
| `GUION_PRESENTACION_FINAL.md` | **INSUMO, no incluir tal cual** | Tiene comandos exactos reutilizables (§"Comandos exactos") y la tabla de métricas — eso alimenta `guia.md`. Pero el resto es logística de oral en vivo (reloj de minutos, roles por persona, "frases de emergencia", checklist de proyector): no aplica a un módulo que se sube a un aula virtual sin exposición en vivo. **No copiar el archivo; extraer solo comandos+tabla de métricas hacia `guia.md`.** |
| `CHECKLIST_DEMO_FINAL.md` | **INTERNA** | 100% logística de sala/proyector para el día del oral (ya pasado). No aporta nada a un lector que abre el zip después. No incluir. |

### 2.2 Internas (NO van al zip)

| Doc | Motivo |
|---|---|
| `VEREDICTO_PRESENTAR_V2_VS_LUMINA.md` | Auditoría/veredicto interno; cita sesiones Lumina, transcripciones orales, jerga "PRESENTAR_V2_CON_CAVEATS". Es el insumo que confirma la decisión "solo v2/final" (ver Parte B), pero el documento en sí no es material de curso. |
| `MODELO_V2_TRABAJO.md` | Nota de trabajo fase 0-1, jerga "Fase X HECHA". |
| `AUDIT_FASE0_FASE1_V2.md`, `AUDIT_FASE2_V2.md`, `AUDIT_FASE3_V2.md`, `AUDIT_FASE4_V2.md`, `AUDIT_CIERRE_V2.md`, `CHECK_FASE0_FASE1_V2.md` | Audits internos del reentrenamiento v2. |
| `AUDIT_PASO1_CIERRE.md` … `AUDIT_PASO4_CIERRE.md` | Audits internos del pipeline original (Pasos 1-4). |
| `AUDIT_GHOSTS_VS_PIVOTPOINTS_HL.md`, `AUDIT_DOCX_INDICACIONES_FINAL_V1.md`, `AUDIT_ORAL_LUMINA_IA_ULTIMO_MES.md`, `AUDIT_PIPELINE_ML_CIERRE_FINAL.md` | Audits de conformidad contra DOCX/oral del profe; uso interno del equipo. |
| `ESTUDIO_ORAL_PRESENTACION.html`, `ESTUDIO_ORAL_ELEVEN_READER.txt` | Material de estudio personal para el oral (ya pasado). |
| `TRANSCRIPCION_PROFE_2026-07-28_POST_ORAL.md`, `TRANSCRIPCION_JUAN_SOLICITUD.md`, `transcripcion_IA_2026-07-27_ultimas_indicaciones.txt`, `notas_IA_2026-07-27_ultimas_indicaciones.json`, `lumina_IA_2026-07-27_import_result.json` | Transcripciones/metadatos de audio privados; no son material de curso. |
| `AUDIT_LIMPIEZA_COMENTARIOS_ML.md` (este mismo doc y su antecesor) | Auditorías de proceso, no material de curso. |
| `_check_fase6.py`, `_patch_pdf_script.py`, `_gen_presentacion_pptx.py`, `_gen_presentacion_pdf.py`, `_strip_html_chrome.py` | Utilidades privadas de generación de las diapositivas (prefijo `_`); no aportan al lector del zip. |
| `Especificacion_2a_Fase_TEXTO.txt`, `Pearson_PCC_TEXTO.txt`, `Direccion-del-precio-interna-externa_PDF.txt`, `transcripciones_actualizadas_202607/**` | Material de **indicadores** (ya subido a otra parte del aula, según el profe); fuera del alcance "módulo predictivo". |
| `docs/RUTA_FINAL_MODELOS.md`, `docs/PLAN_REENTRENAMIENTO_MODELO_V2.md`, `docs/PLAN_SIGUIENTE_MODELOS.html` (fuera de `material_profesor/`) | Roadmap/planificación interna del equipo, con jerga "Fase X", "gate", tablas de estado. No es material de curso. |

**No existe** todavía un `guia.md` propio del módulo predictivo — hay que redactarlo (Parte B, checklist
pre-zip). Tampoco hay un archivo llamado literalmente "guia" en el repo (se buscó; el único resultado es
un `.docx` no relacionado de material de aula).

---

## 3. Veredicto

## **LISTO_PARA_EMPAQUETAR**

- **Código:** presentable sin cambios adicionales (§1.4).
- **Docs:** presentables **con edición menor** — quitar 6 enlaces internos rotos (`AUDIT_PASO2/3_CIERRE.md`,
  `AUDIT_FASE2/3/4_V2.md`, `docs/PLAN_REENTRENAMIENTO_MODELO_V2.md`) de 4 archivos (`EXTRACTOR_FANTASMA.md`,
  `NORMALIZACION_FANTASMA.md`, `LSTM_FANTASMA_V2.md`, `METRICAS_BINARIAS_V2.md`, `MODELO_FINAL_V2.md`).
  Esta edición es cosmética (quitar referencias a documentos que no viajan en el zip), no re-limpieza de
  tono ni de lógica; se puede hacer al armar el zip (Parte B, checklist) sin bloquear nada ahora.
- **Falta redactar:** `guia.md` seca (qué es / esquema / comandos / features / resultados) — no existe aún;
  el material fuente (`GUION_PRESENTACION_FINAL.md`, `MODELO_FINAL_V2.md`, `METRICAS_BINARIAS_V2.md`)
  ya tiene todo el contenido necesario, solo falta consolidarlo sin la logística de oral en vivo.

No se encontró ningún hallazgo bloqueante nuevo en código. No se re-limpia nada en esta pasada (fuera de
alcance del encargo); los 6 enlaces internos quedan listados arriba para que quien arme el zip los quite.

---

## 4. Resumen para el padre

- **Veredicto:** LISTO_PARA_EMPAQUETAR (con edición cosmética menor en 5 docs: quitar links a audits
  internos, no re-limpieza de código).
- **Código:** 0 hallazgos bloqueantes; `train_fantasma_lstm_v2.pl` y `NormalizeFantasmaDataset.pm`
  (no cubiertos por el audit anterior) verificados ahora, PASS.
- **Docs aptas para el zip:** `EXTRACTOR_FANTASMA.md`, `NORMALIZACION_FANTASMA.md`, `LSTM_FANTASMA_V2.md`,
  `METRICAS_BINARIAS_V2.md`, `MODELO_FINAL_V2.md`, `ENTREGA_JUAN_86_FEATURES.md/.txt`,
  `PRESENTACION_FINAL_ML.*`. Falta redactar `guia.md` (no existe; ver Parte B).
- **Docs internas (no van):** todos los `AUDIT_*`, `VEREDICTO_*`, `MODELO_V2_TRABAJO.md`,
  `CHECK_FASE0_FASE1_V2.md`, transcripciones, `ESTUDIO_ORAL_*`, `CHECKLIST_DEMO_FINAL.md`, scripts `_*.py`
  de generación de slides, y todo lo de indicadores/roadmap fuera de este módulo.
