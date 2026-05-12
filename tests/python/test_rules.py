"""REQ-SW-ANA-04: rules.load_rules accepts well-formed YAML, rejects malformed."""
from __future__ import annotations
from pathlib import Path
import pytest

from analyzer import rules as R


def test_load_rules_returns_rules_and_policy(tmp_path: Path):
    (tmp_path / "asil_policy.yaml").write_text(
        "thresholds:\n  cov_dec_pct_max: 5\n")
    (tmp_path / "validation.yaml").write_text(
        "rules:\n"
        "  - id: COV-DEC-01\n"
        "    when: 'coverage.bms_master.decision.coverage_pct < 95'\n"
        "    severity: minor\n"
        "    finding: 'decision coverage low'\n")
    rules, policy = R.load_rules(tmp_path)
    assert len(rules) == 1
    assert rules[0].id == "COV-DEC-01"
    assert rules[0].severity == "minor"
    assert policy["thresholds"]["cov_dec_pct_max"] == 5


def test_load_rules_rejects_missing_id(tmp_path: Path):
    (tmp_path / "bad.yaml").write_text(
        "rules:\n  - when: '1 == 1'\n    severity: info\n")
    with pytest.raises(KeyError):
        R.load_rules(tmp_path)


def test_load_rules_rejects_missing_when(tmp_path: Path):
    (tmp_path / "bad.yaml").write_text(
        "rules:\n  - id: X\n    severity: info\n")
    with pytest.raises(KeyError):
        R.load_rules(tmp_path)


def test_evaluate_premise_returns_true_on_satisfied_rule(tmp_path: Path):
    (tmp_path / "v.yaml").write_text(
        "rules:\n"
        "  - id: T1\n"
        "    when: 'a.b == 1'\n"
        "    severity: info\n")
    rules, _ = R.load_rules(tmp_path)
    ok, _used = R.evaluate_premise(rules[0], {"a": {"b": 1}})
    assert ok is True


def test_evaluate_premise_returns_false_when_fact_missing(tmp_path: Path):
    (tmp_path / "v.yaml").write_text(
        "rules:\n"
        "  - id: T1\n"
        "    when: 'a.b == 1'\n"
        "    severity: info\n")
    rules, _ = R.load_rules(tmp_path)
    ok, _ = R.evaluate_premise(rules[0], {})  # a.b missing
    assert ok is False
