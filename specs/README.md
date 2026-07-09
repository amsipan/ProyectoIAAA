# Specs

Una spec describe QUÉ se quiere y POR QUÉ, no el cómo técnico detallado. Cada spec se
implementa vía una o más tasks en `tasks/`. Fuente de verdad de los requisitos:
`../docs/material_profesor/Especificacion_Proyeto_2a_Fase.pdf` + transcripciones de clase.

**Estado de implementación (2026-07-08):** columna *Estado en repo* es orientativa; el detalle
de tasks está en `tasks/README.md`. Las specs **no se reescriben** al implementar (convención);
solo se anota aquí el estado para evitar mapas mentales desfasados.

## Índice de specs

| Spec | Tema | Entrega | Prioridad | Estado en repo |
|------|------|---------|-----------|----------------|
| 0000 | Pulido Fase 1: etiqueta TradingView del crosshair + grid temporal equidistante (parcial: crosshair aceptado; criterio de grid reemplazado por 0000b) | Antes de Fase 2 | Alta | ✅ cerrado vía 0000–0000j |
| 0000b | Eje temporal inferior TradingView por fronteras reales de reloj/calendario | Antes de Fase 2 | Alta | ✅ |
| 0000c | Pulido post-0000b: ticks 90m en gaps, crosshair con hora y paneo suave | Antes de Fase 2 | Alta | ✅ |
| 0000d | Regresiones visuales post-0000c: crosshair en eje temporal y control de ticks/grid en gaps | Antes de Fase 2 | Alta | ✅ |
| 0000e | Coherencia lógica del eje temporal: índices reales y crosshair alineado | Antes de Fase 2 | Alta | ✅ |
| 0000f | Tickmarks ponderados tipo TradingView/Supercharts | Antes de Fase 2 | Alta | ✅ (superseded visualmente por 0000g) |
| 0000g | Cadencia global uniforme del eje temporal tipo TradingView (Modo A) | Antes de Fase 2 | Alta | ✅ |
| 0001 | Temporalidades extendidas (1m..W) | 29/06 | Alta | ✅ |
| 0002 | Sistema Replay | 29/06 | Alta | ✅ (+ UX TV 0041–0053) |
| 0003 | Arquitectura base de Overlays | 29/06 | Alta (habilitador) | ✅ |
| 0004 | SMC Structures (BOS/CHoCH/FVG/Fibonacci) | 29/06 + 13/07 | Alta | ✅ (+ calibración 0056/0059/0060) |
| 0005 | Módulo de Liquidez (swings, EQH/EQL, sweep/grab/run, FSM) | 29/06 + 13/07 | Alta | ✅ (+ 0054/0055/0057/0058/0062) |
| 0006 | Concurrencia Liquidez → BOS/CHoCH (pesos de probabilidad) | 13/07 | Media | ⏳ pendiente formalizar/implementar pesos |
| 0007 | DIY Custom Strategy Builder | 13/07 | Media | ✅ código + `t/19` |
| 0008 | Perfil de Volumen avanzado | 13/07 | Media | ✅ código + `t/20` |
| 0009 | Anchored VWAP multipivot | 13/07 | Media | ✅ código + `t/21` |
| 0010 | UI: timeframe + toggles + controles Replay | 29/06 | Alta | ✅ (inline/pestañas; no menubar) |
| 0011 | (Fase 3) HMM + Viterbi tensorial (MXNet) | Fin semestre | Futura | ⏳ no iniciado |
| 0012 | (Fase 3) Selección de features con Pearson/PCC | Fin semestre | Futura | ⏳ no iniciado |

Extras en producto no cubiertos por una sola fila de la tabla PDF: **Mxwll Suite**, **ZigZag**
interno/externo + canal clásico (ver tasks 0021+, 0033, 0061).

## Plantilla

```
# Spec: [nombre]

## Objetivo

## Problema

## Usuarios afectados

## Comportamiento esperado

## Fuera de alcance

## Criterios de aceptación

## Casos límite

## Plan de verificación
```

## Convenciones

- Las specs no cambian; si un requisito cambia, se versiona o se añade una nueva.
- Cada spec enlaza el apartado del PDF oficial y la(s) clase(s) relevante(s).
- Los parámetros numéricos llevan su valor inicial del PDF y se marcan como "calibrable".
- El estado de implementación se actualiza en este README y en `tasks/README.md`, no reescribiendo el cuerpo de cada spec.
