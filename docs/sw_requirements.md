# Software-Level Requirements (REQ-SW-*)

This document captures the *software side* of the V-model — the Python and
MATLAB tooling that surrounds the BMS Simulink models. The model-level
requirements live in [`validator/requirements/requirements.json`](../validator/requirements/requirements.json)
(REQ-HL-* and REQ-LL-*); this file complements them with REQ-SW-* IDs that
each map to one or more automated tests under `tests/`.

Acceptance tests for the GUI (`app/bms_assistant.m`) are performed
**manually** through the running application and are intentionally not
covered by automated test suites.

## Conventions

- IDs are `REQ-SW-<MODULE>-<NN>`.
- Each requirement maps to ≥1 unit test in `tests/python/` or
  `tests/matlab/` and ≥1 integration scenario in `tests/integration/`.
- Verification status is rolled up by `pytest` (Python) and
  `matlab.unittest.TestRunner` (MATLAB).

## orchestrator/ (CLI driver)

| ID                | Statement                                                                                              |
| ----------------- | ------------------------------------------------------------------------------------------------------ |
| REQ-SW-ORCH-01    | `orchestrator.cli.parse_args` SHALL accept `--mil/--sil/--pil/--cov/--analysis/--doc-only` switches and reject unknown flags. |
| REQ-SW-ORCH-02    | The CLI SHALL exit non-zero when no validation phase is requested AND `--doc-only` is not passed.       |
| REQ-SW-ORCH-03    | When invoked with `--dry-run`, the CLI SHALL NOT spawn `matlab` or any LLM call.                        |

## doc_generator/

| ID                | Statement                                                                                              |
| ----------------- | ------------------------------------------------------------------------------------------------------ |
| REQ-SW-DOC-01     | `consolidate.build_full` SHALL pass through MIL/SIL/PIL/COV/analyzer reports verbatim, preserving timestamps and per-test details. |
| REQ-SW-DOC-02     | `consolidate.build_slim` SHALL emit a stub `{not_run: true, ref, summary, tests:[]}` for any suite passed as `None`. |
| REQ-SW-DOC-03     | `consolidate.build_slim` SHALL set `kpis.suites_run` to the union of suites whose input was non-empty. |
| REQ-SW-DOC-04     | `prompt.SYSTEM_PROMPT_A` and `prompt.SYSTEM_PROMPT_B` SHALL together require exactly the 9 sections (header,summary,scope,mil,sil,pil,header,analysis,conclusion) using literal `<section id="...">` wrappers. |
| REQ-SW-DOC-05     | `cli._trim_part1` and `cli._trim_part2` SHALL bring the merged token estimate under `TPM_BUDGET=7600` for any well-formed slim payload. |
| REQ-SW-DOC-06     | `llm_client.chat` SHALL set an explicit `User-Agent` header (default Python urllib UA is rejected by Cloudflare). |
| REQ-SW-DOC-07     | `cli.audit_refs` SHALL accept JSON Pointers (leading `/`) referenced via `<code>...</code>` and SHALL ignore filenames without leading `/`. |

## analyzer/ (Python expert system + MATLAB collectors)

| ID                | Statement                                                                                              |
| ----------------- | ------------------------------------------------------------------------------------------------------ |
| REQ-SW-ANA-01     | `analyzer.facts.load` SHALL merge FACTS.json + COV/MIL/SIL/PIL reports into one read-only context object accessible via dotted-path lookup. |
| REQ-SW-ANA-02     | `analyzer.engine.run` SHALL fire each rule at most once per run, except `forEach` rules which expand one finding per binding match. |
| REQ-SW-ANA-03     | `analyzer.engine.run` SHALL down-rank findings whose locator is on the WIP allowlist to severity `info` and prefix the title with `[WIP]`. |
| REQ-SW-ANA-04     | `analyzer.rules.load` SHALL parse YAML files under `analyzer/knowledge/` and SHALL reject rules missing the required keys (`id`, `premise`, `severity`). |
| REQ-SW-ANA-05     | `analyzer.reporter.format_finding` SHALL emit a MATLAB locator command (`hilite_system('<path>')`) when the finding involves a Simulink block path. |
| REQ-SW-ANA-06     | `+ana/collect.m` SHALL silently skip blocks whose parent has a non-empty `MaskType` or `ReferenceBlock` (library shadows). |
| REQ-SW-ANA-07     | `+ana/collect.m` SHALL aggregate default-named blocks per parent (one finding per offending subsystem). |

## orch/ (MATLAB pipeline driver)

| ID                | Statement                                                                                              |
| ----------------- | ------------------------------------------------------------------------------------------------------ |
| REQ-SW-MOR-01     | `orch.run` SHALL accept `paths`, `mil_filter`, `sil_filter`, `pil_filter`, `skip_build`, `log_cb`, `progress_cb` name/value pairs. |
| REQ-SW-MOR-02     | `orch.run` SHALL stamp `out.error`, `out.failed_phase`, `out.elapsed_s` when any phase throws.         |
| REQ-SW-MOR-03     | `orch.run/local_norm_filter` SHALL accept either a string scalar, a `cellstr`, or empty input and SHALL return a `cellstr`. |
| REQ-SW-MOR-04     | `orch.list_reports` SHALL union the timestamps of `REPORT_PART1_*.html`, `REPORT_PART2_*.html`, legacy `REPORT_*.html`, and `FULL_REPORT_*.json`, newest first. |
| REQ-SW-MOR-05     | `orch.scenarios` SHALL return one struct per pipeline path (mil/sil/pil) with at minimum `name`, `filter` and (for mil) `subsystem`. |

## val/ (MATLAB validation helpers)

| ID                | Statement                                                                                              |
| ----------------- | ------------------------------------------------------------------------------------------------------ |
| REQ-SW-VAL-01     | `val.signal` SHALL resolve a logged signal by exact name, by source-Outport block name, or by case-insensitive substring match (in that order). |
| REQ-SW-VAL-02     | `val.master_inputs` SHALL build a `Simulink.SimulationData.Dataset` whose elements match every root inport of `bms_master`. |
| REQ-SW-VAL-03     | `val.snapshot_ws` / `val.restore_ws` SHALL preserve and restore the BMS test parameter variables across one test invocation. |
| REQ-SW-VAL-04     | `val.scenario_plot` SHALL render one narrative-timeline figure per MIL test (stim panels, response panels, phase bands, threshold lines, assertion markers, PASS/FAIL banner) at the requested path. `val.equivalence_plot` SHALL render the MIL vs SIL/PIL overlay + per-step |error| vs tolerance for the host-vs-target equivalence tests. |
| REQ-SW-VAL-05     | `val.export_json` SHALL whitelist only `timestamp`, `suite`, `summary`, and per-test `req_id`/`name`/`status`/`signals_plot`/`checks` fields. |

## ana/ (MATLAB metric collectors)

| ID                | Statement                                                                                              |
| ----------------- | ------------------------------------------------------------------------------------------------------ |
| REQ-SW-ANM-01     | `ana.collect` SHALL emit a JSON file at `analyzer/reports/FACTS.json` containing the union of all `metrics_*` collectors. |
| REQ-SW-ANM-02     | Each `metrics_*` collector SHALL succeed on the `bms_master`, `bms_slave` and `fault_predictor` reference models and SHALL never throw on an empty model. |

## Verification cross-reference

Tests live under `tests/`:

- `tests/python/`         — pytest unit tests (one file per module).
- `tests/matlab/`         — `matlab.unittest.TestCase` classes for `+orch`, `+val`, `+ana` helpers.
- `tests/integration/`    — end-to-end pytest scenarios that drive `python -m doc_generator`, `python -m analyzer`, `matlab -batch ana.collect`.

Run all Python tests:

```sh
pytest -q
```

Run all MATLAB tests:

```matlab
runtests('tests/matlab','IncludeSubfolders',true)
```
