"""Preprocess the MIL fault dataset into windowed train/val/test splits.

dataset.mat -> preprocessed/{train,val,test}.npz  +  stats.json  +  split.json
Trip-level split (no trip appears in two sets).
"""

from __future__ import annotations

import csv
import json
import random
from pathlib import Path

import mat73
import numpy as np

# ---------------------------------------------------------------------------
ROOT      = Path(__file__).resolve().parents[2]
DATA_DIR  = ROOT / "data"
OUT_DIR   = DATA_DIR / "preprocessed"
MAT_PATH  = DATA_DIR / "dataset.mat"
LOG_PATH  = DATA_DIR / "log.csv"

W = 50    # BPTT window [samples]; inference is stateful so W only affects training unroll
S = 1     # stride [samples] (0.1 s = match runtime cadence, no subsampling)

FEATURES = ["Vmin", "Vmax", "SoC", "Tmax", "Tcool", "Ipack", "dVmin", "dTmax"]
LABELS   = ["OT", "OV", "UV"]

SEED = 42
SPLIT_RATIOS = (0.70, 0.15, 0.15)


# ---------------------------------------------------------------------------
def load_runs():
    """Return list of {X, Y, trip_id, scen_id, fault} dicts from dataset.mat + log.csv."""
    print(f"Loading {MAT_PATH.name} ...")
    d = mat73.loadmat(str(MAT_PATH))["results"]
    Xs, Ys, metas = d["X"], d["Y"], d["meta"]

    with LOG_PATH.open() as f:
        log = list(csv.DictReader(f))

    if len(log) != len(Xs):
        raise RuntimeError(f"log.csv ({len(log)}) and dataset ({len(Xs)}) length mismatch")

    runs = []
    for i, (X, Y, meta, row) in enumerate(zip(Xs, Ys, metas, log)):
        if not bool(meta["sim_ok"]) or X is None or Y is None:
            continue
        runs.append({
            "idx":     i,
            "trip_id": row["trip_id"],
            "scen_id": meta["scen_id"],
            "fault":   meta["fault"],
            "X":       np.asarray(X, dtype=np.float32),
            "Y":       np.asarray(Y, dtype=np.float32),
        })
    print(f"  {len(runs)} valid runs loaded.")
    return runs


def split_trips(runs):
    """Trip-level 70/15/15 split, guaranteeing UV and OT trips in val and test."""
    trip_ids = sorted({r["trip_id"] for r in runs})
    rng = random.Random(SEED)

    # Trips that actually produce positives for a given class.
    def trips_with(cls):
        return sorted({r["trip_id"] for r in runs if r["Y"][:, cls].sum() > 0})

    def reserve(pool, name):
        if len(pool) < 3:
            raise RuntimeError(f"Need >=3 {name} trips, got {len(pool)}")
        rng.shuffle(pool)
        return [pool[0]], [pool[1]], pool[2:]   # val, test, train

    uv_val, uv_test, uv_train = reserve(trips_with(2), "UV")
    ot_pool = [t for t in trips_with(0) if t not in uv_val + uv_test]
    ot_val, ot_test, ot_train = reserve(ot_pool, "OT")

    reserved = set(uv_val + uv_test + uv_train + ot_val + ot_test + ot_train)
    rest = [t for t in trip_ids if t not in reserved]
    rng.shuffle(rest)
    n_tr = round(len(rest) * SPLIT_RATIOS[0])
    n_va = round(len(rest) * SPLIT_RATIOS[1])

    splits = {
        "train": sorted(rest[:n_tr]              + uv_train + ot_train),
        "val":   sorted(rest[n_tr:n_tr + n_va]   + uv_val   + ot_val),
        "test":  sorted(rest[n_tr + n_va:]       + uv_test  + ot_test),
    }
    print(f"  Trips: {len(trip_ids)} -> train={len(splits['train'])} "
          f"val={len(splits['val'])} test={len(splits['test'])}")
    print(f"  UV trips: train={uv_train} val={uv_val} test={uv_test}")
    print(f"  OT trips: train={ot_train} val={ot_val} test={ot_test}")
    return splits


def window_run(X, Y, W, S):
    """Slide W-length windows with stride S. Label = Y at the window's last sample."""
    N = X.shape[0]
    if N < W:
        return np.empty((0, W, X.shape[1]), np.float32), np.empty((0, Y.shape[1]), np.float32)

    starts = np.arange(0, N - W + 1, S)
    Xw = np.stack([X[s:s + W] for s in starts]).astype(np.float32)
    Yw = Y[starts + W - 1].astype(np.float32)
    return Xw, Yw


def build_split(runs, trip_ids):
    """Window every run whose trip_id is in trip_ids, concatenate."""
    Xs, Ys, run_idx, trip_idx = [], [], [], []
    for r in runs:
        if r["trip_id"] not in trip_ids:
            continue
        Xw, Yw = window_run(r["X"], r["Y"], W, S)
        if Xw.shape[0] == 0:
            continue
        Xs.append(Xw)
        Ys.append(Yw)
        run_idx.append(np.full(Xw.shape[0], r["idx"], dtype=np.int32))
        trip_idx.append(np.array([r["trip_id"]] * Xw.shape[0]))

    return (np.concatenate(Xs),
            np.concatenate(Ys),
            np.concatenate(run_idx),
            np.concatenate(trip_idx))


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    runs   = load_runs()
    splits = split_trips(runs)

    print("Windowing ...")
    data = {name: build_split(runs, ids) for name, ids in splits.items()}

    # z-score from training set only (float64 accumulator avoids overflow on ~1e8 rows)
    Xtr = data["train"][0]
    flat = Xtr.reshape(-1, Xtr.shape[-1])
    mean = flat.mean(axis=0, dtype=np.float64).astype(np.float32)
    std  = flat.std(axis=0,  dtype=np.float64).astype(np.float32)
    std[std < 1e-8] = 1.0   # guard against constant features

    print("Per-feature stats (train):")
    for f, m, s in zip(FEATURES, mean, std):
        print(f"  {f:6s}  mean={m:+.4f}  std={s:.4f}")

    # Apply normalisation, save splits
    for name, (X, Y, ridx, tidx) in data.items():
        Xn = (X - mean) / std
        out = OUT_DIR / f"{name}.npz"
        np.savez_compressed(out, X=Xn.astype(np.float32), Y=Y.astype(np.float32),
                            run_idx=ridx, trip_id=tidx)
        pos = Y.sum(axis=0).astype(int)
        print(f"  {name:5s}  X={Xn.shape}  Y_pos={dict(zip(LABELS, pos.tolist()))}  -> {out.name}")

    # Stats and split metadata
    (OUT_DIR / "stats.json").write_text(json.dumps({
        "features": FEATURES,
        "mean":     mean.tolist(),
        "std":      std.tolist(),
        "W":        W,
        "S":        S,
    }, indent=2))

    (OUT_DIR / "split.json").write_text(json.dumps({
        "seed":   SEED,
        "ratios": list(SPLIT_RATIOS),
        "trips":  splits,
    }, indent=2))

    print(f"\nDone. Artefacts in {OUT_DIR}")


if __name__ == "__main__":
    main()
