# Roadmap

Última actualización: 2026-07-19.

> **Plan de dirección vigente (meta modelos + orden de trabajo):**  
> **`docs/PLAN_DEFINITIVO.md`**.  
> Este `ROADMAP.md` conserva el histórico de entregas PDF y notas antiguas; si hay
> conflicto de prioridades, manda `PLAN_DEFINITIVO.md`.

Fechas del PDF oficial de Fase 2 (`docs/material_profesor/Especificacion_Proyeto_2a_Fase.pdf`).
Estado de tasks: `tasks/README.md`.

## Estado actual

- **Fase 1** completa y evaluada (89/100): motor gráfico, paneles, ATR, interacciones, 1m/5m/15m.
- Eje temporal TradingView cerrado en `0000g`–`0000j`.
- **1ª entrega Fase 2 (29/06) — completa en código:** temporalidades 1m..W, Replay, Overlays,
  SMC, Liquidez, UI, optimizaciones 0016/0017.
- **2ª entrega Fase 2 (13/07) — gran parte implementada y testeada:**
  - Strategy Builder, Volume Profile, Anchored VWAP (`t/19`–`t/21`).
  - Mxwll Suite, ZigZag + canal de tendencia (`t/22`, `t/24`).
  - Replay calque TradingView (0041–0053; 0047 baja prio; 0053 pausado WSLg).
  - Feedback profe/QA 0054–0062 (densidad, anclajes, recolor RUN, Fib TF bajas, slider, etc.).
  - Fixes recientes: overlays estables en zoom/pan, grid, ZigZag continuo, Fib Mxwll,
    anti-solapamiento etiquetas SMC.
- Suite de tests: **29 archivos** en `t/`.

## Objetivo inmediato

- Cerrar restos de pulido UX/visual que el profe o Bryan marquen (issues puntuales → task nueva).
- Decidir y, si aplica, formalizar **spec 0006** (concurrencia liquidez→estructura).
- Mantener docs/código alineados; no abrir Fase 3 sin entorno MXNet verificado.

## Objetivo 1ª entrega — 29/06 (PDF) — CUMPLIDO en código

- Múltiples temporalidades; Replay sin futuro; Overlays; SMC (BOS/CHoCH/FVG); Liquidez + FSM.

## Objetivo 2ª entrega — 13/07 (PDF) — MAYORMENTE CUMPLIDO en código

| Objetivo PDF | Estado en repo |
|--------------|----------------|
| SMC unificado + liquidez interactiva multi-TF | ✅ Implementado + calibrado (0054–0062) |
| DIY Strategy Builder (ST/HT/RF/S/D) | ✅ `Strategy_Builder` + overlay + `t/19` |
| Perfil de Volumen avanzado | ✅ `VolumeProfile` + `t/20` |
| Anchored VWAP multipivot | ✅ `AnchoredVWAP` + `t/21` |
| Concurrencia liquidez→estructura (pesos) | ⏳ Spec `0006` sin lote de tasks formal post-0062 |

Extras no listados como tabla PDF pero en producto: Mxwll, ZigZag MTF, canal clásico, slider
de densidad, Replay UX TradingView.

## Objetivo a fin de semestre (Fase 3 — ML recurrente)

- HMM con Viterbi tensorial (orden 1 → 2 → 3/4) sobre AI::MXNet, con logaritmos (spec `0011`).
- Selección de features con Pearson/PCC (spec `0012`).
- Discretización de data continua a etiquetas enteras (K-Means/KNN, EM, PCA — material U5).
- Posibles LSTM / Transformers (exploración; no confirmados como obligatorios).

## Decisiones pendientes (por confirmar con el profesor)

- **Número final de estados ocultos del HMM.** Base: alcista, bajista, lateral choppy, lateral
  seno + auxiliares. El profesor dice "más de cuatro". Sin número fijo.
- **Diseño de concurrencia liquidez→estructura (spec 0006):** cómo se materializan los pesos
  de probabilidad en UI y en features para el HMM.
- **Parámetros numéricos por calibrar:** tolerancia EQH/EQL (`ATR*0.10`), k de swing, N de
  aceptación Run, umbrales de volumen, pesos por TF. Base PDF; se ajustan por experimentación
  (varios ya endurecidos en 0054–0056).
- **Normalizar vs estandarizar** antes de covarianza/Pearson (Fase 3).

## Decisiones cerradas (implementación)

- **Packages Replay / VolumeProfile / VWAP:** `ReplayController`; VP y VWAP como
  `Indicators/` + `Overlays/` (mismo patrón que SMC/Liquidez).
- **Fibonacci:** niveles estándar 0.236/0.382/0.5/0.618/0.786; en TF bajas solo 3 niveles
  (task 0060). Ancla en major high/low.
- **Replay UX:** panel **inline** en pestaña Replay (no flotante); `>>` = jump-to-real-time;
  etiquetas ASCII por mojibake Fedora35; atajos en bind de ventana.
- **Liquidez:** pivotes externos desde SMC cuando aplica (0055); densidades filtradas en origen
  + slider (0054, 0062).
- **Canal:** tendencia clásico (2 paralelas por pierna), no envelope ATR (0061).

## Features candidatas / exploratorias

- Proyección real de niveles HTF sobre LTF (si el profe la pide; el placeholder UI se eliminó).
- Heatmap de correlación de features (Chart::Plotly) offline.
- App Android / VPS (fuera del alcance académico actual).
- Tijeras vectoriales Select Bar (0047) y cursor SO invisible (0053, limitado por WSLg).
