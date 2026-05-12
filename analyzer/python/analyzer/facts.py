"""Load facts + validator reports into a single nested dict."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any


def _load_json(path: Path) -> dict | None:
    if not path.is_file():
        return None
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def build_context(
    facts_path: Path,
    cov_path: Path | None,
    mil_path: Path | None,
    sil_path: Path | None,
    pil_path: Path | None,
    reqs_path: Path | None,
    policy: dict,
) -> dict[str, Any]:
    """Assemble the working memory the rule engine sees as `ctx`.

    Layout (paths used in YAML rules):
      model.<mdl>.{static, stateflow, solver, codegen}
      coverage.<mdl>.{execution, decision, condition, mcdc}.{covered, total,
                                                              coverage_pct,
                                                              dead_pct}
      validation.<phase>.{total, passed, fail, error, status}
                         where phase in {mil, sil, pil}
      validation.pil.wcet_us, validation.pil.ram_kb,
      validation.pil.predictor_max_abs_err
      requirements.<REQ-ID>.{component, function, asil, phases, ...}
      policy.<...>           (loaded from analyzer/knowledge/asil_policy.yaml)
    """
    facts = _load_json(facts_path)
    if facts is None:
        raise FileNotFoundError(f"facts file not found: {facts_path}")

    cov = _load_json(cov_path) if cov_path else None
    mil = _load_json(mil_path) if mil_path else None
    sil = _load_json(sil_path) if sil_path else None
    pil = _load_json(pil_path) if pil_path else None
    reqs = _load_json(reqs_path) if reqs_path else None

    ctx: dict[str, Any] = {
        "model": facts.get("models", {}),
        "coverage": (cov or {}).get("by_model", {}),
        "validation": _validation_view(mil, sil, pil),
        "policy": policy,
    }

    # Index requirements by id so rules can write requirements.<ID>.asil.
    if reqs:
        idx: dict[str, dict] = {}
        for r in reqs.get("low_level", []):
            idx[r["id"]] = r
        ctx["requirements"] = idx
    else:
        ctx["requirements"] = {}

    # Useful provenance for the output report.
    ctx["_inputs"] = {
        "facts": str(facts_path),
        "coverage": str(cov_path) if cov_path else None,
        "mil": str(mil_path) if mil_path else None,
        "sil": str(sil_path) if sil_path else None,
        "pil": str(pil_path) if pil_path else None,
        "requirements": str(reqs_path) if reqs_path else None,
    }
    return ctx


_MISSING = object()


def lookup(ctx: dict, dotted: str):
    """Resolve a dotted path against `ctx`. Returns _MISSING if any segment
    is absent so the engine can treat the premise as false rather than
    crashing on a missing fact."""
    cur: Any = ctx
    for part in dotted.split("."):
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            return _MISSING
    return cur


def is_missing(value) -> bool:
    # Treat both the sentinel and JSON null (None) as "absent" so that
    # rule comparisons like `x > threshold` degrade gracefully instead of
    # raising TypeError when a field exists in the JSON with a null value.
    return value is _MISSING or value is None


# --------------------------------------------------------------------------
# Validator-report shaping
# --------------------------------------------------------------------------

def _suite_summary(report: dict | None) -> dict:
    """Flatten the validator's `summary` block into a stable shape, plus
    capture the list of failing/erroring test ids so a rule can name them."""
    if not report:
        return {"present": False, "total": 0, "passed": 0, "fail": 0,
                "error": 0, "skipped": 0, "status": "missing",
                "failing_tests": []}

    s = report.get("summary", {}) or {}
    out = {
        "present": True,
        "total":   int(s.get("total",   0)),
        "passed":  int(s.get("pass",    0)),
        "fail":    int(s.get("fail",    0)),
        "error":   int(s.get("error",   0)),
        "skipped": int(s.get("skipped", 0)),
    }
    out["status"] = ("ok" if out["fail"] == 0 and out["error"] == 0
                     else "fail")

    failing = []
    results = report.get("results", [])
    if isinstance(results, dict):
        results = [results]
    for r in results:
        st = str(r.get("status", "")).lower()
        if st in ("fail", "error"):
            failing.append(r.get("req_id") or r.get("name") or "?")
    out["failing_tests"] = failing
    return out


def _pil_metrics(pil: dict | None) -> dict:
    """Extract the per-requirement numerics PIL exposes that rules want
    to compare against budgets (WCET us, RAM kB, predictor max abs error)."""
    out = {"wcet_us": None, "ram_kb": None, "predictor_max_abs_err": None}
    if not pil:
        return out

    results = pil.get("results", [])
    if isinstance(results, dict):
        results = [results]

    pick = {
        "REQ-LL-RT-WCET-01":  "wcet_us",
        "REQ-LL-RT-RAM-01":   "ram_kb",
        "REQ-LL-PIL-PRD-01":  "predictor_max_abs_err",
    }
    for r in results:
        key = pick.get(r.get("req_id"))
        if key is None:
            continue
        checks = r.get("checks")
        if isinstance(checks, list) and checks:
            checks = checks[0]
        if isinstance(checks, dict):
            v = checks.get("value")
            if isinstance(v, (int, float)):
                out[key] = float(v)
    return out


def _validation_view(mil: dict | None, sil: dict | None,
                     pil: dict | None) -> dict:
    """Build the `validation.*` namespace exposed to rules."""
    view = {
        "mil": _suite_summary(mil),
        "sil": _suite_summary(sil),
        "pil": _suite_summary(pil),
    }
    view["pil"].update(_pil_metrics(pil))
    return view
