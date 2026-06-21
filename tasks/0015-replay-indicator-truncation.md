# Task 0015: Recalcular indicadores hasta replay_idx (no hasta el fin del dataset)

## Spec relacionada
`specs/0002-sistema-replay.md` (PDF §3) + `specs/0004-smc-structures.md` / `specs/0005-liquidez.md`.
Corrige un defecto del cableado introducido en tasks 0008/0012.

## Contexto / defecto (revisión del arquitecto)
En `Market/ChartEngine.pm::render`, el cableado de overlays alimenta los indicadores SMC y
Liquidity con `update_last` **hasta el final del dataset** (`$last = size()-1`), confiando en que el
filtro `index <= end` del overlay evita la "fuga de futuro". Eso es **incorrecto**: los indicadores
son máquinas incrementales con estado, y sus atributos se calculan viendo TODAS las velas
alimentadas, aunque el item quede anclado a un índice visible.

Ejemplos de fuga real (PDF §3: "los indicadores se recalcularán únicamente hasta la última vela
visible en el puntero del Replay"):
- Un **FVG** anclado en `index=5` muestra `hi/lo/mitig` recortados por velas 6,7,8 ya alimentadas.
  En Replay parado en la vela 5 debería verse SIN mitigar. El filtro `index<=5` lo deja pasar con la
  mitigación del futuro.
- Un **swing/pivote** en `j=index-k` necesita `k` velas futuras para confirmarse. Con `replay_idx=5`
  y `k=3`, un swing en `index=3` no debería existir aún (se confirma en la vela 6), pero el cableado
  ya lo alimentó y el overlay lo dibuja.
- **Step-backward** no funciona: el cursor `_smc_fed_up_to`/`_liq_fed_up_to` solo avanza; al
  retroceder el puntero, el estado del indicador sigue adelantado.

El defecto NO afecta la vista normal (sin Replay, alimentar hasta el final es correcto). Solo se
manifiesta con Replay activo, que se cableará a la UI en task 0004 — por eso hay que corregirlo
ANTES de 0004.

## Objetivo
Que, con Replay activo, los indicadores reflejen exactamente el estado que tendrían si el dataset
terminara en `replay_idx`: recalculados hasta `replay_idx`, nunca más allá. Sin Replay, el
comportamiento actual (alimentar hasta el final) se mantiene.

## Archivos permitidos
- `Market/ChartEngine.pm`
- `t/12-replay.t` (o un test nuevo `t/16-replay-indicator-truncation.t`)

## Diseño requerido
1. Definir el tope efectivo de alimentación en `render`:
   - `feed_to = end` (el `end` que ya devuelve `compute_window`, que está truncado a `replay_idx`
     cuando Replay está activo). Cuando no hay Replay, `end` es la última vela visible, pero el
     indicador debe estar alimentado hasta el final del dataset para que la vista normal y el
     scroll/zoom no pierdan estructura. Por tanto:
     - Si Replay **activo**: `feed_to = replay_controller->current_index` (== `replay_idx`).
     - Si Replay **inactivo**: `feed_to = size()-1` (como hoy).
2. **Avance** (`feed_to > _fed_up_to`): alimentar `update_last` de `_fed_up_to+1 .. feed_to`.
3. **Retroceso** (`feed_to < _fed_up_to`): `reset()` el indicador y realimentar `0 .. feed_to`.
   (Los indicadores ya tienen `reset()`; es O(n) pero correcto y simple — `ponytail`: recálculo
   completo en retroceso, optimizable con snapshots si el Replay resulta lento.)
4. Aplicar el mismo patrón a SMC y Liquidity.
5. `compute_all($market_data, $start, $end)` y el filtro del overlay se mantienen como segunda
   barrera (defensa en profundidad), pero la corrección real es alimentar hasta `feed_to`.

## Tests requeridos
Crear `t/16-replay-indicator-truncation.t` (o ampliar `t/12`). Usar `TestMarketData`/`TestCanvas`
del estilo de `t/07`/`t/13`, con un `ReplayController` real:
1. **No-fuga de FVG/mitigación:** dataset donde un FVG en `index=I` se mitiga por velas posteriores.
   Con `replay_idx=I` (parado justo en la formación), el indicador del chart debe reportar ese FVG
   SIN mitigar (`mitig==0`, `hi/lo` originales). Comparar contra un indicador independiente
   alimentado solo `0..I`. Deben coincidir exactamente.
2. **No-fuga de pivote:** con `replay_idx=R`, los pivotes/eventos del indicador del chart == los de
   un indicador alimentado solo `0..R`.
3. **Step-backward:** avanzar `replay_idx` a R2 y luego retroceder a R1<R2; el estado del indicador
   debe ser idéntico a alimentar `0..R1` desde cero.
4. **Sin Replay:** el indicador se alimenta hasta `size()-1` (comportamiento normal intacto).
5. `prove -l t` completo en verde; conservar t/14 y t/15.

## Qué no tocar
- `Market/Debug/` (solo arquitecto).
- `Market/MarketData.pm`, `Data/2026_03.csv`.
- La lógica de cálculo de los indicadores y el render de los overlays (0008/0012) — solo se corrige
  el CABLEADO de alimentación en `ChartEngine::render`.

## Verificación obligatoria
```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. -c Market/ChartEngine.pm && perl -I. -c market.pl && prove -l t"
```
(Copia Windows desde WSL: `cd /mnt/c/m/ia/proyecto_iaaa/Proyecto/ProyectoIAAA`.)

## Prompt mínimo para implementor
Implementa `tasks/0015-replay-indicator-truncation.md`. Bug detectado por el arquitecto: en
`ChartEngine::render`, los indicadores SMC/Liquidity se alimentan hasta el fin del dataset aunque
Replay esté activo, filtrando solo el dibujo — eso filtra futuro (FVG mitigado por velas futuras,
pivotes confirmados con velas futuras). Corrige el cableado para alimentar hasta `replay_idx` cuando
Replay está activo (y hasta `size()-1` si no lo está), con `reset()`+realimentación en retroceso.
Añade `t/16` que pare el Replay en la formación de un FVG y verifique `mitig==0` comparando contra un
indicador alimentado solo hasta ese índice (debe fallar con el cableado viejo). No toques
Market/Debug/, MarketData.pm, el CSV, ni la lógica de cálculo/render. Ejecuta `prove -l t` completo.
