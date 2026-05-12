# MATLAB unit tests

These tests cover pure-MATLAB modules (no Simulink simulation required) and
can be run from the repo root with:

```matlab
runtests('tests/matlab', 'IncludeSubfolders', true)
```

Coverage map:

| File                              | Software requirement(s)                |
|-----------------------------------|----------------------------------------|
| `test_val_new_result_check.m`     | REQ-SW-VAL-01, REQ-SW-VAL-02           |
| `test_orch_scenarios.m`           | REQ-SW-MOR-03, REQ-SW-MOR-04           |
| `test_orch_list_reports.m`        | REQ-SW-MOR-01                          |

Tests that exercise full Simulink models (MIL/SIL/PIL runners,
`val.sim_model`, `val.scenario_plot`, `val.equivalence_plot`) are covered by the validator suites
themselves (`mil.run`, `sil.run`, `pil.run`) and by the Plots smoke
verification — they are not duplicated here because cold MATLAB startup
plus model load makes them prohibitively slow for a unit-test loop.

Acceptance tests are performed manually through the UI
(`app/bms_assistant.m`) per the project's V-model definition.
