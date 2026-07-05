# Revisión visual de la app por el arquitecto (interacción + captura)

> Capacidad del agente arquitecto para **verificar visualmente** la GUI Perl/Tk sin depender del
> usuario: lanzar la app, **navegar con clicks/teclado** como un humano, capturar a PNG y **leer la
> imagen**. Montado y probado el 2026-07-05 (validación de la task 0042).
>
> **Contexto clave:** el agente arquitecto SÍ procesa imágenes; el agente implementor NO. Por eso la
> comparación "¿se ve como TradingView?" es responsabilidad del arquitecto.

## Requisitos (ya instalados en Fedora35)
- **WSLg** activo: `DISPLAY=:0`, `WAYLAND_DISPLAY=wayland-0` (la app Tk corre por XWayland).
- **ImageMagick** (`import`) — captura. `dnf -y install ImageMagick`
- **xwininfo** — inspección de ventanas. `dnf -y install xwininfo`
- **xdotool** — clicks, movimiento de ratón y teclas. `dnf -y install xdotool`

Comprobar con: `scratch/check_screenshot_tools.sh`.

## Reglas de oro aprendidas
1. **Capturar por WINDOW ID, no por root.** `import -window root` FALLA bajo XWayland. Hay que
   localizar la ventana y capturar con `import -window "$WID"`.
2. **Localizar la ventana:** `xdotool search --name "Plataforma" | tail -1`
   (el título real de la app es *"Plataforma de Gráficos Financieros - Motor de Charting Tk"*).
3. **Activar antes de interactuar:** `xdotool windowactivate "$WID"` + `sleep 1`.
4. **Clicks relativos a la ventana:** `xdotool mousemove --window "$WID" X Y click 1`.
5. **Esperar el render:** la app tarda ~7s en abrir+render inicial; poner `sleep 7` tras lanzarla,
   y `sleep 1` entre acciones para que el `after(20ms)` de coalescing dibuje.
6. **Hover (Motion):** para disparar la línea de crosshair/selección hay que MOVER el ratón dentro
   del canvas (dos `mousemove` seguidos a coords ligeramente distintas), no solo posicionarlo.
7. **Copiar el PNG a Windows para leerlo:** `cp /tmp/x.png "/mnt/c/Users/ASUS ROG/AppData/Local/Temp/opencode/x.png"`
   y luego usar la herramienta Read sobre esa ruta Windows.
8. **Scripts en `scratch/`** (ignorado por git). Comandos con `$` fallan al pasar por
   PowerShell→WSL; siempre poner la lógica en un `.sh` y ejecutarlo con
   `wsl -d Fedora35 -- bash -lc "bash '/mnt/c/.../scratch/x.sh'"`.
9. **Cerrar la app al terminar:** guardar el PID y `kill`/`kill -9`, o quedan procesos Tk colgados.

## Coordenadas de referencia (ventana maximizada ~1428x819)
Aproximadas; reconfirmar si cambia el layout de `market.pl`.
- **Barra de pestañas** (fila superior de la barra de controles): `y≈781`.
  - `TF` botones a la izquierda; pestañas `Capas / Liq / Mxwll / ZigZag / Escala / Replay`.
  - Pestaña **Replay**: `x≈618, y≈781`.
- **Fila de controles de la pestaña activa:** `y≈801`.
  - En pestaña Replay: `Select Bar (x≈93) / Inicio / Play / Pause / < / > / >> / Salir`.
  - ⚠️ Estas cambiarán cuando 0043 sustituya la fila por el panel flotante (centrado abajo,
    `relx=0.5, rely=1.0, anchor=s`).
- **Centro del chart** (para hover/click de vela): `x≈700, y≈350`.

## Flujo típico de validación
```bash
# 1) lanzar app en background
perl -I. market.pl >/tmp/out.log 2>/tmp/err.log &
APP_PID=$!; sleep 7
# 2) localizar + activar
WID=$(xdotool search --name "Plataforma" | tail -1)
xdotool windowactivate "$WID"; sleep 1
# 3) navegar (ejemplo: entrar a modo selección de Replay)
xdotool mousemove --window "$WID" 618 781 click 1; sleep 1   # pestaña Replay
xdotool mousemove --window "$WID" 93 801 click 1;  sleep 1   # Select Bar
xdotool mousemove --window "$WID" 700 350;         sleep 1   # hover chart
xdotool mousemove --window "$WID" 720 360;         sleep 1   # mover -> dispara Motion
# 4) capturar por window id
import -window "$WID" /tmp/shot.png
# 5) copiar a Windows y leer con la herramienta Read
cp /tmp/shot.png "/mnt/c/Users/ASUS ROG/AppData/Local/Temp/opencode/shot.png"
# 6) cerrar
kill "$APP_PID"; sleep 1; kill -9 "$APP_PID" 2>/dev/null
```

## Scripts ya listos en `scratch/`
- `check_screenshot_tools.sh` — verifica display + herramientas.
- `capture_app.sh <wait> <out>` — abre app, captura estado inicial, cierra.
- `validate_0042.sh <out>` — ejemplo completo: Replay → Select Bar → hover → captura.
  Plantilla reutilizable para validar otras tareas de UI (copiar y cambiar los clicks).

## Limitaciones (honestas)
- Los clicks son por **coordenadas de píxel**: robustos para botones de barra, frágiles para
  "clickear una vela concreta" o leer tooltips que siguen al cursor. A veces hay que reintentar.
- La validación visual **complementa** los tests headless, no los reemplaza. El veredicto de
  aprobación combina: diff leído + `prove -l t` verde + test que ejercita el código real + captura.
- El usuario (Bryan) da el visto bueno final por si algo se escapa a la captura.

## Ejemplo real (task 0042, 2026-07-05)
Navegué Replay → Select Bar → hover y capturé: confirmé línea azul `#2962ff`, etiqueta
`Re: Mon 29 Jun '26 09:20` en el eje temporal y velo blanco (stipple) sobre las velas a la derecha.
Detecté que el glyph `✂` no renderiza (sale `x`) → registrado como `tasks/0047-replay-scissors-vector.md`.
