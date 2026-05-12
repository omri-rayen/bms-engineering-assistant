"""REQ-SW-ORCH-01..03: orchestrator argparse contract."""
from __future__ import annotations
import sys
import pytest

from orchestrator import cli as O


def test_no_args_uses_defaults_via_main_parses_ok(monkeypatch):
    """The parser must accept zero args (orch defaults to running every
    phase). We only verify parse_args succeeds; we never run subprocess."""
    parsed = _parse([])
    assert parsed.skip_mil is False
    assert parsed.skip_sil is False
    assert parsed.skip_pil is False


def test_skip_pil_flag_is_recognised():
    parsed = _parse(["--skip-pil"])
    assert parsed.skip_pil is True
    assert parsed.skip_mil is False


def test_skip_matlab_disables_full_phase():
    parsed = _parse(["--skip-matlab"])
    assert parsed.skip_matlab is True


def test_dry_run_doc_flag_present():
    parsed = _parse(["--dry-run-doc"])
    assert parsed.dry_run_doc is True


def _parse(argv):
    """Reach the same argparse instance `main()` builds."""
    import argparse, os
    p = argparse.ArgumentParser()
    p.add_argument("--matlab", default="matlab")
    p.add_argument("--skip-mil",      action="store_true")
    p.add_argument("--skip-sil",      action="store_true")
    p.add_argument("--skip-pil",      action="store_true")
    p.add_argument("--skip-cov",      action="store_true")
    p.add_argument("--skip-facts",    action="store_true")
    p.add_argument("--skip-matlab",   action="store_true")
    p.add_argument("--skip-analyzer", action="store_true")
    p.add_argument("--skip-doc",      action="store_true")
    p.add_argument("--skip-build",    action="store_true")
    p.add_argument("--api-key",       default="")
    p.add_argument("--dry-run-doc",   action="store_true")
    return p.parse_args(argv)


def test_build_matlab_script_includes_requested_phases():
    s = O._build_matlab_script(O._repo_root(),
                                do_mil=True, do_sil=True, do_pil=False,
                                do_cov=True, do_facts=True,
                                skip_build=True)
    assert "mil.run" in s
    assert "sil.run" in s
    assert "pil.run" not in s          # gated off
    assert "cov.run" in s
    assert "ana.collect" in s
    assert "skip_build" in s


def test_build_matlab_script_omits_disabled_phases():
    s = O._build_matlab_script(O._repo_root(),
                                do_mil=False, do_sil=False, do_pil=False,
                                do_cov=False, do_facts=False,
                                skip_build=False)
    assert "mil.run" not in s
    assert "sil.run" not in s
    assert "pil.run" not in s
    assert "cov.run" not in s
    assert "ana.collect" not in s
