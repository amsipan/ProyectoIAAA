# Task 0053: Replay Select Bar — tijera reemplaza al cursor, negra y ligeramente más grande

**Estado:** ⏸ PARCIAL / PAUSADO por Bryan (2026-07-05).
- ✅ **Tijera negra Helvetica 22:** HECHO y verificado (captura + Bryan). Se ve como se pidió.
- ⏸ **Ocultar el cursor del SO en Select Bar:** NO LOGRADO en WSLg. PAUSADO tras muchos intentos.

**Por qué se pausó (para retomar después):** En Fedora35/WSLg (Tk 804.036) NADA logró ocultar del
todo el puntero del SO sobre el chart: sigue mostrándose una flecha de mouse normal, ligeramente
transparente (varía). Intentos fallidos documentados:
- `-cursor => 'none'` / `'blank'` → no existen en este Tk (`bad cursor spec`).
- `-cursor => ''` → `cget=undef`; WSLg pinta flecha fantasma semitransparente.
- XBM fuente+máscara todo-ceros CON hotspot (`['@'.$src,$mask,'black','black']`) → Tk lo ACEPTA
  (probe headless OK) pero WSLg/XWayland igual muestra la flecha fantasma. Aplicado también a los
  frames ancestros (`plot_frames`) sin éxito.
- Hipótesis pendiente: XWayland ignora el cursor Tk vacío y usa el del compositor; probablemente
  requiera XFixesHideCursor vía X11 directo (no expuesto por Perl/Tk 8.x aquí), o un workaround a
  nivel de compositor. Ver `scratch/probe_cursor_*.pl` y la lección en `tasks/README.md`.

**Al retomar:** el código actual (assets XBM + `_select_mode_blank_cursor` con arrayref+hotspot)
queda como base; NO se revierte (es lo más cerca que se llegó y no rompe nada). La tijera negra
funciona. Solo falta resolver la ocultación real del puntero del SO.

**Estado anterior:** ✅ AUTORIZADA (pedido Bryan 2026-07-05). Pulido visual del modo Select Bar. Ojo: la
0047 (tijeras VECTORIALES) sigue sin autorizar; esto es solo color/tamaño/cursor del glyph actual.

## Pedidos de Bryan (exactos)
1. Mientras esté activa la barra vertical azul de selección (modo Select Bar), **el símbolo de
   tijera debe REEMPLAZAR a la cruz del cursor** — es decir, ocultar el cursor nativo `crosshair`
   sobre el chart y que la tijera dibujada haga las veces de puntero.
2. La tijera actualmente es **azul** (`#2962ff`); Bryan la quiere **negra**.
3. Hacerla **ligeramente más grande** (hoy `Helvetica 18`).

## Estado actual (código)
- `Market/ChartEngine.pm:_draw_replay_select_hover` (~1301-1313): dibuja la tijera con
  `-text => "\x{2702}"`, `-font => 'Helvetica 18'`, `-fill => $color` donde `$color = '#2962ff'`
  (el mismo azul de la línea). Tag `replay_select_scissors`.
- El cursor nativo del canvas se fija a `crosshair` en `<Enter>` y en `<Leave>`
  (`_set_cursor($p_canvas, 'crosshair')`, líneas ~1372/1374 y ~1426/1428). Por eso hoy se ve la cruz
  Y la tijera a la vez.

## Diseño
1. **Tijera negra:** en `_draw_replay_select_hover`, para el `createText` de la tijera usar
   `-fill => 'black'` (no `$color`). La LÍNEA vertical y el velo siguen azules (`$color`); solo
   cambia la tijera. (Mantener criterio: es un glyph unicode que en Fedora35 SÍ renderiza a 18pt
   según validación 0042; si por tamaño mayor dejara de renderizar, reportar para 0047 vectorial.)
2. **Ligeramente más grande:** subir la fuente de `Helvetica 18` a ~`Helvetica 22` (ligero, no
   enorme). Ajustar si a 22 se ve mal en WSLg; el arquitecto valida el tamaño final por captura.
3. **Reemplazar el cursor por la tijera:** mientras `_replay_select_mode` está ON y el cursor está
   sobre el chart, poner el cursor nativo en `none` (o `blank`) en price/atr canvas, de modo que solo
   se vea la tijera dibujada siguiendo el puntero. Al salir de select mode (o al `<Leave>`), restaurar
   `crosshair`.
   - Implementar como un helper, p.ej. `_apply_select_mode_cursor($on)`, llamado desde
     `set_replay_select_mode` (on→`none`, off→`crosshair`) y respetado por los binds `<Enter>`/`<Leave>`
     (que hoy fuerzan `crosshair` incondicionalmente: deben consultar el modo y NO pisar el `none`).
   - Fallback (lección 0049): si Tk en Fedora35 no acepta cursor `none`, usar `'tcross'`/`'dotbox'` o
     el que menos estorbe; reportar cuál funciona. NO dejar la cruz `crosshair` encima de la tijera.
4. La tijera debe seguir al cursor (ya lo hace vía `_draw_replay_select_hover` con `last_mouse_x/y`
   en `<Motion>`); no cambiar ese flujo.

## Criterios de aceptación
- En modo Select Bar, sobre el chart NO se ve la cruz nativa; se ve la tijera negra siguiendo el
  cursor, con la línea azul vertical.
- La tijera es negra y algo más grande que antes, legible, sin mojibake.
- Al confirmar la vela (clic) o salir de Select Bar, el cursor vuelve a `crosshair` normal.
- La línea azul y el velo siguen azules (sin regresión de 0042).
- `prove -l t` verde. Test razonable: `_draw_replay_select_hover` usa fill negro para el scissors tag
  (si el snapshot/estado lo permite) o al menos que `set_replay_select_mode` cambie el cursor
  esperado (helper testeable sin GUI).

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c Market/ChartEngine.pm && prove -l t"
```
Validación visual del arquitecto en WSLg (captura del modo Select Bar): confirmar tijera negra,
tamaño, y ausencia de cruz nativa.

## Qué no tocar
- No cambiar el color de la línea vertical ni del velo (siguen `#2962ff` / blanco stipple).
- No tocar la semántica de selección (selected-1) ni el truncado.
- No abordar tijeras vectoriales (eso es 0047, sin autorizar): solo color/tamaño/cursor del glyph.
