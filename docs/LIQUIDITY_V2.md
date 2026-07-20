# Liquidity v2 — especificación de producto

**Estado:** MVP implementado (BSL/SSL/EQH/EQL + FSM + export).  
**Módulos:** `Market/Indicators/Liquidity.pm`, `Market/Overlays/Liquidity.pm`.  
**Prohibido:** copiar código de `ProyectoIAAA_LEGACY_ARCHIVE`.

> Parte del **plan definitivo** del proyecto: **`docs/PLAN_DEFINITIVO.md`**.  
> Liquidity existe para etiquetar sweep/grab/run y alimentar la tablota de modelos.

**Última corrección (2026-07-19):**

- Labels ASCII `SWEEP UP`/`SWEEP DN`; BSL/SSL con etiqueta **dentro del plot** (clamp).
- **Historial** (checkbox): dibuja niveles `resolved` tenues (`BSL*`).
- **Pivotes ZZ acumulados** en Liquidity (no se pierden al trim visual de 15 segs).
- Replay: span de vivos hasta `causal_end`; resueltos pivot→resolve; sin futuro.
- Replay usa slots vacíos a la derecha (no `x_shift -20%`), por lo que niveles/eventos conservan la misma X que su vela en cualquier zoom.
- Al rebobinar, `reset_full` elimina el historial de pivotes y lo reconstruye desde el ZigZag/SMC recalculado hasta `replay_idx`; así no sobrevive un pivote antiguo cuya confirmación requirió barras futuras.
- El mapa que recolorea velas `RUN` se calcula después de esa sincronización causal y antes de pintar PricePanel; el primer frame tras el rewind no reutiliza eventos futuros.
- La escala manual de precio/ATR se captura desde slices causales actuales y no desde caches heredados de la vista live.
- El overscan derecho de paneo solo llega a `end + 1` si esa vela sigue siendo causal y nunca supera `replay_idx`.
- Labels fuera del viewport ya no se empujan al borde; en zoom lejano los puntos exactos se conservan y los textos cercanos se reducen por densidad.
- Camino principal: ZZ (+SMC); k-swing solo si no hay pivotes externos.

## Fuentes de verdad

1. PDF 2ª fase §4 (BSL/SSL, EQH/EQL, FSM, estilos tabla 2).  
2. Clase IA 16-jun (Lumina `1d3e610b36ae`) — 7 zonas, int/ext, HMM.  
3. Audio IndicacionesExaProy (VPS transcript) — pipeline modelos, ventanas sweep/grab/run, umbral 85%.

## Fin último (no es este módulo solo)

```
Eventos de liquidez (este módulo)
  → tablota ~50 features (solo filas cerca de niveles)
  → t-SNE (atemporal) → GMM P(sweep|grab|run)≥85%
  → HMM interno + HMM externo (etiquetas en el tiempo)
```

Los indicadores generan **observaciones**. Los modelos se entrenan **después**.

## FSM

```
Detected → Swept → Resolved(sweep|grab|run)
```

| Resolución | Criterio (defaults) |
|------------|---------------------|
| **sweep** | Tras penetrar el nivel, cierre de regreso en ≤ `sweep_max_bars` (2), o mismo-vela PDF |
| **grab** | Regreso en 3 … `grab_max_bars` (8) |
| **run** | `run_accept_n` (3) cierres consecutivos del lado roto |

## Niveles MVP

| Kind | Origen |
|------|--------|
| BSL | Swing high (k-vecinos, default k=3) |
| SSL | Swing low |
| EQH | Dos swing highs con \|Δ\| ≤ ATR × 0.10 |
| EQL | Dos swing lows, misma tolerancia |

## API

```perl
$ind->update_last($md, $i);          # feed incremental (ChartEngine)
$ind->get_values();                  # levels + events
$ind->export_liquidity_events();     # filas para GMM (metadato time aparte)
$ind->get_observation_stream();      # etiquetas por vela → HMM
$ind->set_external_pivots([...]);    # opcional (v1.5: ZZ/SMC)
```

## Overlay / UI

- Capa `liq` (checkbox Liquidity).  
- Subelementos: BSL, SSL, EQH, EQL, SWEEP, GRAB, RUN.  
- Colores PDF: BSL rojo punteado, SSL verde, Grab naranja, Run azul.

## Las 7 zonas (roadmap v1.5)

1. EQH/EQL — MVP  
2. Arriba SH / abajo SL (BSL/SSL) — MVP  
3. Trendlines / Parallel Channel  
4. Order blocks + doji/envolvente  
5. Soporte / resistencia HTF  
6. Fibonacci (último impulso ZZ externo)  
7. OHLC diario/semanal previo (HLD)

## Tests

`t/32-liquidity-v2.t` — sweep, grab, run, SSL, export, reset.
