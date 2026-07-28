"""Compute binary confusion metrics (>=1 rastro) per target from preds_test.csv."""
import csv
import json

PREDS = r"C:\Users\bryan\ia\proyecto_iaaa\Proyecto\ProyectoIAAA\Data\ml_out\lstm_fantasma\preds_test.csv"
OUT = r"C:\Users\bryan\ia\proyecto_iaaa\Proyecto\ProyectoIAAA\Data\ml_out\lstm_fantasma\binary_metrics_test.json"

THRESH = 1.0
targets = ["y3", "y5", "y10", "y15"]

stats = {}
with open(PREDS, newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        for t in targets:
            tv = float(row[f"true_{t}"]) >= THRESH
            pv = float(row[f"pred_{t}"]) >= THRESH
            d = stats.setdefault(t, {"tp": 0, "fp": 0, "tn": 0, "fn": 0})
            if tv and pv:
                d["tp"] += 1
            elif not tv and pv:
                d["fp"] += 1
            elif not tv and not pv:
                d["tn"] += 1
            else:
                d["fn"] += 1

result = {"threshold": THRESH, "definition": "pos = >=1 rastro en la ventana; pred>=0.5 -> pos"}
for t, d in stats.items():
    tp, fp, tn, fn = d["tp"], d["fp"], d["tn"], d["fn"]
    n = tp + fp + tn + fn
    acc = (tp + tn) / n if n else 0.0
    prec = tp / (tp + fp) if (tp + fp) else 0.0
    rec = tp / (tp + fn) if (tp + fn) else 0.0
    spec = tn / (tn + fp) if (tn + fp) else 0.0
    f1 = 2 * prec * rec / (prec + rec) if (prec + rec) else 0.0
    result[t] = {
        "n": n,
        "confusion": {"tp": tp, "fp": fp, "tn": tn, "fn": fn},
        "accuracy": round(acc, 4),
        "precision": round(prec, 4),
        "recall": round(rec, 4),
        "specificity": round(spec, 4),
        "f1": round(f1, 4),
    }

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(result, f, indent=2, ensure_ascii=False)

print(json.dumps(result, indent=2, ensure_ascii=False))
