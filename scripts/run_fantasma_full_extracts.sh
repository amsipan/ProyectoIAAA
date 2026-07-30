#!/bin/bash
# Launcher full extracts train+test en /tmp (I/O local), logs con progreso.
set -euo pipefail
ROOT="/mnt/c/Users/bryan/ia/proyecto_iaaa/Proyecto/ProyectoIAAA"
cd "$ROOT"

cp -n Data/2026_Abril-Junio.csv /tmp/2026_Abril-Junio.csv 2>/dev/null || cp Data/2026_Abril-Junio.csv /tmp/2026_Abril-Junio.csv
cp -n Data/2026_07_24.csv /tmp/2026_07_24.csv 2>/dev/null || cp Data/2026_07_24.csv /tmp/2026_07_24.csv

# Matar runs previos del extractor
pkill -f 'scripts/extract_fantasma_dataset.pl' 2>/dev/null || true
sleep 1

rm -f /tmp/fantasma_test_julio.log /tmp/fantasma_train_abril_junio.log
rm -f /tmp/fantasma_test_julio.csv /tmp/fantasma_train_abril_junio.csv

nohup perl -I. scripts/extract_fantasma_dataset.pl \
  --csv /tmp/2026_07_24.csv \
  --out /tmp/fantasma_test_julio.csv \
  --pack full > /tmp/fantasma_test_julio.log 2>&1 &
echo $! > /tmp/fantasma_test.pid
echo "TEST_PID=$(cat /tmp/fantasma_test.pid)"

nohup perl -I. scripts/extract_fantasma_dataset.pl \
  --csv /tmp/2026_Abril-Junio.csv \
  --out /tmp/fantasma_train_abril_junio.csv \
  --pack full > /tmp/fantasma_train_abril_junio.log 2>&1 &
echo $! > /tmp/fantasma_train.pid
echo "TRAIN_PID=$(cat /tmp/fantasma_train.pid)"

echo "Logs: /tmp/fantasma_test_julio.log /tmp/fantasma_train_abril_junio.log"
