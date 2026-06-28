# Arquitectura

Estado real del sistema. Separa lo implementado (Fase 1 + 1ª entrega Fase 2) de lo planificado (2ª entrega Fase 2 / Fase 3).
Última actualización: 2026-06-28.

## Diagrama (texto)

```
                          market.pl  (Capa Aplicación)
                          - crea ventana Tk, tema, controles
                          - lee CSV, instancia MarketData
                          - instancia ChartEngine y arranca loop
                                   |
                                   v
        +-------------------- ChartEngine.pm --------------------+
        | (orquestador: ventana de datos, eventos, render coord) |
        |   conoce a: paneles, escalas, (Fase2) overlays         |
        +----+-------------------+--------------------+----------+
             |                   |                    |
             v                   v                    v
        PricePanel.pm        ATRPanel.pm          (Fase 2)
        (render velas)       (render ATR)         Overlays/*.pm
             |                   |                 (render SMC,
             +---------+---------+                  Liquidity,
                       v                            Strategy)
                   Scales.pm
              (datos <-> pixeles;
               X compartida, Y por panel)

   Capa Datos:        MarketData.pm  (OHLCV, timeframes, slicing, anclas)
   Capa Indicadores:  IndicatorManager.pm  ->  Indicators/ATR.pm
                      (Fase 2) Indicators/{SMC_Structures,Liquidity,Strategy_Builder}.pm
   Capa Debug:        Market/Debug/TimeAxisSnapshot.pm   (eje temporal)
                      Market/Debug/IndicatorSnapshot.pm  (indicadores/overlays Fase 2)
                      (diagnóstico removible; no participa en render/producto final)
```

## Capas del sistema

1. **Datos** — `MarketData.pm`. Almacena OHLCV en 1m y agrega a 5m/15m/1h/2h/4h/D/W por fronteras reales
   de reloj (W = lunes ISO). Acceso por índice, slicing, última vela y anclas temporales. El tope de Replay
   vive en `ReplayController`, no dentro de la capa de datos.
2. **Indicadores (cálculo, sin Tk)** — `IndicatorManager.pm` + `Indicators/`. Contrato:
   `update_last`, `get_values`, `reset`. ATR es O(1) por vela. (Fase 2: SMC_Structures,
   Liquidity, Strategy_Builder.)
3. **Renderizado** — `ChartEngine.pm`, `Panels/*`, `Scales.pm`. (Fase 2: `Overlays/` para
   dibujar estructuras/liquidez/estrategias sobre el Canvas.)
4. **Aplicación** — `market.pl`. Punto de entrada y orquestación inicial.
5. **Debug removible** — `Market/Debug/`. No renderiza ni muta permanentemente la app.
   - `TimeAxisSnapshot.pm`: replica las conversiones del motor para capturar, por estado actual o
     por rango explícito, lo que se dibuja en el eje temporal (labels, coordenadas, índices,
     timestamps, `bar_w`, cadencia, gaps, deltas X y resumen textual).
   - `IndicatorSnapshot.pm` (Fase 2): convierte la salida estructurada de cualquier indicador/overlay
     (items con `index`/`type`/`price`/`state`/...) en texto determinista comparable en tests, e
     incluye el guard de Replay (cero items con índice > tope). Contrato en
     `docs/PHASE2_DEBUG_CONTRACT.md`. **Capa propiedad del arquitecto; el implementor no la edita.**
   Se mantiene fuera de `ChartEngine.pm` para poder omitirla al final sin afectar las clases
   principales pedidas por el profesor.

## Flujo de datos

CSV → `MarketData.add_candle` (1m) → `build_timeframes` (5m/15m/1h/2h/4h/D/W) → `ChartEngine.compute_window`
(qué rango es visible, offset desde el final y tope efectivo de Replay) → `Scales` mapea índice/valor a píxeles →
`PricePanel`/`ATRPanel` dibujan. Indicadores base: cada vela se propaga con `update_last`; al
cambiar timeframe, `reset_all` + recálculo vela por vela (O(N)). Indicadores pesados de overlays: alimentación bajo demanda solo cuando su capa está visible.

(Fase 2) El Replay fija un índice tope; indicadores y overlays solo calculan hasta ese índice
(jamás velas futuras). Overlays SMC/Liquidez calculan sobre velas visibles + ventana de
contexto, no sobre todo el historial.

## Dependencias principales

- `Tk` (Canvas, eventos), `Time::Moment` (timestamps). Confirmadas en código.
- (Fase 2/3) `AI::MXNet` (NDArray, tensores, corrcoef), `Chart::Plotly` (heatmaps/scatter de
  análisis). Confirmadas en el material del profesor.
- Datos: `Data/2026_03.csv` contiene abril 2026 (`2026-04-01` a `2026-04-30`, zona `UTC-5`), 29.888 velas 1m. La calibración visual se hace contra TradingView `NQ1!` / NASDAQ 100 E-mini Futures / CME en 15m.

## Estado actual (qué funciona hoy — Fase 1)

- Render de velas + ATR con paneles sincronizados.
- Zoom (rueda, Ctrl+rueda con ancla), drag horizontal, downsample por píxel.
- Crosshair sincronizado, snap a centro de vela, labels de precio/tiempo.
- Eje temporal estilo TradingView en cierre de `0000g`: `compute_intraday_labels()` elige un plan global de cadencia por ventana con **Modo A obligatorio** (días + horas uniformes), preserva gaps reales comprimidos por índice lógico y evita thinning por peso que degradaba 90m a 3h. El caso calibrado NQ1!/CME 15m UTC-5 `2026-04-29T15:00 -> 2026-05-01T00:00` se verifica por `Market/Debug/TimeAxisSnapshot.pm` y `t/07-time-axis-global-cadence.t` con la secuencia TradingView esperada.
- Timeframes 1m/5m/15m con agregación por fronteras reales.
- ATR 14 con modo auto/manual independiente y controles propios.
- Validado contra la rúbrica (89/100); según observación actual, está más cerca del 100% al cerrar los detalles de spec `0000`.

## Estado actual (qué funciona hoy — Fase 2, 1ª entrega)

- **8 timeframes** (1m/5m/15m/1h/2h/4h/D/W) por fronteras de reloj; W=lunes ISO (`MarketData`).
- **Sistema Replay** (`ReplayController` + `ChartEngine::sync_overlay_indicators`): índice-tope;
  indicadores/overlays se recalculan SOLO hasta `replay_idx` (cero fuga de futuro, `t/16`).
- **Overlays** (`OverlayManager` + `Overlays/`): patrón base con tag de Canvas propio, toggles,
  alimentación BAJO DEMANDA (solo si la capa está visible) y tope de recencia (vista legible).
- **SMC** (`Indicators/SMC_Structures` + overlay): zigzag HH/HL/LL/LH por FSM, BOS/CHoCH
  true/false, major high/low, FVG con mitigación, Fibonacci. Getters idempotentes (`0014`).
- **Liquidez** (`Indicators/Liquidity` + overlay): swings, EQH/EQL (`ATR*0.10`), BSL/SSL, FSM
  Sweep/Grab/Run (5 estados), volumen multi-TF por timestamp, 7 zonas, interno/externo.
- **UI inline** (`market.pl` + `UI/Callbacks`): controles en la ventana (sin menubar ni
  Optionmenu, que abrían popups X erráticos bajo WSLg); TF/capas/Replay/escala/Reset.
- **Rendimiento:** Liquidity 272s→5.8s (`0016`), SMC 37.6s→2.9s (`0017`); arranque instantáneo
  con capas OFF. Verificado contra las 29888 velas reales.
- **672 tests** (`t/00`–`t/18`) en verde. Pendiente: aceptación visual final del usuario.

## Problemas arquitectónicos (con evidencia)

- **`ChartEngine.pm` ~2600 líneas.** Concentra orquestación, render de 3 ejes, eventos de
  mouse/teclado, zoom, drag, cursores, Replay y overlays. God object. Evidencia: inventario de
  subs (`_render_price_axis`, `_render_time_axis`, `_render_atr_axis`, `_draw_*_crosshair`,
  `_wheel_zoom_delta`, `sync_overlay_indicators`, etc.).
  Recomendación: aislar el control de Replay y el registro de overlays en colaboradores
  dedicados (ya hay `ReplayController` y `OverlayManager`; falta sacar más lógica de render). (Ver TECH_DEBT.)
- **Registro de overlays presente.** `OverlayManager` ya centraliza overlays activables; Fase 2
  lo usa para SMC/Liquidez. Falta extraerle a ChartEngine el feeding y el render-loop (análogo a
  `IndicatorManager` pero para render).
- **Acoplamiento timeframe → recálculo total de indicadores.** Hoy O(N) por timeframe está
  bien para ATR; SMC/Liquidez son más caros, de ahí la regla de "solo velas visibles +
  contexto" del PDF y la alimentación bajo demanda (tasks 0016/0017/0018).
- **Tests automatizados presentes.** Suite `t/00`–`t/18` con Test::More (672 tests): sintaxis,
  regresión, eje temporal, indicadores SMC/Liquidez (vía debug snapshot), Replay, overlays y UI.
  Para los algoritmos de ML (Viterbi, Pearson) hay valores de referencia que permitirán tests
  deterministas en Fase 3.

## Recomendaciones futuras (no obligaciones inmediatas)

- Extraer de `ChartEngine.pm` más lógica de alimentación/render-loop de overlays hacia colaboradores dedicados; `OverlayManager` y `ReplayController` ya existen.
- Mantener el patrón uniforme de `Market/Overlays/` (cada overlay: `compute_visible`, `draw`, `set_visible`) para Strategy Builder, Volume Profile y VWAP.
- Añadir tests `.t` (Test::More) para Viterbi tensorial y Pearson usando los valores de referencia del material del profesor.
- A mediano plazo, evaluar partir `ChartEngine` (render de ejes vs orquestación de eventos).
