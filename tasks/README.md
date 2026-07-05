# Tasks

Una task convierte (parte de) una spec en trabajo concreto y verificable. Son pequeñas y
pensadas para que un modelo implementor (más barato) las ejecute una a una sin ambigüedad.

## Reglas duras para el implementor (Fase 2)

1. **Verificación por debug obligatoria.** Cada task de indicador/overlay (0005–0012) debe traer un
   test `.t` que compruebe su salida con `Market/Debug/IndicatorSnapshot.pm` contra un esperado
   transcrito en la task. Ver `docs/PHASE2_DEBUG_CONTRACT.md`. "Validación visual" NO cuenta como
   única prueba.
2. **`Market/Debug/` es intocable.** No crear ni modificar nada ahí. Si falta un campo, reportarlo
   al arquitecto.
3. **`prove -l t` debe pasar completo** tras cada task (no solo el archivo nuevo).
4. **No tocar `MarketData.pm` ni `Data/2026_03.csv`** sin autorización humana.

## Cómo usar (para el implementor)
1. Toma la siguiente task no completada en orden de `Orden de ejecución`.
2. Lee la spec enlazada y el material del profesor que cite.
3. Implementa SOLO lo de esa task; respeta "Qué no tocar".
4. Corre los "Comandos de verificación".
5. Marca la task como hecha (checkbox) y pasa a la siguiente.

## Orden de ejecución recomendado

### Cierre Fase 1 — antes de Fase 2

Resolver primero estas tasks visuales. `0000` dejó aceptada la etiqueta del crosshair (`Thu 23 Apr '26`), pero el criterio de grid equidistante quedó reemplazado por `0000b`: TradingView prioriza fronteras reales de reloj/calendario.

| # | Task | Spec | Depende de |
|---|------|------|-----------|
| 0000 | Pulido Fase 1: etiqueta TradingView del crosshair + grid temporal equidistante (parcial; crosshair OK) | 0000 | — |
| 0000b | Eje temporal inferior TradingView por fronteras reales | 0000b | 0000 |
| 0000c | Pulido post-0000b: ticks 90m en gaps, crosshair con hora y paneo suave | 0000c | 0000b |
| 0000d | Regresiones visuales post-0000c: crosshair en eje temporal y control de ticks/grid en gaps | 0000d | 0000c |
| 0000e | Coherencia lógica del eje temporal: índices reales y crosshair alineado | 0000e | 0000d |
| 0000f | Tickmarks ponderados tipo TradingView/Supercharts: días como anchors, formato intradía y cadencias visuales 1m (implementado, pero visualmente insuficiente) | 0000f | 0000e |
| 0000g | Cadencia global uniforme del eje temporal tipo TradingView: Modo A obligatorio con días + horas uniformes; no aceptar modo diario como cierre final | 0000g | 0000f |

### 1ª entrega Fase 2 — 29/06

Los habilitadores van primero porque el resto depende de ellos.

| # | Task | Spec | Depende de |
|---|------|------|-----------|
| 0001 | Temporalidades extendidas en MarketData | 0001 | 0000g |
| 0002 | ReplayController + índice-tope | 0002 | — (**arrancable ya**) |
| 0003 | Patrón base de Overlays + registro | 0003 | — (**arrancable ya**) |
| 0004 | UI: menú de timeframe + controles Replay + toggles | 0010 | 0001,0002,0003 |
| 0005 | Indicators/SMC_Structures: zigzag FSM + HH/HL/LL/LH | 0004 | 0001 |
| 0006 | SMC: BOS/CHoCH (verdadero/falso) + major high/low | 0004 | 0005 |
| 0007 | SMC: FVG con mitigación + Fibonacci | 0004 | 0005 |
| 0008 | Overlays/SMC_Structures: render de estructura | 0004 | 0003,0006,0007 |
| 0009 | Indicators/Liquidity: swings, EQH/EQL, BSL/SSL | 0005 | 0005 |
| 0010 | Liquidity: clasificación Sweep/Grab/Run + FSM 5 estados | 0005 | 0009 |
| 0011 | Liquidity: pesado de volumen multi-TF + 7 zonas | 0005 | 0009,0001 |
| 0012 | Overlays/Liquidity: render Tabla 2 + toggles | 0005 | 0003,0010 |
| 0019 | Regresiones visuales beta: overlays SMC/Liquidez con coordenadas locales y Replay | 0004/0005/0010 | 0008,0012,0015,0018 |
| 0020 | Anclaje de temporalidades a sesión CME/TradingView | 0001/0000g | 0019 |

(2ª entrega — 13/07: concurrencia 0006, strategy builder 0007, volume profile 0008, VWAP 0009.
Fase 3: HMM/Viterbi 0011, Pearson 0012. Se crearán tasks cuando se aborden.)

### Revisión del profe (29/06) — mejoras Mxwll/Liquidez

`0021` es el documento maestro (backlog + cruce con notas del profe + ORDEN 1-9 ya
implementadas). Las órdenes nuevas 10-19 se detallan una por archivo (0022-0031).

| # | Task | Estado |
|---|------|--------|
| 0021 | Volatilidad + ruido CHoCH (maestro; ORDEN 1-9 hechas) | ✅ ORDEN 1-9 |
| 0022 | Estructura: líneas externas sólidas, internas entrecortadas | ✅ hecho |
| 0023 | FVG vigente solo cerca del precio actual | ✅ hecho |
| 0024 | Grab/Run: solapamiento (apilado vertical) | ✅ hecho |
| 0025 | Colorear velas de liquidity RUN | ✅ hecho |
| 0026 | Etiquetar Order Blocks como "OB" | ✅ hecho |
| 0027 | BSL/SSL más limpio en banda (tarea E) | ✅ hecho |
| 0028 | Strong/Weak High/Low | ✅ hecho |
| 0029 | ML/MH antes del Fibonacci | ✅ verificado ya correcto |
| 0030 | Replay: seleccionar vela de inicio (Select Bar) | ✅ hecho |
| 0031 | El canal (tarea J) | ✅ hecho |
| 0032 | Rediseño barra de controles con pestañas | ✅ hecho |
| 0033 | Dirección precio interna/externa vía ZigZag (NUEVO enfoque profe) | ✅ hecho |
| 0034 | SMC CHoCH/BOS líneas mal dibujadas (a media vela) | ✅ hecho |
| 0035 | Modo Manual de escala fallando | ✅ hecho |
| 0036 | Pulido menor tras lote (validación visual + detalles) | ✅ hecho (A: checklist visual usuario) |
| 0037 | [CRÍTICO] Zoom/Replay deja eje Y corrupto → velas desaparecen | ✅ hecho |
| 0038 | [ALTO] Fuga de futuro en Liquidity Zone 6/7 rompe Replay | ✅ hecho |
| 0039 | [MEDIO] Bugs de render en overlays (SuperTrend flip, whitespace, toggles muertos) | ✅ hecho |
| 0040 | [MEDIO] Estado residual Replay/Select Bar/cambio de TF | ✅ hecho |

### Lote de CORRECCIÓN de bugs (auditoría arquitecto 04/07) — orden para implementor
1. ~~**0037** — CRÍTICO: el zoom deja pantalla en blanco~~ ✅
2. ~~**0038** — ALTO: fuga de futuro en Liquidity~~ ✅
3. ~~**0040** — MEDIO: estado residual de Replay/Select Bar/TF~~ ✅
4. ~~**0039** — MEDIO: bugs de render de overlays~~ ✅

### Orden recomendado para el implementor (lote restante)
1. ~~**0030** — Replay Select Bar~~ ✅
2. ~~**0031** — El canal~~ ✅
3. ~~**0028** — Strong/Weak High/Low~~ ✅
4. ~~**0027** — BSL/SSL en banda~~ ✅
5. ~~**0025** — Colorear velas de liquidity RUN~~ ✅

### Lote CALQUE Bar Replay TradingView (plan `docs/PLAN_REPLAY_TRADINGVIEW.md`)

Objetivo: que el Replay se vea y funcione igual que TradingView. Referencia UX + 5 capturas en
`docs/TRADINGVIEW_BAR_REPLAY_REFERENCE.md`.

| # | Task | Depende | Estado |
|---|------|---------|--------|
| 0041 | Backend velocidad (9 mult.) + intervalo de replay | — | ✅ hecho (verif. arq., 970 tests) |
| 0042 | Modo selección visual: línea azul, `Re:`, velo blanco | — | ✅ hecho (verif. arq. visual; tijeras → 0047) |
| 0043 | Panel flotante media-player (layout TV) | 0041 | ✅ hecho (verif. arq. visual; glyphs → 0048) |
| 0044 | Menú Go-to (Bar/Date/Random/First available) | 0043 | ✅ hecho + 0049 (verif. arq. visual) |
| 0045 | Dropdowns velocidad + intervalo cableados + barra inline | 0041,0043 | ✅ hecho + fixes UX (verif. arq. + visto bueno Bryan; 1116 tests) |
| 0046 | Play/Pause toggle + Jump-to-real-time + marca de agua + botón Mark on/off (atajos → 0050) | 0043 | ✅ hecho + APROBADO (d1c2aa5; visto bueno Bryan; 1134 tests) |
| 0047 | [PULIDO] Tijeras vectoriales (glyph ✂ no renderiza en Fedora35) | 0042 | pendiente (baja prio) |
| 0048 | [ALTO] Panel Replay mojibake: `use utf8` + etiquetas ASCII legibles | 0043 | ✅ hecho (verif. arq. visual; 1042 tests) |
| 0049 | [CRÍTICO] 4 bugs API Tk en 0044 (pady/winfo_/idletasks/bind) | 0044 | ✅ resuelta por arquitecto |
| 0050 | Atajos de teclado oficiales TV (Shift+↓ toggle, Shift+→ step) | 0046 | ✅ hecho + APROBADO arq. (a64e21f; 1153 PASS; precedencia select>replay verificada) |
| 0051 | Atajos extra no-TV: Shift+← step back, Esc salir, M toggle marca de agua | 0046 | ✅ hecho + APROBADO arq. (a64e21f; M ramifica: replay→marca, fuera→escala manual, sin regresión) |
| 0052 | [BUG] Atajos replay no responden en runtime (foco → bind all ventana) | 0050,0051 | ✅ código hecho (bind all $mw + focus canvas; 1170 PASS, Test 20). Falta confirmación de tecla en vivo por Bryan (xdotool no inyecta teclas fiable en WSLg) |
| 0053 | Select Bar: tijera reemplaza cursor cruz, negra Helvetica 22 | 0042 | ✅ hecho + APROBADO arq. (1a4d9df; cursor invisible = XBM fuente+máscara todo-ceros CON hotspot, NO ''/none; verificado por captura + Bryan) |
 
**Orden de ejecución:** 0041 → … → 0046 → **0050 → 0051 → 0052 → 0053** ✅. (0047 pulido, baja prio.)

**Desviaciones de spec APROBADAS por el arquitecto (05/07, con visto bueno visual de Bryan):**
- **Panel Replay INLINE en pestaña Replay**, no flotante (0043 original). Ratificado: mejor UX, sin
  botón `<< Bar Replay`; al abrir pestaña → modo Select bar inmediato.
- **Botones de transporte con iconos Canvas** (play triángulo, back, fwd, jump, exit) dentro de
  cajita `raised`, en vez de solo texto Play/Pause (0046 original). Sigue cumpliendo 0048 (el texto
  `Select bar`/`1x`/`D` es ASCII; los iconos son dibujo vectorial Canvas, no glyphs de fuente).
- **`>>` = Jump to real-time** (revela todas las velas y vuelve a modo Select Bar, como TV),
  NO fast-forward +10 y NO sale del replay. Distinto del botón Exit X (ese sí sale, `replay_on=0`).
  Implementado en 0046 (commit db19858).
- **Línea azul de Select Bar solo con el cursor DENTRO del chart** (TV): al entrar en Select Bar ya
  no se siembra hover en la última vela; se dibuja solo tras `<Motion>` real. Commit d1c2aa5.
- **Botón `Mark: on/off`** en la barra inline para conmutar la marca de agua "Replay" en caliente
  (pedido de Bryan). Default ON.
- Clics resueltos con `Tk::bind` en TODOS los widgets del botón (frame/canvas/label/hit), no solo
  `-command` del Button (lección Tk #9/#10, ver handoff §5).

**Arquitectura verificada modular (05/07):** `ReplayController` (índice-tope, sin Tk) /
`ChartEngine` (ventana+render replay) / `ReplayPanel`+`ReplayMediaWidget` (UI) /
`ReplayDropdown` (base) con `ReplayGotoMenu`/`ReplaySpeedMenu`/`ReplayIntervalMenu` heredando de
ella / `Callbacks` (cableado). Sin regresiones API Tk 0049 (grep limpio).

**Criterio fijado por 0048:** etiquetas ASCII legibles (no glyphs unicode que la fuente de
Fedora35 no tiene). 0044/0045 deben seguir el mismo criterio en sus menús/dropdowns.

**Lección 0049 (API Tk Fedora35 — CRÍTICA para todo el que toque GUI):**
- Pad asimétrico = arrayref `[top,bottom]`, NUNCA `(top,bottom)` (se aplana y rompe). Además,
  `-pady` va en `pack(...)`, NO en el constructor de Checkbutton (`bad screen distance "4 4"`).
- Métodos SIN prefijo `winfo_`: `exists`/`rootx`/`rooty`/`width`/`height`/`containing`/`pointerx`/`pointery`.
- `idletasks` (no `update_idletasks`); `waitWindow` (no `wait`).
- `bind` sin modo `'+'`: `$w->Tk::bind($seq,$cb)`; desbindear con `$w->Tk::bind($seq,'')`.
- `-background => $color` (string). NUNCA `-background => $widget`; para heredar color usar
  `$w->cget('-background')` y descartar refs/`Tk::`/`.` (`unknown color name ".frame..."`).
- Dropdown que se auto-cierra al abrir: instalar el bind de click-fuera DIFERIDO con `after(1)`,
  no síncrono; cerrar hermanos al abrir uno (`hide_menus` + `toggle`).
- Botón con icono Canvas: los clics mueren si el Canvas tapa al Button. Poner `Tk::bind` en TODOS
  los widgets del botón (frame + canvas + label + hit), no confiar solo en `-command` del Button.
- **Cursor invisible (0053):** en Fedora35/WSLg (Tk 804.036) `none`/`blank` NO existen y `-cursor => ''`
  deja el cursor `undef` → WSLg muestra una flecha fantasma. Lo ÚNICO que oculta el puntero: cursor
  XBM fuente+máscara todo-ceros **CON hotspot** (`#define *_x_hot 0` / `*_y_hot 0`; sin hotspot da
  `bad hot spot in bitmap file`). Spec como arrayref `['@'.$src, $mask, 'black', 'black']` pasado tal
  cual a `configure(-cursor=>...)`. Assets: `assets/blank_cursor.xbm` + `assets/blank_cursor_mask.xbm`.
- **Atajos de teclado que dependen del foco (0052):** bindear en un canvas solo funciona si ese canvas
  tiene el foco (se lo da `<Enter>`). Para atajos globales de un modo (replay), usar `$mw->bind(all =>
  $seq, $cb)` con guard por estado, NO solo el canvas. Evitar doble disparo: si un `$seq` está en
  `all`, no lo dupliques en el canvas (o hazlos mutuamente excluyentes por estado, como `<Key-m>`).
- **Automatización de input NO es fiable en WSLg:** `xdotool key/click` sintético a menudo NO llega a
  Tk (`XGetInputFocus returned focused window of 1`). La captura visual (`import -window`) SÍ sirve
  para verificar RENDER, pero la verificación de ATAJOS de teclado la hace el usuario en vivo.
- `perl -c` y mocks NO detectan nada de esto. Toda task GUI debe smoke-abrir `perl -I. market.pl` Y
  verificar que los widgets bajo demanda (menús/diálogos/botones) REALMENTE responden. Ver
  `scratch/probe_*.pl` y el handoff §5 (tabla de 10 síntomas Tk Fedora35).

Fuera de alcance de este lote (mejora futura): sesión Continue/Start new, multi-chart sync,
Replay Trading (P&L), calendario gráfico completo en Select date.

## Plantilla

```
# Task: [nombre]

## Spec relacionada

## Objetivo

## Archivos probablemente relevantes

## Pasos

## Criterios de aceptación

## Comandos de verificación

## Qué no tocar
```

## Comando de verificación base

Cada task debe ejecutar su comando específico de `perl -I. -c` y, además, la suite de regresión del repo:

```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && prove -l t"
```

Si estás trabajando directamente sobre la copia Windows desde WSL, usa:

```bash
wsl -d Fedora35 -- bash -lc "cd /mnt/c/m/ia/proyecto_iaaa/Proyecto/ProyectoIAAA && prove -l t"
```

Comando de sintaxis Perl para archivos puntuales:

```bash
wsl -d Fedora35 -- bash -lc "cd '<ruta del repo en Fedora35>' && perl -I. -c <archivo.pm>"
```

La ruta en Fedora35 es `~/Documents/ProyectoIA/ProyectoIAAA` (mantener sync con `git pull` o sincronización manual).
