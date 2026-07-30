# Inventario detallado — material aula virtual

Fecha de organización: **2026-07-25**.  
Ruta: `docs/material_aula_virtual/`.  
Total en disco tras organización: **~173 MB**, **114 archivos** (sin el RPM Citrix omitido).

Leyenda de relevancia:

| Etiqueta | Significado |
|---|---|
| **APP** | Directo al motor de charting / Fase 2 del proyecto |
| **ML** | Tubería t-SNE → GMM → HMM (meta del curso; diferida) |
| **MXNet** | Runtime / demos Gluon-Perl |
| **CURSO** | Teoría o ejercicios del aula (contexto) |
| **OPS** | Acceso VPN/Citrix/Jupyter (operativo, no código app) |

---

## 0. Zips fuente (intactos en Downloads)

| Archivo | Existe | Tamaño | Notas |
|---|---|---:|---|
| `C:\Users\bryan\Downloads\OneDrive_2026-07-25 (1).zip` | Sí | 1.32 MB | |
| `C:\Users\bryan\Downloads\OneDrive_1_7-25-2026 (2).zip` | Sí | 165.73 MB | |
| `C:\Users\bryan\Downloads\OneDrive_1_7-25-2026 (1).zip` | Sí | 4.49 MB | |
| `C:\Users\bryan\Downloads\OneDrive_1_7-25-2026.zip` | Sí | 2.94 MB | |
| `C:\Users\bryan\Downloads\OneDrive_2026-07-25.zip` | Sí | 148.57 MB | |
| `C:\Users\bryan\Downloads\MXNet_patches.zip` | Sí | 0.11 MB | versión aula 25-jul |
| `C:\Users\bryan\Downloads\MXNet_patches (1).zip` | Sí | ~0.1 MB | actualización 2026-07-27 → `09/` |
| `C:\Users\bryan\Downloads\LSTM.zip` | Sí | — | smoke → `09/lstm_prueba_acustica/` |

Ningún zip faltante ni corrupto (todos extrajeron OK).

---

## 1. `01_perl_y_tensores/` — origen: zip `(2)`

| Archivo | Tipo | Tamaño | Relevancia | Notas |
|---|---|---:|---|---|
| `01_Guia-introductoria-a-Perl.pdf` | pdf | 2.3 MB | CURSO | Stack del curso |
| `02_01_Data_Manipulation.pdf` | pdf | 2.7 MB | CURSO | |
| `02_Tensores.pdf` | pdf | 144 KB | MXNet/CURSO | Base para NDArray |
| `Funciones-y-OO.pdf` | pdf | 440 KB | CURSO | |
| `Hashes-y-arreglos.pdf` | pdf | 321 KB | CURSO | |

---

## 2. `02_servidor_jupyter_y_vpn/` — origen: zip `(2)`

| Archivo | Tipo | Tamaño | Relevancia | Notas |
|---|---|---:|---|---|
| `Guia_de_acceso_al_servidor_Jupyter.docx` | docx | 5.0 MB | OPS | |
| `Manual VPN NETSCALER para ingresar aula Doctor Josafa.pdf` | pdf | 0.9 MB | OPS | |
| `Jupyter-notebooks/01_Guia-introductoria-a-Perl.ipynb` | ipynb | 172 KB | CURSO | Paralel a PDF Perl |
| `Jupyter-notebooks/02_01_Data_Manipulation.ipynb` | ipynb | 147 KB | CURSO | |
| `Jupyter-notebooks/Chapter01-Load_Data_From_CSV.ipynb` | ipynb | 26 KB | CURSO | |
| `Jupyter-notebooks/Chapter02-Scale_Machine_Learning_Data.ipynb` | ipynb | 24 KB | CURSO | |

---

## 3. `03_bibliografia_brownlee/` — origen: zip `(2)`

| Archivo | Tipo | Tamaño | Relevancia |
|---|---|---:|---|
| `Jason Brownlee - Machine Learning Algorithms From Scratch (2018).pdf` | pdf | 1.1 MB | CURSO |
| `Jason Brownlee - Master Machine Learning Algorithms_ … (2016).pdf` | pdf | 1.1 MB | CURSO |

---

## 4. `04_entorno_citrix_fedora/` — origen: zip `(2)`

| Archivo | Tipo | Tamaño | Relevancia | Notas |
|---|---|---:|---|---|
| `Citrix-on-Fedora.txt` | txt | 2 KB | OPS | |
| `ctxusb-22.11.0.19-1.x86_64.rpm` | rpm | 158 KB | OPS | USB redirect |
| `epn-edu-ec.cert.pem` | pem | 3 KB | OPS | |
| `UserTrustRSACertificationAuthority.cert.pem` | pem | 2 KB | OPS | |
| `OMITIDO_ICAClient_RPM.txt` | txt | — | OPS | Apunta al RPM ~151 MB **no** copiado |

**Omitido deliberadamente:** `ICAClient-rhel-22.11.0.19-0.x86_64.rpm` (~151 MB) — sigue en el zip `(2)`.

---

## 5. `05_datasets_ejemplo/` — origen: `data.zip` dentro de zip `(2)`

Datasets de ejercicios (clasificación/regresión). **No** son velas NQ.

| Archivo | Tamaño aprox. | Relevancia |
|---|---:|---|
| `abalone.csv`, `iris.csv`, `pima-indians-diabetes.csv`, `Titanic.csv`, `winequality-white.csv`, `ionosphere.csv`, `sonar.all-data.csv`, `nba.csv`, `employees.csv`, `data_banknote_authentication.csv`, `seeds_dataset.csv`, `golf.csv`, `insurance.csv`, `model.csv`, `frutas.txt` | ~0.8 MB juntos | CURSO |
| `data.zip` | 254 KB | CURSO | Copia del zip anidado original |

---

## 6. `06_ml_supervisado_cap01_06/` — origen: zips `(1)` + sin sufijo

### Capítulos y teoría

| Ruta | Contenido clave | Relevancia |
|---|---|---|
| `Chapter01-Introduccion/` | `Introduccion2MachineLearning.pdf`, Load CSV | CURSO |
| `Chapter02-Escalamiento-de-Datos/` | PDF + diapos + `Chapter02.pl` | CURSO |
| `Chapter03-Metodos_de_particionamiento/` | hold-out / CV + `Chapter03.pl` | CURSO |
| `Algoritmos_parametricos/` | paramétricos vs no paramétricos | CURSO |
| `Chapter04-Evaluation_Metrics/` | métricas, ROC, `Chapter04_ROC.pl`, `model.csv` | CURSO |
| `Chapter05-Baseline_Models/` | random / rule-0 + `.pl` | CURSO |
| `Chapter06-Algorithm-Test-Harnesses/` | train/test y CV harnesses | CURSO |
| `Ajuste_de_modelos/` | overfitting / underfitting | CURSO |
| `Equilibrio_entre_Sesgo_y_Varianza/` | bias-variance | CURSO |
| `Proyecto_Fase1_spec/` | `Proyecto-Visualizacion-de-Datos-Parte1-v0.1.2.pdf` | **APP** (histórico Fase 1) |

Scripts `.pl` presentes: Cap. 02, 03, 04 (ROC), 05 (random, rule0), 06 (cv, train_test).

---

## 7. `07_unidad4_recurrentes_hmm/` — origen: `OneDrive_2026-07-25 (1).zip`

| Archivo | Tipo | Tamaño | Relevancia | Notas |
|---|---|---:|---|---|
| `HMMs/Diapositivas_HMM.pdf` | pdf | 326 KB | **ML** | HMM |
| `HMMs/Viterbi-tensorial-v0.3_ejercicio.docx` | docx | 7 KB | **ML** | Ejercicio Viterbi |
| `Markov-Chains/Cadenas_de_Markov_Diapositivas.pdf` | pdf | 280 KB | **ML** | |
| `Markov-Chains/Markov_Chains1.pdf` | pdf | 446 KB | **ML** | |
| `Markov-Chains/Markov_Chains3.pdf` | pdf | 290 KB | **ML** | |

---

## 8. `08_unidad5_no_supervisado/` — origen: `OneDrive_2026-07-25.zip`

### 8.1 Algoritmos

| Carpeta | Archivos | Relevancia | Para qué sirve |
|---|---|---|---|
| `t-SNE/` | `t-SNE.pdf` + 3 PDFs auxiliares + `t-SNE.pl` | **ML** | Reducción dimensional del plan |
| `EM-GMM/` | PDF + `Expectation_Maximization_EM_Algorithm.pl` | **ML** | GMM / EM |
| `PCA/` | PDF + `.pl` | **ML** | PCA de referencia |
| `Pearson/` | PDF + `.pl` | **ML**/CURSO | Correlación features |
| `k-Means/` | PDF + `.pl` | CURSO/ML | Clustering |

### 8.2 `LSTM/` — demo acústico (ejemplo del profe)

| Archivo | Tipo | Tamaño | Relevancia | Notas |
|---|---|---:|---|---|
| `09_02_02-Concise_Implementation_of_LSTM.pl` | pl | 13 KB | **MXNet** | Implementación concisa LSTM |
| `09_02_02-Concise_Implementation_of_LSTM.pdf` | pdf | 580 KB | **MXNet** | Notebook/PDF del demo |
| `09_02_02-Concise_Implementation_of_LSTM.mdl` | mdl | 4 KB | **MXNet** | Modelo guardado |
| `LSTM_ROC_Pause_predictions.png` | png | 33 KB | **MXNet** | Resultado VAD |
| `VAD_data/…/VAD_train1.csv` | csv | 4.5 MB | **MXNet** | Train voz (VAD) |
| `VAD_data/…/VAD_test1.csv` | csv | 4.1 MB | **MXNet** | Test voz |

**Importante:** es un LSTM de **detección de actividad de voz**, no de precios. Sirve como plantilla de cómo el curso usa `AI::MXNet` + Gluon en Perl (junto con `09_mxnet_patches`).

### 8.3 `Proyecto/` — contrato charting Fase 2

| Archivo | Tipo | Tamaño | Relevancia | Notas |
|---|---|---:|---|---|
| `Especificacion_Proyeto_2a_Fase.pdf` | pdf | 150 KB | **APP** | Spec oficial 2ª fase |
| `Indicador-zigzag-para-direccion-interna-externa.pdf` | pdf | 427 KB | **APP** | ZigZag / dirección |
| `Etiquetas-HH-HL-LL-LH.jpeg` | jpeg | 62 KB | **APP** | Estructura HH/HL/LL/LH |
| `Direccion-del-precio-interna-externa.mp4` | mp4 | **125 MB** | **APP** | Video explicativo (gitignored) |
| `2026_04.csv` … `2026_07_20.csv` | csv | ~6.3 MB | **APP** | Duplicados de `Data/` (gitignored aquí) |
| `Capturas-de-pantallas-configuracion-indicadores/*.jpg` | jpg | varios | **APP** | SMC, AVP, AVWAP, ZigZag, FVG… |
| `…/Smart Money Concepts Pro [Neon].txt` | txt | 38 KB | **APP** | Settings TV |
| `…/Ghosts_in_swings.txt` | txt | 21 KB | **APP** | Settings |

Las capturas alinean con la cola del feedback del profesor (SMC, liquidez, AVP/AVWAP, canal, etc.).

---

## 9. `09_mxnet_patches/` — origen: `MXNet_patches (1).zip` (actualizado 2026-07-27)

También: `LSTM.zip` → `lstm_prueba_acustica/`.

| Archivo | Relevancia | Rol |
|---|---|---|
| `sml.pm` | **MXNet** | Helpers del curso |
| `AI/MXNet/Base.pm`, `NS.pm`, `Types.pm`, `LinAlg.pm` | **MXNet** | Núcleo |
| `AI/MXNet/NDArray.pm` (+ `Base`, `Slice`) | **MXNet** | Tensores |
| `AI/MXNet/Gluon/{Block,Parameter,Loss}.pm` | **MXNet** | Gluon |
| `AI/MXNet/Gluon/NN/BasicLayers.pm` | **MXNet** | Capas |
| `AI/MXNet/Gluon/Data/Loader.pm` | **MXNet** | DataLoader |
| `python/mxnet/gluon/block.py` | **MXNet** | Referencia Python del parche |
| `lstm_prueba_acustica/LSTM/09_02_02-Concise_Implementation_of_LSTM.pl` | **smoke** | Probar patches (VAD acústico) |
| `lstm_prueba_acustica/LSTM/VAD_data/` | **smoke** | CSV train/test de voz |

Omitido: `sml.pm~` (backup).

Ver `09_mxnet_patches/README.md` y Paso 0 de `docs/RUTA_FINAL_MODELOS.md`.

---

## 10. Qué NO está en git (y por qué)

| Ítem | Motivo |
|---|---|
| Todo el árbol de PDFs/binarios de esta carpeta | Evitar `git add` masivo de material de aula (~173 MB; el video solo ya son 125 MB) |
| `*.mp4`, `*.rpm`, `*.zip` | `.gitignore` local |
| `08_…/Proyecto/*.csv` | Ya canónicos en `Data/` |
| `08_…/LSTM/VAD_data/` | Datasets de voz pesados; reextraíbles del zip U5 |
| `ICAClient-…rpm` | Ni siquiera está en disco aquí (~151 MB); solo en Downloads |
| Zips originales en Downloads | Pedido explícito: **no borrar** |

Si hace falta versionar solo la documentación:

```powershell
git add docs/material_aula_virtual/README.md docs/material_aula_virtual/00_inventario.md docs/material_aula_virtual/.gitignore
```

(No ejecutado automáticamente: esperar indicación explícita de commit.)

---

## 11. Mapa zip → carpeta (resumen)

```
OneDrive_1_7-25-2026 (2).zip  →  01, 02, 03, 04, 05
OneDrive_1_7-25-2026 (1).zip  →  06 (caps 1–3 + paramétricos)
OneDrive_1_7-25-2026.zip      →  06 (caps 4–6 + sesgo + Fase 1)
OneDrive_2026-07-25 (1).zip   →  07
OneDrive_2026-07-25.zip       →  08
MXNet_patches.zip             →  09 (versión 25-jul)
MXNet_patches (1).zip         →  09 (actualización 27-jul)
LSTM.zip                      →  09/lstm_prueba_acustica/
OneDrive_1_7-27-2026.zip      →  10
```
