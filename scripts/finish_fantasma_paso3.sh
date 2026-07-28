#!/bin/bash
# Espera fin del train extract, copia a Data/ml_out y normaliza.
set -euo pipefail
ROOT="/mnt/c/Users/bryan/ia/proyecto_iaaa/Proyecto/ProyectoIAAA"
cd "$ROOT"
TRAIN_PID_FILE=/tmp/fantasma_train.pid
LOG=/tmp/fantasma_paso3_finish.log

exec > >(tee -a "$LOG") 2>&1

echo "[finish] start $(date -Is)"
TPID=$(cat "$TRAIN_PID_FILE" 2>/dev/null || true)
if [[ -n "${TPID}" ]] && kill -0 "$TPID" 2>/dev/null; then
  echo "[finish] waiting train PID=$TPID"
  while kill -0 "$TPID" 2>/dev/null; do
    sleep 60
    tail -1 /tmp/fantasma_train_abril_junio.log || true
  done
  echo "[finish] train process exited"
else
  echo "[finish] no live train PID; checking output exists"
fi

if [[ ! -f /tmp/fantasma_train_abril_junio.csv ]]; then
  echo "[finish] ERROR: missing /tmp/fantasma_train_abril_junio.csv" >&2
  exit 1
fi
if [[ ! -f /tmp/fantasma_test_julio.csv ]]; then
  echo "[finish] ERROR: missing /tmp/fantasma_test_julio.csv" >&2
  exit 1
fi

mkdir -p Data/ml_out
cp -v /tmp/fantasma_train_abril_junio.csv Data/ml_out/fantasma_train_abril_junio.csv
cp -v /tmp/fantasma_test_julio.csv Data/ml_out/fantasma_test_julio.csv
cp -v /tmp/fantasma_train_abril_junio.log Data/ml_out/fantasma_train_abril_junio.log
cp -v /tmp/fantasma_test_julio.log Data/ml_out/fantasma_test_julio.log

perl -I. scripts/normalize_fantasma_dataset.pl \
  --train Data/ml_out/fantasma_train_abril_junio.csv \
  --test  Data/ml_out/fantasma_test_julio.csv \
  --out-train Data/ml_out/fantasma_train_norm.csv \
  --out-test  Data/ml_out/fantasma_test_norm.csv \
  --stats     Data/ml_out/fantasma_norm_stats.json

echo "[finish] rows train=$(wc -l < Data/ml_out/fantasma_train_abril_junio.csv)"
echo "[finish] rows test=$(wc -l < Data/ml_out/fantasma_test_julio.csv)"
echo "[finish] OK $(date -Is)"
