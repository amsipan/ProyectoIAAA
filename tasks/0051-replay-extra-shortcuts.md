# Task 0051: Replay — atajos extra (no-TV): Step Back, Escape, Toggle marca de agua

**Estado:** ✅ HECHO (2026-07-05). Shift+Left step back, Escape exit, M toggle Mark; 1153 PASS.
Autorizado por Bryan (2026-07-05). Capa extra independiente de 0050 (calque TV puro).

## Referencia
- `docs/TRADINGVIEW_BAR_REPLAY_REFERENCE.md` §6 (§ nota: TV no tiene step-back oficial; la comunidad
  lo pide desde 2024).
- Depende de 0046 (exit, step_back y toggle de marca de agua ya existen como acciones de botón).
- Hermana de 0050 (mismos canvas, mismo patrón de bind con guard por estado).

## Objetivo
Tres atajos de teclado extra, activos solo con la pestaña Replay activa:
- **`Shift+←`** (`<Shift-Left>`) → step back (retroceder una vela) cuando el replay corre.
- **`Esc`** (`<Escape>`) → salir del replay (equivale al botón Exit X).
- **`M`** (`<Key-m>`) → activar/desactivar la marca de agua "Replay" (equivale al botón `Mark`).

## Estado actual (ya en el código)
- `make_replay_step_back` (`Callbacks.pm:644`) y `ReplayController::step_backward` (`:92`) EXISTEN.
- `make_replay_exit` (`Callbacks.pm:678`) EXISTE (lo usa el botón Exit X).
- `<Shift-Left>` YA bindeado en canvas precio (`ChartEngine.pm:1302`) y ATR (`:1362`) con
  `return unless $self->{_replay_select_mode}` → hoy solo mueve la selección en Select Bar.
- Flag marca de agua: `$replay_watermark_on` en `market.pl:128`, ref en `%ui_vars{replay_watermark_on}`
  y en `$chart_engine->{replay_watermark_on_ref}`. El botón `Mark` lo conmuta INLINE en
  `ReplayPanel.pm:308-323` (flip flag + `mark_btn->configure(-text=>...)` + re-render).
- ⚠️ **CONFLICTO:** `<Key-m>` YA está bindeado: precio → `set_scale_mode('manual')`
  (`ChartEngine.pm:1297`), ATR → `set_atr_scale_mode('manual')` (`:1357`). NO se puede simplemente
  re-bindear o se pierde el "modo manual". Ver resolución abajo.

## Diseño
1. **`<Shift-Left>` (step back) — extender el bind existente con precedencia** (igual que hizo 0050
   con `<Shift-Right>`):
   - `_replay_select_mode` ON → `adjust_selected_bar(-1)` como HOY. NO tocar.
   - Replay activo y NO en select mode → retroceder un paso (reusar `make_replay_step_back` /
     `step_backward`). No reimplementar.
   - Nada activo → nada.
   - Documentar la precedencia (select > replay-activo > nada) en comentario.
2. **`<Escape>` (salir del replay):**
   - Bindear en canvas precio Y ATR. Actuar solo si el replay está activo; si no, no hacer nada
     (no interferir con otros usos de Esc si los hubiera).
   - Reutilizar `make_replay_exit` (mismo efecto que el botón Exit X: restaura chart completo,
     `replay_on=0`, sale de Select Bar).
3. **`<Key-m>` (toggle marca de agua) — resolver el conflicto por ramificación:**
   - **Factorizar primero** la lógica del toggle del Mark que hoy está inline en
     `ReplayPanel.pm:308-323` a una función reutilizable (p.ej. `make_replay_toggle_watermark` en
     `Callbacks.pm`): flip del flag `replay_watermark_on_ref` + re-render + (si hay `mark_btn`
     accesible) sincronizar su texto `Mark: on/off`. El botón `Mark` pasa a usar esa función.
   - En el handler de `<Key-m>` (precio y ATR): **si el replay está activo → toggle marca de agua**
     (y `return`); **si no → comportamiento actual** (`set_scale_mode('manual')` /
     `set_atr_scale_mode('manual')`). Así M sigue sirviendo para escala manual fuera del replay y
     conmuta la marca dentro del replay, sin perder ninguna función.
   - Mantener sincronizado el texto del botón `Mark` cuando se conmuta por teclado (que no queden
     desfasados botón y estado real).

## Notas de implementación (lecciones 0049 — obligatorias)
- API Tk Fedora35: `$w->Tk::bind($seq,$cb)` sin modo `'+'`. Los canvas ya reciben `focus` en `<Enter>`.
- Bindear en precio Y ATR, igual que los atajos existentes.
- Guard por estado dentro del callback (no instalar/quitar binds dinámicos): evita atajos huérfanos.
- Sin UI nueva → criterio ASCII 0048 no aplica (el texto `Mark: on/off` ya es ASCII).

## Criterios de aceptación
- `Shift+←` mueve selección en Select Bar; retrocede el replay cuando corre y NO en select; sin
  regresión del comportamiento actual de selección.
- `Esc` sale del replay solo cuando está activo (mismo efecto que Exit X).
- `M` dentro del replay conmuta la marca de agua (y actualiza el texto del botón `Mark`); fuera del
  replay sigue poniendo la escala en manual (sin regresión).
- El botón `Mark` y la tecla `M` comparten la MISMA lógica (una sola fuente de verdad del toggle).
- `prove -l t` verde; tests en `t/17-ui-wiring.t`:
  - precedencia de `Shift+←` (select vs replay-activo) invocando el callback real;
  - `make_replay_toggle_watermark` (o equivalente) alterna el flag correctamente;
  - `make_replay_exit` deja `is_active==0`.

## Verificación
```bash
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c market.pl && perl -I. -c Market/ChartEngine.pm && perl -I. -c Market/UI/Callbacks.pm && perl -I. -c Market/UI/ReplayPanel.pm && prove -l t"
```
**OBLIGATORIO (0049):** arrancar la app real (`perl -I. market.pl`), entrar en Replay y probar EN
RUNTIME: Shift+← retrocede, Esc sale, M conmuta la marca; y comprobar que M FUERA del replay sigue
poniendo escala manual. `perl -c` + mocks no detectan errores de bind de Tk.

## Qué no tocar
- No romper Select Bar (0042) ni el `<Shift-Left>`/`<Shift-Right>` de selección.
- No romper el `<Key-m>` de escala manual FUERA del replay (precio y ATR).
- No romper el toggle Play/Pause, el Jump, el Mark ni los atajos TV de 0050.
- No añadir más atajos de los tres listados.
