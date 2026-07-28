# Patch demo Juan — mismatch arquitectura LSTM

## Síntoma

```
perl -I. scripts/demo_fantasma_predict.pl --n 8
Parameter 1.bias is missing in file Data/ml_out/lstm_fantasma_final/fantasma_lstm.params,
which contains parameters: 0_unfused.0.i2h_*, 0_unfused.0.h2h_*, 2.bias, 2.weight
```

## Causa

El modelo final v2 (r06) se guardó como **LSTM → Dropout → Dense**. El Dropout no tiene pesos pero ocupa el hijo `1`, así que Dense queda en `2.weight` / `2.bias`. El demo viejo construía **LSTM → Dense** (Dense = `1.*`) y fallaba al `load_parameters`.

## Fix

Actualizar solo `scripts/demo_fantasma_predict.pl` (no hace falta tocar `.params` ni reentrenar). El script nuevo:

- Defaults: `lstm_fantasma_final/`, `hidden=48`, `dropout=0.2`
- Auto-detecta `2.weight` (v2) vs `1.weight` (v1) y arma la red acorde
- Flags opcionales: `--dense-dropout` / `--no-dense-dropout`

## Qué hacer Juan

**Opción A (rápida):** reemplazar el archivo en su copia del zip:

```
scripts/demo_fantasma_predict.pl
```

por la versión parcheada del repo, luego:

```bash
cd ProyectoIAAA_ML   # o la carpeta extraída
perl -I. scripts/demo_fantasma_predict.pl --n 8
```

**Opción B:** re-extraer un zip regenerado que ya lleve el script corregido.

Los pesos en `Data/ml_out/lstm_fantasma_final/` no cambian.
