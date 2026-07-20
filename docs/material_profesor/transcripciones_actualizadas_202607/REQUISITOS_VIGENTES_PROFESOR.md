# Requisitos vigentes del profesor — dictamen consolidado

**Estado:** conclusión de investigación, con mandatos, interpretaciones y decisiones técnicas separados.  
**Regla aplicada:** una instrucción explícita posterior reemplaza a una anterior sobre el mismo requisito. Una omisión no cancela.

## Conclusión ejecutiva

La app debe ser un chart causal tipo TradingView en Perl/Tk que construya estructura externa e interna, proyecte fuentes coordinadas de liquidez, clasifique eventos históricos como Sweep/Grab/Run, exporte features sin fuga y, después de completar indicadores, alimente t-SNE, GMM y HMM interno/externo.

Las ventanas más recientes son **Sweep 1–2 velas, Grab 3–8 velas y Run con consolidación fuera, directa o tras retest**. Grab 3–8 sí reemplaza el ≤3 del PDF. El resto de los conflictos y decisiones técnicas se detalla abajo.

## 1. Indicadores que debe tener la aplicación

### Estructura y niveles

1. **Estructura SMC externa e interna**
   - Externa primero, interna después.
   - BOS y CHoCH de ambos ámbitos.
   - Externo continuo, interno discontinuo.
   - Colores alcista/bajista de referencia.
   - Validar externo con SMC Pro/LuxAlgo y ZigZag externo, no con Mxwll cuando discrepe.

2. **Order Blocks**
   - Internos y externos.
   - Causales, mitigables y eliminados al consumirse.
   - Confluencia con Supply/Demand exportable como evidencia.

3. **FVG**
   - Patrón de tres velas, incluyendo gap de apertura válido.
   - Varios FVG activos disponibles.
   - Mitigación parcial reduce la zona y total la elimina.
   - No usar el FVG defectuoso del script descartado.

4. **DIY Strategy Builder**
   - Contractualmente conserva SuperTrend, HalfTrend, Range Filter, Supply y Demand.
   - A07 mostró únicamente Supply/Demand visible, por lo que se prioriza su visualización/confluencia, pero no se eliminan los otros tres.

5. **Trend line / canal**
   - Detección causal, preferentemente 1m.
   - ≥3 apoyos alineados durante más de una hora.
   - Pequeñas perforaciones con retorno no invalidan.
   - Un canal activo, extendido a la última vela causal.
   - Invalidación por ruptura real, cambio de tendencia, lateralización o consumo.

6. **EQH/EQL**
   - Equal Highs/Lows con tolerancia formal `ATR×0.10` mientras no exista corrección.
   - Conservar apariencia de referencia.

7. **HLD — terminado y aceptado**
   - Solo 4h y D, conforme a la instrucción oral explícita.
   - El rótulo `HL D/W Candle` de la imagen se considera desactualizado y no obliga a añadir W.
   - Bryan confirma que este indicador no debe reabrirse ni volver a la cola.

8. **ZigZag externo e interno**
   - Externo con pivotes principales limpios.
   - Interno seleccionable 15m, 30m, 1h y 2h.
   - Recalcular al cambiar TF.
   - Fibonacci no se obtiene del ZZ interno.

9. **Fibonacci automático**
   - Último impulso consolidado del ZZ externo, no retroceso ni rama móvil.
   - Actualizar al salir, alcanzar 0 o consolidarse un nuevo impulso.
   - Nivel 0.618 con mayor peso cualitativo.
   - Conservar cinco niveles: `0.236`, `0.382`, `0.5`, `0.618`, `0.786`. La omisión de 0.786 en una enumeración de A15 no lo cancela.

10. **Anchored VWAP**
    - Anchors del PDF: sesión, apertura, BOS, CHoCH y POC.
    - Añadir swing externo o interno relevante confirmado.
    - Hasta 3σ y ancla reciente/no móvil.

11. **Advanced/Anchored Volume Profile**
    - Sesión, BOS/CHoCH HTF, contingencia histórica, POC/VAH/VAL.
    - El posible anclaje al ZZ externo aparece en A14b como formulación tentativa sin diarización. Se conserva como opción por confirmar, no como obligación inequívoca.

## 2. Fuentes de liquidez

Liquidity debe integrar progresivamente BSL/SSL, EQH/EQL, OB, Supply/Demand, FVG, canal, soporte/resistencia, Fibonacci, HLD, AVWAP y Volume Profile. Lumina presenta una taxonomía anterior de siete zonas, pero julio no ratifica una lista cerrada. El principio firme es: **primero niveles válidos, luego Sweep/Grab/Run**.

## 3. Definición vigente de eventos

| Evento | Definición | Ventana |
|---|---|---:|
| Sweep | Toma liquidez y regresa rápidamente al rango | 1–2 velas |
| Grab | Consume gradualmente, permanece indeciso y regresa | 3–8 velas |
| Run | Rompe/toma y consolida en la dirección, directo o tras retest | `N=3` cierres fuera como default formal; ventana futura máxima abierta |

El futuro se usa únicamente offline para resolver la etiqueta histórica. Features, Replay y render permanecen causales.

## 4. FSM obligatoria

```text
Detected → Swept → Acceptance o Reclaimed → Resolved
```

- `Detected`: nivel válido.
- `Swept`: cruza/toma el extremo.
- `Acceptance`: sostiene aceptación fuera, candidato a Run.
- `Reclaimed`: vuelve al rango, candidato a Sweep/Grab según duración.
- `Resolved`: clase final inmutable.

Julio cambia ventanas, no elimina estados.

## 5. INT/EXT sin inventar una autoridad

**Mandato contractual:** el PDF define Internal Liquidity por origen en TF activa y External Liquidity por origen HTF proyectado.

**Evidencia adicional:** julio usa “interno/externo” también para jerarquía SMC/ZZ. No demuestra inequívocamente que la separación de HMM deba usar esta segunda dimensión.

**Recomendación de ingeniería, pendiente de decisión:** preservar ambas sin colisión:

```text
origin_tf / projected_from_htf       # procedencia contractual
structure_scope = internal|external  # jerarquía SMC/ZZ
```

No atribuir esta arquitectura de dos campos al profesor. Antes de entrenar HMM debe definirse cuál dimensión separa sus dos secuencias.

## 6. Volumen y causalidad

- Persistir `v1m`, `v5m`, `v15m` reales por evento.
- No derivar 1m/5m desde base 15m.
- ATR no es volumen.
- VWAP/VP son representaciones visibles; OHLCV agrega features.
- Separar cálculo puro de Tk.
- Al rebobinar, reconstruir desde prefijo causal.
- Congelar features al primer contacto/toma; futuro solo cambia la etiqueta final.
- GUI usa ventana/contexto cuando sea viable; batch procesa historia completa con la misma lógica causal.

## 7. Export por eventos

Una fila representa un evento cercano a liquidez, no cada minuto:

```perl
{
  event_id, time, index,             # metadata, fuera de t-SNE/GMM
  level_kind, level_price, side,
  origin_tf, projected_from_htf,
  structure_scope,                   # campo técnico recomendado
  event, state_history,
  features => {
    distance_pips, atr_pips,
    v1m, v5m, v15m,
    # distancias, flags y confluencias
  },
}
```

Mandatos: aproximadamente 50–100 columnas, precios/distancias en pips, normalización Z, metadatos separados y junio solo test.

Salvaguarda técnica, no frase docente: ajustar Z-score solo con train y reutilizar esos parámetros en test.

## 8. Modelos posteriores

### t-SNE

- Primero para visualizar 2–3 dimensiones.
- Ajustar perplejidad y semilla.
- Sin tiempo/índice como features.

### GMM

- `P(Sweep)+P(Grab)+P(Run)=1`.
- Abstención si `max(P)<0.85`.
- El audio es ambiguo sobre si recibe embedding t-SNE o las 50–100 features “parametrizadas” por t-SNE.
- Recomendación técnica: usar t-SNE para exploración/inicialización y entrenar GMM sobre features completas estandarizadas. Debe validarse antes de implementar.

### HMM

- Temporal, con secuencias de etiquetas.
- Un HMM interno y otro externo.
- La dimensión exacta usada para separar ambos sigue abierta.
- Evaluar con accuracy, precisión, ROC, matriz de confusión y métricas del curso.

## 9. Estado real de la app

### Sustancialmente implementado

- Chart, TF agregables y Replay causal.
- SMC BOS/CHoCH INT/EXT.
- FVG.
- ZigZag base.
- Liquidity visual base BSL/SSL/EQH/EQL y nombres Sweep/Grab/Run.

### Parcial

- **Liquidity semántica:** retornos >8 también acaban Grab; reclaim resuelve antes de poder reconocer Run tras retest.
- **Liquidity FSM/export:** faltan Acceptance/Reclaimed, volumen multi-TF, INT/EXT y pips reales.
- **HLD 1D/4H:** terminado y aceptado por Bryan; no añadir W ni reabrir su implementación.
- **ZZ interno 2h:** el cálculo y callback 120 existen; falta exposición visible/wiring de UI y test dirigido.
- **Fibonacci:** selección asistida de pierna ZZ; falta automatización y renovación causal.
- **Canal automático:** faltan >1h, elegir uno, extenderlo a la última vela causal e invalidarlo completamente.
- **Fuentes:** no alimentan todavía un export unificado.

### Ausente

- Concurrencia §5.
- DIY §6.
- Advanced Volume Profile §7.
- Anchored VWAP §8.
- Dataset/modelos.

### Deuda obligatoria del contrato de debug

`PHASE2_DEBUG_CONTRACT.md` exige items canónicos y tests con `IndicatorSnapshot`. Liquidity no expone esos snapshots; ZigZag usa tipos `ZZ_*` en vez de `HH/HL/LL/LH`; Fib/canal Drawing no son verificables mediante ese contrato. HLD queda fuera de esta reapertura por decisión expresa de Bryan. Las demás tasks no deben declararse cerradas hasta reconciliar contrato, adapters y tests.

## 10. Orden de continuación vigente

La imagen proporcionada por Bryan es el checklist que el profesor usa para comprobar visualmente si están todos los indicadores. Por eso se distinguen dos colas, sin eliminar obligaciones del PDF.

### A. Cierre visual inmediato del checklist

1. No reabrir HLD 1D/4H.
2. Verificar en Replay los bloques ya sustanciales: SMC INT/EXT, OB mitigados, FVG mitigados y EQH/EQL. Corregir solo defectos demostrados.
3. Cerrar los bloques visuales parciales: canal automático causal, botón 2h del ZZ interno y Fibonacci automático desde el último impulso consolidado del ZZ externo.
4. Implementar **Anchored Volume Profile** con POC/VAH/VAL.
5. Implementar **Anchored VWAP** después, reutilizando POC además de sesión, apertura, BOS, CHoCH y pivotes confirmados.
6. Integrar esas fuentes en Liquidity y cerrar Sweep 1–2, Grab 3–8, Run directo/retest y la FSM formal.
7. Ejecutar una demo final con Replay siguiendo, en orden, el checklist de la imagen.

### B. Cumplimiento formal no visible y fases posteriores

8. Completar `v1m/v5m/v15m`, INT/EXT contractual, pips y export sin placeholders.
9. Concurrencia §5.
10. DIY §6, que sigue en el PDF pero **no figura en la imagen de aceptación**.
11. Dataset/modelos: features → batch → Z-score/split → t-SNE → GMM → HMM.

Esto reemplaza como prioridad práctica la cola anterior que adelantaba DIY a los overlays ausentes. No elimina DIY: únicamente lo aplaza hasta cerrar lo que el profesor verifica directamente con la imagen.

## 11. Decisiones que sí faltan

1. Representación técnica de procedencia TF y alcance estructural.
2. Dimensión INT/EXT para separar HMM.
3. Visibilidad de ST/HT/RF, sin eliminarlos.
4. Si VP anclado a ZZ externo se vuelve requisito u opción.
5. Entrada definitiva de GMM.
6. Ubicación de canal/Fib/ZZ 2h/debug contract en la cola.

No quedan pendientes de aprobación los overrides explícitos ya resueltos por la regla del usuario, en particular Grab 3–8. Este documento determina el alcance actual, pero no modifica código ni la documentación viva del roadmap hasta que Bryan decida los seis puntos técnicos anteriores.
