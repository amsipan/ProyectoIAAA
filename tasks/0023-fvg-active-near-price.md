# Task 0023: FVG vigente solo cerca del precio actual

## Estado: HECHO (2026-07-02, 799 tests PASS)
- Parametro `fvg_near_atr` (default 8; 0 desactiva). Helper `_fvg_is_near`:
  distancia del close actual al gap (0 si el precio esta dentro); vigente si
  dist <= fvg_near_atr*ATR.
- `get_values` expone solo FVG `active` (no rellenado) Y `near` (cerca del precio).
  No borra del historial → replay intacto; el podado O(n) del array se conserva.
- Impacto: 1m FVG vigentes 47->8, 5m 24->10.
- Test nuevo en t/22 (bloque 13): FVG lejano deja de ser vigente con default,
  sigue vigente con fvg_near_atr=0.

## Origen
- ORDEN 11 de `tasks/0021-volatility-and-choch-noise.md`.
- Nota WhatsApp profe (29/06): "Solo dejar FVG vigentes cuando estén cerca al
  precio actual, sino dejarlos inactivos".

## Objetivo
Un FVG deja de mostrarse (o se atenúa) cuando queda lejos del precio actual,
aunque no haya sido rellenado. Reduce ruido de FVGs antiguos e irrelevantes.

## Estado verificado (02/07)
- `Market/Indicators/Mxwll_Suite.pm`: `_detect_fvg` crea el gap; `_mitigate_fvg`
  solo lo invalida cuando el precio RELLENA el hueco (low<=bottom / high>=top).
- NO existe criterio de proximidad al precio actual. Un FVG lejano no mitigado
  sigue "vigente" indefinidamente.
- Referencia en el .pine de Mxwll: `closeOnly` (mostrar solo el FVG más cercano
  arriba y abajo del precio) y `contract` (encoger el FVG violado).

## Diseño
- Añadir parámetro `fvg_max_dist_atr` (p.ej. 10): un FVG se considera inactivo
  si la distancia del precio actual (close) a su rango es > fvg_max_dist_atr*ATR.
- Opción alternativa/complementaria (más fiel al .pine): `fvg_close_only` — dejar
  vigente solo el FVG alcista más cercano por debajo y el bajista más cercano por
  encima del precio. Decidir con el usuario cuál (o ambos, configurables).
- La marca de inactividad NO debe borrar el FVG del historial (para replay), solo
  excluirlo del dibujo (o atenuarlo). Preferible marcar `active`/`near` y que el
  overlay filtre, igual que `only_relevant` en Liquidity (ORDEN 4).
- Cuidado con el rendimiento: la evaluación de proximidad es O(activos) por vela;
  seguir el patrón de podado ya usado para no reintroducir O(n²).

## Criterios de aceptación
- FVG lejanos al precio quedan inactivos/atenuados; los cercanos siguen vigentes.
- El parámetro es configurable y con default razonable; 0/off = comportamiento
  actual (solo mitigación por relleno).
- Determinista; suite `prove -l t` verde con test nuevo en t/22.

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '<repo>' && perl -I. -c Market/Indicators/Mxwll_Suite.pm && prove -l t/22-mxwll-suite.t"
```

## Qué no tocar
- No borrar FVGs del historial (romper replay). Solo marcar/filtrar dibujo.
- No reintroducir escaneos O(n²) (respetar el podado incremental existente).
