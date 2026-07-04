# Task 0036: Pulido menor tras lote 0025-0031 (baja prioridad)

## Estado
✅ **Hecho** (2026-07-04) — B y C implementados/evaluados; A pendiente confirmación visual del usuario.

## Origen
- Revisión de arquitecto (04/07) tras aprobar 0025/0027/0028/0030/0031. Todo
  quedó funcional y con tests; estos son detalles de pulido, NO bugs bloqueantes.

## Puntos a revisar

### A. Validación visual pendiente (usuario, WSLg)
Los tests cubren cálculo/contrato, pero falta confirmar en pantalla:
1. **0030 Select Bar:** botón "Select Bar" activa modo; click en el chart marca
   la vela; Shift+←/→ la mueve; Play arranca en selected-1. Verificar que el
   marcador vertical se ve y que no interfiere con el crosshair/zoom normal.
2. **0031 Canal:** toggle "Canal" (pestaña ZigZag) dibuja dos líneas paralelas al
   zigzag externo; con OFF no aparece.
3. **0028 S/W:** toggle "S/W" (pestaña Mxwll) muestra Strong/Weak High/Low.
4. **0027 banda:** BSL/SSL como bandas sombreadas; verificar que no tapan velas.
5. **0025 velas RUN:** halo azul en las velas de RUN relevante; verificar en 1m y
   en zoom bajo (downsample) que no molesta.

### B. Consistencia de `bar_w` en el halo de RUN (0025)
`_highlight_run_candle` calcula `bar_w = plot_width/bars`. Confirmar que ese
`bars` coincide con el que usa PricePanel para dibujar las velas (si difieren en
overscan/downsample, el halo podría quedar ligeramente más ancho/estrecho que la
vela). No es un bug funcional, es alineación fina.

### C. Densidad visual con varias capas activas
Con banda BSL/SSL + halos RUN + zigzag + estructura, en 1m puede saturar. Evaluar
si conviene que algunos defaults vengan OFF (hoy band_mode ON, halo siempre en
RUN relevante). Decisión de UX, confirmar con profe/usuario.

## Criterios de aceptación
- Validación visual (A) OK por el usuario; si algo se ve mal, abrir task puntual.
- (B) y (C) evaluadas; ajustar solo si hay problema real.

## Resultado (04/07)

### B — `bar_w` halo RUN
- `_highlight_run_candle` ahora usa `_bar_left_x` / `_bar_right_x` (mismo patrón que
  `SMC_Structures` y `PricePanel` downsample).
- Modo normal: ancho halo = 60% de `bar_w` (igual que cuerpo de vela en PricePanel).
- Modo downsample (`bar_w < 2`): línea gruesa centrada en la columna de píxel.
- Test: `t/15-overlay-liquidity-render.t` (bloque task 0036-B).

### C — densidad visual
- Sin cambio de defaults: `band_mode` sigue ON; halo RUN solo en eventos relevantes.
- Saturación posible en 1m con todas las capas ON — decisión UX para el profe/usuario.

### A — validación visual (usuario, WSLg)
Checklist pendiente de confirmación en pantalla:
1. Select Bar: marcador, Shift+←/→, Play en selected-1.
2. Canal ZigZag ON/OFF.
3. S/W High/Low toggle.
4. BSL/SSL bandas no tapan velas.
5. Halo RUN en 1m y con zoom bajo.

## Prioridad
BAJA. No bloquea. Hacer tras validación visual del usuario.

## Qué no tocar
- No rehacer las 5 tareas ya aprobadas salvo que la validación visual revele un
  fallo concreto (en ese caso, task nueva específica).
