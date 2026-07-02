# Task 0024: Grab/Run — verificar solapamiento y semántica continuidad/rebote

## Estado: HECHO (2026-07-02, 797 tests PASS)
- SEMANTICA: verificada correcta, NO se tocó (RUN=continuidad, GRAB/SWEEP=rebote).
- SOLAPAMIENTO: SI era real. Medido en Data/2026_06_29.csv (solo eventos
  relevantes): 1m=190 velas con >1 marcador (16 con RUN+GRAB juntos), 5m=36,
  15m=21. Los marcadores se encimaban en la misma vela.
- FIX: en `_draw_event_marker` se apilan verticalmente los marcadores de la misma
  vela (offset 18px por nivel), contador `%stack` por index en el bucle de draw.
- Test nuevo en t/15 (ORDEN 12): dos eventos misma vela → etiquetas en Y distinta.

## Origen
- ORDEN 12 de `tasks/0021-volatility-and-choch-noise.md`.
- Notas WhatsApp profe (29/06): "Están sobrepuestos los grab y run"; "Run implica
  continuidad, los sweep/grab implican rebote"; "El run debería colocarse al
  romper el nivel y continuar".

## Objetivo
Confirmar que la semántica RUN=continuidad vs GRAB/SWEEP=rebote es correcta y que
las etiquetas no se solapan visualmente en el mismo punto.

## Estado verificado (02/07)
- `Market/Indicators/Liquidity.pm` FSM (`_update_fsm`): la semántica YA es
  correcta:
  * RUN = N cierres consecutivos FUERA del nivel (continuidad tras romper).
  * GRAB = rechazo rápido (<=3 velas) de vuelta al otro lado (rebote).
  * SWEEP = rechazo lento (>3 velas) de vuelta (rebote).
- El "sobrepuestos" reportado probablemente era:
  1. El aglomeramiento general (5000 eventos en 1m) → YA atacado en ORDEN 4
     (filtro de relevancia, 5000→1714).
  2. Marcadores sueltos sin ancla → YA atacado en ORDEN 3 (ancla al nivel).
- CONCLUSIÓN PROVISIONAL: probablemente ya resuelto por ORDEN 3+4. Falta
  confirmación visual.

## Diseño (solo si tras revisión visual siguen solapando)
- Si dos etiquetas caen en la misma X/Y (mismo punto de resolución), separar
  verticalmente (offset incremental) o priorizar la más relevante.
- NO cambiar la clasificación de la FSM (es correcta).

## Criterios de aceptación
- Verificación visual en 1m/5m: RUN aparece donde el precio rompe y continúa;
  GRAB/SWEEP donde rebota. Sin etiquetas encimadas ilegibles.
- Si no hay solapamiento real, cerrar la task como "ya resuelto por 0021 ORDEN 3+4"
  sin cambios de código.

## Verificación
```bash
# Analítica: revisar que no haya eventos RUN y GRAB en el mismo index/nivel.
wsl -d Fedora35 -- bash -lc "cd '<repo>' && perl -I. scratch/analyze_liq_density.pl"
```
Requiere además captura visual del usuario para confirmar.

## Qué no tocar
- No cambiar la FSM de clasificación RUN/GRAB/SWEEP (verificada correcta).
