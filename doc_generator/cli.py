"""CLI: build FULL + SLIM JSON files, then ask the LLM for TWO HTML
summary parts (validation data + engineering analysis).

Two parts -> two LLM calls -> roughly twice the per-call TPM budget
of the legacy single-shot, with no change to the underlying free-tier
quota. Each part is a standalone HTML5 document that references
FULL_REPORT.json by JSON Pointer."""
from __future__ import annotations

import argparse
import json
import os
import re
from datetime import datetime
from pathlib import Path

from .consolidate import consolidate, slim_for_part1, slim_for_part2
from .llm_client import DEFAULT_MODEL, DEFAULT_URL, chat
from .prompt import (
    SYSTEM_PROMPT_A, USER_PROMPT_TEMPLATE_A,
    SYSTEM_PROMPT_B, USER_PROMPT_TEMPLATE_B,
)


# ---------------------------------------------------------------- helpers

def _repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def _strip_html_fences(text: str) -> str:
    t = text.strip()
    m = re.match(r"^```(?:html)?\s*(.*?)\s*```$", t, flags=re.DOTALL | re.IGNORECASE)
    return m.group(1).strip() if m else t


def _resolve_api_key(explicit: str) -> str:
    for src in (explicit,
                os.environ.get("LLM_API_KEY", ""),
                os.environ.get("WISGATE_API_KEY", ""),
                os.environ.get("GROQ_API_KEY", "")):
        if src:
            return src
    return ""


def _resolve_pointer(doc: dict, ptr: str):
    """Best-effort RFC 6901 lookup; returns None on miss."""
    if not ptr or not ptr.startswith("/"):
        return None
    cur = doc
    for tok in ptr[1:].split("/"):
        tok = tok.replace("~1", "/").replace("~0", "~")
        if isinstance(cur, list):
            try:
                cur = cur[int(tok)]
            except (ValueError, IndexError):
                return None
        elif isinstance(cur, dict):
            if tok not in cur:
                return None
            cur = cur[tok]
        else:
            return None
    return cur


def _audit_refs(html: str, full: dict) -> tuple[int, list[str]]:
    """Verify every `<code>/...</code>` token in the HTML resolves
    inside the full file. Returns (total_refs, broken_refs)."""
    refs = re.findall(r"<code>(/[^<>\s]+)</code>", html)
    broken = [r for r in refs if _resolve_pointer(full, r) is None]
    return len(refs), broken


# ---------------------------------------------------------------- TPM guard
#
# Free-tier Groq TPM caps prompt + max_completion (per call) at 8000 for
# `openai/gpt-oss-120b`. Each of our two calls gets its own budget, so
# the trim logic runs independently for each slim slice.
TPM_BUDGET = 7600


def _approx_tokens(text: str) -> int:
    # ~4 chars per token for English HTML/JSON; stable enough as a guard.
    return (len(text) + 3) // 4


def _slim_tokens(slim: dict, system_prompt: str,
                 user_template: str, full_filename: str) -> int:
    payload = json.dumps(slim, separators=(",", ":"), default=str)
    user    = user_template.format(full_report=full_filename, payload=payload)
    return _approx_tokens(system_prompt) + _approx_tokens(user)


def _trim_part1(slim: dict, max_tokens: int, full_filename: str) -> dict:
    """Shrink the validation-data slice until prompt + max_tokens fits.

    Order (each step is skipped once the budget fits):
      1. drop `checks` from passing SIL/PIL tests
      2. trim every test name to 60 chars
      3. drop passing MIL tests entirely (keep only fail/error rows)
      4. drop passing SIL/PIL tests entirely (keep only fail/error rows)
    """
    target = TPM_BUDGET - max_tokens

    def fits():
        return _slim_tokens(slim, SYSTEM_PROMPT_A, USER_PROMPT_TEMPLATE_A,
                            full_filename) <= target

    if fits(): return slim
    for key in ("sil", "pil"):
        if slim.get(key, {}).get("not_run"): continue
        for t in slim.get(key, {}).get("tests", []):
            if t.get("status") == "pass" and "checks" in t:
                t.pop("checks", None)
        if fits(): return slim

    for key in ("mil", "sil", "pil"):
        for t in slim.get(key, {}).get("tests", []):
            nm = t.get("name", "")
            if len(nm) > 60:
                t["name"] = nm[:59].rstrip() + "\u2026"
        if fits(): return slim

    if not slim.get("mil", {}).get("not_run"):
        slim["mil"]["tests"] = [t for t in slim["mil"]["tests"]
                                if t.get("status") != "pass"]
        slim["mil"]["dropped_passing_rows"] = True
        if fits(): return slim

    for key in ("sil", "pil"):
        if slim.get(key, {}).get("not_run"): continue
        slim[key]["tests"] = [t for t in slim[key]["tests"]
                              if t.get("status") != "pass"]
        slim[key]["dropped_passing_rows"] = True
        if fits(): return slim
    return slim


def _trim_part2(slim: dict, max_tokens: int, full_filename: str) -> dict:
    """Shrink the analysis slice until prompt + max_tokens fits.

      1. cap each rule's `refs` to 1 entry
      2. drop the lowest-severity half of `analysis.rules`
      3. blank `reasoning` and `recommend` for non-critical rules
    """
    target = TPM_BUDGET - max_tokens

    def fits():
        return _slim_tokens(slim, SYSTEM_PROMPT_B, USER_PROMPT_TEMPLATE_B,
                            full_filename) <= target

    if fits(): return slim
    for r in slim.get("analysis", {}).get("rules", []):
        r["refs"] = (r.get("refs") or [])[:1]
    if fits(): return slim

    rules = slim.get("analysis", {}).get("rules", []) or []
    if len(rules) > 2:
        keep = max(2, len(rules) // 2)
        slim["analysis"]["rules"] = rules[:keep]
        slim["analysis"]["truncated_rules"] = True
        if fits(): return slim

    for r in slim.get("analysis", {}).get("rules", []):
        if r.get("severity") != "critical":
            r["reasoning"] = ""
            r["recommend"] = []
    return slim


# ---------------------------------------------------------------- one LLM call

def _generate_part(label: str, slim_slice: dict, system_prompt: str,
                   user_template: str, full_filename: str,
                   model: str, url: str, api_key: str,
                   temperature: float, max_tokens: int,
                   full_for_audit: dict) -> str:
    """Run the budget guard then a single chat() call. Returns the
    HTML body (with markdown fences stripped) and prints an audit
    summary of the JSON-Pointer references it embedded."""
    pre = _slim_tokens(slim_slice, system_prompt, user_template,
                       full_filename)
    print(f"[doc_gen] [{label}] estimated prompt tokens: {pre}  "
          f"max_completion={max_tokens}  budget={TPM_BUDGET}")
    if pre + max_tokens > TPM_BUDGET:
        slim_call = json.loads(json.dumps(slim_slice, default=str))
        # Per-part trimmer (different rules for data vs analysis).
        if label == "part1":
            slim_call = _trim_part1(slim_call, max_tokens, full_filename)
        else:
            slim_call = _trim_part2(slim_call, max_tokens, full_filename)
        post = _slim_tokens(slim_call, system_prompt, user_template,
                            full_filename)
        print(f"[doc_gen] [{label}] trimmed slim: {pre} -> {post} prompt tokens")
        if post + max_tokens > TPM_BUDGET:
            new_max = max(1200, TPM_BUDGET - post - 100)
            print(f"[doc_gen] [{label}] still over budget, lowering "
                  f"max_completion {max_tokens} -> {new_max}")
            max_tokens = new_max
    else:
        slim_call = slim_slice

    user_prompt = user_template.format(
        full_report=full_filename,
        payload=json.dumps(slim_call, separators=(",", ":"), default=str))
    print(f"[doc_gen] [{label}] calling LLM ...")
    html = _strip_html_fences(chat(api_key, system_prompt, user_prompt,
                                   model=model, url=url,
                                   temperature=temperature,
                                   max_completion_tokens=max_tokens,
                                   rate_limit_retries=4,
                                   rate_limit_wait_s=20))
    if not html.lower().lstrip().startswith("<!doctype") \
            and "<html" not in html.lower():
        print(f"[doc_gen] [{label}] WARNING: response is not HTML; "
              "saving raw output for inspection.")
    n_refs, broken = _audit_refs(html, full_for_audit)
    if n_refs == 0:
        print(f"[doc_gen] [{label}] WARNING: no JSON-Pointer references "
              "found in the HTML.")
    elif broken:
        print(f"[doc_gen] [{label}] WARNING: {len(broken)}/{n_refs} JSON "
              "Pointers do NOT resolve inside FULL_REPORT.json:")
        for r in broken[:10]:
            print(f"    {r}")
    else:
        print(f"[doc_gen] [{label}] reference audit: all {n_refs} "
              "JSON Pointers resolve.")
    return html


# ---------------------------------------------------------------- main

def main(argv: list[str] | None = None) -> int:
    repo = _repo_root()
    p = argparse.ArgumentParser(
        prog="python -m doc_generator",
        description="Generate the BMS V&V two-part HTML summary "
                    "(REPORT_PART1 + REPORT_PART2) and the FULL/SLIM "
                    "JSON archives from the latest report inputs.")
    p.add_argument("--mil",      type=Path,
                   default=repo / "validator" / "reports" / "MIL.json")
    p.add_argument("--sil",      type=Path,
                   default=repo / "validator" / "reports" / "SIL.json")
    p.add_argument("--pil",      type=Path,
                   default=repo / "validator" / "reports" / "PIL.json")
    p.add_argument("--analysis", type=Path,
                   default=repo / "analyzer" / "reports" / "ANALYSIS.json")
    p.add_argument("--out",      type=Path,
                   default=repo / "doc_generator" / "reports")
    p.add_argument("--skip-mil", action="store_true",
                   help="Omit the MIL section from the report.")
    p.add_argument("--skip-sil", action="store_true",
                   help="Omit the SIL section from the report.")
    p.add_argument("--skip-pil", action="store_true",
                   help="Omit the PIL section from the report.")
    p.add_argument("--model",    default=DEFAULT_MODEL,
                   help=f"LLM model name (default: {DEFAULT_MODEL}).")
    p.add_argument("--url",      default=DEFAULT_URL,
                   help=f"chat-completions endpoint (default: {DEFAULT_URL}).")
    p.add_argument("--api-key",  default="",
                   help="API key (else $LLM_API_KEY / $WISGATE_API_KEY / "
                        "$GROQ_API_KEY).")
    p.add_argument("--temperature",  type=float, default=0.2)
    p.add_argument("--max-tokens",   type=int,   default=3500,
                   help="max_completion_tokens for EACH LLM call.")
    p.add_argument("--dry-run", action="store_true",
                   help="Only write the JSON archives, skip the LLM calls.")
    args = p.parse_args(argv)

    args.out.mkdir(parents=True, exist_ok=True)
    full_filename = "FULL_REPORT.json"

    print("[doc_gen] consolidating reports ...")
    full, slim = consolidate(
        None if args.skip_mil else args.mil,
        None if args.skip_sil else args.sil,
        None if args.skip_pil else args.pil,
        args.analysis, full_filename=full_filename)

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    full_path     = args.out / full_filename
    slim_path     = args.out / "CONSOLIDATED.json"
    full_path_ts  = args.out / f"FULL_REPORT_{ts}.json"
    slim_path_ts  = args.out / f"CONSOLIDATED_{ts}.json"
    for path, doc in ((full_path,    full),
                       (full_path_ts, full),
                       (slim_path,    slim),
                       (slim_path_ts, slim)):
        with path.open("w", encoding="utf-8") as f:
            json.dump(doc, f, indent=2, default=str)
    print(f"[doc_gen] wrote {full_path}  ({full_path.stat().st_size} bytes)")
    print(f"[doc_gen] wrote {slim_path}  ({slim_path.stat().st_size} bytes)")

    if args.dry_run:
        return 0

    api_key = _resolve_api_key(args.api_key)
    if not api_key:
        print("[doc_gen] ERROR: no API key (use --api-key or set "
              "LLM_API_KEY / WISGATE_API_KEY / GROQ_API_KEY).")
        return 2

    slim_a = slim_for_part1(slim)
    slim_b = slim_for_part2(slim)

    html_a = _generate_part(
        "part1", slim_a, SYSTEM_PROMPT_A, USER_PROMPT_TEMPLATE_A,
        full_filename, args.model, args.url, api_key,
        args.temperature, args.max_tokens, full)
    html_b = _generate_part(
        "part2", slim_b, SYSTEM_PROMPT_B, USER_PROMPT_TEMPLATE_B,
        full_filename, args.model, args.url, api_key,
        args.temperature, args.max_tokens, full)

    out_a_ts     = args.out / f"REPORT_PART1_{ts}.html"
    out_a_sticky = args.out / "REPORT_PART1.html"
    out_b_ts     = args.out / f"REPORT_PART2_{ts}.html"
    out_b_sticky = args.out / "REPORT_PART2.html"
    for path, body in ((out_a_ts, html_a), (out_a_sticky, html_a),
                       (out_b_ts, html_b), (out_b_sticky, html_b)):
        path.write_text(body, encoding="utf-8")
        print(f"[doc_gen] wrote {path}")
    return 0
