# V-Model Audit

This document audits the V-model coverage of the BMS Engineering Assistant.
It is a static, human-readable cross-reference for review. The
machine-readable mapping lives in
[`validator/requirements/requirements.json`](../validator/requirements/requirements.json)
(model level) and [`docs/sw_requirements.md`](sw_requirements.md) (software
level); both are kept consistent with the test files cited below.

The project realises **two parallel V-models** that share the same
requirements catalogue:

1. **Model-level V** — *Requirement → Model → MIL → SIL → PIL*. Verifies
   the embedded control behaviour against the virtual plant and on the
   STM32 target.
2. **Software-level V** — *Requirement → Code → Unit → Integration →
   Acceptance*. Verifies the Python + MATLAB tooling that orchestrates,
   analyses, and reports on the model-level pipeline.

---

## 1. Model-level V-model

```
  REQ-HL / REQ-LL ─────────────────────────────────────────────► acceptance (UI)
        │                                                                  ▲
        ▼                                                                  │
   modelling                                                           closed loop
   (model/)                                                       PIL on STM32 H7A3
        │                                                                  ▲
        ▼                                                                  │
   MIL  (validator/mil)  ──► SIL (validator/sil) ──► PIL (validator/pil) ──┘
```

### 1.1 Left leg — decomposition + design

| Stage | Artefact | Source of truth |
| --- | --- | --- |
| System requirements    | `REQ-HL-*` (high-level)             | `validator/requirements/requirements.json` (`high_level`) |
| Module requirements    | `REQ-LL-*` (low-level)              | `validator/requirements/requirements.json` (`low_level`)  |
| Thresholds / params    | Numeric values cited by every REQ   | `model/system/params/init_system.m` (single source of truth, **no magic numbers** in tests) |
| Plant model            | 96s1p ECM-2RC + thermal             | `model/plant/`                                            |
| BMS controller         | `bms_master` + 8 × `bms_slave`      | `model/bms/`                                              |
| Fault predictor        | LSTM dlnetwork + ONNX importer      | `model/fault_predictor/`                                  |
| Closed-loop integration | `system_model.slx`                  | `model/system/`                                           |

### 1.2 Right leg — verification

Each REQ-LL is automatically verified by exactly one test file, named
`test_<REQ-ID>.m` and tagged with the requirement ID inside the test:

| Phase | Coverage | Driver | Tests |
| --- | --- | --- | --- |
| **PLANT** (MIL) | virtual plant ↔ measurement | `mil.plant_convergence` | `validator/mil/tests/plant/` (3 tests) |
| **MIL**         | controller logic ↔ plant    | `mil.run('suites',{'bms'})`        | `validator/mil/tests/bms/` (24 tests) |
| **MIL**         | predictor logic             | `mil.run('suites',{'predictor'})`  | `validator/mil/tests/predictor/` (5 tests) |
| **SIL**         | generated C ↔ MIL           | `sil.run`                          | `validator/sil/tests/` (1 test)        |
| **PIL**         | on-target ↔ host            | `pil.run`                          | `validator/pil/tests/` (3 tests)       |
| **COV**         | model dead code             | `cov.run`                          | `validator/cov/` (1 aggregator)        |

### 1.3 Requirement → phase → test mapping

| REQ-LL ID            | Phase(s)        | Test file |
| -------------------- | --------------- | --------- |
| REQ-LL-PLT-V-01      | PLANT           | `validator/mil/tests/plant/test_REQ_LL_PLT_V_01.m` |
| REQ-LL-PLT-SOC-01    | PLANT           | `validator/mil/tests/plant/test_REQ_LL_PLT_SOC_01.m` |
| REQ-LL-PLT-T-01      | PLANT           | `validator/mil/tests/plant/test_REQ_LL_PLT_T_01.m` |
| REQ-LL-BMS-VMON-01   | MIL (+SIL via EQ-01) | `validator/mil/tests/bms/test_REQ_LL_BMS_VMON_01.m` |
| REQ-LL-BMS-VMON-02   | MIL (+SIL)      | `validator/mil/tests/bms/test_REQ_LL_BMS_VMON_02.m` |
| REQ-LL-BMS-TMON-01   | MIL (+SIL)      | `validator/mil/tests/bms/test_REQ_LL_BMS_TMON_01.m` |
| REQ-LL-BMS-TMON-02   | MIL (+SIL)      | `validator/mil/tests/bms/test_REQ_LL_BMS_TMON_02.m` |
| REQ-LL-BMS-IMON-01   | MIL (+SIL)      | `validator/mil/tests/bms/test_REQ_LL_BMS_IMON_01.m` |
| REQ-LL-BMS-IMON-02   | MIL (+SIL)      | `validator/mil/tests/bms/test_REQ_LL_BMS_IMON_02.m` |
| REQ-LL-BMS-FSM-01    | MIL (+SIL)      | `validator/mil/tests/bms/test_REQ_LL_BMS_FSM_01.m` |
| REQ-LL-BMS-FSM-02    | MIL (+SIL)      | `validator/mil/tests/bms/test_REQ_LL_BMS_FSM_02.m` |
| REQ-LL-BMS-SOC-01    | MIL (+SIL)      | `validator/mil/tests/bms/test_REQ_LL_BMS_SOC_01.m` |
| REQ-LL-BMS-SOH-01    | MIL (+SIL)      | `validator/mil/tests/bms/test_REQ_LL_BMS_SOH_01.m` |
| REQ-LL-BMS-SOH-02    | MIL (+SIL)      | `validator/mil/tests/bms/test_REQ_LL_BMS_SOH_02.m` |
| REQ-LL-BMS-BAL-01    | MIL (+SIL)      | `validator/mil/tests/bms/test_REQ_LL_BMS_BAL_01.m` |
| REQ-LL-BMS-BAL-02    | MIL             | `validator/mil/tests/bms/test_REQ_LL_BMS_BAL_02.m` |
| REQ-LL-BMS-BAL-03    | MIL (+SIL)      | `validator/mil/tests/bms/test_REQ_LL_BMS_BAL_03.m` |
| REQ-LL-BMS-THM-01    | MIL (+SIL)      | `validator/mil/tests/bms/test_REQ_LL_BMS_THM_01.m` |
| REQ-LL-BMS-THM-02    | MIL (+SIL)      | `validator/mil/tests/bms/test_REQ_LL_BMS_THM_02.m` |
| REQ-LL-BMS-PWR-01    | MIL (+SIL)      | `validator/mil/tests/bms/test_REQ_LL_BMS_PWR_01.m` |
| REQ-LL-BMS-PWR-02    | MIL (+SIL)      | `validator/mil/tests/bms/test_REQ_LL_BMS_PWR_02.m` |
| REQ-LL-BMS-WDG-01    | MIL (+SIL)      | `validator/mil/tests/bms/test_REQ_LL_BMS_WDG_01.m` |
| REQ-LL-BMS-WDG-02    | MIL (+SIL)      | `validator/mil/tests/bms/test_REQ_LL_BMS_WDG_02.m` |
| REQ-LL-BMS-AGG-01    | MIL (+SIL)      | `validator/mil/tests/bms/test_REQ_LL_BMS_AGG_01.m` |
| REQ-LL-BMS-AGG-02    | MIL (+SIL)      | `validator/mil/tests/bms/test_REQ_LL_BMS_AGG_02.m` |
| REQ-LL-BMS-PRD-01    | MIL (+SIL)      | `validator/mil/tests/bms/test_REQ_LL_BMS_PRD_01.m` |
| REQ-LL-BMS-HWP-01    | MIL (+SIL)      | `validator/mil/tests/bms/test_REQ_LL_BMS_HWP_01.m` |
| REQ-LL-PRD-LT-01     | MIL             | `validator/mil/tests/predictor/test_REQ_LL_PRD_LT_01.m` |
| REQ-LL-PRD-LT-02     | MIL             | `validator/mil/tests/predictor/test_REQ_LL_PRD_LT_02.m` |
| REQ-LL-PRD-LT-03     | MIL             | `validator/mil/tests/predictor/test_REQ_LL_PRD_LT_03.m` |
| REQ-LL-PRD-DR-01     | MIL             | `validator/mil/tests/predictor/test_REQ_LL_PRD_DR_01.m` |
| REQ-LL-PRD-FAR-01    | MIL             | `validator/mil/tests/predictor/test_REQ_LL_PRD_FAR_01.m` |
| REQ-LL-SIL-EQ-01     | SIL             | `validator/sil/tests/test_REQ_LL_SIL_EQ_01.m` |
| REQ-LL-PIL-PRD-01    | PIL             | `validator/pil/tests/test_REQ_LL_PIL_PRD_01.m` |
| REQ-LL-RT-WCET-01    | PIL             | `validator/pil/tests/test_REQ_LL_RT_WCET_01.m` |
| REQ-LL-RT-RAM-01     | PIL             | `validator/pil/tests/test_REQ_LL_RT_RAM_01.m` |
| REQ-LL-COV-DEAD-01   | COV             | `validator/cov/run.m` (aggregator)             |

**Note on `(+SIL)`**: every `REQ-LL-BMS-*` requirement is verified at MIL by
its own dedicated test, *and* implicitly at SIL by `REQ-LL-SIL-EQ-01` which
asserts bit-tolerant signal equivalence between the generated C and the MIL
reference on a representative trip. The MIL test set therefore stands as
the functional contract, and SIL guards against code-generation drift.

### 1.4 Verdict artefacts (per test)

Every test now produces **one verdict figure** beside its JSON line:

| Test family           | Figure shape | Helper             |
| --------------------- | --- | --- |
| BMS MIL (24 tests)    | Stim panels (top) + response panels (bottom), shaded phase bands, threshold lines, green-O / red-X assertion markers, PASS/FAIL banner | `val.scenario_plot` |
| Predictor MIL (5)     | Confusion-counts bar + recall vs `DR_min` + median lead vs per-class min, PASS/FAIL banner | `val.predictor_summary_plot` |
| SIL equivalence (1)   | Per-signal MIL vs SIL overlay (left) + |error| vs tolerance line (right), PASS/FAIL banner | `val.equivalence_plot` |
| PIL equivalence (1)   | Per-class MIL vs PIL overlay + |error| vs tolerance, PASS/FAIL banner | `val.equivalence_plot` |
| PIL WCET (1)          | Per-step on-chip time vs budget (left), distribution histogram (right), cold-start annotated | inline (`i_plot_wcet`) |
| PIL RAM (1)           | No figure (single scalar metric) | — |

All figures are written under `validator/reports/plots/<suite>/`.

---

## 2. Software-level V-model

```
  REQ-SW-*  ───────────────────────────────────────► acceptance (manual UI use)
      │                                                      ▲
      ▼                                                      │
   code        ──► unit  (tests/python, tests/matlab)        │
                          ──► integration (tests/integration)
```

### 2.1 Left leg

| Layer            | Module              | REQ-SW prefix |
| ---------------- | ------------------- | ------------- |
| CLI driver       | `orchestrator/`     | `REQ-SW-ORCH-*` |
| Report builder   | `doc_generator/`    | `REQ-SW-DOC-*`  |
| Analyzer         | `analyzer/python/`, `analyzer/+ana/` | `REQ-SW-ANA-*` / `REQ-SW-ANM-*` |
| MATLAB orchestr. | `orch/+orch/`       | `REQ-SW-MOR-*` |
| MATLAB helpers   | `validator/+val/`   | `REQ-SW-VAL-*` |

### 2.2 Right leg

| Stage          | Location                  | Driver                      |
| -------------- | ------------------------- | --------------------------- |
| Unit (Python)  | `tests/python/`           | `pytest -q`                 |
| Unit (MATLAB)  | `tests/matlab/`           | `runtests('tests/matlab','IncludeSubfolders',true)` |
| Integration    | `tests/integration/`      | `pytest tests/integration -q` (drives `python -m doc_generator`, `python -m analyzer`, `matlab -batch ana.collect`) |
| Acceptance     | `app/bms_assistant.m` UI  | Manual (see `docs/sw_requirements.md` note) |

Every REQ-SW-* in [`docs/sw_requirements.md`](sw_requirements.md) is mapped
to ≥ 1 unit test and ≥ 1 integration scenario; see the *Verification
cross-reference* section at the bottom of that file.

---

## 3. Gaps and known limitations

| Item | Status |
| --- | --- |
| Acceptance tests for the UI | **Manual** — App Designer GUI; not driven by an automated test suite. |
| PIL host-only smoke (no MCU) | The PIL suite refuses to build/run without a connected Nucleo (by design). Off-target CI is therefore MIL+SIL only. |
| Coverage report | Single aggregate (`REQ-LL-COV-DEAD-01`). Decision / Condition / MCDC are emitted *informationally* alongside Execution. |

---

## 4. How to re-audit

```matlab
% List every REQ-LL and the file that verifies it
mil.run                       % runs everything that can run on host
sil.run('skip_build', true)   % SIL (requires Embedded Coder)
pil.run                       % PIL (requires Nucleo + STM32CubeMX/CubeProg)
```

The resulting JSON in `validator/reports/` carries one `req_id` field per
result, so `jq -r '.results[].req_id'` will produce the verified-IDs set
which must equal the set of `low_level[].id` in `requirements.json`.
