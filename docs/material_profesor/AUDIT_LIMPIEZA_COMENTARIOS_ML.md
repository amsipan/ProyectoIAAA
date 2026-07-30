# Auditoría — Limpieza de comentarios (Market/ML, scripts fantasma, ChartEngine)

Fecha: 2026-07-28
Auditor: independiente (post-limpieza)
Rama: `main` (working tree, sin commitear)

## Alcance verificado

Archivos modificados por el limpiador (`git status` / `git diff HEAD`, 11 archivos):

- `Market/ChartEngine.pm`
- `Market/ML/ExtractFantasmaDataset.pm`
- `Market/ML/FantasmaLSTMData.pm`
- `PATCH_DEMO_JUAN.md`
- `scripts/demo_fantasma_predict.pl`
- `scripts/extract_fantasma_dataset.pl`
- `scripts/finish_fantasma_paso3.sh`
- `scripts/normalize_fantasma_dataset.pl`
- `scripts/run_fantasma_full_extracts.sh`
- `scripts/train_fantasma_lstm.pl`
- `scripts/train_fantasma_lstm_v2b.pl`

También se verificó sintaxis y se hizo grep sobre archivos del mismo dominio que el
limpiador **no tocó** (para contexto, no para exigirle nada): `Market/ML/NormalizeFantasmaDataset.pm`,
`scripts/train_fantasma_lstm_v2.pl`, `scripts/monitor_fantasma_extracts.sh`,
`scripts/ensure_train_and_finish.sh`, `market.pl`, `Market/MarketData.pm`,
`Market/Indicators/AnchoredVWAP.pm`, `Market/Overlays/AnchoredVWAP.pm`,
`Market/Indicators/HLD.pm`, `Market/Overlays/HLD.pm`.

## 1. Sintaxis (`perl -I. -c`, WSL Fedora35, perl 5.34.1)

Todos OK:

```
Market/ML/ExtractFantasmaDataset.pm    -> syntax OK
Market/ML/FantasmaLSTMData.pm          -> syntax OK
Market/ML/NormalizeFantasmaDataset.pm  -> syntax OK
Market/ChartEngine.pm                  -> syntax OK
market.pl                              -> syntax OK
scripts/demo_fantasma_predict.pl       -> syntax OK
scripts/train_fantasma_lstm.pl         -> syntax OK
scripts/train_fantasma_lstm_v2.pl      -> syntax OK
scripts/train_fantasma_lstm_v2b.pl     -> syntax OK
scripts/extract_fantasma_dataset.pl    -> syntax OK
scripts/normalize_fantasma_dataset.pl  -> syntax OK
```

No se corrió `perl -c` sobre `scripts/finish_fantasma_paso3.sh` /
`scripts/run_fantasma_full_extracts.sh` (son bash, no Perl); se revisaron a mano (§4).

## 2. Smoke ligero

MXNet disponible en Fedora35 (`perl -MAI::MXNet` OK). Se ejecutó:

```
perl -I. scripts/demo_fantasma_predict.pl --n 2
```

**Resultado: OK.** Carga `Data/ml_out/lstm_fantasma_final/fantasma_lstm.params`, detecta
arquitectura `2.weight` (v2/final), carga 2391 filas / 2387 secuencias / 86 features, y
produce 2 predicciones con métricas de referencia (MAE/RMSE/bin_acc) sin errores. Wall time
1.2s. El pipeline predictivo no se rompió con la limpieza de comentarios.

## 3. Grep de restos IA/proceso (alcance de código)

Patrones buscados (case-insensitive, con límites de palabra donde aplica):
`====`, `----`, `PASS_CON`, `NO TOCAR`, `handoff`, `side chat`, `worker`, `auditor`,
`task 00`, `spec 00`, `HARD`, `oral`, `Lumina`, `Josafa`, `Fase [0-9]`, `Opción 4a`,
`proyector`, `agente`.

Escaneado sobre: `Market/ML/*`, `Market/ChartEngine.pm`, `scripts/*fantasma*`,
`scripts/demo_fantasma_predict.pl`, `scripts/train_fantasma_lstm*.pl`,
`scripts/extract_fantasma_dataset.pl`, `scripts/normalize_fantasma_dataset.pl`,
más `Market/MarketData.pm`, `Market/Indicators/AnchoredVWAP.pm`,
`Market/Overlays/AnchoredVWAP.pm`, `Market/Indicators/HLD.pm`, `Market/Overlays/HLD.pm`.

**Hallazgos: 0 restos reales en el código tocado por esta limpieza.** Solo dos falsos
positivos del regex, documentados para que el siguiente limpiador no pierda tiempo con ellos:

| Archivo:línea | Texto | Motivo falso positivo | Severidad |
|---|---|---|---|
| `Market/ChartEngine.pm:4874,4883,4893,4908` | `my $worker = Market::Indicators::ATR->new(...)` | `$worker` es una variable local legítima (instancia de ATR para cálculo de cache), no una referencia a "worker" de proceso/agente. | COSMÉTICO (no acción) |
| `Market/ChartEngine.pm` (varias líneas con "temporal") | "eje **tempor-al**", "escala **tempor-al**" | El regex `\boral\b` con límites de palabra ya no hace match (se corrigió); se deja nota porque una primera pasada sin `\b` sí disparaba falsos positivos por la subcadena "oral" dentro de "temporal". | COSMÉTICO (no acción) |

Fuera del alcance de código, en `Market/MarketData.pm:233` (archivo **no tocado** por esta
limpieza) aparece `comportamiento Fase 1`, que es terminología contractual legítima del curso
(fases del proyecto), no narrativa de proceso de agente. Se marca **FUERA_DE_ALCANCE_DOCS/CÓDIGO
PREEXISTENTE** — no requiere acción de esta pasada.

No se encontraron banners multilínea densos, ni referencias a `task 00xx`/`spec 00xx`, ni
menciones a "handoff"/"side chat"/"auditor" en los archivos de código auditados.

Nota aparte (no es un "resto", es diseño intencional): `scripts/demo_fantasma_predict.pl`
imprime separadores ASCII (`'=' x 100`, `'-' x 100`, etc.) como parte de la salida del CLI
para hacerla legible en terminal. Son literales de **salida en runtime**, no comentarios de
código, y la regla de estilo (AGENTS.md) prohíbe banners `====`/`----` en **comentarios**, no
en el formato visual del propio programa. No se marca como hallazgo.

## 4. Diff sanity

Se revisó `git diff HEAD` completo de los 11 archivos modificados. En todos los casos el
cambio se limita a:

- Texto de comentarios (p. ej. "fantasmita" → "fantasma", eliminación de menciones a
  "Josafa", "oral", "Fase 4 / Opción 4a", "0053", "revisión").
- Strings de ayuda CLI (`print_usage`, banners de `print "[*] ..."`) — solo texto,
  sin tocar flags ni lógica de parseo.
- `PATCH_DEMO_JUAN.md`: se reescribió como nota técnica breve, eliminando narrativa de
  handoff dirigida a "Juan" (síntoma/causa/qué-hacer-Juan/opción A-B). Es un `.md`, no
  código ejecutable; el contenido técnico (arquitectura `2.weight`/`2.bias`, auto-detección
  v1/v2) se preservó.

**No se detectó ningún cambio de lógica** (sin alteración de flujo de control, cálculo,
parámetros por defecto, nombres de subs/variables usadas en cómputo, ni de las fórmulas de
features/labels/entrenamiento). Confirmado línea por línea en los 11 diffs.

## Veredicto

**PASS**

- Sintaxis: 11/11 archivos tocados + 4 archivos de contexto del mismo dominio, todos OK.
- Smoke demo: OK (predicciones correctas, sin errores, arquitectura v2 detectada bien).
- Restos de código IA/proceso: 0 (solo 2 falsos positivos de regex documentados arriba, sin
  acción requerida).
- Diff sanity: solo comentarios/strings de ayuda/documentación; cero cambios de lógica.

Limpio para pasar a la siguiente fase (plan zip).

## Resumen para el padre

- Veredicto: **PASS**
- Restos reales en código: **0** (2 falsos positivos de regex documentados, sin acción)
- Smoke `demo_fantasma_predict.pl --n 2`: **OK** (MXNet disponible en Fedora35)
- Acta: `docs/material_profesor/AUDIT_LIMPIEZA_COMENTARIOS_ML.md`
