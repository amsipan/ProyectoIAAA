# Task 0059: FVG vigente solo cerca del precio — unificar filtro en la capa SMC

## Estado
🔲 ABIERTA (2026-07-05). Feedback profe/QA 2ª ronda. Refina 0023.

## Origen
- `docs/FEEDBACK_PROFESOR_QA_2026-07-05.md` punto 9, audio 1.
- Profe (lista): "Solo dejar FVG vigentes cuando estén cerca al precio actual, si no dejarlos
  inactivos."
- QA (audio 1): "Lo del FVG/FBG creo que estaba puesto." (parcial)
- Refina `tasks/0023-fvg-active-near-price.md`.

## Estado en código (verificado)
Hay DOS detectores de FVG con comportamiento distinto:
- `Market/Indicators/Mxwll_Suite.pm` `_fvg_is_near` (532-545): SÍ filtra por cercanía
  (`fvg_near_atr=8`); `get_values` omite lejanos.
- `Market/Indicators/SMC_Structures.pm` `_detect_and_mitigate_fvgs` (431-503) / `get_fvg`
  (602-616): NO filtra por cercanía (solo mitigación por penetración de precio).

Según qué capa esté encendida, el usuario ve FVGs lejanos (los de SMC) que deberían estar inactivos.

## Objetivo
Comportamiento consistente: los FVG lejos del precio actual se marcan INACTIVOS (o no se dibujan)
en AMBAS capas, no solo en Mxwll.

## Enfoque (a implementar)
- En `SMC_Structures.pm`: añadir filtro de cercanía análogo a Mxwll — parámetro `fvg_near_atr`
  (default coherente con Mxwll, ~8). Un FVG está "vigente/activo" si la distancia del close actual
  al gap ≤ `fvg_near_atr * ATR`; si no, `_active=0` (o excluido de `get_fvg`).
- Reusar el ATR disponible en el módulo (o el que ya use SMC). Si no hay ATR aún, fallback: no
  filtrar (comportamiento actual).
- Overlay SMC: los inactivos, o no se dibujan, o se dibujan atenuados (decidir con arquitecto;
  el profe dijo "dejarlos inactivos", así que atenuar/ocultar).

## Criterios de aceptación
- Un FVG del SMC lejos del precio actual queda inactivo (no se dibuja o se atenúa); uno cercano
  sigue vigente.
- Mxwll conserva su comportamiento (ya correcto).
- `prove -l t` verde; test en `t/07`/`t` que verifique: gap lejano → inactivo, gap cercano → activo.

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c Market/Indicators/SMC_Structures.pm && prove -l t/05-smc.t && prove -l t"
```

## Qué no tocar
- CSV, MarketData, Market/Debug/.
- No cambiar la mitigación por penetración ya existente (es complementaria al filtro de cercanía).
