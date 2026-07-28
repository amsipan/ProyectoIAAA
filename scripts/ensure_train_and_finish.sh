#!/bin/bash
set -euo pipefail
ROOT="/mnt/c/Users/bryan/ia/proyecto_iaaa/Proyecto/ProyectoIAAA"
cd "$ROOT"

# Asegurar PID correcto del train vivo
PID=$(pgrep -f 'extract_fantasma_dataset.pl --csv /tmp/2026_Abril-Junio.csv' | head -1 || true)
if [[ -z "$PID" ]]; then
  echo "No hay train corriendo; relanzando..."
  rm -f /tmp/fantasma_train_abril_junio.csv /tmp/fantasma_train_abril_junio.log
  nohup perl -I. scripts/extract_fantasma_dataset.pl \
    --csv /tmp/2026_Abril-Junio.csv \
    --out /tmp/fantasma_train_abril_junio.csv \
    --pack full > /tmp/fantasma_train_abril_junio.log 2>&1 &
  PID=$!
fi
echo "$PID" > /tmp/fantasma_train.pid
echo "TRAIN_PID=$PID"

# Finish hook (solo uno)
pkill -f 'finish_fantasma_paso3.sh' 2>/dev/null || true
sleep 1
nohup bash scripts/finish_fantasma_paso3.sh > /tmp/fantasma_paso3_finish_nohup.log 2>&1 &
echo $! > /tmp/fantasma_finish.pid
echo "FINISH_PID=$(cat /tmp/fantasma_finish.pid)"
ps -o pid,etime,pcpu,cmd -p "$PID"
