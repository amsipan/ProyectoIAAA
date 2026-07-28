# Auditoría Fase 0 + Fase 1 — Reentrenamiento modelo v2

**Re-auditoría:** 2026-07-28 (~02:55 UTC-5), tras fix documental del worker.
**Primera pasada:** mismo día ~02:50 → Fase 0 FAIL / Fase 1 FAIL documental (no existía evidencia del worker).
**Rol:** Auditor independiente (sin ejecutar entrenamiento).
**Base:** `docs/PLAN_REENTRENAMIENTO_MODELO_V2.md` (Fase 0 y Fase 1, con sus gates).

## Resumen ejecutivo

|| Veredicto |
|---|---|
| **Fase 0** — Congelar scope y ramificar trabajo | **PASS** (3/3 criterios) |
| **Fase 1** — Higiene de datos y reproducibilidad | **PASS** |
| **Gate Fase 2 (entrenamiento)** | **SÍ** |

El worker completó las 4 correcciones exigidas en la primera pasada y este auditor las verificó de forma independiente (incluido recomputo de labels en la pasada previa y comparación campo a campo del baseline binario).

---

## Fase 0 — detalle

Gate del plan: *v1 intacto + espacio de trabajo v2 limpio.*

| # | Criterio | Estado | Evidencia |
|---|---|---|---|
| 0.1 | No sobrescribir `Data/ml_out/lstm_fantasma/` v1 | **PASS** | Los 9 artefactos mantienen LastWriteTime del 27-jul 23:50–23:59 (+ `binary_metrics_test.json` aditivo 00:31) — sin escrituras nuevas desde la primera pasada del audit. Métricas coinciden con lo transcrito en `AUDIT_PASO4_CIERRE.md`. El worker documenta hashes SHA256 pre/post idénticos (`CHECK_FASE0_FASE1_V2.md` §Fase 0). |
| 0.2 | Nuevo directorio `Data/ml_out/lstm_fantasma_v2/` | **PASS** | Existe (creado 28-jul 02:50) con `baseline_v1_binary_metrics.json`. |
| 0.3 | Documentar “v2 = mejora métricas + presentación; v1 = baseline” | **PASS** | `docs/material_profesor/MODELO_V2_TRABAJO.md` (v1 “congelado como baseline: no se modifica ni se reentrena”; tabla de rutas) + sección “Actualización 2026-07-28 — trabajo v2” en `docs/RUTA_FINAL_MODELOS.md` (líneas ~440–446). |

## Fase 1 — detalle

Gate del plan: *baseline v1 reproducible + dataset estable.*

| # | Criterio | Estado | Evidencia |
|---|---|---|---|
| 1.1a | `fantasma_norm_stats.json` (86 features) | **PASS** | CHECK §Fase 1 confirma 86 `feature_columns`, z-score fit solo train (n=7649), exclusiones correctas; coincide con la verificación del auditor en la primera pasada. |
| 1.1b | `fantasma_train_norm.csv` / `fantasma_test_norm.csv` | **PASS** | 7649 / 2391 filas (CHECK + recomputo independiente del auditor, idénticos). |
| 1.1c | Distribución labels y3–y15 (masa 0…3) | **PASS** | CHECK documenta conteos train y test que **coinciden exactamente** con el recomputo independiente del auditor de la primera pasada (train: y3 100%, y5 89.6%, y10 72.0%, y15 62.5%; test: 100 / 87.4 / 67.2 / 55.2%). Añade P(≥1) por ventana y máximos observados. |
| 1.2 | Confirmar `seq_len=5`, seed, splits | **PASS** | `seq_len=5`, `seed=42`, 7645/2387 secuencias (aritmética 7649−5+1 / 2391−5+1 verificada); hiperparams v1 registrados (hidden=32, dropout=0.2, lr=0.01, batch=64, epochs=20, L2Loss+adam). |
| 1.3 | Baseline binario v1 regenerado | **PASS** | `baseline_v1_binary_metrics.json` regenerado desde `preds_test.csv`. **Verificación del auditor:** comparación campo a campo contra `lstm_fantasma/binary_metrics_test.json` → MATCH exacto en las 5 métricas × 4 ventanas y las 16 celdas de confusión (n=2387, threshold=1). El hash de archivo difiere solo por serialización (clave extra `_baseline`); el contenido métrico es idéntico. |

### Baseline v1 de comparación (test julio, n=2387)

| Ventana | acc | precision | recall | specificity | F1 | TP/FP/TN/FN |
|---|---:|---:|---:|---:|---:|---|
| y3 | 0.4755 | 0.7108 | 0.3197 | 0.7613 | 0.4411 | 494/201/641/1051 |
| y5 | 0.5689 | 0.7682 | 0.5642 | 0.5806 | 0.6506 | 958/289/400/740 |
| y10 | 0.6778 | 0.8276 | 0.7461 | 0.4252 | 0.7848 | 1402/292/216/477 |
| y15 | 0.7151 | 0.8533 | 0.7889 | 0.3756 | 0.8198 | 1547/266/160/414 |

Regresión v1 (`metrics_test.json`): MAE y3 0.909 / y5 1.311 / y10 2.149 / y15 2.809; RMSE 1.143 / 1.669 / 2.753 / 3.581.

---

## Gate Fase 2 (entrenamiento): **SÍ**

Cumplidos los gates de Fase 0 (v1 intacto + workspace v2 limpio) y Fase 1 (baseline reproducible + dataset estable y documentado). Fase 2 debe correr en Fedora35/MXNet.

### Observación no bloqueante (llevar a Fase 2)

1. `MODELO_V2_TRABAJO.md` no repite el criterio de selección; ya está congelado en el plan maestro (gate Fase 2 + Fase 5: **primario menor MAE promedio de las 4 ventanas; secundario mayor F1 promedio; gate: MAE total ≤ v1 o, si sube, F1/bin_acc claramente mejor**). Se recomienda copiarlo al doc de trabajo al iniciar Fase 2 para tenerlo a la vista durante el grid.
2. Riesgos señalados por el propio CHECK (acertados): prevalencia positiva alta en y15 (P(≥1)=82% test → un trivial “siempre ≥1” ya da acc 0.82): exigir a v2 mejorar **F1 y specificity** en y10/y15, no solo accuracy. Y y3 es la ventana dura (F1 v1 0.44); el plan ya prioriza MAE.
3. Dataset congelado: cualquier mejora de v2 será atribuible al modelo, no a los datos.

## Historial de esta auditoría

- **Pasada 1 (~02:50):** Fase 0 FAIL (1/3) / Fase 1 FAIL documental; gate F2 NO. Correcciones pedidas: crear dir v2, `MODELO_V2_TRABAJO.md`, `CHECK_FASE0_FASE1_V2.md`, nota en ruta.
- **Pasada 2 (~02:55):** las 4 correcciones verificadas → Fase 0 PASS / Fase 1 PASS; **gate F2 SÍ**.
