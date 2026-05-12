"""REQ-SW-ANA-02 (single-fire + forEach) and REQ-SW-ANA-03 (WIP downrank).
Also covers the locator emission (REQ-SW-ANA-05)."""
from __future__ import annotations
from pathlib import Path

from analyzer import rules as R
from analyzer import engine as E


def _load(tmp: Path, body: str):
    (tmp / "r.yaml").write_text("rules:\n" + body)
    return R.load_rules(tmp)[0]


def test_rule_fires_once_per_run(tmp_path: Path):
    rules = _load(tmp_path,
        "  - id: ONCE\n"
        "    when: 'flag == 1'\n"
        "    severity: minor\n"
        "    finding: 'fired'\n")
    ctx = {"flag": 1}
    findings, trace = E.run_engine(rules, ctx)
    assert len(findings) == 1
    assert findings[0]["rule_id"] == "ONCE"
    assert sum(1 for t in trace if t["fired"]) == 1


def test_for_each_expands_per_binding(tmp_path: Path):
    rules = _load(tmp_path,
        "  - id: FE\n"
        "    forEach: { var: dead, in: deads }\n"
        "    when: 'dead.value > 0'\n"
        "    severity: minor\n"
        "    bind: { path: 'dead.path', value: 'dead.value' }\n"
        "    finding: 'dead {value} at {path}'\n")
    ctx = {"deads": [
        {"path": "bms_master/Sub/A", "value": 3},
        {"path": "bms_master/Sub/B", "value": 1},
        {"path": "bms_master/Sub/C", "value": 0},   # filtered by `when`
    ]}
    findings, _ = E.run_engine(rules, ctx)
    assert len(findings) == 2
    paths = sorted(f["evidence"]["values"]["path"] for f in findings)
    assert paths == ["bms_master/Sub/A", "bms_master/Sub/B"]


def test_wip_downrank_demotes_to_info(tmp_path: Path):
    """REQ-SW-ANA-03: a finding whose `path` lives under a WIP allowlist
    entry must be marked info+wip even if the rule said minor/major."""
    rules = _load(tmp_path,
        "  - id: WIP\n"
        "    when: 'sub.path != \"\"'\n"
        "    severity: major\n"
        "    bind: { path: 'sub.path' }\n"
        "    finding: 'x'\n")
    ctx = {
        "sub": {"path": "bms_master/Predictor/Inner"},
        "policy": {"wip_paths": ["bms_master/Predictor"]},
    }
    findings, _ = E.run_engine(rules, ctx)
    assert len(findings) == 1
    assert findings[0]["severity"] == "info"
    assert findings[0]["wip"] is True


def test_locator_command_emitted_for_block_paths(tmp_path: Path):
    """REQ-SW-ANA-05: a finding whose `path` looks like a Simulink
    block path includes a `hilite_system(...)` locator."""
    rules = _load(tmp_path,
        "  - id: LOC\n"
        "    when: 'sub.path != \"\"'\n"
        "    severity: minor\n"
        "    bind: { path: 'sub.path' }\n"
        "    finding: 'x'\n")
    ctx = {"sub": {"path": "bms_master/Sub/Block"}}
    findings, _ = E.run_engine(rules, ctx)
    assert findings[0]["locator"] == \
        "hilite_system('bms_master/Sub/Block')"


def test_summarize_picks_worst_severity(tmp_path: Path):
    findings = [
        {"severity": "info",  "category": "x"},
        {"severity": "minor", "category": "x"},
        {"severity": "major", "category": "y"},
    ]
    s = E.summarize(findings)
    assert s["verdict"] == "review_required"
    assert s["by_severity"]["major"] == 1
