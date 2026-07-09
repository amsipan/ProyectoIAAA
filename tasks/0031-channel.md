# Task 0031: El canal (tarea J)

## Estado
⚠️ **REABIERTA como `tasks/0061-trend-channel-classic.md`** (2026-07-05). El enfoque de esta task
(envelope ±ATR alrededor del zigzag) NO era lo que pedía el profe. Bryan confirmó con la imagen
"Static Liquidity" que quiere un canal de tendencia clásico (2 diagonales paralelas por pierna).
Ver 0061. Lo de abajo queda como registro histórico del envelope implementado.

## Estado anterior
✅ **Hecho** (2026-07-04) — envelope ATR (superado).

## Origen
- ORDEN 19 de `tasks/0021-volatility-and-choch-noise.md` (= tarea J original).
- Nota WhatsApp profe (29/06): "Falta el canal".

## Objetivo
Añadir "el canal" que el profe echa en falta. El término exacto está a confirmar,
pero hay varios candidatos ya calculados en el código sin render.

## Estado verificado (02/07)
- `Market/Indicators/Strategy_Builder.pm`: calcula HalfTrend y Range Filter
  (bandas high_band/low_band = un canal) pero el overlay solo dibuja SuperTrend y
  Order Blocks; HalfTrend y Range Filter NO se renderizan.
- `Market/Indicators/Liquidity.pm`: `zone_3` = trendlines/channels (último swing
  high y low como límites de canal), calculado pero sin render dedicado.
- No hay un "canal de tendencia" (líneas paralelas envolviendo el precio) dibujado.

## ENFOQUE DECIDIDO (04/07) — DESBLOQUEADA
"El canal" = el **Swing Channel** del indicador ZigZag Volume Profile (ChartPrime)
que el profe mandó implementar (ver `docs/reference_indicators/zigzag_volumeprofile_chartprime.txt`,
`drawBinLevel` usa `channelLineArray` con offset ATR).
Es decir: dos líneas PARALELAS al segmento del ZigZag EXTERNO, desplazadas ±ancho
(basado en ATR), que envuelven el movimiento. Aunque en las capturas del profe el
Swing Channel está deshabilitado, "el canal" es exactamente esa estructura y ahora
tenemos el ZigZag externo (task 0033) sobre el cual construirlo.

Se construye SOBRE el ZigZag externo ya implementado en `Market/Indicators/ZigZag.pm`
/ `Market/Overlays/ZigZag.pm` (task 0033), NO sobre Strategy_Builder.

Diseño concreto:
- En `Market/Indicators/ZigZag.pm`: para cada segmento externo, exponer también
  el ancho del canal = `channel_width * atr` (ya hay `channel_width` y ATR(200) en
  el módulo). Añadir a `get_values` una lista `external_channel` con, por segmento:
  from/to index y precios de las DOS líneas paralelas (segmento ± ancho/2, o el
  segmento como línea central y dos offsets). Seguir el criterio del .pine:
  `yStart = startPrice + offset`, `yEnd = endPrice + offset` para offset = ±ancho.
- En `Market/Overlays/ZigZag.pm`: nuevo elemento toggle `CHANNEL` (default OFF para
  no saturar). Dibuja las dos líneas paralelas del canal (color tenue, p.ej.
  gris/azul claro) siguiendo cada segmento externo.
- UI: checkbox "Canal" en la pestaña ZigZag (junto a Interno/Externo).

## Criterios de aceptación
- Con el toggle Canal ON, se dibujan dos líneas paralelas al zigzag externo,
  separadas por un ancho proporcional al ATR.
- Con el toggle OFF (default), no se dibuja (sin regresión visual).
- Determinista; test en t/24 (o t nuevo) que verifique que cada segmento externo
  produce dos líneas de canal a distancia = channel_width*ATR del segmento.

## Nota
Si al mostrárselo el profe resulta que "el canal" era otra cosa (canal de
tendencia por regresión, o premium/discount zones), se reabre. Pero el candidato
más probable —y el que viene del propio indicador que mandó— es este Swing Channel.

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c Market/Indicators/ZigZag.pm && perl -I. -c Market/Overlays/ZigZag.pm && prove -l t/24-zigzag.t && prove -l t"
```

## Depende de
- Task 0033 (ZigZag) — YA HECHA. El canal se construye sobre el zigzag externo.

## Qué no tocar
- No tocar el cálculo del zigzag externo (solo añadir la salida del canal).
- No tocar el Volume Profile/POC (el profe los deshabilita).
