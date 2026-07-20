# Checklist de aceptación de la imagen del profesor

**Fuente:** transcripción exacta proporcionada por Bryan el 20-07-2026 de la imagen que el profesor usa para revisar si el proyecto está completo.  
**Fecha original de la imagen:** no determinada.  
**Uso correcto:** checklist visual/funcional de aceptación. No sustituye silenciosamente el PDF ni parámetros explícitos de audios posteriores.

## Texto exacto proporcionado

> ESTRUCTURA SMC INTERNA / EXTERNA
>
> Niveles de liquidez:
> - OB | Mitigar antiguos
> - FVG | Mitigar antiguos
> - Trend lines / canales
> - EQH / EQL
> - HL D/W Candle
>
> ZONAS DE LIQUIDEZ:
> - Niveles de Fibonacci del ZIGZAG EXTERNO
> - SWEEP / GRAB
> - RUN
>
> ZIGZAG INTERNO / EXTERNO
> Anchored VWAP
> Anchored Volume profile

## Interpretación mínima segura

La imagen exige que el profesor pueda encontrar y comprobar visualmente estos bloques:

1. Estructura SMC interna y externa.
2. Order Blocks y eliminación/mitigación de los antiguos.
3. FVG y eliminación/mitigación de los antiguos.
4. Trend lines o canales.
5. EQH/EQL.
6. High/Low de velas **1D/4H**, conforme a la instrucción oral explícita. `HL D/W Candle` se conserva solo como texto literal desactualizado de la imagen.
7. Niveles Fibonacci derivados del ZigZag externo.
8. Sweep, Grab y Run alrededor de zonas de liquidez.
9. ZigZag interno y externo.
10. Anchored VWAP.
11. Anchored Volume Profile.

## Diferencias respecto de la lectura OCR anterior

- La lectura exacta **no contiene DIY**.
- La imagen escribe `HL D/W Candle`, pero Bryan confirma que debe ignorarse ese rótulo y conservar la indicación oral explícita **1D/4H**. El bloque ya está hecho y aceptado.
- La foto dice `Anchored Volume profile`, no solo un Volume Profile genérico.
- La imagen agrupa Sweep/Grab/Run dentro de zonas de liquidez, pero no fija sus ventanas ni la FSM.

## Conflictos con otras fuentes

### Rótulo D/W frente a instrucción oral 1D/4H

A14b dice “daily time and four hours also, only the two”. Bryan confirma que esa instrucción oral es la que debe aplicarse y que el rótulo `D/W` de la imagen se ignora. Por tanto:

- la app conserva **1D y 4H**;
- no se añade W;
- HLD se considera ya hecho y aceptado;
- no vuelve a la cola de implementación.

### DIY

El PDF §6 y A07 siguen respaldando DIY/Supply-Demand, pero la foto exacta no lo usa para decidir si están todos los bloques visuales. Por ello:

- no debe eliminarse del alcance contractual;
- no debe ser el siguiente bloque visible antes de completar los once elementos de esta imagen;
- queda en una segunda capa de cumplimiento después del checklist visual, salvo instrucción nueva del profesor.

### Detalles no visibles en la imagen

La FSM, `v1m/v5m/v15m`, concurrencia §5, pips, export y modelos no aparecen en el checklist. Siguen respaldados por PDF/audios, pero no deben confundirse con los faltantes visuales. HLD 1D/4H queda cerrado y no desplaza trabajo pendiente.

## Estado contra el runtime actual

| Elemento | Estado | Brecha principal |
|---|---|---|
| SMC INT/EXT | Sustancial | Verificación final de estilos/estructura contra referencia |
| OB + mitigar antiguos | Parcial/sustancial | Confirmar snapshot y desaparición causal de consumidos |
| FVG + mitigar antiguos | Sustancial | Verificación final y contrato de debug |
| Trend lines/canales | Parcial | Automático: >1h, uno activo, extensión causal e invalidación |
| EQH/EQL | Sustancial en Liquidity | Confirmar INT/EXT y presentación esperada |
| HL 1D/4H | **Terminado/aceptado** | Se ignora el rótulo D/W de la imagen; no añadir W ni reabrir HLD |
| Fib de ZZ externo | Parcial | Selección asistida; falta automático sobre último impulso consolidado |
| Sweep/Grab/Run | Parcial | Grab >8 incorrecto, Run tras retest y FSM incompletos |
| ZZ INT/EXT | Sustancial | Falta exponer 2h por audio, aunque la foto no fija TF |
| Anchored VWAP | Ausente | Implementar desde cero sin reactivar legacy |
| Anchored Volume Profile | Ausente | Implementar desde cero sin reactivar legacy |

## Orden técnico recomendado para cerrar el checklist

1. **No reabrir HLD 1D/4H.**
2. Cerrar dependencias visuales que están parciales: canal automático, exposición final de ZZ interno/externo y Fibonacci automático desde el ZZ externo consolidado.
3. Implementar **Anchored Volume Profile** y después **Anchored VWAP**, porque el POC del perfil es uno de los anclajes formales del VWAP.
4. Integrar esos niveles con OB/FVG/EQH/EQL/canal/Fibonacci en Liquidity.
5. Corregir Sweep/Grab/Run y completar su FSM: Sweep 1–2, Grab 3–8 y Run directo o tras retest.
6. Ejecutar una demo visual con Replay siguiendo los once elementos de la imagen.
7. Después cerrar obligaciones no visibles del PDF/audio: `v1m/v5m/v15m`, pips/export, concurrencia §5 y DIY §6.
8. Modelos al final.
