# Audit DOCX — Indicaciones Proyecto parte final v1.0

**Documento fuente (contractual #1):**  
`docs/material_aula_virtual/10_indicaciones_finales_2026-07-27/Indicaciones-Proyecto-parte-final_v1.0.docx`

**Metadatos del escrito:**
- Título: *Indicaciones para el entrenamiento de modelo predictivo para la parte final del proyecto*
- Versión: **1.0**
- Fecha/hora del doc: **25/07/2026 a las 14:00**

**Jerarquía (para el equipo):** este DOCX manda sobre lo oral si hay duda, salvo aclaración oral **más reciente** que complemente **sin contradecir** el escrito.

**Extracción:** texto completo del `word/document.xml` (PowerShell Expand-Archive), 2026-07-27.

**Oral Lumina:** audit en  
`docs/material_profesor/AUDIT_ORAL_LUMINA_IA_ULTIMO_MES.md` — **mergeado** en `docs/RUTA_FINAL_MODELOS.md` el 2026-07-27.

---

## 1. Objetivo del modelo (texto íntegro del requisito)

- [ ] El modelo debe aprender a **predecir la cantidad de rastros futuros** que dejarán los fantasmas.
- [ ] Ventanas posteriores: **3, 5, 10 y 15 minutos** (cuatro horizontes).
- [ ] Momento de referencia de la predicción: **a partir de la vela siguiente a cada aparición** del fantasma.
- [ ] Cada **nueva reubicación del fantasma** → se vuelve a estimar el número de rastros en **todas** esas ventanas futuras.
- [ ] Interpretación del ejemplo del doc: si el fantasma aparece a medianoche en punto, estimar cuántos **movimientos hacia afuera del rango actual de precio** habrá hasta medianoche+3 min, +5 min, etc.

**Salidas implícitas:** cuatro valores numéricos (conteos de rastros / proyecciones fuera de rango) para horizontes 3 / 5 / 10 / 15.

---

## 2. Datasets train / test (obligatorios del escrito)

| Rol | Archivo (ruta aula) | Copia en repo | Rango explícito en DOCX |
|---|---|---|---|
| **Entrenamiento** | `Unidad 5/Proyecto /2026_Abril-Junio.csv` | `…/10_indicaciones_finales_2026-07-27/2026_Abril-Junio.csv` | abril a junio |
| **Testeo** | `Unidad 5/Proyecto/2026_07_24.csv` | `…/10_indicaciones_finales_2026-07-27/2026_07_24.csv` | 1 a 24 de julio |

Checklist:
- [ ] Usar **solo** esos CSV para train/test del modelo predictivo final.
- [ ] No mezclar otros rangos/historicos como si fueran el split oficial.
- [ ] Evaluar el modelo predictivo **a partir de la data de testeo** (julio).

---

## 3. Fantasma / labels (Ghosts_in_swings)

- [ ] Implementación **idéntica** al indicador publicado en:  
  `Unidad 5/Proyecto/Capturas-de-pantallas-configuracion-indicadores/Ghosts_in_swings.txt`  
  (copia local típica: `docs/material_aula_virtual/08_unidad5_no_supervisado/Proyecto/Capturas-de-pantallas-configuracion-indicadores/Ghosts_in_swings.txt`).
- [ ] Debe funcionar correctamente en el sistema de trading del grupo.
- [ ] Usar **Replay** para observar la cantidad de rastros dejados.
- [ ] Los rastros se indican con etiquetas **`1`**.
- [ ] Ese conteo de `1`s en ventanas futuras = **etiquetado automático** contra el que se comparan las predicciones.

---

## 4. Extractor de características (script obligatorio)

### 4.1 Mecánica general

- [ ] Script extractor de características (aparte de la demo GUI).
- [ ] Tomar **todos los niveles de liquidez** a partir de la **estructura previa a la vela actual**.
- [ ] Mediante la función **Replay**.
- [ ] Gráfica / feed de muestreo: **1 minuto**.
- [ ] Flujo: **primero** observar la aparición del fantasma; **luego** medir distancias a niveles.
- [ ] Distancia = del **promedio de precio de la vela donde está el fantasma** respecto a los **niveles de liquidez más cercanos**.
- [ ] Convertir la unidad de precio a **PIP**.
- [ ] Ese conjunto (indicadores × ≥3 TF) = **un registro** en la tabla de datos.
- [ ] **Optimizar** el algoritmo de extracción desde el principio (no recalcular el universo entero por vela si se puede evitar).

### 4.2 Temporalidades mínimas (explícitas)

Al menos **3 temporalidades distintas**:

| Rol | TF del DOCX |
|---|---|
| Pequeña | **1 minuto** |
| Mediana | **10 minutos** |
| Grande | **1 hora** |

- [ ] Features de liquidez medidas en esas ≥3 TF (no solo en 1m).

### 4.3 Niveles / features de liquidez (lista completa 1–11)

Cada ítem es requisito del escrito (salvo condicionales 9 y 11):

1. [ ] **Order Block** — nivel **y** rango (espesor).
2. [ ] **FVG** — nivel **y** rango.
3. [ ] **Fibonacci** — niveles anclados a la **trama consolidada del impulso consolidado del zigzag externo**.
4. [ ] **VWAP anclado** — bandas del indicador VWAP anclado **automáticamente al penúltimo pivot** (según el indicador cuyo **código fuente** está en Unidad 5/Proyecto).
5. [ ] **Perfil de volumen** — niveles **POC, VAH y VAL** anclados al **impulso consolidado del zigzag externo**  
   *(nota: la frase del DOCX queda truncada: “servirán para indicar”; se interpreta como features de distancia a esos niveles).*
6. [ ] **Soportes/resistencias** — **4h / diario / semanal**.
7. [ ] Etiqueta **BOS / CHoCH** — su nivel.
8. [ ] Etiqueta **EQH / EQL** — su nivel.
9. [ ] Etiqueta **Sweep / Grab / Run** — su nivel  
   **solo si** correctamente implementadas: **debidamente justificadas con su respectivo nivel de liquidez**.
10. [ ] **Supply / Demand** — Indicador **DIY**; su nivel.
11. [ ] **Canal / Trendline** — nivel **y** rango  
    **solo si** correctamente implementado, con reglas del doc:
    - 3 mínimos (**HL o LL**) que coincidan linealmente en el tiempo;
    - a partir de **2 horas**;
    - máximos (**HH, LH**) que se ubiquen **dentro del canal**;
    - volatilidad **ATR baja**.

### 4.4 Columnas adicionales y metadata

A añadir (ejemplos explícitos del doc + “etc.”):

- [ ] **ATR** de 1 minuto.
- [ ] **Volumen** de 1 minuto.
- [ ] **EMA(9)** del volumen de 1 minuto.
- [ ] Otras columnas auxiliares razonables (“etc.”) si aportan contexto numérico causal.

Metadata (explícito):

- [ ] Incluir **fecha, hora y minuto** del evento en la tabla.
- [ ] Esa metadata **NO se usa para entrenar** el modelo.
- [ ] Sirve para **validar en la fase de testeo**.

---

## 5. Normalización / estandarización

- [ ] **Normalizar o estandarizar** los datos de features.
- [ ] **Guardar los parámetros** de normalización/estandarización.
- [ ] Reutilizar esos mismos parámetros en los **testeos** (no refitear en julio).

*(El DOCX no nombra min-max vs z-score; cualquiera vale si es consistente y persistido.)*

---

## 6. Entrenamiento, guardado, carga, comparación

- [ ] **Entrenar** el modelo (sobre data abr–jun ya normalizada).
- [ ] **Guardar** el modelo entrenado.
- [ ] **Cargar** el modelo entrenado para el testeo.
- [ ] **Comparar** los resultados obtenidos con el **etiquetado automático**.
- [ ] **Evaluar** el modelo predictivo con la data de testeo (julio 1–24).

*(El DOCX no fija la lista de métricas numéricas — ver oral / merge Lumina. Exige evaluación + comparación vs labels automáticos.)*

---

## 7. Arquitectura del modelo (LSTM / CNN)

- [ ] Referencia: script del algoritmo **LSTM** del curso (data numérica).
- [ ] En ese lab **no** se usan **CNN** para data numérica.
- [ ] Usar capas convolucionales queda **opcional**.
- [ ] Sugerencia explícita del profe: **primero probar sin CNN** para asegurar el funcionamiento más sencillo.

---

## 8. Presentación / exposición

- [ ] Presentación que cubra:
  1. El **extractor de características**.
  2. Los **features utilizados**.
  3. Los **resultados de la evaluación**.
  4. **Demostrar las predicciones al final** de la exposición.
- [ ] La demo de predicciones es a partir de:
  - carga del **modelo** entrenado, y
  - carga de la **tabla de features** previamente extraída.
- [ ] Exposiciones **grupales**.
- [ ] Duración: **hasta 10 minutos**.

---

## 9. Exclusiones / no-requisitos (lo que el DOCX NO pide)

Útil para no inventar alcance contractual:

- No exige cadena **t-SNE → GMM → HMM** en este escrito (puede venir del oral/curso; no está en v1.0).
- No fija métricas concretas (accuracy, F1, ROC, etc.) — solo “evaluar” + comparar vs etiquetado automático.
- No pide una fila por cada minuto (el muestreo es por aparición/reubicación del fantasma).
- No pide incluir fecha/hora/minuto como features de entrenamiento.
- No obliga CNN.
- Ítems 9 (Sweep/Grab/Run) y 11 (Canal) son **condicionales** a implementación correcta.
- No define el valor PIP para NQ ni la fórmula exacta de “promedio de precio” (open/high/low/close mid, etc.) — hay que fijarlo en implementación de forma coherente y documentarlo.

---

## 10. Checklist maestra (todo el DOCX en una lista)

Copiar/pegar para tracking de entrega:

### Objetivo y labels
- [ ] Predicción de conteos de rastros en 3 / 5 / 10 / 15 min
- [ ] Disparo = aparición / reubicación del fantasma (vela siguiente)
- [ ] Ghosts_in_swings.txt idéntico; rastros = etiquetas `1` vía Replay
- [ ] Etiquetado automático para comparar predicciones

### Datos
- [ ] Train = `2026_Abril-Junio.csv`
- [ ] Test = `2026_07_24.csv` (1–24 jul)
- [ ] Evaluación reportada sobre test

### Extractor
- [ ] Replay 1m, estructura previa a vela actual
- [ ] Distancia (PIP) precio medio vela-fantasma → niveles más cercanos
- [ ] ≥3 TF: 1m, 10m, 1h
- [ ] Features 1–11 (OB, FVG, Fib ZZ ext, AVWAP auto, POC/VAH/VAL, S/R 4h/D/W, BOS/CHoCH, EQH/EQL, Sweep/Grab/Run cond., S/D DIY, Canal cond.)
- [ ] Columnas extra: ATR 1m, vol 1m, EMA(9) vol 1m, etc.
- [ ] Metadata fecha/hora/minuto solo para validación test
- [ ] Optimización del extractor desde el inicio

### ML
- [ ] Normalizar/estandarizar + guardar parámetros
- [ ] Entrenar + guardar modelo
- [ ] Cargar modelo en test + comparar vs labels auto
- [ ] LSTM numérico; CNN opcional (preferir sin CNN primero)

### Presentación
- [ ] Extractor + features + evaluación + demo predicción (modelo + tabla)
- [ ] Grupal ≤ 10 min

---

## 11. Mapa rápido → roadmap del repo

| Bloque DOCX | Paso en `docs/RUTA_FINAL_MODELOS.md` |
|---|---|
| Entorno LSTM/MXNet (implícito vía lab) | Paso 0 (HECHO) |
| CSV train/test + Ghosts alineado | Paso 1 |
| Extractor Replay + features 1–11 + PIP + 3 TF | Paso 2 |
| Labels `1` en ventanas 3/5/10/15 | Paso 3 |
| Normalizar/estandarizar + params | Paso 4 |
| Entrenar/guardar/cargar/evaluar LSTM | Paso 5 |
| Presentación ≤10 min + demo | Paso 7 |

---

## 12. Texto fuente (párrafos del DOCX, para trazabilidad)

> Indicaciones para el entrenamiento de modelo predictivo para la parte final del proyecto  
> Versión 1.0 (25/07/2026 a las 14:00)

> Objetivo: El modelo deberá aprender a predecir la cantidad de rastros futuros serán dejados por los fantasmas en ventanas de 3, 5, 10 y 15 minutos posteriores, a partir de la vela siguiente a cada aparición. Esto significa que a cada nueva reubicación del fantasma, se estimará nuevamente el número de rastros dejados en todas esas ventanas de tiempo futuro.

> Ejemplo. Si el fantasma aparece a la media noche en punto, cuántos movimientos hacia afuera del rango actual de precio se estima hasta la media noche y 3 minutos? Y hasta la media noche y 5? etc.

> La data de entrenamiento es de abril a junio: Unidad 5/Proyecto /2026_Abril-Junio.csv  
> La data de testeo es la del mes de julio (1 a 24 de julio): Unidad 5/Proyecto/2026_07_24.csv

> Su script extractor de características deberá tomar todos los niveles de liquidez a partir de la estructura previa a la vela actual, mediante la función Replay: [ítems 1–11]

> Trate de optimizar el algoritmo de extracción de características desde el principio.

> Usando la función Replay en gráfica de 1 minuto, primero se observa la aparición del fantasma. Luego de eso, se toma la distancia del promedio de precio de vela donde está el fantasma con respecto a todos los niveles de liquidez más cercanos para al menos 3 temporalidades distintas: una pequeña (1 minuto), una mediana (10 minutos) y una grande (1 hora).

> Convertir la unidad de precio a la unidad PIP.

> Ese conjunto de características de los indicadores en al menos 3 temporalidades será un registro que se almacena en la tabla de datos. A añadir columnas con información adicional como ATR de 1 minuto, volumen de 1 minuto, EMA(9) del volumen de 1 minuto, etc. Metadato como la fecha, hora y minuto cuando ocurre no se usa para entrenar modelo. Servirá para validar en la fase de testeo.

> El indicador publicado en …/Ghosts_in_swings.txt muestra donde el fantasma deja los rastros. Necesita una implementación idéntica … Usar Replay … etiquetas 1.

> Normalizar o estandarizar los datos y guardar los parámetros … para los testeos.

> Entrenar el modelo y guardar el modelo entrenado. Cargar el modelo entrenado para el testeo. Comparar los resultados obtenidos con el etiquetado automático.

> Evaluar el modelo predictivo a partir de la data de testeo.

> Preparar una presentación del extractor … features … resultados … demostrar las predicciones al final … carga del modelo y de la tabla de features …

> Las exposiciones son grupales y deben durar hasta 10 minutos.

> … LSTM … no se utiliza CNN … queda opcional … Sugiero primero probarlo sin capas convolucionales …

---

*Fin del audit DOCX v1.0. Nada del escrito debe considerarse “opcional por omisión” salvo los condicionales 9/11 y CNN.*
