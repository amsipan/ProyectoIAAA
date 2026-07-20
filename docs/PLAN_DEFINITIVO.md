# Plan definitivo del proyecto (meta de datos y modelos)

**Fuente canónica de la meta ML y de sus restricciones causales.** Este documento explica hacia dónde llegará el proyecto y por qué cada capa existe. **No es la cola operativa inmediata de indicadores.**

> **Prioridad operativa confirmada por Bryan el 2026-07-19:** terminar primero la reforma de indicadores. Leer `docs/BRUJULA_CONTINUIDAD.md` para el orden vigente y `docs/MEMORIA_RECUPERADA_019f6e8d.md` para la historia completa. El orden actual es: cierre formal de Liquidity §4 → concurrencia §5 → DIY §6 → Volume Profile §7 → Anchored VWAP §8 → volver a este plan de modelos.

| Campo | Valor |
|-------|--------|
| **Ruta** | `docs/PLAN_DEFINITIVO.md` |
| **Última actualización** | 2026-07-19 |
| **Rama de trabajo típica** | producto oficial en `main` / features tipo `feature/liquidity-v2-fsm` |
| **Lista de capas que cargan en runtime** | `docs/PRODUCTO_OFICIAL.md` |
| **Detalle Liquidity** | `docs/LIQUIDITY_V2.md` |
| **Legacy (no usar)** | `docs/LEGACY.md` + archive fuera de git |

Si una conversación contradice el **contrato ML** de este plan, mandan este archivo, `PRODUCTO_OFICIAL.md` y el código. Para la **prioridad operativa inmediata y el checkpoint vivo**, manda `BRUJULA_CONTINUIDAD.md`, confirmada por Bryan. Los planes bajo `.grok/sessions/` son evidencia histórica, no estado vivo del repo.

---

## 0. La meta (léelo siempre antes de tocar código)

### 0.1 Qué es y qué no es esta app

| Es | No es |
|----|--------|
| Una plataforma tipo TradingView en **Perl/Tk** que genera **etiquetas y features limpios** | Un robot de trading “para ganar dinero” como fin del curso |
| El **generador de observaciones** para entrenar modelos del profe | El producto final = solo indicadores bonitos en pantalla |
| Base académica (IA / ML, EPN 2026A) con rúbrica de indicadores **y** de modelos | Un clon TV 1:1 de cada script de la comunidad |

**Frase del profe (clase liquidez):**  
> *Solo se puede predecir si hay liquidez dentro de la estructura.*  
Estructura sola no basta. Indicadores sin eventos de liquidez no alimentan bien al modelo.

### 0.2 Fin último del semestre (pipeline de modelos)

Los indicadores **no son el destino**. Son el medio para armar datos y entrenar:

```
┌─────────────────────────────────────────────────────────────┐
│  APP (Perl/Tk) — lo que construimos ahora                   │
│  Chart + Replay + capas oficiales (SMC, ZZ, Fib, Liq, …)    │
│  → observaciones / eventos etiquetados en el tiempo         │
└───────────────────────────┬─────────────────────────────────┘
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  TABLA DE EVENTOS (solo filas cerca de liquidez)            │
│  ~50 columnas de features numéricas                         │
│  Precios en PIPS + normalización Z                          │
│  Train ≈ abr → inicios jun  |  Test = junio (split temporal)│
│  time / event_id = METADATO (archivo aparte)                │
└───────────────────────────┬─────────────────────────────────┘
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  t-SNE (atemporal)  →  2–3 dims, clusters, hiperparámetros  │
│  GMM  (atemporal)   →  P(sweep)+P(grab)+P(run)=1 por evento │
│                       actuar si max(P) ≥ ~85%               │
└───────────────────────────┬─────────────────────────────────┘
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  HMM (temporal, solo etiquetas)                             │
│  · modelo INTERNO  +  modelo EXTERNO                        │
│  · secuencia por vela (1m / 5m / 15m según TF)              │
│  Presentación: accuracy, precisión, ROC, matriz confusión   │
└─────────────────────────────────────────────────────────────┘
```

**Implicación práctica para cada PR:**

1. ¿Esta capa produce **etiquetas o features estables** exportables?  
2. ¿Reduce **ruido** (overfit visual = basura para el modelo)?  
3. ¿Respeta **replay** (sin futuro) y **separación cálculo/render**?  
4. Si no aporta al pipeline de arriba, **no es prioritario**.

### 0.3 Rúbrica y plazos (audio IndicacionesExaProy + sílabo)

| Ítem | Dato |
|------|------|
| Proyecto | **35 pts**: indicadores **20/35** + modelos/presentación **15/35** |
| Indicadores | Misma importancia inicial entre capas (ningún “peso” especial en rúbrica al inicio) |
| Modelos | Presentación de resultados y métricas (cap. 4 del libro: precisión, ROC, confusión) |
| Examen | **Lunes 27 de julio 2026** — cálculo **o** código (tensores del bimestre) |
| Quizzes / exámenes | ~30% quizzes; ~35% exámenes del curso (según sílabo) |

### 0.4 Reglas del dataset (no negociables cuando llegue la fase modelos)

1. **Filas = eventos cerca de un nivel de liquidez**, no una fila por cada minuto.  
2. **~50 columnas** desde indicadores (distancias, flags, ATR en bins, volumen, etc.).  
3. **PIPS** para estandarizar precios entre activos.  
4. **Z-score** (capítulo 1) sobre features.  
5. **t-SNE y GMM sin tiempo**: ni timestamp ni índice 1,2,3… en la tablota de train.  
6. **HMM sí usa tiempo**: solo **secuencias de etiquetas**; HMM **interno** y **externo** aparte.  
7. Fib “probable”: desde el **último impulso del ZigZag externo**.  
8. Procesar **toda** la historia de entrenamiento (bloques), no solo lo visible en el overlay.
9. **Congelar las features en `sweep_index`** (primera toma del nivel) usando únicamente información disponible hasta esa vela. La resolución posterior aporta la etiqueta histórica `sweep|grab|run`, pero jamás puede recalcular o contaminar las variables de entrada.
10. Ajustar PIPS/Z-score y cualquier transformación solo con el período de **train**; aplicar esos parámetros sin reajustar al período de test.

### 0.5 Eventos de liquidez (etiquetas supervisadas)

| Evento | Definición (profe) | Uso en modelos |
|--------|--------------------|----------------|
| **Sweep** | Toma liquidez en **1–2 velas** y **regresa** (manipulación) | Clase GMM / etiqueta |
| **Grab** | Toma más lenta (**~3–8 velas**) y regresa | Clase GMM / etiqueta |
| **Run** | Toma liquidez y **avanza** (movimiento verdadero; puede retest) | Clase GMM / etiqueta; mirar **futuro** al etiquetar histórico |

### 0.6 Las 7 zonas de liquidez (clase 16-jun)

| # | Zona | Estado en producto |
|---|------|--------------------|
| 1 | Equal Highs / Equal Lows | Liquidity v2 (EQH/EQL) |
| 2 | Arriba swing high / abajo swing low (stops → BSL/SSL) | Liquidity v2 |
| 3 | Trendlines y canales | Parallel Channel oficial; features v1.5 |
| 4 | Order blocks (+ doji / envolvente en zona) | SMC Pro OBs; flags v1.5 |
| 5 | Soporte / resistencia | Estructura HTF; v1.5 |
| 6 | Fibonacci (p.ej. ~61.8) | Fib tool + último impulso ZZ ext |
| 7 | OHLC diario/semanal **previo** | HLD / proyección; v1.5 |

**Interno vs externo (HMM):** externa = majors HTF; interna = picos LTF entre majors; intermedio = entre major high y major low. Alta probabilidad al salir de externa hacia interna (o con confirmación).

**Multi-TF:** estructura limpia en HTF (1h/4h/D/W); ejecución y barridos en LTF (1m/5m/15m). ZigZag debe ser correcto en el pivote real (HH/HL/LL/LH), no “saltar” con left/right ciego.

---

## 1. Cómo usar este plan (agentes y humanos)

### Lectura obligatoria al iniciar sesión

1. **`docs/PLAN_DEFINITIVO.md`** ← este archivo (dirección + meta modelos).  
2. **`docs/PRODUCTO_OFICIAL.md`** — qué hay cargado en runtime **ahora**.  
3. **`docs/CONSTITUTION.md`** — cálculo ≠ render, replay, rendimiento.  
4. Spec/task concreta si existe en `specs/` / `tasks/`.  
5. Detalle de capa actual (ej. `docs/LIQUIDITY_V2.md`).

### Checklist antes de implementar cualquier feature

- [ ] ¿Cómo se convierte en **columna de la tablota** o **etiqueta de secuencia**?  
- [ ] ¿Puede exportarse sin Tk (`Indicators/*.pm`)?  
- [ ] ¿Respeta replay (sin velas futuras)?  
- [ ] ¿Evita reactivar **legacy** (`docs/LEGACY.md`)?  
- [ ] ¿UI paso a paso (capa OFF por defecto / on-demand)?  
- [ ] ¿Tests sintéticos o de regresión en `t/`?

### Qué no hacer

- No reactivar código de `ProyectoIAAA_LEGACY_ARCHIVE` “porque ya estaba”.  
- No meter tiempo/índice en el train de t-SNE/GMM.  
- No priorizar indicadores de adorno que no den features.  
- No entrenar HMM dentro del render del chart.  
- No escribir bajo `Downloads\Proyecto` (si aplica política del usuario: copiar al repo).

---

## 2. Estado del producto oficial (2026-07-19)

Runtime (`ChartEngine`):  
`smc_pro`, `smc_fvg`, `hld`, `pchan`, `zigzag`, `fib`, **`liq`**.

| Pieza | Rol hacia modelos | Estado |
|-------|-------------------|--------|
| Chart + TF + Replay | Validar eventos sin futuro | ✅ geometría causal: head ~80% con slots vacíos; grid/velas/overlays alineados incluso en zoom extremo |
| SMC Pro | BOS/CHoCH, swings, OBs, inducement | ✅ |
| Structures + FVG | Desequilibrio / imán | ✅ |
| HLD 4h/D | Niveles HTF (zona 7 / externos) | ✅ |
| Parallel Channel | Zona 3 (extremos) | ✅ herramienta |
| ZigZag ext / int | Dirección limpia multi-TF; Fib impulse | ✅ |
| Fib Retracement | Zona 6; niveles de reacción | ✅ herramienta TV |
| **Liquidity v2** | Zonas 1–2 + Sweep/Grab/Run + **export** | ✅ + labels en plot, Historial, pivotes ZZ acumulados, replay |
| Export dataset completo ~50 cols | Tablota train/test | ⏳ fase modelos |
| t-SNE → GMM → HMM | Fin último | ⏳ fase modelos |

Detalle Liquidity: `docs/LIQUIDITY_V2.md`.  

### Contrato definitivo de Replay (no romper)

Replay es una garantía de **causalidad para los indicadores y el dataset futuro**, no solo una animación:

- `causal_end = replay_idx`: OHLC, ATR, timestamps reales, indicadores y overlays nunca leen un índice posterior.
- El head se muestra cerca del 80% mediante **slots lógicos vacíos a la derecha**, nunca con un `x_shift = -20%`.
- `ctrl_zoom_x_shift` queda reservado al residuo subvela del paneo suave.
- Velas, ATR, grid temporal, crosshair y overlays comparten la misma escala X, también cuando `bar_w < 2` y se agrega por píxel.
- El calendario del hueco derecho puede proyectarse desde el último timestamp causal + TF, pero no consulta velas futuras.
- La autoescala Y solo usa datos causales; una vela futura extrema no puede modificar el frame actual.
- Al rebobinar, SMC/FVG/ZigZag/Liquidity se reconstruyen hasta `replay_idx`; Liquidity borra incluso pivotes con índice antiguo si habían sido confirmados usando barras posteriores.
- El overscan del paneo fraccional puede dibujar `end + 1` solo cuando esa vela ya pertenece al prefijo causal; siempre se clampa a `replay_idx`.
- Prueba canónica: `t/38-replay-geometry.t` (52 checks de geometría, render denso, causalidad, escala manual y rewind).

Esto importa para la meta ML: una fuga de futuro en Replay produciría etiquetas/features inválidos y contaminaría train/test.

API ya orientada a modelos:

- `export_liquidity_events()` — filas de eventos resueltos  
- `get_observation_stream()` — etiquetas por índice de vela  

---

## 3. Roadmap ML posterior (pausado mientras se termina Fase 2 de indicadores)

Esta sección conserva el pipeline de datos/modelos que deberá retomarse más adelante. **No es la cola operativa actual.** La prioridad vigente y su checkpoint están en `docs/BRUJULA_CONTINUIDAD.md`.

### Cola operativa actual de indicadores

1. Cerrar formalmente Liquidity §4: volumen `v1m/v5m/v15m`, INT/EXT, reconciliación `Acceptance/Reclaimed`, semántica Grab y export preliminar.
2. Concurrencia Liquidity→estructura §5.
3. DIY Strategy Builder §6, priorizando Supply/Demand y confluencia con OB.
4. Advanced Volume Profile §7.
5. Anchored VWAP §8.
6. Volver entonces al pipeline ML de la tabla siguiente.

### Pipeline ML preservado

| Orden futuro | Hito | Criterio de hecho | Meta modelos |
|--------------|------|-------------------|--------------|
| **A — CUMPLIDO 2026-07-19** | Liquidity v2 MVP estable | ✅ FSM resumida + UI + tests; validación visual NQ; Replay causal | Etiquetas sweep/grab/run fiables |
| **B — PAUSADO HASTA CERRAR INDICADORES** | Liquidity v1.5 (7 zonas / features) | Distancias a canal, OB, Fib, D/W; INT/EXT | Más columnas de la tablota |
| **C** | Export batch histórico | CSV/JSON eventos + features en PIPS; split temporal | Dataset listo para train/test |
| **D** | t-SNE + GMM | Clusters + P≥85%; sin columnas de tiempo | Probabilidades de evento |
| **E** | HMM int + HMM ext | Secuencias de etiquetas; métricas presentación | Entrega 15/35 modelos |

Cuando Bryan autorice volver a modelos, construir B como capa de extracción *headless*. Las zonas 1–2 vienen del MVP de Liquidity; las zonas 3–7 deben convertirse en features numéricas reutilizando las capas oficiales, sin depender de Tk ni de herramientas manuales. No empezar t-SNE/GMM hasta cerrar B y generar el export batch C.

Ramas típicas: `feature/<capa>-…` desde stack oficial limpio. No mezclar legacy.

---

## 4. Contrato de datos (recordatorio)

```perl
# Evento (fila candidata GMM) — time/event_id solo en metadato
{
  event_id, time, index,          # metadato
  level_kind, level_price, side,
  kind => 'internal'|'external',
  event => 'sweep'|'grab'|'run',
  features => { ... ~50 nums en pips/z ... },
}

# Por vela (HMM)
{
  index,
  labels => [ 'BSL', 'SWEEP', 'BOS', ... ],
  kind   => 'internal'|'external'|'intermediate',
}
```

Procesar historia completa en **bloques** al generar la tablota (el overlay de pantalla no es el dataset).

---

## 5. Fuentes del profe (para no reinventar)

| Fuente | Contenido |
|--------|-----------|
| PDF 2ª fase | `docs/material_profesor/Especificacion_Proyeto_2a_Fase.pdf` (+ texto extraído) |
| Clase liquidez 16-jun | Lumina sesión `1d3e610b36ae` (+ live `066e585f3b5c`) |
| SMC estructura 15-jun | Lumina `a21ce910fecc` |
| Indicaciones examen/proyecto | Transcript VPS `IA_IndicacionesExaProy-20260719-051032` |
| HMM / Viterbi / Markov | Clases mayo–junio en Lumina; specs `0011`, `0012` |
| Pine de referencia | `docs/reference_indicators/` (no verdad absoluta; capturas profe mandan) |

---

## 6. Mapa de documentación

| Documento | Rol |
|-----------|-----|
| **`docs/PLAN_DEFINITIVO.md`** | **Dirección del proyecto + meta modelos (este archivo)** |
| `docs/PRODUCTO_OFICIAL.md` | Capas que existen en runtime **hoy** |
| `docs/UI_FASE_ACTUAL.md` | Cómo usar la UI paso a paso |
| `docs/LIQUIDITY_V2.md` | Spec técnica Liquidity |
| `docs/LEGACY.md` | Qué está fuera del repo y no se reactiva |
| `docs/CONSTITUTION.md` | Principios de ingeniería |
| `docs/ARCHITECTURE.md` | Capas técnicas |
| `docs/ROADMAP.md` | Histórico de entregas PDF; **la estrategia vigente está aquí** |
| `docs/AI_CONTEXT.md` | Resumen rápido; debe apuntar a este plan |
| `AGENTS.md` | Bootstrap de agentes; debe listar este plan **primero** |
| `specs/` / `tasks/` | Trabajo SDD por ticket (detalle táctico) |

---

## 7. Criterio de “¿vamos bien?”

Vas bien si:

1. Cada capa oficial reduce ruido o añade una observación real del profe.  
2. Liquidity (y el resto) pueden **exportar** sin la GUI.  
3. El dataset futuro será de **eventos de liquidez**, no de velas ruidosas al azar.  
4. Sabes en qué casilla del pipeline estás (indicadores → tabla → t-SNE/GMM → HMM).  
5. No has reintroducido legacy roto.

Estás desviado si:

- Optimizas solo “que se vea como TV” sin etiquetas exportables.  
- Generas miles de niveles basura (el modelo aprenderá ruido).  
- Mezclas fase modelos dentro del paint del canvas.  
- Olvidas split temporal y metes “futuro” en train.

---

## 8. Resumen en una frase

> **La app es la fábrica de observaciones limpias; el proyecto se aprueba de verdad cuando esas observaciones alimentan t-SNE → GMM → HMM con métricas presentables.**

Mantén esa frase en la cabeza en cada commit.
