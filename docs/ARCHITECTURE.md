# Arquitectura

Estado real del sistema. Separa lo implementado (Fase 1 + Fase 2 casi completa) de lo
planificado (restos de Fase 2 / Fase 3).
Última actualización: 2026-07-08.

## Diagrama (texto)

```
                          market.pl  (Capa Aplicación)
                          - ventana Tk, tema, pestañas de controles
                          - lee CSV, instancia MarketData
                          - registra indicadores/overlays, ChartEngine, loop
                                   |
                                   v
        +-------------------- ChartEngine.pm --------------------+
        | (orquestador: ventana, eventos, render, feed overlays) |
        |   conoce: paneles, escalas, OverlayManager, Replay     |
        +----+----------+----------+-------------+---------------+
             |          |          |             |
             v          v          v             v
        PricePanel  ATRPanel  OverlayManager  ReplayController
        (velas)     (ATR)     draw_all /      (índice-tope,
             |          |     compute_all      speed, ticks)
             +-----+----+          |
                   v               v
               Scales.pm     Overlays/*.pm
            (X compartida;   (solo Canvas/Tk)
             Y por panel)          |
                                   | lee items de
                                   v
                         IndicatorManager / Indicators/*.pm
                              (cálculo PURO)

   Capa Datos:   MarketData.pm  (OHLCV, 8 TF, slicing, anclas)
   Capa UI:      Market/UI/*    (Callbacks, ReplayPanel + menús)
   Capa Debug:   Market/Debug/* (TimeAxisSnapshot, IndicatorSnapshot; removible)
```

## Capas del sistema

1. **Datos** — `MarketData.pm`. OHLCV en 1m; agrega 5m/15m/1h/2h/4h/D/W por fronteras reales
   de reloj (W = lunes ISO). Acceso por índice, slicing, anclas. El tope de Replay **no** vive
   aquí: vive en `ReplayController`.
2. **Indicadores (cálculo, sin Tk)** — `IndicatorManager.pm` + `Indicators/`. Contrato base:
   `update_last`, getters estructurados, `reset`. Familia actual:
   `ATR`, `SMC_Structures`, `Liquidity`, `Strategy_Builder`, `VolumeProfile`, `AnchoredVWAP`,
   `Mxwll_Suite`, `ZigZag`.
3. **Renderizado** — `ChartEngine.pm`, `Panels/*`, `Scales.pm`, `Overlays/*` (cada overlay con
   tag de Canvas propio y contrato `Base.pm`).
4. **Aplicación / UI** — `market.pl` + `Market/UI/*`. Controles inline por pestañas; factorías
   de callbacks testeables sin GUI.
5. **Replay** — `ReplayController` (estado de índice/velocidad) + lógica de ventana/visual en
   `ChartEngine` + panel/menús en `UI/Replay*`.
6. **Debug removible** — `Market/Debug/`. No participa en producto final.
   - `TimeAxisSnapshot.pm`: eje temporal (labels, X, cadencia, gaps…).
   - `IndicatorSnapshot.pm`: items de indicadores → texto determinista + guard de Replay.
   **Propiedad del arquitecto; el implementor no la edita.**

## Flujo de datos

CSV → `MarketData.add_candle` (1m) → `build_timeframes` → `ChartEngine.compute_window`
(offset desde el final + tope efectivo de Replay) → `Scales` → `PricePanel`/`ATRPanel` +
`OverlayManager.draw_all`.

- **ATR:** propagación completa al cambiar TF (`reset_all` + O(N)).
- **Overlays pesados:** feed **bajo demanda** si la capa está visible; hasta `replay_idx` si
  Replay activo; a menudo solo ventana visible + contexto (PDF §2). Liquidez puede usar feed
  por chunks no bloqueantes.
- **Replay:** ningún item/vela con índice > tope (verificado en tests de truncado y fugas).

## Dependencias principales

- `Tk` (Canvas, eventos), `Time::Moment` (timestamps).
- (Fase 3) `AI::MXNet`, `Chart::Plotly` — material del profesor; no son runtime de charting.
- Datos: `Data/2026_03.csv` (principal, ~29.888 velas 1m, abril 2026 `UTC-5`); también
  `2026_06_29.csv` y `2026_07_06.csv`. Calibración visual vs TradingView `NQ1!` / CME.

## Estado actual — Fase 1

- Velas + ATR, paneles sincronizados, zoom/drag/crosshair, downsample por píxel.
- Eje temporal estilo TradingView (cadencia global Modo A; `t/07` + TimeAxisSnapshot).
- Timeframes base y ATR 14 auto/manual independiente.
- Evaluado ~89/100 en rúbrica de GUI.

## Estado actual — Fase 2 (1ª + 2ª entrega)

### 1ª entrega (mínimo PDF 29/06) — implementado
- 8 timeframes; Replay sin fuga de futuro; patrón Overlays; SMC; Liquidez; UI inline;
  optimizaciones 0016/0017.

### 2ª entrega y extensiones — implementado
- **Strategy Builder** (SuperTrend, HalfTrend, Range Filter, Supply/Demand).
- **Volume Profile** y **Anchored VWAP**.
- **Mxwll Suite** y **ZigZag** (interno/externo, canal de tendencia clásico).
- **Replay UX TradingView:** Select Bar, panel inline, velocidades/intervalos, Go-to,
  jump-to-real-time, atajos de teclado, marca de agua (lote 0041–0053; ver `tasks/README.md`).
- **Calibración profe/QA:** densidad BSL/SSL, anclaje liquidez a pivotes SMC, menos pivotes
  ruidosos, EQH/EQL INT/EXT, recolor velas RUN, FVG near price en SMC, Fib 3 niveles en TF
  bajas, slider de densidad, canal clásico (0054–0062).
- **UI:** pestañas Capas/SMC/Liq/Mxwll/ZigZag/Estrategia/Escala/Replay; grid toggle.
- **Tests:** 29 archivos en `t/` (suite extendida más allá de `t/00`–`t/18`).

### Aún no / parcial
- Concurrencia liquidez→estructura con pesos (spec `0006`).
- Pulidos: 0047 tijeras vectoriales; 0053 cursor SO invisible (pausado WSLg).
- Fase 3 ML (Viterbi, Pearson).

## Problemas arquitectónicos (con evidencia)

- **`ChartEngine.pm` ~3300+ líneas.** Sigue concentrando orquestación, ejes, eventos, zoom,
  visuals de Replay y feed de overlays. `ReplayController` y `OverlayManager` ya extraen parte
  del dominio, pero el feed/render-loop de overlays y mucho de Replay visual siguen aquí.
  **No refactorizar masivamente sin spec propia.**
- **Feed de overlays aún acoplado a ChartEngine.** `sync_overlay_indicators` y helpers de
  liquidez viven en el orquestador; ideal a medio plazo: colaborador dedicado.
- **Cambio de timeframe → reset/recálculo** de indicadores activos. Mitigado con under-demand
  y chunks, pero sigue siendo un eje de coste.
- **Tests de cota temporal** pueden ser flaky bajo CPU cargada (ver TECH_DEBT).

## Recomendaciones futuras (no obligaciones inmediatas)

- Extraer feed/render-loop de overlays y más lógica de Replay visual fuera de `ChartEngine`.
- Mantener el patrón `Indicators/` + `Overlays/` para cualquier capa nueva.
- Formalizar tasks de spec `0006` (concurrencia) antes de improvisar pesos en producción.
- Añadir tests de Viterbi/Pearson en Fase 3 con valores de referencia del material del profe.
- Partir ChartEngine (ejes vs eventos) solo con ADR + task grande, no "de paso".
