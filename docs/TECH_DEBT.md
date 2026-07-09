# Deuda técnica

Clasificada por severidad. No se resuelve aquí; solo se documenta. Última act.: 2026-07-08.

## Crítico

(Sin críticas abiertas. Arranque con capas OFF solo computa velas+ATR; overlays pesados bajo
demanda. Feed de liquidez puede ir por chunks no bloqueantes.)

### [RESUELTO 2026-06-22] Fallos de UI en la primera validación visual — task 0018
- **F1 (toggles no restauraban líneas):** los `-command` de Checkbutton no recibían el valor de su
  `-variable` (Tk no lo pasa). Fix: `market.pl` pasa explícito `$cb->($var ? 1 : 0)`. Verificado en
  `t/18` (OFF→ON restaura los mismos items).
- **F2 (barra saturada, TF/Replay recortados):** ~28 widgets en una sola fila desbordaban el ancho.
  Fix final: rediseño a controles **inline** (luego pestañas en 0032); sin menubar ni Optionmenu
  por problemas de popups bajo WSLg.
- **F3 (arranque pesado):** `market.pl` registraba un SMC extra duplicado + alimentaba indicadores
  con capas apagadas. Fix: SMC extra eliminado; alimentación **bajo demanda** en
  `sync_overlay_indicators` (solo si el overlay está visible). Arranque instantáneo.
- **F4 (demasiadas líneas al abrir):** overlays nacían visibles. Fix: overlays OFF por defecto.
- **F5 (sin recuperación con app en blanco):** Reset Vista y controles críticos siempre accesibles.

### [RESUELTO 2026-06-22] SMC_Structures se colgaba ~37s en el dataset real — task 0017
- **Era:** `_detect_and_mitigate_fvgs` recorría `_fvgs` entero por vela; FVGs inactivos nunca
  se podaban → O(n²).
- **Fix:** poda `_fvgs` a solo activos tras mitigación. 37.6s → 2.9s en feed completo.

### [RESUELTO 2026-06-21] La app se colgaba al abrir con el dataset real — Liquidity, task 0016
- **Era:** `_sum_volume_for_tf` parseaba Time::Moment por vela sobre arrays completos → cuelgue.
- **Fix:** cache de epochs + prefix-sum + búsqueda binaria; poda Resolved. 272s → 5.8s.

### [RESUELTO 2026-06-21] Indicadores se alimentaban hasta el fin del dataset en Replay — task 0015
- **Era:** feed hasta `size()-1` con Replay activo → fuga de futuro.
- **Fix:** tope `replay_idx`; test `t/16` y regresiones posteriores (0038, etc.).

### [RESUELTO 2026-06-21] Pesado de volumen multi-TF — task 0013
- Suma por rango temporal (epoch), no por índice de arrays de distinto TF.

## Alto

### ChartEngine.pm como god object (ABIERTO, mitigado parcialmente)
- **Descripción:** `ChartEngine.pm` (~3300+ líneas) concentra orquestación, render de ejes,
  eventos de mouse/teclado, zoom, drag, cursores, visuals de Replay y feed de overlays.
- **Mitigación ya hecha:** `ReplayController`, `OverlayManager`, paneles UI Replay extraídos.
- **Impacto residual:** feed (`sync_overlay_indicators` y helpers de liquidez) y mucho dibujo
  de Replay siguen en ChartEngine; riesgo de regresiones al tocar UI o overlays.
- **Recomendación:** extraer colaborador de feed/render-loop solo con task/ADR propia; no
  refactor "de paso".
- **¿Bloquea escalabilidad?:** parcialmente (Fase 3 y features nuevas deben evitar meter más
  lógica de dominio aquí).

### [RESUELTO / mitigado] Cadencia del eje temporal TradingView
- Cerrado en tests `t/07` + TimeAxisSnapshot (`0000g`–`0000j`). Comparación visual puntual
  sigue siendo útil si cambia el dataset o el TF de calibración, pero ya no bloquea Fase 2.

### [RESUELTO 2026-06-22] Falta de carpeta/patrón de Overlays
- Patrón `Indicators/` + `Overlays/` + `OverlayManager` en uso para SMC, Liquidez, Strategy,
  VP, VWAP, Mxwll, ZigZag.

## Medio

### Tests de cota por tiempo (0016/0017) flaky bajo contención de CPU
- **Descripción:** `elapsed < N s` en `t/09`/`t/10` puede fallar si la máquina está cargada.
- **Impacto:** bajo. Umbrales holgados ya aplicados.
- **¿Bloquea?:** no.

### Detección SMC — simplificaciones conocidas (parcialmente vigentes)
1. **Mitigación FVG unidireccional** (no bidireccional completa como TradingView/LuxAlgo).
2. ~~get_pivots mutante~~ **RESUELTO 0014.**
3. **`CHoCH_false` sin body-close** (compara close vs nivel, no close vs open) — a vigilar vs profe.
- Densidad de pivotes y FVG near-price se endurecieron en 0056/0059; no confunde con estos puntos.

### Recálculo / feed al cambiar timeframe o activar capas
- **Descripción:** cambio de TF sigue implicando reset/realimentación de indicadores activos;
  capas pesadas mitigan con under-demand y chunks.
- **Impacto:** medio en datasets grandes si se encienden muchas capas a la vez.
- **Recomendación:** no romper el modelo de feed incremental; perfilar antes de "optimizar".

### Concurrencia liquidez→estructura (spec 0006) no implementada como feature de pesos
- **Descripción:** la app une pivotes SMC y liquidez (0055) y calibra densidades, pero no hay
  aún el modelo de **pesos de probabilidad** de la spec 0006.
- **Impacto:** hueco de 2ª entrega conceptual / puente a HMM.
- **Recomendación:** formalizar tasks antes de codificar.

## Bajo

### Debug removible antes de entrega final
- `Market/Debug/*` es diagnóstico, no producto. Mantener en desarrollo; decidir exclusión
  solo si el profe exige árbol estricto.

### Entorno frágil (Fedora35 EOL + parches MXNet)
- Crítico solo al entrar a Fase 3. Ver `docs/SETUP_FEDORA35.md`.

### Lecciones Tk/WSLg (no deuda de diseño, trampas operativas)
- Documentadas en `tasks/README.md` (0049 ampliado) y handoffs: pady arrayref, `Tk::bind`,
  no `-background => $widget`, cursor XBM+hotspot, bind `all` para atajos, ASCII en labels.
- **0053:** ocultar cursor del SO en Select Bar no es fiable en WSLg → pausado.

### CRLF Windows ↔ Linux
- Cosmético en `git diff --check`.

### Proyecto en OneDrive + gitdir separado
- Working tree OneDrive; objects en `C:\Users\ASUS ROG\.gitdirs\ProyectoIAAA.git`.
  No borrar el gitdir. Junction `C:\m\...` puede confundir listados recursivos de archivos
  no hidratados.
