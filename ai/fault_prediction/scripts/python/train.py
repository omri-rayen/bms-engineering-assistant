"""Train the LSTM fault predictor.

Weighted BCE + early stopping on val loss. Saves best.pt + per-class thresholds.
"""

from __future__ import annotations

import json
import random
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset

from model import FaultLSTM, count_params

# ---------------------------------------------------------------------------
ROOT      = Path(__file__).resolve().parents[2]
DATA_DIR  = ROOT / "data" / "preprocessed"
MODEL_DIR = ROOT / "models"
MODEL_DIR.mkdir(parents=True, exist_ok=True)

LABELS      = ["OT", "OV", "UV"]
W_MAX       = 25.0       # cap on per-class positive weight
BATCH       = 1024
LR          = 2e-3       # scaled with batch (linear rule)
MAX_EPOCHS  = 25
ES_PATIENCE = 5
LR_PATIENCE = 2
SEED        = 42


def seed_all(s):
    random.seed(s); np.random.seed(s); torch.manual_seed(s)


def load_split(name):
    d = np.load(DATA_DIR / f"{name}.npz", allow_pickle=True)
    return torch.from_numpy(d["X"]), torch.from_numpy(d["Y"])


def class_pos_weight(Y):
    """w_c = N_neg / N_pos, clipped to W_MAX (avoids UV dominating the loss)."""
    pos = Y.sum(dim=0).clamp(min=1)
    neg = Y.shape[0] - pos
    w   = (neg / pos).clamp(max=W_MAX)
    return w


def run_epoch(model, loader, criterion, device, optimizer=None):
    train_mode = optimizer is not None
    model.train(train_mode)

    total_loss, total_n = 0.0, 0
    all_y, all_p = [], []

    with torch.set_grad_enabled(train_mode):
        for xb, yb in loader:
            xb, yb = xb.to(device), yb.to(device)
            logits = model(xb)
            loss   = criterion(logits, yb)

            if train_mode:
                optimizer.zero_grad()
                loss.backward()
                optimizer.step()

            total_loss += loss.item() * xb.size(0)
            total_n    += xb.size(0)
            all_y.append(yb.detach().cpu().numpy())
            all_p.append(torch.sigmoid(logits).detach().cpu().numpy())

    return total_loss / total_n, np.concatenate(all_y), np.concatenate(all_p)


def _prf(yt, pt):
    tp = float(((pt == 1) & (yt == 1)).sum())
    fp = float(((pt == 1) & (yt == 0)).sum())
    fn = float(((pt == 0) & (yt == 1)).sum())
    prec = tp / (tp + fp) if tp + fp else 0.0
    rec  = tp / (tp + fn) if tp + fn else 0.0
    f1   = 2 * prec * rec / (prec + rec) if prec + rec else 0.0
    return prec, rec, f1


def per_class_metrics(y, p, thr=0.5):
    """Precision / recall / F1 per class. thr can be a scalar or per-class list."""
    thr = np.broadcast_to(np.asarray(thr, dtype=np.float32), (y.shape[1],))
    return [_prf(y[:, c], (p[:, c] >= thr[c]).astype(np.float32)) for c in range(y.shape[1])]


def best_thresholds(y, p, grid=None, beta=0.5):
    """Per-class threshold maximising F-beta (beta=0.5 favours precision) on val predictions."""
    if grid is None:
        grid = np.linspace(0.05, 0.95, 19)
    b2 = beta * beta
    thr = []
    for c in range(y.shape[1]):
        best, best_fb = 0.5, -1.0
        for t in grid:
            pr, rc, _ = _prf(y[:, c], (p[:, c] >= t).astype(np.float32))
            fb = (1 + b2) * pr * rc / (b2 * pr + rc) if (b2 * pr + rc) else 0.0
            if fb > best_fb:
                best_fb, best = fb, float(t)
        thr.append(best)
    return thr


def main():
    seed_all(SEED)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Device: {device}")

    Xtr, Ytr = load_split("train")
    Xva, Yva = load_split("val")
    print(f"Train: {tuple(Xtr.shape)}  Val: {tuple(Xva.shape)}")

    pos_w = class_pos_weight(Ytr)
    print("pos_weight (capped):",
          {l: round(w.item(), 2) for l, w in zip(LABELS, pos_w)})

    train_loader = DataLoader(TensorDataset(Xtr, Ytr), batch_size=BATCH,
                              shuffle=True,  num_workers=0, drop_last=True)
    val_loader   = DataLoader(TensorDataset(Xva, Yva), batch_size=BATCH,
                              shuffle=False, num_workers=0)

    model     = FaultLSTM().to(device)
    print(f"Model params: {count_params(model)}")

    criterion = nn.BCEWithLogitsLoss(pos_weight=pos_w.to(device))
    optimizer = torch.optim.Adam(model.parameters(), lr=LR)
    scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(
        optimizer, mode="min", factor=0.5, patience=LR_PATIENCE)

    best_val, bad_epochs = float("inf"), 0
    history = []

    for epoch in range(1, MAX_EPOCHS + 1):
        t0 = time.time()
        tr_loss, _, _      = run_epoch(model, train_loader, criterion, device, optimizer)
        va_loss, y_va, p_va = run_epoch(model, val_loader,  criterion, device)

        m = per_class_metrics(y_va, p_va, thr=0.5)
        scheduler.step(va_loss)
        lr_now = optimizer.param_groups[0]["lr"]

        log = {
            "epoch": epoch, "train_loss": tr_loss, "val_loss": va_loss,
            "lr": lr_now, "time_s": round(time.time() - t0, 1),
            **{f"{LABELS[c]}_f1@0.5": round(m[c][2], 3) for c in range(3)},
        }
        history.append(log)
        print(f"[{epoch:02d}]  tr={tr_loss:.4f}  va={va_loss:.4f}  "
              f"f1@0.5 OT={m[0][2]:.2f} OV={m[1][2]:.2f} UV={m[2][2]:.2f}  "
              f"lr={lr_now:.1e}  {log['time_s']}s")

        if va_loss < best_val - 1e-4:
            best_val, bad_epochs = va_loss, 0
            torch.save(model.state_dict(), MODEL_DIR / "best.pt")
        else:
            bad_epochs += 1
            if bad_epochs >= ES_PATIENCE:
                print(f"Early stopping (no improvement for {ES_PATIENCE} epochs).")
                break

    # Re-load best, pick thresholds on val
    model.load_state_dict(torch.load(MODEL_DIR / "best.pt", map_location=device))
    _, y_va, p_va = run_epoch(model, val_loader, criterion, device)
    thr = best_thresholds(y_va, p_va)
    print("Best per-class thresholds (val F1):",
          {l: round(t, 2) for l, t in zip(LABELS, thr)})

    m_thr = per_class_metrics(y_va, p_va, thr=thr)
    for l, (pr, rc, f1) in zip(LABELS, m_thr):
        print(f"  {l}: prec={pr:.3f}  rec={rc:.3f}  f1={f1:.3f}")

    (MODEL_DIR / "thresholds.json").write_text(json.dumps(
        {"labels": LABELS, "thresholds": thr, "val_f1": [m_thr[c][2] for c in range(3)]},
        indent=2))
    (MODEL_DIR / "history.json").write_text(json.dumps(history, indent=2))
    print(f"Saved best.pt, thresholds.json, history.json -> {MODEL_DIR}")


if __name__ == "__main__":
    main()
