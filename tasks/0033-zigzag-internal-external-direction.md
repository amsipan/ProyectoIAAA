# Task 0033: Dirección del precio interna/externa vía ZigZag (enfoque del profe)

## Origen
- Correo + video del profe (03/07). Reemplaza el enfoque de "corregir el
  etiquetado HH/HL/LL/LH" que se venía trabajando.
- Material: `docs/material_profesor/Direccion-del-precio-interna-externa_video.txt`
  (guion del video), `Indicador-zigzag-para-direccion-interna-externa.pdf` (del
  profe, PENDIENTE de pasar a texto: este modelo no lee PDF).
- Source codes de referencia (guardados):
  * `docs/material_profesor/ZigZag_MTF_Fibonacci_reference.pine` (LonesomeTheBlue,
    "ZigZag Multi Time Frame with Fibonacci Retracement").
  * `docs/material_profesor/ZigZag_VolumeProfile_ChartPrime_reference.pine`
    (ChartPrime, "ZigZag Volume Profile").

## Problema que resuelve
Las etiquetas HH/HL/LL/LH en 1m generan mucho RUIDO (movimiento oscilatorio) que
degrada el entrenamiento de los modelos predictivos. Corregir el etiquetado
directamente es subjetivo (depende del rango elegido). El profe propone una
solución MÁS ROBUSTA Y OBJETIVA: dos indicadores ZigZag que dan la dirección
INTERNA y EXTERNA del precio de forma consistente.

## El enfoque (según el video del profe)
Dos ZigZag simultáneos, cada uno da una "dirección":

1. **Dirección INTERNA** — ZigZag Multi Time Frame (indicador 1):
   - Se configura con una temporalidad MAYOR a la del gráfico (el profe usa
     **30 minutos** viendo un gráfico de 1m; 15m da más ruido, 30m más limpio).
   - Config del profe: SOLO "Show Zig Zag" habilitado; resto deshabilitado.
   - Da la perspectiva interna: cuándo cambia el precio en temporalidad media.
   - Color verde (subida) / rojo (bajada) en la referencia.

2. **Dirección EXTERNA** — ZigZag Volume Profile (indicador 2):
   - Usa volumen + ATR(200) para una visión de MÁS LARGO PLAZO.
   - Config del profe: deshabilitar los displays (volume profile, POC, etc.),
     dejar solo la config numérica básica → se ve solo el segmento ZigZag azul.
   - Reacciona más lento; da la tendencia externa.

3. **Comportamiento clave (replay)**: el ZigZag NO pinta un segmento por vela.
   Espera a que el movimiento se CONSOLIDE. Solo el ÚLTIMO segmento se va
   ajustando con el precio; los segmentos anteriores quedan fijos (consolidados)
   y ya no cambian. Hay que reproducir ese comportamiento en nuestro Replay.

4. **Uso combinado (señal de calidad)**: 4 combinaciones de las 2 direcciones.
   - Ambas MISMA dirección (ambas arriba / ambas abajo) → alta probabilidad
     (información consistente/validada).
   - Direcciones opuestas (una arriba, otra abajo) → divergencia = ruido =
     baja probabilidad (típico en rangos laterales).

## Algoritmos de referencia (resumen de los .pine)

### ZigZag MTF (indicador 1 — dirección interna)
- `tf` = resolución del zigzag (input, p.ej. 30m); `prd` = período (default 2).
- Detecta pivote alto (`ph`) / bajo (`pl`) usando `highestbars/lowestbars` sobre
  una ventana `len` que depende del cambio de barra del TF elegido (`newbar`).
- `dir` = +1 tras un ph, -1 tras un pl.
- Array `zigzag` [precio, barindex, ...]: al cambiar `dir` se AÑADE un vértice
  nuevo (`add_to_zigzag`); si NO cambia, se ACTUALIZA el último (`update_zigzag`)
  solo si el nuevo extremo supera al vértice actual. → Esto es exactamente el
  "solo el último segmento se ajusta" del video.

### ZigZag Volume Profile (indicador 2 — dirección externa)
- `atrRange = ta.atr(200) * channelWidthFactor`.
- `swingHigh = ta.highest(swingLength)`, `swingLow = ta.lowest(swingLength)`
  (default swingLength=150).
- `isBullish` cambia cuando el precio marca nuevo highest (true) o lowest (false).
- Al cambiar `isBullish` se cierra el segmento zigzag y se abre uno nuevo; el
  último segmento se ajusta con `set_xy2`. Para NUESTRO uso solo interesa la
  línea zigzag (dirección externa), NO el volume profile/POC/canal.

## Diseño propuesto (a implementar, previa confirmación de detalles)
- Nuevo indicador `Market/Indicators/ZigZag.pm` (cálculo puro) que produzca:
  * Segmento interno (MTF, resolución configurable, default 30m) con dirección.
  * Segmento externo (volumen+ATR200, swingLength configurable) con dirección.
  * Estado "consolidado vs último segmento en ajuste" para el replay.
- Nuevo overlay `Market/Overlays/ZigZag.pm`: dibuja los 2 zigzag (interno
  verde/rojo, externo azul) como líneas; solo el último segmento se redibuja.
- Exponer la DIRECCIÓN interna/externa (+1/-1) como salida para alimentar el
  futuro modelo (Fase 3) y, opcionalmente, una señal de convergencia.
- Integrar en ChartEngine + capa/toggle en la UI (nueva pestaña o dentro de una
  existente).
- DECIDIR con el usuario/profe: ¿este ZigZag REEMPLAZA las etiquetas HH/HL/LL/LH
  del Mxwll/SMC, o CONVIVE con ellas? El profe dice "en lugar de atascarse con
  el etiquetado" → probablemente el ZigZag es la nueva fuente de dirección, pero
  las etiquetas pueden quedar como capa opcional.

## Criterios de aceptación
- Dos ZigZag (interno MTF + externo volumen/ATR) calculados de forma determinista.
- El último segmento se ajusta con el precio; los anteriores quedan consolidados
  (verificable en replay, reproduciendo el video del profe sobre el 29/jun).
- Dirección interna/externa expuesta como +1/-1 por vela.
- Toggle en UI; no rompe overlays existentes ni Fase 1.
- Tests con `IndicatorSnapshot` + verificación analítica sobre Data/2026_06_29.csv.

## Pendiente / bloqueante
- Pasar a texto el PDF `Indicador-zigzag-para-direccion-interna-externa.pdf`
  (puede tener parámetros/definiciones que el video no detalla).
- Confirmar: ¿reemplaza o convive con HH/HL/LL/LH?
- Confirmar resolución interna default (30m) y swingLength externo.

## Qué no tocar
- No borrar el etiquetado HH/HL/LL/LH existente hasta decidir reemplazo/convivencia.
- No portar el Volume Profile/POC del indicador 2 (el profe lo deshabilita); solo
  la línea zigzag externa.
