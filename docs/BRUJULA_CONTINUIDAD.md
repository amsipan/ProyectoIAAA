# Brújula de continuidad — Proyecto IA

**Leer primero al iniciar o recuperar una sesión.**  
**Última actualización:** 2026-07-19  
**Prioridad operativa confirmada por Bryan:** terminar la reforma de **indicadores** antes de iniciar t-SNE/GMM/HMM.

Esta brújula es el punto de entrada corto. La historia y evidencia completas están en [`MEMORIA_RECUPERADA_019f6e8d.md`](MEMORIA_RECUPERADA_019f6e8d.md). La meta ML se conserva en [`PLAN_DEFINITIVO.md`](PLAN_DEFINITIVO.md), pero no reemplaza la cola inmediata de indicadores descrita aquí.

## 1. Repositorio y protección del trabajo

- Repositorio canónico: `C:\ia\proyecto_iaaa\Proyecto\ProyectoIAAA`
- No usar como fuente de trabajo: `C:\m1\ia\proyecto_iaaa\Proyecto\ProyectoIAAA`
- Rama observada al fijar esta brújula: `feature/liquidity-v2-fsm`
- El worktree contiene trabajo importante de Liquidity/Replay sin consolidar.

Antes de editar, ejecutar y leer:

```powershell
git status --short --branch
git diff --stat
git diff
```

No ejecutar `reset --hard`, `clean`, checkout destructivo, rebase, sustituciones masivas, commit, push o merge sin autorización expresa de Bryan. Un archivo sin seguimiento puede formar parte del trabajo aceptado.

`C:\Users\bryan\Downloads\Proyecto` es material del profesor de **solo lectura**. El archive legacy está fuera del repo. No reactivar ni importar sus módulos al runtime; se pueden consultar ideas históricas, pero cualquier lógica útil debe reimplementarse en módulos actuales y probarse.

## 2. Fuentes y autoridad por ámbito

1. **Estado vivo:** código, `git status`, diff y tests actuales.
2. **Runtime oficial:** [`PRODUCTO_OFICIAL.md`](PRODUCTO_OFICIAL.md).
3. **Prioridad de continuidad:** este documento, confirmado por Bryan el 19-jul-2026.
4. **Historia y decisiones:** [`MEMORIA_RECUPERADA_019f6e8d.md`](MEMORIA_RECUPERADA_019f6e8d.md).
5. **Requisitos formales:** `material_profesor/Especificacion_Proyeto_2a_Fase.pdf`.
6. **Dependencias conceptuales del profesor:** `C:\Users\bryan\Downloads\20260714_164526_extract\ORDEN_PROYECTO_DEFINITIVO.md`.
7. **Meta posterior de datos/ML:** [`PLAN_DEFINITIVO.md`](PLAN_DEFINITIVO.md).
8. Capturas/configuraciones del profesor prevalecen frente a defaults genéricos de Pine/TradingView.

Si dos fuentes chocan, no lo resuelvas silenciosamente: señala la contradicción y pregunta a Bryan. `ROADMAP.md`, `AI_CONTEXT.md` y documentos viejos pueden contener historia de módulos legacy; no prueban que esos módulos formen parte del producto actual.

## 3. Producto oficial terminado

Runtime oficial: `smc_pro`, `smc_fvg`, `hld`, `pchan`, `zigzag`, `fib`, `liq`.

Completado y aceptado:

- Chart OHLC, temporalidades y Replay causal.
- SMC Pro + Structures/FVG.
- HLD 4h/D.
- Parallel Channel manual de tres clics.
- ZigZag externo ChartPrime e interno ZZMTF.
- Fib Retracement nativo y editable.
- Liquidity v2 **MVP/hito A**: BSL/SSL, EQH/EQL, Sweep/Grab/Run, Historial, pivotes acumulados, export básico y observation stream.
- Replay con slots vacíos, transformación X compartida, rewind y feeds causales.

Validación histórica de cierre: suite oficial seleccionada 558/558 y `t/38` con 52 checks. Esto no significa que toda `prove -l t` estuviera verde: `t/17-ui-wiring.t` conservaba 20 expectativas antiguas de UI. Reejecutar antes de afirmar el estado actual.

## 4. Cola operativa vigente

### Paso 1 — cerrar y verificar formalmente Liquidity §4

1. Volumen real por evento `v1m`, `v5m`, `v15m`, agregado por timestamps/rangos de cada TF.
2. Clasificación INT/EXT real y propagada a eventos/observation stream.
3. Reconciliar la FSM actual con los estados formales `Acceptance` y `Reclaimed` del PDF.
4. Resolver con evidencia la diferencia de Grab: PDF ≤3 velas frente a clases posteriores con indecisión de varias velas.
5. Completar export preliminar: `dist_pips_placeholder`, `kind` y features causales mínimas.

Las siete zonas y ~50 features son enriquecimiento posterior; no afirmar que ya existen ni mezclarlas silenciosamente con el MVP.

### Paso 2 — concurrencia §5

- Sweep refuerza CHoCH contrario.
- Run refuerza el próximo BOS a favor.
- Grab genera alerta de reversal.
- FVG durante o inmediatamente después de Sweep/Grab = Zona de Alta Reacción.

### Paso 3 — próximo indicador visible: DIY Strategy Builder §6

Priorizar Supply/Demand y confluencia con OB. El feedback posterior favorece retirar u ocultar SuperTrend/HalfTrend/Range Filter, pero el PDF aún los enumera: Bryan debe confirmar si se implementan, quedan ocultos o se consideran sustituidos. No restaurar el módulo legacy.

### Paso 4 — Advanced Volume Profile §7

Sesión, BOS/CHoCH HTF, contingencia histórica, POC, VAH y VAL; causal y bajo demanda.

### Paso 5 — Anchored VWAP §8

Multipivot desde sesión, apertura, BOS, CHoCH y POC; causal, anclas consolidadas y hasta 3σ cuando corresponda.

### Paso 6 — modelos, solo después

Siete zonas/features → export batch → pips/Z-score train-only → split temporal → t-SNE → GMM → HMM INT/EXT.

**Anchored VWAP no es el próximo indicador. No iniciar modelos todavía.**

## 5. Reglas que no se pueden perder

- Cálculo separado de Tk/render.
- Escala X compartida; geometría estable bajo zoom.
- Velas encima de estructuras; ancho estructural 1.
- Overlays pesados bajo demanda.
- Replay sin futuro en OHLC, ATR, timestamps, escala, labels, pivotes, estado ni features.
- En rewind, reconstruir hasta `replay_idx` y eliminar confirmaciones dependientes del futuro.
- No refactorizar masivamente `ChartEngine.pm` “de paso”.
- No agregar dependencias sin aprobación.
- Validar sintaxis Perl, tests dirigidos, Replay y suite oficial relevante.

## 6. Protocolo contra pérdida de contexto

### Al iniciar cada sesión

1. Leer `AGENTS.md` y esta brújula.
2. Inspeccionar Git en modo lectura.
3. Leer solo la sección relevante de la memoria extensa y la spec/task actual.
4. Declarar en 5 líneas: rama, worktree, último hito, tarea actual y próximo paso.
5. No escribir código hasta reconciliar cualquier divergencia.

### Antes de una compactación o cambio de modelo

Actualizar únicamente la sección **Checkpoint vivo** de este archivo con:

- tarea exacta en curso;
- archivos modificados en la sesión;
- decisiones nuevas de Bryan;
- pruebas ejecutadas y resultados;
- pendientes y primer comando/paso para retomar;
- incertidumbres o bloqueadores.

No reescribir la historia completa en cada compactación. La memoria extensa es histórica; esta brújula contiene el estado vivo.

## 7. Checkpoint vivo

**Fecha:** 2026-07-19  
**Tarea actual:** documentación de continuidad terminada; aún no se inició el siguiente lote de código.  
**Último hito de producto:** Liquidity v2 MVP + cierre causal de Replay.  
**Próximo análisis/implementación autorizado:** comenzar por inspección del worktree y diseñar el cierre formal de Liquidity §4.  
**Primera decisión pendiente:** alcance exacto de FSM/Grab/export y, más adelante, tratamiento de ST/HT/RF dentro de DIY.  
**Archivos creados para continuidad:** `docs/BRUJULA_CONTINUIDAD.md`, `docs/MEMORIA_RECUPERADA_019f6e8d.md`.  
**Entradas actualizadas:** `AGENTS.md`, `README.md`, `docs/PLAN_DEFINITIVO.md`, `docs/AI_CONTEXT.md`.  
**Código de producto tocado en esta tarea:** ninguno.  
**Pruebas de esta tarea documental:** verificar existencia de archivos, enlaces relativos, búsquedas de prioridades contradictorias y diff de documentación.  
**Advertencia:** preservar el trabajo sin commit de `feature/liquidity-v2-fsm` y distinguir estos cambios documentales del trabajo previo de Liquidity/Replay.

## 8. Prompt corto de rescate

Usa este texto si notas que el agente perdió el rumbo:

> Detente y recupera el contexto del proyecto. Trabaja únicamente en `C:\ia\proyecto_iaaa\Proyecto\ProyectoIAAA`. Lee primero `AGENTS.md`, luego `docs/BRUJULA_CONTINUIDAD.md` y consulta `docs/MEMORIA_RECUPERADA_019f6e8d.md` para la historia. Inspecciona `git status --short --branch`, `git diff --stat` y el diff en modo de solo lectura antes de tocar archivos. Preserva el worktree de `feature/liquidity-v2-fsm`; no reactives legacy, no hagas reset/clean/commit/push. La prioridad vigente es terminar indicadores antes de modelos: cerrar Liquidity §4 (volumen v1m/v5m/v15m, INT/EXT, FSM Acceptance/Reclaimed, semántica Grab y export), después concurrencia §5, DIY Supply/Demand §6, Volume Profile §7 y Anchored VWAP §8. Solo luego se retoma t-SNE/GMM/HMM. Resume lo entendido y señala contradicciones antes de implementar.

## 9. Prompt de checkpoint antes de compactar

> Antes de que se compacte el contexto, actualiza solamente la sección `Checkpoint vivo` de `docs/BRUJULA_CONTINUIDAD.md`. Registra: tarea en curso, decisiones nuevas del usuario, archivos tocados, pruebas y resultados exactos, pendientes, incertidumbres y primer paso para reanudar. No cambies la prioridad histórica ni marques algo como terminado sin evidencia. Después muéstrame el checkpoint para aprobarlo.
