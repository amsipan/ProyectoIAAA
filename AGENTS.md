# AGENTS.md — Proyecto Motor de Charting Financiero (Tk/Perl)

## Resumen

Aplicación de visualización de datos OHLCV con indicador técnico ATR, construida con Perl/Tk para la asignatura IA y Aprendizaje Automático (EPN, 2026A, GR1SW). El profesor evaluó con una rúbrica (ver `Rubrica_Proyecto_GUI.xlsx`, hoja `AA-GR1`, columna `Grupo 2`). Puntaje base: 89/100.

## Stack

- **Lenguaje:** Perl 5 con Tk para GUI nativa
- **Entorno de ejecución:** WSL Fedora35 (EOL, mirrors en `archives.fedoraproject.org`)
- **Dependencias Perl:** `Time::Moment`, `Tk` (módulos CPAN ya instalados en Fedora35)
- **Datos:** `Data/2026_03.csv` — 29,888 velas 1-minuto (marzo 2026)
- **Control de versiones:** Git, remote `https://github.com/amsipan/ProyectoIAAA`

## Estructura

```
ProyectoIAAA/
  market.pl                  # Punto de entrada, UI Tk, controles
  Market/
    MarketData.pm            # Capa de datos: OHLCV, timeframes, slicing
    ChartEngine.pm           # Motor principal: render, zoom, crosshair, drag
    IndicatorManager.pm      # Gestor de indicadores
    Indicators/
      ATR.pm                 # Cálculo del ATR (14 periodos)
    Panels/
      PricePanel.pm          # Render de velas japonesas + crosshair
      ATRPanel.pm            # Render línea ATR + crosshair sincronizado
      Scales.pm              # Conversión coordenadas ↔ valores
  Data/
    2026_03.csv              # Datos OHLCV 1-minuto, ~29888 filas
  Rubrica_Proyecto_GUI.xlsx  # Rúbrica del profesor (NO BORRAR)
  PDF_BASE_EXTRACTED.txt     # Requisitos extraídos del PDF del profesor (NO BORRAR)
  AGENTS.md                  # Este archivo
```

## Cómo ejecutar y validar

```bash
# Validación de sintaxis (sin GUI):
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c Market/ChartEngine.pm && perl -I. -c Market/Panels/PricePanel.pm && perl -I. -c Market/Panels/ATRPanel.pm && perl -I. -c Market/MarketData.pm && perl -I. -c market.pl"

# Ejecutar (desde WSL Fedora35 con WSLg para GUI):
cd ~/Documents/ProyectoIA/ProyectoIAAA
perl -I. market.pl
```

La copia en Fedora35 está en `~/Documents/ProyectoIA/ProyectoIAAA` y debe mantenerse sync con GitHub (`git pull`).

## Cambios principales realizados (commits recientes)

### Zoom y escala temporal (commits 9952bd7 → 1941241)
- **Zoom multiplicativo** (`_wheel_zoom_delta`): factor = 1 + zoom_scale/10. Cerca pasos pequeños, lejos pasos grandes.
- **Ctrl+rueda** ancla la vela bajo el crosshair con shift exacto (`ctrl_zoom_x_shift`).
- **MAX_VISIBLE_BARS = 40000** — límite tipo TradingView (el CSV solo tiene ~29888 velas 1m).
- **Downsample por píxel**: cuando `bar_w < 2`, PricePanel y ATRPanel agrupan datos por píxel (high/low para velas, promedio para ATR).

### Escala de tiempo (Req. 5.6)
- Grid temporal usa **timestamps reales alineados al reloj** (`_is_time_axis_boundary`), no fase arbitraria por zoom.
- Intervalos por escalera según timeframe: 1m → `[1,5,15,60,180,720,1440]`, 5m → `[5,15,60,180,720,1440]`, 15m → `[15,30,60,90,360,720,1440,2880]`.
- En 1m con intervalo 5, solo marca `:00, :05, :10...` nunca `:02, :07`.
- Líneas verticales mantienen separación horizontal uniforme porque cada barra ocupa igual espacio (TradingView-style, no tiempo continuo).

### Timeframes corregidos (MarketData.pm)
- Agrupación 5m/15m por **fronteras reales de reloj** (`_bucket_timestamp`): porciones `:00-:04`, `:05-:09`, no cada N filas consecutivas.

### Crosshair
- X anclada al centro de vela (`_snap_crosshair_x`).
- Label de precio redondeado a `tick_size = 0.25`.
- Label de tiempo respeta `ctrl_zoom_x_shift`.
- Solo cursores nativos Tk/Windows; no se dibuja cursor duplicado en Canvas.

### ATR — Modo manual independiente
- `set_atr_scale_mode('auto'|'manual')` independiente de price scale.
- Eje ATR tiene drag vertical para zoom (igual que price axis).
- Panel ATR tiene paneo vertical por arrastre dentro del canvas (`_apply_atr_vertical_drag_from_start`).
- Teclas en foco ATR: `a`/`m` = auto/manual, `+/-` = zoom vertical, `Up/Down` = desplazar vertical.
- Al cambiar timeframe o reset, ATR vuelve a auto.
- Controles ATR en barra inferior derecha, controles Precio en izquierda, separados visualmente (frames con `relief => 'groove'`).

### UI (market.pl)
- Timeframes como `Radiobutton` con `active_tf` compartido.
- `Precio: Auto/Manual` en caja izquierda, `ATR: Auto/Manual` en caja derecha.
- Callbacks `scale_mode_callback` y `atr_scale_mode_callback` sincronizan estado de botones con motor.

## Decisiones de diseño (importante para futuros cambios)

1. **Separación horizontal uniforme**: Las velas se dibujan con índice (0, 1, 2...), no con coordenada de tiempo real. Esto implica que fines de semana y gaps nocturnos no crean huecos visuales, igual que TradingView por defecto.

2. **Eje Y de precio**: 5% padding sobre min/max de velas visibles.

3. **Offset y visible_bars**: El offset cuenta desde el final (vista más reciente). `compute_window` calcula `start/end` en índices globales.

4. **Coalescing de render**: `request_render()` usa `after(20ms)` para no saturar con renders múltiples.

5. **Tema claro**: Colores inyectados vía `%theme` en `market.pl` → `ChartEngine` → paneles y escalas. Todos los colores usan defaults con `//`.

6. **ATR**: Siempre 14 periodos. Se recalcula completo al cambiar timeframe.

## Archivos que NO se deben borrar

- `Rubrica_Proyecto_GUI.xlsx` — requisitos oficiales del profesor
- `PDF_BASE_EXTRACTED.txt` — especificaciones extraídas del PDF del profesor
- `Data/2026_03.csv` — única fuente de datos

## Notas para el futuro

- Fedora35 está EOL; los mirrors son lentos. Si hay que instalar paquetes nuevos, usar `dnf --releasever=35` con repos `archives.fedoraproject.org`.
- WSLg funciona para GUI; la variable `DISPLAY` se configura automáticamente.
- `git diff --check` puede mostrar warning CRLF en `market.pl` — es inofensivo (Windows ↔ Linux).
- No hay tests automatizados; la validación es visual contra la rúbrica.
- `t/` está vacía pero se conserva por si se añaden tests en el futuro.
- La copia en Fedora35 (`~/Documents/ProyectoIA/ProyectoIAAA`) tiene un stash con el cambio local viejo (`MAX_VISIBLE_BARS = 4000`).