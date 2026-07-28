"""Binary metrics (>=1 rastro) per target for the v2 model, from preds_test_v2.csv.

Single reporting convention: label pos = true>=1; predicted pos = pred>=0.5
(same rule as the v1 baseline binary_metrics_test.json, like-for-like).
Adds AUC per target and a Youden-optimal threshold computed on the same test
set, kept in a separate block and used only for discussion, never for the
reported metrics (no val preds artifact exists and nothing is re-trained).
"""
import argparse
import csv
import json

TARGETS = ["y3", "y5", "y10", "y15"]
LABEL_THRESH = 1.0
PRED_THRESH = 0.5


def load_rows(path):
    rows = []
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            rows.append(row)
    return rows


def confusion_at(rows, target, pred_thresh):
    d = {"tp": 0, "fp": 0, "tn": 0, "fn": 0}
    for row in rows:
        tv = float(row[f"true_{target}"]) >= LABEL_THRESH
        pv = float(row[f"pred_{target}"]) >= pred_thresh
        if tv and pv:
            d["tp"] += 1
        elif not tv and pv:
            d["fp"] += 1
        elif not tv and not pv:
            d["tn"] += 1
        else:
            d["fn"] += 1
    return d


def metrics_from_confusion(d):
    tp, fp, tn, fn = d["tp"], d["fp"], d["tn"], d["fn"]
    n = tp + fp + tn + fn
    acc = (tp + tn) / n if n else 0.0
    prec = tp / (tp + fp) if (tp + fp) else 0.0
    rec = tp / (tp + fn) if (tp + fn) else 0.0
    spec = tn / (tn + fp) if (tn + fp) else 0.0
    f1 = 2 * prec * rec / (prec + rec) if (prec + rec) else 0.0
    return {
        "n": n,
        "confusion": d,
        "accuracy": round(acc, 4),
        "precision": round(prec, 4),
        "recall": round(rec, 4),
        "specificity": round(spec, 4),
        "f1": round(f1, 4),
    }


def auc_rank(rows, target):
    # Mann-Whitney AUC: P(score_pos > score_neg) with average ranks for ties
    pairs = [
        (float(row[f"pred_{target}"]), float(row[f"true_{target}"]) >= LABEL_THRESH)
        for row in rows
    ]
    pairs.sort(key=lambda p: p[0])
    n_pos = sum(1 for _, pos in pairs if pos)
    n_neg = len(pairs) - n_pos
    if not n_pos or not n_neg:
        return None
    rank_sum_pos = 0.0
    i = 0
    while i < len(pairs):
        j = i
        while j + 1 < len(pairs) and pairs[j + 1][0] == pairs[i][0]:
            j += 1
        avg_rank = (i + 1 + j + 1) / 2.0
        for k in range(i, j + 1):
            if pairs[k][1]:
                rank_sum_pos += avg_rank
        i = j + 1
    return (rank_sum_pos - n_pos * (n_pos + 1) / 2.0) / (n_pos * n_neg)


def youden_threshold(rows, target):
    # Sweep candidate thresholds over the observed scores; maximize J = rec + spec - 1
    scores = sorted({float(row[f"pred_{target}"]) for row in rows})
    best = None
    for thr in scores:
        d = confusion_at(rows, target, thr)
        tp, fp, tn, fn = d["tp"], d["fp"], d["tn"], d["fn"]
        rec = tp / (tp + fn) if (tp + fn) else 0.0
        spec = tn / (tn + fp) if (tn + fp) else 0.0
        j = rec + spec - 1.0
        if best is None or j > best["youden_j"]:
            best = {"threshold": round(thr, 6), "youden_j": round(j, 4)}
            best.update(metrics_from_confusion(d))
    return best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preds", default=r"Data\ml_out\lstm_fantasma_v2\preds_test_v2.csv")
    ap.add_argument("--out", default=r"Data\ml_out\lstm_fantasma_v2\binary_metrics_test_v2.json")
    args = ap.parse_args()

    rows = load_rows(args.preds)
    result = {
        "model_version": "v2",
        "preds_source": args.preds,
        "label_threshold": LABEL_THRESH,
        "pred_threshold": PRED_THRESH,
        "definition": "pos = >=1 rastro en la ventana (true>=1); pred>=0.5 -> pos",
        "n_rows": len(rows),
    }
    f1s = []
    for t in TARGETS:
        m = metrics_from_confusion(confusion_at(rows, t, PRED_THRESH))
        m["n_pos"] = m["confusion"]["tp"] + m["confusion"]["fn"]
        auc = auc_rank(rows, t)
        m["auc"] = round(auc, 4) if auc is not None else None
        result[t] = m
        f1s.append(m["f1"])
    result["f1_avg"] = round(sum(f1s) / len(f1s), 4)

    # Informative only: best achievable threshold on this same test set (in-sample).
    youden = {}
    for t in TARGETS:
        youden[t] = youden_threshold(rows, t)
    result["youden_test_informative"] = {
        "note": "Optimo in-sample sobre el propio test; solo discusion, no usado en las metricas reportadas",
        "per_target": youden,
    }

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
