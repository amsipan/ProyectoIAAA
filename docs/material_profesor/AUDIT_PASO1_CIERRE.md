# Audit de cierre — Paso 1 (datos + Ghosts)

**Fecha:** 2026-07-27  
**Rol:** auditor de cierre (sin implementación).  
**Veredicto Paso 1 global:** **PASS_CON_RIESGOS**

---

## Resumen

| Ítem | Resultado |
|---|---|
| CSV train/test en `Data/` | **PASS** |
| GUI default `Data/2026_07_20.csv` intacto | **PASS** |
| Audit Ghosts vs `PivotPointsHL` | **PASS** (documento coherente) |
| Paridad labels “idénticos” al literal Pine | **FAIL / bloqueante** hasta contrato |
| Gate extractor (Paso 2) | **SÍ, solo bajo contrato Opción A** |

El Paso 1 **no está bloqueado** para arrancar el extractor headless, siempre que los labels se definan contra el **comportamiento actual Perl / comentario Josafa (Opción A)**, no contra el literal Pine con paints duplicados. Queda **deuda** D2/D3 documentada (no fix obligatorio antes del extractor).

Estado en ruta: **HECHO_CON_DEUDA** (ver `docs/RUTA_FINAL_MODELOS.md`).

---

## Checklist CSV

| Check | Esperado | Observado | Resultado |
|---|---|---|---|
| Existe `Data/2026_Abril-Junio.csv` | sí | sí (~5.45 MB) | **PASS** |
| Filas datos train | ~88 736 | **88 736** (88737 líneas − header) | **PASS** |
| Rango train | 2026-04-01 → 2026-06-30 | `2026-04-01T00:00:00-05:00` → `2026-06-30T23:59:00-05:00` | **PASS** |
| Existe `Data/2026_07_24.csv` | sí | sí (~1.48 MB) | **PASS** |
| Filas datos test | ~24 179 | **24 179** (24180 líneas − header) | **PASS** |
| Rango test | 2026-07-01 → 2026-07-24T15:59 | `2026-07-01T00:00:00-05:00` → `2026-07-24T15:59:00-05:00` | **PASS** |
| Header OHLCV | `time,open,high,low,close,Volume` | idéntico en train y test | **PASS** |
| `Data/2026_07_20.csv` intacto | no sobrescrito; default GUI | existe (~18 658 filas); `market.pl` sigue listando `Data/2026_07_20.csv` primero | **PASS** |
| Cableado GUI a abr–jun / jul-24 | no | no cableado (correcto) | **PASS** |

**Checklist CSV global: PASS.**

---

## Checklist Ghosts

Fuente audit: [`AUDIT_GHOSTS_VS_PIVOTPOINTS_HL.md`](AUDIT_GHOSTS_VS_PIVOTPOINTS_HL.md) — veredicto **ALINEADO_PARCIAL**.

### Spot-check (no re-auditoría completa)

| Check | Resultado | Evidencia |
|---|---|---|
| Copias `.txt` idénticas | **PASS** | SHA-256 `1B5D7931…CCA8` en aula y `docs/reference_indicators/ghosts_in_swings_josafa.txt` |
| Núcleo pivote / missed / causal Replay | **PASS** | Coherente con audit + `t/42` (rastro, reset+refeed) |
| D1 rastro `"1"` ≠ literal Pine | **bloqueante** (si se exige TV literal) | Pine L.371–374 + L.417–419 pinta `"1"` en punta actual (comentario “cambia de lugar” **no** está en el `if`); Perl `_update_rastro_from_provisional` solo si cambia punta, `"1"` en **previa** |
| D2 ventana `px1` | **bloqueante** (punta / reubicaciones) | Pine `for i = 0 to b - px1 - 1` **excluye** `px1`; Perl `_provisional` `$from .. $n` **incluye** `px1` |
| D3 desempate extremo | **bloqueante** (índice punta) | Pine `array.indexof` (serie nuevo→viejo) → más **reciente**; Perl primer extremo viejo→nuevo → más **antiguo** |
| D4–D9 (timing ticks, D5 missed, semilla, AVWAP fuera de alcance, doble paint) | aceptables / nota | No reabiertos; D9 refuerza que “idéntico literal” es ambiguo |
| Coherencia del audit con código | **PASS** | Fragmentos Perl + Pine releídos; el audit no inventa divergencias |

**Checklist Ghosts global: PASS (auditoría) / bloqueante para labels “idénticos TV” sin contrato.**

---

## Decisión de contrato labels (Opción A vs B)

| | Opción A | Opción B |
|---|---|---|
| Definición | Congelar comportamiento **actual Perl** ≈ **comentario** Josafa (“solo si se mueve”) | Portar bloque `barstate.islast` **literal** (L.371–374 + L.417–419) |
| Rastro `"1"` | Solo si la punta provisional cambia; marca en posición **previa** | Paint en punta **actual**; casi un `"1"` por barra confirmada (+ posible doble paint) |
| Ventana / tie-break | Aceptar inclusivo `px1` + desempate más antiguo **como contrato app** (deuda vs Pine) | Excluir `px1` + más reciente (y el resto del islast) |
| DOCX “idéntico” | Cumple la **intención** del indicador de muestreo / oral; no el source tal cual | Cumple literal ambiguo del `.txt` (paints duplicados D9) |
| Oral 27 (masa y3… en 0…3; muestreo correcto) | Encaja | Riesgo de conteos inflados / tip oral inválido |

### Recomendación del auditor: **Opción A**

**Por qué (pragmático para ML del curso):**

1. El DOCX pide implementación idéntica a Ghosts, pero el propio `.txt` **se contradice** (comentario vs código; doble `label.new` de `"1"`). “Idéntico literal” no es un contrato unívoco.
2. El oral prioriza **muestreo correcto** y tip. conteos **0…3**; eso encaja con “un `"1"` por salto”, no con un paint por cierre en punta.
3. El motor LuxAlgo de pivotes/missed ya es usable y causal (Replay). Congelar A permite etiquetar de forma **determinista y reproducible** con el código que ya pasa `t/42`.
4. Opción B sin validación con el profe arriesga labels inútiles para la demo oral.

### Mínimo antes del extractor

| Acción | ¿Obligatoria para gate? |
|---|---|
| Congelar por escrito **Opción A** (este documento) | **Sí** — hecho aquí |
| Fix código D1 (rastro) | **No** — A = comportamiento actual |
| Fix D2 (`px1` exclusivo) / D3 (desempate reciente) | **No** para gate A; quedan como **deuda opcional** Paso 1.5 si se quiere punta más cercana a TV **sin** cambiar la semántica del rastro |
| Port literal Pine (Opción B) | **No** — desaconsejado |
| Smoke Replay 1m / masa trails 0…3 en 1 día de abril | Recomendado **en paralelo** al extractor (smoke labels), no bloquea scaffold del script |

**No hay fix mínimo de ~10 líneas obligatorio** antes del Paso 2 bajo A. Cualquier alineación D2/D3 es trabajo de un worker Paso 1.5 / polish, no del extractor en sí.

---

## Gate Paso 2 — ¿se puede empezar el extractor?

| Pregunta | Respuesta |
|---|---|
| ¿Extractor asumiendo paridad TV literal? | **NO** |
| ¿Extractor headless anclado a `PivotPointsHL` actual + labels bajo **Opción A**? | **SÍ** |
| ¿Hay que esperar un port Pine completo? | **NO** |

**Gate: SÍ (condicionado a contrato A).**  
Disparo de muestra = aparición/reubicación del fantasma provisional según Perl.  
Labels `y3/y5/y10/y15` = conteo de trails `"1"` del mismo motor (no del literal islast TV).

---

## Veredicto final

**PASS_CON_RIESGOS**

- Datos train/test: listos.  
- Ghosts: auditado y coherente; labels TV-literal **no** cerrados.  
- Contrato recomendado y congelado para seguir: **Opción A**.  
- Deuda abierta: D2/D3 (y opcional smoke masa 0…3) — no bloquean scaffold del extractor bajo A.
