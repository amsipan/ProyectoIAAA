# Task 0060: Fibonacci — solo 3 niveles en temporalidades bajas

## Estado
🔲 ABIERTA (2026-07-05). Feedback profe/QA 2ª ronda.

## Origen
- `docs/FEEDBACK_PROFESOR_QA_2026-07-05.md` punto 12, audio 1.
- QA (audio 1): "El único problema era esto que dijo el profe, que en temporalidades más bajas se
  pueden solo poner tres niveles del Fibonacci."
- QA además: "el Fibonacci creo que está bien hecho" (el anclaje ML/MH está OK → 0029).

## Estado en código (verificado)
Fibonacci fijo en 5 niveles `0.236, 0.382, 0.5, 0.618, 0.786`:
- `Market/Indicators/SMC_Structures.pm` `get_fibonacci` (618-637) — niveles hardcoded (627).
- `Market/Indicators/Mxwll_Suite.pm` `_compute_fibs` (500-522) — `fib_ratios` param, default 5.
No hay lógica que varíe el número de niveles según la temporalidad.

## Objetivo
En temporalidades bajas (p.ej. 1m, 5m) mostrar solo 3 niveles de Fibonacci; en TF altas, el set
completo. Reduce ruido en intradía, como pidió el profe.

## Enfoque (a implementar)
- Definir el mapeo TF → set de niveles. Propuesta (confirmar con arquitecto):
  - TF bajas (1m, 5m, 15m): 3 niveles → `0.382, 0.5, 0.618` (los centrales/más usados).
  - TF altas (1h+, D, W): 5 niveles (actual).
  - Umbral exacto de "baja" a confirmar.
- El timeframe activo ya se conoce en `ChartEngine`/`market.pl`. Pasar el TF (o un flag "low_tf" /
  el set de ratios) al indicador de fib para que `get_fibonacci`/`_compute_fibs` emita solo esos
  niveles. Mantener el cálculo puro (el TF entra como parámetro, no como dependencia Tk).
- Aplicar de forma coherente en las dos fuentes de fib (SMC y Mxwll) y en el render.

## Criterios de aceptación
- En TF baja se dibujan exactamente 3 niveles; en TF alta, 5.
- El anclaje ML/MH (0029) no cambia; solo cambia CUÁNTOS niveles se muestran.
- `prove -l t` verde; test que verifique el set de niveles según TF (bajo=3, alto=5).

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c Market/Indicators/SMC_Structures.pm && perl -I. -c Market/Indicators/Mxwll_Suite.pm && prove -l t"
```
Requiere confirmación visual del arquitecto.

## Relación
- Coordinar con 0029 (anclaje) y 0056 (pivotes reducidos).

## Qué no tocar
- CSV, MarketData, Market/Debug/.
- No cambiar los ratios de los niveles que sí se muestran.
