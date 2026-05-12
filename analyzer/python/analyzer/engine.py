"""Forward-chaining inference engine.

A rule fires at most once per run. Rules with a `forEach` clause expand
into one finding per matching item -- the loop variable is bound under
its declared name in the working context, so `bind:` and `when:` can
reference `<var>.path`, `<var>.value`, etc.

The trace records, in firing order, the rule id, the bound values and
the dotted fact paths the premise consulted. The outer loop repeats
until no new rule fires, so a rule whose premise depends on a derived
fact can still match on a later pass.
"""
from __future__ import annotations

from typing import Any

from .facts import is_missing, lookup
from .rules import Rule, evaluate_premise, resolve_bindings


_SEVERITY_RANK = {"info": 0, "minor": 1, "major": 2, "critical": 3}


def _format_safe(template: str, bindings: dict) -> str:
    if not template:
        return ""
    try:
        return template.format(**bindings)
    except (KeyError, IndexError, ValueError, TypeError):
        return template


def _emit(rule: Rule, ctx: dict, findings: list, trace: list,
          derived: dict, premise_paths: list, pass_no: int) -> None:
    bindings, bind_paths = resolve_bindings(rule, ctx)

    # If the bindings include a Simulink block path, pre-compute a one-line
    # MATLAB command so the user can jump straight to the offender.
    locator = ""
    path = bindings.get("path")
    if isinstance(path, str) and "/" in path:
        # `hilite_system` is forgiving and works on blocks, subsystems and
        # Stateflow chart containers alike.
        locator = "hilite_system('" + path.replace("'", "''") + "')"

    # WIP downrank: if the finding's path lives inside a known
    # work-in-progress subsystem, demote it to `info` and tag it. This
    # keeps the digest focused on production-scope issues without losing
    # the trail.
    severity = rule.severity
    is_wip = False
    if isinstance(path, str):
        wip_paths = lookup(ctx, "policy.wip_paths")
        if isinstance(wip_paths, list):
            for p in wip_paths:
                if isinstance(p, str) and (path == p or path.startswith(p + "/")):
                    severity = "info"
                    is_wip = True
                    break

    finding = {
        "id":        f"F-{len(findings) + 1:03d}",
        "rule_id":   rule.id,
        "category":  rule.category,
        "severity":  severity,
        "wip":       is_wip,
        "finding":   _format_safe(rule.finding, bindings),
        "reasoning": _format_safe(rule.reasoning, bindings),
        "recommend": [_format_safe(r, bindings) for r in rule.recommend],
        "refs":      list(rule.refs),
        "locator":   locator,
        "evidence": {
            "facts_used": sorted(set(premise_paths + bind_paths)),
            "values":     bindings,
        },
    }
    findings.append(finding)
    derived.setdefault(rule.category, []).append({
        "rule_id":  rule.id,
        "severity": severity,
    })
    trace.append({
        "pass":     pass_no,
        "rule_id":  rule.id,
        "category": rule.category,
        "source":   rule.source,
        "fired":    True,
        "bindings": bindings,
        "facts":    sorted(set(premise_paths + bind_paths)),
    })


def run_engine(rules: list[Rule], ctx: dict) -> tuple[list[dict], list[dict]]:
    """Returns (findings, trace). Both lists are in firing order."""
    findings: list[dict] = []
    trace: list[dict] = []
    derived: dict[str, list[dict]] = {}
    fired: set[str] = set()

    # Make `derived` visible so future rules can match on it.
    ctx["derived"] = derived

    pass_no = 0
    changed = True
    while changed:
        changed = False
        pass_no += 1
        for rule in rules:
            if rule.id in fired:
                continue

            if rule.for_each:
                seq = lookup(ctx, rule.for_each["in"])
                if is_missing(seq) or not isinstance(seq, (list, tuple)):
                    fired.add(rule.id)        # nothing to iterate -> done
                    continue
                var_name = rule.for_each["var"]
                any_emitted = False
                for item in seq:
                    ctx[var_name] = item
                    try:
                        ok, premise_paths = evaluate_premise(rule, ctx)
                        if not ok:
                            continue
                        _emit(rule, ctx, findings, trace, derived,
                              premise_paths, pass_no)
                        any_emitted = True
                    finally:
                        ctx.pop(var_name, None)
                fired.add(rule.id)
                if any_emitted:
                    changed = True
                continue

            ok, premise_paths = evaluate_premise(rule, ctx)
            if not ok:
                continue
            _emit(rule, ctx, findings, trace, derived,
                  premise_paths, pass_no)
            fired.add(rule.id)
            changed = True

    return findings, trace


def summarize(findings: list[dict]) -> dict:
    by_sev: dict[str, int] = {k: 0 for k in _SEVERITY_RANK}
    by_cat: dict[str, int] = {}
    worst = "info"
    for f in findings:
        by_sev[f["severity"]] = by_sev.get(f["severity"], 0) + 1
        by_cat[f["category"]] = by_cat.get(f["category"], 0) + 1
        if _SEVERITY_RANK.get(f["severity"], 0) > _SEVERITY_RANK[worst]:
            worst = f["severity"]
    if worst == "critical":
        verdict = "blocking"
    elif worst in ("major", "minor"):
        verdict = "review_required"
    else:
        verdict = "ok"
    return {
        "n_findings":  len(findings),
        "by_severity": by_sev,
        "by_category": by_cat,
        "verdict":     verdict,
    }
