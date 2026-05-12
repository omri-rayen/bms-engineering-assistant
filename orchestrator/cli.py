"""End-to-end orchestrator for the BMS Engineering Assistant.

Steps (each may be skipped via flag):
    1. MATLAB   : mil.run + sil.run + pil.run + cov.run + ana.collect
    2. Python   : python -m analyzer       -> ANALYSIS.json
    3. Python   : python -m doc_generator  -> REPORT_PART1.html + REPORT_PART2.html

The MATLAB block runs in a single -batch session to avoid paying the cold
startup cost (~5 min) more than once. Hardware (STM32 Nucleo on COM3) must
be connected for the PIL step; use --skip-pil otherwise.
"""
from __future__ import annotations

import argparse
import os
import shlex
import subprocess
import sys
import time
from pathlib import Path


def _repo_root() -> Path:
    # orchestrator/cli.py -> orchestrator/ -> repo root
    return Path(__file__).resolve().parents[1]


def _build_matlab_script(repo: Path, do_mil: bool, do_sil: bool,
                         do_pil: bool, do_cov: bool, do_facts: bool,
                         skip_build: bool) -> str:
    """Compose the MATLAB code that runs inside `matlab -batch`."""
    sb = "true" if skip_build else "false"
    parts = [
        f"cd('{repo.as_posix()}');",
        "run('startup.m');",
        "addpath('analyzer');",
    ]
    if do_mil:
        parts += [
            "fprintf('\\n=== [orch] MIL ===\\n');",
            "mil.run('suites', {'bms','predictor'});",
        ]
    if do_sil:
        parts += [
            "fprintf('\\n=== [orch] SIL ===\\n');",
            f"sil.run('skip_build', {sb});",
        ]
    if do_pil:
        parts += [
            "fprintf('\\n=== [orch] PIL ===\\n');",
            f"pil.run('skip_build', {sb});",
        ]
    if do_cov:
        parts += [
            "fprintf('\\n=== [orch] COV (dead-code) ===\\n');",
            "cov.run();",
        ]
    if do_facts:
        parts += [
            "fprintf('\\n=== [orch] ana.collect ===\\n');",
            "ana.collect('verbose', true);",
        ]
    return " ".join(parts)


def _run_matlab(repo: Path, script: str, matlab_exe: str) -> int:
    cmd = [matlab_exe, "-batch", script]
    print(f"[orch] matlab cmd: {shlex.join(cmd)}")
    t0 = time.time()
    rc = subprocess.call(cmd, cwd=str(repo))
    print(f"[orch] matlab finished rc={rc} in {time.time()-t0:.1f}s")
    return rc


def _run_python_module(repo: Path, module: str, extra: list[str],
                       env_extra: dict | None = None) -> int:
    cmd = [sys.executable, "-m", module, *extra]
    print(f"[orch] python -m {module} {' '.join(extra)}")
    env = os.environ.copy()
    if env_extra:
        env.update(env_extra)
    t0 = time.time()
    rc = subprocess.call(cmd, cwd=str(repo), env=env)
    print(f"[orch] {module} finished rc={rc} in {time.time()-t0:.1f}s")
    return rc


def main(argv: list[str] | None = None) -> int:
    repo = _repo_root()

    p = argparse.ArgumentParser(
        prog="python -m orchestrator",
        description="Run the BMS validation + analyzer + doc-generator "
                    "pipeline end-to-end.")
    p.add_argument("--matlab", default=os.environ.get("MATLAB", "matlab"),
                   help="matlab executable (default: 'matlab' on PATH)")
    p.add_argument("--skip-mil",      action="store_true")
    p.add_argument("--skip-sil",      action="store_true")
    p.add_argument("--skip-pil",      action="store_true",
                   help="Skip PIL (use when the STM32 board is not connected).")
    p.add_argument("--skip-cov",      action="store_true")
    p.add_argument("--skip-facts",    action="store_true",
                   help="Skip ana.collect (analyzer needs FACTS.json).")
    p.add_argument("--skip-matlab",   action="store_true",
                   help="Skip the whole MATLAB phase (reuse existing JSON).")
    p.add_argument("--skip-analyzer", action="store_true")
    p.add_argument("--skip-doc",      action="store_true")
    p.add_argument("--skip-build",    action="store_true",
                   help="Pass skip_build=true to sil.run / pil.run.")
    p.add_argument("--api-key",       default=os.environ.get("LLM_API_KEY",
                                          os.environ.get("WISGATE_API_KEY",
                                          os.environ.get("GROQ_API_KEY", ""))),
                   help="LLM API key (also read from $LLM_API_KEY / "
                        "$WISGATE_API_KEY / $GROQ_API_KEY).")
    p.add_argument("--dry-run-doc",   action="store_true",
                   help="doc_generator: only write consolidated JSON.")
    args = p.parse_args(argv)

    t_start = time.time()

    # ----- 1. MATLAB phase --------------------------------------------------
    if not args.skip_matlab:
        do_mil = not args.skip_mil
        do_sil = not args.skip_sil
        do_pil = not args.skip_pil
        do_cov = not args.skip_cov
        do_facts = not args.skip_facts
        if any([do_mil, do_sil, do_pil, do_cov, do_facts]):
            script = _build_matlab_script(repo, do_mil, do_sil, do_pil,
                                          do_cov, do_facts, args.skip_build)
            rc = _run_matlab(repo, script, args.matlab)
            if rc != 0:
                print(f"[orch] MATLAB phase failed (rc={rc}). Aborting.")
                return rc
        else:
            print("[orch] MATLAB phase: nothing to do (all sub-steps skipped).")
    else:
        print("[orch] skipping MATLAB phase.")

    # ----- 2. Analyzer ------------------------------------------------------
    if not args.skip_analyzer:
        py_path_extra = {"PYTHONPATH": str(repo / "analyzer" / "python")}
        rc = _run_python_module(repo, "analyzer", [], env_extra=py_path_extra)
        # The analyzer exits 1 (review_required) or 2 (blocking) by design
        # to act as a CI gate. ANALYSIS.json is still produced -- treat it
        # as success here so the doc generator can pick it up. We only
        # abort if the report file is missing.
        analysis_json = repo / "analyzer" / "reports" / "ANALYSIS.json"
        if not analysis_json.is_file():
            print(f"[orch] analyzer did not produce {analysis_json} "
                  f"(rc={rc}). Aborting.")
            return rc or 1
        if rc != 0:
            print(f"[orch] analyzer rc={rc} (non-zero verdict, "
                  f"continuing -- ANALYSIS.json is present).")
    else:
        print("[orch] skipping analyzer.")

    # ----- 3. Doc generator -------------------------------------------------
    if not args.skip_doc:
        extra = []
        env_extra = {}
        if args.api_key:
            # Pass under both names so doc_generator picks it up regardless
            # of which provider it ends up calling.
            env_extra["LLM_API_KEY"]     = args.api_key
            env_extra["WISGATE_API_KEY"] = args.api_key
        if args.dry_run_doc:
            extra.append("--dry-run")
        rc = _run_python_module(repo, "doc_generator", extra,
                                env_extra=env_extra)
        if rc != 0:
            print(f"[orch] doc_generator failed (rc={rc}).")
            return rc
    else:
        print("[orch] skipping doc_generator.")

    print(f"\n[orch] PIPELINE OK in {time.time()-t_start:.1f}s")
    return 0
