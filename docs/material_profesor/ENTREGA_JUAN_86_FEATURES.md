# Entrega Juan — lista de 86 features (TXT)

**Pedido (audio):** listar en un `.txt` las 86 dimensiones/features que usa el modelo, por si el profesor pregunta “¿cuáles está usando?”.  
**Transcripción:** [`TRANSCRIPCION_JUAN_SOLICITUD.md`](TRANSCRIPCION_JUAN_SOLICITUD.md)

## Archivo entregado

[`ENTREGA_JUAN_86_FEATURES.txt`](ENTREGA_JUAN_86_FEATURES.txt) — **86 líneas**, una feature por línea, sin cabecera.

Fuente canónica: `Data/ml_out/fantasma_norm_stats.json` → campo `feature_columns` (mismo orden que usan el trainer y la inferencia).

## v1 vs v2 / final

**NO se diferencian.** Las 86 features son **idénticas** (mismo orden, mismos nombres) en:

| Artefacto | `feature_columns` |
|---|---|
| `Data/ml_out/fantasma_norm_stats.json` | 86 cols |
| `Data/ml_out/lstm_fantasma/train_config.json` (v1) | **igual** |
| `Data/ml_out/lstm_fantasma_final/train_config.json` (v2/final) | **igual** |
| `Data/ml_out/lstm_fantasma_v2/train_config_v2.json` (espejo v2) | **igual** (mismo dataset congelado) |

Lo que cambia entre v1 y v2 son hiperparámetros y métricas (hidden 32→48, MAE/F1, etc.), **no** el vector de entrada X.

## Exclusiones (no van en las 86)

Del mismo stats JSON: `meta_*`, labels `y3/y5/y10/y15`, `sgr_kind_*` (categóricos string), `ref_mid_pips`.
