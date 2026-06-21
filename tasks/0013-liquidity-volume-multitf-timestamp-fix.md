# Task 0013: Corregir pesado de volumen multi-TF por rango temporal (no por índice)

## Spec relacionada
`specs/0005-liquidez.md` (§ Pesado de volumen multi-temporal) + PDF Fase 2 §4.4.
Corrige un defecto introducido en task 0011.

## Contexto / defecto detectado (revisión del arquitecto)
`Market/Indicators/Liquidity.pm::_sum_volume_for_tf($tf, $from_idx, $to_idx)` recorre
`md->{data}->{$tf}[$from_idx .. $to_idx]` usando **los mismos índices** del array activo (1m).
Eso es incorrecto: el índice `i` del array `5m`/`15m` es un bucket de reloj distinto, no la
sub-vela 1m número `i`. El propio código lo admite con un comentario
`# ponytail: best effort on synthetic test data`.

El PDF §4.4 exige extraer "los volúmenes agregados de las sub-velas de menor rango" para el
**rango temporal** del evento, independientemente del TF macro visible. La unidad correcta es el
TIMESTAMP, no el índice.

El test actual `t/10-liquidity.t` (caso 18) solo verifica `v1m` exacto (=280) y que `v5m`/`v15m`
"existan" (`ok(defined ...)`), por lo que NO detecta el bug. Hay que endurecerlo.

## Objetivo
Que `_compute_event_meta` calcule `v1m`, `v5m`, `v15m` sumando los volúmenes de las velas de cada
TF cuyo **timestamp** cae dentro del rango temporal del evento `[ts(level.index) .. ts(resolve_index)]`
del array activo, sin depender de alineación de índices entre arrays.

## Archivos permitidos
- `Market/Indicators/Liquidity.pm`
- `t/10-liquidity.t`

## Pasos
1. En `_compute_event_meta`, obtener el rango temporal del evento:
   - `ts_start` = timestamp de la vela `level.index` en el array ACTIVO (`md->get_timestamp` o
     `md->{data}{active_tf}[level.index][0]`).
   - `ts_end`   = timestamp de la vela `resolve_index` en el array activo.
2. Reescribir `_sum_volume_for_tf($tf, $ts_start, $ts_end)` para que:
   - recorra `md->{data}->{$tf}` (que ya existe tras `build_timeframes`);
   - sume `vol` (`$c->[5]`) de cada vela cuyo `timestamp` (`$c->[0]`) cumpla
     `ts_start <= ts < ts_end_next` — usa comparación temporal con `Time::Moment->from_string(...)->epoch`,
     NO comparación de strings ni de índices.
   - Define con cuidado el borde superior: incluir todas las sub-velas cuyo bucket comienza dentro
     del rango del evento. Documenta la convención elegida en un comentario.
3. Si un TF no fue construido (array vacío), devolver 0 sin morir.
4. Mantener `internal` como está (1 si `active_tf` ∈ {1m,5m,15m}).

## Nota de diseño (leer)
Como `5m`/`15m` son agregaciones del mismo `1m`, la suma total sobre un mismo rango temporal
**coincide** entre TFs (v1m == v5m == v15m si el rango cubre buckets completos). Eso es correcto y
esperado: el valor es el volumen transaccionado en ese rango, "observado" a cada granularidad. Lo
que se corrige es que hoy los índices desalineados hacen que `v5m`/`v15m` sumen velas FUERA del
rango temporal del evento. El test debe fijar un fixture donde el rango NO empieza en el índice 0,
de modo que un cálculo por índice y uno por timestamp den resultados DISTINTOS, y exigir el de
timestamp.

## Tests requeridos (endurecer caso 18 y añadir uno nuevo)
1. **v1m exacto** como hoy (suma de volúmenes 1m del rango temporal del evento).
2. **v5m / v15m exactos por timestamp**: construir un fixture de ≥ 30 velas 1m con volúmenes
   conocidos, un evento cuyo rango temporal sea, por ejemplo, `[10m .. 25m]`, y afirmar que
   `v5m`/`v15m` = suma de los buckets 5m/15m cuyos timestamps caen en ese rango (calculada a mano).
   Elegir el rango de forma que sumar por índice (`arr[10..25]`) daría un número DISTINTO al correcto
   por timestamp — así el test falla con el código viejo y pasa con el nuevo.
3. **TF macro no afecta el volumen**: con `set_timeframe('1h')` el `v1m/v5m/v15m` del evento debe ser
   el mismo que con `set_timeframe('1m')` (el volumen multi-TF es independiente del TF visible).
   `internal` sí cambia (0 en 1h).
4. Conservar replay guard y equivalencia incremental==batch.

## Qué no tocar
- `Market/Debug/` (solo arquitecto).
- `Market/MarketData.pm`, `Data/2026_03.csv`.
- La FSM, EQH/EQL, BSL/SSL, las 7 zonas (ya validadas) — salvo lo imprescindible para el rango temporal.

## Verificación obligatoria
```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. -c Market/Indicators/Liquidity.pm && prove -l t"
```
(En copia Windows desde WSL: `cd /mnt/c/m/ia/proyecto_iaaa/Proyecto/ProyectoIAAA`.)

## Prompt mínimo para implementor
Implementa `tasks/0013-liquidity-volume-multitf-timestamp-fix.md`. El bug: el volumen multi-TF
suma por índice en vez de por rango temporal (timestamp). Corrige `_sum_volume_for_tf` y
`_compute_event_meta` en `Market/Indicators/Liquidity.pm` para sumar por timestamp, y endurece
`t/10-liquidity.t` con un fixture donde índice y timestamp den resultados distintos (el test debe
fallar con el código viejo). No toques Market/Debug/, MarketData.pm ni el CSV. Ejecuta la
regresión completa.
