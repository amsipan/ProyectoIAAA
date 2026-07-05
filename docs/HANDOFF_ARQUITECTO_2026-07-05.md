# Handoff para el arquitecto — sesión completa 2026-07-05

**Para:** agente arquitecto  
**De:** Bryan (vía implementor, rol arquitecto temporal)  
**Repo:** ProyectoIAAA, rama `main`  
**HEAD:** `47f1a5d`  
**Suite:** **1116 tests PASS** (28 archivos `t/*.t`)  
**Base de partida del arquitecto:** `c58cb8a`

Este documento consolida **todos los pedidos explícitos de Bryan** desde que el arquitecto dejó el repo,
lo implementado, lo que debe **quedar como contrato UX**, lo que requiere **revisión/arquitectura**,
y lo **pendiente** (0046, 0047, verificación visual).

---

## Resumen ejecutivo (30 segundos)

Bryan pidió calcar Bar Replay de TradingView en la pestaña **Replay inline** (no panel flotante).
El lote 0045 está **funcional en repo** con extras UX que Bryan validó o pidió explícitamente.
En la última sesión se corrigieron: **clics de botones** (`Tk::bind`), **Select bar** con texto,
**sin línea punteada fija** en vela confirmada, y **línea horizontal de precio** anclada a `replay_idx`.

**El arquitecto debe:** (1) aprobar desviaciones de spec, (2) verificar WSLg visual, (3) confirmar
que la arquitectura modular se mantiene, (4) autorizar inicio de **0046**.

---

## 1. Lo que Bryan pidió y debe QUEDAR (contrato UX aprobado por implementación)

Estas decisiones salieron de mensajes directos de Bryan. El arquitecto las ratifica o corrige.

### 1.1 Barra y navegación

| # | Pedido Bryan | Estado | Dónde |
|---|--------------|--------|-------|
| B1 | Sin botón `<< Bar Replay`; controles en barra horizontal (pestaña Replay) | ✅ Hecho | `market.pl`, `ReplayPanel` inline |
| B2 | Al abrir pestaña Replay → modo Select bar inmediato (línea azul, sin segundo clic) | ✅ Hecho | `make_replay_activate`, `_seed_replay_select_hover` |
| B3 | Dropdowns `v` / `1x` / `D` funcionando al primer clic | ✅ Hecho (`79373cc`) | `ReplayDropdown`, hermanos |
| B4 | Velocidad real: 1x = 1 vela/s, 5x = 5/s, etc. | ✅ Hecho | `ReplayController::tick_ms`, `advance_one_tick` |
| B5 | Botón **Select bar** con **texto ASCII** (no solo icono tijeras) | ✅ Hecho (`c4a1624`) | `ReplayPanel`, etiqueta `'Select bar'` |
| B6 | Botones multimedia: cajita `raised` + iconos Canvas (play ▷, back, fwd, jump, exit ✕) | ✅ Hecho | `ReplayMediaWidget`, `_make_media_button` |
| B7 | Clics de botones deben responder en Fedora35/WSLg | ✅ Hecho (`c4a1624`) | `Tk::bind` en frame/canvas/label/hit |
| B8 | Mantener estilo “control remoto”; Play = **triángulo** (no texto `>`) | ✅ Hecho | `_draw_play` Canvas |
| B9 | `>>` = **Jump to real-time** (revelar todo y salir replay) | ⏳ Pendiente 0046 | Spec decidida; código aún no |
| B10 | Exit **X** restaura chart completo (todas las velas visibles) | ✅ Hecho | `restore_after_replay_exit`, `sync_overlay_indicators` |

### 1.2 Select Bar y truncado (comportamiento TradingView)

| # | Pedido Bryan | Estado | Comportamiento esperado |
|---|--------------|--------|-------------------------|
| S1 | Clic en vela N → **N desaparece** del chart | ✅ Hecho | `replay_idx = N-1`; no dibujar índice > `replay_idx` |
| S2 | **N-1** es la última vela visible antes de Play | ✅ Hecho | `replay_confirm_bar_selection` → `_replay_begin(selected-1)` |
| S3 | Al dar Play, **N** es la primera vela que aparece | ✅ Hecho | `step_forward` / `advance_one_tick` desde `replay_idx = N-1` |
| S4 | Ancla ~80%: última visible con hueco ~20% a la derecha | ✅ Hecho | `REPLAY_BAR_ANCHOR_FRAC=0.80`, gap px fijo al zoom |
| S5 | **No** mostrar línea vertical punteada fija en vela ya elegida | ✅ Hecho (`c0e4f5d`) | TV no la muestra; solo hover azul en select mode |
| S6 | Durante replay, línea horizontal de precio sigue la vela **actual** (`replay_idx`) | ✅ Hecho (`47f1a5d`) | Color verde/rojo según open/close de esa vela |
| S7 | Línea de precio correcta aunque el usuario haga pan/zoom durante replay | ✅ Hecho (`47f1a5d`) | `replay_head_candle` en escala, no última visible en pantalla |

### 1.3 Visual selección (modo tijeras)

| # | Pedido Bryan | Estado |
|---|--------------|--------|
| V1 | Línea azul al activar pestaña Replay | ✅ |
| V2 | Tijeras más grandes (`Helvetica 18`) | ✅ (glyph unicode; 0047 vectorial NO hacer) |
| V3 | Velo / etiqueta Re: bajo cursor en select mode | ✅ (`0042`) |

### 1.4 Reglas operativas (Bryan + arquitecto)

- **0048:** etiquetas ASCII en panel; sin mojibake Fedora35.
- **0049:** API Tk Fedora35 (`exists`/`rootx`, `idletasks`, `Tk::bind` sin `+`, `pady` arrayref solo en `pack`).
- **0047:** tijeras vectoriales — **NO tocar** hasta nuevo aviso.
- Antes de “hecho”: `perl -I. -c` + `prove -l t` + smoke `timeout 20 perl -I. market.pl`.

---

## 2. Commits desde `c58cb8a` (cronología completa)

| Commit | Resumen |
|--------|---------|
| `eb513e2` | UX: línea azul al activar, truncado al clic, tijeras 18pt |
| `757b432` | **0045 core:** barra inline, dropdowns, `tick_ms` real |
| `83da0ff` | Fix crash Tk: `-background` widget; Checkbutton `pady` |
| `79373cc` | Dropdowns primer clic: `after(1)` + hermanos + `ReplayDropdown` |
| `eb4757c` | Handoff inicial |
| `1df6337` | Ancla Select Bar 80% |
| `77f80f4` | Gap fijo 20% zoom; play triángulo; exit restaura chart |
| `538016e` | Botones multimedia `ReplayMediaWidget` + Canvas |
| `1f02381` | Iconos visibles (z-order Canvas/Button) — **clics rotos** |
| `c4a1624` | **Fix clics** `Tk::bind`; restaurar texto **Select bar** |
| `c0e4f5d` | Quitar línea punteada vertical en vela confirmada |
| `47f1a5d` | Línea precio en `replay_idx`; sin overscan/futuro en Select Bar |

**Tests:** 1090 (`c58cb8a`) → **1116** (`47f1a5d`).

---

## 3. Estado de tasks 0041–0049

| Task | Estado | Nota arquitecto |
|------|--------|-----------------|
| 0041 | ✅ | Backend speed/interval — estable |
| 0042 | ✅ | Hover azul/velo/Re:; ampliado con sesiones Bryan |
| 0043 | ✅* | *Desviación:* inline, no flotante — **aprobar** |
| 0044 | ✅ | Go-to; hereda `ReplayDropdown` |
| 0045 | ✅* | Core + UX Bryan; **falta verificación visual arquitecto** |
| 0046 | ⏳ | Siguiente: Play/Pause toggle, Jump RT, atajos, marca Replay |
| 0047 | ⏸ | **NO hacer** (tijeras vectoriales) |
| 0048 | ✅ | ASCII panel (`Select bar`, `1x`, `D` + iconos Canvas) |
| 0049 | ✅ | Lecciones Tk ampliadas (ver §7) |

---

## 4. Pendiente de REVISIÓN del arquitecto (no asumir cerrado)

### 4.1 Verificación visual WSLg (obligatoria)

Smoke headless **no sustituye** esto. Checklist:

1. `git pull backup main` (o `origin main`)
2. `perl -I. market.pl` en WSLg
3. Pestaña Replay → línea azul sin clic extra
4. **Select bar** (texto) + **v** (go-to) abren al primer clic
5. Clic vela N → solo hasta N-1 visible; N no asoma; hueco ~20% derecha
6. Play → N aparece; línea horizontal verde/roja coincide con vela actual del replay
7. Pan/zoom durante replay → línea de precio sigue `replay_idx`, no borde de pantalla
8. Exit X → chart completo restaurado
9. Dropdowns `1x`/`D` y velocidades (1x lento vs 5x)
10. Capturas vs `docs/TRADINGVIEW_BAR_REPLAY_REFERENCE.md`

### 4.2 Desviaciones de spec a ratificar

| Tema | Spec original | Realidad Bryan | Acción |
|------|---------------|----------------|--------|
| Panel | Flotante (0043) | Inline en pestaña Replay | Actualizar 0043/0046/docs si se aprueba |
| Botones transporte | Texto Play/Pause (0046) | Iconos Canvas + triángulo | Actualizar 0046 |
| `>>` | Fast-forward +10 | Jump to real-time | Implementar en 0046 |
| Select bar | `✂ Select bar ▾` | `Select bar` + botón `v` separado | Ya 0048; OK |

### 4.3 Arquitectura — mantener estable y modular

**Lo que el arquitecto debe vigilar (pedido implícito de Bryan: “que todo siga estable y modular”):**

| Capa | Módulo | Responsabilidad | No mezclar con |
|------|--------|-----------------|--------------|
| Índice-tope | `ReplayController` | `replay_idx`, play/pause/step, `tick_ms`, `effective_end` | UI Tk, dibujo |
| Ventana/truncado | `ChartEngine::compute_window` | `end <= replay_idx`; overscan sin futuro en replay | Callbacks UI |
| Dibujo replay | `ChartEngine::render` | `replay_head_candle`, `replay_max_index`, anchor shift | Lógica menús |
| Panel UI | `ReplayPanel` + menús | Botones, `ReplayMediaWidget`, dropdowns | Truncado datos |
| Base dropdown | `ReplayDropdown` | place/toggle/`after(1)` click-fuera | Lógica goto/speed |
| Callbacks | `Callbacks.pm` | Factorías, `_replay_begin`, play `after` | Render directo |
| Precio último | `PricePanel` | `render_last_visible_price`; respeta `replay_head_candle` | `ReplayController` |

**Deuda técnica aceptable (no romper en 0046):**

- `ReplayMediaWidget` en el mismo archivo que `ReplayPanel` — OK si no crece más; factorizar solo si 0046 añade mucho.
- `replay_view_anchor` fuerza `ctrl_zoom_x_shift` cada render — revisar si pan manual durante replay debe desactivar anchor (Bryan no lo pidió aún).
- Crosshair se limpia al `_replay_begin`; si el cursor vuelve al chart durante replay, crosshair gris puede coexistir con línea de precio verde/roja — validar vs TV.

**Anti-patrones prohibidos:**

- Duplicar lógica de truncado fuera de `ReplayController` + `compute_window`.
- `bind()` Perl/Tk genérico en Canvas Fedora35 sin `Tk::bind` (regresión clics).
- Overscan `end+1` durante replay activo (fuga visual de barra seleccionada).
- `-background => $widget` en modo inline.

### 4.4 Tests añadidos en última sesión

- `t/25-replay-select-bar.t`: línea precio `replay_idx`, sin dibujar velas futuras (+3 tests).
- `t/17-ui-wiring.t`: `Select bar` en etiquetas esperadas; 6 iconos Canvas.

---

## 5. Lecciones Tk Fedora35 (0049 ampliado)

| # | Síntoma | Causa | Fix |
|---|---------|-------|-----|
| 1–4 | (originales 0044) | pady, winfo_, idletasks, bind `+` | Ver `tasks/0049-*.md` |
| 5 | `unknown color name ".frame..."` | `-background => $widget` | `cget('-background')` |
| 6 | `bad screen distance "4 4"` | `pady` en constructor Checkbutton | `pady` en `pack` |
| 7 | Dropdown multi-clic | bind sincrónico click-fuera | `after(1)` |
| 8 | Menús hermanos | sin cerrar al abrir otro | `hide_menus` + toggle |
| 9 | Iconos visibles pero **clics muertos** | Canvas encima + `->bind` | `Tk::bind` en todos los widgets del botón |
| 10 | Button encima tapa iconos | z-order | Hit debajo + `Tk::bind` en Canvas (no solo `-command` del Button) |

---

## 6. Archivos principales (mapa post-sesión)

| Archivo | Rol |
|---------|-----|
| `Market/ReplayController.pm` | Índice-tope, velocidad, intervalo, ticks |
| `Market/ChartEngine.pm` | Ventana, anchor 80%, render replay, select hover |
| `Market/Panels/PricePanel.pm` | Velas, `replay_head_candle`, línea precio |
| `Market/Panels/ATRPanel.pm` | ATR, `replay_head_value` |
| `Market/UI/ReplayPanel.pm` | Barra inline, botones multimedia |
| `Market/UI/ReplayDropdown.pm` | Base dropdowns |
| `Market/UI/ReplayGotoMenu.pm` | Go-to |
| `Market/UI/ReplaySpeedMenu.pm` | 9 velocidades |
| `Market/UI/ReplayIntervalMenu.pm` | Intervalo + Auto |
| `Market/UI/Callbacks.pm` | Cableado replay, play/pause, truncado |
| `market.pl` | Pestaña Replay |
| `docs/TRADINGVIEW_BAR_REPLAY_REFERENCE.md` | Spec UX referencia |
| `t/25-replay-select-bar.t`, `t/26-replay-dropdown.t`, `t/17-ui-wiring.t` | Regresiones |

---

## 7. Próximo trabajo: 0046 (cuando arquitecto apruebe)

Según `tasks/0046-replay-toggle-jump-shortcuts.md`, adaptado a UI actual:

1. Toggle **Play ↔ Pause** en botón triángulo (mismo widget).
2. **`>>` → Jump to real-time** (`make_replay_jump_real` o equivalente).
3. Atajos `Shift+↓` (toggle), `Shift+→` (step fwd); **no pisar** Shift+←/→ de Select Bar.
4. Marca de agua “Replay” en canvas (gris, centrada).
5. Tests + WSLg obligatorio.

**NO hacer:** 0047 tijeras vectoriales; refactors grandes fuera del lote Replay.

---

## 8. Verificación reproducible

```bash
perl -I. -c market.pl
perl -I. -c Market/ChartEngine.pm
perl -I. -c Market/UI/ReplayPanel.pm
perl -I. -c Market/UI/Callbacks.pm
prove -l t
timeout 20 perl -I. market.pl   # smoke; WSLg visual aparte
```

---

## 9. Prompt corto para el agente arquitecto

Copiar y pegar:

```
Eres el arquitecto del proyecto ProyectoIAAA (Perl/Tk, WSL Fedora35).
Lee docs/HANDOFF_ARQUITECTO_2026-07-05.md (HEAD 47f1a5d, 1116 tests PASS).

Bryan pidió calque Bar Replay TradingView en pestaña Replay inline. El implementor cerró 0045 + fixes UX:
Select bar texto, clics Tk::bind, sin línea punteada en vela confirmada, línea precio en replay_idx.

Tu trabajo:
1) Revisar el handoff: ratificar qué debe QUEDAR (§1) vs pendiente (§4–§7).
2) Verificar arquitectura modular (§4.3): ReplayController / ChartEngine / ReplayPanel / ReplayDropdown sin mezclar responsabilidades.
3) Aprobar desviaciones de spec (panel inline, iconos Canvas, >> = jump RT pendiente 0046).
4) Ejecutar checklist visual WSLg (§4.1) o delegar a Bryan con criterios de aceptación claros.
5) Si 0045 OK → actualizar tasks/README y autorizar implementación 0046 según §7.
6) NO autorizar 0047 (tijeras vectoriales).

Salida esperada: dictamen breve (APROBADO / CORRECCIONES), lista de tasks actualizada, y prompt de implementación para 0046 si procede.
Reglas: 0048 ASCII, 0049 Tk Fedora35, prove -l t verde antes de cerrar cualquier task.
```

---

*Actualizado: 2026-07-05, implementor (rol arquitecto temporal). Base `c58cb8a` → `47f1a5d`.*