# Task 0038: [ALTO] Fuga de futuro en Liquidity Zone 6/7 (daily/weekly) rompe Replay

## Estado
✅ **Hecho** (2026-07-04)

## Origen
- Auditoría de arquitecto (04/07). No es visible a simple vista pero corrompe el
  Replay, que el profe evalúa explícitamente.

## Problema
`Market/Indicators/Liquidity.pm`, `_detect_zones($index)` (se llama en cada
`update_last`):
- Zone 6 (Daily), líneas ~919-922: `my $d_arr = $md->{data}->{'D'}; my $d = $d_arr->[-1];`
- Zone 7 (Weekly), líneas ~940-943: `my $w_arr = $md->{data}->{'W'}; my $w = $w_arr->[-1];`

`$md->{data}{D}` y `{W}` son los arrays del dataset COMPLETO (Replay es un cursor,
no un truncado). `->[-1]` toma el último día/semana de TODO el CSV = FUTURO
absoluto respecto a `replay_idx`. Además, aunque se tomara el bucket del día
"actual", ese bucket diario ya está agregado con velas 1m posteriores a
`replay_idx` (H/L/C intradía del futuro).

**La guarda de replay basada en índice NO lo detecta** (`IndicatorSnapshot`
línea ~103 compara `index > replay_idx`, pero estas zonas usan `index => $index`
actual con PRECIO del futuro). Es una fuga silenciosa.

## Fix requerido
- El daily/weekly usado en Zone 6/7 debe corresponder al bucket vigente en
  `replay_idx` y calcularse SOLO con velas <= replay_idx (no `->[-1]` del array
  completo, ni un bucket cerrado con datos futuros).
- Opción simple y correcta: rastrear incrementalmente el H/L/O/C del día/semana en
  curso a medida que llegan velas 1m en `update_last` (como se hace con otros
  acumuladores), en vez de leer `$md->{data}{D/W}`.
- Si eso es costoso, alternativa: usar el bucket daily/weekly cuyo timestamp de
  cierre sea <= timestamp del `$index` actual, y para el bucket en curso usar solo
  el H/L acumulado hasta `$index`.

## Criterios de aceptación
- Ningún valor de Zone 6/7 depende de velas con índice/tiempo > índice actual.
- Verificación analítica: alimentar el indicador hasta un índice N y comprobar que
  las zonas daily/weekly son idénticas a alimentar un dataset truncado en N
  (sin las velas futuras). Script en scratch/.
- Suite `prove -l t` verde; reforzar t/10 con un caso que detecte la fuga
  (comparar zonas con dataset truncado vs completo-hasta-N).

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c Market/Indicators/Liquidity.pm && prove -l t/10-liquidity.t t"
```

## Qué no tocar
- No cambiar el cálculo de las zonas 1-5 (esas no tienen fuga).
- No tocar MarketData ni los CSV.
