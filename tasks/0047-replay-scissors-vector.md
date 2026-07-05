# Task 0047: [PULIDO baja prioridad] Tijeras vectoriales en modo selección Replay

## Origen
- Validación visual del arquitecto de la task 0042 (05/07). Todo lo demás de 0042 quedó correcto
  (línea azul, etiqueta `Re:`, velo blanco). Único defecto cosmético.

## Problema
En `Market/Overlays`/`Market/ChartEngine.pm`, `_draw_replay_select_hover` dibuja el cursor de
selección con el glyph unicode `\x{2702}` (✂) vía `createText` + fuente `Helvetica 14`. En
Fedora35 esa fuente **no tiene el glyph**, así que renderiza como una `x` diminuta azul en el
centro de la línea, en lugar de unas tijeras como en TradingView (captura 1 de la referencia).
El propio implementor lo anticipó con un comentario `ponytail:`.

## Fix requerido
Reemplazar el glyph por unas **tijeras vectoriales** dibujadas con primitivas de canvas
(`createLine` / `createOval` / `createPolygon`), tag `replay_select_scissors`, centradas en la
línea azul a la altura del cursor. No depender de que la fuente tenga el carácter.
- Alternativa aceptable si sale más simple y se ve bien: cursor nativo Tk que insinúe corte
  (`'pirate'`, `'X_cursor'`, `'tcross'`) + quitar el createText del glyph. Elegir lo que más se
  parezca a las tijeras de TV con el mínimo código.
- Mantener el color azul `#2962ff` y la limpieza por tag ya existente (Leave / select-off / click).

## Criterios de aceptación
- En modo selección se ve un símbolo de tijeras reconocible (no una `x`) sobre la línea azul.
- Sigue el cursor y se limpia igual que ahora al salir del modo / hacer click / Leave.
- `prove -l t` verde; actualizar el bloque de 0042 en `t/25-replay-select-bar.t` si cambia el
  tipo de op (de `createText` a `createLine`/etc.) para que el test verifique el nuevo dibujo por
  tag `replay_select_scissors`.

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c Market/ChartEngine.pm && prove -l t/25-replay-select-bar.t t"
```
Validación visual del arquitecto en WSLg (comparar con captura 1 de la referencia TV).

## Qué no tocar
- No cambiar la línea azul, la etiqueta `Re:` ni el velo (ya aprobados en 0042).
- No romper la limpieza de tags hover.
