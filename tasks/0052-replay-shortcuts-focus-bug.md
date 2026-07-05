# Task 0052: Replay — atajos de teclado no responden en runtime (foco)

**Estado:** 🐞 ABIERTA (reportada por Bryan 2026-07-05). Los atajos 0050/0051 pasan tests pero NO
funcionan al usarlos: en replay con vela ya seleccionada, `Shift+↓` no da Play ni cambia el icono
del panel. Igual sospecha para el resto (`Shift+→/←`, `Esc`, `M`).

## Síntoma exacto (Bryan)
- Entra a la pestaña Replay, selecciona una vela (se coloca bien).
- Pulsa `Shift+↓` esperando Play (y que el botón del panel alterne play↔pausa): NO pasa nada.

## Diagnóstico (arquitecto)
Los handlers (`_replay_shift_down_key`, etc.) y sus tests son correctos — por eso `prove` pasa: los
tests invocan los handlers directamente. El fallo está en el **puente Tk → handler en runtime**, muy
probablemente el **foco de teclado**:
- Los binds de teclado están en `price_canvas` y `atr_canvas` (`ChartEngine::_bind_all_canvas`).
- El canvas solo toma foco en `<Enter>` (`$p_canvas->focus`, líneas ~1372 y ~1426).
- Al hacer clic para seleccionar la vela, o al usar el panel de controles (botones/dropdowns), el
  foco de teclado se va a esos widgets. Si el cursor no vuelve a ENTRAR al canvas (o el WM no
  re-dispara `<Enter>`), los `<Shift-*>` se envían al widget con foco (un Button/Frame) que no los
  tiene bindeados → el atajo "no hace nada".
- `<Down>` (sin Shift) ya está bindeado para pan vertical; NO colisiona con `<Shift-Down>` (eventos
  distintos en Tk), así que la causa no es esa.

**Verificar primero (en vivo, WSLg):** lanzar la app, entrar en replay, seleccionar vela, mover el
cursor SOBRE el chart y recién ahí pulsar `Shift+↓`. Si con el cursor dentro del chart SÍ funciona,
queda confirmado que es foco. (El arquitecto puede automatizarlo con xdotool: `key shift+Down` y leer
si el icono del panel cambió.)

## Fix propuesto
Que los atajos de replay NO dependan de que el cursor esté sobre el canvas:
1. **Bindear también a nivel de ventana (toplevel)**, no solo en los canvas. Añadir los mismos binds
   (`<Shift-Down>`, `<Shift-Right>`, `<Shift-Left>`, `<Escape>`, `<Key-m>`) al toplevel (`$mw`) o vía
   `bindtags`, con el MISMO guard por estado (`is_active`/`_replay_select_mode`) para no actuar fuera
   de replay. Reutilizar los handlers existentes (no duplicar lógica).
   - Ojo `<Key-m>`: a nivel de ventana debe seguir ramificando (replay→marca, fuera→NO tocar escala
     global, porque a nivel ventana no hay panel "price/atr" claro; si fuera de replay, mejor no
     hacer nada a nivel toplevel y dejar el `<Key-m>` de escala solo en los canvas). Documentar.
2. **Alternativa/complemento:** cuando el replay se activa (`_replay_begin` / confirmar selección),
   forzar `focus` al `price_canvas` para que los atajos respondan sin pedir al usuario que pase el
   cursor. Combinar con (1) para robustez.
3. Asegurar que el toggle refleje el estado en el PANEL: `_sync_replay_play_icon` ya se llama en
   `make_replay_toggle_play`/play/pause; verificar que tras el atajo el icono del botón cambie
   (Bryan lo espera explícitamente: "debería reflejarse sobre todo en el menú").

## Criterios de aceptación
- En replay (vela ya seleccionada), `Shift+↓` da Play SIN necesidad de tener el cursor sobre el
  chart, y el botón del panel alterna su icono play↔pausa. Otra pulsación pausa.
- `Shift+→`/`Shift+←` avanzan/retroceden; `Esc` sale; `M` conmuta marca — todos sin depender del
  cursor sobre el canvas.
- Fuera de replay, ninguno interfiere (guards intactos); `M`/flechas de escala manual siguen igual
  cuando el cursor está en el canvas.
- `prove -l t` verde. Añadir un test que verifique que el bind existe a nivel de ventana (o que el
  handler se invoca vía el widget de ventana), no solo llamada directa al handler.

## Verificación (OBLIGATORIA en runtime — lección 0049)
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c market.pl && perl -I. -c Market/ChartEngine.pm && prove -l t"
```
Arrancar `perl -I. market.pl`, entrar en replay, y probar CADA atajo con el foco en distintos sitios
(en el chart, en un botón del panel). Todos deben responder. `perl -c`+mocks NO detectan esto.

## Qué no tocar
- No romper los atajos de escala manual (`<Key-m>`, `<Up>/<Down>`, `+/-`) cuando el cursor está en el
  canvas y NO hay replay.
- No romper Select Bar ni el `<Shift-Left>/<Shift-Right>` de selección.
- No duplicar la lógica de play/pause/step; reutilizar `replay_keyboard_callbacks` y los handlers.
