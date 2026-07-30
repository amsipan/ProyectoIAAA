#!/bin/bash
set -euo pipefail
ROOT='/mnt/c/Users/bryan/Downloads/_test_ModuloPredictivo_run/ModuloPredictivo_Fantasma_LSTM'
cd "$ROOT"
echo "CWD=$(pwd)"
ls -lh /mnt/c/Users/bryan/Downloads/ModuloPredictivo_Fantasma_LSTM.zip

echo "=== perl -c ==="
for f in scripts/*.pl; do perl -I. -c "$f"; done

echo "=== py_compile ==="
python3 -m py_compile scripts/compute_fantasma_binary_metrics.py
echo OK_py

echo "=== DEMO n=4 ==="
perl -I. scripts/demo_fantasma_predict.pl --n 4
echo "DEMO_EC=$?"

echo "=== EVAL-ONLY ==="
perl -I. scripts/train_fantasma_lstm.pl --eval-only \
  --model Data/ml_out/lstm_fantasma/fantasma_lstm.params \
  --out-dir Data/ml_out/lstm_fantasma
echo "EVAL_EC=$?"

echo "=== BINARY METRICS ==="
python3 scripts/compute_fantasma_binary_metrics.py \
  --preds Data/ml_out/lstm_fantasma/preds_test.csv \
  --out /tmp/bin_metrics_check.json | tail -n 8
python3 - <<'PY'
import json
d=json.load(open('/tmp/bin_metrics_check.json'))
print('f1_avg', d.get('f1_avg'))
assert abs(d.get('f1_avg',0) - 0.8657) < 1e-3
print('binary_metrics OK')
PY

echo "=== HELP extract/normalize ==="
perl -I. scripts/extract_fantasma_dataset.pl --help | head -n 8
perl -I. scripts/normalize_fantasma_dataset.pl --help | head -n 8

echo "=== grep v2 ==="
if grep -RIn --include='*.pl' --include='*.pm' --include='*.py' --include='*.md' --include='*.txt' --include='*.json' -i 'v2' . ; then
  echo FAIL_v2_found; exit 3
else
  echo no_v2_ok
fi

echo ALL_PASS
