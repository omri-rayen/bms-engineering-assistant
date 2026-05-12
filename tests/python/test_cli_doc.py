"""REQ-SW-DOC-05/-07: cli token-trim ladders + ref audit."""
from __future__ import annotations
from doc_generator import cli as Cli, consolidate as C


def _build_full_with_n_tests(n: int) -> dict:
    mil = {
        "timestamp": "20260101_000000",
        "suite": "mil",
        "summary": {"total": n, "pass": n, "fail": 0,
                    "error": 0, "skipped": 0},
        "results": [
            {"req_id": f"REQ-LL-X-{i}",
             "name":   f"test_x_{i}",
             "status": "pass",
             "checks": [{"name": "k", "status": "pass",
                         "value": 1, "threshold": "==1"}]}
            for i in range(n)
        ],
    }
    sil = C._empty_validator("sil")
    pil = C._empty_validator("pil")
    ana = {"summary": {"n_findings": 0, "verdict": "ok",
                        "by_severity": {}}, "findings": []}
    return C.build_full(mil, sil, pil, ana)


def test_trim_part1_brings_payload_under_budget():
    """REQ-SW-DOC-05: trim must bring pre+max under TPM_BUDGET."""
    full = _build_full_with_n_tests(60)
    slim = C.build_slim(full)
    p1 = C.slim_for_part1(slim)
    p1_trimmed = Cli._trim_part1(p1, max_tokens=3000,
                                  full_filename="FULL_REPORT.json")
    pre = Cli._slim_tokens(p1_trimmed,
                           "fake-system-prompt",
                           Cli.USER_PROMPT_TEMPLATE_A,
                           "FULL_REPORT.json")
    assert pre + 3000 <= Cli.TPM_BUDGET, \
        f"trimmed payload still {pre + 3000} > {Cli.TPM_BUDGET}"


def test_trim_part2_keeps_analysis_present():
    full = _build_full_with_n_tests(20)
    slim = C.build_slim(full)
    p2 = C.slim_for_part2(slim)
    p2_t = Cli._trim_part2(p2, max_tokens=3000,
                            full_filename="FULL_REPORT.json")
    assert "analysis" in p2_t


def test_audit_refs_accepts_pointer_finds_value():
    """REQ-SW-DOC-07: JSON Pointer references resolve."""
    full = {"validation": {"mil": {"summary": {"pass": 5}}}}
    html = "<p>see <code>/validation/mil/summary/pass</code></p>"
    n_refs, broken = Cli._audit_refs(html, full)
    assert n_refs == 1
    assert broken == []


def test_audit_refs_ignores_filenames_without_leading_slash():
    """REQ-SW-DOC-07: <code>FULL_REPORT.json</code> is NOT a pointer."""
    full = {"validation": {}}
    html = '<p>see <code>FULL_REPORT.json</code></p>'
    n_refs, broken = Cli._audit_refs(html, full)
    assert n_refs == 0
    assert broken == []


def test_audit_refs_distinguishes_pointer_vs_filename():
    full = {"validation": {"mil": {}}}
    html = ('<p>see <code>FULL_REPORT.json</code> '
            'and <code>/validation/mil</code></p>')
    n_refs, broken = Cli._audit_refs(html, full)
    # Only the pointer (/validation/mil) is captured + valid.
    assert n_refs == 1
    assert broken == []


def test_audit_refs_flags_missing_pointer():
    full = {"validation": {"mil": {}}}
    html = "<code>/does/not/exist</code>"
    n_refs, broken = Cli._audit_refs(html, full)
    assert n_refs == 1
    assert broken == ["/does/not/exist"]


def test_strip_html_fences_removes_markdown_codeblock():
    raw = "```html\n<p>x</p>\n```"
    out = Cli._strip_html_fences(raw)
    assert out.strip() == "<p>x</p>"
