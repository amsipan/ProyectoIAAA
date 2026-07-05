# Handoff para el arquitecto — noche 2026-07-05

**Contexto:** El arquitecto se fue a dormir tras dejar el repo en `c58cb8a` con specs 0045/0046
actualizadas y prompts para el implementor. Bryan continuó trabajando con el implementor (este agente).
Este documento recoge **todo lo hecho desde `c58cb8a`**, los pedidos explícitos de Bryan, el estado
real del lote CALQUE Bar Replay, y qué falta / qué revisar.

**HEAD actual al escribir esto:** ver último commit en §2 (actualizado tras cada sesión).

**Suite de tests:** ver §2 (objetivo: mantener verde tras cada cambio).

---

## 1. Punto de partida (mensaje del arquitecto a Bryan)

El arquitecto reportó en `c58cb8a`:

- 0044 + 0049 verificadas: menú Go-to despliega en runtime (4 bugs Tk Fedora35 corregidos).
- Specs 0045 y 0046 actualizadas con criterios 0048 (ASCII) y 0049 (API Tk Fedora35).
- Plantilla dropdown: `Market/UI/ReplayGotoMenu.pm` (Frame + place + toggle + click-fuera).
- Siguiente trabajo del implementor: **0045**, luego **0046**.
- 0047 (tijeras vectoriales) explícitamente **NO** hacer aún.
- Regla dura: `prove -l t` + `perl -I. market.pl` sin crash + verificación visual runtime.

---

## 2. Commits desde `c58cb8a` (orden cronológico)

| Commit | Resumen |
|--------|---------|
| `eb513e2` | UX Replay: línea azul al activar pestaña, truncado al clic en vela, tijeras `Helvetica 18` |
| `757b432` | **0045 core:** barra Replay **inline** (pestaña Replay), sin `<< Bar Replay`; dropdowns `1x`/`D`; `tick_ms()` + `advance_one_tick()`; botones control remoto `|<` `>` `>|` |
| `83da0ff` | Fix crash Tk Fedora35: `-background` no puede ser widget; `pady` arrayref solo en `pack`, no en `Checkbutton` |
| `79373cc` | Fix dropdowns multi-clic: `after(1)` antes del bind click-fuera; cerrar menús hermanos; `ReplayGotoMenu` hereda `ReplayDropdown`; `t/26-replay-dropdown.t` |
| `eb4757c` | Este handoff document creado |
| `1df6337` | Ancla Select Bar ~80% (TradingView) — ver §3 sesión E |
| *(ver git log)* | Gap fijo 20% zoom-independiente; Play triangulo Canvas; exit X restaura velas |

**Evolución tests:** 1090 (c58cb8a) → … → **1122** (+tests anchor/exit/play icon).

---

## 3. Pedidos explícitos de Bryan (acumulado para revisión del arquitecto)

### Sesión A — UX selección (`eb513e2`)

1. **Activación inmediata:** al pulsar Replay debe mostrarse la línea azul sin botón extra.
   - Implementado: `_seed_replay_select_hover()` al activar modo selección.
2. **Clic en vela:** truncar gráfico (vela elegida + derecha desaparecen); última visible = vela anterior; esperar Play.
   - Implementado: `replay_confirm_bar_selection()` → `_replay_begin(selected-1)`.
3. **Tijeras más grandes:** `Helvetica 14` → `Helvetica 18` (sigue siendo glyph unicode; 0047 pendiente).

### Sesión B — Barra estilo TradingView (`757b432`)

1. **Sin botón `<< Bar Replay`:** en TV no existe; controles en barra horizontal inferior.
   - Implementado: pestaña **Replay** en `market.pl`; `ReplayPanel` modo `inline`.
2. **Al pulsar pestaña Replay:** modo tijeras + línea azul automático (no segundo clic).
   - Implementado: `make_replay_activate()` al cambiar a pestaña Replay.
3. **Botones control remoto ASCII:** `|<` atrás, `>` play (centro), `>|` adelante (sin palabras).
4. **Dropdown velocidad `1x`:** 9 opciones; escala real 1x=1 vela/s, 5x=5/s, 0.1x=1/10s, etc.
5. **Controles no flotando sobre ATR:** empaquetados en pestaña Replay.

### Sesión C — Bugs runtime reportados por Bryan

1. **Crash al lanzar** (`83da0ff`): `unknown color name ".frame.frame1.frame5"` — `-background => $parent` en inline.
2. **Crash Checkbutton** (`83da0ff`): `bad screen distance "4 4"` — `pady` en constructor vs `pack`.

### Sesión D — Dropdowns intermitentes (`79373cc`)

1. **Varios clics para abrir menú:** race Tk conocida — bind click-fuera sincrónico cierra en el mismo clic.
   - Fix: `after(1)` + cerrar hermanos (`v`/`1x`/`D`) + base común `ReplayDropdown`.

### Regla operativa acordada con Bryan

- Siempre `perl -I. -c` + `prove -l t` + smoke `market.pl` **antes** de reportar "hecho".
- Informe acumulado al final de cada respuesta (este doc lo centraliza).

### Sesión E — Decisiones UX + ancla 80% (Bryan, arquitecto temporal)

**Decisiones confirmadas por Bryan (para 0046 y posteriores):**

1. **Mantener estilo control remoto** en botones (`|<` `>|`, etc.).
2. **Play = triángulo** (como TV), NO el símbolo `>` — pendiente implementar en 0046.
3. **`>>` = JumpToRealTime** (revelar todo y salir del replay) — pendiente 0046.
4. **Dropdowns `v`/`1x`/`D`:** Bryan confirma que ya funcionan bien tras `79373cc`.
5. **Ancla Select Bar ~80%:** tras clic en vela, la última visible (selected-1) queda al ~80%
   del ancho del plot, con hueco a la derecha para velas futuras del Play (estilo TradingView).
   - Implementado: `frame_replay_view_at($idx, { anchor => 1 })` solo en `replay_confirm_bar_selection`;
     `REPLAY_RIGHT_GAP_FRAC = 0.20` (hueco fijo en px, no depende del zoom en barras).
6. **Play triángulo TV:** Canvas con `createPolygon` (no texto `>`).
7. **Exit X:** `restore_after_replay_exit()` limpia anchor/shift/offset + `sync_overlay_indicators`.
8. **Botones multimedia unificados:** cajita `raised` + iconos Canvas (back/fwd/goto/jump/exit/select)
   + `Button` overlay con `-command` (fix Play que no respondía en Fedora35).

---

## 4. Estado de tasks 0041–0049

| Task | Estado en repo | Notas para el arquitecto |
|------|----------------|--------------------------|
| 0041 | ✅ hecho | Backend speed/interval — sin cambios en esta sesión |
| 0042 | ✅ hecho | Selección visual; UX ampliada en `eb513e2` |
| 0043 | ✅ hecho | **Desviación:** panel ya no flota; es **inline** en pestaña Replay (`757b432`). Actualizar narrativa en docs si se aprueba |
| 0044 | ✅ hecho | Go-to; refactorizado a heredar `ReplayDropdown` en `79373cc` |
| 0045 | ✅ marcada hecho | Core implementado + extras UX Bryan. **Falta tu verificación visual WSLg** (capturas 4 y 5) |
| 0046 | ⏳ pendiente | **Siguiente lógica** — ver sección 6 (conflictos de spec) |
| 0047 | ⏸ no tocar | Tijeras vectoriales — baja prio, explícitamente postergada |
| 0048 | ✅ hecho | ASCII en panel; botones ahora son `>|<` `>` `>|` (más allá del panel original) |
| 0049 | ✅ lección | Aplicada en todos los módulos Replay UI; nuevos bugs encontrados y corregidos en `83da0ff`/`79373cc` |

---

## 5. Archivos principales tocados (post-c58cb8a)

| Archivo | Cambio |
|---------|--------|
| `Market/UI/ReplayPanel.pm` | Modo inline, botones ASCII, cableado dropdowns, `_panel_background`, `toggle_menu` hermanos |
| `Market/UI/ReplayDropdown.pm` | Base común: place/toggle, `after(1)` click-fuera, `_widget_contains` |
| `Market/UI/ReplayGotoMenu.pm` | Hereda `ReplayDropdown`; eliminada duplicación show/hide/bind |
| `Market/UI/ReplaySpeedMenu.pm` | Dropdown 9 velocidades |
| `Market/UI/ReplayIntervalMenu.pm` | Dropdown intervalo + Auto toggle |
| `Market/UI/Callbacks.pm` | `tick_ms`, `advance_one_tick`, `reschedule_replay_play`, activate/truncado |
| `market.pl` | Pestaña Replay inline; sin `<< Bar Replay` |
| `t/25-replay-select-bar.t` | Tests UX selección/truncado |
| `t/26-replay-dropdown.t` | Tests race dropdown (13 tests) |
| `tasks/0045-*.md`, `tasks/README.md` | 0045 marcada ✅ |

---

## 6. Desviaciones de spec que requieren visto bueno del arquitecto

### 6.1 Panel inline vs flotante (0043)

La spec 0043 y la 0046 aún hablan de "panel flotante". Bryan pidió explícitamente barra en pestaña
inferior estilo TradingView. **Recomendación:** aprobar desviación y actualizar 0043/0046/docs.

### 6.2 Botón Play en 0046 vs UI actual — **DECIDIDO por Bryan**

- **Bryan:** mantener control remoto; Play = **triángulo ASCII** (p. ej. `>` rotado no — usar `>` triangular
  o carácter `4`/`►` solo si Fedora35 lo renderiza; preferir dibujo/triángulo canvas o ASCII `>` estilizado
  — validar en WSLg). Toggle Play ↔ Pause en el **mismo** botón.
- **Spec 0046 original** decía texto `Play`/`Pause` — actualizar spec al aprobar.

### 6.3 Botón `>>` en 0046 — **DECIDIDO por Bryan**

- **`>>` = JumpToRealTime** (revelar todas las velas y salir del replay).
- Fast-forward +10 actual se elimina o se mueve (decidir en 0046; TV no lo tiene en barra principal).

### 6.4 Verificación visual pendiente del arquitecto

Aunque `perl -I. market.pl` arranca y los tests pasan, **Bryan no confirmó explícitamente** tras
`79373cc` que los dropdowns abren al primer clic en WSLg. El implementor solo tiene smoke headless
(timeout). **El arquitecto debe:**

1. `git pull backup main`
2. `perl -I. market.pl` en WSLg
3. Probar `v`, `1x`, `D` — primer clic consistente
4. Probar velocidades (1x lento, 5x rápido)
5. Captura visual vs referencia TradingView

---

## 7. Lecciones Tk Fedora35 (ampliación de 0049)

Además de los 4 bugs originales del arquitecto:

| # | Síntoma | Causa | Fix |
|---|---------|-------|-----|
| 5 | `unknown color name ".frame..."` | `-background => $widget` en inline | `cget('-background')` del padre |
| 6 | `bad screen distance "4 4"` | `-pady => [t,b]` en widget, no en `pack` | Mover `pady` al `->pack()` |
| 7 | Menú abre y cierra al instante / multi-clic | `Tk::bind <Button-1>` sincrónico en `show()` | `after(1)` antes de instalar bind |
| 8 | Menús hermanos interferían | Un solo bind en `$mw`, sin cerrar hermanos | `hide_menus` antes de `toggle` |

---

## 8. Verificación reproducible (comandos)

```bash
# Compilar
perl -I. -c market.pl
perl -I. -c Market/UI/ReplayPanel.pm
perl -I. -c Market/UI/ReplayDropdown.pm
perl -I. -c Market/UI/ReplayGotoMenu.pm
perl -I. -c Market/UI/ReplaySpeedMenu.pm
perl -I. -c Market/UI/ReplayIntervalMenu.pm
perl -I. -c Market/UI/Callbacks.pm

# Tests
prove -l t

# Runtime smoke (headless — no sustituye WSLg visual)
timeout 20 perl -I. market.pl
```

---

## 9. Próximos pasos recomendados (para Bryan + implementor mientras el arquitecto duerme)

### Inmediato (arquitecto al despertar)

1. Leer este handoff.
2. Verificación visual WSLg de 0045 (dropdowns + barra inline + velocidad real).
3. Decidir desviaciones §6 (Play/Pause, `>>` jump vs fast-fwd, panel inline).
4. Aprobar o corregir 0045 formalmente → luego 0046.

### Implementación 0046 (cuando se apruebe criterio Play/`>>`)

Alcance según `tasks/0046-replay-toggle-jump-shortcuts.md`, adaptado a UI actual:

1. Toggle Play/Pause en botón `>` (texto según decisión §6.2).
2. `>>` → jump-to-real-time (revelar velas + salir replay).
3. Atajos `Shift+Down` (toggle), `Shift+Right` (step fwd) sin pisar Select Bar.
4. Marca de agua "Replay" en canvas (gris, centrada).
5. Tests + runtime obligatorio (regla 0049).

### NO hacer aún

- **0047** tijeras vectoriales.
- Refactors grandes fuera del lote Replay.

### Tasks que ya no aplican tal cual (pero el trabajo está hecho)

- Prompt original 0045 "panel flotante sobre botón 1x" → **superado** por inline + dropdowns (mismo patrón).
- Estado "autoplay 80ms fijo" en texto de 0045 → **resuelto** en `757b432`.

---

## 10. Rol temporal

Mientras el arquitecto no esté, el implementor asume coordinación con Bryan, mantiene este handoff
actualizado en cada sesión significativa, y **no marca 0046 como hecha** sin verificación runtime +
actualización de este documento.

---

*Generado: 2026-07-05. Autor: implementor (rol arquitecto temporal por instrucción del arquitecto a Bryan).*
*Base: `c58cb8a` → `1df6337`.*