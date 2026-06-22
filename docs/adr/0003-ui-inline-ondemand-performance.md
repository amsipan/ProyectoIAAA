# ADR 0003: UI inline, alimentacion bajo demanda y rendimiento de overlays (Fase 2)

- Estado: Aceptado.
- Fecha: 2026-06-22.
- Contexto de fase: cierre funcional de la 1a entrega de Fase 2 y primeras validaciones
  visuales reales de la app con el dataset completo (29888 velas).

## Contexto

Tras implementar la 1a entrega (temporalidades, Replay, overlays SMC/Liquidez, UI), la primera
ejecucion real con el CSV completo revelo problemas que los tests (datasets de 10-35 velas) no
detectaban: la app se colgaba al abrir, la barra de controles se saturaba y los menus nativos
abrian ventanas X erraticas bajo WSLg. Estas decisiones resuelven esos problemas de raiz.

## Decisiones

### D1. Rendimiento de indicadores: O(1) amortizado por vela
- Problema: `Liquidity::_sum_volume_for_tf` escaneaba el array completo del TF parseando
  `Time::Moment` por vela en cada evento (O(eventos x velas)); `_active_levels` y `_fvgs` crecian
  sin podar (O(n^2)). Arranque ~48s con la GUI congelada.
- Decision: cache de epochs por TF + prefix-sum de volumen + busqueda binaria del rango
  (Liquidity, task 0016); poda de niveles `Resolved` y de FVGs inactivos (tasks 0016/0017).
- Resultado: Liquidity 272s -> 5.8s, SMC 37.6s -> 2.9s. Semantica identica (tests intactos).

### D2. Alimentacion de indicadores BAJO DEMANDA
- Problema: los indicadores pesados se alimentaban en el primer render aunque su capa
  estuviera apagada -> arranque lento y grafico saturado.
- Decision: `ChartEngine::sync_overlay_indicators` solo alimenta un indicador si su overlay
  esta visible. Si no hay overlay registrado (tests t/16), alimenta igual (preserva el test).
  Los overlays nacen OFF por defecto.
- Consecuencia: arranque instantaneo (solo velas+ATR como Fase 1); el costo de SMC/Liquidez
  se paga al activar la capa, una vez (cursor cacheado).

### D3. UI INLINE, sin menubar ni Optionmenu
- Problema: el menubar nativo (`$mw->Menu(-type=>menubar)`) y el `Optionmenu` abren ventanas
  X toplevel; bajo WSLg aparecen en posiciones erraticas, se traban o no cargan.
- Decision: todos los controles van inline en la ventana, en filas, con widgets que NO crean
  ventanas: `Radiobutton` (TF y escala, estilo boton con `-indicatoron=>0`), `Checkbutton`
  (capas), `Button` (Replay/Reset). Las acciones se construyen con factorias puras de
  `Market::UI::Callbacks` (testeables headless).
- Consecuencia: cero popups; controles siempre accesibles (recuperacion garantizada).

### D4. Overlays: tope de recencia
- Problema: en vistas amplias (mensual) el rango visible abarca cientos de velas; dibujar
  todos los pivotes/niveles/eventos amontona etiquetas ilegibles (medido: 4291 pivotes, 6106
  niveles).
- Decision: los overlays muestran solo la estructura RECIENTE (los N items de mayor indice
  por familia: SMC 14/10/8, Liquidez 12/10), como TradingView SMC.
- Consecuencia: vista legible en cualquier zoom; al hacer zoom-in se ven los de esa zona.

### D5. Toggles: pasar el valor de la -variable explicito
- Problema: Tk no pasa el valor de `-variable` al `-command` de un Checkbutton; el callback
  recibia `undef` -> siempre "off" -> reactivar una capa no restauraba sus lineas.
- Decision: `market.pl` siempre llama `$cb->($var ? 1 : 0)`. Las factorias de Callbacks
  esperan el bool explicito (contrato verificado en t/17/t/18).

### D6. Paneo: clamp de start_idx solo en Replay
- Problema: el clamp `start_idx = 0` (anadido para Replay) se aplicaba siempre y encogia la
  ventana al panear a la izquierda -> efecto "zoom" en vez de espacio vacio (regresion Fase 1).
- Decision: el clamp solo aplica con Replay activo. En modo normal `start_idx` puede ser
  negativo (espacio a la izquierda de la 1a vela, simetrico al de la derecha). Al tocar el tope,
  `ctrl_zoom_x_shift` se anula para evitar el temblor sub-vela.

## Alternativas descartadas

- Mantener el menubar y "arreglar" su posicionamiento: el problema es de WSLg con toplevels, no
  configurable de forma fiable. Inline es robusto.
- Cargar la app con todo precomputado en background con hilos: Perl/Tk es single-thread; la
  alimentacion bajo demanda da el mismo efecto (arranque rapido) sin complejidad de hilos.
- Mostrar todos los overlays con anti-solapamiento de etiquetas: mas complejo y aun saturaria
  con cientos de lineas; el tope de recencia es lo que hace TradingView.

## Consecuencias

- Positivas: arranque instantaneo, UI estable sin popups, vista legible, paneo de Fase 1
  restaurado, 672 tests verdes.
- A vigilar: el tope de recencia es un valor de criterio visual (ajustable). `ChartEngine`
  sigue siendo un god object; la deuda se mantiene en TECH_DEBT.
