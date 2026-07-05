# Task 0061: Canal de tendencia clásico (reemplazar el envelope ATR actual)

## Estado
✅ HECHO + VERIFICADO arquitecto (2026-07-05). Implementación inicial delegada a grok
(multiagente); corregí yo el núcleo geométrico tras 2 iteraciones fallidas de grok (ver Notas).
1170 PASS + verificación visual real (canal de tendencia clásico renderizado, ver abajo).

REABRIÓ `tasks/0031-channel.md` (enfoque envelope ATR incorrecto confirmado por Bryan).

## Notas de implementación (arquitecto)
- grok generó `trend_channels`/overlay/test pero: (a) se salió de scope editando un handoff (revertido);
  (b) su geometría definía "pierna = 1 segmento" → 0 canales; (c) su test asertaba un canal desde
  fixtures que solo producían 2 vértices (imposible geométricamente). Entró en thrashing (1 fallo → 2).
- CAUSA RAÍZ que grok no vio: `_ext_vertices` trae vértices DUPLICADOS (cada segmento empuja
  inicio+fin), así que la clasificación por paridad `$i%2` se desalinea. Solución: `_dedup_ext_vertices`
  antes de clasificar high/low, y `_trend_channel_between` que ancla la paralela al pivote opuesto más
  extremo ENTRE los 2 pivotes del mismo lado. Fixture de test reescrita (onda triangular multi-swing,
  `_triangle_wave_rows`) que sí produce ≥1 canal.
- Verificado visualmente forzando (throwaway) zigzag+canal ON + `swing_length` bajo: se dibujan las
  2 diagonales paralelas por pierna (gris) encerrando el precio, geometría del slide del profe. Todos
  los cambios throwaway (market.pl/ChartEngine defaults) revertidos; commit solo con ZigZag+test.

## Origen
- `docs/FEEDBACK_PROFESOR_QA_2026-07-05.md` sección 5b.
- Bryan (2026-07-05): "el botón canal crea unas dos líneas alrededor de otra principal que se ven
  raras y creo que eso nunca lo pidió el profesor." Referencia: slide "Static Liquidity" de Smart
  Risk (canal de tendencia con dos diagonales paralelas: "Trendline" + "Channel").
- La propia 0031 dejó nota: "Si resulta que el canal era otra cosa, se reabre." → se reabre.

## Estado en código (verificado — INCORRECTO)
El botón CHANNEL dibuja un ENVELOPE (sobre), no un canal:
- `Market/Indicators/ZigZag.pm` `_rebuild_external_segments` (392-416) + `_external_channel_list`
  (108-126): por cada segmento del zigzag externo genera dos líneas desplazadas a **±ATR fijo**
  (`channel_offset = channel_width * ATR`). Son dos rieles equidistantes a UNA diagonal.
- `Market/Overlays/ZigZag.pm` (143-166): las dibuja punteadas (`-dash '.'`) alrededor de la línea.

## Objetivo
Canal de tendencia CLÁSICO: dos líneas diagonales PARALELAS que encierran una pierna de tendencia,
una tocando los swing highs y la otra los swing lows (como el "Channel" del slide). El precio queda
DENTRO. NO un offset de ATR.

## Geometría objetivo (canal de 3 puntos)
Por cada pierna de tendencia significativa (del ZigZag externo):
1. **Trendline base**: recta que une 2 extremos del mismo lado de la pierna.
   - Tendencia bajista → 2 swing HIGHS descendentes (línea de resistencia superior).
   - Tendencia alcista → 2 swing LOWS ascendentes (línea de soporte inferior).
2. **Línea del canal (paralela)**: misma pendiente que la trendline, desplazada hasta tocar el
   extremo OPUESTO más lejano dentro de la pierna (el low/high que más sobresale).
3. Se dibuja UN canal por pierna de tendencia, no por cada micro-segmento del zigzag.
4. Líneas SÓLIDAS (no punteadas de offset). Color a definir (blanco/gris como el slide).

## Enfoque (a decidir con arquitecto)
- Construir sobre el ZigZag EXTERNO (marca las piernas grandes) — es el candidato natural.
- En `Indicators/ZigZag.pm`: nueva salida `trend_channels` (reemplaza o convive con
  `external_channel`), por pierna: pendiente, 2 puntos de la trendline, y el punto de anclaje de la
  paralela (extremo opuesto). Cálculo puro, sin ATR fijo.
  - ¿Cómo elegir los 2 extremos del mismo lado? Los 2 últimos vértices high (o low) consecutivos de
    la pierna. Definir mínimo de vértices para trazar canal (≥3 vértices: 2 de un lado + 1 opuesto).
- En `Overlays/ZigZag.pm`: el elemento `CHANNEL` dibuja las 2 paralelas sólidas.
- DEPRECAR el envelope ATR (`_external_channel_list`) o dejarlo solo si algún test lo cubre; el
  toggle "Canal" pasa a dibujar el canal de tendencia.
- UI: el checkbox "Canal" ya existe (panel ZigZag, `market.pl`).

## Criterios de aceptación
- Con "Canal" ON, se dibujan dos diagonales paralelas que encierran la pierna de tendencia,
  visualmente como el slide del profe (no rieles equidistantes a ±ATR).
- Con OFF, no se dibuja (sin regresión).
- Determinista; test en `t/24-zigzag.t` (o nuevo): dada una pierna con extremos conocidos, el
  indicador produce trendline + paralela con la MISMA pendiente y la paralela toca el extremo opuesto.

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c Market/Indicators/ZigZag.pm && perl -I. -c Market/Overlays/ZigZag.pm && prove -l t/24-zigzag.t && prove -l t"
```
OBLIGATORIA verificación visual del arquitecto (comparar contra el slide).

## Depende de
- Task 0033 (ZigZag externo) — hecha. El canal cuelga del zigzag externo.

## Qué no tocar
- No romper el cálculo del zigzag externo (interno/externo/segmentos/dirección).
- No tocar Volume Profile/POC.
