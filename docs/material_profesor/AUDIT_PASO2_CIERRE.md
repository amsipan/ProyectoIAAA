# Audit de cierre — Paso 2 (extractor fantasmita)

**Fecha:** 2026-07-27  
**Rol:** auditor de cierre (fixes mínimos solo si bloqueantes triviales).  
**Veredicto Paso 2:** **PASS_CON_RIESGOS**

---

## Resumen

| Ítem | Resultado |
|---|---|
| Módulo + CLI headless Opción A | **PASS** |
| Disparo aparición/reubicación provisional | **PASS** |
| Labels `y3/y5/y10/y15` | **PASS** (tras fix truncado `--max-samples`) |
| Features multi-TF 1m/10m/1h pack `full` | **PASS** (vacíos condicionales aceptables) |
| Causalidad features vs labels | **PASS** |
| `time` fuera de features de train | **PASS** (`meta_*` solamente) |
| `t/50-extract-fantasma-dataset.t` | **PASS** (26 tests, Fedora35) |
| Docs extractor + ruta | **PASS** (actualizados con este cierre) |
| Gate Paso 3 (full extract + normalización) | **SÍ** |

Estado en ruta: **HECHO_CON_DEUDA** (ver `docs/RUTA_FINAL_MODELOS.md`).

---

## Checklist

| Check | Esperado | Observado | Resultado |
|---|---|---|---|
| Disparo = cambio de punta provisional (`_prov_key`) | sí | `ExtractFantasmaDataset` L.143–175 | **PASS** |
| Contrato `meta_contract=A` | Opción A congelada Paso 1 | columna + valor `A` en smoke/test | **PASS** |
| Labels = trails creados en `(event_bar, event_bar+H]` | Opción A | `_count_trails_in_window`; test y3 vs PPH sintético | **PASS** |
| Horizontes 3/5/10/15 | sí | `@LABEL_HORIZONS`; columnas `y3…y15` | **PASS** |
| `feature_bar = event_bar + 1` | DOCX vela siguiente | `meta_feature_bar`; test | **PASS** |
| Features con estructura ≤ `event_bar` | causal | snapshot en `i=event_bar`; HTF solo velas **cerradas** | **PASS** |
| Futuro solo para `y*` | sí | trails posteriores al disparo; no entran al snapshot | **PASS** |
| PIP NQ = 0.25 | sí | `PIP_SIZE`; test `_pips` | **PASS** |
| ref = mid (H+L)/2 de vela del tip | DOCX | `_snapshot_features` | **PASS** |
| TF 1m / 10m / 1h | ≥3 TF DOCX | columnas `*_1m/*_10m/*_1h`; `MarketData` tiene `10m` | **PASS** |
| Features 1–11 presentes (o nulo condicional) | pack `full` | OB/FVG/Fib/AVWAP/AVP/HLD/BOS/EQH/SGR/DIY/canal en header smoke | **PASS** |
| Metadata `meta_time/date/hour/minute` no como feature train | no entrenar `time` | solo `meta_*`; no columna `time` cruda | **PASS** |
| Test `prove -l t/50` | PASS | **PASS** 26 tests (2026-07-27) | **PASS** |
| Smoke CLI | runnable | `--smoke --pack core --max-samples 10` OK (~1s) | **PASS** |

**Checklist global: PASS_CON_RIESGOS.**

---

## Spot-check causalidad

1. **Features:** se calculan en el bar del disparo (`event_bar`) con feed Replay `0…i`. HTF avanza solo hasta `_last_closed_tf_index` (excluye vela HTF en formación). HLD usa `chart_end_index => $i`.  
2. **Labels:** miran `@trail_created` con `t > event_bar && t <= event_bar+H` — futuro permitido **solo** para `y*`. El rastro creado en el mismo bar del disparo **no** entra en el label de esa muestra (exclusivo).  
3. **Predicción:** `meta_feature_bar = event_bar+1` (vela de referencia DOCX); features de estructura siguen siendo ≤ `event_bar` (documentado en `EXTRACTOR_FANTASMA.md`).  
4. **Train hygiene:** columnas de features = todo lo que no es `meta_*` ni `yN`; `time` crudo ausente.

---

## Fix mínimo aplicado en esta auditoría

**Bug:** con `--max-samples N` el loop hacía `last` en el bar del N-ésimo disparo → `@trail_created` incompleto → **subconteo sistemático** de `y10/y15` (y a veces `y3/y5`) en smoke. Evidencia pre-fix: 14 mismatches vs extract completo en 1 día de abril (`cut_trails=4` vs `full_trails=145`).

**Fix (~25 líneas en `Market/ML/ExtractFantasmaDataset.pm`):**
- Tras alcanzar `max_samples`, seguir alimentando hasta `event_bar + 15` (horizonte máx.) sin acumular más muestras.
- Descartar muestras con ventana `y15` incompleta al final de serie (`event_bar + 15 >= n`).

**Post-fix:** mismatches=0; `t/50` PASS; `perl -c` OK.

No se reescribió el extractor.

---

## Deuda aceptable vs bloqueante

### Aceptable (no bloquea Paso 3)

| Deuda | Nota |
|---|---|
| Canal auto vacío frecuente | Condicional DOCX; smoke abr-w1: 30/30 vacío — OK dejar nulo |
| Fib `*_1m` vacío al inicio (swing 150) | Calentamiento; HTF 10m/1h sí rellenan en smoke |
| EQH 1h / EQH·EQL 1m parciales | Serie corta / pocos equals — nulos OK |
| AVP `row_size=200` | Más ligero que TV 1000; documentado |
| Paridad TV fantasma D2/D3 | Deuda Paso 1.5; labels = Opción A (congelado) |
| `ref_mid_pips` = precio absoluto/PIP (no distancia) | Útil como escala; **excluir o tratar aparte** en normalización si se quiere evitar filtrar nivel de precio |
| `sgr_kind_*` categórico string | Feature condicional; encoding one-hot / omitir en LSTM v1 |
| Full run puede tardar horas | Esperado; no es defecto de contrato |
| Smokes CSV previos a este fix | Regenerar si se usan para métricas; full extract no usa `--max-samples` |

### Bloqueante (resuelto o no aplica)

| Ítem | Estado |
|---|---|
| Truncado labels con `--max-samples` | **Resuelto** en esta auditoría |
| Contaminación features con futuro | **No hallado** |
| Falta TF 10m | **No** — presente en `MarketData` + columnas |

---

## Gate Paso 3 — ¿lanzar extracción full + normalización?

| Pregunta | Respuesta |
|---|---|
| ¿Extractor Opción A listo para train/test completos? | **SÍ** |
| ¿Hay que esperar polish canal/Fib/EQH/paridad TV? | **NO** |
| ¿Entrenar LSTM ya? | **NO** — primero full CSV + normalización (Paso 3–4 de la ruta) |
| ¿Usar `--max-samples` en full? | **NO** |

**Gate: SÍ.**

### Comando recomendado (siguiente)

```bash
cd /mnt/c/Users/bryan/ia/proyecto_iaaa/Proyecto/ProyectoIAAA

# Train (puede tardar mucho; pack full)
perl -I. scripts/extract_fantasma_dataset.pl \
  --csv Data/2026_Abril-Junio.csv \
  --out Data/ml_out/fantasma_train_abril_junio.csv --pack full

# Test
perl -I. scripts/extract_fantasma_dataset.pl \
  --csv Data/2026_07_24.csv \
  --out Data/ml_out/fantasma_test_julio.csv --pack full
```

Luego Paso 3/4 de la ruta: **normalizar fit solo en train**, guardar parámetros, aplicar a test. **No** meter `meta_*` ni `time` en la matriz; decidir exclusión de `ref_mid_pips` / encoding de `sgr_kind_*` en ese paso.

Opcional previo (barato): regenerar smoke post-fix  
`perl -I. scripts/extract_fantasma_dataset.pl --smoke --pack core`  
(no bloquea el full).

---

## Veredicto final

**PASS_CON_RIESGOS**

- Extractor headless Opción A: disparo, labels 3/5/10/15, features multi-TF y causalidad OK.  
- Tests PASS; bug truncado `--max-samples` corregido.  
- Deuda de cobertura (canal/Fib temprano/EQH/D2–D3) documentada y no bloqueante.  
- **Gate Paso 3 abierto:** full extract train+test y después normalización.
