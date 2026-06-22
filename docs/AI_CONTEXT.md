# AI Context

Resumen reutilizable del proyecto para que cualquier sesión de IA recupere contexto rápido.
Última actualización: 2026-06-22 (cierre funcional 1ª entrega Fase 2 + rediseño de UI).

## Producto

Plataforma de trading/charting financiero tipo TradingView, construida en Perl 5 + Tk.
Renderiza velas OHLCV con indicadores técnicos, paneles sincronizados e interacciones de
usuario (zoom, drag, crosshair, timeframes). Es la base de visualización sobre la que se
montan, en el segundo bimestre, los modelos de Machine Learning (HMM/Viterbi tensorial)
para predecir cambios de estructura de mercado (no precio vela a vela).

Contexto académico: asignatura de IA y Aprendizaje Automático, EPN 2026A, GR1SW.
Integrantes: Bryan Ayala, Juan Chugá, Sebastián Jibaja, Oscar Tamayo.
Repo remoto: `https://github.com/amsipan/ProyectoIAAA` (branch `main`).

## Usuarios objetivo

- El estudiante/operador que analiza estructura de mercado de forma visual e interactiva.
- El profesor que evalúa contra una rúbrica y un PDF de especificación por fase.
- Las fases posteriores de ML, que consumen las etiquetas (BOS/CHoCH/FVG/liquidez,
  ATR por bins, volumen) como observaciones discretas para entrenar el HMM.

## Estado por fases

- **Fase 1 (Primer bimestre) — COMPLETADA y evaluada (89/100).** Motor gráfico, paneles,
  ATR, interacciones de UI, 3 timeframes (1m/5m/15m).
- **Fase 2 (Segundo bimestre) — 1ª ENTREGA FUNCIONALMENTE COMPLETA (código).** Todo el
  contenido mínimo del PDF para el 29/06 está implementado y verificado por tests:
  8 timeframes, sistema Replay sin fuga de futuro, arquitectura de Overlays, motor SMC
  (BOS/CHoCH/FVG/Fibonacci), módulo de liquidez (swings/EQH/EQL/BSL/SSL, FSM Sweep/Grab/Run,
  volumen multi-TF, 7 zonas), y UI (TF/Replay/toggles). **672 tests PASS** (`t/00`–`t/18`).
  Pendiente: aceptación visual final del usuario y la 2ª entrega (13/07: SMC unificado con
  concurrencia, Strategy Builder, Volume Profile, Anchored VWAP).
- **Fase 3 (ML recurrente) — FUTURA.** HMM + Viterbi tensorial (órdenes superiores),
  posibles LSTM/Transformers. Insumo: las etiquetas que produce la Fase 2.

## Módulos principales (estado actual)

### Fase 1 (base)
- `market.pl` — punto de entrada; UI Tk INLINE (sin menubar ni Optionmenu — ver TECH_DEBT
  F6/F7), controles, tema, orquestación inicial. Las acciones de la barra se construyen con
  factorías de `Market/UI/Callbacks.pm`.
- `Market/MarketData.pm` — capa de datos: OHLCV, 8 timeframes (1m/5m/15m/1h/2h/4h/D/W) por
  fronteras de reloj (W=lunes ISO), slicing (soporta índices negativos), anclas.
- `Market/ChartEngine.pm` — orquestador: render, zoom, drag, crosshair, ejes, Replay,
  overlays (archivo grande, ~2600 líneas; god object — ver TECH_DEBT).
- `Market/IndicatorManager.pm` — contenedor genérico de indicadores desacoplados.
- `Market/Indicators/ATR.pm` — ATR (14 periodos, incremental O(1) por vela).
- `Market/Panels/{PricePanel,ATRPanel,Scales}.pm` — render de velas/ATR + conversión datos↔píxeles.

### Fase 2 (implementados)
- `Market/Indicators/SMC_Structures.pm` — cálculo PURO de zigzag (HH/HL/LL/LH por FSM),
  BOS/CHoCH (true/false), major high/low, FVG con mitigación progresiva, Fibonacci. Getters
  NO-mutantes (idempotentes, task 0014). Poda de FVGs inactivos para rendimiento (0017).
- `Market/Overlays/SMC_Structures.pm` — render en Canvas (tag `ov_smc`); tope de recencia.
- `Market/Indicators/Liquidity.pm` — swings, EQH/EQL (tol `ATR*0.10`), BSL/SSL, FSM
  Sweep/Grab/Run (5 estados), volumen multi-TF por timestamp (0013), 7 zonas. Optimizado con
  cache de epochs + prefix-sum + búsqueda binaria (0016).
- `Market/Overlays/Liquidity.pm` — render Tabla 2 del PDF (tag `ov_liq`); toggles por elemento.
- `Market/ReplayController.pm` — índice-tope de Replay; truncado sin fuga de futuro (0002/0015).
- `Market/OverlayManager.pm` + `Market/Overlays/{Base,Example}.pm` — patrón base de overlays.
- `Market/UI/Callbacks.pm` — factorías puras (sin Tk) de callbacks de la barra; testeables headless.
- `Market/Debug/TimeAxisSnapshot.pm` — diagnóstico removible del eje temporal. Captura por estado o rango (`timeframe`/`start_ts`/`end_ts`/`canvas_width`): labels, X, índices, timestamps, cadencia, `bar_w`, gaps, deltas. No es producto final; sirve para comparar con TradingView sin screenshots.
- `Market/Debug/IndicatorSnapshot.pm` — diagnóstico removible y genérico de indicadores/overlays. Convierte la salida estructurada (items `index`/`type`/`price`/`state`/`meta`) en texto determinista comparable en tests, con guard de Replay. Contrato y patrón: `docs/PHASE2_DEBUG_CONTRACT.md`. Self-test: `t/08`. **Capa del arquitecto; el implementor no la edita.**

## Módulos a crear (2ª entrega Fase 2 — aún NO existen)

- `Market/Indicators/Strategy_Builder.pm` + `Market/Overlays/Strategy_Builder.pm` — SuperTrend,
  HalfTrend, Range Filter, Supply, Demand.
- Volume Profile y Anchored VWAP (ubicación de package por confirmar; ver specs 0008/0009).
- Concurrencia liquidez→estructura (pesos de probabilidad; spec 0006).

## Stack detectado

- **Lenguaje:** Perl 5 (POO con `bless`, `package`).
- **GUI:** Tk (Canvas). Confirmado en código y PDF.
- **Tensores/ML (Fase 2-3):** AI::MXNet (NDArray) — slice estilo NumPy, GPU opcional.
  Requiere parches MXNet en Fedora35 (ver `docs/SETUP_FEDORA35.md`).
- **Gráficas de análisis (PCC/heatmap):** Chart::Plotly (en los ejemplos del profesor).
- **Datos:** `Data/2026_03.csv` — 29.888 velas 1-minuto; aunque el nombre dice `03`, el contenido real va de `2026-04-01T00:00:00-05:00` a `2026-04-30T23:59:00-05:00`. Comparación visual confirmada contra TradingView `NQ1!` (NASDAQ 100 E-mini Futures, CME) en 15m, zona `UTC-5` Bogotá/Quito.
- **Tiempo:** `Time::Moment`.
- **Entorno:** WSL Fedora35 (EOL; mirrors en `archives.fedoraproject.org`). WSLg para GUI.
- **VCS:** Git.

## Estructura de carpetas

```
ProyectoIAAA/
  market.pl                     # entrada, UI Tk inline (controles, sin popups)
  Market/
    MarketData.pm               # datos: 8 timeframes
    ChartEngine.pm              # orquestador/render/zoom/drag/replay/overlays
    IndicatorManager.pm         # contenedor de indicadores
    ReplayController.pm         # índice-tope de Replay (Fase 2)
    OverlayManager.pm           # registro de overlays (Fase 2)
    Indicators/                 # CÁLCULO (sin Tk)
      ATR.pm
      SMC_Structures.pm         # Fase 2 (zigzag/BOS/CHoCH/FVG/Fib)
      Liquidity.pm              # Fase 2 (swings/EQH/EQL/BSL/SSL/FSM/volumen/zonas)
    Overlays/                   # RENDER (Fase 2)
      Base.pm  Example.pm
      SMC_Structures.pm  Liquidity.pm
    Panels/
      PricePanel.pm  ATRPanel.pm  Scales.pm
    UI/
      Callbacks.pm              # factorías de callbacks de la barra (Fase 2)
    Debug/                      # diagnóstico removible (capa del arquitecto)
      TimeAxisSnapshot.pm  IndicatorSnapshot.pm
  Data/2026_03.csv
  docs/                         # documentación SDD (esta carpeta)
    PHASE2_DEBUG_CONTRACT.md    # contrato de verificación por debug (Fase 2)
    material_profesor/          # PDFs/docx originales del profesor + textos extraídos
  specs/                        # qué construir y por qué
  tasks/                        # unidades de trabajo (0000*–0018)
  t/                            # 19 archivos de test (t/00–t/18), 672 tests
```

## Flujos principales

1. **Carga y agregación de datos:** `market.pl` lee el CSV → `MarketData` almacena 1m y
   construye 5m/15m por fronteras reales de reloj (`_bucket_timestamp`).
2. **Render del chart:** `ChartEngine` calcula la ventana visible (offset desde el final),
   delega a `PricePanel`/`ATRPanel` usando `Scales` para mapear datos↔píxeles.
3. **Indicadores:** `IndicatorManager` propaga cada vela a los indicadores (`update_last`,
   O(1)); al cambiar timeframe se hace `reset_all` + recálculo vela por vela.
4. **(Fase 2) Overlays SMC/Liquidez:** alimentación BAJO DEMANDA — el indicador pesado solo
   se calcula cuando su capa está visible (`sync_overlay_indicators`). Con las capas OFF al
   abrir, el arranque es instantáneo (solo velas+ATR como Fase 1). Los overlays dibujan solo la
   estructura reciente (tope de recencia) sobre la ventana visible, respetando el `replay_idx`.
5. **(Fase 2) Replay:** `ReplayController` fija un índice-tope; indicadores y overlays se
   recalculan SOLO hasta ese índice (cero fuga de futuro, verificado en `t/16`).

## Integraciones externas

Ninguna en runtime (app de escritorio local). Dependencias CPAN: `Tk`, `Time::Moment`,
y para Fase 2/3 `AI::MXNet`, `Chart::Plotly`. Datos desde archivo CSV local.

## Riesgos conocidos

- **Aceptación visual pendiente:** el código de la 1ª entrega pasa 672 tests, pero la
  validación visual con el usuario sigue abierta. Última ronda (task 0018) corrigió fallos de
  UI: barra saturada/popups (menubar y Optionmenu abrían ventanas X erráticas bajo WSLg → ahora
  controles inline), toggles que no restauraban líneas, arranque pesado (alimentación bajo
  demanda), overlays amontonados (tope de recencia), y regresión del paneo izquierdo (espacio
  vacío restaurado). Verificar en GUI antes de cerrar formalmente.
- **Rendimiento a escala:** los indicadores SMC/Liquidity tenían O(n²) que colgaba la app con
  las 29888 velas (tasks 0016/0017, resueltas). Lección: los tests usaban 10-35 velas y no lo
  detectaban; añadir cotas de tiempo a escala en features pesadas futuras.
- `ChartEngine.pm` es muy grande (~2600 líneas) y concentra orquestación + render + ejes +
  eventos + Replay + overlays: god object. Ver TECH_DEBT.
- Validación visual contra TradingView: apoyarse primero en `Market/Debug/TimeAxisSnapshot.pm`
  (eje) y `Market/Debug/IndicatorSnapshot.pm` (indicadores); el usuario solo confirma percepción.
- El entorno (Fedora35 EOL + parches MXNet manuales) es frágil de reproducir.
- El proyecto vive en OneDrive vía junction `C:\m\...`; algunas herramientas no "ven"
  archivos hidratados desde la nube en listados recursivos (cosmético).
- WSL no tiene salida a github:443 (timeouts); el backup se sube con git de Windows. Hay dos
  copias del repo: canónica en OneDrive (`/mnt/c/m/...`) y copia de trabajo en Fedora
  (`~/Documents/ProyectoIA/ProyectoIAAA`), que se sincroniza por `cp -a` desde la canónica.

## Preguntas abiertas

Ver `docs/ROADMAP.md` (decisiones pendientes) y la sección 18 de
`../Requisitos_Proyecto_2do_Bimestre.md`. Principales: número final de estados del HMM,
ubicación de packages para Replay/VolumeProfile/VWAP, parámetros exactos de tolerancias.
