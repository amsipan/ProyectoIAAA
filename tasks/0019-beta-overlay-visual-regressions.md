# Task 0019: Regresiones visuales de overlays SMC/Liquidez y Replay

## Spec relacionada
- `specs/0004-smc-structures.md`
- `specs/0005-liquidez.md`
- `specs/0010-ui-timeframe-replay-toggles.md`

## Objetivo
Corregir regresiones visuales reportadas por beta testers sin perder componentes de Fase 1: velas, ATR, zoom, drag, crosshair, eje temporal, escala manual/auto y Replay base.

## Reporte de beta testers

### SMC
1. Las etiquetas HH/LL/HL/LH aparecen pegadas a la pantalla y no se mueven con la gráfica; algunas desaparecen.
2. Las etiquetas BOS/CHoCH se quedan en un rincón como clonadas y no se muestran con zoom bajo.
3. Las líneas relacionadas con estructura se muestran solo en rangos de zoom concretos y se alargan indefinidamente en lugar de detenerse como en los videos.
4. Las franjas verdes FVG se quedan pegadas a la pantalla y solo se ven con zoom alto.

### Liquidez
5. Activar el botón Liquidez aparentemente no muestra nada.
6. No está claro qué son BSL y SSL ni si salen bien en pantalla.
7. EQH aparece volando en la gráfica.
8. EQL aparentemente no hace nada.
9. GRAB aparece volando igual que EQH.
10. RUN tiene el mismo problema.

### Replay
11. En Replay, BOS/CHoCH funcionan al inicio pero se alejan cuando la gráfica termina; las velas se mueven pero etiquetas/overlays no desaparecen o no se mueven con la gráfica.
12. A veces Replay termina donde debe, pero las etiquetas aparecen clonadas.
13. Parece que el último frame de Replay queda congelado de alguna forma.

## Diagnóstico confirmado
Los overlays reciben items con `index` global, pero `Market::Panels::Scales` espera índices locales de la ventana visible `[0..bars-1]`. En `ChartEngine::render`, las velas se dibujan con índices locales, pero `Market/Overlays/SMC_Structures.pm` y `Market/Overlays/Liquidity.pm` usaban directamente el índice global en `index_to_x` / `index_to_center_x`.

Impacto esperado del bug:
- Si la ventana visible empieza en `start > 0`, un item con `index=1000` se dibuja en X de barra 1000 dentro de una escala que quizá solo tiene 60 barras visibles.
- En zoom bajo o Replay, los overlays quedan fuera del viewport, pegados al borde, aparentan congelarse o parecen clonados.

## Criterios de aceptación
- Todo overlay convierte índice global a índice local con `local = index - start` antes de llamar a `Scales`.
- HH/HL/LL/LH, BOS/CHoCH, FVG, EQH/EQL, GRAB/RUN se mueven junto con las velas al panear, hacer zoom y usar Replay.
- No se cambia la lógica de cálculo de SMC/Liquidez.
- No se rompe Fase 1: velas, ATR, crosshair, zoom/drag y ejes siguen intactos.

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c Market/Overlays/SMC_Structures.pm && perl -I. -c Market/Overlays/Liquidity.pm && prove -l t/14-overlay-smc-render.t t/15-overlay-liquidity-render.t t/18-ui-ondemand-and-toggles.t"
```

## Qué no tocar
- No tocar `MarketData.pm` ni `Data/2026_03.csv`.
- No cambiar cálculo SMC/Liquidez salvo nueva task explícita.
- No refactorizar `ChartEngine.pm` masivamente en esta task.
