# Task 0046: Replay — Play/Pause toggle, Jump-to-real-time, atajos y marca de agua

## Referencia
- `docs/TRADINGVIEW_BAR_REPLAY_REFERENCE.md` §6, §7, §8, §19 capturas 1 y 2.
- Depende de 0043 (panel flotante).

## Objetivo
Cerrar el calque de comportamiento:
1. **Play/Pause como UN botón toggle** (no dos botones separados).
2. **Jump to real-time** (`▷▷|`): carga todo hasta el final y sale del replay al instante.
3. **Atajos de teclado oficiales:** `Shift+↓` = Play/Pause, `Shift+→` = step forward.
4. **Marca de agua "Replay"** gris en el centro del chart mientras el modo está activo (captura 2).

## Estado actual
- Botones `Play` y `Pause` separados; `>>` es fast-forward (+10), no "jump to real-time".
- Shift+←/→ solo ajustan la vela seleccionada en modo Select Bar (no controlan el autoplay).
- No hay marca de agua.

## Diseño
En `Market/UI/Callbacks.pm` + `Market/ChartEngine.pm`:
1. **Toggle Play/Pause:** `make_replay_toggle_play` → si `playing` pausa; si no, arranca autoplay
   (usando `tick_ms()`/`advance_one_tick` de 0041/0045). El botón del panel alterna icono/texto
   `▷` ↔ `❚❚` según estado. Conservar `make_replay_play`/`make_replay_pause` como internos.
2. **Jump to real-time:** `make_replay_jump_real` → lleva `replay_idx` al último índice
   (`step` hasta el final o setter directo), luego `exit()` + limpiar estado (reusar
   `_sync_replay_ui_cleanup`) → chart vuelve a vivo mostrando todas las velas. Distinto de `✕`
   (cerrar) solo en que jump primero revela todo; documentar la diferencia.
3. **Atajos globales** (bind en la ventana o en los canvas de precio/ATR, activos solo con replay ON):
   - `<Shift-Down>` → toggle play/pause.
   - `<Shift-Right>` → step forward (una vela / un intervalo).
   - NO pisar los Shift+←/→ de Select Bar: cuando `_replay_select_mode` está ON, Shift+←/→ siguen
     moviendo la selección; cuando el replay está activo y NO en select mode, Shift+→ avanza el
     replay. Documentar la precedencia.
4. **Marca de agua:** en `render`, si el replay está activo, dibujar texto gris claro "Replay"
   grande y centrado (createText con `-fill => '#d0d0d0'`), detrás de las velas (lower). Tag propio,
   borrado al salir del replay.

## Criterios de aceptación
- Un solo botón alterna Play↔Pause y su icono refleja el estado.
- `Shift+↓` alterna autoplay; `Shift+→` avanza un paso; no interfieren con Select Bar.
- Jump-to-real-time revela todas las velas y sale del replay (chart en vivo).
- La marca de agua "Replay" aparece solo con el modo activo y desaparece al salir.
- `prove -l t` verde; tests en `t/17-ui-wiring.t`/`t/12-replay.t`: toggle cambia `playing`;
  jump deja `is_active==0` y replay_idx en el último; precedencia de Shift+→ según modo.

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c market.pl && perl -I. -c Market/UI/Callbacks.pm && perl -I. -c Market/ChartEngine.pm && prove -l t/12-replay.t t/17-ui-wiring.t t/25-replay-select-bar.t t"
```
Validación visual en WSLg (comparar con capturas 1 y 2).

## Qué no tocar
- No romper Select Bar (0042) ni sus atajos Shift+←/→.
- No romper la limpieza de estado al salir/cambiar TF (0040).
