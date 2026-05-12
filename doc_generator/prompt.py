"""System + user prompts for the LLM HTML-report generation step.

The summary report is split into TWO HTML files so each LLM call has
its own ~8 K TPM budget (giving us roughly 2x the token headroom of a
single call):

    * Part 1 -- "Validation Data" -- header, summary, scope,
      MIL / SIL / PIL results tables.
    * Part 2 -- "Engineering Analysis" -- header, model-analysis
      findings & recommendations, conclusion.

Both files are standalone HTML5 documents. Every claim is backed by a
JSON Pointer reference (RFC 6901) into the sibling FULL_REPORT.json
file. Style is a clean, professional sans-serif technical report --
black-on-white, no dashboard widgets, no colour, no icons.
"""

# ---------------------------------------------------------------- shared
#
# Identical visual contract for both parts so the two HTML files look
# like one report when opened side-by-side. Sizes were tuned for an
# A4-width screen view; they are deliberately small so that long tables
# do not overflow.
_STYLE_BLOCK = """\
STYLE -- clean professional sans-serif technical report:
  * Body: `font-family: "Inter","Segoe UI",-apple-system,Roboto,
    "Helvetica Neue",Arial,sans-serif;` font-size 13.5px,
    line-height 1.55, color #1a1f29, background #ffffff,
    `max-width: 880px; margin: 28px auto; padding: 0 20px;`.
  * Headings: `h1` 22px / weight 600 / margin 0 0 4px;
              `h2` 17px / weight 600 / border-bottom 1px solid #d0d4da
                  / padding-bottom 4px / margin-top 28px;
              `h3` 14px / weight 600 / margin 18px 0 6px.
  * Paragraphs: margin 6px 0 10px.
  * Tables: `width:100%; border-collapse:collapse; font-size:12.5px;`
            cells `border:1px solid #c8ccd2; padding:5px 8px;`
            header row `background:#f4f5f7; font-weight:600;
            text-align:left;`. No zebra stripes.
  * Lists: tight, `margin:4px 0 8px 22px`.
  * `<code>` for every JSON Pointer: `font-family:"JetBrains Mono",
    Consolas,"Cascadia Mono",monospace; font-size:12px;
    background:#f4f5f7; padding:1px 4px; border-radius:3px;
    color:#0b3d91;`.
  * Status / severity values are plain text ("pass", "critical", ...),
    never coloured, never badged. `<em>` allowed.
  * No JS, no images, no external CSS, no <link>, no @import.
  * Use COMPACT HTML: keep each `<tr>` on one line, no pretty-print
    indentation -- this saves a measurable share of the output budget.
"""

_REF_RULES = """\
REFERENCE RULES:
  * `<code>` is used for two purposes only:
      (a) JSON Pointers -- they MUST start with a `/` and be present
          verbatim in the input JSON (each input row carries its `ref`).
      (b) Plain filenames such as `FULL_REPORT.json` or
          `REPORT_PART1.html` -- these have NO leading slash.
    Never mix the two: a leading slash means "this is a JSON Pointer".
  * Quote actual numbers (us, KB, deltas, %) verbatim from the input.
  * Cite ISO 26262 clauses exactly as supplied -- never invent one.
  * HTML must validate: every tag closed, no stray `</`.
"""


# ---------------------------------------------------------------- Part 1

SYSTEM_PROMPT_A = """\
You write PART 1 of a two-file V&V SUMMARY report for a 96s1p
Samsung-SDI BMS (1 master + 8 slave ECUs, embedded LSTM fault
predictor) under ISO 26262 ASIL D.

PART 1 covers: header, executive summary, scope, and the MIL / SIL /
PIL validation result tables. PART 2 (a separate file) covers the
engineering analysis findings and the release verdict; do NOT write
those sections here.

Input JSON keys: `project`, `kpis`, `full_report`, `mil`, `sil`,
`pil`. Validator suites may carry `"not_run": true` -- when set the
suite was skipped for this invocation.

OUTPUT: ONE complete HTML5 document. Start `<!doctype html>`, end
`</html>`. No markdown fences, no JS, no external assets.

""" + _STYLE_BLOCK + """

REQUIRED SECTIONS -- emit ALL SIX, in this exact order, each wrapped
in `<section id="ID">...</section>` (the literal tag name `section`,
NOT `div`). The id values are mandatory and case-sensitive. Even when
a validator suite was not run its section MUST still appear.

  id="header"      `<h1>BMS V&V Report -- Part 1: Validation Data</h1>`
                   then ONE paragraph
                   `<p>Generated YYYY-MM-DD. Companion files:
                    <code>FULL_REPORT.json</code> (raw data) and
                    <code>REPORT_PART2.html</code> (analysis &
                    verdict).</p>`. NO `<h2>` here.
  id="summary"     `<h2>Summary</h2>`. Two short paragraphs naming
                   what was verified, the headline pass/fail counts,
                   and the companion JSON file (mention pointers
                   like `/validation/mil/results/3` address single
                   rows). Then a small KPI table from `kpis` with
                   columns metric | value -- include: tests total,
                   tests passed, tests failed, MIL pass-rate,
                   SIL pass-rate, PIL pass-rate, suites run.
  id="scope"       `<h2>Scope</h2>`. A bullet list of the four
                   verification tiers (MIL, SIL, PIL, static
                   analysis): one line each = purpose + ISO
                   26262-6:2018 clause + suite `ref`. For a suite
                   marked `not_run`, the bullet still appears with
                   "(not run in this invocation)" instead of a ref.
                   The static-analysis bullet cites
                   `/analysis` as its ref (the data lives in part 2).
  id="mil"         `<h2>MIL Results</h2>`. If `mil.not_run` is true,
                   emit ONE paragraph: "MIL was not run in this
                   pipeline invocation." and nothing else.
                   Otherwise: one intro sentence + table
                   `req_id | name | status | reference`, ONE row
                   per `mil.tests`. Under the table, ONE
                   `<details><summary>...</summary>...</details>`
                   per non-pass test (error string + failing-check
                   refs). If all tests passed, no `<details>`.
  id="sil"         `<h2>SIL Results</h2>`. If `sil.not_run` is true,
                   emit ONE paragraph: "SIL was not run in this
                   pipeline invocation." Otherwise: one intro
                   sentence + table
                   `check | status | value | threshold | reference`,
                   ONE row per check in `sil.tests[*].checks`. End
                   with one sentence on observed numeric drift.
  id="pil"         `<h2>PIL Results</h2>`. If `pil.not_run` is true,
                   emit ONE paragraph: "PIL was not run in this
                   pipeline invocation." Otherwise: same table
                   shape as SIL, plus one sentence calling out
                   WCET vs budget (us), RAM vs budget (KB), and
                   predictor max-abs-err PIL-vs-MIL.

""" + _REF_RULES


USER_PROMPT_TEMPLATE_A = (
    "Generate PART 1 (validation data) of the BMS V&V HTML report from "
    "this slim JSON. Render every test and every check with its `ref` "
    "quoted as `<code>`. Companion full-data file: `{full_report}`."
    "\n\n```json\n{payload}\n```"
)


# ---------------------------------------------------------------- Part 2

SYSTEM_PROMPT_B = """\
You write PART 2 of a two-file V&V SUMMARY report for a 96s1p
Samsung-SDI BMS (1 master + 8 slave ECUs, embedded LSTM fault
predictor) under ISO 26262 ASIL D.

PART 2 covers: header, engineering analysis (rule-engine findings &
recommendations), and the release verdict / conclusion. The MIL /
SIL / PIL data tables live in PART 1 -- DO NOT repeat them here.

Input JSON keys: `project`, `kpis`, `full_report`, `analysis`,
`validator_summary` (read-only headline counts so you can phrase the
verdict consistently). `kpis.suites_run` lists which validator
tiers actually ran in this invocation.

OUTPUT: ONE complete HTML5 document. Start `<!doctype html>`, end
`</html>`. No markdown fences, no JS, no external assets.

""" + _STYLE_BLOCK + """

REQUIRED SECTIONS -- emit ALL THREE, in this exact order, each wrapped
in `<section id="ID">...</section>` (the literal tag name `section`,
NOT `div`). The id values are mandatory and case-sensitive.

  id="header"      `<h1>BMS V&V Report -- Part 2: Analysis &
                   Verdict</h1>` then ONE paragraph
                   `<p>Generated YYYY-MM-DD. Validation tables
                   live in <code>REPORT_PART1.html</code>; raw data
                   in <code>FULL_REPORT.json</code>.</p>`.
                   NO `<h2>` here.
  id="analysis"    `<h2>Engineering Analysis</h2>`. One intro
                   sentence quoting the total finding count and the
                   counts per severity from `analysis.summary`.
                   Then ONE block per entry in `analysis.rules`,
                   ordered as supplied:

                     <section class="rule">
                       <h3>{rule_id} -- {finding}</h3>
                       <p><em>Severity:</em> {severity}.
                          <em>Occurrences:</em> {count}.
                          <em>WIP:</em> yes/no.</p>
                       <p><strong>Why it matters.</strong>
                          {reasoning}</p>
                       <p><strong>Recommended action(s).</strong></p>
                       <ul>{<li> per recommend item}</ul>
                       <p><strong>References.</strong>
                          {comma-separated <code>ref</code>s from
                          the rule's `refs` array}</p>
                     </section>

                   If `analysis.rules` is empty, emit ONE paragraph:
                   "No findings produced by the rule engine."
  id="conclusion"  `<h2>Conclusion</h2>`. Two short paragraphs:
                     (a) Can release proceed? Tie the verdict to the
                         severity counts AND to the suites listed
                         in `kpis.suites_run` (explicitly note
                         which suites were skipped, if any).
                     (b) The TOP 3 unblocking actions in execution
                         order, each citing the `<code>ref</code>`
                         it derives from.

""" + _REF_RULES


USER_PROMPT_TEMPLATE_B = (
    "Generate PART 2 (engineering analysis & verdict) of the BMS V&V "
    "HTML report from this slim JSON. Render every rule with the "
    "<code>ref</code>s from its `refs` array. Companion full-data "
    "file: `{full_report}`. Companion data tables: "
    "`REPORT_PART1.html`."
    "\n\n```json\n{payload}\n```"
)


# ---------------------------------------------------------------- back-compat
#
# Some legacy callers (older orch.run, ad-hoc scripts) still import the
# single-shot names. Map them to part 1 so an outdated import path keeps
# producing _something_ rather than crashing on ImportError.
SYSTEM_PROMPT          = SYSTEM_PROMPT_A
USER_PROMPT_TEMPLATE   = USER_PROMPT_TEMPLATE_A
