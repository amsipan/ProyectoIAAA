# Task 0031: El canal (tarea J)

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

## Interpretación (a confirmar con el profe)
"El canal" puede ser:
1. **Canal de tendencia**: dos líneas paralelas (soporte/resistencia dinámicos)
   que envuelven el movimiento entre swings.
2. **HalfTrend / Range Filter** ya calculados en Strategy_Builder → solo falta
   renderizar sus bandas (la opción de MENOR esfuerzo, ya está el cálculo).
3. **Premium/Discount zones** del SMC (zona premium/equilibrio/discount de LuxAlgo).

## Diseño
- Confirmar cuál de las 3 quiere el profe.
- Si es (2): añadir al overlay Strategy_Builder el render de HalfTrend y Range
  Filter (bandas), con toggle. Mínimo esfuerzo, cálculo ya hecho.
- Si es (1): implementar detección de canal (regresión/paralelas sobre swings) +
  overlay.
- Si es (3): portar premium/discount zones del .pine de LuxAlgo.

## Criterios de aceptación
- Se dibuja "el canal" acordado, con toggle.
- Determinista; test del cálculo/render.

## Pendiente de confirmar (BLOQUEANTE)
- Qué es "el canal" para el profe (opciones 1/2/3 arriba). No implementar hasta
  confirmar para no construir lo que no era.

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c Market/Overlays/Strategy_Builder.pm && prove -l t/19-strategy-builder.t"
```

## Qué no tocar
- No implementar a ciegas: confirmar el tipo de canal primero.
