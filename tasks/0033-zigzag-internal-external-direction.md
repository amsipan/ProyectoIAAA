# Task 0033: Dirección del precio interna/externa vía ZigZag (enfoque del profe)

## Origen
- Correo + video + PDF del profe (03/07). Reemplaza el enfoque de "corregir el
  etiquetado HH/HL/LL/LH" que se venía trabajando.
- Material (todo guardado en `docs/material_profesor/`):
  * `Direccion-del-precio-interna-externa_video.txt` — guion del video.
  * `Direccion-del-precio-interna-externa_PDF.txt` — texto extraído del PDF oficial.
  * `imagenes/zigzag_concepto_htf_ltf.png` — negro=HTF (limpio) vs rojo=LTF (ruido).
  * `imagenes/zigzag_config_zzmtf.png` — config exacta del indicador interno.
  * `imagenes/zigzag_config_volumeprofile.png` — config exacta del indicador externo.
  * `imagenes/zigzag_resultado_replay.png` — RESULTADO OBJETIVO (1m con ambos zigzag).
  * `ZigZag_MTF_Fibonacci_reference.pine` (LonesomeTheBlue).
  * `ZigZag_VolumeProfile_ChartPrime_reference.pine` (ChartPrime).

## DECISIÓN DE ALCANCE (confirmada por Bryan, 04/07)
El ZigZag CONVIVE con las etiquetas HH/HL/LL/LH y con SMC/Mxwll existentes; NO
reemplaza nada por ahora. Va como capa/módulo SEPARADO. Todo lo actual se mantiene
hasta confirmar con el profe qué quiere hacer finalmente. Lo IMPORTANTE es que la
visualización quede TAL CUAL la describen el video y el PDF (ver imagen
`zigzag_resultado_replay.png`).

## PARÁMETROS EXACTOS (confirmados de las capturas del PDF)
### Indicador interno — ZZMTF (config `zigzag_config_zzmtf.png`):
- ZigZag Resolution = **30 min** (configurable: 15/30/60).
- ZigZag Period = **2**.
- SOLO "Show Zig Zag" HABILITADO. Fibonacci Ratios OFF, Colorful OFF, todos los
  Enable Level (0.236/0.382/0.5/0.618/0.786) OFF.
- Zigzag Line Colors: verde (subida) / rojo (bajada).
### Indicador externo — ZigZag Volume Profile (config `zigzag_config_volumeprofile.png`):
- Amount of Profiles = 15.
- Swing Channel Display = OFF; Length = **150**; Width = **1**.
- VolumeProfile Display = OFF; Bins = 10; Bins Width = 5.
- POC Display = OFF.
- → Con todo OFF, solo se ve la LÍNEA zigzag azul (dirección externa).

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

## Desbloqueado (04/07)
- PDF ya extraído (texto + imágenes en `docs/material_profesor/`).
- Alcance decidido: CONVIVE, capa separada, no reemplaza nada.
- Parámetros default confirmados: interno ZZMTF 30m period 2; externo Length 150
  Width 1.

## Sub-pasos de implementación sugeridos
1. `Market/Indicators/ZigZag.pm`: pivotes MTF (resolución configurable, agregando
   velas 1m a la resolución elegida) → segmentos con dirección interna (+1/-1).
2. Mismo módulo o segundo: zigzag externo por swingLength(150) + ATR(200), solo
   la línea (dirección externa +1/-1). Reproducir "último segmento se ajusta,
   anteriores consolidados".
3. `Market/Overlays/ZigZag.pm`: dibujar interno (verde/rojo) + externo (azul).
4. ChartEngine: instanciar + feed bajo demanda + reset (patrón de los otros).
5. UI: nueva capa "ZigZag" (checkbox) + sub-toggles interno/externo y selector de
   resolución interna (15/30/60). Integrar en el diseño de pestañas (task 0032).
6. Verificar en Replay que reproduce el comportamiento del video del profe (29/jun).

## Qué no tocar
- No borrar ni modificar el etiquetado HH/HL/LL/LH ni SMC/Mxwll (conviven).
- No portar el Volume Profile/POC del indicador 2 (el profe lo deshabilita); solo
  la línea zigzag externa.
