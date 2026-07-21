# AI Context

> **Advertencia de continuidad (2026-07-19):** este archivo conserva contexto histórico y varias descripciones de módulos legacy. No usarlo como inventario vivo ni como cola de trabajo. Leer primero `docs/BRUJULA_CONTINUIDAD.md`, después `docs/PRODUCTO_OFICIAL.md`; usar `docs/MEMORIA_RECUPERADA_019f6e8d.md` para recuperar la historia. La prioridad vigente es indicadores antes de modelos.

Resumen reutilizable del proyecto para que cualquier sesión de IA recupere contexto rápido.
Última actualización: 2026-07-19.

> **Meta posterior:** `docs/PLAN_DEFINITIVO.md` (app → dataset → t-SNE → GMM → HMM).
> **Prioridad actual:** `docs/BRUJULA_CONTINUIDAD.md`.
> **Capas reales en runtime:** `docs/PRODUCTO_OFICIAL.md`.

## Producto

Plataforma de trading/charting financiero tipo TradingView, construida en Perl 5 + Tk.
Renderiza velas OHLCV con indicadores técnicos, paneles sincronizados e interacciones de
usuario (zoom, drag, crosshair, timeframes, Replay).

**No es el fin en sí misma:** es la **fábrica de observaciones** (estructura, liquidez,
features) para entrenar modelos del curso: tabla de eventos → **t-SNE → GMM (P≥85%) →
HMM interno/externo**. Detalle: `docs/PLAN_DEFINITIVO.md`.

Contexto académico: asignatura de IA y Aprendizaje Automático, EPN 2026A, GR1SW.
Integrantes: Bryan Ayala, Juan Chugá, Sebastián Jibaja, Oscar Tamayo.
Repo remoto: `https://github.com/amsipan/ProyectoIAAA` (branch `main`).

## Usuarios objetivo

- El estudiante/operador que analiza estructura de mercado de forma visual e interactiva.
- El profesor que evalúa contra una rúbrica y un PDF de especificación por fase.
- Las fases posteriores de ML, que consumen las etiquetas (BOS/CHoCH/FVG/liquidez,
  ATR por bins, volumen, strategy flags) como observaciones discretas para entrenar el HMM.

## Estado por fases

- **Fase 1 (Primer bimestre) — COMPLETADA y evaluada (89/100).** Motor gráfico, paneles,
  ATR, interacciones de UI, 3 timeframes (1m/5m/15m). Eje temporal TradingView cerrado en
  `0000g`–`0000j`.
- **Fase 2 — 1ª entrega (29/06) — COMPLETA en código y tests.** 8 timeframes, Replay sin
  fuga de futuro, Overlays, SMC (BOS/CHoCH/FVG/Fibonacci), Liquidez (swings/EQH/EQL/BSL/SSL,
  FSM Sweep/Grab/Run, volumen multi-TF, 7 zonas), UI inline.
- **Fase 2 — 2ª entrega (13/07) — IMPLEMENTADA en gran parte (código + tests + pulido).**
  - Strategy Builder, Volume Profile, Anchored VWAP (`t/19`–`t/21`).
  - Mxwll Suite, ZigZag interno/externo + canal de tendencia clásico (`t/22`, `t/24`).
  - Replay calque TradingView (panel inline, Select Bar, velocidades, Go-to, atajos) —
    tasks `0041`–`0053` (0047 baja prio; 0053 cursor SO pausado por límite WSLg).
  - Feedback profe/QA 2ª ronda `0054`–`0062` (densidad BSL/SSL, anclaje liquidez→SMC,
    pivotes SMC, EQH/EQL INT/EXT, recolor RUN, FVG near price, Fib 3 niveles en TF bajas,
    canal clásico, slider de densidad).
  - Fixes posteriores: estabilidad overlays al zoom/pan, grid toggle, ZigZag cadena continua,
    Fib Mxwll, anti-solapamiento etiquetas SMC.
  - Suite: **29 archivos** `t/*.t` (índices no contiguos: `t/00`–`t/26`, `t/37`, `t/58`).
  - **Pendiente / parcial:** concurrencia liquidez→estructura con pesos de probabilidad
    (spec `0006`, aún sin task formal post-0062); 0047 tijeras vectoriales; 0053 cursor OS.
- **Fase 3 (ML recurrente) — FUTURA.** HMM + Viterbi tensorial (órdenes superiores),
  Pearson/PCC, discretización. Specs `0011`/`0012`. Insumo: etiquetas de Fase 2.

Fuente de estado de tasks: **`tasks/README.md`** (más actual que este archivo si divergen).

## Módulos principales (estado actual)

### Capa aplicación y orquestación
- `market.pl` — punto de entrada; UI Tk **inline por pestañas** (Capas, SMC, Liq, Mxwll,
  ZigZag, Estrategia, Escala, Replay); sin menubar ni Optionmenu (popups erráticos en WSLg).
- `Market/ChartEngine.pm` — orquestador: render, zoom, drag, crosshair, ejes, Replay visual,
  feed de overlays (`sync_overlay_indicators`). ~3300+ líneas; god object — ver TECH_DEBT.
- `Market/MarketData.pm` — OHLCV, 8 TF (1m/5m/15m/1h/2h/4h/D/W) por fronteras de reloj
  (W=lunes ISO), slicing, anclas de sesión.
- `Market/IndicatorManager.pm` — contenedor de indicadores base (ATR).
- `Market/ReplayController.pm` — índice-tope de Replay, play/pause/step, 9 velocidades,
  intervalos (sin Tk de dibujo).
- `Market/OverlayManager.pm` — registro de overlays activables.

### Indicadores (cálculo PURO, sin Tk) — `Market/Indicators/`
- `ATR.pm` — ATR 14, O(1) por vela.
- `SMC_Structures.pm` — HH/HL/LL/LH, BOS/CHoCH, major high/low, FVG (+ near price), Fibonacci
  (3 niveles en TF bajas). Getters idempotentes; filtros de densidades/ATR.
- `Liquidity.pm` — niveles BSL/SSL, EQH/EQL INT/EXT, FSM Sweep/Grab/Run, volumen multi-TF,
  7 zonas; pivotes anclables a SMC; k/significancia para menos ruido.
- `Strategy_Builder.pm` — SuperTrend, HalfTrend, Range Filter, Supply/Demand.
- `VolumeProfile.pm` — perfil de volumen.
- `AnchoredVWAP.pm` — VWAP multipivot.
- `Mxwll_Suite.pm` — suite unificada estilo referencia Mxwll/Pine.
- `ZigZag.pm` — dirección interna/externa + canal de tendencia clásico (2 paralelas por pierna).

### Overlays (render Canvas) — `Market/Overlays/`
- `Base.pm` / `Example.pm` — contrato: `set_visible`, `compute_visible`, `draw`, `clear`, `tag`.
- Pares de render: `SMC_Structures`, `Liquidity`, `Strategy_Builder`, `VolumeProfile`,
  `AnchoredVWAP`, `Mxwll_Suite`, `ZigZag`.

### Paneles y UI
- `Market/Panels/{PricePanel,ATRPanel,Scales}.pm` — velas/ATR + mapeo datos↔píxeles;
  recolor de velas RUN; línea de precio de cabeza de Replay.
- `Market/UI/Callbacks.pm` — factorías de callbacks (testeables headless).
- `Market/UI/ReplayPanel.pm` (+ `ReplayDropdown`, `ReplayGotoMenu`, `ReplaySpeedMenu`,
  `ReplayIntervalMenu`) — barra Replay inline estilo TradingView.

### Debug (capa del arquitecto; implementor no edita)
- `Market/Debug/TimeAxisSnapshot.pm` — eje temporal por estado o rango.
- `Market/Debug/IndicatorSnapshot.pm` — items estructurados → texto determinista + guard Replay.
  Contrato: `docs/PHASE2_DEBUG_CONTRACT.md`. Self-test: `t/08`.

## Módulos / trabajo aún pendiente

- **Spec 0006** — concurrencia liquidez → BOS/CHoCH (pesos de probabilidad); no formalizada
  como lote de tasks post-0062.
- **0047** — tijeras vectoriales (baja prioridad).
- **0053** — ocultar cursor del SO en Select Bar (pausado: límite WSLg).
- **Fase 3** — `Algorithm/Viterbi` (u equivalente) + Pearson; aún no en `Market/`.

## Stack detectado

- **Lenguaje:** Perl 5 (POO con `bless`, `package`).
- **GUI:** Tk (Canvas). Confirmado en código y PDF.
- **Tensores/ML (Fase 3):** AI::MXNet (NDArray). Parches en Fedora35: `docs/SETUP_FEDORA35.md`.
- **Gráficas de análisis (PCC/heatmap):** Chart::Plotly (material del profesor).
- **Datos:**
  - `Data/2026_07_20.csv` — dataset predeterminado: 18.658 velas NQ1! 1m con volumen,
    del 1 al 20 de julio de 2026 (`UTC-5`).
  - Los demás CSV de `Data/` se conservan como datasets históricos y fallbacks.
- **Tiempo:** `Time::Moment`.
- **Entorno:** WSL Fedora35 (EOL) + WSLg.
- **VCS:** Git; remote GitHub. Working tree en OneDrive; **gitdir separado** en
  `C:\Users\ASUS ROG\.gitdirs\ProyectoIAAA.git` (ver `AGENTS.md`).

## Estructura de carpetas

```
ProyectoIAAA/
  market.pl                     # entrada, UI Tk inline por pestañas
  Market/
    MarketData.pm               # datos: 8 timeframes
    ChartEngine.pm              # orquestador/render/zoom/drag/replay/overlays
    IndicatorManager.pm
    ReplayController.pm
    OverlayManager.pm
    Indicators/                 # CÁLCULO (sin Tk)
      ATR.pm  SMC_Structures.pm  Liquidity.pm
      Strategy_Builder.pm  VolumeProfile.pm  AnchoredVWAP.pm
      Mxwll_Suite.pm  ZigZag.pm
    Overlays/                   # RENDER
      Base.pm  Example.pm
      SMC_Structures.pm  Liquidity.pm  Strategy_Builder.pm
      VolumeProfile.pm  AnchoredVWAP.pm  Mxwll_Suite.pm  ZigZag.pm
    Panels/
      PricePanel.pm  ATRPanel.pm  Scales.pm
    UI/
      Callbacks.pm  ReplayPanel.pm  ReplayDropdown.pm
      ReplayGotoMenu.pm  ReplaySpeedMenu.pm  ReplayIntervalMenu.pm
    Debug/                      # arquitecto only
      TimeAxisSnapshot.pm  IndicatorSnapshot.pm
  Data/
    2026_07_20.csv  # default; demás CSV = históricos/fallback
  assets/                       # cursores XBM (Select Bar)
  docs/                         # SDD + handoffs + material_profesor/
    reference_indicators/       # Pine/TV originals (LuxAlgo, Mxwll, DIY, ZigZag…)
  specs/                        # qué y por qué
  tasks/                        # unidades de trabajo (0000*–0062+)
  t/                            # suite Test::More (29 archivos)
  scratch/                      # probes/capturas (no producto)
```

## Flujos principales

1. **Carga y agregación:** CSV → `MarketData` (1m) → `build_timeframes` (fronteras de reloj).
2. **Render:** `ChartEngine.compute_window` → `Scales` → `PricePanel`/`ATRPanel` + ejes.
3. **ATR base:** `IndicatorManager` con `update_last`; al cambiar TF, `reset_all` + recálculo.
4. **Overlays pesados:** alimentación **bajo demanda** solo si la capa está visible
   (`sync_overlay_indicators`). Liquidez puede alimentarse por chunks no bloqueantes.
   Overlays dibujan ventana visible + contexto; respetan `replay_idx`.
5. **Replay:** `ReplayController` fija índice-tope; indicadores/overlays solo hasta ese índice
   (cero fuga de futuro, `t/16` y regresiones posteriores). UI en pestaña Replay (Select Bar,
   play, jump-to-real-time, atajos de ventana).

## Integraciones externas

Ninguna en runtime (app de escritorio local). Dependencias CPAN: `Tk`, `Time::Moment`,
y para Fase 3 `AI::MXNet`, `Chart::Plotly`. Datos desde CSV local.

## Riesgos conocidos

- **`ChartEngine.pm` god object** (~3300+ líneas): orquestación + render + ejes + eventos +
  Replay + feed overlays. Ver TECH_DEBT. No refactorizar “de paso”.
- **Rendimiento:** historial de O(n²) en Liq/SMC (resuelto 0016/0017). Cualquier loop
  estructuras×velas es sospechoso; tests sintéticos cortos no bastan.
- **Densidad visual:** controlada por filtros en origen + slider de densidad + tope de
  recencia; el profe es sensible al “ruido” de etiquetas.
- **WSLg/Tk:** menubar/Optionmenu rotos; clics en botones con Canvas requieren `Tk::bind` en
  todos los widgets; atajos globales con `$mw->bind(all => ...)`; xdotool poco fiable.
- **Docs vs código:** este archivo y `ARCHITECTURE`/`ROADMAP` se sincronizaron el 2026-07-08;
  si hay duda, **código + `tasks/README.md` + `git log` mandan**.
- Entorno Fedora35 EOL + parches MXNet frágiles; OneDrive junction; gitdir fuera de OneDrive.

## Preguntas abiertas

Ver `docs/ROADMAP.md`. Principales aún abiertas:

- Número final de estados ocultos del HMM (“más de cuatro”).
- Concurrencia liquidez→estructura (spec 0006): diseño de pesos y cableado.
- Normalizar vs estandarizar antes de Pearson (Fase 3).
- Parámetros calibrables (k, N, umbrales de volumen) — valores base del PDF, ajustables.

**Cerradas por implementación (antes abiertas):**

- Ubicación de packages: Replay → `ReplayController`; VolumeProfile y AnchoredVWAP →
  `Indicators/` + `Overlays/` como el resto.
- Fibonacci: niveles estándar; en TF bajas solo 3 niveles (task 0060).
