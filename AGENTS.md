# AGENTS.md — Proyecto Motor de Charting Financiero (Tk/Perl)

> **ESTAMOS EN FASE 2 (indicadores); los modelos se conservan como meta posterior.**
> Antes de escribir código, lee en este orden:
> 1. **`docs/BRUJULA_CONTINUIDAD.md`** — prioridad operativa, checkpoint vivo y prompt de rescate.
> 2. **`docs/MEMORIA_RECUPERADA_019f6e8d.md`** — historia reconstruida de la sesión principal; consultar cuando falte contexto.
> 3. **`docs/PLAN_DEFINITIVO.md`** — meta de dataset/modelos y restricciones causales para la fase posterior.
> 4. `docs/PRODUCTO_OFICIAL.md` — capas que cargan en runtime **hoy**.
> 5. `docs/CONSTITUTION.md` — principios no negociables (cálculo ≠ render, Replay, etc.).
> 6. `docs/AI_CONTEXT.md` / `docs/ARCHITECTURE.md` — contexto y capas técnicas; pueden contener historia desactualizada.
> 7. `docs/material_profesor/Especificacion_Proyeto_2a_Fase.pdf` — requisitos contractuales de Fase 2.
> 8. Spec/task en `specs/` / `tasks/` si aplica (`tasks/README.md`).
>
> **Estado actual (2026-07-19):** Fase 1 cerrada. Producto oficial en
> **`docs/PRODUCTO_OFICIAL.md`**: SMC Pro, Structures+FVG, HLD, Parallel Channel, ZigZag
> ext/int, Fib Retracement y **Liquidity v2 MVP**. Legacy fuera del repo (`docs/LEGACY.md`).
> **Prioridad confirmada por Bryan:** terminar indicadores antes de modelos. Orden actual:
> cerrar Liquidity §4 → concurrencia §5 → DIY §6 → Volume Profile §7 → Anchored VWAP §8 → modelos.
> Si documentación y código divergen, inspecciona Git/código, consulta la brújula, señala la
> contradicción y pregunta; no la resuelvas silenciosamente.
>
> **Flujo de trabajo (SDD):** toma una task de `tasks/` → implementa solo eso → verifica con
> `perl -I. -c` de los archivos tocados + `prove -l t` → no toques nada fuera de "Archivos relevantes"/"Qué no tocar" de la task.
>
> **Entregas Fase 2 (PDF oficial):** 1ª = **29/06**, 2ª = **13/07**. Vale 20/100.

> ⚠️ **GIT DIR SEPARADO DE ONEDRIVE (05/07).** El repo vive en OneDrive, pero `.git` fue
> movido FUERA con `git init --separate-git-dir` para que OneDrive no sincronice los objetos
> de Git (causaba "borrar 999 elementos" y riesgo de corrupción de packfiles).
> - En el working dir, `.git` es un **archivo-puntero** (no carpeta) que contiene:
>   `gitdir: C:/Users/ASUS ROG/.gitdirs/ProyectoIAAA.git`
> - El repo real (objects, refs, historial) vive en **`C:\Users\ASUS ROG\.gitdirs\ProyectoIAAA.git`** (fuera de OneDrive, NO respaldado por OneDrive — el respaldo es GitHub `backup`+`origin`).
> - **NO borrar `C:\Users\ASUS ROG\.gitdirs\`** (perderías el historial local; GitHub lo tiene, pero evita el susto).
> - **Si mueves/renombras la carpeta del proyecto:** el puntero `.git` tiene ruta ABSOLUTA y se
>   rompe. Para arreglarlo, re-ejecutar `git init --separate-git-dir "<nueva ruta .gitdirs>"`
>   desde el working dir, o editar la ruta dentro del archivo `.git`.
> - Git funciona idéntico para todo lo demás (status/commit/push). No cambia ningún flujo.

## Resumen

Aplicación de visualización de datos OHLCV con indicadores técnicos y overlays de estructura
de mercado, construida con Perl/Tk para la asignatura IA y Aprendizaje Automático (EPN, 2026A,
GR1SW). El profesor evaluó Fase 1 con una rúbrica (ver `Rubrica_Proyecto_GUI.xlsx`, hoja
`AA-GR1`, columna `Grupo 2`). Puntaje base: 89/100 (Fase 1).

**Meta del curso (no olvidar):** la app es la **fábrica de observaciones** (estructura +
liquidez + features) para entrenar **t-SNE → GMM → HMM**. Detalle y orden de trabajo:
**`docs/PLAN_DEFINITIVO.md`**.

## Fase 2 — producto oficial (resumen)

- Temporalidades 1m…W; **Replay** sin futuro.
- **Oficial ahora:** SMC Pro, Structures+FVG, HLD, Parallel Channel, ZigZag, Fib Retracement,
  **Liquidity v2**.
- Separación Indicators (cálculo) vs Overlays/Drawing (render).
- Lista runtime: `docs/PRODUCTO_OFICIAL.md`. Dirección del proyecto: `docs/PLAN_DEFINITIVO.md`.

Regla de rendimiento clave (PDF §2): los indicadores de alta complejidad calculan **solo sobre
las velas visibles + una ventana de contexto indexada**, nunca todo el historial por frame.

## Stack

- **Lenguaje:** Perl 5 con Tk para GUI nativa
- **Entorno de ejecución:** WSL Fedora35 (EOL, mirrors en `archives.fedoraproject.org`)
- **Dependencias Perl:** `Time::Moment`, `Tk` (módulos CPAN ya instalados en Fedora35);
  Fase 3: `AI::MXNet`, `Chart::Plotly`
- **Datos:** `Data/2026_03.csv` (~29.888 velas 1m; contenido real abril 2026 UTC-5);
  también `Data/2026_06_29.csv`, `Data/2026_07_06.csv`
- **Control de versiones:** Git, remote `https://github.com/amsipan/ProyectoIAAA`

## Estructura

```
ProyectoIAAA/
  market.pl                  # Entrada, UI Tk por pestañas, controles
  Market/
    MarketData.pm            # Datos: OHLCV, timeframes, slicing
    ChartEngine.pm           # Orquestador: render, zoom, crosshair, drag, replay, overlays
    IndicatorManager.pm      # Gestor de indicadores base
    ReplayController.pm      # Índice-tope Replay, velocidades, intervalos
    OverlayManager.pm        # Registro de overlays
    Indicators/              # CÁLCULO (sin Tk) — solo producto oficial
      ATR.pm  SMC_Pro.pm  SMC_Structures_FVG.pm  HLD.pm  ZigZag.pm  Liquidity.pm
    Overlays/                # RENDER
      Base.pm  SMC_Pro.pm  SMC_Structures_FVG.pm  HLD.pm  ZigZag.pm
      ParallelChannel.pm  FibRetracement.pm  Liquidity.pm
    Drawing/
      ParallelChannel.pm  FibRetracement.pm
    Panels/
      PricePanel.pm  ATRPanel.pm  Scales.pm
    UI/
      Callbacks.pm
      ReplayPanel.pm  ReplayDropdown.pm
      ReplayGotoMenu.pm  ReplaySpeedMenu.pm  ReplayIntervalMenu.pm
    Debug/                   # Arquitecto only
      TimeAxisSnapshot.pm  IndicatorSnapshot.pm
  Data/
    2026_03.csv  2026_06_29.csv  2026_07_06.csv
  assets/                    # blank_cursor XBM (Select Bar)
  docs/                      # SDD (LEER PRIMERO)
    reference_indicators/    # Pine/TV source code canónico (consultar para portar)
  specs/  tasks/  t/  scratch/
  Rubrica_Proyecto_GUI.xlsx  # NO BORRAR
  PDF_BASE_EXTRACTED.txt     # NO BORRAR
  AGENTS.md                  # Este archivo
```

## Cómo ejecutar y validar

### Sistema de debug (CERRADO al implementor)

`Market/Debug/` es propiedad del arquitecto. El agente implementor **NO crea ni modifica** nada
bajo `Market/Debug/`. Si un test necesita un campo que el snapshot no expone, el implementor lo
**reporta**; el arquitecto extiende el módulo.

- Eje temporal: `Market/Debug/TimeAxisSnapshot.pm` (Fase 1, `0000g`–`0000j`).
- Indicadores/overlays Fase 2: `Market/Debug/IndicatorSnapshot.pm` (genérico). Contrato y patrón de
  test en `docs/PHASE2_DEBUG_CONTRACT.md`. Self-test: `t/08-indicator-debug-harness.t`.

Regla dura para Fase 2: **cada task de indicador/overlay debe traer un test `.t` que verifique su
salida vía el módulo de debug contra un esperado transcrito.** Sin ese test, la task NO está
terminada. La "validación visual" con WSLg es complementaria, nunca la única prueba.

### Revisión visual de la GUI por el arquitecto (interacción + captura)

El agente **arquitecto** puede verificar visualmente la app: lanzar `market.pl` en WSLg, **navegar
con clicks/teclado** (xdotool), capturar a PNG (ImageMagick `import -window <id>`, NO `root`) y
**leer la imagen**. Herramientas ya instaladas en Fedora35: `ImageMagick`, `xwininfo`, `xdotool`.
Flujo completo, reglas de oro y scripts reutilizables documentados en
**`docs/ARQUITECTO_REVISION_VISUAL.md`**. El **implementor solo procesa texto**: la comparación
"¿se ve como la referencia?" es del arquitecto; el usuario da el visto bueno final.

### Debug del eje temporal contra TradingView

Usar `Market/Debug/TimeAxisSnapshot.pm` vía `ChartEngine::debug_time_axis_snapshot(...)`.
Caso calibrado `0000g`:

```perl
$chart->debug_time_axis_snapshot(
    timeframe    => '15m',
    start_ts     => '2026-04-29T15:00:00-05:00',
    end_ts       => '2026-05-01T00:00:00-05:00',
    canvas_width => 1400,
);
```

Debe producir la secuencia TradingView esperada en `labels_text` con cadencia dominante `90`.

```bash
# Validación de sintaxis (sin GUI) — desde WSL, copia canónica o de trabajo:
wsl -d Fedora35 -- bash -lc "cd /mnt/c/m/ia/proyecto_iaaa/Proyecto/ProyectoIAAA && perl -I. -c Market/ChartEngine.pm && perl -I. -c market.pl"

# Suite de regresión:
wsl -d Fedora35 -- bash -lc "cd /mnt/c/m/ia/proyecto_iaaa/Proyecto/ProyectoIAAA && prove -l t"

# Ejecutar GUI (WSLg):
cd ~/Documents/ProyectoIA/ProyectoIAAA   # o la ruta canónica montada
perl -I. market.pl
```

La copia en Fedora35 (`~/Documents/ProyectoIA/ProyectoIAAA`) debe mantenerse sincronizada con el
working tree canónico / GitHub.

## Decisiones de diseño vigentes (importantes para futuros cambios)

1. **Separación horizontal uniforme:** velas por índice (0,1,2…), no tiempo continuo; gaps no
   crean huecos visuales (como TradingView por defecto).
2. **Eje Y de precio:** padding ~5% sobre min/max de velas visibles (modo auto).
3. **Offset y visible_bars:** offset desde el final (vista más reciente); `compute_window`
   calcula `start/end` globales y respeta tope de Replay.
4. **Coalescing de render:** `request_render()` con `after(20ms)`.
5. **Tema claro:** colores vía `%theme` en `market.pl` → ChartEngine → paneles; defaults con `//`.
6. **ATR:** 14 periodos; se recalcula al cambiar timeframe.
7. **Eje temporal inferior:** fronteras reales de reloj/calendario (TradingView), no grid
   equidistante arbitrario; ver tasks `0000b`–`0000j`.
8. **Cálculo ≠ render:** nunca Tk dentro de `Indicators/`.
9. **Overlays bajo demanda:** no alimentar capas OFF al arrancar.
10. **Replay:** cero fuga de futuro en feed, getters y dibujo.
11. **UI WSLg:** inline; no menubar/Optionmenu; clics con `Tk::bind` en todos los widgets de un
    botón con Canvas; atajos globales con `$mw->bind(all => ...)`; etiquetas ASCII (no glyphs
    rotos en Fedora35).

## Archivos que NO se deben borrar

- `Rubrica_Proyecto_GUI.xlsx` — requisitos oficiales del profesor
- `PDF_BASE_EXTRACTED.txt` — especificaciones extraídas del PDF de Fase 1
- `Data/2026_03.csv` (y CSVs de Data/ en uso) — fuentes de datos
- `docs/material_profesor/` — material original del profesor

## Notas para el futuro

- Fedora35 está EOL; mirrors lentos. Paquetes nuevos: `dnf --releasever=35` +
  `archives.fedoraproject.org`.
- WSLg: `DISPLAY` automático; xdotool a menudo no entrega input a Tk (captura de ventana sí sirve).
- `git diff --check` puede avisar CRLF en `market.pl` — inofensivo Windows↔Linux.
- Suite `t/` con Test::More (sin GUI): `prove -l t`. Contrato de indicadores:
  `docs/PHASE2_DEBUG_CONTRACT.md`.
- Handoffs y lecciones Tk: `docs/HANDOFF_*`, `docs/INFORME_IMPLEMENTOR_*`, `tasks/README.md` §0049.
