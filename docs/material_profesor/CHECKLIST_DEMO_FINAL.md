# Checklist proyector — demo final ML

Usar **la mañana del oral** (o la noche anterior). Criterio: terminal legible + comandos que ya probaron.

Companion: [`GUION_PRESENTACION_FINAL.md`](GUION_PRESENTACION_FINAL.md).  
**Modelo final (2026-07-28):** v2 simple (r06) en `Data/ml_out/lstm_fantasma_final/` → [`MODELO_FINAL_V2.md`](MODELO_FINAL_V2.md).  
**Diapositivas:** [`PRESENTACION_FINAL_ML.html`](PRESENTACION_FINAL_ML.html) (recomendado en proyector) · [`PRESENTACION_FINAL_ML.pdf`](PRESENTACION_FINAL_ML.pdf).  
**Métricas binarias:** `Data/ml_out/lstm_fantasma_final/binary_metrics_test.json` (si preguntan por precisión / confusion matrix / AUC).

---

## A. Hardware / sala (5 min)

- [ ] Laptop conectada a proyector / HDMI; resolución OK
- [ ] Fuente de terminal **grande** (14–18 pt) y contraste alto
- [ ] Zoom de ventana al 125–150% si el aula es grande
- [ ] Desactivar notificaciones / OneDrive popups
- [ ] WSL Fedora35 arranca; `echo $DISPLAY` no importa (demo es CLI)

---

## B. Paths y artefactos (obligatorio)

Desde el repo:

```bash
cd /mnt/c/Users/bryan/ia/proyecto_iaaa/Proyecto/ProyectoIAAA
```

- [ ] `Data/ml_out/lstm_fantasma_final/fantasma_lstm.params`
- [ ] `Data/ml_out/fantasma_test_norm.csv`
- [ ] `Data/ml_out/fantasma_norm_stats.json`
- [ ] `Data/ml_out/lstm_fantasma_final/metrics_test.json`
- [ ] `Data/ml_out/lstm_fantasma_final/preds_test.csv` (plan B)
- [ ] `scripts/demo_fantasma_predict.pl`

Comprobación rápida:

```bash
ls -la Data/ml_out/lstm_fantasma_final/fantasma_lstm.params \
       Data/ml_out/fantasma_test_norm.csv \
       Data/ml_out/fantasma_norm_stats.json \
       scripts/demo_fantasma_predict.pl
```

---

## C. Smoke pre-oral (hacer **antes** de entrar)

### C1. Demo predicción (principal)

```bash
perl -I. scripts/demo_fantasma_predict.pl --n 8
```

Esperado:

- [ ] Imprime `Modelo : Data/ml_out/lstm_fantasma_final/fantasma_lstm.params` y `hidden=48`
- [ ] Imprime `Cargando pesos` + `OK — modelo cargado`
- [ ] Tabla TRUE / PRED / err para `y3 y5 y10 y15`
- [ ] Snapshot MAE/RMSE al final (y3 ~0.82, y15 ~2.24)
- [ ] Sale con `FIN DEMO` y wall time razonable (típicamente < 60–90 s)

### C2. Eval-only (backup carga modelo)

```bash
perl -I. scripts/train_fantasma_lstm_v2.pl --eval-only \
  --model Data/ml_out/lstm_fantasma_final/fantasma_lstm.params \
  --out-dir /tmp/fantasma_final_eval \
  --hidden 48 --dropout 0.2 --batch-size 32 --seq-len 5
```

Esperado:

- [ ] `Cargando modelo ...`
- [ ] MAE/RMSE ≈ metrics_test.json del final (MAE prom ~1.49; y3 ~0.82)
- [ ] `OK` al final  
  **Nota:** `--out-dir /tmp/...` a propósito: escribe métricas/preds en `/tmp` y **no** toca `lstm_fantasma_final/` (verificado en Fase 5: reproducción byte-idéntica).

---

## D. Durante el oral

- [ ] Terminal ya en el `cd` correcto **antes** de empezar
- [ ] Comando demo en el portapapeles
- [ ] Plan B: `head -n 15 Data/ml_out/lstm_fantasma_final/preds_test.csv` si MXNet falla
- [ ] No lanzar extract full ni re-train
- [ ] Reloj visible (teléfono / compañero) — corte a demo a los ~6:30

---

## E. Frases de emergencia

| Si pasa… | Decir / hacer |
|---|---|
| Demo tarda | “Está cargando el test normalizado y los pesos; no reentrena.” |
| MXNet rompe | Abrir `preds_test.csv` y señalar `true_*` vs `pred_*` |
| Preguntan F1 | “F1 promedio 0.87 (0.81 en y3 → 0.91 en y15), binaria con umbral 0.5; detalle en `binary_metrics_test.json`.” |
| Preguntan TV literal | “Contrato Opción A (Perl); D2/D3 no reclamados.” |
| Preguntan t-SNE/GMM | “Paralelo si hay tiempo; el DOCX pide LSTM + extractor + demo.” |

---

## F. Post-demo (opcional, no oral)

- Variante CNN 1D + LSTM (opción 4b del plan, hoy omitida)
- Regenerar test extract post-fix AVWAP
- Paso 5 t-SNE→GMM→HMM si el grupo tiene bandwidth
