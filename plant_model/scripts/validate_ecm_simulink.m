% validate_ecm_simulink.m
% validates cell_ecm_2rc.slx against a single measurement trip

TRIP_ID  = 'TripA01';
N_SERIES = 96;

scriptDir = fileparts(mfilename('fullpath'));
dataDir   = fullfile(scriptDir, '..', 'data');
plotDir   = fullfile(scriptDir, '..', 'plots', 'trips');
modelPath = fullfile(scriptDir, '..', 'models', 'cell_ecm_2rc');

if ~exist(plotDir, 'dir'), mkdir(plotDir); end

load(fullfile(dataDir, 'ecm_params.mat'));
trips = load(fullfile(dataDir, 'drivecycles_meas.mat'));
trip  = trips.(matlab.lang.makeValidName(TRIP_ID));

t_meas   = double(trip.time_s(:)) - double(trip.time_s(1));
soc_init = double(trip.SoC_pct(1));

fprintf('%s | SoC0=%.1f%% | T_mean=%.1f°C | dur=%.0fs\n', ...
    TRIP_ID, soc_init, mean(trip.T_cell_C), t_meas(end));

mdl = 'cell_ecm_2rc';
load_system(modelPath);

% config

simIn = Simulink.SimulationInput(mdl) ...
    .setVariable('soc_init', soc_init) ...
    .setModelParameter('StopTime',  num2str(t_meas(end)), ...
                       'SolverType','Fixed-step', 'Solver', 'ode4', ...
                       'FixedStep', num2str(dt), ...
                       'SaveTime',  'on', 'TimeSaveName',   'tout', ...
                       'SaveOutput','on', 'OutputSaveName', 'yout', ...
                       'SaveFormat','Array') ...
    .setExternalInput([t_meas, double(trip.I_A(:)), double(trip.T_cell_C(:))]);

simOut = sim(simIn);
close_system(mdl, 0);

t_sim      = simOut.tout;
V_cell_sim = simOut.yout(:, 1);
SoC_sim    = simOut.yout(:, 2);

V_cell_ref = interp1(t_meas, double(trip.V_pack_V(:)) / N_SERIES, t_sim, 'linear', 'extrap');
SoC_ref    = interp1(t_meas, double(trip.SoC_pct(:)),             t_sim, 'linear', 'extrap');

err_mV = (V_cell_sim - V_cell_ref) * 1e3;

fprintf('RMSE=%.2f  MAE=%.2f  Max=%.2f  Bias=%.2f mV  delta SoC=%.2f%%\n', ...
    rms(err_mV), mean(abs(err_mV)), max(abs(err_mV)), mean(err_mV), SoC_sim(end) - SoC_ref(end));

% plots

figure('Position', [100 100 900 700], 'Name', sprintf('Validation %s', TRIP_ID));

subplot(3,1,1)
plot(t_sim, V_cell_ref, 'k', t_sim, V_cell_sim, 'r--');
ylabel('V_{cell} [V]'); legend('Measured','ECM'); grid on

subplot(3,1,2)
plot(t_sim, err_mV, 'b'); yline(0, 'k--');
ylabel('Error [mV]'); grid on

subplot(3,1,3)
plot(t_sim, SoC_ref, 'k', t_sim, SoC_sim, 'r--');
ylabel('SoC [%]'); xlabel('Time [s]'); legend('Measured','ECM'); grid on

saveas(gcf, fullfile(plotDir, sprintf('val_slx_%s.png', TRIP_ID)));