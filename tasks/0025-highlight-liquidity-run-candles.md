# Task 0025: Colorear velas donde ocurrió un liquidity RUN

## Origen
- ORDEN 13 de `tasks/0021-volatility-and-choch-noise.md`.
- Nota WhatsApp profe (29/06): "Cambiar colores de velas importantes para saber
  cuándo ocurrió un liquidity run".

## Objetivo
Resaltar visualmente (color/borde distinto) las velas donde se resolvió un evento
RUN, para localizar de un vistazo los momentos de continuidad relevantes.

## Estado verificado (02/07)
- `Market/Panels/PricePanel.pm`: las velas se colorean SOLO por dirección
  (`close>=open` → bull, si no → bear). No hay resaltado por evento.
- Existe downsample por píxel cuando `bar_w < 2` (agrupa velas): cualquier
  resaltado debe respetar ese modo para no romperlo.
- Los eventos RUN viven en `Market::Indicators::Liquidity` (`get_events`), con
  `index` (vela de resolución) y ahora `relevant`/`magnitude` (ORDEN 4).

## Diseño
- Necesita un puente de datos: PricePanel debe conocer los índices de velas a
  resaltar. Opciones:
  1. ChartEngine pasa a PricePanel un set de índices "highlight" derivado de
     `liq_indicator->get_events` (solo RUN, quizá solo relevantes).
  2. Una capa/overlay ligera que dibuje un borde/halo sobre esas velas (menos
     intrusivo que tocar PricePanel, respeta el patrón de overlays).
- PREFERENCIA: opción 2 (overlay o marca en el price_canvas con su tag) para no
  alterar el render de velas ni el downsample. Confirmar con el usuario.
- Solo resaltar RUN (no GRAB/SWEEP), y probablemente solo los relevantes, para no
  saturar (en 1m hay ~2000 RUN; con relevancia ~34%).
- Considerar que en replay solo se resalten velas con index <= replay_idx.

## Criterios de aceptación
- Las velas de un RUN (relevante) se distinguen visualmente del resto.
- No se rompe el downsample por píxel ni Fase 1 (velas normales, ATR, crosshair).
- Respeta replay (no resalta futuro).
- Determinista; suite `prove -l t` verde con test del puente de datos.

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c Market/Panels/PricePanel.pm && perl -I. -c Market/ChartEngine.pm && prove -l t"
```
Requiere confirmación visual.

## Qué no tocar
- No romper el downsample por píxel de PricePanel.
- No alterar el coloreado normal bull/bear de las velas no resaltadas.
