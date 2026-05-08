"""Evaluate the trained LSTM on the test split.

Reports per-class precision/recall/F1, ROC-AUC, PR-AUC and a lead-time
histogram (how many seconds the model fires before the rule-based detector
would have crossed its threshold). Also writes false-alarm counts on the
nominal portion of test.
"""

from __future__ import annotations

import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import torch
from sklearn.metrics import average_precision_score, roc_auc_score
from torch.utils.data import DataLoader, TensorDataset

from model import FaultLSTM

# ---------------------------------------------------------------------------
ROOT      = Path(__file__).resolve().parents[2]
DATA_DIR  = ROOT / "data" / "preprocessed"
MODEL_DIR = ROOT / "models"
PLOT_DIR  = ROOT / "plots"
PLOT_DIR.mkdir(parents=True, exist_ok=True)

LABELS    = ["OT", "OV", "UV"]
DT        = 0.1   # sample period [s]
S         = 1     # window stride [samples] -- must match preprocess.py
BATCH     = 512
LOOKBACK_S = 20.0 # how far back (s) to scan for a pre-event prediction


def load_test():
    d = np.load(DATA_DIR / "test.npz", allow_pickle=True)
    return (torch.from_numpy(d["X"]),
            torch.from_numpy(d["Y"]),
            d["run_idx"],
            d["trip_id"])


def predict(model, X, device):
    loader = DataLoader(TensorDataset(X), batch_size=BATCH, shuffle=False)
    out = []
    model.eval()
    with torch.no_grad():
        for (xb,) in loader:
            out.append(torch.sigmoid(model(xb.to(device))).cpu().numpy())
    return np.concatenate(out)


def event_lead_times(y_true, y_pred, stride_s):
    """For every contiguous positive run in y_true, return the lead time
    (s) between the first positive prediction in [start - LOOKBACK, end]
    and the event start. Positive lead = predicted before truth.

    NOTE: y_true is anchored to the BMS WARN-level crossing (see
    run_and_extract.m: THR_OT/OV/UV are bms.*_warn, not shutdown). So
    the lead time computed here is "time between alarm and warn fault",
    which is the quantity gated by REQ-FP-04 (>= MIN_LEAD_S).
    """
    LOOKBACK = max(1, int(round(LOOKBACK_S / stride_s)))
    leads, n_events = [], 0

    padded = np.concatenate([[0], (y_true > 0).astype(int), [0]])
    edges  = np.diff(padded)
    starts = np.where(edges ==  1)[0]
    ends   = np.where(edges == -1)[0]    # exclusive

    for s, e in zip(starts, ends):
        n_events += 1
        lo = max(0, s - LOOKBACK)
        hits = np.where(y_pred[lo:e] > 0)[0]
        if hits.size:
            leads.append((s - (lo + hits[0])) * stride_s)

    return leads, n_events


def main():
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = FaultLSTM().to(device)
    model.load_state_dict(torch.load(MODEL_DIR / "best.pt", map_location=device))

    thr = json.loads((MODEL_DIR / "thresholds.json").read_text())["thresholds"]
    print("Thresholds:", dict(zip(LABELS, [round(t, 2) for t in thr])))

    Xte, Yte_t, run_idx, trip_id = load_test()
    Yte = Yte_t.numpy()
    print(f"Test: {tuple(Xte.shape)}")

    P = predict(model, Xte, device)            # [N, 3] sigmoid
    Yhat = (P >= np.array(thr)).astype(np.int8)

    # ---- Sample-level metrics --------------------------------------------
    rows = []
    for c, lbl in enumerate(LABELS):
        yt, pt = Yte[:, c], Yhat[:, c]
        tp = int(((pt == 1) & (yt == 1)).sum())
        fp = int(((pt == 1) & (yt == 0)).sum())
        fn = int(((pt == 0) & (yt == 1)).sum())
        prec = tp / (tp + fp) if tp + fp else 0.0
        rec  = tp / (tp + fn) if tp + fn else 0.0
        f1   = 2 * prec * rec / (prec + rec) if prec + rec else 0.0
        try:
            roc = roc_auc_score(yt, P[:, c])
            ap  = average_precision_score(yt, P[:, c])
        except ValueError:                  # only one class present
            roc, ap = float("nan"), float("nan")
        rows.append({"class": lbl, "prec": prec, "rec": rec, "f1": f1,
                     "roc_auc": roc, "pr_auc": ap, "tp": tp, "fp": fp, "fn": fn})

    print("\n=== Sample-level (test) ===")
    print(f"{'cls':<4}  prec   rec    f1    ROC    PR-AUC   TP     FP     FN")
    for r in rows:
        print(f"{r['class']:<4}  {r['prec']:.3f}  {r['rec']:.3f}  {r['f1']:.3f}  "
              f"{r['roc_auc']:.3f}  {r['pr_auc']:.3f}   "
              f"{r['tp']:6d} {r['fp']:6d} {r['fn']:6d}")

    # ---- Event-level lead times per run ----------------------------------
    print("\n=== Event-level lead times (per run, per class) ===")
    stride_s = S * DT                       # 0.1 s (stateful inference cadence)

    all_leads = {l: [] for l in LABELS}
    fa_counts = {l: 0  for l in LABELS}     # FA events on fully-nominal runs
    n_nominal_runs = 0

    for ri in np.unique(run_idx):
        mask = run_idx == ri
        is_nominal = (Yte[mask].sum() == 0)
        if is_nominal:
            n_nominal_runs += 1

        for c, lbl in enumerate(LABELS):
            yt = Yte[mask, c].astype(int)
            pt = Yhat[mask, c].astype(int)
            if yt.sum() == 0:
                if is_nominal:
                    fa = int((np.diff(np.concatenate([[0], pt, [0]])) == 1).sum())
                    fa_counts[lbl] += fa
                continue
            leads, _ = event_lead_times(yt, pt, stride_s)
            all_leads[lbl].extend(leads)

    for lbl in LABELS:
        L = np.array(all_leads[lbl])
        if L.size == 0:
            print(f"  {lbl}: no positive events in test split")
            continue
        print(f"  {lbl}: events={L.size:3d}  "
              f"median_lead={np.median(L):+.2f}s  mean={L.mean():+.2f}s  "
              f"early(>=0)={int((L >= 0).sum())}  late(<0)={int((L < 0).sum())}")

    print(f"\nFalse-alarm events on {n_nominal_runs} nominal test run(s):  {fa_counts}")

    # ---- REQ-FP-04 lead-time gate (>= MIN_LEAD_S vs warn fault) ---------
    MIN_LEAD_S = 5.0
    print(f"\n=== REQ-FP-04 gate: median lead-time vs warn fault >= {MIN_LEAD_S:.1f}s ===")
    lead_gate = {}
    for lbl in LABELS:
        L = np.array(all_leads[lbl])
        if L.size == 0:
            lead_gate[lbl] = {"median_s": None, "pass": None, "n_events": 0}
            print(f"  {lbl}: SKIP (no events)")
            continue
        med = float(np.median(L))
        ok = med >= MIN_LEAD_S
        lead_gate[lbl] = {"median_s": med, "pass": bool(ok), "n_events": int(L.size)}
        print(f"  {lbl}: median={med:+.2f}s  -> {'PASS' if ok else 'FAIL'}")

    # ---- Plots ------------------------------------------------------------
    fig, axes = plt.subplots(1, 3, figsize=(13, 3.5))
    for ax, lbl in zip(axes, LABELS):
        L = np.array(all_leads[lbl])
        if L.size:
            ax.hist(L, bins=20, color="steelblue", edgecolor="white")
            ax.axvline(0, color="k", ls="--", lw=0.8)
            ax.set_title(f"{lbl}  (n={L.size}, median={np.median(L):+.1f}s)")
        else:
            ax.set_title(f"{lbl}  (no events)")
        ax.set_xlabel("lead time [s]")
        ax.set_ylabel("count")
        ax.grid(alpha=0.3)
    fig.suptitle("Lead time per fault event (positive = predicted before threshold cross)")
    fig.tight_layout()
    fig.savefig(PLOT_DIR / "lead_time_hist.png", dpi=130)
    print(f"\nSaved plot -> {PLOT_DIR/'lead_time_hist.png'}")

    # Save raw report
    report = {
        "thresholds": dict(zip(LABELS, thr)),
        "sample_level": rows,
        "lead_time_s": {l: list(map(float, all_leads[l])) for l in LABELS},
        "lead_time_gate": {
            "min_lead_s": MIN_LEAD_S,
            "anchored_to": "BMS warn fault crossing (REQ-FP-04)",
            "per_class":   lead_gate,
        },
        "false_alarm_events_on_nominal": fa_counts,
        "n_nominal_runs": int(n_nominal_runs),
    }
    (MODEL_DIR / "test_report.json").write_text(json.dumps(report, indent=2))
    print(f"Saved report -> {MODEL_DIR/'test_report.json'}")


if __name__ == "__main__":
    main()
