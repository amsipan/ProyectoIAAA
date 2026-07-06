# Task 0058: Recolorear las velas de un liquidity RUN (no solo halo)

## Estado
✅ HECHO + VERIFICADO arquitecto (2026-07-05). Borrador delegado a grok composer-2.5-fast;
corrección arquitecto para respetar overlay/toggle/densidad en el mapa RUN. 1220 PASS.

Notas:
- `ChartEngine::compute_run_candle_map` deriva índices RUN visibles desde Liquidez y respeta Replay,
  toggle principal Liquidez, sub-toggle RUN y densidad 0062.
- `PricePanel` recolorea cuerpo/mecha de velas RUN con colores propios y preserva el halo overlay 0025.
- Downsample marca un bucket como RUN si contiene al menos una vela RUN.
- Verificación visual WSLg: `C:\Users\ASUS ROG\AppData\Local\Temp\opencode\0058_run_recolor.png`.

## Origen
- `docs/FEEDBACK_PROFESOR_QA_2026-07-05.md` punto 8, audio 1.
- Profe (lista): "Cambiar colores de velas importantes para saber cuándo ocurrió un liquidity run."
- QA (audio 1): "Lo de los colores de las velas, eso de ley que no estaba puesto."
- Refina `tasks/0025-highlight-liquidity-run-candles.md` (✅ hecho pero como HALO, no recoloreo).

## Estado en código (verificado)
`tasks/0025` se implementó como un HALO/overlay superpuesto: `Overlays/Liquidity.pm`
`_highlight_run_candle` (538-580) dibuja un rectángulo con stipple azul ENCIMA de la vela. La vela
en sí NO cambia de color (`Panels/PricePanel.pm:147-149,171-173` solo colorea bull/bear). El QA no
percibe eso como "color de vela".

## Objetivo
Que la vela donde ocurrió un RUN (relevante) se pinte con un COLOR DISTINTO (cuerpo/mecha), no solo
un halo, para que se distinga claramente del bull/bear normal.

## Enfoque (a implementar)
- Puente de datos: `ChartEngine` pasa a `PricePanel` un mapa `{index => run_dir}` derivado de
  `liq_indicator->get_events` (solo RUN, solo relevantes), respetando `replay_idx` (no futuro).
- En `PricePanel.pm`: al dibujar cada vela, si su índice está en el mapa de RUN, usar un color
  especial (p.ej. `run_bull`/`run_bear` o un color único de "liquidity run", a definir con
  arquitecto) en lugar del bull/bear normal. Respetar el downsample por píxel (`bar_w<2`): si un
  bucket agrupa una vela RUN, marcar el bucket.
- Mantener (o retirar) el halo de 0025 según se vea mejor — decidir con arquitecto tras captura.
- Toggle: reutilizar el toggle RUN existente; si RUN está OFF, no recolorear.

## Criterios de aceptación
- Las velas de un RUN relevante se ven con color propio, distinto del bull/bear normal.
- No se rompe el downsample por píxel ni el coloreado normal de las demás velas.
- Respeta Replay (no colorea futuro).
- `prove -l t` verde; test del puente de datos (ChartEngine→PricePanel entrega los índices RUN
  correctos y filtra futuro en replay).

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c Market/Panels/PricePanel.pm && perl -I. -c Market/ChartEngine.pm && prove -l t"
```
Requiere confirmación visual del arquitecto.

## Depende de
- 0054/0055 (menos RUN, más significativos) — idealmente después, para no pintar cientos de velas.

## Qué no tocar
- CSV, MarketData, Market/Debug/.
- No romper Fase 1 (velas normales, ATR, crosshair).
