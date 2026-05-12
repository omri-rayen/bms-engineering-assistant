"""Build two artefacts from the four raw reports:

  * `full`  -- the four original reports concatenated under stable
               keys with NO modification. The user keeps this file
               for deep inspection; every reference in the HTML
               points back into it via a JSON Pointer.

  * `slim`  -- a much smaller summary derived from `full`, attached
               with the JSON Pointer of the source row for every
               item. This is what the LLM sees when it writes the
               HTML, so it can quote references verbatim instead of
               having to invent them.

JSON Pointer reminder (RFC 6901): "" is the whole document, and a
slash-separated path drills in (e.g. `/validation/mil/results/3`
addresses the 4th MIL test in the full file).
"""
from __future__ import annotations

import json
from pathlib import Path


# ---------------------------------------------------------------- io

def _load(p: Path) -> dict:
    if not p.is_file():
        raise FileNotFoundError(f"Required report not found: {p}")
    with p.open(encoding="utf-8") as f:
        return json.load(f)


def _empty_validator(suite: str) -> dict:
    return {
        "timestamp": "",
        "suite":     suite,
        "summary":   {"total": 0, "pass": 0, "fail": 0,
                      "error": 0, "skipped": 0},
        "results":   [],
        "skipped":   True,
    }


def _trim(text: str, n: int) -> str:
    text = (text or "").strip().replace("\n", " ")
    return text if len(text) <= n else text[: n - 1].rstrip() + "\u2026"


# ---------------------------------------------------------------- full

def build_full(mil: dict, sil: dict, pil: dict, analysis: dict) -> dict:
    """Concatenate the four originals UNCHANGED. Every reference in
    the HTML must resolve against this exact structure."""
    return {
        "project": {
            "name":      "BMS Engineering Assistant",
            "system":    "EV battery, 96s1p Samsung-SDI, 1 master + 8 slaves",
            "asil":      "ASIL D context (per ISO 26262-6:2018)",
            "predictor": "Embedded LSTM fault predictor",
        },
        "validation": {
            "mil": mil,
            "sil": sil,
            "pil": pil,
        },
        "analysis": analysis,
    }


# ---------------------------------------------------------------- slim helpers

def _suite_summary(report: dict) -> dict:
    s = report.get("summary", {}) or {}
    total = s.get("total", 0) or 0
    passed = s.get("pass", 0) or 0
    rate = round(100.0 * passed / total, 2) if total else 0.0
    return {**s, "pass_rate_pct": rate}


def _slim_validator(report: dict, base_ref: str,
                    keep_passing_checks: bool) -> dict:
    """Slim a validator suite (MIL/SIL/PIL).

    For every test we keep req_id, name, status, the JSON Pointer
    that addresses its full record, and -- if it failed/erred or the
    suite is small (SIL/PIL) -- the failing check rows with their
    own JSON Pointers."""
    raw_results = report.get("results", [])
    # The full file is UNMODIFIED, so refs must match its real shape:
    # for a dict-shaped results we drop the index, for list-shaped we keep it.
    if isinstance(raw_results, dict):
        results = [raw_results]
        ref_for = lambda _i: f"{base_ref}/results"
    else:
        results = raw_results
        ref_for = lambda i: f"{base_ref}/results/{i}"

    tests = []
    for i, r in enumerate(results):
        status = r.get("status", "")
        ref    = ref_for(i)
        item = {
            "req_id": r.get("req_id", ""),
            "name":   _trim(r.get("name", ""), 80),
            "status": status,
            "ref":    ref,
        }
        if r.get("error"):
            item["error"] = _trim(r.get("error", ""), 160)

        # Keep checks for SIL/PIL (small) and for failing/error tests.
        checks_src = r.get("checks", [])
        if isinstance(checks_src, dict):
            checks_iter   = [checks_src]
            check_ref_for = lambda _j: f"{ref}/checks"
        else:
            checks_iter   = checks_src
            check_ref_for = lambda j: f"{ref}/checks/{j}"
        if checks_iter and (keep_passing_checks or status != "pass"):
            item["checks"] = [{
                "name":      c.get("name", ""),
                "status":    c.get("status", ""),
                "value":     c.get("value", ""),
                "threshold": c.get("threshold", ""),
                "ref":       check_ref_for(j),
            } for j, c in enumerate(checks_iter)]
        tests.append(item)

    return {
        "ref":     base_ref,
        "summary": _suite_summary(report),
        "tests":   tests,
    }


def _slim_analysis(report: dict, base_ref: str) -> dict:
    """Group analyzer findings by rule_id. Every rule entry carries
    the JSON Pointers of every raw finding it summarises so the
    reader can drill back into FULL_REPORT.json."""
    raw = report.get("findings", []) or []
    severity_rank = {"critical": 4, "major": 3, "minor": 2, "info": 1}

    by_rule: dict[str, dict] = {}
    for i, f in enumerate(raw):
        rid = f.get("rule_id", "") or "UNRULED"
        sev = f.get("severity", "info")
        ev  = f.get("evidence", {}) or {}
        path = (ev.get("values", {}) or {}).get("path") or ""
        ref  = f"{base_ref}/findings/{i}"

        slot = by_rule.get(rid)
        if slot is None:
            slot = {
                "rule_id":   rid,
                "category":  f.get("category", ""),
                "severity":  sev,
                "count":     0,
                "wip_any":   False,
                "finding":   _trim(f.get("finding", ""),    120),
                "reasoning": _trim(f.get("reasoning", ""),  140),
                "recommend": [_trim(r, 110)
                              for r in (f.get("recommend") or [])][:1],
                "refs":      [],         # JSON Pointers into the full file
            }
            by_rule[rid] = slot
        else:
            if severity_rank.get(sev, 0) > severity_rank.get(slot["severity"], 0):
                slot["severity"] = sev

        slot["count"]  += 1
        slot["wip_any"] = slot["wip_any"] or bool(f.get("wip", False))
        slot["refs"].append(ref)

    # Cap per-rule lists so the slim file stays compact.
    for slot in by_rule.values():
        slot["refs"] = slot["refs"][:3]

    grouped = sorted(
        by_rule.values(),
        key=lambda s: (-severity_rank.get(s["severity"], 0), -s["count"]),
    )

    summary = report.get("summary", {}) or {}
    return {
        "ref":     base_ref,
        "summary": summary,
        "rules":   grouped,
    }


# ---------------------------------------------------------------- slim entry

def build_slim(full: dict, full_filename: str = "FULL_REPORT.json") -> dict:
    v = full["validation"]
    a = full["analysis"]

    slim = {
        "project":     full["project"],
        "full_report": full_filename,
    }
    # Always emit a slot for every validator suite so the report layout
    # stays stable (header / summary / scope / MIL / SIL / PIL / model
    # analysis / conclusion). Suites that were skipped get `not_run: true`
    # plus a stub summary; the LLM renders a one-line "not run" paragraph
    # for them while still producing the surrounding structure.
    suites_present = []
    for key in ("mil", "sil", "pil"):
        if v[key].get("skipped"):
            slim[key] = {
                "ref":     f"/validation/{key}",
                "not_run": True,
                "summary": {"total": 0, "pass": 0, "fail": 0,
                            "error": 0, "skipped": 0,
                            "pass_rate_pct": 0.0},
                "tests":   [],
            }
            continue
        slim[key] = _slim_validator(v[key], f"/validation/{key}",
                                    keep_passing_checks=(key != "mil"))
        suites_present.append(key)
    slim["analysis"] = _slim_analysis(a, "/analysis")

    sev = a.get("summary", {}).get("by_severity", {}) or {}
    slim["kpis"] = {
        "tests_total":  sum(slim[t]["summary"].get("total", 0)
                            for t in suites_present),
        "tests_passed": sum(slim[t]["summary"].get("pass",  0)
                            for t in suites_present),
        "tests_failed": sum(slim[t]["summary"].get("fail",  0)
                            + slim[t]["summary"].get("error", 0)
                            for t in suites_present),
        "pass_rate_pct": {t: slim[t]["summary"].get("pass_rate_pct", 0.0)
                          for t in suites_present},
        "suites_run":        suites_present,
        "findings_total":    a.get("summary", {}).get("n_findings", 0),
        "findings_by_sev":   sev,
        "findings_critical": sev.get("critical", 0),
        "findings_major":    sev.get("major", 0),
        "verdict":           a.get("summary", {}).get("verdict", "unknown"),
    }
    return slim


# ---------------------------------------------------------------- public entry

def consolidate(mil_path: Path | None, sil_path: Path | None,
                pil_path: Path | None, analysis_path: Path,
                full_filename: str = "FULL_REPORT.json"
                ) -> tuple[dict, dict]:
    """Return (full, slim). Caller writes both to disk.
    Pass None for any of mil/sil/pil to omit that section from the report."""
    mil = _load(mil_path) if mil_path else _empty_validator("mil")
    sil = _load(sil_path) if sil_path else _empty_validator("sil")
    pil = _load(pil_path) if pil_path else _empty_validator("pil")
    full = build_full(mil, sil, pil, _load(analysis_path))
    slim = build_slim(full, full_filename=full_filename)
    return full, slim


# ---------------------------------------------------------------- two-part split
#
# The summary HTML is generated as TWO files (REPORT_PART1.html =
# data tables, REPORT_PART2.html = analysis & verdict). Each LLM call
# only sees the slice of `slim` it actually needs, which roughly halves
# the prompt-token footprint per call versus the legacy single-shot.

def slim_for_part1(slim: dict) -> dict:
    """Slice fed to the PART 1 prompt: project + kpis + MIL/SIL/PIL.

    The analyzer findings are stripped; we only keep the high-level
    severity counts inside `kpis` so the data report can quote them in
    its summary KPI table."""
    keep = ("project", "full_report", "kpis", "mil", "sil", "pil")
    return {k: slim[k] for k in keep if k in slim}


def slim_for_part2(slim: dict) -> dict:
    """Slice fed to the PART 2 prompt: project + kpis + analysis +
    a tiny `validator_summary` so the verdict paragraph can quote the
    headline pass/fail numbers without re-shipping the per-test rows."""
    out = {
        "project":     slim.get("project", {}),
        "full_report": slim.get("full_report", "FULL_REPORT.json"),
        "kpis":        slim.get("kpis", {}),
        "analysis":    slim.get("analysis", {}),
    }
    vs = {}
    for key in ("mil", "sil", "pil"):
        sec = slim.get(key, {}) or {}
        if sec.get("not_run"):
            vs[key] = {"ref": sec.get("ref", f"/validation/{key}"),
                       "not_run": True}
        else:
            vs[key] = {
                "ref":     sec.get("ref", f"/validation/{key}"),
                "summary": sec.get("summary", {}),
            }
    out["validator_summary"] = vs
    return out
