% validate_plant_model.m — Validate pack_96s against measurement trips
%
% For each trip:
%   1. Build Simulink input dataset from measured drive-cycle data
%   2. Simulate pack_96s
%   3. Compare V_pack, SoC, T_cell against measurements
%   4. Save per-trip plot
%
% After all trips: save validation_results.csv and summary plots.
%
% Usage:
%   >> run('plant_model/scripts/init_plant_model.m')
%   >> run('plant_model/scripts/validate_plant_model.m')

%% Configuration
CAMPAIGN   = 'all';    % 'A', 'B', or 'all'
SAVE_PLOTS = true;
CLOSE_FIGS = true;
VERBOSE    = true;
T_DISP_STD = 1.0;     % [degC] cell-to-cell initial temperature dispersion

%% Paths
scriptDir = fileparts(mfilename('fullpath'));
dataDir   = fullfile(scriptDir, '..', 'data');
plotDir   = fullfile(scriptDir, '..', 'plots', 'trips');
summDir   = fullfile(scriptDir, '..', 'plots');
modelDir  = fullfile(scriptDir, '..', 'models');

if ~exist(plotDir, 'dir'), mkdir(plotDir); end
if ~exist(summDir, 'dir'), mkdir(summDir); end

%% Load parameters and drive-cycle data
if ~exist('OCV_data', 'var')
    run(fullfile(scriptDir, 'init_plant_model.m'));
end

measMat = fullfile(dataDir, 'drivecycles_meas.mat');
if ~isfile(measMat)
    error('validate_plant_model:noData', ...
        'drivecycles_meas.mat not found. Run export_drivecycles.m first.');
end
allTrips   = load(measMat);
tripNames  = sort(fieldnames(allTrips));
fprintf('Loaded %d measurement trips.\n', numel(tripNames));

if ~strcmpi(CAMPAIGN, 'all')
    prefix    = ['Trip' upper(CAMPAIGN)];
    tripNames = tripNames(startsWith(tripNames, prefix));
    fprintf('Filtered to campaign %s: %d trips.\n', upper(CAMPAIGN), numel(tripNames));
end

%% Load model
bdclose('all');
addpath(modelDir);

mdl = 'pack_96s';
load_system(fullfile(modelDir, mdl));
fprintf('Model %s loaded.\n', mdl);

refModels = find_mdlrefs(mdl, 'AllLevels', true);
for i = 1:numel(refModels)
    load_system(refModels{i});
end
fprintf('Loaded %d referenced models.\n\n', numel(refModels));

%% Validate each trip
nTrips  = numel(tripNames);
results = table('Size', [nTrips, 18], ...
    'VariableTypes', repmat({'double'}, 1, 18), ...
    'VariableNames', {'duration_s','n_samples', ...
                      'T_mean','T_min','T_max','T_amb_mean', ...
                      'soc_start','soc_end_meas','soc_end_sim', ...
                      'rmse_V_mV','mae_V_mV','max_err_V_mV','bias_V_mV', ...
                      'rmse_SoC_pct', ...
                      'rmse_T_C','mae_T_C','max_err_T_C','bias_T_C'});
results.trip_id  = tripNames;
results.campaign = repmat({''}, nTrips, 1);

for k = 1:nTrips
    tid  = tripNames{k};
    trip = allTrips.(tid);

    % --- Extract trip data ---
    t_raw  = double(trip.time_s(:));
    t_s    = t_raw - t_raw(1);
    I_A    = double(trip.I_A(:));
    V_meas = double(trip.V_pack_V(:));
    SoC_m  = double(trip.SoC_pct(:));
    T_cell = double(trip.T_cell_C(:));

    if isfield(trip, 'T_amb_C')
        T_amb_trip = double(trip.T_amb_C(:));
    else
        T_amb_trip = T_cell;
    end

    dur  = t_s(end);
    camp = trip.campaign;
    soc0 = SoC_m(1);

    % --- Coolant initial condition ---
    if isfield(trip, 'T_cool_C') && ~isnan(trip.T_cool_C(1)) && trip.T_cool_C(1) ~= 0
        T_cool0 = double(trip.T_cool_C(1));
    else
        Tc1 = T_cell(1);
        if Tc1 < T_heat_on
            T_cool0 = Tc1 + 15;
        elseif Tc1 < T_heat_off
            T_cool0 = Tc1 + 10;
        else
            T_cool0 = Tc1;
        end
    end

    % --- Per-trip initial cell temperatures with dispersion ---
    rng(k, 'twister');
    dT = randn(12, 8);
    dT = dT - mean(dT(:));
    T_cells_init = T_cell(1) + T_DISP_STD * dT; %#ok<NASGU>

    if VERBOSE
        fprintf('[%d/%d] %s | camp=%s | dur=%.0fs | SoC0=%.1f%% | T=%.1f degC\n', ...
            k, nTrips, tid, camp, dur, soc0, mean(T_cell));
    end

    % --- Passive balancing ---
    BAL_THRESHOLD = 1.0;   % [%]
    I_BLEED       = 0.1;   % [A]
    soc_12x8 = soc0 + cell_dSoC_pct;
    I_bal    = zeros(12, 8);
    for m = 1:8
        soc_mod  = soc_12x8(:, m);
        need_bal = soc_mod - min(soc_mod) > BAL_THRESHOLD;
        I_bal(need_bal, m) = I_BLEED;
    end
    I_bal_default = I_bal; %#ok<NASGU>

    % --- Build input dataset (6 inports) ---
    %   [1] I_pack       timeseries [A]
    %   [2] T_amb        timeseries [degC]
    %   [3] SoC_init     constant   [%]
    %   [4] T_cool_init  constant   [degC]
    %   [5] V_RC1_init   constant   [V]
    %   [6] V_RC2_init   constant   [V]
    ds = Simulink.SimulationData.Dataset;

    ts_I    = timeseries(I_A,        t_s, 'Name', 'I_pack');
    ts_Tamb = timeseries(T_amb_trip, t_s, 'Name', 'T_amb');

    t_const   = [0; dur];
    ts_soc0   = timeseries(soc0    * [1;1], t_const, 'Name', 'SoC_init');
    ts_Tcool0 = timeseries(T_cool0 * [1;1], t_const, 'Name', 'T_cool_init');

    % RC init: steady-state if vehicle already moving, else zero
    I0 = I_A(1);  T0 = T_cell(1);
    if isfield(trip, 'v_kmh') && double(trip.v_kmh(1)) > 0
        T0_c   = max(min(T0,   T_bp(end)),   T_bp(1));
        soc0_c = max(min(soc0, SoC_bp_ecm(end)), SoC_bp_ecm(1));
        R1_init = interp2(T_bp, SoC_bp_ecm, R1_data, T0_c, soc0_c, 'linear');
        R2_init = interp2(T_bp, SoC_bp_ecm, R2_data, T0_c, soc0_c, 'linear');
        vrc1_0 = R1_init * I0;
        vrc2_0 = R2_init * I0;
    else
        vrc1_0 = 0;
        vrc2_0 = 0;
    end
    ts_vrc1 = timeseries(vrc1_0 * [1;1], t_const, 'Name', 'V_RC1_init');
    ts_vrc2 = timeseries(vrc2_0 * [1;1], t_const, 'Name', 'V_RC2_init');

    ds = ds.addElement(ts_I);
    ds = ds.addElement(ts_Tamb);
    ds = ds.addElement(ts_soc0);
    ds = ds.addElement(ts_Tcool0);
    ds = ds.addElement(ts_vrc1);
    ds = ds.addElement(ts_vrc2);

    % --- Simulate ---
    simIn = Simulink.SimulationInput(mdl);
    simIn = simIn.setModelParameter('StopTime',  num2str(dur));
    simIn = simIn.setModelParameter('SaveTime',  'on');
    simIn = simIn.setModelParameter('SaveOutput','on');
    simIn = simIn.setModelParameter('SaveFormat','Dataset');
    simIn = simIn.setModelParameter('ReturnWorkspaceOutputs', 'on');
    simIn = simIn.setModelParameter('ReturnWorkspaceOutputsName', 'out');
    simIn = simIn.setExternalInput(ds);

    try
        simOut = sim(simIn);
    catch ME
        warning('Trip %s failed: %s', tid, ME.message);
        if ~isempty(ME.cause)
            for ci = 1:numel(ME.cause)
                fprintf('  Cause %d: %s\n', ci, ME.cause{ci}.message);
            end
        end
        continue;
    end

    % --- Extract outputs ---
    % pack_96s top-level outports: [1] V_pack, [2] T_pack, [3] SoC_pack, [4] T_coolant
    yout = simOut.yout;

    V_ts       = extractTS(yout, 1);
    t_sim      = V_ts.Time;
    V_pack_sim = squeeze(double(V_ts.Data));

    T_sim      = squeeze(double(extractTS(yout, 2).Data));
    SoC_sim    = squeeze(double(extractTS(yout, 3).Data));
    T_cool_sim = squeeze(double(extractTS(yout, 4).Data));

    % --- Interpolate measured data to simulation time grid ---
    V_meas_interp   = interp1(t_s, V_meas, t_sim, 'linear', 'extrap');
    SoC_meas_interp = interp1(t_s, SoC_m,  t_sim, 'linear', 'extrap');
    T_meas_interp   = interp1(t_s, T_cell, t_sim, 'linear', 'extrap');

    % --- Error metrics ---
    errV    = V_pack_sim - V_meas_interp;
    rmseV   = sqrt(mean(errV.^2)) * 1e3;
    maeV    = mean(abs(errV)) * 1e3;
    maxErrV = max(abs(errV)) * 1e3;
    biasV   = mean(errV) * 1e3;

    errSoC  = SoC_sim - SoC_meas_interp;
    rmseSoC = sqrt(mean(errSoC.^2));

    errT    = T_sim - T_meas_interp;
    rmseT   = sqrt(mean(errT.^2));
    maeT    = mean(abs(errT));
    maxErrT = max(abs(errT));
    biasT   = mean(errT);

    % --- Store results ---
    results.duration_s(k)    = dur;
    results.n_samples(k)     = numel(t_s);
    results.T_mean(k)        = mean(T_cell);
    results.T_min(k)         = min(T_cell);
    results.T_max(k)         = max(T_cell);
    results.T_amb_mean(k)    = mean(T_amb_trip);
    results.soc_start(k)     = soc0;
    results.soc_end_meas(k)  = SoC_m(end);
    results.soc_end_sim(k)   = SoC_sim(end);
    results.rmse_V_mV(k)     = rmseV;
    results.mae_V_mV(k)      = maeV;
    results.max_err_V_mV(k)  = maxErrV;
    results.bias_V_mV(k)     = biasV;
    results.rmse_SoC_pct(k)  = rmseSoC;
    results.rmse_T_C(k)      = rmseT;
    results.mae_T_C(k)       = maeT;
    results.max_err_T_C(k)   = maxErrT;
    results.bias_T_C(k)      = biasT;
    results.campaign{k}      = camp;

    if VERBOSE
        fprintf('  RMSE=%.1f mV | MAE=%.1f mV | Max=%.1f mV | Bias=%+.1f mV | SoC=%.2f%% | T=%.2f degC\n', ...
            rmseV, maeV, maxErrV, biasV, rmseSoC, rmseT);
    end

    % --- Per-trip plot ---
    if SAVE_PLOTS
        fig = figure('Position', [50 50 1200 800], 'Visible', 'off');

        subplot(3,1,1);
        plot(t_sim, V_meas_interp, 'k', 'LineWidth', 0.7); hold on;
        plot(t_sim, V_pack_sim, 'r--', 'LineWidth', 0.7);
        ylabel('V_{pack} [V]');
        title(sprintf('%s | Campaign %s | V RMSE=%.1f mV | SoC RMSE=%.2f%% | T RMSE=%.2f degC', ...
            tid, camp, rmseV, rmseSoC, rmseT));
        legend('Measured','Simulated','Location','best');
        grid on;

        subplot(3,1,2);
        plot(t_sim, SoC_meas_interp, 'k', 'LineWidth', 0.7); hold on;
        plot(t_sim, SoC_sim, 'r--', 'LineWidth', 0.7);
        ylabel('SoC_{pack} [%]');
        legend('Measured','Simulated','Location','best');
        grid on;

        subplot(3,1,3);
        plot(t_sim, T_meas_interp, 'k', 'LineWidth', 0.7); hold on;
        plot(t_sim, T_sim, 'r--', 'LineWidth', 0.7);
        plot(t_sim, T_cool_sim, 'b:', 'LineWidth', 1.0);
        legend('T_{cell} Meas','T_{cell} Sim','T_{coolant} Sim','Location','best');
        ylabel('Temperature [degC]');
        xlabel('Time [s]');
        grid on;

        saveas(fig, fullfile(plotDir, sprintf('val_pack_%s.png', tid)));
        if CLOSE_FIGS, close(fig); end
    end
end

close_system(mdl, 0);

%% Save results
csvPath = fullfile(dataDir, 'validation_results.csv');
writetable(results, csvPath);
fprintf('\nResults saved: %s\n', csvPath);

%% Print summary
valid = results.rmse_V_mV > 0;
res   = results(valid, :);

fprintf('\n========================================\n');
fprintf('  PACK-LEVEL VALIDATION SUMMARY\n');
fprintf('========================================\n');
fprintf('  Trips evaluated: %d / %d\n', height(res), nTrips);
fprintf('  V_pack RMSE:\n');
fprintf('    Median: %.1f mV\n', median(res.rmse_V_mV));
fprintf('    Mean:   %.1f mV\n', mean(res.rmse_V_mV));
fprintf('    Max:    %.1f mV (%s)\n', max(res.rmse_V_mV), ...
    res.trip_id{res.rmse_V_mV == max(res.rmse_V_mV)});
fprintf('    < 500 mV:  %d / %d\n', sum(res.rmse_V_mV < 500), height(res));
fprintf('    < 1000 mV: %d / %d\n', sum(res.rmse_V_mV < 1000), height(res));
fprintf('  SoC RMSE:\n');
fprintf('    Median: %.2f%%\n', median(res.rmse_SoC_pct));
fprintf('    Mean:   %.2f%%\n', mean(res.rmse_SoC_pct));
fprintf('  Temperature RMSE:\n');
fprintf('    Median: %.2f degC\n', median(res.rmse_T_C, 'omitnan'));
fprintf('    Mean:   %.2f degC\n', mean(res.rmse_T_C, 'omitnan'));
fprintf('    Max:    %.2f degC\n', max(res.rmse_T_C));

for camp = {'A', 'B'}
    c   = camp{1};
    sub = res(strcmp(res.campaign, c), :);
    if isempty(sub), continue; end
    fprintf('\n  Campaign %s (%d trips):\n', c, height(sub));
    fprintf('    V RMSE:   median=%.1f mV, mean=%.1f mV\n', ...
        median(sub.rmse_V_mV), mean(sub.rmse_V_mV));
    fprintf('    Bias:     mean=%+.1f mV\n', mean(sub.bias_V_mV));
    fprintf('    SoC RMSE: median=%.2f%%, mean=%.2f%%\n', ...
        median(sub.rmse_SoC_pct), mean(sub.rmse_SoC_pct));
    fprintf('    T RMSE:   median=%.2f degC, mean=%.2f degC\n', ...
        median(sub.rmse_T_C, 'omitnan'), mean(sub.rmse_T_C, 'omitnan'));
    fprintf('    T range:  [%.0f, %.0f] degC\n', min(sub.T_mean), max(sub.T_mean));
end

%% Summary plots
campA = res(strcmp(res.campaign, 'A'), :);
campB = res(strcmp(res.campaign, 'B'), :);

% RMSE histogram
fig1 = figure('Position', [50 50 900 500], 'Visible', 'off');
hold on;
if ~isempty(campA)
    histogram(campA.rmse_V_mV, 20, 'FaceColor', [0.2 0.4 0.8], 'FaceAlpha', 0.6, ...
        'EdgeColor', 'k', 'DisplayName', sprintf('Campaign A (n=%d)', height(campA)));
end
if ~isempty(campB)
    histogram(campB.rmse_V_mV, 20, 'FaceColor', [0.9 0.5 0.1], 'FaceAlpha', 0.6, ...
        'EdgeColor', 'k', 'DisplayName', sprintf('Campaign B (n=%d)', height(campB)));
end
med = median(res.rmse_V_mV);
xline(med, 'r--', 'LineWidth', 1.5, 'DisplayName', sprintf('Median = %.1f mV', med));
xlabel('V_{pack} RMSE [mV]'); ylabel('Trip count');
title(sprintf('Pack Validation — RMSE Distribution (%d trips)', height(res)));
legend('Location', 'best'); grid on;
saveas(fig1, fullfile(summDir, 'validation_pack_rmse_hist.png'));
if CLOSE_FIGS, close(fig1); end

% RMSE vs temperature
fig2 = figure('Position', [50 50 900 500], 'Visible', 'off');
hold on;
if ~isempty(campA)
    scatter(campA.T_mean, campA.rmse_V_mV, 50, [0.2 0.4 0.8], 'o', 'filled', ...
        'MarkerFaceAlpha', 0.7, 'DisplayName', 'Campaign A');
end
if ~isempty(campB)
    scatter(campB.T_mean, campB.rmse_V_mV, 50, [0.9 0.5 0.1], 's', 'filled', ...
        'MarkerFaceAlpha', 0.7, 'DisplayName', 'Campaign B');
end
xlabel('Mean Battery Temperature [degC]'); ylabel('V_{pack} RMSE [mV]');
title('Per-Trip Pack RMSE vs Temperature');
legend('Location', 'best'); grid on;
saveas(fig2, fullfile(summDir, 'validation_pack_rmse_vs_temp.png'));
if CLOSE_FIGS, close(fig2); end

% SoC RMSE vs temperature
fig3 = figure('Position', [50 50 900 500], 'Visible', 'off');
hold on;
if ~isempty(campA)
    scatter(campA.T_mean, campA.rmse_SoC_pct, 50, [0.2 0.4 0.8], 'o', 'filled', ...
        'MarkerFaceAlpha', 0.7, 'DisplayName', 'Campaign A');
end
if ~isempty(campB)
    scatter(campB.T_mean, campB.rmse_SoC_pct, 50, [0.9 0.5 0.1], 's', 'filled', ...
        'MarkerFaceAlpha', 0.7, 'DisplayName', 'Campaign B');
end
xlabel('Mean Battery Temperature [degC]'); ylabel('SoC RMSE [%]');
title('Per-Trip SoC RMSE vs Temperature');
legend('Location', 'best'); grid on;
saveas(fig3, fullfile(summDir, 'validation_pack_soc_vs_temp.png'));
if CLOSE_FIGS, close(fig3); end

% Temperature RMSE vs temperature
fig4 = figure('Position', [50 50 900 500], 'Visible', 'off');
hold on;
if ~isempty(campA)
    scatter(campA.T_mean, campA.rmse_T_C, 50, [0.2 0.4 0.8], 'o', 'filled', ...
        'MarkerFaceAlpha', 0.7, 'DisplayName', 'Campaign A');
end
if ~isempty(campB)
    scatter(campB.T_mean, campB.rmse_T_C, 50, [0.9 0.5 0.1], 's', 'filled', ...
        'MarkerFaceAlpha', 0.7, 'DisplayName', 'Campaign B');
end
xlabel('Mean Battery Temperature [degC]'); ylabel('Temperature RMSE [degC]');
title('Per-Trip Temperature RMSE vs Mean Temperature');
legend('Location', 'best'); grid on;
saveas(fig4, fullfile(summDir, 'validation_pack_temp_rmse_vs_temp.png'));
if CLOSE_FIGS, close(fig4); end

% Temperature RMSE histogram
fig5 = figure('Position', [50 50 900 500], 'Visible', 'off');
hold on;
if ~isempty(campA)
    histogram(campA.rmse_T_C, 20, 'FaceColor', [0.2 0.4 0.8], 'FaceAlpha', 0.6, ...
        'EdgeColor', 'k', 'DisplayName', sprintf('Campaign A (n=%d)', height(campA)));
end
if ~isempty(campB)
    histogram(campB.rmse_T_C, 20, 'FaceColor', [0.9 0.5 0.1], 'FaceAlpha', 0.6, ...
        'EdgeColor', 'k', 'DisplayName', sprintf('Campaign B (n=%d)', height(campB)));
end
medT = median(res.rmse_T_C, 'omitnan');
xline(medT, 'r--', 'LineWidth', 1.5, 'DisplayName', sprintf('Median = %.2f degC', medT));
xlabel('Temperature RMSE [degC]'); ylabel('Trip count');
title(sprintf('Pack Validation — Temperature RMSE Distribution (%d trips)', height(res)));
legend('Location', 'best'); grid on;
saveas(fig5, fullfile(summDir, 'validation_pack_temp_rmse_hist.png'));
if CLOSE_FIGS, close(fig5); end

% Bias vs SoC start
fig6 = figure('Position', [50 50 900 500], 'Visible', 'off');
hold on;
if ~isempty(campA)
    scatter(campA.soc_start, campA.bias_V_mV, 50, [0.2 0.4 0.8], 'o', 'filled', ...
        'MarkerFaceAlpha', 0.7, 'DisplayName', 'Campaign A');
end
if ~isempty(campB)
    scatter(campB.soc_start, campB.bias_V_mV, 50, [0.9 0.5 0.1], 's', 'filled', ...
        'MarkerFaceAlpha', 0.7, 'DisplayName', 'Campaign B');
end
yline(0, 'k--');
xlabel('SoC Start [%]'); ylabel('V_{pack} Bias [mV]');
title('Voltage Bias vs Initial SoC');
legend('Location', 'best'); grid on;
saveas(fig6, fullfile(summDir, 'validation_pack_bias_vs_soc.png'));
if CLOSE_FIGS, close(fig6); end

fprintf('\nSummary plots saved to: %s\n', summDir);
fprintf('Per-trip plots saved to: %s\n', plotDir);
fprintf('Done.\n');


%% === Local function ===

function ts = extractTS(dataset, idx)
    el = dataset.getElement(idx);
    if isa(el, 'Simulink.SimulationData.Signal')
        ts = el.Values;
    else
        ts = el;
    end
end
