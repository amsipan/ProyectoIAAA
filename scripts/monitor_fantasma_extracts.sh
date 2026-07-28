#!/bin/bash
echo "=== PIDs ==="
echo -n "test="; cat /tmp/fantasma_test.pid 2>/dev/null; echo
echo -n "train="; cat /tmp/fantasma_train.pid 2>/dev/null; echo
echo "=== procs ==="
ps -o pid,etime,pcpu,pmem,rss,cmd -p "$(cat /tmp/fantasma_test.pid 2>/dev/null)","$(cat /tmp/fantasma_train.pid 2>/dev/null)" 2>/dev/null || ps aux | grep extract_fantasma | grep -v grep
echo "=== test log (tail) ==="
tail -20 /tmp/fantasma_test_julio.log 2>/dev/null || echo "(no log)"
echo "=== train log (tail) ==="
tail -20 /tmp/fantasma_train_abril_junio.log 2>/dev/null || echo "(no log)"
echo "=== out CSVs ==="
ls -lh /tmp/fantasma_test_julio.csv /tmp/fantasma_train_abril_junio.csv 2>&1 || true
exit 0
