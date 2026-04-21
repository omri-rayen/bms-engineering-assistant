%% Paths
scriptDir = fileparts(mfilename('fullpath'));
milRoot   = fileparts(scriptDir);
projRoot  = fileparts(milRoot);
plantData = fullfile(projRoot, 'plant_model', 'data');
milData   = fullfile(milRoot, 'data');

%% ECM lookup tables
paramFile = fullfile(plantData, 'ecm_params.mat');
if ~isfile(paramFile)
    error('init_MIL_model:fileNotFound', ...
        'ecm_params.mat not found - run export_luts.m first.\n  Expected: %s', paramFile);
end
load(paramFile);  % SoC_bp_ocv, SoC_bp_ecm, T_bp, OCV/R0/R1/C1/R2/C2_data

%% Pack configuration
N_series = 96;    % 12s x 8 modules
Q_nom_Ah = 60;    % cell capacity [Ah]
dt       = 0.1;   % time step [s]

%% Drive-cycle data
measFile = fullfile(plantData, 'drivecycles_meas.mat');
if isfile(measFile)
    trips_meas = load(measFile);
    fprintf('init_MIL_model: loaded %d measurement trips\n', numel(fieldnames(trips_meas)));
else
    warning('init_MIL_model:noMeasData', 'drivecycles_meas.mat not found.');
    trips_meas = struct();
end

simFile = fullfile(plantData, 'drivecycles_sim.mat');
if isfile(simFile)
    trips_sim = load(simFile);
    fprintf('init_MIL_model: loaded %d simulation trips\n', numel(fieldnames(trips_sim)));
else
    trips_sim = struct();
end

%% Cell thermal parameters
thermalCsv = fullfile(plantData, 'thermal_params.csv');
if isfile(thermalCsv)
    tp      = readtable(thermalCsv);
    m_cell  = tp.m_cell_kg;
    cp_cell = tp.cp_cell_JkgK;
    h_cool  = tp.h_cool_WK;
    h_amb   = tp.h_amb_WK;
else
    m_cell  = 1.3;
    cp_cell = 1000;
    h_cool  = 0.02;
    h_amb   = 0.15;
end

%% Coolant loop
m_coolant  = 8;       % [kg]
cp_coolant = 3500;    % [J/(kg·K)]  50/50 glycol-water
h_rad      = 40;      % [W/K] radiator

%% Heater / chiller
tau_heater    = 10;    % [s] time constant
tau_chiller   = 10;
P_heater_max  = 7000;  % [W]
P_chiller_max = 5000;

%% Thermal management relay thresholds
T_target_heat = 18;   T_target_cool = 25;
T_heat_target = T_target_heat;  % alias used by Simulink
T_cool_target = T_target_cool;  % alias used by Simulink
T_heat_on  = 8;       T_heat_off = T_target_heat;
T_cool_on  = 35;      T_cool_off = T_target_cool;

%% Cell-to-cell variation (generated once per session)
if ~exist('cell_Q_Ah','var') || isempty(cell_Q_Ah)
    cell_Q_Ah     = Q_nom_Ah * (1 + 0.03 * randn(12, 8));
    cell_dSoC_pct = 1.0 * randn(12, 8);
    cell_RO_scale = 1 + 0.05 * randn(12, 8);
    cell_Q_Ah     = max(min(cell_Q_Ah,     1.09*Q_nom_Ah), 0.91*Q_nom_Ah);
    cell_dSoC_pct = max(min(cell_dSoC_pct, 3.0), -3.0);
    cell_RO_scale = max(min(cell_RO_scale, 1.15), 0.85);
end

%% Default initial conditions (overridden per trip by validation scripts)
firstTripFields = fieldnames(trips_meas);
if ~isempty(firstTripFields)
    firstTrip     = trips_meas.(firstTripFields{1});
    T_init_scalar = double(firstTrip.T_cell_C(1));
    fprintf('init_MIL_model: T_cells_init = %.1f °C (from "%s")\n', ...
        T_init_scalar, firstTripFields{1});
else
    T_init_scalar = 25;
end

if ~exist('T_cells_init','var') || isempty(T_cells_init)
    T_cells_init = T_init_scalar * ones(12, 8);
end
if ~exist('T_cool_init','var')  || isempty(T_cool_init),  T_cool_init  = T_init_scalar; end
if ~exist('V_RC1_init','var')   || isempty(V_RC1_init),    V_RC1_init   = 0; end
if ~exist('V_RC2_init','var')   || isempty(V_RC2_init),    V_RC2_init   = 0; end

T_stop = 3600;  % default sim duration [s] - required by bms_master model

%% BMS fault thresholds
% Voltage [V/cell]
bms.V_OV_warn = 4.15;  bms.V_OV_derate = 4.20;  bms.V_OV_shut = 4.25;
bms.V_UV_warn = 2.80;  bms.V_UV_derate = 2.60;  bms.V_UV_shut = 2.50;

% Temperature [°C]
bms.T_OT_warn = 45;    bms.T_OT_derate = 55;    bms.T_OT_shut = 60;
bms.T_UT_warn = 0;     bms.T_UT_derate = -10;   bms.T_UT_shut = -20;

% Current [A]
bms.I_OC_chg_warn  = 150;  bms.I_OC_chg_derate  = 200;  bms.I_OC_chg_shut  = 300;
bms.I_OC_dchg_warn = 350;  bms.I_OC_dchg_derate = 420;  bms.I_OC_dchg_shut = 500;
bms.I_cont_chg  = 60;   % 1C continuous
bms.I_cont_dchg = 180;  % 3C continuous

% Debounce counts (at dt=0.1s)
bms.N_debounce_warn   = 10;  % 1.0 s
bms.N_debounce_derate = 30;  % 3.0 s
bms.N_debounce_shut   = 5;   % 0.5 s

% Hardware protection (no debounce)
bms.I_SC_thresh   = 800;   % [A] short-circuit
bms.V_OVP2_thresh = 4.50;  % [V/cell]

% Slave watchdog
bms.N_watchdog_timeout         = 100;  % 10 s
bms.N_slave_disconnect_warn    = 2;
bms.N_slave_disconnect_derate  = 4;
bms.N_slave_disconnect_shut    = 4;

% Balancing
bms.bal_dV_thresh        = 0.010;  % [V] per-cell voltage spread
bms.bal_dV_module_thresh = 0.12;
bms.bal_I_nom            = 0.1;    % [A] passive bleed current
bms.bal_dSoC_thresh      = 1.0;    % [%] master enable threshold

%% EKF tuning (8 module-level EKFs)
ekf_params.Q_SoC  = 1e-6;
ekf_params.Q_VRC1 = 1e-5;
ekf_params.Q_VRC2 = 1e-5;
ekf_params.R_V    = 1e-3;
ekf_params.P0_SoC = 0.01;
ekf_params.SoC0   = 0.80;
ekf_params.N_modules = 8;

%% SoH estimator
bms.Q_nom_Ah     = Q_nom_Ah;
bms.dSoC_min_pct = 40;       % min delta-SoC for capacity update [%]
bms.alpha_ema    = 0.05;      % R0 EMA smoothing factor
if ~isfield(bms, 'R0_fresh')
    bms.R0_fresh = 0.001;     % fresh-cell R0 at 25°C [Ω]
end
bms.R0_window_s  = 300;

%% Balancing / SoC defaults
if ~exist('I_bal_default','var') || isempty(I_bal_default)
    I_bal_default = zeros(12, 8);
end
if ~exist('SoC_init','var')
    SoC_init = 80;
end
ekf_params.SoC0 = SoC_init / 100;

%% Fault injection defaults (zero = pass-through)
fault_inj_dV = timeseries(0, 0);
fault_inj_dT = timeseries(0, 0);
fault_inj_dI = timeseries(0, 0);

%% Load bus objects from data dictionary
slddFile = fullfile(milData, 'buses.sldd');
if isfile(slddFile)
    dd      = Simulink.data.dictionary.open(slddFile);
    ddSec   = getSection(dd, 'Design Data');
    entries = find(ddSec);
    for i = 1:numel(entries)
        val = getValue(entries(i));
        if isa(val, 'Simulink.Bus')
            assignin('base', entries(i).Name, val);
        end
    end
    fprintf('init_MIL_model: loaded bus objects from buses.sldd\n');
else
    warning('init_MIL_model:noSLDD', 'buses.sldd not found at %s', slddFile);
end

%% Model paths
addpath(fullfile(milRoot, 'models'));
addpath(fullfile(projRoot, 'plant_model', 'models'));
addpath(fullfile(projRoot, 'bms_model', 'models'));

fprintf('init_MIL_model: workspace ready (96s1p, Q_nom=%.0f Ah, dt=%.2f s, EKF SoC0=%.1f%%).\n', ...
    Q_nom_Ah, dt, SoC_init);
