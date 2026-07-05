# Task 0055: Anclar run/sweep/grab a los swings del SMC (no a swings propios)

## Estado
✅ HECHO + VERIFICADO arquitecto (2026-07-05). Borrador delegado a grok composer-2.5-fast;
fixtures y cable de alimentación SMC→Liquidity corregidos por arquitecto. 1186 PASS.

Notas:
- Liquidity tiene modo opt-in de pivotes externos (`use_external_pivots`, `set_external_pivots`,
  `sync_external_pivots`) y dedup por side/index/price.
- ChartEngine activa pivotes externos para Liquidity y alimenta SMC también cuando solo Liquidity
  está activo (sin eso, Liq quedaba sin pivotes si el overlay SMC estaba apagado).
- Tests nuevos en `t/10-liquidity.t`: pivotes externos manuales, anti-dup y cable SMC incremental.

## Origen
- `docs/FEEDBACK_PROFESOR_QA_2026-07-05.md` puntos 4, 6.
- Profe (lista): "Las etiquetas del SMC se usan como base del run y sweep."
- QA (audio 1): "Lo del RUN, algunos no le veía que tenía mucho sentido. Igual los grab.
  Están puestos así como medio arbitrariamente."

## Causa raíz (verificada)
`Market/Indicators/Liquidity.pm` calcula sus PROPIOS swings (fractal `k`) independientes de
`Market/Indicators/SMC_Structures.pm` (HH/HL/LH/LL con `k=3`, BOS/CHoCH). Los niveles que barre la
FSM de liquidez no coinciden con la estructura SMC visible → los run/grab parecen arbitrarios.
El profe quiere que la liquidez se ancle en la ESTRUCTURA SMC.

## Objetivo
Que los niveles de liquidez (los que disparan sweep/grab/run) se deriven de los swings/estructura
del SMC, de modo que run/grab caigan sobre niveles que el usuario reconoce en el gráfico.

## Enfoque (a decidir con arquitecto antes de codear)
Dos alternativas — el implementor debe proponer la de menor acoplamiento y el arquitecto aprueba:
- **A (preferida):** exponer desde `SMC_Structures` los swing highs/lows confirmados (ya existe
  `get_pivots`, `get_major`) y que `Liquidity` CONSUMA esos pivotes como origen de BSL/SSL en vez
  de recalcular su fractal. Requiere inyectar el indicador SMC (o su lista de pivotes) a Liquidity
  vía `ChartEngine::sync_overlay_indicators`, respetando `replay_idx` (no filtrar futuro).
- **B:** unificar el detector de swings en un módulo común y que ambos lo usen.

Restricción de arquitectura (CONSTITUTION): cálculo sin Tk; overlays no alimentan indicadores; se
respeta truncado de Replay.

## Criterios de aceptación
- Los niveles BSL/SSL que la FSM barre coinciden con swings SMC visibles (mismo precio/índice).
- run/grab/sweep se resuelven sobre esos niveles; su ubicación es coherente con la estructura.
- No hay fuga de futuro en Replay.
- `prove -l t` verde; test que verifique que, dado un SMC con pivotes conocidos, Liquidity produce
  niveles en esos mismos precios/índices (no en otros).

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c Market/Indicators/Liquidity.pm && perl -I. -c Market/ChartEngine.pm && prove -l t"
```

## Depende de
- 0054 (densidad) — idealmente después, porque al anclar en SMC (k=3) la densidad ya baja.

## Qué no tocar
- CSV, MarketData, Market/Debug/.
- No romper la semántica RUN/GRAB/SWEEP ni el contrato de `get_events`.
