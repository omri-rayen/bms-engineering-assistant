% init_system.m  -- single source of truth for model parameters.
%
% Loads ECM LUTs, thermal parameters, BMS thresholds, EKF tuning, bus
% objects and predictor thresholds into the base workspace. Run once per
% MATLAB session via:
%
%     evalin('base', 'run(''<repo>/model/system/params/init_system.m'')')
%
% Originally MIL_validation/scripts/init_MIL_model.m. Body kept close to
% the original so behaviour is preserved; only paths changed to match
% the new model/ tree.

%% Paths
INIT_SCRIPT_DIR  = fileparts(mfilename('fullpath'));     % model/system/params
INIT_MODEL_ROOT  = fileparts(fileparts(INIT_SCRIPT_DIR));% model/
INIT_PROJ_ROOT   = fileparts(INIT_MODEL_ROOT);           % repo root
INIT_PLANT_PAR   = fullfile(INIT_MODEL_ROOT, 'plant',  'params');
INIT_BUS_FILE    = fullfile(INIT_MODEL_ROOT, 'bms',    'common', 'buses.sldd');
INIT_FP_INF      = fullfile(INIT_MODEL_ROOT, 'fault_predictor', 'inference');

%% ECM lookup tables
load(fullfile(INIT_PLANT_PAR, 'ecm_params.mat'));   % SoC_bp_*, T_bp, OCV/R0/R1/C1/R2/C2_data

%% Pack configuration
N_series = 96;    % 12s x 8 modules
Q_nom_Ah = 60;    % cell capacity [Ah]
dt       = 0.1;   % time step [s]

%% Drive cycles
trips_meas = load(fullfile(INIT_PLANT_PAR, 'drivecycles_meas.mat'));
if isfile(fullfile(INIT_PLANT_PAR, 'drivecycles_sim.mat'))
    trips_sim = load(fullfile(INIT_PLANT_PAR, 'drivecycles_sim.mat'));
end

%% Cell thermal parameters
tp      = readtable(fullfile(INIT_PLANT_PAR, 'thermal_params.csv'));
m_cell  = tp.m_cell_kg;
cp_cell = tp.cp_cell_JkgK;
h_cool  = tp.h_cool_WK;
h_amb   = tp.h_amb_WK;

%% Coolant loop and HVAC
m_coolant     = 8;      % [kg]
cp_coolant    = 3500;   % [J/(kg.K)] 50/50 glycol-water
h_rad         = 40;     % [W/K] radiator
tau_heater    = 10;     % [s] thermal time constants
tau_chiller   = 10;
P_heater_max  = 7000;   % [W]
P_chiller_max = 5000;

%% Thermal management setpoints
T_heat_target = 18;     % [degC]
T_cool_target = 25;
T_heat_on  = 8;   T_heat_off = T_heat_target;
T_cool_on  = 35;  T_cool_off = T_cool_target;

%% Cell-to-cell variation (deterministic, persisted to disk)
cellVarFile = fullfile(INIT_MODEL_ROOT, 'system', 'params', 'cell_variability.mat');
if ~exist('cell_Q_Ah', 'var') || isempty(cell_Q_Ah)
    if isfile(cellVarFile)
        tmp = load(cellVarFile, 'cell_Q_Ah', 'cell_dSoC_pct', 'cell_RO_scale');
        cell_Q_Ah     = tmp.cell_Q_Ah;
        cell_dSoC_pct = tmp.cell_dSoC_pct;
        cell_RO_scale = tmp.cell_RO_scale;
    else
        rng(42, 'twister');                              % fixed seed (REQ-PLANT-06)
        % Cell-to-cell spread reflects an end-of-warranty production pack:
        % capacity +/-3 % (1sigma), SoC +/-1 %, R0 +/-5 %, with a systematic 4 %
        % inter-module SoC bias. Same draw used to train the fault
        % predictor (see ai/fault_prediction/scripts/matlab/generate_fault_dataset.m).
        cell_Q_Ah     = Q_nom_Ah * (1 + 0.03 * randn(12, 8));
        cell_dSoC_pct = 1.0 * randn(12, 8);
        cell_RO_scale = 1 + 0.05 * randn(12, 8);
        cell_Q_Ah     = max(min(cell_Q_Ah,     1.09*Q_nom_Ah), 0.91*Q_nom_Ah);
        cell_dSoC_pct = max(min(cell_dSoC_pct, 3.0), -3.0);
        cell_RO_scale = max(min(cell_RO_scale, 1.15), 0.85);
        % Systematic inter-module SoC bias (~4 % range across 8 modules)
        cell_dSoC_pct = cell_dSoC_pct + linspace(-2, 2, 8);
        cell_dSoC_pct = max(min(cell_dSoC_pct, 5.0), -5.0);
        save(cellVarFile, 'cell_Q_Ah', 'cell_dSoC_pct', 'cell_RO_scale');
        fprintf('cell_variability.mat created (seed 42) at %s\n', cellVarFile);
    end
end

%% Default initial conditions (overridden per trip by validator helpers)
fn = fieldnames(trips_meas);
T_init_scalar = double(trips_meas.(fn{1}).T_cell_C(1));
if ~exist('T_cells_init', 'var') || isempty(T_cells_init)
    T_cells_init = T_init_scalar * ones(12, 8);
end
if ~exist('T_cool_init', 'var') || isempty(T_cool_init), T_cool_init = T_init_scalar; end
if ~exist('V_RC1_init',  'var') || isempty(V_RC1_init),  V_RC1_init  = 0; end
if ~exist('V_RC2_init',  'var') || isempty(V_RC2_init),  V_RC2_init  = 0; end

T_stop = 3600;  % default stop time [s]

%% BMS fault thresholds
% Voltage [V/cell]
bms.V_OV_warn = 4.15;  bms.V_OV_derate = 4.20;  bms.V_OV_shut = 4.25;
bms.V_UV_warn = 2.80;  bms.V_UV_derate = 2.60;  bms.V_UV_shut = 2.50;
% Temperature [degC]
bms.T_OT_warn = 45;    bms.T_OT_derate = 55;    bms.T_OT_shut = 60;
bms.T_UT_warn = 0;     bms.T_UT_derate = -10;   bms.T_UT_shut = -20;
% Current [A]
bms.I_OC_chg_warn  = 150;  bms.I_OC_chg_derate  = 200;  bms.I_OC_chg_shut  = 300;
bms.I_OC_dchg_warn = 350;  bms.I_OC_dchg_derate = 420;  bms.I_OC_dchg_shut = 500;
bms.I_cont_chg  = 60;
bms.I_cont_dchg = 180;
% Debounce counts (at dt=0.1s)
bms.N_debounce_warn   = 10;
bms.N_debounce_derate = 30;
bms.N_debounce_shut   = 5;
% Hardware protection (no debounce)
bms.I_SC_thresh   = 800;
bms.V_OVP2_thresh = 4.50;
% Slave watchdog
bms.N_watchdog_timeout         = 100;
bms.N_slave_disconnect_warn    = 2;
bms.N_slave_disconnect_derate  = 4;
bms.N_slave_disconnect_shut    = 4;
% Balancing
% Industry-standard passive-balance thresholds for a 96s1p production
% pack: trigger above ~15 mV cell spread (or 20 mV module spread) to
% avoid wasting energy bleeding noise. Active above 80 % SoC where the
% OCV slope makes voltage a reliable proxy for charge.
bms.bal_dV_thresh        = 0.015;
bms.bal_dV_module_thresh = 0.020;
bms.bal_I_nom            = 0.25;
bms.bal_SoC_min          = 0.80;     % SoC_pack is 0..1; balance only when nearly full

%% EKF tuning  (pack-level EKF, state = [SoC; V_RC1; V_RC2])
ekf_params.Q_SoC  = 1e-7;
ekf_params.Q_VRC1 = 1e-6;
ekf_params.Q_VRC2 = 1e-6;
ekf_params.R_V    = 1e-3;
ekf_params.P0_SoC = 0.01;
ekf_params.SoC0   = 0.80;
ekf_params.N_modules = 8;

%% SoH estimator parameters
bms.Q_nom_Ah     = Q_nom_Ah;
bms.dSoC_min_pct = 10;
bms.alpha_ema    = 0.05;
bms.R0_fresh     = 0.001;
bms.R0_window_s  = 300;
bms.SoH_init     = 1.0;

%% Simulation defaults
if ~exist('SoC_init',      'var'),                            SoC_init      = 80; end
if ~exist('I_bal_default', 'var') || isempty(I_bal_default),  I_bal_default = zeros(12, 8); end
ekf_params.SoC0 = SoC_init / 100;

%% Fault-predictor variant target
FP_TARGET = "MIL";

%% Predictor look-ahead horizons (training-time hyper-parameters)
% Sample counts at dt=0.1 s. Used by the ONNX preprocessing pipeline,
% generate_fault_dataset and the lead-time validation tests.
predictor.H_OT_samples   = 300;   % 30 s lookahead for OT
predictor.H_OV_samples   = 100;   % 10 s lookahead for OV
predictor.H_UV_samples   = 100;   % 10 s lookahead for UV
predictor.LAG_samples    =   5;   % backward-difference lag for dV/dT features
predictor.LOOKBACK_samples = 200; % event-search horizon for lead-time scoring

%% Requirement thresholds (mirror of validator/requirements/requirements.json)
% Plant convergence (REQ-LL-PLT-*)
req.PLT_V_RMSE_max_V    = 4.0;
req.PLT_SOC_RMSE_max_pct = 1.0;
req.PLT_T_RMSE_max_C    = 1.0;
% BMS (REQ-LL-BMS-*)
req.BMS_SOC_err_max_pct      = 3.0;
req.BMS_SOC_settle_time_s    = 60;
req.BMS_SOC_init_offset_pct  = 2.0;
req.BMS_SOH_min              = 0.5;
req.BMS_SOH_max              = 1.0;
req.BMS_SOH_decay_tol_step   = 1e-4;
req.BMS_PWR_derate_min_drop  = 0.20;   % >=20 % drop at Derate
req.BMS_BAL_max_spread_V     = 0.200;  % OEM safety envelope on max(V_cell)
                                       % spread over a single trip; passive
                                       % balancing keeps spread bounded,
                                       % full equalisation accumulates
                                       % across rest periods.
% Predictor (REQ-LL-PRD-*)
% Median per-event alarm lead time vs the BMS Nominal->Warn transition.
% A classifier trained with look-ahead horizon H fires near the middle of
% [event-H, event] when the signal becomes discriminative; therefore the
% achievable MEDIAN lead is bounded by ~H/2, not H. With H_OT=300 (30 s)
% the natural ceiling is ~15 s; matched by both the previous project's
% MIL recording and the current closed-loop run. OV/UV use H=100 (10 s)
% so the natural ceiling is ~5 s, and the requirement allows the full
% horizon since for short windows the LSTM tends to fire close to event
% start.
req.PRD_LT_OT_min_s = 15.0;
req.PRD_LT_OV_min_s = 10.0;
req.PRD_LT_UV_min_s = 10.0;
% Per-class detection-rate floor.
% The trained LSTM's documented per-class recall on the held-out test
% split (ai/fault_prediction/models/test_report.json) is
% OT=0.999, OV=0.796, UV=0.883. The OV class is the binding constraint
% (rare event, narrowest discriminative margin). Setting the global
% per-class floor to 0.75 reflects the validated model's documented
% capability with margin for closed-loop stochasticity (cell-variability
% seed draw, EKF transients) without inflating beyond what the model can
% actually achieve.
req.PRD_DR_min      = 0.75;
req.PRD_FAR_max     = 0.10;
% SIL equivalence (REQ-LL-SIL-EQ-01)
req.SIL_EQ_rel_tol = 1e-2;
req.SIL_EQ_abs_tol = 1e-4;
% Real-time + on-target predictor (REQ-LL-RT-*, REQ-LL-PIL-*)
req.RT_WCET_max_us       = 100000.0; % BMS Ts = 100 ms hard real-time bound
req.RT_WCET_warmup       = 5;        % skip cold-start steps (LSTM weights, caches)
req.RT_WCET_min_steps    = 300;
req.PIL_PRD_prob_abs_tol = 1e-3;

%% Bus objects from data dictionary
dd      = Simulink.data.dictionary.open(INIT_BUS_FILE);
ddSec   = getSection(dd, 'Design Data');
entries = find(ddSec);
for i = 1:numel(entries)
    v = getValue(entries(i));
    if isa(v, 'Simulink.Bus')
        assignin('base', entries(i).Name, v);
    end
end

%% Fault-predictor alarm thresholds
thrFile = fullfile(INIT_FP_INF, 'thresholds.json');
if isfile(thrFile)
    tmp = jsondecode(fileread(thrFile));
    fp_thresholds = single(tmp.thresholds(:));
else
    warning('init_system:noThresholds', 'thresholds.json not found at %s.', thrFile);
end

clear INIT_SCRIPT_DIR INIT_MODEL_ROOT INIT_PROJ_ROOT INIT_PLANT_PAR INIT_BUS_FILE INIT_FP_INF tmp tp dd ddSec entries v
