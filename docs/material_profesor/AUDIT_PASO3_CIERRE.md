# Audit de cierre — Paso 3 (full extract + normalización)

**Fecha:** 2026-07-27  
**Rol:** auditor de cierre Paso 3 → gate Paso 4 LSTM.  
**Veredicto Paso 3:** **PASS_CON_RIESGOS**  
**Gate Paso 4 LSTM:** **SÍ**

---

## Resumen

| Ítem | Resultado |
|---|---|
| Full extract train abr–jun | **PASS** — 7649 muestras / 88 736 barras / ~2285 s |
| Full extract test jul | **PASS** — 2391 muestras / 24 179 barras / ~3075 s |
| Headers train=test=norm (104 cols) | **PASS** |
| Normalización z-score train-only | **PASS** — 86 features; stats persistidos |
| Exclusiones meta / y* / sgr_kind / ref_mid | **PASS** |
| Labels sin normalizar | **PASS** |
| Fix AnchoredVWAP `set_anchor` (sin preload `size()`) | **PASS** — causalidad de `get_point(i)` + perf |
| `prove -l t/43-avwap-auto.t t/41-anchored-vwap.t t/50-extract-fantasma-dataset.t` | **PASS** (82 tests, Fedora35) |
| Deuda test extract pre-fix AVWAP | **Aceptable** — regenerar **opcional** (no bloquea) |
| Gate Paso 4 LSTM | **SÍ** |

Estado en ruta: **HECHO_CON_DEUDA** (`docs/RUTA_FINAL_MODELOS.md`).

---

## Checklist datos

| Check | Esperado | Observado | Resultado |
|---|---|---|---|
| `fantasma_train_abril_junio.csv` | full pack, sin `--max-samples` | 7649 filas; log OK; contract A | **PASS** |
| `fantasma_test_julio.csv` | full pack julio | 2391 filas; log OK | **PASS** |
| Columnas crudas | mismo schema train/test | 104 cols; headers idénticos | **PASS** |
| Labels `y3/y5/y10/y15` | presentes; tip masa 0…3 | train y3 100% / y5 89.6% / y10 72.0% / y15 62.5% | **PASS** |
| Metadata `meta_*` | no entrenar | solo passthrough en norm | **PASS** |
| Timing train vs test | train post-fix AVWAP | train ~26 s/1k bars; test ~201 s/1k (pre-fix) | **INFO** |

---

## Checklist normalización

| Check | Esperado | Observado | Resultado |
|---|---|---|---|
| Módulo + CLI | `NormalizeFantasmaDataset` + script | presentes y `perl -c` OK | **PASS** |
| Método | z-score fit solo train | `method=zscore`; `n_rows=7649` en stats | **PASS** |
| Features | 86 | `feature_columns` len=86; `stats.n_features=86` | **PASS** |
| Excluir `meta_*` / `time` | sí | en `excluded.meta_time` | **PASS** |
| Excluir `y3..y15` | sí | no en `feature_columns`; valores enteros en `*_norm` | **PASS** |
| Excluir `sgr_kind_*` | sí (categóricos v1) | 3 cols en `excluded.sgr_kind` | **PASS** |
| Excluir `ref_mid_pips` | sí (default) | `excluded.other=[ref_mid_pips]` | **PASS** |
| Apply a test con stats train | sí | test mean≠0 / std≠1 (p.ej. atr mean 0.23) | **PASS** |
| Train z ~ N(0,1) | sí | atr/vol/… mean≈0 std≈1 | **PASS** |
| Fórmula fila 0 | `(x-μ)/σ` | atr_1m match exacto vs JSON | **PASS** |
| Vacios → 0 | documentado | `missing_as_zero=1` | **PASS** |
| Artefactos | `*_norm.csv` + JSON | train ~12M / test ~3.8M / stats ~15K | **PASS** |
| Doc | `NORMALIZACION_FANTASMA.md` | alineado con corrida | **PASS** |

---

## Checklist tests / AVWAP

| Check | Resultado |
|---|---|
| `perl -I. -c Market/Indicators/AnchoredVWAP.pm` | **PASS** |
| `perl -I. -c Market/ML/NormalizeFantasmaDataset.pm` | **PASS** |
| `prove -l t/43-avwap-auto.t t/41-anchored-vwap.t t/50-extract-fantasma-dataset.t` | **PASS** (82) |
| Spot-check causalidad AVWAP | **PASS** — ver § siguiente |

### Spot-check causalidad AnchoredVWAP

**Bug pre-fix:** `set_anchor` precargaba `0..MarketData->size()-1` (historial completo del CSV en extract) y forzaba `_last_data_idx` al final → recompute O(N) por ancla / update (test julio ~51 min).

**Fix:** ya no precarga; OHLC solo vía `update_last` (Replay causal). Bench reportado 5k: 124 s → 12 s.

**¿Contamina features del test pre-fix?**  
`get_point($i)` lee VWAP **acumulativo** `anchor..i` (`_accumulate_index`). Aunque el pre-fix rellenara arrays hasta el final de la serie, el valor en el índice `i` del snapshot sigue siendo prefijo causal. Las 12 cols `pip_avwap_*` están 100% pobladas en train y test.

**Conclusión:** no hay fuga de futuro material en las features AVWAP usadas por el extractor. El riesgo residual es higiene (mismo binario / mismos tiempos), no integridad de labels ni de otras features.

---

## Deuda: test extract antes del fix AVWAP

| Pregunta | Respuesta |
|---|---|
| ¿Bloquea LSTM? | **NO** |
| ¿Hay que regenerar test extract? | **NO obligatorio** — **RECOMENDADO_OPCIONAL** (~50 min) si se quiere CSV test con el mismo path post-fix + re-norm |
| ¿Lanzar regen en esta auditoría? | **No** — barato pero no necesario para consistencia causal de X/y |

Si se regenera (opcional, fuera de gate):

```bash
cd /mnt/c/Users/bryan/ia/proyecto_iaaa/Proyecto/ProyectoIAAA
perl -I. scripts/extract_fantasma_dataset.pl \
  --csv Data/2026_07_24.csv \
  --out Data/ml_out/fantasma_test_julio.csv --pack full
perl -I. scripts/normalize_fantasma_dataset.pl
```

---

## Deuda aceptable (no bloquea Paso 4)

| Deuda | Nota |
|---|---|
| Test CSV generado pre-fix AVWAP | Higiene; valores AVWAP en `i` siguen siendo prefijo causal |
| `sgr_kind_*` sin one-hot | Omitidos v1; LSTM puede ignorarlos |
| `ref_mid_pips` excluido | Correcto (nivel abs.); flag CLI si se insiste |
| Imputación vacío→0 | Puede sesgar distancias ausentes; OK v1 |
| Canal / Fib temprano / EQH parciales | Deuda Paso 2; nulos condicionales |
| Ghosts D2/D3 | Deuda Paso 1; contrato A congelado |

---

## Gate Paso 4 — ¿entrenar LSTM?

| Pregunta | Respuesta |
|---|---|
| ¿Datos train/test normalizados listos? | **SÍ** (`fantasma_{train,test}_norm.csv` + `fantasma_norm_stats.json`) |
| ¿Matriz X definida? | **SÍ** — 86 cols en `feature_columns` del JSON |
| ¿Targets? | `y3,y5,y10,y15` sin normalizar |
| ¿Regenerar test antes de cablear LSTM? | **NO** (opcional después / antes de métricas finales si se quiere) |
| ¿CNN primero? | **NO** — LSTM simple (DOCX) |

**Gate: SÍ.**

### Siguiente comando / agente

```text
Agente Paso 4 LSTM: entrenar sobre Data/ml_out/fantasma_train_norm.csv
(features = fantasma_norm_stats.json → feature_columns; targets y3/y5/y10/y15;
seq_len≈5; sin CNN; guardar modelo; evaluar en fantasma_test_norm.csv).
```

---

## Veredicto final

**PASS_CON_RIESGOS**

- Full extract + normalización train-only correctos (7649 / 2391 / 86 feats).  
- AVWAP fix validado por tests; deuda test-pre-fix **no bloquea**.  
- **Gate Paso 4 LSTM abierto.**
