"""Write the ANALYSIS.json output and a short stdout digest."""
from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path


def write_report(out_dir: Path, ctx: dict, findings: list[dict],
                 trace: list[dict], summary: dict) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")

    report = {
        "schema_version": "1.0",
        "timestamp":      ts,
        "inputs":         ctx.get("_inputs", {}),
        "summary":        summary,
        "findings":       findings,
        "trace":          trace,
    }

    ts_path = out_dir / f"ANALYSIS_{ts}.json"
    sticky  = out_dir / "ANALYSIS.json"
    for p in (ts_path, sticky):
        with p.open("w", encoding="utf-8") as f:
            json.dump(report, f, indent=2, default=str)
    return ts_path


def print_digest(findings: list[dict], summary: dict, out_path: Path) -> None:
    print("\n=== ANALYZER SUMMARY ===")
    print(f"Findings: {summary['n_findings']}  verdict: {summary['verdict']}")
    bs = summary["by_severity"]
    print(f"  critical={bs.get('critical', 0)}  major={bs.get('major', 0)}  "
          f"minor={bs.get('minor', 0)}  info={bs.get('info', 0)}")
    print()

    # Group findings by severity (worst first) so the eye lands on the
    # blocking issues. Print the locator and the first recommendation
    # right under the headline so the user can act without opening the
    # full JSON.
    order = ["critical", "major", "minor", "info"]
    grouped: dict[str, list[dict]] = {k: [] for k in order}
    for f in findings:
        grouped.setdefault(f["severity"], []).append(f)

    for sev in order:
        items = grouped.get(sev, [])
        if not items:
            continue
        print(f"--- {sev.upper()} ({len(items)}) ---")
        for f in items:
            tag = " [WIP]" if f.get("wip") else ""
            print(f"  [{f['rule_id']}]{tag} {f['finding']}")
            if f.get("locator"):
                print(f"      MATLAB> {f['locator']}")
            for rec in f.get("recommend", [])[:1]:    # just the first hint
                print(f"      fix:    {rec}")
        print()
    print(f"Report: {out_path}")
