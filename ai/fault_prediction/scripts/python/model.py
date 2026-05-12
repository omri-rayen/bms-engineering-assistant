"""LSTM fault predictor: [batch, W, features] -> [batch, n_classes] logits.

Use BCEWithLogitsLoss during training. Wrap with ProbWrapper for inference/export.
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
    """Sigmoid wrapper — used for inference/export, not during training."""

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
