# SETUP — porting the BMS Engineering Assistant to a fresh PC

This guide brings a clean machine up to the point where `mil.run`,
`sil.run`, `pil.run`, and the App-Designer UI all work.

> Tested on Windows 10/11 + MATLAB R2024b (Update 2). Linux/macOS will work
> for MIL and most of the Python tooling; SIL/PIL need a Windows host
> because the STM32 support package ships MSVC and arm-none-eabi binaries
> for Windows only.

---

## 1. Prerequisites

### 1.1 MATLAB R2024b + toolboxes

Install via the MathWorks installer (`mpm` works in batch too):

| Product | Purpose |
| --- | --- |
| MATLAB R2024b | required runtime |
| Simulink | model execution |
| Stateflow | severity FSM (`bms_master/Severity_FSM`) |
| Simulink Coder | C code generation |
| Embedded Coder | ert.tlc target + code-execution profiling (WCET) |
| MATLAB Coder | dependency of the above |
| Simulink Coverage | dead-code report (`cov.run`) |
| Deep Learning Toolbox | LSTM predictor (`fault_predictor`) + ONNX import |
| Deep Learning Toolbox Converter for ONNX | imports the trained `.onnx` |
| Embedded Coder Support Package for STMicroelectronics STM32 Processors | PIL target |
| MATLAB Support for MinGW-w64 C/C++ Compiler | host SIL build |

After install, verify in MATLAB:

```matlab
ver('embeddedcoder')                       % must list R2024b
matlab.addons.installedAddons              % must contain "STM32"
```

### 1.2 STM32 toolchain (only for PIL)

Hardware: STM32 Nucleo-H7A3ZI-Q board, USB to PC (ST-Link enumerates as a
virtual COM port).

Install:

| Tool | Default install path | Override env var |
| --- | --- | --- |
| STM32CubeMX 6.4+   | `C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeMX`      | `BMS_STM32CUBEMX` |
| STM32CubeProgrammer 2.6+ | `C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeProgrammer` | `BMS_STM32CUBEPROG` |

If installed elsewhere, set the env vars before launching MATLAB:

```powershell
$Env:BMS_STM32CUBEMX     = 'D:\STM32\STM32CubeMX'
$Env:BMS_STM32CUBEPROG   = 'D:\STM32\STM32CubeProgrammer'
matlab.exe
```

`pil.detect_stlink_port` auto-detects the COM port. If you need to pin a
specific port, edit `validator/pil/+pil/detect_stlink_port.m` or set
`comPort` directly in `pil.configure.m` line 16.

### 1.3 Python 3.10+ (for `doc_generator`, `analyzer`, `tests/python`)

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt   # see below
```

Direct dependencies (no `requirements.txt` is committed yet):

| Package | Used by |
| --- | --- |
| `pytest`            | `tests/python`, `tests/integration` |
| `onnxruntime`       | `ai/fault_prediction/scripts/python` (training) |
| `numpy`, `pandas`, `matplotlib`, `scipy`, `scikit-learn` | data prep + EDA |
| `pyyaml`            | `analyzer/knowledge/` rules loader |

The runtime `doc_generator/llm_client.py` uses only the stdlib (`urllib`,
`json`), so it has no Python deps.

### 1.4 LLM API key (for `doc_generator`)

The report builder reads (in order):
1. `--api-key` CLI argument
2. `$LLM_API_KEY` env var
3. `$WISGATE_API_KEY` env var
4. `$GROQ_API_KEY` env var

For the MATLAB orchestrator there is an additional fallback:
`orch/+orch/api_key.m` (gitignored). Create it like:

```matlab
function k = api_key
% orch.api_key  hardcoded LLM key (this file is in .gitignore).
k = 'gsk_...your_groq_key...';
end
```

---

## 2. First-time MATLAB bring-up

```powershell
cd <repo>
matlab.exe -sd "$PWD"            % open the repo as cwd
```

In MATLAB:

```matlab
setup_project              % one-time: register the MATLAB project,
                           % builds resources/ + slprj/ caches
startup                    % every session: add paths + run init_system
```

`startup.m` runs `model/system/params/init_system.m`, which is the SINGLE
source of truth for every threshold, debounce window, balancing current,
thermal setpoint, and LSTM hyper-parameter consumed by both the models
and the tests. There are NO magic numbers in the test files.

---

## 3. Smoke validation

Run in MATLAB after `startup`:

```matlab
mil.run('suites', {'bms'})           % ~3-5 min — pure MATLAB, no codegen
sil.run                              % ~1 min after first SIL build (~5 min cold)
pil.run                              % needs Nucleo connected — ~10 min cold
cov.run                              % ~3 min, Coverage toolbox required
```

Results land in:
- `validator/reports/{MIL,SIL,PIL,COV}.json` (sticky latest)
- `validator/reports/plots/{mil,sil,pil}/` (one verdict figure per test)

The UI:

```matlab
bms_assistant
```

---

## 4. Python smoke

```powershell
.venv\Scripts\Activate.ps1
pytest -q                            % unit tests
pytest tests/integration -q          % integration (drives matlab -batch)
```

For the doc generator (offline of MATLAB):

```powershell
$Env:GROQ_API_KEY = '<key>'
python -m doc_generator --in validator\reports\MIL.json doc_generator\reports\REPORT.html
```

---

## 5. Regenerating heavyweight artefacts

These are gitignored and are recomputed automatically by the entry points
above:

| Artefact | Regenerator |
| --- | --- |
| `slprj/`, `*_ert_rtw/`, `*.mexw64`, `*.slxc` | `sil.run` / `pil.run` |
| `validator/reports/plots/*` | each MIL/SIL/PIL test |
| `model/system/params/cell_variability.mat` | `init_system.m` first run |
| `model/plant/params/drivecycles_sim.mat` | `model/plant/build_drivecycles.m` |
| `resources/` (MATLAB project metadata) | `setup_project.m` |
| `ai/fault_prediction/data/` | `ai/fault_prediction/scripts/python/build_dataset.py` |

The raw BMW i3 dataset and the cleaned trip pickles under `data/` are
**not** in the repo and are recreated by the scripts in
`ai/data_preparation/`. The cell-level Samsung datasheet curves under
`model/plant/params/` are committed.

---

## 6. Troubleshooting

| Symptom | Fix |
| --- | --- |
| `Unable to resolve the name 'val.scenario_plot'`         | call `startup` first |
| PIL hangs on `Connecting to target...`                   | wrong COM port — edit/override `pil.detect_stlink_port` |
| `PIL:pil:ConfigClassError - "STM32 Targets"`             | DO NOT add `CustomInclude` / `CustomDefine='-DMW_DCACHE_ENABLED'` / `data.Connection.SerialModule` — see `memories/repo/bms-engineering-assistant.md` |
| `arm-none-eabi-size.exe not found` (REQ-LL-RT-RAM-01)    | reinstall the STM32 Embedded Coder support pkg (provides the GNU ARM toolchain under `C:\ProgramData\MATLAB\SupportPackages\R2024b\3P.instrset\gnuarm-armcortex.instrset`) |
| `HTTP 413 / rate_limit_exceeded` (doc_generator)         | free-tier Groq TPM is 8000; wait ~60 s and retry |
| `Python-urllib/3.x` rejected by Cloudflare (Groq)        | already handled in `doc_generator/llm_client.py` (explicit `User-Agent`) |
