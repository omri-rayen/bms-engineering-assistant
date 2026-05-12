"""REQ-SW-ANA-01: facts.build_context + lookup."""
from __future__ import annotations
import json
from pathlib import Path

from analyzer import facts as F


def _write(path: Path, obj):
    path.write_text(json.dumps(obj))


def test_build_context_merges_facts_cov_validation(tmp_path: Path):
    facts = tmp_path / "facts.json"
    cov   = tmp_path / "cov.json"
    mil   = tmp_path / "mil.json"

    _write(facts, {"models": {"bms_master": {"static": {"blocks": 12}}}})
    _write(cov,   {"by_model": {"bms_master": {
        "execution": {"covered": 100, "total": 100, "coverage_pct": 100,
                      "dead_pct": 0}}}})
    _write(mil,   {"summary": {"total": 5, "pass": 5, "fail": 0,
                                "error": 0, "skipped": 0}, "results": []})

    ctx = F.build_context(facts, cov, mil, None, None, None,
                           policy={"thr": 1})
    assert ctx["model"]["bms_master"]["static"]["blocks"] == 12
    assert ctx["coverage"]["bms_master"]["execution"]["coverage_pct"] == 100
    assert ctx["validation"]["mil"]["passed"] == 5
    assert ctx["policy"] == {"thr": 1}


def test_lookup_returns_missing_sentinel_for_unknown_path(tmp_path: Path):
    facts = tmp_path / "f.json"
    _write(facts, {"models": {}})
    ctx = F.build_context(facts, None, None, None, None, None, policy={})
    out = F.lookup(ctx, "model.does.not.exist")
    assert F.is_missing(out)


def test_lookup_finds_nested_value(tmp_path: Path):
    facts = tmp_path / "f.json"
    _write(facts, {"models": {"bms_master": {"static": {"depth": 7}}}})
    ctx = F.build_context(facts, None, None, None, None, None, policy={})
    assert F.lookup(ctx, "model.bms_master.static.depth") == 7


def test_build_context_indexes_requirements_by_id(tmp_path: Path):
    facts = tmp_path / "f.json"
    reqs  = tmp_path / "r.json"
    _write(facts, {"models": {}})
    _write(reqs, {"low_level": [
        {"id": "REQ-LL-X-01", "asil": "D"},
        {"id": "REQ-LL-Y-02", "asil": "B"},
    ]})
    ctx = F.build_context(facts, None, None, None, None, reqs, policy={})
    assert ctx["requirements"]["REQ-LL-X-01"]["asil"] == "D"
    assert ctx["requirements"]["REQ-LL-Y-02"]["asil"] == "B"
