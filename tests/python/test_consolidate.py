"""REQ-SW-DOC-01..03: consolidate.{build_full, build_slim, _empty_validator}."""
from __future__ import annotations
import json
from pathlib import Path
import pytest

from doc_generator import consolidate as C


@pytest.fixture
def mil_report():
    return {
        "timestamp": "20260101_120000",
        "suite":     "mil",
        "summary":   {"total": 2, "pass": 2, "fail": 0,
                      "error": 0, "skipped": 0},
        "results": [
            {"req_id": "REQ-LL-BMS-VMON-01", "name": "test_vmon_01",
             "status": "pass", "checks": []},
            {"req_id": "REQ-LL-BMS-VMON-02", "name": "test_vmon_02",
             "status": "pass", "checks": []},
        ],
    }


@pytest.fixture
def analysis_report():
    return {
        "summary": {"n_findings": 1, "verdict": "ok",
                    "by_severity": {"critical": 0, "major": 0,
                                    "minor": 1, "info": 0}},
        "findings": [
            {"id": "DEAD-01", "severity": "minor",
             "title": "unused branch", "locator": "bms_master/X"},
        ],
    }


def test_empty_validator_shape():
    """REQ-SW-DOC-02: stub for missing suite carries skipped=True."""
    e = C._empty_validator("sil")
    assert e["suite"] == "sil"
    assert e["skipped"] is True
    assert e["summary"]["total"] == 0
    assert e["results"] == []


def test_build_full_passes_inputs_through(mil_report, analysis_report):
    """REQ-SW-DOC-01: build_full preserves originals verbatim."""
    sil = C._empty_validator("sil")
    pil = C._empty_validator("pil")
    full = C.build_full(mil_report, sil, pil, analysis_report)
    assert full["validation"]["mil"] is mil_report
    assert full["validation"]["sil"] is sil
    assert full["analysis"] is analysis_report
    assert "project" in full and "name" in full["project"]


def test_build_slim_marks_skipped_suites(mil_report, analysis_report):
    """REQ-SW-DOC-02: skipped suites carry not_run=True + zero summary."""
    sil = C._empty_validator("sil")
    pil = C._empty_validator("pil")
    full = C.build_full(mil_report, sil, pil, analysis_report)
    slim = C.build_slim(full)
    assert slim["sil"]["not_run"] is True
    assert slim["pil"]["not_run"] is True
    assert slim["sil"]["summary"]["total"] == 0
    assert "mil" in slim and slim["mil"].get("not_run") is not True


def test_build_slim_kpis_only_count_present_suites(mil_report, analysis_report):
    """REQ-SW-DOC-03: kpis.suites_run reflects what actually ran."""
    sil = C._empty_validator("sil")
    pil = C._empty_validator("pil")
    full = C.build_full(mil_report, sil, pil, analysis_report)
    slim = C.build_slim(full)
    assert slim["kpis"]["suites_run"] == ["mil"]
    assert slim["kpis"]["tests_total"] == 2
    assert slim["kpis"]["tests_passed"] == 2


def test_slim_for_part1_omits_analysis(mil_report, analysis_report):
    full = C.build_full(mil_report, C._empty_validator("sil"),
                        C._empty_validator("pil"), analysis_report)
    slim = C.build_slim(full)
    p1 = C.slim_for_part1(slim)
    assert "analysis" not in p1
    assert {"mil", "sil", "pil"}.issubset(p1.keys())


def test_slim_for_part2_keeps_analysis_and_summaries(mil_report, analysis_report):
    full = C.build_full(mil_report, C._empty_validator("sil"),
                        C._empty_validator("pil"), analysis_report)
    slim = C.build_slim(full)
    p2 = C.slim_for_part2(slim)
    assert "analysis" in p2 and "validator_summary" in p2
    assert p2["validator_summary"]["sil"]["not_run"] is True
    assert "summary" in p2["validator_summary"]["mil"]


def test_consolidate_loads_from_files(tmp_path: Path, mil_report, analysis_report):
    """End-to-end: consolidate(mil_path, None, None, analysis_path)."""
    milp = tmp_path / "mil.json"
    anap = tmp_path / "ana.json"
    milp.write_text(json.dumps(mil_report))
    anap.write_text(json.dumps(analysis_report))
    full, slim = C.consolidate(milp, None, None, anap)
    assert full["validation"]["mil"]["summary"]["total"] == 2
    assert slim["sil"]["not_run"] is True
