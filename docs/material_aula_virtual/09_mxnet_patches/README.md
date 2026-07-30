# MXNet patches (Unidad 5) + smoke LSTM acústico

**Actualizado:** 2026-07-27 desde `C:\Users\bryan\Downloads\MXNet_patches (1).zip`.  
Zip anterior del aula: `MXNet_patches.zip` (contenido equivalente; se sobrescribió con la copia `(1)`).

## Contenido

| Ruta | Origen |
|---|---|
| `AI/MXNet/**/*.pm`, `sml.pm`, `python/mxnet/gluon/block.py` | `MXNet_patches (1).zip` |
| `lstm_prueba_acustica/` | `LSTM.zip` (smoke test de que los patches cargan) |

Omitido a propósito: `sml.pm~` (backup de editor).

## Instalación en Fedora35 (WSL)

Ver **Paso 0** en `docs/RUTA_FINAL_MODELOS.md`. Resumen: copiar **todos** los `.pm` del zip sobre la instalación `AI::MXNet` del sistema, ajustar dueño/permisos (`chown` / `chmod 644`), y correr el `.pl` de `lstm_prueba_acustica/` solo como prueba de entorno.

**Aplicado en Fedora35 (2026-07-27):** raíz `/usr/local/share/perl5/5.34/`, usuario `bryan`, smoke LSTM Acc 97.28% / AUC 0.99.
