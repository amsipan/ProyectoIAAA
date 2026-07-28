# Guion oral — presentación final ML (≤10 min)

**Fecha:** 2026-07-28 (actualizado al modelo final v2)  
**Modelo final:** v2 simple (r06) en `Data/ml_out/lstm_fantasma_final/` → [`MODELO_FINAL_V2.md`](MODELO_FINAL_V2.md)  
**Criterio oral (27-jul):** muestreo correcto ≫ slides bonitas.  
**Checklist proyector:** [`CHECKLIST_DEMO_FINAL.md`](CHECKLIST_DEMO_FINAL.md)  
**Diapositivas:** [`PRESENTACION_FINAL_ML.html`](PRESENTACION_FINAL_ML.html) (proyector; ←/→, F fullscreen) · [`PRESENTACION_FINAL_ML.pdf`](PRESENTACION_FINAL_ML.pdf) · [`PRESENTACION_FINAL_ML.pptx`](PRESENTACION_FINAL_ML.pptx)  
**Métricas extra (vista binaria):** `Data/ml_out/lstm_fantasma_final/binary_metrics_test.json` (confusión TP/FP/TN/FN + accuracy/precision/recall/F1 + AUC por ventana)

Entorno: **WSL Fedora35**, raíz del repo montada:

```bash
cd /mnt/c/Users/bryan/ia/proyecto_iaaa/Proyecto/ProyectoIAAA
```

---

## Reloj (total ≈ 9:30 + 0:30 colchón)

| # | Bloque | Min | Quién habla |
|---|---|---:|---|
| 1 | Problema / objetivo | 1:00 | |
| 2 | Disparo fantasmita (Opción A) + extractor | 2:00 | |
| 3 | Features / TF / PIPs / normalización | 1:30 | |
| 4 | Split train abr–jun / test julio | 0:45 | |
| 5 | Métricas julio (MAE/RMSE + binaria/F1) | 1:30 | |
| 6 | **Demo en vivo** (cargar modelo + pred) | 2:30 | |
| 7 | Límites / deuda / cierre | 1:15 | |
| — | Buffer preguntas cortas | 0:30 | |

Si se atrasa: **recortar bloque 3** (decir “86 features z-score, 3 TF, PIPs; detalle en CSV”) y **no** abrir t-SNE.

---

## 1. Problema (≈1:00)

**Decir:**

> Queremos predecir, justo después de cada aparición o reubicación del fantasmita, **cuántos rastros “1”** dejará en los siguientes **3, 5, 10 y 15 minutos**.
>
> Son **4 salidas numéricas** (`y3,y5,y10,y15`). El modelo es un **LSTM de regresión** (sin CNN), entrenado con features de estructura/liquidez de la app.

**Mostrar (opcional, 5 s):** una frase en pizarra o terminal:

```text
objetivo: fantasma → conteos futuros de rastros (4 ventanas)
```

---

## 2. Disparo + extractor (≈2:00)

**Decir:**

> El muestreo **no** es “una fila por minuto”. Cada muestra = **aparición o reubicación** del fantasma (Opción A, alineada al Perl / comentario Josafa).
>
> En Replay 1m causal: estructura **previa** a la vela del evento; features en la **vela siguiente** (`feature_bar = event_bar + 1`).
>
> Labels = conteo automático de trails en `(event_bar, event_bar+H]`.

**Frase clave (oral 27):** *muestreo correcto importa más que la slide.*

**No hace falta correr el extract full en vivo** (train ~38 min). Si preguntan por evidencia:

```bash
# Solo mencionar paths (ya generados):
# Data/ml_out/fantasma_train_abril_junio.csv   (7649 muestras)
# Data/ml_out/fantasma_test_julio.csv          (2391 muestras)
ls -la Data/ml_out/fantasma_train_abril_junio.csv Data/ml_out/fantasma_test_julio.csv
```

Doc: `docs/material_profesor/EXTRACTOR_FANTASMA.md`.

---

## 3. Features / TF / PIPs (≈1:30)

**Decir:**

> Features = distancias en **PIPs** (NQ: 1 PIP = 0.25) del precio medio de la punta a niveles cercanos, en **≥3 TF: 1m, 10m, 1h**.
>
> Pack full: OB, FVG, Fib ZZ, AVWAP, POC/VAH/VAL, HLD 4h/D/W, BOS/CHoCH, EQH/EQL, DIY, canal (si aplica), ATR/vol…
>
> Tras normalización **train-only**: **86 columnas** z-score. Metadata `meta_*` y `time` **no** entran en X.

**Comando rápido (opcional, 10 s):**

```bash
perl -MJSON::PP -e 'print scalar(@{JSON::PP->new->decode(do{local$/;open my$f,"Data/ml_out/fantasma_norm_stats.json";<$f>})->{feature_columns}}), " features\n"'
```

---

## 4. Split (≈0:45)

**Decir:**

> Train = abril–junio (`2026_Abril-Junio.csv`). Test = 1–24 julio (`2026_07_24.csv`). Stats de normalización solo del train; el test se transforma con esos parámetros.

```text
train: 7649 filas → 7645 secuencias (seq_len=5)
test:  2391 filas → 2387 secuencias
```

---

## 5. Métricas (≈1:30)

**Decir (tabla grande en terminal o papel):**

| Target | MAE | RMSE | acc binaria | F1 |
|---|---:|---:|---:|---:|
| y3 | 0.82 | 1.01 | 0.71 | 0.81 |
| y5 | 1.15 | 1.41 | 0.75 | 0.85 |
| y10 | 1.75 | 2.15 | 0.81 | 0.89 |
| y15 | 2.24 | 2.77 | 0.83 | 0.91 |
| **prom.** | **1.49** | **1.84** | **0.78** | **0.87** |

> Métrica primaria DOCX: **regresión** (MAE/RMSE) y comparación vs etiquetado automático.  
> Vista binaria (≥1 rastro, pred ≥0.5): detecta **98–99%** de las ventanas con actividad (recall); F1 promedio **0.87**.  
> Modelo elegido por **validación causal** entre 8 configuraciones (early stopping); error medio **−17%** frente a la primera versión (1.79 → 1.49).  
> No rebalanceamos clases (oral 27).

**Comando de respaldo (métricas ya guardadas):**

```bash
cat Data/ml_out/lstm_fantasma_final/metrics_test.json
```

O smoke de carga completa (más lento; ver checklist):

```bash
perl -I. scripts/train_fantasma_lstm_v2.pl --eval-only \
  --model Data/ml_out/lstm_fantasma_final/fantasma_lstm.params \
  --out-dir /tmp/fantasma_final_eval \
  --hidden 48 --dropout 0.2 --batch-size 32 --seq-len 5
```

---

## 6. Demo en vivo (≈2:30) — **obligatoria**

**Preparación:** terminal ya en el `cd` del repo; fuente mono grande.

**Comando a pegar:**

```bash
perl -I. scripts/demo_fantasma_predict.pl --n 8
```

**Qué narrar mientras corre (~15–40 s de carga):**

1. “Carga el CSV de test **ya extraído y normalizado**.”  
2. “Arma ventanas `seq_len=5`.”  
3. “**Carga** `lstm_fantasma_final/fantasma_lstm.params` (modelo final, hidden 48) — no reentrena.”  
4. “Imprime TRUE (label auto) vs PRED (LSTM) para `y3/y5/y10/y15` en 8 puntos espaciados de julio.”

**Señalar en pantalla:** una fila donde pred ≈ true y otra con error visible → “el modelo no es magia; esto es la comparación pedida”.

**Variante si quieren índices concretos:**

```bash
perl -I. scripts/demo_fantasma_predict.pl --indices 0,200,500,1000,1500,2000,2300,2386
```

---

## 7. Límites y cierre (≈1:15)

**Decir sin dramatizar:**

1. **No** reclamamos paridad literal TradingView en Ghosts (deuda D1–D3 / Opción A).  
2. El modelo se eligió por **validación causal** (grid de 8 configuraciones, early stopping); una variante con capa densa extra **no mejoró** y se descartó.  
3. Cadena **t-SNE → GMM → HMM**: paralelo si hay tiempo; **no** está en el DOCX ni bloquea esta entrega.

**Cierre (15 s):**

> Entregamos extractor causal Opción A, 86 features multi-TF, LSTM (48 unidades) train abr–jun / eval julio con MAE promedio **1.49** y F1 promedio **0.87**, y demo de carga + predicción vs labels automáticos.

---

## Comandos exactos (copiar/pegar)

```bash
# 0) Ir al repo (Fedora35)
cd /mnt/c/Users/bryan/ia/proyecto_iaaa/Proyecto/ProyectoIAAA

# 1) DEMO PRINCIPAL (oral)
perl -I. scripts/demo_fantasma_predict.pl --n 8

# 2) Smoke eval-only (backup / si preguntan “¿cargó el modelo?”)
perl -I. scripts/train_fantasma_lstm_v2.pl --eval-only \
  --model Data/ml_out/lstm_fantasma_final/fantasma_lstm.params \
  --out-dir /tmp/fantasma_final_eval \
  --hidden 48 --dropout 0.2 --batch-size 32 --seq-len 5

# 3) Métricas JSON (si la demo falla y hay que improvisar)
head -n 20 Data/ml_out/lstm_fantasma_final/preds_test.csv
```

**No correr en oral:** re-extract full, re-train LSTM, t-SNE/GMM/HMM.

---

## Roles sugeridos (ajustar al grupo)

| Rol | Bloques |
|---|---|
| A — problema + disparo | 1–2 |
| B — features + split | 3–4 |
| C — métricas + límites | 5 + 7 |
| D — terminal demo | 6 |

Un solo orador también puede seguir el reloj de arriba.

---

## Material de apoyo (no obligatorio)

- Modelo final: `docs/material_profesor/MODELO_FINAL_V2.md` (selección Fase 5)  
- LSTM v2: `docs/material_profesor/LSTM_FANTASMA_V2.md` (grid + early stopping)  
- Ruta: `docs/RUTA_FINAL_MODELOS.md` (Paso 6)  
- Preds completas: `Data/ml_out/lstm_fantasma_final/preds_test.csv`
