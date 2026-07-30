# Plan de carpeta — ZIP Unidad 5 (módulo predictivo Fantasma/LSTM)

**Fecha:** 2026-07-28
**Estado:** PROPUESTA — no se crea el `.zip` en esta pasada.
**Pedido origen:** audio profe post-oral (`TRANSCRIPCION_PROFE_2026-07-28_POST_ORAL.md`): subir a
**Unidad 5** el **módulo predictivo** con **comandos**, **features** y **detalles técnicos**.
Nota 15/15; correcciones menores permitidas en algunos días.
**Insumo de calidad:** `AUDIT_CALIDAD_FINAL_ENTREGA_U5.md` (veredicto LISTO_PARA_EMPAQUETAR).

### Alcance fijo (decisión Bryan 2026-07-28)

- **Este ZIP = solo el módulo predictivo** (LSTM Fantasma: extract → normalize → train/eval → demo).
- **NO incluye la entrega de indicadores** ni la app de charting como producto. Eso va en **otra
  asignación** (el profe ya trató indicadores aparte / se sube por separado).
- Los `.pm` bajo `Market/Indicators/` que figuran abajo **no son “la entrega de indicadores”**:
  son **dependencias headless del extractor** (sin ellas no se pueden recalcular las 86 features).
  En `guia.md` se aclara en una línea: “módulos de cálculo reutilizados por el extractor; la GUI y
  la entrega de indicadores no forman parte de este paquete.”

---

## 1. Decisión: ¿1 modelo o varios?

### Recomendación: **solo el modelo final** (`lstm_fantasma_final/` = v2 simple r06)

Justificación, cruzando el audio del profe y el veredicto interno ya hecho
(`VEREDICTO_PRESENTAR_V2_VS_LUMINA.md`, que aunque es un doc interno que no va al zip, su conclusión sí
aplica aquí):

1. **El profe pidió "el módulo predictivo"**, no un historial de reentrenamiento. La frase del audio es
   "aquí suben los módulos predictivos, con los comandos que están ejecutando, con los features, todos
   los detalles técnicos que necesitan" — singular, orientado a comandos/features/resultados, no a
   comparativas de hiperparámetros.
2. **v1 (`lstm_fantasma/`) fue superado en las 4 ventanas** por v2/final (MAE prom 1.79 → 1.49, −17%;
   F1 like-for-like 0.81 → 0.87). Subir v1 junto al final sin que el profe lo pida es ruido: obliga al
   lector a comparar dos carpetas de pesos/métricas cuando solo una es "el modelo".
3. **v2b (`lstm_fantasma_v2b/`) fue explícitamente descartada** (MAE 1.4975 > 1.4886 del final) en la
   propia documentación técnica (`LSTM_FANTASMA_V2B.md`). No tiene sentido pedagógico subir una variante
   que el propio equipo determinó que es peor — es literalmente "el laboratorio de reentrenamiento" que
   el pedido del profe no cubre.
4. **Criterio pedagógico:** un entregable de "módulo predictivo" se evalúa por objetivo → método →
   resultado → demo, no por el registro de experimentos. El grid de 8 configuraciones y la comparación
   v1/v2/v2b son evidencia de rigor metodológico, y por eso **sí van en prosa dentro de `guia.md`**
   (una tabla comparativa corta, sin pesos ni CSVs duplicados) — pero como **una sección de "cómo se
   eligió el modelo"**, no como carpetas paralelas de artefactos.

### Tratamiento de v1: mención de una línea, sin duplicar pesos

`guia.md` debe incluir una sub-sección breve "Modelo anterior (referencia)" con la tabla ya existente en
`MODELO_FINAL_V2.md` (MAE/F1 de v1 vs final), citando que v1 quedó archivado como baseline. **No** se
copian `fantasma_lstm.params` de v1 ni sus CSV de predicciones al zip — solo los 3-4 números de la tabla,
transcritos como texto/tabla markdown.

### v2b: ni siquiera mención de una línea con archivo propio

Se resume en la misma tabla comparativa de `guia.md` ("variante con capa densa extra, descartada por peor
MAE") sin carpeta de artefactos ni doc dedicado.

**Conclusión Parte B.1:** el zip lleva **un solo directorio de modelo** (`lstm_fantasma_final/`) con sus
5 artefactos, y las cifras de v1/v2b viven únicamente como tabla comparativa dentro de `guia.md`.

---

## 2. Árbol exacto propuesto del zip

```
ModuloPredictivo_Fantasma_LSTM/
├── guia.md
├── features_86.txt
│
├── presentacion/
│   ├── PRESENTACION_FINAL_ML.pptx
│   └── PRESENTACION_FINAL_ML.pdf
│
├── scripts/
│   ├── extract_fantasma_dataset.pl
│   ├── normalize_fantasma_dataset.pl
│   ├── train_fantasma_lstm_v2.pl
│   ├── demo_fantasma_predict.pl
│   └── compute_fantasma_binary_metrics_v2.py
│
├── Market/
│   ├── MarketData.pm
│   ├── ML/
│   │   ├── ExtractFantasmaDataset.pm
│   │   ├── FantasmaLSTMData.pm
│   │   └── NormalizeFantasmaDataset.pm
│   ├── Indicators/
│   │   ├── PivotPointsHL.pm
│   │   ├── ATR.pm
│   │   ├── SMC_Pro.pm
│   │   ├── SMC_Structures_FVG.pm
│   │   ├── ZigZag.pm
│   │   ├── DIY.pm
│   │   ├── AnchoredVWAP.pm
│   │   ├── VolumeProfile2.pm
│   │   ├── HLD.pm
│   │   ├── AutoTrendChannel.pm
│   │   └── Liquidity.pm
│   └── Drawing/
│       └── FibRetracement.pm
│
├── Data/
│   ├── 2026_Abril-Junio.csv          # fuente train (opcional, ver §4 tamaño)
│   ├── 2026_07_24.csv                # fuente test  (opcional, ver §4 tamaño)
│   └── ml_out/
│       ├── fantasma_train_norm.csv
│       ├── fantasma_test_norm.csv
│       ├── fantasma_norm_stats.json
│       └── lstm_fantasma_final/
│           ├── fantasma_lstm.params
│           ├── metrics_test.json
│           ├── binary_metrics_test.json
│           ├── preds_test.csv
│           └── train_config.json
│
└── docs/
    ├── EXTRACTOR_FANTASMA.md
    ├── NORMALIZACION_FANTASMA.md
    ├── LSTM_FANTASMA_FINAL.md        # = LSTM_FANTASMA_V2.md renombrado, sin jerga "v2"/links internos
    ├── METRICAS_BINARIAS.md          # = METRICAS_BINARIAS_V2.md renombrado, sin links internos
    └── SELECCION_MODELO.md           # = MODELO_FINAL_V2.md renombrado, sin links internos
```

**Por qué se renombran 3 docs (quitar sufijo `_V2`):** "v2" es numeración de proceso interno (hubo v1,
v2, v2b). Para el lector del aula, este *es* el módulo predictivo, punto — no hace falta que sepa que
hubo iteraciones internas de versión salvo en la sección "cómo se eligió el modelo" de `guia.md`. Los
títulos `_FINAL` / `SELECCION_MODELO` comunican mejor el propósito sin perder contenido técnico.

---

## 3. INCLUIR vs EXCLUIR

### INCLUIR

| Categoría | Qué | Por qué |
|---|---|---|
| Guía | `guia.md` (nuevo, por redactar) | Punto de entrada único: qué es, esquema del pipeline, comandos, features, resultados, cómo se eligió el modelo. |
| Features | `features_86.txt` (= `ENTREGA_JUAN_86_FEATURES.txt`) | Pedido explícito del profe/Juan; lista canónica de las 86 dimensiones de entrada. |
| Presentación | `PRESENTACION_FINAL_ML.pptx` + `.pdf` | Diapositivas ya con cifras del modelo final; el `.html` es solo para proyector con teclado, no aporta fuera de esa sesión — no hace falta en el zip. |
| Scripts runtime | `extract_fantasma_dataset.pl`, `normalize_fantasma_dataset.pl`, `train_fantasma_lstm_v2.pl`, `demo_fantasma_predict.pl`, `compute_fantasma_binary_metrics_v2.py` | Cubren el pipeline completo (extraer → normalizar → entrenar/evaluar → demo → métricas binarias) con los comandos exactos que pide el profe. |
| Código Perl (predictivo) | `Market/ML/*`, `Market/MarketData.pm`, `Market/Drawing/FibRetracement.pm` | Núcleo del módulo predictivo + carga OHLCV. |
| Deps de cálculo (no entrega indicadores) | `Market/Indicators/*` (solo los que importa el extractor; ~11 `.pm`) | **No** es el paquete de indicadores del curso. Son libs de cálculo sin Tk, necesarias si alguien re-corre `extract_fantasma_dataset.pl`. La entrega formal de indicadores / `market.pl` / overlays **queda fuera**. |
| Datos procesados | `fantasma_train_norm.csv`, `fantasma_test_norm.csv`, `fantasma_norm_stats.json` | Necesarios para correr `train_fantasma_lstm_v2.pl --eval-only` y `demo_fantasma_predict.pl` sin re-extraer nada. |
| Modelo final | `Data/ml_out/lstm_fantasma_final/*` (5 archivos) | El entregable en sí: pesos + métricas + preds + config. |
| Datos crudos fuente | `Data/2026_Abril-Junio.csv`, `Data/2026_07_24.csv` | **Opcional** (ver §4): solo si se quiere que el extractor sea 100% reproducible desde cero dentro del zip. Sin ellos, el pipeline runtime igual funciona (empieza en `normalize`/`train --eval-only`/`demo`). |
| Docs técnicas | `EXTRACTOR_FANTASMA.md`, `NORMALIZACION_FANTASMA.md`, `LSTM_FANTASMA_V2.md`→`LSTM_FANTASMA_FINAL.md`, `METRICAS_BINARIAS_V2.md`→`METRICAS_BINARIAS.md`, `MODELO_FINAL_V2.md`→`SELECCION_MODELO.md` | Detalle técnico por etapa, tal como pide el profe. Editadas para quitar 6 enlaces rotos a audits internos (ver `AUDIT_CALIDAD_FINAL_ENTREGA_U5.md` §2.1). |

### EXCLUIR

| Categoría | Qué | Por qué |
|---|---|---|
| Modelos descartados | `lstm_fantasma/` (v1), `lstm_fantasma_v2/` (workspace intermedio), `lstm_fantasma_v2b/` (descartado) | Decisión §1: solo el modelo final va como carpeta de artefactos; v1/v2b quedan como 1 tabla en `guia.md`. |
| Audits/veredictos | Todo `AUDIT_*.md`, `VEREDICTO_PRESENTAR_V2_VS_LUMINA.md`, `MODELO_V2_TRABAJO.md`, `CHECK_FASE0_FASE1_V2.md` | Proceso interno del equipo, no material de curso (ver audit de calidad §2.2). |
| Oral (ya pasado) | `GUION_PRESENTACION_FINAL.md`, `CHECKLIST_DEMO_FINAL.md`, `PRESENTACION_FINAL_ML.html`, `ESTUDIO_ORAL_*` | Logística de exposición en vivo (reloj de minutos, roles, checklist de proyector); sin valor para quien abre el zip después. Los comandos útiles de `GUION_*` ya se trasladan a `guia.md`. |
| Transcripciones/audio | `TRANSCRIPCION_*`, `transcripcion_IA_*.txt`, `notas_IA_*.json`, `lumina_IA_*.json` | Privadas, no son material de curso. |
| Planeación interna | `docs/RUTA_FINAL_MODELOS.md`, `docs/PLAN_REENTRENAMIENTO_MODELO_V2.md`, `docs/PLAN_SIGUIENTE_MODELOS.html` | Roadmap del equipo con jerga de fases/gates. |
| Utilidades privadas | `_check_fase6.py`, `_patch_pdf_script.py`, `_gen_presentacion_pptx.py`, `_gen_presentacion_pdf.py`, `_strip_html_chrome.py` | Generan las slides pero no son parte del "módulo predictivo"; prefijo `_` ya las marca como privadas. |
| Aula virtual / material de curso | Todo `docs/material_aula_virtual/**` (PDFs del profesor, datasets de ejemplo, patches MXNet, notebooks Jupyter) | Es material que el profesor ya entregó al curso, no algo que el grupo deba re-subir. Los patches MXNet son del entorno, no del módulo predictivo. |
| Entrega de indicadores (otra asignación) | `market.pl`, `Market/ChartEngine.pm`, `Market/Overlays/**`, `Market/UI/**`, `Market/Panels/**`, `Market/Debug/**`, docs de Fase 2 GUI, capturas TV, specs de indicadores | **Fuera de este zip.** Se sube (o ya se subió) en la asignación de indicadores, no aquí. |
| Material “indicadores como producto” | README de charting, rúbrica GUI, docs de overlays SMC/HLD como entregable visual | No confundir con deps de cálculo del extractor. |
| Scripts operativos puntuales | `scripts/monitor_fantasma_extracts.sh`, `scripts/ensure_train_and_finish.sh`, `scripts/run_fantasma_full_extracts.sh`, `scripts/finish_fantasma_paso3.sh` | Orquestación de una corrida larga puntual (PIDs, rutas `/tmp` de esta máquina); no son comandos reproducibles por un tercero. |
| Otros docs de `material_profesor/` fuera de tema | `Especificacion_2a_Fase_TEXTO.txt`, `Pearson_PCC_TEXTO.txt`, `Direccion-del-precio-interna-externa_PDF.txt`, `transcripciones_actualizadas_202607/**` | Material de indicadores (Fase 1/2 GUI), ya entregado aparte. |
| pycache | `scripts/__pycache__/` | Basura de bytecode Python, nunca se empaqueta. |

---

## 4. Tamaño estimado (grosso modo)

| Bloque | Tamaño aprox. |
|---|---:|
| `Market/ML` + `Indicators` + `Drawing` + `MarketData.pm` (16 archivos Perl) | ~0.26 MB |
| `scripts/*` (5 archivos) | ~0.03 MB |
| `Data/ml_out/lstm_fantasma_final/` (5 archivos: params + 3 json + preds csv) | ~0.4 MB |
| `Data/ml_out/fantasma_{train,test}_norm.csv` + `fantasma_norm_stats.json` | ~16 MB (12.2 + 3.8 + 0.015 MB — son el bulto principal) |
| `docs/*.md` (5 archivos) + `guia.md` + `features_86.txt` | <0.1 MB |
| `presentacion/*.pptx` + `.pdf` | ~0.06 MB |
| **Subtotal sin CSVs crudos** | **≈ 17 MB** |
| + `Data/2026_Abril-Junio.csv` + `Data/2026_07_24.csv` (si se incluyen, opcional) | + 6.6 MB → **≈ 23–24 MB** |

Comprimido en zip (los CSV normalizados son texto con muchos decimales repetidos, comprimen bien:
zip típico de CSV numérico ronda 20-35% del tamaño original) el resultado final probablemente queda
en **~5-8 MB** sin los CSV crudos, o **~6-10 MB** con ellos. Nada que preocupe para subir a un aula
virtual.

**Recomendación sobre los CSV crudos (`2026_Abril-Junio.csv` / `2026_07_24.csv`):** inclúyelos **solo
si quieres que el extractor (`extract_fantasma_dataset.pl`) sea corrible de punta a punta dentro del
zip**. Advertencia honesta para `guia.md`: el extract full tarda ~38 min (train) / ~51 min (test) en
Fedora35 — no es una demo, es una corrida de fondo. Si el objetivo es solo "mostrar detalle técnico y
dejar todo reproducible en teoría", inclúyelos con esa advertencia. Si el objetivo es minimizar peso y
dejar solo lo que realmente se ejecuta en segundos (`--eval-only`, `demo_fantasma_predict.pl`), puedes
omitirlos y decir en `guia.md` "el CSV fuente es el compartido por el profesor, no se re-adjunta aquí".

---

## 5. Checklist pre-zip

- [ ] **Escribir `guia.md`** (no existe todavía) con, como mínimo:
  - Qué es el módulo (1 párrafo: predice conteos de rastros del fantasma en 4 ventanas 3/5/10/15 min).
  - Esquema del pipeline: `CSV OHLCV → extract (Opción A, causal) → normalize (z-score train-only, 86 feats) → train LSTM (grid + early stop) → eval/demo`.
  - Los 4-5 comandos exactos (extract, normalize, train `--eval-only`, demo `--n 8`), tomados de
    `GUION_PRESENTACION_FINAL.md` §"Comandos exactos" y `LSTM_FANTASMA_V2.md`.
  - Tabla de **features** (86, con link a `features_86.txt`; resumen por tipo: OB/FVG/Fib/AVWAP/POC-VAH-VAL/S-R/BOS-CHoCH/EQH-EQL/DIY/canal/ATR-vol, en 3 TF).
  - **Resultados finales:** MAE promedio **1.49**, F1 promedio **0.87** (tabla por ventana y3/y5/y10/y15, tomada de `GUION_PRESENTACION_FINAL.md` §5 o `MODELO_FINAL_V2.md`).
  - Sub-sección corta "cómo se eligió el modelo" con la tabla v1/v2/v2b (sin pesos, solo números).
  - Límites honestos (Opción A ≠ Pine literal, specificity baja en vista binaria) en 3-4 líneas.
- [ ] Quitar los 6 enlaces internos rotos de los 5 docs técnicos antes de copiarlos/renombrarlos
      (lista exacta en `AUDIT_CALIDAD_FINAL_ENTREGA_U5.md` §2.1 y §3).
- [ ] Confirmar que el **demo corre** desde una copia limpia de la carpeta propuesta (sin el resto del
      repo en `@INC`): `perl -I. scripts/demo_fantasma_predict.pl --n 8` debe imprimir la tabla
      TRUE/PRED y cerrar con `FIN DEMO` (criterio ya usado en `CHECKLIST_DEMO_FINAL.md` §C1).
- [ ] Confirmar que `perl -I. scripts/train_fantasma_lstm_v2.pl --eval-only --model Data/ml_out/lstm_fantasma_final/fantasma_lstm.params --out-dir /tmp/zip_check --hidden 48 --dropout 0.2 --batch-size 32 --seq-len 5` reproduce MAE≈1.4886 / F1≈0.8657 (mismo chequeo que `MODELO_FINAL_V2.md` §Verificación de la copia, pero corrido desde la carpeta candidata al zip).
- [ ] Verificar que `guia.md` cita las cifras finales correctas: **MAE 1.49 / F1 0.87** (promedio;
      detalle por ventana y3 0.82/0.81, y5 1.15/0.85, y10 1.75/0.89, y15 2.24/0.91).
- [ ] Decidir si van los 2 CSV crudos (`2026_Abril-Junio.csv`, `2026_07_24.csv`) según §4; si no van,
      dejar 1 línea en `guia.md` aclarando que son los CSV del profesor, no re-adjuntos.
- [ ] Revisar que ningún doc copiado mencione "Josafa", "oral", "Lumina", "handoff" u otra jerga de
      proceso (grep rápido sobre los 5 `.md` + `guia.md` antes de comprimir).
- [ ] Solo entonces: crear el `.zip` (fuera de este encargo).

---

## Resumen para el padre

Árbol final: `guia.md` + `features_86.txt` + `presentacion/` (pptx+pdf) + `scripts/` (5 scripts
extract→normalize→train→demo→métricas) + `Market/` (solo ML + Indicators + Drawing + MarketData,
headless, ~0.26 MB, sin Tk/GUI) + `Data/` (CSV normalizados + stats + `lstm_fantasma_final/` completo;
CSV crudos opcionales) + `docs/` (5 docs técnicas renombradas sin sufijo `_v2` ni links internos).
Tamaño aprox. 17 MB sin CSV crudos / ~23-24 MB con ellos (mucho menos comprimido). Queda pendiente
redactar `guia.md` (no existe aún) y limpiar 6 enlaces rotos a audits internos en 5 docs — nada de esto
bloquea, es la única tarea real antes de comprimir.
