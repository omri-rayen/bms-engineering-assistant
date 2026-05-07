"""LSTM fault predictor.

Input  : [batch, W, n_features]
Output : [batch, n_classes] raw logits (multi-label).

Training uses raw logits with BCEWithLogitsLoss for numerical stability
(see train.py).  Evaluation and export wrap the model in `ProbWrapper`
so that the deployed network (ONNX -> Simulink) emits per-class
probabilities in [0, 1] directly; thresholding to boolean alarms is then
done downstream in Simulink against the values in thresholds.json.
"""

import torch
import torch.nn as nn


class FaultLSTM(nn.Module):
    def __init__(self, n_features=8, n_classes=3, hidden=32, dropout=0.2):
        super().__init__()
        self.lstm  = nn.LSTM(n_features, hidden, num_layers=1, batch_first=True)
        self.drop  = nn.Dropout(dropout)
        self.dense = nn.Linear(hidden, 16)
        self.relu  = nn.ReLU()
        self.head  = nn.Linear(16, n_classes)

    def forward(self, x):
        # x: [B, W, F] -> take last timestep of LSTM output
        out, _ = self.lstm(x)
        h = out[:, -1, :]
        h = self.drop(h)
        h = self.relu(self.dense(h))
        return self.head(h)              # logits, BCEWithLogits applies sigmoid


class ProbWrapper(nn.Module):
    """Wrap a logits-producing model with a sigmoid so the public output
    is per-class probabilities. Used by evaluate.py and export.py; never
    used at training time (training keeps logits + BCEWithLogitsLoss)."""

    def __init__(self, base: nn.Module):
        super().__init__()
        self.base = base

    def forward(self, x):
        return torch.sigmoid(self.base(x))


def count_params(model):
    return sum(p.numel() for p in model.parameters() if p.requires_grad)


if __name__ == "__main__":
    m = FaultLSTM()
    x = torch.zeros(2, 50, 8)
    print("logits :", m(x).shape, " params:", count_params(m))
    print("probs  :", ProbWrapper(m)(x).shape)
