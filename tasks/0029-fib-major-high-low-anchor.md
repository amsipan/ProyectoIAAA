# Task 0029: ML/MH primero para el cálculo de Fibonacci

## Origen
- ORDEN 17 de `tasks/0021-volatility-and-choch-noise.md`.
- Nota WhatsApp profe (29/06, Sebas): "Los ML y MH deben identificarse primero
  para calcular fibonacci sino da los márgenes equivocados".

## Objetivo
Asegurar que el Auto Fib del Mxwll se ancle al par correcto de swings mayores
(Major Low / Major High) para que los niveles fib salgan bien.

## Estado verificado (02/07)
- `Market/Indicators/Mxwll_Suite.pm`, `_compute_fibs`: YA usa `_ext` (upaxis/
  dnaxis y sus índices upaxis2/dnaxis2), que son los últimos swings EXTERNOS
  (extSens=25) — es decir, ya se basa en pivotes mayores, no en una pierna
  parcial cualquiera.
- La pierna se orienta por el pivote más reciente (upaxis2 vs dnaxis2).
- CONCLUSIÓN PROVISIONAL: es posible que ya esté correcto. La queja del profe
  puede venir de un caso concreto donde upaxis/dnaxis no eran el par "mayor"
  vigente (p.ej. un high externo antiguo con un low externo reciente).

## Diseño (solo si se confirma el bug con captura)
- Verificar que el par (y1@x1, y2@x2) usado para el fib sea efectivamente el
  Major High y Major Low del swing vigente, no un high viejo con un low nuevo.
- Posible mejora: recomputar el extremo real dentro de la pierna (como hace el
  .pine en `updateMain`, que busca el min/max real entre los dos anclajes) en
  vez de usar directamente upaxis/dnaxis.
- El .pine (`updateMain`) hace exactamente eso: tras fijar un ancla en el último
  pivote, escanea hacia atrás el min (o max) real para el otro ancla. Portar esa
  lógica si los márgenes salen mal.

## Criterios de aceptación
- Los niveles fib se anclan al Major High y Major Low correctos del swing vigente.
- Verificación analítica: comparar (x1,y1,x2,y2) del fib contra el min/max real
  del rango, y contra una captura de TradingView si el usuario la aporta.
- Determinista; test del anclaje en t/22.

## Pendiente de confirmar
- Captura del usuario mostrando "márgenes equivocados" para reproducir el caso.
  Si no se reproduce, cerrar como "ya correcto".

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '<repo>' && perl -I. -c Market/Indicators/Mxwll_Suite.pm && perl -I. scratch/analyze_mxwll.pl 2h"
```

## Qué no tocar
- No cambiar los ratios fib ni el toggle FIBS.
