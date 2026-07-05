# Task 0042: Replay — modo selección visual estilo TradingView

## Referencia
- `docs/TRADINGVIEW_BAR_REPLAY_REFERENCE.md` §2 (indicador visual), §19 capturas 1 y 2.

## Objetivo
Que al entrar en modo Select Bar el chart se vea EXACTAMENTE como la captura 1:
cursor tijeras (✂) sobre una línea vertical azul que sigue al ratón, etiqueta `Re: <fecha>` en el
eje temporal bajo la línea, y **velo blanco semitransparente sobre las velas a la derecha** de la
línea. Al hacer click (captura 2), se fija el inicio, se quita el velo y el chart se recorta.

## Estado actual
- Existe `_draw_replay_select_marker` (línea naranja punteada `#e67e22`, fija en `_selected_bar`).
- Cursor en modo select = `'crosshair'` genérico; no hay tijeras.
- No hay línea que siga al cursor en tiempo real ni etiqueta `Re:` ni velo.
- `set_replay_select_mode`, `adjust_selected_bar`, binds Shift+←/→ ya existen.

## Diseño
En `Market/ChartEngine.pm`:
1. **Línea azul dinámica bajo el cursor:** en `_on_mouse_move`, si `_replay_select_mode` está ON,
   dibujar una línea vertical azul (`#2962ff`) anclada al centro de la vela bajo el cursor (reusar
   el snapping del crosshair, `_snap_crosshair_x`), en price_canvas y atr_canvas. Tag propio
   (`replay_select_hover`) que se borra/redibuja en cada Motion.
2. **Cursor tijeras:** Tk no trae "scissors" nativo. Opciones (elegir la más simple que se vea):
   (a) cursor nativo aproximado (`'pirate'` o `'tcross'`), o (b) dibujar un pequeño símbolo `✂`
   (createText con carácter unicode) centrado en la línea a la altura media del canvas. Preferir
   (b) con `✂` en el canvas + cursor nativo `'crosshair'` de respaldo, borrándolo en `<Leave>`.
   `ponytail:` texto unicode; si el glyph no renderiza en WSLg, cae al cursor nativo — dejar comentario.
3. **Etiqueta `Re: <fecha>`:** en el eje temporal (time_axis_canvas), bajo la línea azul, caja azul
   con texto `Re: ` + la MISMA fecha que produce `_crosshair_time_label` para esa vela. Tag propio.
4. **Velo blanco sobre velas futuras:** rectángulo blanco semitransparente desde la línea azul hasta
   el borde derecho del canvas. Tk **no soporta alpha real** en Canvas; usar `-stipple => 'gray25'`
   (o 'gray50') con `-fill => 'white'` `-outline => ''` para simular transparencia. Tag propio
   (`replay_select_veil`), redibujado en Motion. Cubre solo price_canvas (y atr_canvas si aplica).
5. **Al hacer click** (`set_selected_bar` desde `_start_horizontal_drag`, ya existe): borrar hover,
   línea azul dinámica y velo; el marcador fijo (0030) y el recorte por replay ya funcionan.
6. Al salir de select mode (`clear_replay_select_mode`): borrar todos los tags nuevos.

## Criterios de aceptación
- En select mode, mover el ratón mueve la línea azul y actualiza la etiqueta `Re: <fecha>` a la
  vela bajo el cursor (fecha idéntica a la del crosshair para esa vela).
- Las velas a la derecha del cursor se ven atenuadas por el velo; a la izquierda normales.
- Click fija el inicio, quita velo/línea/tijeras y recorta el chart (comportamiento 0030 intacto).
- Salir de select mode limpia todos los tags (sin residuos).
- `prove -l t` verde; test en `t/25-replay-select-bar.t`: verificar que el cálculo de la X de la
  línea y del borde del velo corresponde al índice bajo el cursor, y que `_crosshair_time_label`
  alimenta la etiqueta `Re:`. (Lo visual, con mock de canvas que registre ops por tag.)

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c Market/ChartEngine.pm && prove -l t/25-replay-select-bar.t t"
```
Validación visual obligatoria en WSLg (comparar con captura 1 y 2).

## Qué no tocar
- No cambiar la semántica `selected - 1` del inicio (requisito profe).
- No romper el marcador fijo de 0030 ni los binds Shift+←/→.
- No romper el crosshair normal fuera de select mode.
