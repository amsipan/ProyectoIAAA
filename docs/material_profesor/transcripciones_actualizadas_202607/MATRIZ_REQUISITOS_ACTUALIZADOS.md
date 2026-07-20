# Matriz cronológica de requisitos y overrides

**Corte:** 2026-07-19  
**Estado:** dictamen de evidencia. Distingue mandatos docentes, interpretaciones y decisiones de ingeniería.

Claves: **PDF**, **L-SMC/L-LIQ/L-IND** (Lumina), **A07**, **A14a**, **A14b**, **A15**, **IMG**. Los archivos concretos se enumeran en `MANIFEST.md`.

## 1. Reglas para resolver fuentes

1. Una instrucción explícita posterior gana solo sobre el mismo requisito.
2. Una omisión posterior no cancela una regla.
3. Una captura/configuración visual no elimina por sí sola un componente contractual.
4. El output ASR contiene inserciones del prompt y no es una transcripción literal certificada.
5. La imagen confirma inventario, no parámetros ni arquitectura exacta.
6. Las recomendaciones técnicas se identifican como tales.

## 2. Indicadores y dependencias

| Tema | Evidencia posterior | Resultado vigente | Tipo/confianza |
|---|---|---|---|
| Estructura INT/EXT | A14b: externo primero, interno después | Calcular/validar estructura externa antes de interna; BOS/CHoCH diferenciados | Profesor, alta |
| Fuente estructural | A07: LuxAlgo/SMC Pro y ZigZag externo corrigen errores de Mxwll | Usar SMC Pro/LuxAlgo + ZZ externo como referencia; no copiar Mxwll ciegamente | Profesor, alta |
| Estilo | A14a: externo continuo, interno rayado; colores alcista/bajista | Conservar distinción y colores de referencia | Profesor, alta |
| OB | A07/A14a: internos/externos, eliminar consumidos | OB causales, mitigables y exportables | Profesor, alta |
| FVG | A14a: `Display` + `Reduce Mitigated`, varios disponibles | Tres velas, reducción parcial y eliminación total; reemplaza “solo última trama” de A07 | Override, alta |
| DIY | PDF exige ST, HT, RF, Supply y Demand; A07 deja visible solo Supply/Demand | Los cinco siguen contractualmente vigentes. Supply/Demand es prioridad visual/confluencia, no cancelación | PDF + configuración, alta |
| Canal | A07/A14b: ≥3 puntos, >1 h, preferencia 1m, uno activo, Replay, invalidación | Detector causal con un canal activo y reglas de expiración; tolerancia abierta | Profesor, alta |
| EQH/EQL | PDF `ATR×0.10`; julio no sustituye cifra | Mantener tolerancia formal y clasificar/proyectar según diseño | PDF, alta |
| HLD | A14b: solo D/4h; la imagen escribe D/W | **Terminado y aceptado en D/4h.** Bryan confirma que prevalece la voz del profesor, no se añade W y no se reabre el indicador | Decisión confirmada, alta |
| ZZ externo | A14a: coincide con swings relevantes | Pivotes principales limpios y causales | Profesor, alta |
| ZZ interno | A14a: 15m/30m/1h/2h, solo Show ZigZag | Las cuatro opciones deben estar expuestas y recalcular | Profesor, alta |
| Fibonacci | A14b/A15: impulso consolidado de ZZ externo, 61 con mayor peso | Conservar cinco niveles canónicos `0.236/0.382/0.5/0.618/0.786`. A15 enumera cuatro ejemplos, pero no cancela 0.786 | Profesor + contrato técnico, alta |
| AVWAP | PDF: sesión, apertura, BOS, CHoCH, POC. A14b: pivote ext/int relevante confirmado, ≤3σ | Mantener anchors PDF y añadir pivote confirmado | Integración compatible, alta |
| Volume Profile | PDF: sesión, BOS/CHoCH HTF, contingencia, POC/VAH/VAL. A14b: “puede” anclarse a ZZ externo | Modos PDF obligatorios. Ancla ZZ es posibilidad de confianza media, pendiente de confirmación | PDF alta / modo ZZ medio |
| Liquidity | PDF + Lumina + julio | Primero niveles válidos; después Sweep/Grab/Run. No limitarse a pivotes arbitrarios | Convergente, alta |

## 3. Conflictos de Liquidity

| Tema | Regla anterior | Regla más reciente | Decisión |
|---|---|---|---|
| Sweep | PDF: penetra y cierra dentro | A14b/A15: retorno en 1–2 velas | 1–2 velas, incluyendo misma vela |
| Grab | PDF: retorno ≤3 | A15: más de dos, enumera 3–8 y retorno | **Override vigente: 3–8 velas** |
| Run | PDF: N=3 cierres fuera | A14b/A15: consolida fuera, directo o con retest | Conservar N=3 como default formal y soportar retest; ventana máxima futura abierta |
| Futuro | Replay prohíbe futuro | A14b/A15: mirar futuro para etiqueta final | Futuro solo en etiquetado histórico offline; nunca en features/render |
| FSM | PDF/contrato: `Detected→Swept→Acceptance/Reclaimed→Resolved` | Julio no elimina estados | Conservar cinco estados observables |
| INT/EXT | PDF: procedencia TF activa vs HTF | Julio habla de jerarquía estructural ZZ/SMC | El mandato contractual sigue siendo procedencia TF. Guardar además `structure_scope` es recomendación técnica para no perder información; qué dimensión separa los HMM queda por confirmar |
| Volumen | PDF: `v1m/v5m/v15m` exactos | Julio: volumen correlacional; VWAP/VP visibles | Persistir agregados exactos y mantener overlays separados |

## 4. Reglas consolidadas por componente

### Estructura, FVG, OB y DIY

- Externa antes que interna; no promover cada giro interno.
- BOS/CHoCH externos continuos e internos discontinuos.
- FVG de tres velas, varios activos, reducción parcial y eliminación total.
- OB internos/externos desaparecen al consumirse.
- DIY mantiene SuperTrend, HalfTrend, Range Filter, Supply y Demand. Supply/Demand tiene prioridad visual y confluencia con OB.

### Canal

- Preferencia 1m, ≥3 puntos alineados, desarrollo >1 hora.
- Pequeña penetración con retorno no invalida.
- Un solo canal activo, extendido hasta la última vela causal.
- Invalidar por ruptura real, cambio de tendencia, lateralización o consumo.
- Tolerancia/alineación exactas son parámetros de ingeniería abiertos.

### HLD

- Terminado y aceptado en 1D/4H.
- Ignorar el rótulo D/W de la imagen.
- No añadir W ni reabrir implementación, fallback o contrato de snapshot.

### ZigZag y Fibonacci

- ZZ externo = pivotes principales; ZZ interno seleccionable 15m/30m/1h/2h.
- Fibonacci usa último impulso externo consolidado, no rama móvil ni retroceso.
- Actualizar al salir, llegar a 0 o consolidarse el siguiente impulso.
- 61/61.8 tiene mayor peso cualitativo; precisión decimal técnica = 0.618 por contrato.
- Mantener `0.236`, `0.382`, `0.5`, `0.618`, `0.786` en render y como candidatos de features. A15 no cerró la lista al omitir 0.786.

### AVWAP y Volume Profile

- AVWAP: anchors PDF más pivote externo/interno relevante confirmado; hasta 3σ.
- VP: sesión, BOS/CHoCH HTF, contingencia histórica, POC/VAH/VAL.
- Anclar VP al ZZ externo es posibilidad razonable, no obligación cerrada por una frase sin diarización.

## 5. Dataset y modelos

| Tema | Mandato | Decisión/nota |
|---|---|---|
| Filas | Solo eventos cerca de liquidez | Tabla headless por eventos |
| Columnas | ~50, posiblemente 100 | Lista exacta abierta |
| Precio | Pips | Cálculo real por activo |
| Z-score | Normalización Z | Ajuste train-only es salvaguarda técnica contra fuga, no frase explícita del profesor |
| Historia | Toda la historia por bloques | Camino batch separado del viewport |
| Split | Junio “pure test” | Split temporal; periodos anteriores train |
| Metadata | tiempo/event_id aparte | No entran a t-SNE/GMM |
| t-SNE | Primero, 2–3D, perplejidad/semilla | Exploración/parametrización |
| GMM | Probabilidades S/G/R suman 1; umbral 85% | El audio es ambiguo sobre embedding vs features completas. Recomendación: GMM en features completas y t-SNE como ayuda exploratoria, pendiente de validación docente |
| HMM | Secuencias temporales; uno interno y otro externo | La dimensión exacta de “interno/externo” para separar datos debe confirmarse |
| Evaluación | accuracy, precisión, ROC, matriz de confusión | Obligatorio |

## 6. Parámetros no definidos

No deben inventarse como mandato: tolerancia del canal; mitigación wick/cierre/%; pivote interno “relevante”; tiempo de confirmación AVWAP; cercanía para una fila; ventana futura máxima de Run; lista cerrada de features; bins/Value Area; GMM componentes/covarianza; estados/emisiones HMM; porcentaje de train/test; y dimensión exacta INT/EXT usada por HMM.

## 7. Brecha frente al runtime

| Bloque | Estado auditado |
|---|---|
| SMC/BOS/CHoCH | Sustancialmente implementado |
| FVG | Sustancialmente implementado |
| HLD 1D/4H | **Terminado/aceptado**; no añadir W ni reabrir |
| ZZ INT/EXT | Cálculo admite 2h y existe callback 120; falta botón/wiring visible y test dirigido de 2h |
| Fibonacci | Selección asistida de pierna ZZ; falta selección/renovación automática causal |
| Canal | Manual y automático parcial. Al automático le faltan >1h, elección de uno, extensión a última vela causal e invalidación completa |
| Liquidity etiquetas | Parcial: >8 también termina Grab; reclaim resuelve antes de detectar Run tras retest |
| Liquidity FSM | Faltan estados observables Acceptance/Reclaimed |
| Liquidity volumen | Faltan `v1m/v5m/v15m`; base 15m no permite reconstruir 1m/5m |
| Liquidity INT/EXT | `kind => undef` |
| Export | `dist_pips_placeholder => 0`; features incompletas |
| Concurrencia §5 | Ausente |
| DIY §6 | Ausente |
| Volume Profile §7 | Ausente |
| Anchored VWAP §8 | Ausente |
| Dataset/modelos | Ausente |

### Brecha transversal del contrato de debug

Visualmente implementado no equivale a task cerrada bajo `PHASE2_DEBUG_CONTRACT.md`. Liquidity no expone snapshots canónicos mediante `IndicatorSnapshot`; ZigZag usa tipos `ZZ_*` en vez de los `HH/HL/LL/LH` exigidos; Fibonacci y canal son herramientas `Drawing` sin salida compatible. HLD queda expresamente fuera de esta reapertura por decisión de Bryan. Para las demás piezas debe reconciliarse el contrato o añadir adapters/tests.

## 8. Cola operativa reconciliada con la imagen de aceptación

### Cierre visual inmediato

1. Mantener cerrado HLD 1D/4H.
2. Demo/regresión de SMC INT/EXT, OB/FVG mitigados y EQH/EQL; no reescribir lo ya correcto.
3. Terminar canal automático, exposición 2h del ZZ interno y Fibonacci automático del ZZ externo consolidado.
4. Implementar Anchored Volume Profile (POC/VAH/VAL).
5. Implementar Anchored VWAP, usando también POC como ancla.
6. Integrar fuentes y cerrar semántica/FSM de Sweep, Grab y Run.
7. Pasar el checklist completo en Replay.

### Después del cierre visual

8. Volumen multi-TF, INT/EXT contractual, pips y export.
9. Concurrencia §5.
10. DIY §6: sigue siendo contractual por PDF/audio, pero no figura en la imagen usada para aceptación visual.
11. Dataset y modelos.

La imagen nueva sí cambia la **prioridad práctica**: Volume Profile y Anchored VWAP dejan de estar detrás de DIY porque son faltantes visibles del checklist. No cambia la existencia contractual de DIY ni autoriza comenzar modelos antes de cerrar indicadores.

## 9. Decisiones abiertas de ingeniería o confirmación

No requieren “aprobar” de nuevo lo que el profesor ya dijo. Sí requieren decisión:

1. Cómo representar sin colisión procedencia TF y alcance estructural; recomendación: dos campos.
2. Qué dimensión separa el HMM interno/externo.
3. Visibilidad de ST/HT/RF, sin eliminarlos del contrato.
4. Si el modo VP anclado a ZZ externo es obligatorio u opcional.
5. Si GMM usa features completas o embedding t-SNE; recomendación técnica: features completas.
6. Dónde insertar las brechas de canal/Fib/ZZ 2h y debug contract en la cola vigente.
