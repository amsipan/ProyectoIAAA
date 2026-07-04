# Tasks

Una task convierte (parte de) una spec en trabajo concreto y verificable. Son pequeñas y
pensadas para que un modelo implementor (más barato) las ejecute una a una sin ambigüedad.

## Reglas duras para el implementor (Fase 2)

1. **Verificación por debug obligatoria.** Cada task de indicador/overlay (0005–0012) debe traer un
   test `.t` que compruebe su salida con `Market/Debug/IndicatorSnapshot.pm` contra un esperado
   transcrito en la task. Ver `docs/PHASE2_DEBUG_CONTRACT.md`. "Validación visual" NO cuenta como
   única prueba.
2. **`Market/Debug/` es intocable.** No crear ni modificar nada ahí. Si falta un campo, reportarlo
   al arquitecto.
3. **`prove -l t` debe pasar completo** tras cada task (no solo el archivo nuevo).
4. **No tocar `MarketData.pm` ni `Data/2026_03.csv`** sin autorización humana.

## Cómo usar (para el implementor)
1. Toma la siguiente task no completada en orden de `Orden de ejecución`.
2. Lee la spec enlazada y el material del profesor que cite.
3. Implementa SOLO lo de esa task; respeta "Qué no tocar".
4. Corre los "Comandos de verificación".
5. Marca la task como hecha (checkbox) y pasa a la siguiente.

## Orden de ejecución recomendado

### Cierre Fase 1 — antes de Fase 2

Resolver primero estas tasks visuales. `0000` dejó aceptada la etiqueta del crosshair (`Thu 23 Apr '26`), pero el criterio de grid equidistante quedó reemplazado por `0000b`: TradingView prioriza fronteras reales de reloj/calendario.

| # | Task | Spec | Depende de |
|---|------|------|-----------|
| 0000 | Pulido Fase 1: etiqueta TradingView del crosshair + grid temporal equidistante (parcial; crosshair OK) | 0000 | — |
| 0000b | Eje temporal inferior TradingView por fronteras reales | 0000b | 0000 |
| 0000c | Pulido post-0000b: ticks 90m en gaps, crosshair con hora y paneo suave | 0000c | 0000b |
| 0000d | Regresiones visuales post-0000c: crosshair en eje temporal y control de ticks/grid en gaps | 0000d | 0000c |
| 0000e | Coherencia lógica del eje temporal: índices reales y crosshair alineado | 0000e | 0000d |
| 0000f | Tickmarks ponderados tipo TradingView/Supercharts: días como anchors, formato intradía y cadencias visuales 1m (implementado, pero visualmente insuficiente) | 0000f | 0000e |
| 0000g | Cadencia global uniforme del eje temporal tipo TradingView: Modo A obligatorio con días + horas uniformes; no aceptar modo diario como cierre final | 0000g | 0000f |

### 1ª entrega Fase 2 — 29/06

Los habilitadores van primero porque el resto depende de ellos.

| # | Task | Spec | Depende de |
|---|------|------|-----------|
| 0001 | Temporalidades extendidas en MarketData | 0001 | 0000g |
| 0002 | ReplayController + índice-tope | 0002 | — (**arrancable ya**) |
| 0003 | Patrón base de Overlays + registro | 0003 | — (**arrancable ya**) |
| 0004 | UI: menú de timeframe + controles Replay + toggles | 0010 | 0001,0002,0003 |
| 0005 | Indicators/SMC_Structures: zigzag FSM + HH/HL/LL/LH | 0004 | 0001 |
| 0006 | SMC: BOS/CHoCH (verdadero/falso) + major high/low | 0004 | 0005 |
| 0007 | SMC: FVG con mitigación + Fibonacci | 0004 | 0005 |
| 0008 | Overlays/SMC_Structures: render de estructura | 0004 | 0003,0006,0007 |
| 0009 | Indicators/Liquidity: swings, EQH/EQL, BSL/SSL | 0005 | 0005 |
| 0010 | Liquidity: clasificación Sweep/Grab/Run + FSM 5 estados | 0005 | 0009 |
| 0011 | Liquidity: pesado de volumen multi-TF + 7 zonas | 0005 | 0009,0001 |
| 0012 | Overlays/Liquidity: render Tabla 2 + toggles | 0005 | 0003,0010 |
| 0019 | Regresiones visuales beta: overlays SMC/Liquidez con coordenadas locales y Replay | 0004/0005/0010 | 0008,0012,0015,0018 |
| 0020 | Anclaje de temporalidades a sesión CME/TradingView | 0001/0000g | 0019 |

(2ª entrega — 13/07: concurrencia 0006, strategy builder 0007, volume profile 0008, VWAP 0009.
Fase 3: HMM/Viterbi 0011, Pearson 0012. Se crearán tasks cuando se aborden.)

### Revisión del profe (29/06) — mejoras Mxwll/Liquidez

`0021` es el documento maestro (backlog + cruce con notas del profe + ORDEN 1-9 ya
implementadas). Las órdenes nuevas 10-19 se detallan una por archivo (0022-0031).

| # | Task | Estado |
|---|------|--------|
| 0021 | Volatilidad + ruido CHoCH (maestro; ORDEN 1-9 hechas) | ✅ ORDEN 1-9 |
| 0022 | Estructura: líneas externas sólidas, internas entrecortadas | ✅ hecho |
| 0023 | FVG vigente solo cerca del precio actual | ✅ hecho |
| 0024 | Grab/Run: solapamiento (apilado vertical) | ✅ hecho |
| 0025 | Colorear velas de liquidity RUN | pendiente |
| 0026 | Etiquetar Order Blocks como "OB" | ✅ hecho |
| 0027 | BSL/SSL más limpio en banda (tarea E) | pendiente (DESBLOQUEADA: banda por proximidad) |
| 0028 | Strong/Weak High/Low | pendiente (LuxAlgo trailing) |
| 0029 | ML/MH antes del Fibonacci | ✅ verificado ya correcto |
| 0030 | Replay: seleccionar vela de inicio (Select Bar) | ✅ hecho |
| 0031 | El canal (tarea J) | pendiente (DESBLOQUEADA: Swing Channel sobre ZigZag ext) |
| 0032 | Rediseño barra de controles con pestañas | ✅ hecho |
| 0033 | Dirección precio interna/externa vía ZigZag (NUEVO enfoque profe) | ✅ hecho |
| 0034 | SMC CHoCH/BOS líneas mal dibujadas (a media vela) | ✅ hecho |
| 0035 | Modo Manual de escala fallando | ✅ hecho |

### Orden recomendado para el implementor (lote restante)
1. ~~**0030** — Replay Select Bar~~ ✅
2. **0031** — El canal (Swing Channel sobre el ZigZag externo; depende de 0033 ✅).
3. **0028** — Strong/Weak High/Low (port trailing extremes de LuxAlgo).
4. **0027** — BSL/SSL en banda (limpieza visual).
5. **0025** — Colorear velas de liquidity RUN (la más intrusiva, al final).

## Plantilla

```
# Task: [nombre]

## Spec relacionada

## Objetivo

## Archivos probablemente relevantes

## Pasos

## Criterios de aceptación

## Comandos de verificación

## Qué no tocar
```

## Comando de verificación base

Cada task debe ejecutar su comando específico de `perl -I. -c` y, además, la suite de regresión del repo:

```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && prove -l t"
```

Si estás trabajando directamente sobre la copia Windows desde WSL, usa:

```bash
wsl -d Fedora35 -- bash -lc "cd /mnt/c/m/ia/proyecto_iaaa/Proyecto/ProyectoIAAA && prove -l t"
```

Comando de sintaxis Perl para archivos puntuales:

```bash
wsl -d Fedora35 -- bash -lc "cd '<ruta del repo en Fedora35>' && perl -I. -c <archivo.pm>"
```

La ruta en Fedora35 es `~/Documents/ProyectoIA/ProyectoIAAA` (mantener sync con `git pull` o sincronización manual).
