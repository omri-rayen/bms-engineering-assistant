"""Integration: doc_generator --dry-run end-to-end against fixture JSONs.

REQ-SW-DOC-01..05 happy path: validator JSONs in -> consolidated FULL +
SLIM JSONs out, with no LLM call.
"""
from __future__ import annotations
import json
import subprocess
import sys
from pathlib import Path


def _w(path: Path, obj):
    path.write_text(json.dumps(obj))


def _make_validator(suite: str) -> dict:
    return {
        "timestamp": "20260101_000000",
        "suite":     suite,
        "summary":   {"total": 1, "pass": 1, "fail": 0, "error": 0,
                      "skipped": 0},
        "results": [{
            "req_id": "REQ-LL-X-01",
            "id":     "REQ-LL-X-01",
            "name":   f"{suite}_smoke",
            "status": "pass",
            "checks": [{"name": "k", "status": "pass",
                        "value": 1, "expected": 1}],
        }],
    }


def _make_analysis() -> dict:
    return {
        "summary":  {"n_findings": 0, "verdict": "ok",
                      "by_severity": {}},
        "findings": [],
    }


def test_doc_generator_dry_run_writes_json(tmp_path: Path):
    mil_p = tmp_path / "MIL.json"
    sil_p = tmp_path / "SIL.json"
    pil_p = tmp_path / "PIL.json"
    ana_p = tmp_path / "ANALYSIS.json"
    _w(mil_p, _make_validator("mil"))
    _w(sil_p, _make_validator("sil"))
    _w(pil_p, _make_validator("pil"))
    _w(ana_p, _make_analysis())

    out_dir = tmp_path / "out"
    repo    = Path(__file__).resolve().parents[2]

    rc = subprocess.call(
        [sys.executable, "-m", "doc_generator",
         "--mil",      str(mil_p),
         "--sil",      str(sil_p),
         "--pil",      str(pil_p),
         "--analysis", str(ana_p),
         "--out",      str(out_dir),
         "--dry-run"],
        cwd=str(repo))
    assert rc == 0

    full = out_dir / "FULL_REPORT.json"
    slim = out_dir / "CONSOLIDATED.json"
    assert full.is_file(), "FULL_REPORT.json missing"
    assert slim.is_file(), "CONSOLIDATED.json missing"

    with full.open() as f:
        full_doc = json.load(f)
    assert full_doc["validation"]["mil"]["summary"]["pass"] == 1
    assert full_doc["validation"]["sil"]["summary"]["pass"] == 1
    assert full_doc["validation"]["pil"]["summary"]["pass"] == 1
