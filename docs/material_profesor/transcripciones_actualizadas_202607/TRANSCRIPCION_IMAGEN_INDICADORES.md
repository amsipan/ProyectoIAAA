# Lectura de la imagen-resumen de indicadores

**Fuente:** `indicadores_resumen_202607.png`  
**SHA-256:** `F309D27006DD01231CD728C5B73C5A37016D630E6C383AC6B0F6DE021C6029B1`  
**Corrección de lectura:** el 20-07-2026 Bryan proporcionó el texto exacto que el profesor usa como checklist. Esa lectura humana prevalece sobre el OCR local.

## Inventario exacto corregido

1. Estructura SMC interna/externa.
2. Niveles de liquidez:
   - OB, mitigar antiguos.
   - FVG, mitigar antiguos.
   - Trend lines/canales.
   - EQH/EQL.
   - HL D/W Candle.
3. Zonas de liquidez:
   - niveles Fibonacci del ZigZag externo;
   - Sweep/Grab;
   - Run.
4. ZigZag interno/externo.
5. Anchored VWAP.
6. Anchored Volume Profile.

La lectura OCR previa incluyó erróneamente `DIY` y normalizó el rótulo pequeño como `HLD`. La transcripción exacta demuestra que DIY no está en esta imagen y que el rótulo escrito es `HL D/W Candle`. Sin embargo, Bryan confirma que para el producto prevalece la instrucción oral explícita **1D/4H**, ya implementada y aceptada; no se añadirá W ni se reabrirá HLD. El OCR se conserva solo como evidencia del proceso, no como autoridad.

## Qué puede afirmarse

- La foto es un inventario/resumen, no una especificación matemática.
- El producto no termina en SMC o Liquidity básico.
- Incluye INT/EXT, OB, FVG, canal, EQH/EQL, HL de vela (operativamente 1D/4H), ambos ZigZag, Fibonacci, Anchored VWAP y Anchored Volume Profile. **DIY no figura en esta imagen.**
- Fibonacci aparece asociado al ZigZag externo.
- Sweep/Grab/Run aparecen después del bloque de liquidez y son corroborados por la explicación oral.
- VWAP y Volume Profile aparecen como anclados.

## Relaciones corroboradas por audio, no deducidas solo de las flechas

- La estructura externa se revisa antes que la interna.
- ZigZag externo sirve de árbitro/referencia para estructura externa y de fuente para el Fibonacci automático.
- Un pivote externo o interno relevante confirmado puede ser ancla de AVWAP.
- OB, FVG, EQH/EQL, canal, HLD, Fibonacci, VWAP y Volume Profile aportan niveles o confluencias de liquidez.
- Solo después de establecer niveles se clasifica/probabiliza Sweep, Grab o Run.

Estas frases describen **orden pedagógico, validación o relación funcional**. No deben leerse automáticamente como dirección de dependencia de software. Por ejemplo, “ZigZag valida estructura externa” no implica necesariamente que un módulo tenga que construirse primero o llamar al otro en una dirección específica.

## Flechas y relación tentativa

Las flechas pequeñas no son legibles con confianza suficiente para fijar una arquitectura. En particular, la foto por sí sola no prueba:

- que estructura externa calcule ZigZag o viceversa;
- que Volume Profile deba anclarse obligatoriamente al ZigZag externo;
- que todo pivote interno sea ancla válida de AVWAP;
- una secuencia computacional única entre cajas.

El posible anclaje de Volume Profile al ZigZag externo aparece también en A14b, pero la frase oral es tentativa (`puede ser`) y no tiene diarización. Se registra como posibilidad por confirmar, no como modo inequívocamente obligatorio.

## Qué no determina la foto

- ventanas de Sweep/Grab/Run;
- tolerancias de EQH/EQL;
- mitigación de OB/FVG;
- parámetros del canal;
- lista cerrada de niveles Fibonacci;
- sigmas del VWAP;
- bins, Value Area, POC, VAH o VAL;
- features o parámetros de t-SNE, GMM o HMM.

## Confianza

| Elemento | Confianza |
|---|---|
| Inventario INT/EXT, OB, FVG, canal, EQH/EQL, HL de vela, Fib, ZZ, AVWAP, AVP | Alta |
| Aplicación 1D/4H en vez del rótulo D/W | Decisión confirmada por Bryan basada en la voz del profesor |
| Sweep/Grab/Run como terna | Alta por audio; lectura visual parcial |
| Dirección exacta de las flechas | Baja-media; no se usa como arquitectura |
| Anotación pequeña junto a FVG | Baja; omitida |
