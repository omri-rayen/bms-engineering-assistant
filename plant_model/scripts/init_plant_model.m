% init_plant_model.m — Initialize workspace for pack_96s / module_12s / cell_ecm_2rc
%
% Loads ECM parameters, drive-cycle data, and defines all workspace
% variables required by the Simulink model hierarchy.
%
% Called by pack_96s PreLoadFcn callback, or run manually before simulation.

%% Paths
scriptDir = fileparts(mfilename('fullpath'));
dataDir   = fullfile(scriptDir, '..', 'data');

%% ECM lookup tables
paramFile = fullfile(dataDir, 'ecm_params.mat');
if ~isfile(paramFile)
    error('init_plant_model:fileNotFound', ...
        'ecm_params.mat not found. Run export_luts.m first.\n  Expected: %s', paramFile);
end
load(paramFile);  % SoC_bp_ocv, SoC_bp_ecm, T_bp, OCV/R0/R1/C1/R2/C2_data

%% Pack configuration (authoritative source — not stored in .mat)
N_series = 96;    % cells in series (12s x 8 modules)
Q_nom_Ah = 60;    % nominal cell capacity [Ah]
dt       = 0.1;   % simulation time-step [s]

%% Drive-cycle data
measFile = fullfile(dataDir, 'drivecycles_meas.mat');
if isfile(measFile)
    trips_meas = load(measFile);
    fprintf('init_plant_model: loaded %d measurement trips\n', numel(fieldnames(trips_meas)));
else
    warning('init_plant_model:noMeasData', 'drivecycles_meas.mat not found — skipping.');
    trips_meas = struct();
end

simFile = fullfile(dataDir, 'drivecycles_sim.mat');
if isfile(simFile)
    trips_sim = load(simFile);
    fprintf('init_plant_model: loaded %d simulation trips\n', numel(fieldnames(trips_sim)));
else
    trips_sim = struct();
end

%% Cell thermal parameters
thermalCsv = fullfile(dataDir, 'thermal_params.csv');
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
m_coolant  = 8;      % [kg]
cp_coolant = 3500;   % [J/(kg*K)]  50/50 glycol-water
h_rad      = 40;     % [W/K] radiator HTC

%% Heater / chiller
tau_heater    = 10;    % [s]
tau_chiller   = 10;    % [s]
P_heater_max  = 7000;  % [W]
P_chiller_max = 5000;  % [W]

%% Thermal management relay thresholds
T_target_heat = 18;   % [deg C]
T_target_cool = 25;   % [deg C]
T_heat_target = T_target_heat;  % alias for Simulink Constant block
T_cool_target = T_target_cool;

T_heat_on  = 8;
T_heat_off = T_target_heat;
T_cool_on  = 35;
T_cool_off = T_target_cool;

%% Per-cell variation (nominal: no cell-to-cell spread)
cell_Q_Ah     = Q_nom_Ah * ones(12, 8);  % [Ah]
cell_dSoC_pct = zeros(12, 8);            % [%]
cell_RO_scale = ones(12, 8);             % [-]

%% Initial temperature from first measurement trip
firstTripFields = fieldnames(trips_meas);
if ~isempty(firstTripFields)
    firstTrip     = trips_meas.(firstTripFields{1});
    T_init_scalar = double(firstTrip.T_cell_C(1));
    fprintf('init_plant_model: T_cells_init = %.1f degC (from "%s")\n', ...
        T_init_scalar, firstTripFields{1});
else
    T_init_scalar = 25;
    warning('init_plant_model:noTripData', 'No trips — defaulting T_cells_init to 25 degC.');
end
T_cells_init = T_init_scalar * ones(12, 8);

%% RC voltage initial conditions (cold start = 0)
V_RC1_init_cell = 0;
V_RC2_init_cell = 0;
V_RC1_init = V_RC1_init_cell;
V_RC2_init = V_RC2_init_cell;

%% Balancing and overrides
I_bal_default        = zeros(12, 8);
bms_thermal_override = false;

%% Simulation time
T_stop = 3600;  % [s] default; overridden by validation scripts

%% Summary
fprintf('init_plant_model: workspace ready (%ds1p, Q_nom=%.0f Ah, dt=%.2f s, T_stop=%.0f s)\n', ...
    N_series, Q_nom_Ah, dt, T_stop);

%% Bus definitions (needed by module_12s outport blocks)
clear elems_;
elems_(1) = Simulink.BusElement; elems_(1).Name = 'V_module';       elems_(1).Dimensions = 1;
elems_(2) = Simulink.BusElement; elems_(2).Name = 'V_cells_12';     elems_(2).Dimensions = 12;
elems_(3) = Simulink.BusElement; elems_(3).Name = 'SoC_cells_12';   elems_(3).Dimensions = 12;
elems_(4) = Simulink.BusElement; elems_(4).Name = 'T_cells_12';     elems_(4).Dimensions = 12;
elems_(5) = Simulink.BusElement; elems_(5).Name = 'Q_gen_cells_12'; elems_(5).Dimensions = 12;
elems_(6) = Simulink.BusElement; elems_(6).Name = 'I_module_meas';  elems_(6).Dimensions = 1;
PlantToSlaveBus = Simulink.Bus;
PlantToSlaveBus.Elements = elems_;

clear elems_;
elems_(1) = Simulink.BusElement; elems_(1).Name = 'I_bal'; elems_(1).Dimensions = 12;
SlaveToPlantBus = Simulink.Bus;
SlaveToPlantBus.Elements = elems_;
clear elems_;
