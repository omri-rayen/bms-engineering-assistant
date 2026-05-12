"""Repository-wide pytest configuration. Adds the repo root and the
analyzer python source path to sys.path so tests can import the modules
under test without installing them."""
from __future__ import annotations
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
for p in (ROOT, ROOT / "analyzer" / "python"):
    sp = str(p)
    if sp not in sys.path:
        sys.path.insert(0, sp)
