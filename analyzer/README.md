# analyzer/

Smart-assistant module for the BMS engineering project. It looks at the
already-collected validation evidence (COV / MIL / SIL / PIL JSON
reports) plus a fresh static scrape of the Simulink models, applies a
small rule base, and writes an interpretation report -- "what's wrong,
why it matters, what to do next".

The module is intentionally split in two halves:

- **MATLAB side** (`+ana/`) collects facts only. No analysis, no rules.
  One entry point: `ana.collect`.
- **Python side** (`python/analyzer/`) runs a forward-chaining engine
  over the facts + the validator reports. Rules live in `knowledge/`
  as YAML.

This split keeps the slow, license-bound MATLAB step optional: if you
already have a fresh `FACTS.json`, the Python analyzer runs in well under
a second and can be re-executed as you tweak the rule base.

## Layout

```
analyzer/
  +ana/                MATLAB package -- static fact collection
    collect.m          ana.collect (entry)
    metrics_static.m   block counts, depth, signal hygiene, cyclomatic, ...
    metrics_stateflow.m
    metrics_solver.m
    metrics_codegen.m  generated-C LoC (if <model>_ert_rtw/ exists)
    write_json.m
  python/
    analyzer/          Python package
      cli.py           python -m analyzer
      facts.py         load FACTS + validator JSON into one ctx dict
      rules.py         YAML loader + safe expression evaluator
      engine.py        forward-chaining loop
      reporter.py      writes ANALYSIS.json + stdout digest
    requirements.txt   PyYAML only
  knowledge/           rule base
    asil_policy.yaml   ASIL ratings + numeric thresholds (data, no rules)
    dead_code.yaml     12 rules: 3 models x 4 coverage metrics
    model_arch.yaml    depth, cyclomatic, unconnected ports, multi-rate, ...
    validation.yaml    MIL/SIL/PIL pass-fail + PIL WCET/RAM/predictor headroom
  reports/             ANALYSIS_<ts>.json + sticky ANALYSIS.json
  ROADMAP.txt          design notes
```

## Usage

```matlab
% MATLAB: collect facts about the models
ana.collect
%   [ana ] bms_master           blocks=421 depth=5 cyclo=42  (2.1s)
%   [ana ] bms_slave            blocks=92  depth=3 cyclo=14  (0.4s)
%   [ana ] fault_predictor      blocks=18  depth=2 cyclo=2   (0.2s)
%   Facts: analyzer/reports/FACTS_20260509_142210.json
```

```bash
# Python: run the expert system on the latest facts + validator reports
pip install -r analyzer/python/requirements.txt
python -m analyzer
```

The exit code mirrors the verdict: `0 = ok`, `1 = review_required`,
`2 = blocking`. Useful in CI.

## Output

`ANALYSIS.json` contains:

- `summary` -- counts by severity / category and a one-word verdict.
- `findings` -- each one points at the rule that fired, the bound values,
  the dotted fact paths it consulted (`evidence.facts_used`), the
  reasoning, the recommendations and the standard references.
- `trace` -- the full ordered list of rule firings (which pass, which
  category, which facts) so the reasoning is reproducible and inspectable.

## How the rule base works

Rules are plain YAML. A rule has:

- `when` -- a small expression compared against the working memory.
  Supports comparisons (`>`, `<`, `==`, `in`, ...), `and`/`or`/`not`,
  and dotted-path lookups like `coverage.bms_master.execution.dead_pct`.
  Anything else is rejected by the parser. Missing facts evaluate to
  `False` (the rule simply does not fire), so dropping a YAML or a
  report file degrades gracefully.
- `bind` -- named values used to render `finding` and to populate
  `evidence.values`. Strings that look like dotted paths are resolved
  against the context; literals pass through.
- `severity`, `finding`, `reasoning`, `recommend`, `refs` -- the
  human-facing payload.

Adding or tuning a rule is a one-file YAML edit. No code changes.

## Status

Phase 1-4 of `ROADMAP.txt` are implemented. The roadmap items
deferred for later:

- E1 -- `cov.run` enrichment with per-uncovered-block detail. Not needed
  yet; the rules drive off the percentage metrics that are already in
  `COV.json`.
- E2 -- `asil` field inside `requirements.json`. The current rule base
  carries the ASIL classification in `asil_policy.yaml` instead, which
  keeps the change footprint inside `analyzer/`.
- ModelAdvisor / MAAB rules. Skipped for the first version; the static
  metrics already catch the highest-value findings.
- Acceptance test that injects a known dead block. Will be added in a
  follow-up once the rule base stabilises.
