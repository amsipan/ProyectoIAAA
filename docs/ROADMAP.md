# Roadmap

Última actualización: 2026-06-22. Separa estado actual de objetivos. Las fechas vienen del
PDF oficial de Fase 2 (`docs/material_profesor/Especificacion_Proyeto_2a_Fase.pdf`).

## Estado actual

- Fase 1 completa y evaluada (89/100): motor gráfico, paneles, ATR, interacciones, 1m/5m/15m.
- Eje temporal TradingView cerrado en `0000g`–`0000j` (tests verdes, snapshot de debug).
- **1ª entrega Fase 2 funcionalmente completa (código).** Todo el contenido mínimo del PDF
  para el 29/06 está implementado y verificado por **672 tests** (`t/00`–`t/18`):
  - Temporalidades 1m/5m/15m/1h/2h/4h/D/W (`0001`).
  - Sistema Replay sin fuga de futuro (`0002`, `0015`).
  - Arquitectura base de Overlays (`0003`).
  - Motor SMC: zigzag/BOS/CHoCH/FVG/Fibonacci (`0005`–`0007`), getters idempotentes (`0014`).
  - Módulo de liquidez: swings/EQH/EQL/BSL/SSL, FSM Sweep/Grab/Run, volumen multi-TF, 7 zonas
    (`0009`–`0011`, `0013`).
  - Render de overlays SMC y Liquidez (`0008`, `0012`).
  - UI: timeframes + Replay + toggles (`0004`), rediseñada a controles inline (`0018`).
  - Rendimiento: corregidos cuelgues O(n²) en Liquidity y SMC con el dataset real (`0016`, `0017`).
- **Pendiente para cerrar la 1ª entrega:** aceptación visual final del usuario en la GUI
  (varias rondas hechas; última en `0018d` restauró el paneo izquierdo de Fase 1).

## Objetivo inmediato — aceptación visual de la 1ª entrega

- Validar en GUI (WSLg): arranque instantáneo, cambio de TF, capas SMC/Liquidez legibles
  (tope de recencia), Replay sin futuro, paneo con espacio a ambos lados y sin temblor, y que
  Fase 1 (zoom/drag/crosshair) siga intacta.
- Si algo falla, registrar el fallo en una task `0018x` antes de corregir (como F1–F7).

## Objetivo a la 1ª entrega — 29/06 (contenido mínimo exigido por el PDF)

- Motor base con soporte de **múltiples temporalidades** (1m,5m,15m,1h,2h,4h,D,W).
- **Sistema Replay funcional**, sin filtración de velas futuras.
- **Arquitectura base de Overlays** gráficos (`Market/Overlays/`).
- Avances del **motor analítico de SMC** con etiquetas ubicadas en el tiempo (BOS/CHoCH).
- **FVG** con desvanecimiento progresivo (mitigación).
- **Módulo de liquidez** implementado (swing points, EQH/EQL, sweep/grab/run, máquina de estados).

## Objetivo a la 2ª entrega — 13/07

- Sistema SMC unificado completo (Estructuras + FVG + máquina de estados de liquidez
  interactiva con pesado multi-temporal).
- **DIY Custom Strategy Builder** operativo (SuperTrend, HalfTrend, Range Filter, Supply, Demand).
- **Perfil de Volumen avanzado** con modos de contingencia (sesión / BOS-CHoCH / pasado lejano).
- **Anchored VWAP** multipivot (5 tipos de anclaje).

## Objetivo a fin de semestre (Fase 3 — ML recurrente)

- HMM con Viterbi tensorial (orden 1 → 2 → 3/4) sobre AI::MXNet, con logaritmos.
- Selección de features con Pearson/PCC (descartar columnas redundantes).
- Discretización de la data continua a etiquetas enteras (K-Means/KNN, EM, PCA según material U5).
- Posibles LSTM / Transformers (mencionados como exploración, no confirmados como obligatorios).

## Decisiones pendientes (por confirmar con el profesor)

- **Número final de estados ocultos del HMM.** Base: alcista, bajista, lateral choppy, lateral
  seno + auxiliares de espera/confirmación. El profesor dice "más de cuatro". Sin número fijo.
- **Ubicación de packages para Replay, Volume Profile y Anchored VWAP.** El PDF nombra packages
  para SMC/Liquidity/Strategy_Builder pero no para estos tres. Supuesto razonable: Replay en un
  controlador propio; VolumeProfile y VWAP como Indicator+Overlay igual que el resto.
- **Parámetros numéricos por calibrar:** tolerancia EQH/EQL (PDF: `ATR*0.10`), profundidad k de
  swing (PDF: k=3 inicial), N velas de confirmación de Run/Acceptance (PDF: N=3 inicial), umbral
  de volumen anómalo, pesos por temporalidad. Valores iniciales del PDF; ajustar por experimentación.
- **Normalizar vs estandarizar antes de covarianza/Pearson:** ejercicio abierto que el profesor
  deja para experimentar. Implementar ambos y comparar.
- **Niveles de Fibonacci exactos:** el audio los transcribe mal; usar los estándar (0.236, 0.382,
  0.5, 0.618, 0.786), con 0.618 como nivel clave.

## Features candidatas / exploratorias

- Toggle de niveles HTF sobre gráficos LTF (solapamiento multi-temporal de contexto).
- Heatmap de correlación de features (Chart::Plotly) como herramienta de análisis offline.
- App Android nativa / almacenamiento en VPS (fuera del alcance académico actual).
