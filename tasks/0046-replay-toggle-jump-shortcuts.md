# Task 0046: Replay — Play/Pause toggle, Jump-to-real-time, atajos y marca de agua

## Referencia
- `docs/TRADINGVIEW_BAR_REPLAY_REFERENCE.md` §6, §7, §8, §19 capturas 1 y 2.
- Depende de 0043 (panel flotante).

## CRITERIO FIJO (heredado 0048 + 0049) — LEER ANTES DE CODIFICAR
- Etiquetas de botones ASCII legibles, NO glyphs unicode (mojibake en Fedora35). El toggle
  Play/Pause alterna TEXTO `Play` ↔ `Pause` (no `▷`/`❚❚`). Jump = `Jump >>|` o `>>|`. Cerrar = `X`.
- **API de Tk Fedora35 (ver lección completa en tasks/0049 y `scratch/probe_*.pl`):** métodos SIN
  prefijo `winfo_`; `idletasks` no `update_idletasks`; `waitWindow` no `wait`; `Tk::bind($seq,$cb)`
  sin modo `'+'`; pad asimétrico arrayref `[t,b]`.
- La marca de agua "Replay" con `createText` es ASCII normal (texto latino), sin problema de fuente.

## Objetivo
Cerrar el calque de comportamiento:
1. **Play/Pause como UN botón toggle** (no dos botones separados). En la UI actual es el botón de
   triángulo (icono Canvas); alterna play↔pause en el MISMO widget.
2. **Jump to real-time** (botón `>>`): carga todo hasta el final y sale del replay al instante.
3. **Marca de agua "Replay"** gris en el centro del chart mientras el modo está activo (captura 2).
4. **Botón nuevo para activar/desactivar la marca de agua** (pedido de Bryan: por si molesta).

> **Atajos de teclado (`Shift+↓`/`Shift+→`) MOVIDOS a task 0050 (DIFERIDO por Bryan, 05/07).**
> No implementar en 0046. La precedencia con Select Bar queda documentada en 0050.

## Estado actual (tras 0045 + fixes UX)
- Transporte con **iconos Canvas** (`ReplayMediaWidget`): play (triángulo), back, fwd, jump, exit.
- El botón de play arranca autoplay pero NO alterna a pausa en el mismo widget todavía.
- `>>` es fast-forward, no "jump to real-time".
- No hay marca de agua ni botón para conmutarla.

## Diseño
En `Market/UI/Callbacks.pm` + `Market/ChartEngine.pm` + `Market/UI/ReplayPanel.pm` (widget media):
1. **Toggle Play/Pause en el MISMO botón triángulo:** `make_replay_toggle_play` → si `playing`
   pausa; si no, arranca autoplay (usando `tick_ms()`/`advance_one_tick` de 0041/0045). El icono
   Canvas alterna triángulo (play) ↔ dos barras (pause) redibujando el Canvas del botón — NO texto,
   NO glyph de fuente (mantener estilo "control remoto" ya aprobado). Conservar
   `make_replay_play`/`make_replay_pause` como internos.
2. **Jump to real-time:** `make_replay_jump_real` (cableado al botón `>>`) → lleva `replay_idx` al
   último índice (`step` hasta el final o setter directo), luego `exit()` + limpiar estado (reusar
   la limpieza de exit) → chart vuelve a vivo mostrando todas las velas. Distinto del botón exit
   solo en que jump primero revela todo; documentar la diferencia.
3. **Marca de agua:** en `render`, si el replay está activo Y la marca está habilitada (ver #4),
   dibujar texto gris claro "Replay" grande y centrado (createText con `-fill => '#d0d0d0'`), detrás
   de las velas (lower). Tag propio, borrado al salir del replay. (Texto latino ASCII, sin problema
   de fuente.)
4. **Botón nuevo para activar/desactivar la marca de agua** (pedido explícito de Bryan 05/07: "por
   si molesta"):
   - Añadir en la barra inline de replay (`ReplayPanel`) un botón/toggle con etiqueta ASCII, p.ej.
     `Mark` o `Watermark` (NO glyphs; criterio 0048). Puede ser un `Checkbutton` o un botón que
     alterne su texto (`Mark: on` ↔ `Mark: off`).
   - Estado por defecto: marca de agua **ON** (visible), como TradingView.
   - Al conmutar: guardar el flag (p.ej. en el estado de replay / `ReplayController` o el hash de
     UI) y forzar re-render para que la marca aparezca o desaparezca al instante, sin salir del
     replay ni tocar `replay_idx`.
   - El flag debe RESPETARSE en `render`: marca visible solo si (replay activo) Y (flag ON).
   - `Checkbutton`: recordar lección 0049 (`-pady` va en `pack`, no en el constructor).

> Atajos de teclado → task 0050 (diferido). No incluir aquí.

## Criterios de aceptación
- Un solo botón (triángulo) alterna Play↔Pause y su icono Canvas refleja el estado.
- Jump-to-real-time revela todas las velas y sale del replay (chart en vivo).
- La marca de agua "Replay" aparece solo con el modo activo Y el toggle en ON; desaparece al salir.
- **El botón nuevo activa/desactiva la marca de agua en caliente** (sin reiniciar el replay); su
  etiqueta refleja el estado. Por defecto ON.
- `prove -l t` verde; tests en `t/17-ui-wiring.t`/`t/12-replay.t`/`t/26-replay-dropdown.t`: toggle
  Play cambia `playing`; jump deja `is_active==0` y replay_idx en el último; el flag de marca de agua
  controla si se dibuja (verificar la condición `render` marca=ON/OFF vía snapshot o estado).

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c market.pl && perl -I. -c Market/UI/Callbacks.pm && perl -I. -c Market/ChartEngine.pm && prove -l t/12-replay.t t/17-ui-wiring.t t/25-replay-select-bar.t t"
```
**OBLIGATORIO además de tests:** arrancar la app real (`perl -I. market.pl`) sin crash y comprobar
en runtime que el botón triángulo alterna play↔pause (icono cambia), que Jump revela todo y sale, y
que la marca de agua aparece/desaparece. Recordar 0049: `perl -c` + tests con mock NO detectan
errores de API de Tk (ver handoff §5, tabla de 10 síntomas).
Validación visual del arquitecto en WSLg (comparar con capturas 1 y 2).

## Qué no tocar
- No romper Select Bar (0042) ni sus atajos Shift+←/→.
- No romper la limpieza de estado al salir/cambiar TF (0040).
