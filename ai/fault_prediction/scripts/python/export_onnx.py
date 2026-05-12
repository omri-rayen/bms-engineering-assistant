"""Export best.pt as ONNX with z-score normalisation baked in.

Reads  : models/best.pt, data/preprocessed/stats.json
Writes : model/fault_predictor/inference/fault_predictor.onnx
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn

from model import FaultLSTM

ROOT      = Path(__file__).resolve().parents[2]
REPO_ROOT = ROOT.parent.parent
MODEL_DIR = ROOT / "models"
DATA_DIR  = ROOT / "data" / "preprocessed"
INF_DIR   = REPO_ROOT / "model" / "fault_predictor" / "inference"
INF_DIR.mkdir(parents=True, exist_ok=True)


class DeployModel(nn.Module):
    """Inference-only wrapper: raw window -> per-class probabilities."""

    def __init__(self, base: nn.Module, mu: np.ndarray, sig: np.ndarray):
        super().__init__()
        self.base = base
        # Stored as buffers so they are baked into the ONNX graph.
        self.register_buffer("mu",  torch.from_numpy(mu.astype(np.float32)))
        self.register_buffer("sig", torch.from_numpy(sig.astype(np.float32)))

    def forward(self, window):
        # window : [B, T, F] raw features
        x = (window - self.mu) / self.sig
        return torch.sigmoid(self.base(x))


def main() -> None:
    state = torch.load(MODEL_DIR / "best.pt", map_location="cpu")
    stats = json.loads((DATA_DIR / "stats.json").read_text())

    mu  = np.asarray(stats["mean"], dtype=np.float32)
    sig = np.asarray(stats["std"],  dtype=np.float32)
    W   = int(stats["W"])
    F   = mu.size

    base = FaultLSTM(n_features=F)
    base.load_state_dict(state)
    base.eval()

    model = DeployModel(base, mu, sig).eval()

    dummy = torch.zeros(1, W, F, dtype=torch.float32)  # fixed shape: [1, W, F]
    out_path = INF_DIR / "fault_predictor.onnx"

    torch.onnx.export(
        model,
        dummy,
        out_path.as_posix(),
        input_names  = ["window"],
        output_names = ["prob"],
        opset_version = 17,
        dynamo = False,                 # legacy exporter -> single self-contained file
    )

    # Quick sanity check: run the exported graph and the PyTorch model.
    with torch.no_grad():
        probs = model(dummy).numpy().ravel()
    print(f"wrote {out_path}  ({out_path.stat().st_size/1024:.1f} kB)")
    print(f"  input shape  : (1, {W}, {F})")
    print(f"  output shape : (1, 3)")
    print(f"  zero-window probs (OT, OV, UV) = {probs.tolist()}")


if __name__ == "__main__":
    main()
