"""Command-line entry point for the analyzer expert system."""
from __future__ import annotations

import argparse
from pathlib import Path

from .engine import run_engine, summarize
from .facts import build_context
from .reporter import print_digest, write_report
from .rules import load_rules


def _repo_root() -> Path:
    # analyzer/python/analyzer/cli.py -> analyzer/python/analyzer/
    # parents[0]=analyzer, [1]=python, [2]=analyzer/, [3]=repo root
    return Path(__file__).resolve().parents[3]


def main(argv: list[str] | None = None) -> int:
    repo = _repo_root()
    ana  = repo / "analyzer"

    p = argparse.ArgumentParser(
        prog="python -m analyzer",
        description="Run the BMS analyzer rule engine on the latest "
                    "facts + validator reports.")
    p.add_argument("--facts", type=Path,
                   default=ana / "reports" / "FACTS.json")
    p.add_argument("--cov",   type=Path,
                   default=repo / "validator" / "reports" / "COV.json")
    p.add_argument("--mil",   type=Path,
                   default=repo / "validator" / "reports" / "MIL.json")
    p.add_argument("--sil",   type=Path,
                   default=repo / "validator" / "reports" / "SIL.json")
    p.add_argument("--pil",   type=Path,
                   default=repo / "validator" / "reports" / "PIL.json")
    p.add_argument("--reqs",  type=Path,
                   default=repo / "validator" / "requirements" / "requirements.json")
    p.add_argument("--kb",    type=Path,
                   default=ana / "knowledge",
                   help="folder containing rule YAML files")
    p.add_argument("--out",   type=Path,
                   default=ana / "reports",
                   help="folder where ANALYSIS.json is written")
    p.add_argument("--quiet", action="store_true")
    args = p.parse_args(argv)

    rules, policy = load_rules(args.kb)
    if not args.quiet:
        print(f"Loaded {len(rules)} rules from {args.kb}")

    ctx = build_context(args.facts, args.cov, args.mil, args.sil, args.pil,
                        args.reqs, policy)

    findings, trace = run_engine(rules, ctx)
    summary = summarize(findings)
    out_path = write_report(args.out, ctx, findings, trace, summary)

    if not args.quiet:
        print_digest(findings, summary, out_path)

    # Exit code reflects severity so it's CI-friendly.
    if summary["verdict"] == "blocking":
        return 2
    if summary["verdict"] == "review_required":
        return 1
    return 0
