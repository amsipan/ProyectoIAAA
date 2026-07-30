# Material del aula virtual (curso IA / AA — EPN)

Carpeta de **revisión local** con el material descargado del OneDrive/aula el **2026-07-25**.
Los zips originales en `Downloads` **no se borraron**.

> **Git:** el contenido binario/PDF vive en disco para consultar; **no** se versiona en masa.
> Solo tiene sentido trackear este `README.md`, `00_inventario.md` y el `.gitignore` local.
> Ver `.gitignore` en esta carpeta (mp4, rpm, zip, CSVs de mercado, VAD_data).

## Árbol rápido

```
docs/material_aula_virtual/
  README.md
  00_inventario.md
  .gitignore
  01_perl_y_tensores/           # guías Perl + tensores
  02_servidor_jupyter_y_vpn/    # acceso Jupyter + notebooks
  03_bibliografia_brownlee/     # libros Brownlee (from scratch)
  04_entorno_citrix_fedora/     # certs/notas Citrix (sin ICAClient ~151 MB)
  05_datasets_ejemplo/          # CSV de ejercicios ML clásicos
  06_ml_supervisado_cap01_06/   # Caps. 1–6 + sesgo/varianza + spec Fase 1
  07_unidad4_recurrentes_hmm/   # Markov + HMM (Viterbi)
  08_unidad5_no_supervisado/    # t-SNE, GMM, PCA, LSTM, Proyecto Fase 2
  09_mxnet_patches/             # parches AI::MXNet + sml.pm (+ lstm_prueba_acustica/)
  10_indicaciones_finales_2026-07-27/  # DOCX final + CSV train abr-jun + CSV test jul
```

## Origen de cada zip

| Zip (Downloads) | Tamaño | Destino en esta carpeta |
|---|---:|---|
| `OneDrive_1_7-25-2026 (2).zip` | 165.7 MB | `01`–`05` (Perl, Jupyter, biblio, Citrix, datasets) |
| `OneDrive_1_7-25-2026 (1).zip` | 4.5 MB | `06` Caps. 1–3 + algoritmos paramétricos |
| `OneDrive_1_7-25-2026.zip` | 2.9 MB | `06` Caps. 4–6 + ajuste/sesgo + Proyecto Fase 1 |
| `OneDrive_2026-07-25 (1).zip` | 1.3 MB | `07` Unidad 4 (HMM / Markov) |
| `OneDrive_2026-07-25.zip` | 148.6 MB | `08` Unidad 5 (no supervisado + Proyecto) |
| `MXNet_patches.zip` | 0.1 MB | `09` parches MXNet (versión aula 25-jul) |
| `MXNet_patches (1).zip` | ~0.1 MB | `09` **actualización 2026-07-27** (sobrescribe `.pm` de arriba) |
| `LSTM.zip` | — | `09/lstm_prueba_acustica/` — smoke test patches (data acústica) |
| `OneDrive_1_7-27-2026.zip` | 6.9 MB | `10` indicaciones finales + CSV train/test |

## Qué hay en cada subcarpeta

### `01_perl_y_tensores/`
PDFs de arranque del stack Perl del curso: guía introductoria, manipulación de datos, tensores, hashes/arreglos, funciones y OO. Base para leer los `.pl` de las unidades.

### `02_servidor_jupyter_y_vpn/`
Guía de acceso al servidor Jupyter, manual VPN Netscaler, y notebooks `.ipynb` (Perl + Cap. 1–2). Útil si se trabaja en el aula remota; el proyecto de charting corre en WSL/local.

### `03_bibliografia_brownlee/`
Dos PDFs de Jason Brownlee (*ML Algorithms From Scratch*). Referencia teórica de los capítulos Perl del curso.

### `04_entorno_citrix_fedora/`
Notas y certificados para Citrix en Fedora. **Omitido** el RPM `ICAClient-rhel-…` (~151 MB); ver `OMITIDO_ICAClient_RPM.txt`. Sigue en el zip `(2)`.

### `05_datasets_ejemplo/`
Datasets clásicos (iris, pima, titanic, etc.) usados en los ejercicios de los capítulos. **No** son los OHLCV del proyecto (`Data/`).

### `06_ml_supervisado_cap01_06/`
Teoría + scripts `.pl` de evaluación, baselines, test harnesses, overfitting, sesgo/varianza, y la especificación del **Proyecto Fase 1** (visualización).

### `07_unidad4_recurrentes_hmm/`
Cadenas de Markov + HMM (diapositivas y ejercicio Viterbi tensorial). Relevantes para la meta del curso **HMM** (diferida, pero material contractual).

### `08_unidad5_no_supervisado/` — **pieza central Fase 2 / ML**
| Subcarpeta | Contenido | Relevancia proyecto |
|---|---|---|
| `t-SNE/` | PDF + `t-SNE.pl` | Reducción dimensional (meta ML) |
| `EM-GMM/` | PDF + `.pl` | Mezclas gaussianas (meta ML) |
| `PCA/` / `Pearson/` | PDF + `.pl` | Features / correlación |
| `k-Means/` | PDF + `.pl` | Clustering de referencia |
| `LSTM/` | Demo acústico VAD (`.pl`, `.pdf`, `.mdl`, CSV voz) | Ejemplo MXNet/LSTM del profe (no charting) |
| `Proyecto/` | Spec Fase 2, capturas TV, zigzag, CSV NQ, video | **Contrato del charting** |

### `09_mxnet_patches/`
Parches Perl (`AI/MXNet/**`) + `sml.pm` + un `block.py` de referencia. **Actualizados 2026-07-27** desde `MXNet_patches (1).zip`.  
Subcarpeta `lstm_prueba_acustica/` = contenido de `LSTM.zip` (script `.pl` + `VAD_data/`) para **probar que los patches funcionan** en Fedora35 antes del pipeline del proyecto. Ver `09_mxnet_patches/README.md` y Paso 0 de `docs/RUTA_FINAL_MODELOS.md`.

## Piezas CLAVE para ProyectoIAAA

1. **`08_unidad5_no_supervisado/Proyecto/`** — especificación 2ª fase, capturas de indicadores TV, zigzag, etiquetas HH/HL/LL/LH.
2. **`08_unidad5_no_supervisado/t-SNE/` + `EM-GMM/`** — teoría/código de la tubería ML del plan.
3. **`09_mxnet_patches/`** — runtime MXNet parcheado (**Paso 0** de la ruta: instalar en Fedora + smoke LSTM).
4. **`09_mxnet_patches/lstm_prueba_acustica/`** (y copia en `08_…/LSTM/`) — demo LSTM acústico (referencia Gluon/MXNet en Perl).
5. **`07_unidad4_recurrentes_hmm/`** — Markov/HMM.
6. **`06_…/Proyecto_Fase1_spec/`** — enunciado Fase 1 (ya entregada).
7. **`10_indicaciones_finales_2026-07-27/`** — DOCX oficial + CSV train/test.

## Deduplicación / omisiones

- **No** se copió `ICAClient-rhel-22.11.0.19-0.x86_64.rpm` (~151 MB).
- **No** se copió `sml.pm~` (backup editor).
- CSVs `2026_*.csv` del zip Unidad 5 se extrajeron aquí para revisión; el dataset canónico del app sigue siendo `Data/` (p. ej. `Data/2026_07_20.csv`).
- No había solapamiento total entre zips: cada OneDrive trae bloques distintos (Perl / Caps / U4 / U5). Solapes menores: PDFs Perl vs notebooks; `model.csv` en Cap. 4 y en `05_datasets_ejemplo`.

## Cómo reextraer algo omitido

```powershell
Expand-Archive -LiteralPath 'C:\Users\bryan\Downloads\OneDrive_1_7-25-2026 (2).zip' -DestinationPath $env:TEMP\od_reextract
# ICAClient queda en ...\Citrix-Fedora\
```

Detalle archivo por archivo: ver [`00_inventario.md`](00_inventario.md).
