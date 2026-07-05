# Task 0050: Replay — atajos de teclado oficiales TradingView

**Estado:** ✅ HECHO (2026-07-05). Shift+Down toggle, Shift+Right precedencia; 1153 PASS.
Alcance CERRADO a los 2 atajos oficiales de TV. No añadir extras sin pedido explícito.

## Referencia
- `docs/TRADINGVIEW_BAR_REPLAY_REFERENCE.md` §6 (atajos oficiales) y §7.
- Depende de 0046 (toggle Play/Pause `make_replay_toggle_play` y step `make_replay_step_fwd` ya existen).
- Se separó de 0046 porque Bryan lo difirió; ahora autorizado.

## Objetivo
Solo los 2 atajos que TradingView documenta oficialmente, activos solo con la pestaña Replay activa:
- **`Shift+↓`** (`<Shift-Down>`) → toggle Play/Pause.
- **`Shift+→`** (`<Shift-Right>`) → avanzar un paso (step forward).

NO implementar `Shift+←` (step back), ni Espacio, ni jump, ni velocidad por teclado: TV no los tiene
oficiales y Bryan pidió calcar TV exacto.

## Estado actual (ya en el código)
- `Market/ChartEngine.pm` ~1302 y ~1362: `<Shift-Left>`/`<Shift-Right>` YA bindeados en el canvas de
  precio y en el de ATR, con `return unless $self->{_replay_select_mode};` → solo mueven la selección
  en modo Select Bar (`adjust_selected_bar(±1)`).
- `<Shift-Down>` NO existe todavía.
- Funciones listas para cablear: `Market::UI::Callbacks::make_replay_toggle_play`,
  `make_replay_step_fwd`; `ReplayController` tiene `step_forward`/`advance_one_tick`/`is_active`;
  `ChartEngine::is_replay_select_mode`.

## Diseño
1. **`<Shift-Down>` (toggle Play/Pause):** bindear en los MISMOS dos canvas (precio + ATR), llamando
   al toggle ya existente. El bind debe actuar solo si el replay está activo (`is_active` /
   `replay_on`); si no, no hacer nada. Reutilizar la lógica de `make_replay_toggle_play` (no duplicar
   el play/pause; invocar el callback o factorizar un helper interno que ambos usen).
2. **`<Shift-Right>` (step forward) — extender el bind existente con precedencia:**
   - Si `_replay_select_mode` ON → seguir moviendo la selección (`adjust_selected_bar(1)`), como HOY.
     NO tocar ese comportamiento.
   - Si replay activo y NO en select mode → avanzar un paso del replay (equivalente a
     `make_replay_step_fwd`). Reutilizar la misma función del botón Forward, no reimplementar.
   - Si nada activo → no hacer nada.
   - Documentar la precedencia (select > replay-activo > nada) en un comentario.
3. **`<Shift-Left>`:** SIN CAMBIOS. Sigue solo para mover selección en Select Bar (TV no tiene
   step-back oficial). Dejarlo como está.

## Notas de implementación (lecciones 0049 — obligatorias)
- API Tk Fedora35: `$w->Tk::bind($seq, $cb)` sin modo `'+'`. Los canvas ya reciben `focus` en
  `<Enter>`, así que los binds de teclado responden cuando el cursor está sobre el chart.
- Bindear en precio Y ATR (igual que los Shift+flechas actuales) para que funcione en ambos paneles.
- No hace falta instalar/quitar binds dinámicamente: el guard por estado (`is_active`/select_mode)
  dentro del callback basta y evita atajos huérfanos (mismo patrón que los Shift+flechas actuales).
- Sin UI nueva → criterio ASCII 0048 no aplica.

## Criterios de aceptación
- `Shift+↓` alterna Play↔Pause solo con replay activo; el icono del botón triángulo refleja el cambio
  (reusa `_sync_replay_play_icon`).
- `Shift+→` mueve selección en Select Bar; avanza el replay cuando está corriendo y NO en select.
- `Shift+←` sigue solo moviendo selección (sin regresión).
- No quedan atajos activos fuera del modo replay.
- `prove -l t` verde; test en `t/17-ui-wiring.t` o `t/25-replay-select-bar.t` que verifique la
  PRECEDENCIA de `Shift+→` según modo (select vs replay-activo) invocando el callback real, no lógica
  reimplementada.

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c market.pl && perl -I. -c Market/ChartEngine.pm && perl -I. -c Market/UI/Callbacks.pm && prove -l t"
```
**OBLIGATORIO (0049):** arrancar la app real (`perl -I. market.pl`), entrar en Replay y probar los
atajos EN RUNTIME (Shift+↓ pausa/reanuda, Shift+→ avanza). `perl -c` + mocks no detectan errores de
bind de Tk.

## Qué no tocar
- No romper Select Bar (0042) ni el `<Shift-Left>`/`<Shift-Right>` de selección.
- No romper el toggle Play/Pause, el Jump ni el Mark de 0046.
- No añadir atajos que TradingView no documenta (decisión de Bryan: calcar TV exacto).
