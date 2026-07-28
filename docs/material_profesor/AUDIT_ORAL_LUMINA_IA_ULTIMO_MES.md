# Audit oral Lumina — IA (último mes ≈ 2026-06-20 → 2026-07-27)

**Materia Lumina:** `IA` — Inteligencia Artificial (también aparecen alias ASR: “Inteligencia Artificial y Machine Learninge”).  
**Regla de autoridad:** instrucción explícita **más reciente** gana sobre el mismo requisito; omisión no cancela.  
**Fuentes cruzadas locales:**  
- `docs/material_profesor/transcripcion_IA_2026-07-27_ultimas_indicaciones.txt` (+ notas JSON / import)  
- `docs/material_aula_virtual/10_indicaciones_finales_2026-07-27/Indicaciones-Proyecto-parte-final_v1.0.docx` (escrito 25-jul; no es oral, pero cierra el oral)  
- `docs/material_profesor/transcripciones_actualizadas_202607/` (REQUISITOS / MATRIZ corte 19-jul — indicadores)  
- Comparación gaps: `docs/RUTA_FINAL_MODELOS.md` — **gaps §5 cerrados en merge 2026-07-27**

**ASR:** muchas transcripciones tienen errores fonéticos (Disney=t-SNE, PIB/PIP, graph/grab, SWIP/sweep, RST/LSTM, etc.). Aquí se interpreta al criterio del curso, no se cita basura ASR como literal.

---

## 1. Resumen ejecutivo (qué manda el oral más reciente)

El oral del **2026-07-27** (`2d01313877a5`), alineado con el DOCX v1.0 del **25-jul**, define el entregable de modelos así:

1. **Objetivo del modelo:** a partir de cada **aparición o reubicación del fantasmita** (Replay **1m**), predecir **cuántos rastros “1”** dejará hacia adelante en ventanas **3, 5, 10 y 15 minutos** (4 salidas). Cada reubicación = **nueva muestra**.
2. **Lo que el profe evalúa en la oral:** no diapositivas bonitas; que la data se tome **en los momentos/lugares correctos** (eventos del fantasma + contexto de liquidez/volumen). “No se inventan algoritmos; se saca la data del lugar correcto.”
3. **Train / test:** abril–junio para entrenar; julio para test (CSV del profe). Desbalance de clases **no es excusa** (LSTM es sensible a frecuencias reales; analogía con pausa vs habla del lab acústico).
4. **Métricas:**  
   - **Regresión** sobre los conteos 3/5/10/15.  
   - **Y/o clasificación** binarizando aparece/no en cada ventana → precisión, recall, F1, sensibilidad, etc.
5. **Rango típico de conteos (oral 27):** valores **0…3** como rango predecible frecuente (“4 valores”); en 3 min lo más probable es 0 o 1. Esto **suaviza** el oral del 20-jul que hablaba de techos 0…N por ventana (0…5, 0…10, 0…15).
6. **Tipo Sweep/Grab/Run:** el modelo **no tiene** que decir *qué* manipulación será; basta (en la variante binarizada) *si habrá* toma/cambio de liquidez en la ventana. El tipo solo se conoce mirando el **futuro**; puede ir como **feature** de la tablota, no como obligación de etiqueta LSTM.
7. **Presentación:** ≤ **10 min** grupal; demo de predicción con modelo + tabla ya extraída (DOCX + orales 20/22).

**Cadena paralela aún viva (oral 23-jul, peso medio-alto pero subordinada al DOCX/27):** t-SNE → GMM (atemporal, P(sweep/grab/run) en niveles, umbral ~85%) + HMM interno/externo (temporal, solo etiquetas). No la anula el 27; el 27 **reenfoca** el entregable práctico hacia **LSTM + fantasmita + conteos**.

---

## 2. Timeline de sesiones (nuevo → viejo) con peso

| Peso | Fecha | Session id | Título / tema | Relevancia proyecto |
|---:|---|---|---|---|
| **Máximo** | 2026-07-27 | `2d01313877a5` | Últimas indicaciones (modelos / presentación) | Labels 3/5/10/15, muestreo fantasma, métricas, AVP, no slides |
| **Máximo (escrito)** | 2026-07-25 | — (DOCX aula) | Indicaciones-Proyecto-parte-final_v1.0 | Spec features, PIPs, TFs, CSV, Ghosts, presentación, CNN opcional |
| **Alto** | 2026-07-23 | `72a062cbd418` | Indicaciones examen y proyecto | t-SNE/GMM/HMM, PIPs, split abr–jun/jul, rúbrica 20+15, umbral 85% |
| **Alto** | 2026-07-22 | `56af8823ac16` | Modelo predictivo con LSTM | Lab acústico = plantilla; adaptar a CSV; 10 min; máquinas/patches |
| **Alto** | 2026-07-21 | `cc5a2f136d5a` | Microestructura / features | Sweep/Grab/Run y futuro; fantasma = conteo de rebotes; liquidez |
| **Alto** | 2026-07-21 | `384c13811adb` | Revisión indicadores (~24 min) | AVWAP auto anclado a pivote + fantasma; HLD 4h/D; justificar S/G/R |
| Medio | 2026-07-21 | `34666c2f4627`, `9277aa8ce9c8`, `0ed53523b1c9` | Clips cortos mismo día | Fragmentos; usar solo si confirman el bloque largo |
| **Alto** | 2026-07-20 | `6464bc920db3` / `a838e60e197e` | Modelado predictivo + revisión | **Definición canónica del fantasmita**, 4 salidas LSTM, tablota multi-TF, MXNet, 15/35 |
| Medio–alto | 2026-07-14 | `168eb485a606` | SMC + pipeline features + t-SNE | Fantasma ancla AVWAP; Sweep/Grab/Run; revisión indicadores |
| Medio | 2026-07-13 | `d1807c81628e` | t-SNE / desvíos | Fantasma → pivote AVWAP |
| Medio (indicadores) | 2026-07-08 | `076ef266e00b` | Revisión proyecto | Feedback visual OHLC/rangos |
| Medio (indicadores) | 2026-07-06 | `7aad975c6c5e` | ZigZag y otros | Revisión indicadores |
| Bajo (teoría) | 2026-07-01 | `256652222393` | EM / Bayes | Base GMM; no requisitos de entrega |
| Medio (Fase 2) | 2026-06-29 | `04007bb5edf2` | Revisión 1er avance Fase 2 | Indicadores; no redefine modelos finales |
| Contexto | 2026-06-23 … 06-15 | `47bfe676f0e6`, `1d3e610b36ae`, `a21ce910fecc`, etc. | K-means, liquidez, SMC | Base conceptual; **no** mandan el oral de modelos 27-jul |
| Vacío | 2026-07-09 | `c17a11a9cf4c` | (sin título) | Sin audio útil |

### Citas / paráfrasis fieles por sesión clave

#### 2026-07-27 — `2d01313877a5` (peso máximo)

- Presentación: *“no necesito ver diapositivas bonitas… que han tomado … las indicaciones correctas de cuando ocurren los eventos”*.
- Muestreo: Replay 1m; fantasmitas se van “desbloqueando”; cada aparición/desplazamiento → nueva toma para **3, 5, 10 y 15**.
- Conteos: si nadie aparece → **0**; un desplazamiento fuera → **1**; rango frecuente **0…3**.
- Desbalance OK: LSTM “funciona sensible a la frecuencia”; no es como algoritmos que exigen balance de etiquetas.
- Volumen: histograma **horizontal** (interés institucional) vs vertical (solo ese minuto).
- LSTM acústico: secuencia de ejemplo **5** pasos atrás para predecir el último (pista de diseño, no mandato rígido de hiperparámetro).
- Métricas: regresión en conteos **o** binarizar aparece/no → métricas de clasificación.
- Sobre predecir tipo de liquidez: *“¿va a haber una manipulación? Sí o no. … uno no sabe el tipo”* (Sweep/Grab/Run se conoce después).

#### 2026-07-23 — `72a062cbd418` (alto; pipeline probabilístico)

- Filas de la tablota = eventos **cerca de nivel de liquidez** (no 1 fila/minuto).
- Estandarizar precios en **PIPs**; ~50–100 columnas; normalización Cap. 1.
- Split temporal: **abr–jun train**, **julio test**.
- Orden: **t-SNE** (visualizar / parametrizar) → **GMM** (P(sweep)+P(grab)+P(run)=1; umbral **~85%** o abstenerse) → **HMM** interno + externo (solo etiquetas temporales).
- Tiempo / índice de evento = **metadato**, fuera de la matriz t-SNE/GMM.
- Sweep 1–2 velas; Grab 3–8; Run consolida dirección (directo o retest); etiqueta con **futuro** offline.
- Rúbrica proyecto: **20** indicadores + **15** modelos/resultados = **35**. Examen 27-jul (teoría + código/cálculo).

#### 2026-07-22 — `56af8823ac16` (alto; plantilla LSTM)

- Lab con data **acústica**: entrenar, guardar modelo, métricas = plantilla de lo que entregarán.
- Adaptar: features desde indicadores/CSV → tensores → LSTM → evaluar.
- Presentación ~**10 min** “cómo fueron las predicciones”.
- Pedido de máquinas **actualizadas** (patches MXNet / entorno).

#### 2026-07-21 — `384c13811adb` / `cc5a2f136d5a` (alto; features + revisión)

- AVWAP: manual OK, pero falta **automático** anclado a pivote consolidado **y** al fantasmita en movimiento (máx. ~2 automáticos).
- HLD / niveles D y **4h** (refuerzo oral).
- Sweep/Grab/Run deben **justificarse** con nivel de liquidez (OB, FVG, BSL/SSL, etc.); Run solo se confirma con futuro.
- Modelo “para contar cuántos rebotes salta el fantasmita”.

#### 2026-07-20 — `6464bc920db3` / `a838e60e197e` (alto; nacimiento del objetivo LSTM)

- Fantasmita = proyección dinámica al romper pivote; rastro “1” cuenta escapes fuera del rango.
- Ventanas **3, 5, 10, 15** velas de **1m**; **4 salidas**.
- Oral ese día: techos **0…3 / 0…5 / 0…10 / (0…15)** — luego matizado el 27 a “típico 0…3”.
- Tablota en cada primera aparición del ícono: distancias a OB/FVG/VWAP/etc., multi-TF (menciona **1m, 10m, 1h**), volumen, dirección HTF.
- MXNet LSTM; CNN mencionada como posible complemento (el DOCX 25-jul dice **probar primero sin CNN**).
- Exposición ~10 min; **15/35** de la nota del proyecto.

#### 2026-07-14 — `168eb485a606` (medio–alto)

- t-SNE agrupa patrones similares en 2–3D.
- Fantasma = ancla para AVWAP automático (“Mists”).
- Probabilidades Sweep/Grab/Run dado nivel de liquidez (semilla del oral 23).

#### Anteriores (junio / inicios julio)

Útiles para **indicadores** (SMC, liquidez, K-means, EM) y para la matriz de Fase 2; **no** redefinen el objetivo LSTM del 20–27 jul. Corte consolidado de indicadores: `transcripciones_actualizadas_202607/REQUISITOS_VIGENTES_PROFESOR.md` (Grab 3–8, HLD solo 4h/D aceptado, etc.).

---

## 3. Checklist de requisitos orales consolidados

### A. Datos y split

- [ ] Train: **2026-04-01 → 2026-06-30** (`2026_Abril-Junio.csv`)
- [ ] Test: **2026-07-01 → 2026-07-24** (`2026_07_24.csv`)
- [ ] Replay causal **1m** sobre todo el histórico (no solo overlay visible)
- [ ] Procesar por bloques si hace falta (oral 23: coste de CPU)

### B. Disparo de muestra (autoridad 20 + 25 + 27)

- [ ] Evento = aparición **o reubicación** del fantasmita (`Ghosts_in_swings` / rastro “1”)
- [ ] Features desde estructura **previa** a esa vela (causal)
- [ ] Labels mirando **futuro** solo para etiquetar (no filtrar features)

### C. Labels / salidas LSTM (autoridad 27 + DOCX)

- [ ] Cuatro targets: ventanas **3, 5, 10, 15** minutos
- [ ] Conteo de rastros / movimientos fuera del rango (etiqueta “1”)
- [ ] Esperar frecuencias sesgadas a **0** (y a lo sumo 1–2); techo práctico oral **0…3**
- [ ] Opcional: versión binaria aparece/no por ventana

### D. Features (DOCX + orales 20/21/23/27)

Distancias en **PIPs** del precio medio de la vela del fantasma a niveles más cercanos, en **≥3 TF** (1m, 10m, 1h):

1. OB (nivel + espesor)  
2. FVG (nivel + rango)  
3. Fib anclado a impulso ZZ **externo** consolidado  
4. Bandas AVWAP auto (penúltimo pivot / código Unidad 5; oral: también acompañar fantasmita)  
5. POC / VAH / VAL (AVP anclado a ZZ ext)  
6. Soportes/resistencias **4h / D / W** (DOCX; HLD de app ya cerrado en 4h/D — ver contradicciones)  
7. BOS / CHoCH  
8. EQH / EQL  
9. Sweep / Grab / Run (**solo si bien justificados**)  
10. Supply / Demand DIY  
11. Canal / Trendline (**solo si** regla 3 toques ≥2h + máximos dentro + ATR bajo)

Extras: ATR(1m), volumen 1m, EMA(9) volumen, etc.  
**Metadato** fecha/hora: **no** entra al entrenamiento.

### E. Modelo y entorno

- [ ] Patches MXNet + smoke con LSTM acústico (oral 22 + material Unidad 5)
- [ ] Adaptar lab → features del extractor; **primero sin CNN** (DOCX)
- [ ] Normalizar/estandarizar **fit solo en train**; persistir parámetros
- [ ] Guardar modelo; evaluar en julio
- [ ] Pista oral 27: secuencias tipo **len≈5** del lab (adaptar a minutos)

### F. Cadena t-SNE → GMM → HMM (oral 23; secundaria si el tiempo aprieta)

- [ ] t-SNE reduce / visualiza; ayuda a parametrizar GMM  
- [ ] GMM: P(sweep)+P(grab)+P(run)=1; umbral ~**85%** o abstención  
- [ ] Sin tiempo ni índice en la matriz  
- [ ] HMM **interno** + **externo** sobre secuencias de etiquetas  

### G. Presentación (orales 20/22/27 + DOCX)

- [ ] ≤10 min grupal  
- [ ] Mostrar extractor / cuándo dispara el fantasma  
- [ ] Features usadas + ejemplo de fila  
- [ ] Métricas en test julio  
- [ ] Demo en vivo: cargar modelo + tabla  
- [ ] Criterio oral: **muestreo correcto ≫ slides**  
- [ ] Nota: **15/35** modelos; **20/35** indicadores  

### H. Qué NO hacer (consolidado)

- Inventar algoritmos “nuevos” en vez de alimentar bien la tablota  
- Una fila por cada minuto  
- Meter `time` / índice de evento en la matriz de entrenamiento  
- Exigir balance artificial de clases como excusa  
- Priorizar polish visual / FSM “perfecta” sobre el extractor  
- Empezar por CNN  
- Presentar slides sin demo de muestreo/predicción  
- Etiquetar Run/Sweep/Grab en features/render con fuga de futuro  

---

## 4. Contradicciones / evoluciones de criterio

| Tema | Más viejo | Más nuevo | Resolución (más reciente gana) |
|---|---|---|---|
| **Objetivo de predicción** | 14–23 jul: P(sweep/grab/run \| nivel) vía t-SNE/GMM/HMM | 20–27 jul + DOCX: **conteos del fantasmita** 3/5/10/15 vía LSTM | **LSTM+fantasma** es el entregable de la parte final. Cadena t-SNE/GMM/HMM queda **paralela / si alcanza**. |
| **Filas de la tablota** | 23: filas cuando precio **cerca** de liquidez | 20/25/27: filas en **aparición/reubicación del fantasma** | Disparo canónico = **fantasma**. Proximidad a niveles entra como **features**, no como filtro exclusivo de filas. |
| **Techo de labels** | 20: y3∈0..3, y5∈0..5, y10∈0..10, y15∈0..15 | 27: rango predecible **0..3** | Implementar conteo real acotado por la ventana, pero **esperar/reportar** masa en 0..3; no asumir techos altos frecuentes. |
| **¿Predecir tipo S/G/R?** | 23: sí, con umbral 85% | 27: modelo puede ser solo sí/no manipulación; tipo es feature/post-hoc | LSTM final **no obliga** clase S/G/R; GMM sí si se hace la cadena 23. |
| **CNN** | 20: “junto con capas convolucionales” | DOCX 25: **opcional**; primero sin CNN | **Sin CNN primero.** |
| **HLD / S-R semanal** | Oral revisión: HLD app **solo 4h/D** (aceptado) | DOCX features: **4h/D/W** | Features del modelo pueden incluir W vía niveles; **no reabrir** HLD de la app si ya está cerrado en 4h/D. |
| **AVWAP** | PDF anchors varios; julio: auto pivote | 20–21: anclar a **fantasma** + pivote consolidado (≤2 auto) | Auto pivote + fantasmita; manual para eventos especiales. |
| **Grab ventana** | PDF ≤3 | Orales julio **3–8** | **3–8** vigente. |
| **Presentación** | Genérica “métricas Cap. 4” (23) | 27: muestreo correcto > slides | Cumplir métricas **y** demostrar muestreo/fantasma. |
| **Examen vs proyecto** | 23 fija examen 27-jul | 27 oral es clase post-examen / últimas indicaciones modelos | No mezclar: examen = Cap.5 algoritmos; proyecto modelos = fantasma/LSTM. |

---

## 5. Gaps vs `docs/RUTA_FINAL_MODELOS.md`

*(Inventario del audit oral. **Estado:** cerrados en merge a la ruta el 2026-07-27.)*

| # | Oral / DOCX dice | RUTA dice | Gap / acción sugerida |
|---|---|---|---|
| 1 | Conteos tip. **0…3** (27) | “y3…y15 ∈ {0,1,2,3…}” y “tip. 0…3” | Alineado en espíritu; aclarar en ruta que **20-jul techos 0…N** quedan subordinados al 27. |
| 2 | Secuencia lab **≈5** (27) | Adaptar I/O LSTM; no fija `seq_len` | **Falta** en ruta: pista explícita `seq_len≈5` (o justificar otro). |
| 3 | Binarizar aparece/no + métricas clasificación (27) | “Opcional: binarizar…” | Alineado; oral 27 lo eleva a **alternativa de primer nivel**, no solo opcional decorativa. |
| 4 | t-SNE→GMM umbral **85%**, HMM int/ext (23) | Paso 6 “si alcanza tiempo / pizarra” | Ruta ya deprioritiza; oral 23 aún lo pide en la narrativa de modelos — marcar **explícito** “no bloquea entrega LSTM”. |
| 5 | Filas “cerca de liquidez” (23) vs fantasma (20/27) | Disparo = fantasma | Ruta OK; añadir nota anti-confusión vs oral 23. |
| 6 | PIPs + ≥3 TF 1m/10m/1h (DOCX/23) | Presente en Paso 2 | Alineado. |
| 7 | Soportes **4h/D/W** (DOCX) | Lista incluye 4h/D/W | Alineado con DOCX; **falta nota** de no reabrir HLD-app (solo 4h/D). |
| 8 | AVWAP acompaña **fantasmita** (20–21) | “Bandas AVWAP auto (penúltimo pivot…)” | **Falta** mención explícita del ancla al fantasmita en movimiento. |
| 9 | Presentación: muestreo correcto > slides (27) | Criterio oral presente | Alineado. |
| 10 | No inventar algoritmos; data correcta (27) | En “Qué NO hacer” | Alineado. |
| 11 | Desbalance no es excusa (27) | No aparece como checklist | **Falta** bullet: no rebalancear artificialmente / no usar imbalance como coartada. |
| 12 | Volumen horizontal / interés institucional (27) | Features incluyen AVP POC/VAH/VAL | Alineado en lista; oral enfatiza **por qué** (narrativa presentación). |
| 13 | Tipo S/G/R solo post-hoc (27) | Sweep/Grab/Run “solo si bien implementados” como feature | Alineado; aclarar que **no** son labels LSTM obligatorias. |
| 14 | Rúbrica 20+15 / 10 min (20–23) | Presentación ≤10 min | Alineado; puntos 15/35 están implícitos. |
| 15 | Patches + smoke acústico (22) | Paso 0 HECHO | Alineado. |
| 16 | CSV train/test profe | Paso 1 SIGUIENTE | Alineado. |

### Lectura rápida para el agente de DOCX+ruta

Prioridad al alinear documentos: **(1)** DOCX 25-jul + oral 27, **(2)** oral 20 (definición fantasmita), **(3)** oral 22 (plantilla LSTM), **(4)** oral 23 solo como apéndice t-SNE/GMM/HMM y PIPs/rúbrica, **(5)** orales de revisión 21/14 para AVWAP/fantasma y justificación de liquidez.

---

## Apéndice — IDs Lumina tocados en este audit

`2d01313877a5`, `72a062cbd418`, `56af8823ac16`, `cc5a2f136d5a`, `384c13811adb`, `34666c2f4627`, `9277aa8ce9c8`, `0ed53523b1c9`, `6464bc920db3`, `a838e60e197e`, `168eb485a606`, `d1807c81628e`, `076ef266e00b`, `7aad975c6c5e`, `256652222393`, `04007bb5edf2`, más contexto junio (`47bfe676f0e6`, `1d3e610b36ae`, `a21ce910fecc`, …).

**Generado:** 2026-07-27 (audit oral; sin commits).

**Merge:** hallazgos de este audit incorporados en `docs/RUTA_FINAL_MODELOS.md` el **2026-07-27** (sección “Complementos orales”; gaps §5 cerrados). DOCX sigue siendo contractual #1.
