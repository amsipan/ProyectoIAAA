# Recuperación de memoria — Proyecto IA

**Sesión reconstruida:** `019f6e8d-1aa4-7d90-bd50-4b4f47dee7aa`  
**Título original:** `PROYECTO IA 18 DE JUNIO 2026`  
**Fecha de reconstrucción:** 2026-07-19  
**Propósito:** devolver a un modelo nuevo la historia, decisiones, estado real y siguiente paso del proyecto sin reactivar código viejo ni confundir la ruta de indicadores con la ruta posterior de modelos.

---

## 1. Resultado ejecutivo

La sesión completa fue localizada y auditada desde el inicio hasta el último mensaje. La pérdida de contexto ocurrió por varias compactaciones y por el cambio de Grok 4.5 a `kiro/gpt-5.6-sol`, pero el historial, los cuatro segmentos compactados, los checkpoints, el plan conversacional y los resultados de subagentes permiten reconstruir la continuidad.

El dictamen vigente es:

1. El producto oficial ya incluye chart/Replay, SMC Pro, Structures+FVG, HLD, Parallel Channel, ZigZag externo e interno, Fibonacci nativo y Liquidity v2.
2. Liquidity v2 fue aceptado como **MVP/hito A**, junto con la reconstrucción causal de Replay y una suite oficial **seleccionada** de **558/558 pruebas**.
3. Eso **no** significa que el bloque académico de Liquidity esté totalmente terminado. Como pendientes confirmados faltan:
   - volumen multitemporal real por evento: `v1m`, `v5m`, `v15m`;
   - clasificación INT/EXT real por origen estructural/temporal;
   - completar el export (`dist_pips_placeholder`, features y `kind`);
   - reconciliar la FSM resumida actual con los estados formales `Acceptance` y `Reclaimed` del PDF;
   - resolver la diferencia entre la ventana de Grab del PDF (retorno en máximo 3 velas) y la explicación posterior del profesor/clases (indecisión durante varias velas).
   Las siete zonas y la tabla amplia pertenecen al enriquecimiento de features posterior; no deben confundirse con lo ya aceptado como MVP.
4. Después de cerrar y verificar esos requisitos de §4, se implementa la concurrencia determinista Liquidity→BOS/CHoCH/FVG de la §5 del PDF.
5. El siguiente indicador visible que corresponde reformar es **DIY Custom Strategy Builder**, priorizando **Supply/Demand + confluencia con Order Blocks**, no Anchored VWAP.
6. Luego corresponde **Advanced Volume Profile** y, por último, **Anchored VWAP multipivot**.
7. t-SNE, GMM y HMM se preservan como objetivo posterior, pero la última instrucción del usuario fue explícita: **no pasar todavía a modelos; continuar primero la reforma de indicadores**.
8. No se debe implementar nada solo a partir de este documento sin que el usuario lo autorice. La primera acción de cualquier modelo que continúe debe ser inspeccionar el repositorio canónico y preservar su worktree sucio.

La corrección más importante frente a resúmenes anteriores es:

> El final de la sesión no eligió Anchored VWAP como siguiente paso. El orden operativo final fue: completar Liquidity multi-TF + INT/EXT → concurrencia Liquidity–estructura → DIY Supply/Demand → Volume Profile → Anchored VWAP.

---

## 2. Fuentes auditadas y jerarquía de verdad

### 2.1 Sesión Grok

Directorio:

`C:\Users\bryan\.grok\sessions\C%3A%5CUsers%5Cbryan\019f6e8d-1aa4-7d90-bd50-4b4f47dee7aa`

Fuentes principales:

- `chat_history.jsonl`
- `btw_history.jsonl`
- `plan.md`
- `summary.json`
- `compaction\segment_000.md`
- `compaction\segment_001.md`
- `compaction\segment_002.md`
- `compaction\segment_003.md`
- checkpoints y solicitudes de compactación
- salida de revisión independiente de Replay/Liquidity

La sesión contiene aproximadamente 14.588 mensajes internos, 78 mensajes de chat y termina con el modelo `kiro/gpt-5.6-sol`.

### 2.2 Guía del profesor extraída del video del 14 de julio

Fuente principal:

`C:\Users\bryan\Downloads\20260714_164526_extract\ORDEN_PROYECTO_DEFINITIVO.md`

Material asociado:

- `transcript.md`
- `transcript.txt`
- `transcript.chunked.md`
- `frames\`
- `MANIFEST.md`

La transcripción completa tiene aproximadamente 50 minutos y 5.275 palabras. Su regla de interpretación es: cuando respuestas anteriores de IA contradicen la transcripción, manda la transcripción.

### 2.3 Material del profesor

Carpeta de referencia, estrictamente de solo lectura:

`C:\Users\bryan\Downloads\Proyecto`

Fuentes centrales:

- `Especificacion_Proyeto_2a_Fase.pdf`
- `Indicador-zigzag-para-direccion-interna-externa.pdf`
- capturas de configuración de SMC, ZigZag, Fibonacci, Anchored VWAP, Anchored Volume Profile y DIY Strategy Builder
- videos y fuentes Pine de referencia

Nunca modificar, renombrar ni sobrescribir esta carpeta. Los recursos necesarios se copian al repositorio canónico.

### 2.4 Lumina y audio más reciente

Sesiones recuperadas:

- `a21ce910fecc`: SMC, limpieza y fundamento del etiquetado histórico, 15-jun.
- `1d3e610b36ae`: Liquidity/HMM, siete zonas, multi-TF e INT/EXT, 16-jun.
- `47bfe676f0e6`: indicadores y configuraciones, 23-jun.

Audio reciente transcrito mediante VPS/OpenClaw:

`IA_IndicacionesExaProy-20260719-051032`

El audio confirmó la meta del dataset/modelos, el split temporal aproximado, la congelación causal de features y el contexto de entrega/examen.

### 2.5 Jerarquía que debe aplicar el modelo sucesor

No existe un único documento que resuelva todos los temas. Aplicar esta jerarquía por ámbito:

1. **Código actual + `docs/PRODUCTO_OFICIAL.md`:** qué existe y carga realmente en runtime.
2. **`ORDEN_PROYECTO_DEFINITIVO.md`:** dependencias conceptuales entre estructura, ZigZag, Fib, anclas, liquidez y modelos.
3. **PDF formal de segunda fase:** orden y contenido de módulos todavía exigidos como entregables.
4. **Última instrucción del usuario en el chat:** prioridad operativa actual; indicadores antes de modelos.
5. **`docs/PLAN_DEFINITIVO.md`:** objetivo de datos/ML y restricciones causales a preservar para más adelante.
6. **Capturas del profesor:** configuración visual y funcional; prevalecen frente a defaults genéricos del Pine o TradingView.
7. `ARCHITECTURE.md` y `ROADMAP.md` antiguos son históricos donde mencionan módulos legacy ya expulsados; no usarlos para reactivar esos módulos.

---

## 3. Repositorio canónico y advertencia crítica

### 3.1 Ruta correcta

Trabajar únicamente en:

`C:\ia\proyecto_iaaa\Proyecto\ProyectoIAAA`

No trabajar en:

`C:\m1\ia\proyecto_iaaa\Proyecto\ProyectoIAAA`

La copia bajo `C:\m1\ia` está desactualizada y no representa el worktree Git activo.

### 3.2 Estado verificado el 19-jul-2026

Rama:

`feature/liquidity-v2-fsm`

El worktree contiene trabajo sustancial sin commit. Nunca ejecutar `reset --hard`, `clean`, checkout destructivo, rebase, sustitución masiva o copia desde el árbol stale.

Archivos rastreados modificados:

- `AGENTS.md`
- `Market/ChartEngine.pm`
- `Market/Indicators/ZigZag.pm`
- `Market/Panels/ATRPanel.pm`
- `Market/Panels/PricePanel.pm`
- `Market/Panels/Scales.pm`
- `README.md`
- `docs/AI_CONTEXT.md`
- `docs/LEGACY.md`
- `docs/PRODUCTO_OFICIAL.md`
- `docs/ROADMAP.md`
- `docs/UI_FASE_ACTUAL.md`
- `market.pl`
- `t/00-load-and-syntax.t`
- `t/25-replay-select-bar.t`

Diff rastreado verificado:

`15 files changed, 765 insertions(+), 319 deletions(-)`

Archivos sin seguimiento importantes:

- `Data/tv_nq1_15m.csv`
- `Market/Indicators/Liquidity.pm`
- `Market/Overlays/Liquidity.pm`
- `docs/LIQUIDITY_V2.md`
- `docs/PLAN_DEFINITIVO.md`
- `t/32-liquidity-v2.t`
- `t/38-replay-geometry.t`
- `mcps/`

Antes de cualquier cambio, el sucesor debe ejecutar `git status --short --branch`, revisar el diff y determinar qué archivos pertenecen al trabajo aceptado. No debe asumir que un archivo sin seguimiento es descartable.

### 3.3 Commits históricos observados

Los siguientes hashes aparecen en distintas etapas y ramas de trabajo; **no se ha verificado que formen una sola cadena lineal ni que todos sean ancestros de la rama actual**:

- `f760f7b` — sacar legacy del repo a archivo local externo
- `b082b61` — sellar producto oficial y cuarentena de legacy
- `4fde9ad` — eliminar placeholder HTF sobre LTF
- `053d9c0` — Fib unido a p1/p2 y sincronización del checkbox ZZ
- `6a192f6` — selección de pierna ZZ, labels y extensión
- `e67225a` — herramienta Fib estilo TV, retirando auto-ZZ
- `b886209` — primer Fibonacci anclado a pierna externa consolidada
- `9f953d4` — ZigZag interno ZZMTF
- `362c565` — ZigZag externo ChartPrime
- `6382112` — HLD 4h/D
- `b290e30` — Parallel Channel
- `66382ed` — SMC Structures+FVG

### 3.4 Producto oficial

Runtime registrado en `ChartEngine`:

- `smc_pro`
- `smc_fvg`
- `hld`
- `pchan`
- `zigzag`
- `fib`
- `liq`

Archivo legacy externo:

`C:\ia\proyecto_iaaa\Proyecto\ProyectoIAAA_LEGACY_ARCHIVE\`

No reactivar, importar ni conectar al runtime los archivos de ese archive:

- Liquidity antiguo
- `Strategy_Builder`
- `VolumeProfile`
- `AnchoredVWAP`
- `Mxwll_Suite`
- `SMC_Structures` unificado antiguo
- sus overlays y tests legacy

`docs/LEGACY.md` sí permite consultar ideas o lógica histórica como referencia. Si una idea resulta útil, debe reimplementarse en un módulo nuevo, ajustarse al contrato causal actual y cubrirse con pruebas nuevas; nunca se copia el archivo legacy directamente al runtime.

Los próximos módulos deben reconstruirse a partir de las indicaciones actuales del profesor, capturas, PDF y arquitectura oficial, no restaurando código viejo.

---

## 4. Las tres rutas que no deben mezclarse

### 4.1 Ruta A — guía conceptual/dependencias del profesor (14-jul)

Esta fue la guía maestra original recuperada:

1. Chart OHLC, multi-timeframe, Replay y capas de dibujo.
2. SMC, externo antes que interno:
   - BOS/CHoCH;
   - EQH/EQL;
   - Order Blocks;
   - FVG correcto como soporte estructural;
   - trendlines.
3. HLD desde velas históricas relevantes de 4h/D.
4. ZigZag externo primero, luego ZigZag interno multi-TF y un canal vivo.
5. Fibonacci desde un impulso consolidado del ZigZag externo.
6. Pivots missed/fantasmas como anclas, Anchored VWAP hasta 3σ y Anchored Volume Profile.
7. Sweep/Grab/Run solo cuando ya existen niveles de liquidez.
8. Tabla de features → t-SNE → GMM → HMM.

Es un **grafo conceptual**: explica qué información alimenta a qué componente. No debe leerse automáticamente como el orden formal de los últimos entregables del PDF.

### 4.2 Ruta B — orden formal del PDF de segunda fase

En el tramo relevante, el PDF separa:

- §4: módulo integrado SMC + FVG + Liquidity.
- §5: relación estructural y concurrencia Liquidity→BOS/CHoCH/FVG.
- §6: DIY Custom Strategy Builder.
- §7: Advanced Volume Profile.
- §8: Anchored VWAP.

Esta ruta determina el **siguiente entregable visible** después de cerrar el bloque actual. Por eso, en el final vigente, DIY va antes que Volume Profile y Anchored VWAP.

### 4.3 Ruta C — plan futuro de dataset/modelos

`docs/PLAN_DEFINITIVO.md` convierte la app en una fábrica de observaciones:

- filas solo cerca de eventos de liquidez;
- aproximadamente 50 features;
- distancias/magnitudes en pips;
- Z-score ajustado solo con train;
- features congeladas en `sweep_index`;
- futuro usado únicamente para la etiqueta histórica;
- t-SNE/GMM sin columnas de tiempo;
- GMM para `P(sweep)`, `P(grab)`, `P(run)`;
- HMM temporal con secuencias INT/EXT;
- train aproximado abril–inicios de junio y test en junio.

El archivo quedó marcado con “B — EN CURSO: Liquidity v1.5/features” antes de que el usuario corrigiera la prioridad. Esa edición documental no fue revertida. Por ello:

- el plan ML sigue siendo válido como propósito a largo plazo;
- **no es la cola operativa inmediata**;
- la última instrucción del usuario manda: continuar indicadores antes de entrenar modelos.

---

## 5. Guía original detallada del profesor

### Fase 0 — plataforma

- Velas OHLC reales.
- TF relevantes: 1m, 5m, 15m, 30m, 1h, 2h, 4h, D y cuando aplique W.
- Replay vela a vela.
- Capas dibujables y escalas coherentes.
- Nunca mostrar futuro en Replay.

### Fase 1 — SMC externo e interno

- Estructura externa primero.
- Después estructura interna.
- BOS/CHoCH: rojo bajista y verde alcista.
- EQH/EQL con criterio de color consistente.
- OB internos/externos y mitigación.
- FVG propio correcto; no copiar el FVG que el profesor mostró mal configurado.
- El FVG apoya la estructura; no sustituye la estructura.
- Trendlines forman la base geométrica del canal.

### Fase 2 — HLD

- Solo 4h y diario.
- Tomar el precio actual.
- Buscar hacia atrás una vela HTF relevante cuyo OHLC esté cerca del precio actual.
- Priorizar una vela reciente cuyo rango contenga el precio; usar proximidad como fallback.
- Proyectar el nivel desde la vela de origen hasta la actual.
- No reducirlo a “OHLC del día anterior”.
- En máximo histórico sin referencia pasada superior, no inventar HLD; el VWAP se vuelve pertinente.

### Fase 3 — ZigZag y canal

ZigZag externo:

- tipo ChartPrime ZigZag Volume Profile;
- volumen, PoC y canal deshabilitados;
- azul;
- length 150;
- máximo visual de 15 segmentos;
- representa estructura externa consolidada.

ZigZag interno:

- tipo ZZMTF;
- 15/30/60/120 minutos; default 30;
- period 2;
- solo Show ZigZag;
- verde ascendente, rojo descendente;
- todos los Fibonacci del ZZMTF apagados;
- cálculo independiente y bajo demanda.

Canal:

- preferentemente observado en 1m;
- más de una hora de comportamiento; ejemplo de aproximadamente tres horas;
- al menos tres puntos alineados;
- tolerar pequeña toma de liquidez y retorno;
- un solo canal activo;
- debe incluir la última vela en formación;
- desaparece al salir realmente del tubo.

La implementación aceptada hasta ahora es la herramienta manual Parallel Channel de tres clics. El detector automático completo con todas las reglas verbales quedó diferido.

### Fase 4 — Fibonacci

Regla conceptual del profesor:

- nace de un impulso consolidado del ZigZag externo;
- nunca del ZigZag interno;
- no usar el extremo todavía móvil como definitivo;
- niveles 23, 38, 61 y 78; 61 tiene especial importancia;
- “respetar” puede significar tomar liquidez y regresar;
- invalidar o actualizar al escapar de la zona o completar el movimiento.

Evolución real del producto: el primer Fib automático fue rechazado por parecer un overlay gris. Se sustituyó por una herramienta nativa tipo TradingView de dos anclas. `Desde ZZ` ayuda a elegir una pierna consolidada, pero el dibujo queda desacoplado y editable.

### Fase 5 conceptual — anclas y volumen

- Pivots missed/fantasmas ayudan a encontrar el ancla.
- Un fantasma móvil no es ancla estable; esperar consolidación.
- Anchored VWAP desde swing relevante/apertura y hasta 3σ.
- Anchored Volume Profile desde un punto estructural.
- El profesor no pidió una colección indiscriminada de indicadores de volumen.

Estos conceptos siguen siendo válidos, pero la cola formal actual ubica primero DIY y Volume Profile, y deja AVWAP después.

### Fase 6 conceptual — Liquidity

- No existe un indicador mágico llamado Sweep.
- Primero deben existir niveles: EQ, swings/BSL-SSL, OB, FVG, estructura/anclas.
- Sweep: toma liquidez y regresa rápido, aproximadamente 1–2 velas.
- Grab: toma, permanece indeciso varias velas y después regresa.
- Run: acepta el otro lado y construye/continúa un rango nuevo.
- Para etiquetado histórico se puede observar el desenlace futuro; para features live no.
- En el evento importa correlacionar estructura, zona, precio y volumen.

### Fase 7 conceptual — ML

- Lo más difícil es construir la tabla limpia.
- t-SNE reduce/visualiza dimensionalidad, sin tiempo.
- GMM devuelve probabilidades locales; umbral de clase mencionado como ejemplo: ~85%.
- HMM sí modela secuencia temporal y trabaja con etiquetas.
- No comenzar esta fase todavía: primero completar los indicadores pendientes.

---

## 6. Cronología completa de implementación

### 6.1 Recuperación de evidencia y creación de la guía

1. Se extrajeron audio y 100 frames del video `20260714_164526.mp4`.
2. El audio se transcribió en el VPS con `whisper-large-v3-turbo`.
3. Se compararon dos propuestas previas de IA con la transcripción completa.
4. Se creó `ORDEN_PROYECTO_DEFINITIVO.md` como guía conceptual.
5. Se auditó el proyecto avanzado y se estableció que `Downloads\Proyecto` era de solo lectura.

### 6.2 SMC Pro + Structures/FVG

Se abandonó el híbrido visual anterior y se reprodujeron dos capas separadas:

- SMC Pro [Neon]: estructura externa/interna, HH/HL/LH/LL, Strong/Weak, Swing OB, EQH/EQL y niveles MTF conforme a la captura.
- SMC Structures and FVG [LudoGH68]: FVG correcto y estructura complementaria.

Configuración importante SMC Pro:

- Historical;
- internal y swing structure ON;
- swing length 50, interno equivalente a 5;
- internal OB OFF, swing OB ON, máximo 5;
- mitigación High/Low;
- EQH/EQL ON, 3 confirmation bars, 0.1 ATR;
- FVG del propio Pro OFF;
- D/W/M H/L ON.

Configuración importante FVG:

- Display FVG ON;
- Reduce mitigated FVG ON;
- máximo 5;
- body break OFF, usar high/low;
- current structure OFF;
- BOS gris, CHoCH bullish verde y bearish rojo;
- sólido, ancho 1;
- Fib estructural OFF.

Correcciones históricas:

- centrado X de OB y líneas;
- EQH/EQL conectados a sus dos extremos;
- rayos limitados correctamente;
- BOS estable bajo zoom mediante solapamiento y después final real de datos;
- velas por encima de estructuras;
- ancho estructural 1;
- mantener sufijo `i` en estructura interna;
- error HASH de `max_lines`;
- mitigación FVG;
- dataset largo para validar HTF.

El segmento inicial terminó con una regresión de zoom aún roja, pero los segmentos posteriores la cerraron antes de continuar a HLD/ZigZag. No interpretar ese fallo intermedio como estado actual.

### 6.3 Parallel Channel

Se identificó que la captura mostraba el objeto nativo Parallel Channel de TradingView.

Implementado:

- herramienta manual de tres clics;
- P1/P2 definen pendiente y P3 el desplazamiento;
- dos rieles paralelos, relleno, línea media y preview;
- una sola instancia activa;
- anclas en índice/precio, estables ante pan/zoom;
- modelo bajo `Market/Drawing`, render bajo `Market/Overlays`;
- test `t/29-parallel-channel.t`.

No implementado: detector automático completo de un canal vivo con ≥3 contactos y todas las reglas del profesor.

### 6.4 HLD

Implementado para 4h y D:

- búsqueda reciente de vela cuyo rango contiene el precio;
- fallback al OHLC más próximo;
- mínimo 4 barras para 4h y 1 para D;
- un nivel calificable por TF para evitar densidad arbitraria;
- chips 4h/D a la derecha sin intercambiar identidad;
- test `t/30-hld.t`.

Corrección destacada: una primera versión seleccionaba una vela 4h de ~26 días atrás; se corrigió para priorizar candidatas recientes.

### 6.5 ZigZag externo

Implementado conforme a ChartPrime:

- azul;
- length 150;
- solo oscilación;
- sin VP, PoC ni canal;
- máximo 15 segmentos;
- feed bajo demanda;
- corrección específica de pivote high para reproducir el source objetivo;
- test `t/24-zigzag.t`.

### 6.6 ZigZag interno

Implementado después, conforme a ZZMTF:

- selector 15/30/60 (la guía admite también 120; verificar UI real antes de añadirlo);
- default 30;
- period 2;
- verde/rojo;
- Show ZigZag únicamente;
- Fib del ZZMTF apagado;
- externo e interno independientes.

Commit histórico: `9f953d4`.

### 6.7 Fibonacci

Primera versión:

- automática desde la última pierna externa consolidada;
- técnicamente correcta, pero visualmente rechazada.

Rediseño aceptado:

- herramienta de dibujo tipo TradingView;
- dos clics/anclas `p1` y `p2`;
- bandas coloreadas;
- labels `ratio(price)` fuera del borde izquierdo;
- anclas movibles;
- `Desde ZZ` permite elegir una pierna, no toma ciegamente la última;
- sincroniza el checkbox externo;
- `Hasta última vela` sustituye extensiones confusas;
- la caja depende solo de p1/p2;
- fórmula final: `price(level) = p2 + level * (p1 - p2)`;
- se corrigieron orientación y from/to.

También se eliminó el placeholder HTF sobre LTF que no tenía comportamiento real.

### 6.8 Sellado del producto y expulsión de legacy

Antes de Liquidity, el usuario exigió no reutilizar el viejo módulo defectuoso. Se estableció:

- producto oficial limitado a capas aceptadas;
- legacy fuera del repositorio Git;
- documentación de frontera oficial/legacy;
- prohibición de importar, copiar o adaptar el Liquidity viejo;
- Liquidity v2 se construiría desde cero.

### 6.9 Diseño de Liquidity y plan ML

Se consultaron Lumina, PDF, clases y audio. Se definió:

- FSM `Detected → Swept → Resolved(sweep|grab|run)`;
- pivotes preferentemente desde ZigZag/SMC limpios;
- k=3 como formalización/fallback, no como fuente indiscriminada;
- eventos/observaciones exportables;
- separación INT/EXT futura;
- dataset alrededor de eventos, no cada vela;
- congelación causal de features.

`docs/PLAN_DEFINITIVO.md` fue creado al inicio del siguiente segmento como documento permanente de dirección ML.

### 6.10 Liquidity v2

Implementado desde cero:

- BSL/SSL;
- EQH/EQL;
- Sweep/Grab/Run;
- pivotes externos acumulados aunque el ZigZag visual recorte a 15 piernas;
- checkbox Historial para niveles resueltos;
- export básico de eventos;
- observation stream;
- integración con Replay.

Correcciones visuales:

- `SWEEP UP`/`SWEEP DN` ASCII para evitar mojibake;
- clustering y dedupe de niveles/eventos;
- prioridad EQH/EQL sobre BSL/SSL coincidentes;
- EQ trazado entre sus pivotes, no hasta el borde;
- colores direccionales;
- labels solo cuando el ancla corresponde al viewport;
- límite de densidad solo para textos, no para líneas/eventos.

Auditoría NQ 15m registrada: ocho eventos — cuatro sweeps y cuatro runs — con reglas OHLC coherentes; no aparecieron grabs en esa muestra.

### 6.11 Reconstrucción causal de Replay

Problemas encontrados:

- `x_shift` fijo de -20% simulaba hueco derecho recortando historia izquierda;
- paneles usaban transformaciones distintas en zoom denso;
- `compute_window` y feeds podían incluir datos posteriores a `replay_idx`;
- autoescala, ATR, timestamps, indicadores o pivotes podían filtrar futuro;
- rewind conservaba estados confirmados con barras futuras.

Solución:

- `causal_end = replay_idx`;
- slots lógicos vacíos a la derecha, head cerca del 80%;
- `view_start/view_end` separados de `data_start/data_end`;
- escala X compartida entre Price, ATR, grid, crosshair, hit-testing y overlays;
- OHLC, ATR, timestamps reales y autoescala limitados al prefijo causal;
- calendario del hueco derecho sintético, sin leer timestamps futuros;
- reset/re-feed causal al rebobinar;
- `reset_full` de Liquidity en rewind;
- overscan `end+1` permitido solo si sigue dentro de `replay_idx`;
- RUN recoloreado después de sincronización causal;
- escala manual reconstruida desde slices causales.

Validación final reportada:

- `t/38-replay-geometry.t`: 52 checks;
- suite de escala manual: 26/26;
- **suite oficial seleccionada:** 558/558;
- revisión independiente final: sin bloqueadores altos o medios, después de corregir los hallazgos causales de revisiones intermedias.

Esto no equivale a que todo `prove -l t` estuviera verde: la ejecución amplia fallaba únicamente en `t/17-ui-wiring.t` con 20 expectativas antiguas de UI, consideradas stale durante la sesión pero no corregidas. No declarar la suite completa verde hasta actualizar o excluir formalmente ese test.

Observación residual de baja severidad: `t/38` no instrumenta un `render()` completo para contar dinámicamente el orden exacto de una llamada, aunque la inspección estática confirmó el orden correcto.

### 6.12 Última decisión de la sesión

Después de marcar Liquidity v2 MVP como hito A, se propuso pasar a Liquidity v1.5/features y modelos. El usuario corrigió:

> antes de pasar a modelos, seguir la guía para reformar la aplicación por indicadores.

La respuesta final estableció:

1. aún estamos cerrando §4 SMC+FVG+Liquidity;
2. faltan volumen multi-TF e INT/EXT;
3. luego §5 concurrencia;
4. después DIY Supply/Demand;
5. luego Volume Profile;
6. finalmente Anchored VWAP;
7. modelos quedan pospuestos.

No hubo implementación después de esa decisión.

---

## 7. Matriz de estado

| Área | Estado verificable | Nota |
|---|---|---|
| Chart OHLC / TF / Replay | Hecho | Replay causal reconstruido |
| SMC Pro | Hecho | Runtime oficial |
| Structures + FVG | Hecho | FVG correcto separado |
| Parallel Channel manual | Hecho | Detector automático futuro no incluido |
| HLD 4h/D | Hecho | Algoritmo de proximidad, no previous-day estático |
| ZigZag externo | Hecho | ChartPrime, 150, azul, 15 segmentos |
| ZigZag interno | Hecho | ZZMTF, multi-TF, period 2, sin Fib |
| Fib Retracement | Hecho | Herramienta nativa editable |
| Liquidity BSL/SSL + EQH/EQL | Hecho | v2 desde cero |
| FSM Sweep/Grab/Run | Hecho | MVP aceptado |
| Historial/pivotes ZZ acumulados | Hecho | Independiente del trim visual |
| Export básico/observation stream | Hecho | No es aún dataset completo |
| Geometría y rewind causal | Hecho | 558/558 en suite oficial seleccionada; `t/17` stale fuera de ella |
| Volumen `v1m/v5m/v15m` por evento | **Pendiente inmediato** | Por rangos temporales/timestamps |
| INT/EXT real | **Pendiente inmediato** | No dejar `kind => undef` |
| FSM formal Acceptance/Reclaimed | **Pendiente de reconciliar** | El MVP resume resolución; el PDF exige estados explícitos |
| Export básico incompleto | **Pendiente de completar** | `dist_pips_placeholder`, features y `kind` |
| Semántica temporal Grab | **Pendiente de confirmar** | PDF ≤3 velas vs clases posteriores con mayor indecisión |
| Siete zonas/features | Aplazado para enriquecimiento | No confundir con el núcleo MVP ya aceptado |
| Concurrencia Liquidity→estructura | Pendiente siguiente | §5 PDF, tras cierre formal de §4 |
| DIY Supply/Demand | Pendiente | Próximo indicador visible |
| Advanced Volume Profile | Pendiente | Después de DIY |
| Anchored VWAP multipivot | Pendiente | Después de VP |
| Dataset ~50 features/export batch | Aplazado | Tras indicadores |
| t-SNE/GMM/HMM | No iniciado | No ejecutar ahora |

---

## 8. Orden exacto para continuar

### Paso 0 — preservar y auditar

Antes de editar:

1. Entrar a `C:\ia\proyecto_iaaa\Proyecto\ProyectoIAAA`.
2. Leer `AGENTS.md`, `docs/PRODUCTO_OFICIAL.md`, `docs/CONSTITUTION.md`, `docs/LIQUIDITY_V2.md`, PDF/spec/task relevante.
3. Ejecutar `git status --short --branch` y revisar el diff.
4. Identificar archivos sin seguimiento del trabajo aceptado.
5. No resetear, limpiar, cambiar de rama destructivamente, commitear ni pushear sin autorización.
6. Confirmar con el usuario antes de iniciar implementación; esta recuperación no es una orden automática para programar.

### Paso 1 — cerrar Liquidity del §4

#### 1A. Volumen multi-TF real

- Añadir features por evento `v1m`, `v5m`, `v15m`.
- Calcular mediante timestamps/rangos temporales, no reutilizando el mismo índice entre series de distinta resolución.
- Congelar el valor causalmente en el momento definido para el evento.
- No usar resolución futura para recalcular features.
- Mantener cálculo headless en `Indicators`, sin Tk.

#### 1B. INT/EXT real

- Sustituir `kind => undef` por una clasificación respaldada por estructura.
- Según el PDF: interna nace en el TF activo; externa se proyecta desde un HTF.
- Usar la estructura ZigZag/SMC para no convertir la clasificación en una mera etiqueta visual.
- Si existe estado intermedio en el roadmap ML, definir su relación con el contrato formal antes de añadirlo.
- Propagar clasificación a eventos y observation stream.
- Añadir tests sintéticos y de Replay causal.

#### 1C. Reconciliar el núcleo formal restante de §4

- Comparar la FSM actual con `Detected → Swept → Acceptance/Reclaimed → Resolved` del PDF.
- Decidir si `Acceptance` y `Reclaimed` deben ser estados persistidos explícitamente o si la implementación actual ya los representa de forma equivalente; documentarlo y probarlo.
- Resolver con evidencia del profesor la discrepancia temporal de Grab: PDF con retorno en máximo 3 velas frente a clases/transcripción posterior con indecisión durante varias velas.
- Completar los campos preliminares del export, incluidos `dist_pips_placeholder`, `kind` y features causales mínimas.
- Mantener las siete zonas/~50 features como enriquecimiento posterior salvo que el usuario/profesor las exija para declarar formalmente cerrado §4.

### Paso 2 — concurrencia determinista, §5

Implementar después de completar y verificar 1A, 1B y 1C:

- Sweep refuerza un CHoCH contrario.
- Run refuerza el siguiente BOS en dirección de expansión.
- Grab genera alerta de reversal.
- FVG durante o inmediatamente después de Sweep/Grab se marca como Zona de Alta Reacción.

Esto es integración determinista entre indicadores, no ML. Leer `specs/0006-concurrencia-liquidez-estructura.md` y contrastar con el PDF antes de definir pesos o UI.

### Paso 3 — DIY Custom Strategy Builder reformado, §6

Reconstruir desde cero o desde fuentes del profesor dentro de la arquitectura oficial. No copiar el módulo legacy.

Último feedback del profesor:

- priorizar Supply/Demand;
- evitar exponer toggles innecesarios de SuperTrend, HalfTrend y Range Filter si ya no corresponden;
- coordinar Supply/Demand con OB de SMC;
- mitigar/eliminar zonas consumidas;
- Supply/Demand coincidente con OB = confluencia de mayor calidad.

El PDF formal todavía enumera SuperTrend, HalfTrend y Range Filter. Antes de eliminarlos del alcance, confirmar con el usuario si deben implementarse, conservarse ocultos o considerarse sustituidos por el feedback posterior.

Antes de implementar, revisar capturas y `docs/reference_indicators/diy_custom_strategy_builder_zp.txt`; la captura del profesor prevalece sobre defaults.

### Paso 4 — Advanced Volume Profile, §7

Reforma nueva, no restauración del legacy:

- perfil por sesión;
- perfil por BOS/CHoCH HTF;
- contingencia histórica;
- POC, VAH y VAL;
- cálculo separado del render;
- causal en Replay;
- activación bajo demanda.

### Paso 5 — Anchored VWAP, §8

Después de Volume Profile, porque una de sus anclas es el POC:

- inicio de sesión;
- apertura oficial;
- BOS confirmado;
- CHoCH confirmado;
- POC de Volume Profile;
- múltiples anclas simultáneas;
- hasta 3σ cuando corresponda a la guía;
- anclas consolidadas, no pivotes móviles;
- causal en Replay.

### Paso 6 — volver al plan ML

Solo después del cierre de indicadores y con autorización:

- siete zonas/features;
- export batch histórico;
- ~50 columnas;
- pips y Z-score train-only;
- split temporal;
- t-SNE;
- GMM;
- HMM interno/externo.

---

## 9. Restricciones de ingeniería no negociables

1. `Downloads\Proyecto` es solo lectura.
2. El único repositorio válido es `C:\ia\proyecto_iaaa\Proyecto\ProyectoIAAA`.
3. Preservar el worktree sucio de `feature/liquidity-v2-fsm`.
4. No reactivar, importar ni conectar archivos legacy al runtime; solo consultar ideas históricas y reimplementarlas en módulos nuevos con pruebas.
5. Separación estricta cálculo (`Market/Indicators`) y Tk/render (`Market/Overlays`, paneles).
6. Escala X compartida y Y por panel; no introducir transformaciones paralelas.
7. Velas visualmente encima de dibujos estructurales; líneas estructurales de ancho 1.
8. Geometría independiente del zoom.
9. Overlays pesados bajo demanda.
10. Replay estrictamente causal: no futuro en OHLC, ATR, timestamps, autoescala, labels, pivotes, estado o features.
11. En rewind, reconstruir indicadores hasta `replay_idx` y eliminar confirmaciones que dependieron del futuro.
12. Capturas/configuración del profesor prevalecen frente a defaults Pine.
13. No introducir dependencias nuevas sin aprobación.
14. No refactorizar masivamente `ChartEngine.pm` “de paso”.
15. No hacer commit, push, merge ni cambios destructivos sin petición expresa.
16. Validación mínima: sintaxis Perl, tests dirigidos del módulo, tests de Replay y suite oficial relevante.
17. No declarar toda la suite verde basándose en tests legacy obsoletos; distinguir suite oficial de producto y documentar cualquier exclusión.

---

## 10. Incertidumbres y matices que deben conservarse

1. **Canal:** está hecha la herramienta manual; no está demostrado un detector automático con todas las reglas del profesor.
2. **Fib:** la guía conceptual hablaba de Fib automático; el producto terminó usando una herramienta nativa editable porque el usuario rechazó el overlay automático. No revertir esa decisión sin pedirlo.
3. **ZigZag interno 120m:** la guía admite 15/30/60/120; el resumen del producto menciona 15/30/60. Inspeccionar UI/código antes de afirmar que 120 ya existe.
4. **Grab/Run:** defaults actuales son Sweep ≤2, Grab 3–8 y Run con 3 cierres, pero son parámetros calibrables, no leyes universales del profesor.
5. **Fuente de pivotes de Liquidity:** el camino principal es ZigZag/SMC acumulado; k=3 es fallback. La documentación breve puede simplificarlo de forma distinta; confirmar código.
6. **`PLAN_DEFINITIVO.md`:** su sección “Ahora: B features” quedó desalineada con la última prioridad conversacional. No borrar el objetivo ML; añadir una aclaración futura solo con autorización.
7. **`ROADMAP.md`:** todavía dice que Strategy/VP/VWAP fueron implementados, pero se refiere a versiones legacy expulsadas. No es evidencia de que los módulos reformados actuales existan.
8. **Tests:** 558/558 corresponde a la suite oficial aceptada al cierre. Antes de nuevos cambios, volver a ejecutar la selección documentada y no asumir que el entorno Windows tiene Perl directamente; históricamente se usó WSL/Fedora 35.
9. **No se implementó nada después del último mensaje:** todos los pasos multi-TF/INT-EXT/concurrencia/DIY/VP/VWAP siguen pendientes.

---

# 11. Prompt autosuficiente listo para pegar

Copia desde la línea siguiente hasta `FIN DEL PROMPT` en la sesión que perdió memoria.

---

## INICIO DEL PROMPT

Quiero que recuperes y adoptes la siguiente memoria como contexto operativo del proyecto. Esta memoria reconstruye la sesión Grok `019f6e8d-1aa4-7d90-bd50-4b4f47dee7aa` desde su inicio hasta el último mensaje, después de que varias compactaciones y el cambio de Grok 4.5 a GPT-5.6-SOL hicieran perder parte de la historia. Trata esta memoria como un índice histórico contrastado, no como sustituto del estado vivo: inspecciona de inmediato el repositorio en modo de solo lectura, confirma que entendiste el estado y pregúntame antes de modificar archivos o iniciar el siguiente lote.

### A. Identidad del proyecto y repositorio

La aplicación es una plataforma tipo TradingView en Perl/Tk para visualizar estructura de mercado y generar posteriormente observaciones causales para modelos. El repositorio canónico es exclusivamente:

`C:\ia\proyecto_iaaa\Proyecto\ProyectoIAAA`

No uses la copia stale:

`C:\m1\ia\proyecto_iaaa\Proyecto\ProyectoIAAA`

La rama actual es `feature/liquidity-v2-fsm` y contiene un worktree grande sin commit. En la última inspección había 15 archivos rastreados modificados con aproximadamente 765 inserciones y 319 eliminaciones, además de archivos críticos sin seguimiento, entre ellos:

- `Market/Indicators/Liquidity.pm`
- `Market/Overlays/Liquidity.pm`
- `docs/LIQUIDITY_V2.md`
- `docs/PLAN_DEFINITIVO.md`
- `t/32-liquidity-v2.t`
- `t/38-replay-geometry.t`
- `Data/tv_nq1_15m.csv`

Antes de tocar nada, ejecuta `git status --short --branch`, revisa el diff y preserva todo el trabajo. No uses `reset --hard`, `clean`, checkout destructivo, rebase ni copies archivos desde el árbol stale. No hagas commit o push salvo que yo lo pida expresamente.

La carpeta `C:\Users\bryan\Downloads\Proyecto` contiene material del profesor y es estrictamente de solo lectura. Puedes consultar o copiar recursos al repo, pero nunca modificarla.

El legacy está fuera del repo en:

`C:\ia\proyecto_iaaa\Proyecto\ProyectoIAAA_LEGACY_ARCHIVE\`

No reactives, importes ni conectes al runtime el Liquidity viejo, Strategy Builder viejo, Volume Profile viejo, Anchored VWAP viejo, Mxwll o el SMC unificado viejo. Puedes consultar ideas históricas conforme a `docs/LEGACY.md`, pero cualquier lógica útil debe reimplementarse en módulos nuevos, ajustarse al contrato causal y probarse; nunca copies el archivo legacy directamente al runtime.

### B. Fuentes y jerarquía

Aplica esta jerarquía por ámbito:

1. Código actual + `docs/PRODUCTO_OFICIAL.md`: runtime real.
2. `C:\Users\bryan\Downloads\20260714_164526_extract\ORDEN_PROYECTO_DEFINITIVO.md`: guía conceptual y dependencias recuperadas del video completo del profesor.
3. `docs/material_profesor/Especificacion_Proyeto_2a_Fase.pdf`: orden formal de módulos pendientes.
4. Mi última instrucción conversacional: continuar indicadores antes de modelos.
5. `docs/PLAN_DEFINITIVO.md`: objetivo de dataset/modelos para después, no la prioridad inmediata.
6. Capturas/configuración del profesor prevalecen sobre defaults Pine/TradingView.
7. `ROADMAP.md` y arquitectura antigua no autorizan a reactivar legacy.

Fuentes Lumina importantes:

- `a21ce910fecc`: SMC/data cleaning, 15-jun.
- `1d3e610b36ae`: Liquidity/HMM, siete zonas, multi-TF e INT/EXT, 16-jun.
- `47bfe676f0e6`: indicadores/configuraciones, 23-jun.

Audio reciente transcrito por VPS: `IA_IndicacionesExaProy-20260719-051032`.

### C. Las rutas deben mantenerse separadas

Ruta conceptual del profesor (14-jul):

1. OHLC/multi-TF/Replay/capas.
2. SMC externo primero, luego interno: BOS/CHoCH, EQH/EQL, OB, FVG correcto y trendlines.
3. HLD 4h/D basado en una vela histórica relevante cercana al precio.
4. ZigZag externo, después interno multi-TF y canal.
5. Fib desde impulso consolidado del ZigZag externo.
6. Fantasmas/pivots como anclas, Anchored VWAP hasta 3σ y Anchored Volume Profile.
7. Sweep/Grab/Run solo después de establecer niveles.
8. Tabla → t-SNE → GMM → HMM.

Orden formal del PDF para lo que falta:

- §4: SMC + FVG + Liquidity.
- §5: concurrencia Liquidity→estructura.
- §6: DIY Custom Strategy Builder.
- §7: Advanced Volume Profile.
- §8: Anchored VWAP.

Ruta ML futura:

- eventos cerca de liquidez;
- ~50 features, pips, Z-score train-only;
- congelar features en `sweep_index`;
- futuro solo para asignar la clase histórica;
- t-SNE/GMM sin tiempo;
- HMM temporal INT/EXT;
- train aproximado abril–inicios de junio, test junio.

No mezcles estas rutas. El archivo `PLAN_DEFINITIVO.md` quedó diciendo que el hito B de features estaba “en curso”, pero después yo corregí la prioridad: **antes de modelos, terminar la reforma de indicadores**.

### D. Historia implementada

1. Se extrajo y transcribió el video del 14-jul y se creó `ORDEN_PROYECTO_DEFINITIVO.md`.
2. Se reconstruyó SMC como dos capas oficiales:
   - SMC Pro [Neon] para estructura externa/interna, BOS/CHoCH, HH/HL/LH/LL, OB, EQH/EQL, Strong/Weak y MTF;
   - Structures+FVG [LudoGH68] para FVG correcto.
3. Se corrigieron estabilidad bajo zoom, centrado de OB, mitigación FVG, ancho 1 y z-order con velas encima.
4. Se implementó Parallel Channel manual de tres clics. No está hecho un detector automático completo de canal.
5. Se implementó HLD 4h/D buscando una vela histórica relevante/cercana, no previous-day OHLC estático.
6. Se implementó ZigZag externo ChartPrime: azul, length 150, sin volumen/PoC/canal, máximo 15 segmentos.
7. Se implementó ZigZag interno ZZMTF: default 30m, period 2, verde/rojo y sin Fib. Verifica si 120m está realmente expuesto antes de afirmarlo.
8. El primer Fib automático fue rechazado visualmente. Se reemplazó por una herramienta nativa TradingView de dos anclas, bandas, labels, selección `Desde ZZ` y edición directa. No reviertas a líneas grises automáticas.
9. Se selló el producto oficial y se expulsó legacy del repo.
10. Se construyó Liquidity v2 desde cero:
    - BSL/SSL;
    - EQH/EQL;
    - FSM Sweep/Grab/Run;
    - pivotes ZZ/SMC acumulados;
    - Historial;
    - export básico y observation stream;
    - labels ASCII, dedupe, clustering y colores corregidos.
11. Se reconstruyó Replay:
    - slots vacíos reales a la derecha;
    - head cerca del 80%;
    - escala X compartida;
    - causalidad de OHLC/ATR/timestamps/autoescala/feeds;
    - reset causal al rebobinar;
    - overscan causal;
    - RUN recoloreado después de sincronizar.
12. Validación final registrada en la sesión:
    - `t/38`: 52 checks;
    - escala manual: 26/26;
    - suite oficial seleccionada: 558/558;
    - revisión independiente final sin bloqueadores altos/medios, después de corregir hallazgos causales intermedios.
    - La suite completa no estaba verde: `prove -q t/*.t` conservaba 20 expectativas stale en `t/17-ui-wiring.t`; no confundir esa ejecución amplia con la suite oficial aceptada.

Runtime oficial actual:

`smc_pro`, `smc_fvg`, `hld`, `pchan`, `zigzag`, `fib`, `liq`.

### E. Estado exacto

Hecho:

- Chart/TF/Replay causal.
- SMC Pro y Structures+FVG.
- HLD.
- Parallel Channel manual.
- ZigZag externo e interno.
- Fib Retracement nativo.
- Liquidity v2 MVP: niveles, FSM resumida, historial y export básico.
- Replay causal; suite oficial seleccionada verde. La suite completa mantiene `t/17-ui-wiring.t` stale.

Pendiente inmediato para cerrar y verificar formalmente §4:

1. Volumen multitemporal real por evento: `v1m`, `v5m`, `v15m`, calculado por timestamps/rangos temporales y sin mezclar índices de TF.
2. Clasificación INT/EXT real. No dejar `kind => undef`; debe derivarse de estructura/TF y propagarse a eventos/observaciones.
3. Reconciliar la FSM resumida actual con los estados formales `Acceptance` y `Reclaimed` del PDF: determinar si ya están representados de manera equivalente o si deben persistirse explícitamente.
4. Resolver la discrepancia temporal de Grab: PDF con retorno en máximo 3 velas frente a las clases/transcripciones posteriores que describen indecisión durante varias velas.
5. Completar los campos preliminares del export, incluidos `dist_pips_placeholder`, `kind` y las features causales mínimas. Las siete zonas/~50 features permanecen como enriquecimiento posterior salvo que el usuario o el profesor las exijan para declarar cerrado §4.

Después:

6. §5 concurrencia determinista:
   - Sweep refuerza CHoCH contrario;
   - Run refuerza próximo BOS a favor;
   - Grab alerta reversal;
   - FVG durante/inmediatamente después de Sweep/Grab = Zona de Alta Reacción.
7. §6 DIY Custom Strategy Builder, priorizando Supply/Demand y confluencia con OB. El feedback posterior favorece retirar u ocultar ST/HT/RF, pero el PDF formal todavía los enumera: confirmar con el usuario si se implementan, quedan ocultos o se consideran sustituidos. No restaurar el módulo legacy.
8. §7 Advanced Volume Profile: sesión, BOS/CHoCH HTF, POC/VAH/VAL y contingencia histórica.
9. §8 Anchored VWAP multipivot: sesión, apertura, BOS, CHoCH y POC; causal, múltiples anclas, hasta 3σ cuando corresponda.
10. Solo después, dataset/t-SNE/GMM/HMM.

La corrección central es: **Anchored VWAP no es el siguiente indicador**. El orden final vigente es:

`Liquidity multi-TF + INT/EXT → concurrencia → DIY Supply/Demand → Volume Profile → Anchored VWAP → modelos`.

### F. Reglas técnicas no negociables

- Separar cálculo de Tk/render.
- Mantener escala X compartida.
- Geometría estable bajo zoom.
- Velas encima de estructuras; ancho estructural 1.
- Overlays pesados bajo demanda.
- Replay sin futuro en datos, timestamps, escala, estado, pivotes, labels o features.
- En rewind reconstruir hasta `replay_idx` y borrar confirmaciones dependientes del futuro.
- Capturas del profesor mandan sobre defaults.
- No introducir dependencias ni refactorizar masivamente `ChartEngine` sin permiso.
- No modificar `Downloads\Proyecto`.
- No reactivar legacy.
- No commit/push/merge sin autorización.
- Validar sintaxis Perl, tests dirigidos, Replay y suite oficial relevante.

### G. Matices que no debes olvidar

- Liquidity v2 está aceptado como MVP/hito A, pero §4 no está completo: faltan multi-TF, INT/EXT, export preliminar y la reconciliación formal de FSM/Grab.
- Las siete zonas y ~50 features pertenecen al enriquecimiento posterior según el plan actual; no afirmar que ya existen ni fusionarlas silenciosamente con el MVP.
- La herramienta manual de canal está hecha; el detector automático completo no.
- El Fib conceptual era automático, pero el producto aceptado es una herramienta nativa editable.
- Sweep/Grab/Run usan defaults calibrables; no conviertas 2/8/3 en leyes inmutables.
- El camino principal de pivotes Liquidity es ZZ/SMC acumulado; k=3 es fallback.
- `ROADMAP.md` puede decir que Strategy/VP/VWAP estaban implementados, pero esas eran versiones legacy expulsadas y no cuentan como la reforma actual.
- No hubo implementación después de la última decisión; todos los pendientes anteriores siguen sin ejecutar.

### H. Tu respuesta inicial y comportamiento

Primero responde con un resumen breve que demuestre que entendiste:

1. cuál es el repositorio y rama que debes preservar;
2. qué quedó realmente terminado;
3. qué falta para cerrar Liquidity;
4. cuál es el orden exacto posterior;
5. por qué no debes empezar modelos ni Anchored VWAP todavía.

Inspecciona de inmediato y solo en lectura `git status --short --branch`, `git diff --stat`, el diff relevante y los documentos canónicos. Después espera mi autorización antes de modificar archivos o implementar. Si la evidencia actual contradice esta memoria, no sobrescribas nada: señala la discrepancia y pregúntame.

## FIN DEL PROMPT
