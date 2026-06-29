# 0021 — Notas del profesor: volatilidad y ruido de estructura (Mxwll/SMC)

> Backlog de indicaciones del profesor para implementar **una por una**. Cada
> ítem queda como pendiente hasta validarse visualmente + tests verdes + commit.
> Orden de ataque sugerido de arriba hacia abajo.

---

## Estado de los ítems

- [~] **A. Filtro por volatilidad** — En zonas de baja volatilidad mostrar (casi)
  ninguna etiqueta/indicador. Objetivo doble del profe: mejor visualización
  (menos saturación) y mejor rendimiento. Idea: medir volatilidad local (ATR
  relativo, o rango de la pierna vs ATR) y suprimir etiquetas cuyo movimiento
  asociado esté por debajo de un umbral.
  PARCIAL: aplicado a estructura (CHoCH/BoS) en ORDEN 1. Falta extender a swings
  y tomas de liquidez (ORDEN 2).

- [ ] **B. CHoCH interno vs externo bien diferenciado** — Confirmar que I-CHoCH
  (interno, intSens) y CHoCH (externo, extSens) se distinguen en cálculo Y en
  render. Estado actual: SÍ se diferencian en cálculo (`I-CHoCH`/`CHoCH`) y en
  fuente del overlay, pero ver ítem C (son demasiados).
  - **REQUISITO LITERAL (confirmado con captura TradingView 2026-06-29):** la
    distinción debe ser con el TEXTO exacto en pantalla, no con sutilezas
    (color/fuente). Internos = `I-CHoCH` / `I-BoS`; externos = `CHoCH` / `BoS`.
    VERIFICADO: el overlay Mxwll ya dibuja esos strings literales
    (`-text => $s->{label}` con label `I-CHoCH`/`CHoCH`/`I-BoS`/`BoS`). Esto YA
    se cumple en Mxwll. Pendiente: confirmar que aplica igual a EQH/EQL (ítem G)
    y a cualquier otra etiqueta interna/externa.

- [x] **C. CHoCH solo en cambio real de estado (3 estados)** — El profe define 3
  estados de mercado: **alcista, bajista, rango lateral**. Dice que hay mucho
  ruido en 1m (varios CHoCH muy juntos) porque NO se está mostrando "solo cuando
  cambia de estado". Hay que introducir el estado *rango lateral* y emitir CHoCH
  únicamente en transiciones reales de estado, no en cada cruce de nivel.
  HECHO (ORDEN 1): estado lateral por volatilidad; I-CHoCH 1m 1056->542.

- [ ] **D. Toma de liquidez vinculada a un nivel** — (TÉRMINOS A VERIFICAR) El
  profe dice que "la toma de liquidez depende del nivel" y que lo que él ve es
  que NO está vinculada con ningún nivel; sugiere que "tal vez falta poner un
  nivel". Pendiente confirmar a qué se refiere exactamente: probablemente que
  los eventos de barrido/toma (SWEEP/GRAB/RUN del módulo Liquidity, o los
  marcadores del Mxwll) deberían dibujarse anclados al nivel BSL/SSL/EQH/EQL que
  se está tomando, no sueltos. VERIFICAR con el profe el término y el indicador
  concreto antes de tocar nada.

- [ ] **E. Demasiados BSL (¿order block?)** — (TÉRMINOS A VERIFICAR) El profe
  dice que se están mostrando "mucho BSL o algo así" y que "deberíamos poner un
  order block o algo así". Pendiente confirmar: si se refiere a que hay
  demasiadas líneas BSL (Buy Side Liquidity) y que en su lugar / además habría
  que mostrar order blocks, o reducir la cantidad de BSL. CONFIRMAR términos
  exactos (BSL vs otra cosa) y qué espera ver antes de implementar.

- [ ] **F. Demasiadas etiquetas de toma de liquidez (mostrar solo relevantes)** —
  El profe dice que SWEEP/GRAB/RUN están muy aglomeradas; mostrar solo las más
  relevantes. Liga con A (volatilidad) y con F2.

- [ ] **F2. SWEEP/GRAB/RUN deben basarse en HH/HL/LH/LL** — El profe dice que
  estas etiquetas (sweep/grab/run) deben anclarse a los pivotes de estructura
  (HH, HL, LH, LL), no calcularse independientes. Hoy el módulo Liquidity detecta
  sus propios swings/niveles BSL/SSL aparte de los HH/HL/LH/LL del Mxwll/SMC.
  Hay que vincular la toma de liquidez a esos pivotes nombrados.

- [ ] **F3. RUN (y sweep/grab) a veces mal ubicadas o ausentes** — El profe nota
  que RUN a veces está bien, a veces mal, a veces no aparece donde debería.
  Probablemente consecuencia de F2 (no estar ancladas a HH/HL/LH/LL). Revisar
  la FSM de `Liquidity.pm` tras vincular a pivotes.

- [ ] **G. EQH/EQL: distinguir internos vs externos** — Igual que la estructura,
  el profe quiere EQH/EQL internos y externos diferenciados. Hoy `Liquidity.pm`
  produce EQH/EQL con un solo `eqhl_size`. Habría que generar dos conjuntos
  (interno con size pequeño, externo con size grande) y distinguirlos en render.

- [ ] **H. EQH/EQL: los más largos horizontalmente = más importantes** — Las
  líneas EQH/EQL largas (pivotes lejanos en el tiempo) son más relevantes; las
  cortas dan menos info. Idea: filtrar/atenuar las cortas, o resaltar las largas
  (grosor/opacidad según la distancia horizontal entre los dos pivotes del par).

- [ ] **I. FVG: confirmar que existe y cómo encenderlo** — VERIFICADO (ver
  diagnóstico). SÍ existe FVG, en DOS sitios:
    1. `Market/Indicators/SMC_Structures.pm` + overlay SMC → capa **SMC**.
    2. `Market/Indicators/Mxwll_Suite.pm` + overlay Mxwll (elemento `FVG`) → capa **Mxwll**.
  PROBLEMA UX: el FVG de Mxwll está activo por defecto dentro de la capa pero NO
  hay checkbutton individual en la UI para encender/apagar solo FVG (los
  elementos STRUCTURE/SWINGS/OB/FVG/AOE/FIBS del Mxwll no tienen toggles en
  `market.pl`, solo el toggle de capa completa 'Mxwll'). Falta exponer esos
  sub-toggles, o documentar que FVG se ve al activar la capa Mxwll (o SMC).

- [ ] **J. Debe haber lo del "canal"** — (TÉRMINOS A VERIFICAR) El profe menciona
  que debe haber "lo del canal". Pendiente confirmar a qué se refiere: lo más
  probable es un **canal de tendencia** (líneas paralelas que envuelven el
  movimiento entre swings), pero podría ser otra cosa (p.ej. premium/discount
  zones del SMC, o el canal HalfTrend/Range Filter del Strategy Builder).
  Notas de lo que YA existe y podría cubrirlo:
    - `Strategy_Builder` ya calcula HalfTrend y Range Filter (bandas/canal) pero
      NO se renderizan (solo SuperTrend y Order Blocks se dibujan hoy).
    - El módulo Liquidity tiene `zone_3` (trendlines/channels: último swing
      high/low como límites de canal) calculado pero sin render dedicado.
  CONFIRMAR con el profe el término exacto y en qué indicador lo quiere antes de
  implementar.

---

## Diagnóstico técnico (verificado en código + datos, 2026-06-29)

### Sobre B (diferenciación interno/externo)
`Market/Indicators/Mxwll_Suite.pm` → `_update_structure()`:
- Externo usa `extSens=25`, etiqueta `BoS` / `CHoCH`.
- Interno usa `intSens=3`, etiqueta `I-BoS` / `I-CHoCH`.
- El overlay `Market/Overlays/Mxwll_Suite.pm` dibuja internos con fuente
  `Helvetica 7` y externos con `Helvetica 8 bold`.
- **Conclusión: SÍ están diferenciados.** El problema no es la diferenciación,
  es el volumen de I-CHoCH (ver C).

### Sobre C (ruido de CHoCH)
Conteo real sobre `Data/2026_06_29.csv`:

| TF  | velas | BoS | CHoCH | I-BoS | I-CHoCH | total |
|-----|-------|-----|-------|-------|---------|-------|
| 1m  | 27937 | 152 | 173   | 1010  | 1056    | 2391  |
| 5m  | 5589  | 28  | 36    | 186   | 226     | 476   |
| 15m | 1864  | 12  | 15    | 71    | 68      | 166   |

En 1m hay **1056 I-CHoCH** (separación mediana 20 velas, mínimo 1). Eso es el
ruido que ve el profe.

**Causa raíz:** el modelo actual solo tiene 2 estados de tendencia vía la
variable `moving` (+1 alcista / -1 bajista). La etiqueta se decide así:
- cruce al alza de `upaxis`: si `moving < 0` → CHoCH, si no → BoS.
- cruce a la baja de `dnaxis`: si `moving > 0` → CHoCH, si no → BoS.

Es decir, **CHoCH = primer cruce que invierte la dirección anterior**. NO existe
el estado "rango lateral", así que en mercados laterales (1m) el precio cruza
arriba/abajo repetidamente y cada inversión genera un CHoCH. Por eso aparecen
tan juntos. Coincide exactamente con lo que dice el profe: "no se muestran solo
cuando cambia de estado".

**Esto viene heredado del .pine de Mxwll** (su `bigData.get("moving")` es
igualmente binario), así que es una mejora nuestra sobre el indicador base, no
un bug de portabilidad.

### Direcciones de solución para C (a decidir con el usuario antes de codear)
1. Introducir un 3er estado `lateral` (rango): no emitir CHoCH dentro de rango;
   solo al salir del rango hacia alcista/bajista confirmado.
2. Definir "rango" por volatilidad/compresión (liga con el ítem A): si la pierna
   o el ATR local es pequeño, el mercado está lateral y se silencian CHoCH.
3. Alternativa mínima: de-duplicar CHoCH cercanos (cooldown de N velas o de
   X·ATR de distancia). Más simple pero menos "correcto" que el estado lateral.

### Sobre B (texto literal I-CHoCH)
VERIFICADO sobre `Data/2026_06_29.csv` (5m): el indicador genera los 4 labels
EXACTOS `BoS`, `CHoCH`, `I-BoS`, `I-CHoCH`, y el overlay los dibuja con
`-text => $s->{label}`. El texto literal YA existe. El usuario no lo veía porque
los internos usan fuente diminuta (`Helvetica 7`) y en 1m hay 1056 I-CHoCH
amontonados → mancha ilegible. Es un problema de RUIDO+LEGIBILIDAD (ítems C/A),
no de falta de texto.

---

# =====================================================================
# PLAN DE EJECUCION — una tarea a la vez, en este orden
# =====================================================================
# Para cada tarea: (1) implementar solo eso, (2) verificacion analitica con
# script en scratch/, (3) `perl -I. -c` de archivos tocados + `prove -l t`,
# (4) validar visual en 1m y en 1h/2h, (5) commit + push a backup y origin.
# No avanzar a la siguiente sin tests verdes.

## ORDEN 1 — Tarea C+A juntas: estado de mercado (3 estados) por volatilidad
**[HECHO 2026-06-29 — commit pendiente]**
**Por que primero:** es la queja central (ruido de CHoCH) y A (volatilidad) es
el mecanismo natural para definir "rango lateral". Resolver C con volatilidad
mata dos pajaros.
**Diseno:**
- En `Mxwll_Suite::_update_structure` (o un helper nuevo `_market_state`),
  añadir un 3er estado al `moving`: `+1 alcista`, `-1 bajista`, `0 lateral`.
- Definir "lateral" por volatilidad/compresion: usar el ATR ya disponible
  (`_atr_last`) vs el rango de la pierna (|upaxis - dnaxis|). Si la pierna es
  pequeña respecto al ATR (umbral configurable, p.ej. rango < k·ATR), el mercado
  esta lateral.
- Regla de emision: CHoCH SOLO en transicion real de estado
  (lateral→alcista, lateral→bajista, alcista→bajista, bajista→alcista). Dentro
  de un mismo estado o cruces dentro de rango → no emitir (o degradar a nada).
- Parametros nuevos en `new()`: `state_atr_factor` (umbral de rango lateral).
- Aplica a internos y externos por igual (cada uno con su `moving`).
**Riesgo/!:** cambia el conteo de CHoCH → ajustar fixtures de `t/22` y
documentar la nueva semantica. Verificar que en 1h/2h siguen saliendo CHoCH
legitimos y que en 1m bajan drasticamente.
**Archivos:** `Market/Indicators/Mxwll_Suite.pm`, `t/22-mxwll-suite.t`.

**RESULTADO (verificado sobre Data/2026_06_29.csv, default factor=2.0):**
- Parametro nuevo `state_atr_factor` (default 2.0; 0 desactiva el filtro).
- Estado de mercado por overlay `_ext`/`_int`: +1 alcista, -1 bajista, 0 lateral.
- Un break solo emite etiqueta si |upaxis-dnaxis| >= factor*ATR; si no, es
  rango lateral (se consume el cruce, sin etiqueta).
- Conteo I-CHoCH en 1m: 1056 -> 542 (~49% menos ruido).
- Estructura EXTERNA preservada: CHoCH 173->171, BoS 152 (intactos).
- 4 tests nuevos en t/22 (bloque 9). Suite completa 753 tests PASS.

## ORDEN 2 — Tarea A (visual): suprimir etiquetas en baja volatilidad
**Diseno:** filtro de render/calculo que omite etiquetas cuyo movimiento
asociado < umbral de volatilidad local. Si ORDEN 1 ya silencia CHoCH laterales,
aqui se extiende a swings (HH/HL/LH/LL) y a tomas de liquidez poco significativas.
Preferible filtrar en el indicador (menos items = mejor rendimiento) y exponer
un parametro.
**Archivos:** `Market/Indicators/Mxwll_Suite.pm` (+ Liquidity si aplica).

## ORDEN 3 — Tarea F2: SWEEP/GRAB/RUN anclados a HH/HL/LH/LL
**Por que clave:** el profe dice que la toma de liquidez debe basarse en los
pivotes nombrados; hoy `Liquidity.pm` detecta sus propios swings/niveles
(BSL/SSL) independientes de los HH/HL/LH/LL del Mxwll. Esto explica F (aglomerado)
y F3 (RUN mal ubicado/ausente).
**Diseno (a decidir):** dos caminos —
  (a) Hacer que `Liquidity` use los mismos pivotes que `Mxwll`/`SMC`
      (compartir detector de swings), o
  (b) Vincular cada evento sweep/grab/run al nivel BSL/SSL del pivote nombrado
      mas cercano y dibujar el ancla.
**Archivos:** `Market/Indicators/Liquidity.pm`, overlay Liquidity, posible
refactor compartido de pivotes.

## ORDEN 4 — Tarea F + F3: mostrar solo tomas relevantes + arreglar RUN
Tras F2, filtrar por relevancia (volatilidad/tamaño del barrido) y revisar la
FSM de RUN/SWEEP/GRAB para corregir ubicaciones. Verificacion analitica como se
hizo antes con la tabla de SWEEP.
**Archivos:** `Market/Indicators/Liquidity.pm`, `Market/Overlays/Liquidity.pm`.

## ORDEN 5 — Tarea D: toma de liquidez vinculada a un nivel (ancla visual)
(TERMINOS A CONFIRMAR con profe.) Probablemente se resuelve junto con F2/F3:
dibujar el marcador anclado al nivel tomado (linea al BSL/SSL/EQH/EQL).
**Archivos:** overlay Liquidity.

## ORDEN 6 — Tarea G: EQH/EQL internos vs externos (texto literal)
**Diseno:** hoy `Liquidity` usa un solo `eqhl_size`. Generar DOS conjuntos:
interno (size pequeño, p.ej. 3) y externo (size grande, p.ej. 25), y etiquetar
LITERAL en pantalla: externos `EQH`/`EQL`, internos `I-EQH`/`I-EQL` (mismo
criterio literal que B). Distinguir en el overlay.
**Archivos:** `Market/Indicators/Liquidity.pm`, `Market/Overlays/Liquidity.pm`,
`t/10-liquidity.t`.

## ORDEN 7 — Tarea H: EQH/EQL largos = mas importantes
**Diseno:** medir la distancia horizontal del par (|idx_b - idx_a|). Resaltar
los largos (mayor grosor/opacidad) y atenuar/filtrar los cortos por debajo de un
umbral configurable.
**Archivos:** `Market/Overlays/Liquidity.pm` (+ getter de distancia en indicador).

## ORDEN 8 — Tarea E: demasiados BSL / order blocks (TERMINOS A CONFIRMAR)
Esperar confirmacion del profe. Probable: reducir densidad de BSL y/o mostrar
order blocks asociados. Liga con el modulo de order blocks ya existente en Mxwll
(`high_blocks`/`low_blocks`) y Strategy.
**Archivos:** por definir tras confirmar.

## ORDEN 9 — Tarea I (UX): exponer sub-toggles de la capa Mxwll
**Diseno:** añadir checkbuttons individuales en `market.pl` para los elementos
del Mxwll (STRUCTURE, SWINGS, OB, FVG, AOE, FIBS), igual que ya existen para
Liquidez (BSL/SSL/EQH/...). Reusar `make_liq_element_toggle` o crear
`make_mxwll_element_toggle`. Asi el FVG (y cada elemento) se enciende/apaga solo.
**Archivos:** `market.pl`, `Market/UI/Callbacks.pm`.

---

## Notas transversales de implementacion
- **Diferenciacion interno/externo SIEMPRE con TEXTO literal** (`I-CHoCH`,
  `I-BoS`, `I-EQH`, `I-EQL`), no solo color/fuente. Ya cumplido en CHoCH/BoS;
  replicar en EQH/EQL (G).
- No romper la diferenciacion interno/externo ya existente.
- Mantener salida determinista y `prove -l t` verde; ajustar fixtures cuando
  cambie la semantica, documentando el porque.
- Validar visualmente en 1m (ruido maximo) y en 1h/2h (deben seguir saliendo
  estructuras legitimas).
- Cada tarea: commit independiente + push a `backup` y `origin`.
