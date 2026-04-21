% validate_MIL_model.m - MIL validation against measurement trips
%
% Simulates MIL_model for each of 70 measurement trips, compares BMS outputs
% against measurements, and saves per-trip plots + a CSV summary.
%
% Usage:
%   >> run('MIL_validation/scripts/validate_MIL_model.m')
%
% Single-trip mode:
%   >> TRIP_ID = 'TripA01'; run('MIL_validation/scripts/validate_MIL_model.m')

%% Configuration
if ~exist('TRIP_ID', 'var'), TRIP_ID = ''; end
CAMPAIGN   = 'all';   % 'A', 'B', or 'all'
SAVE_PLOTS = true;
CLOSE_FIGS = true;
VERBOSE    = true;

%% Paths
valScriptDir = fileparts(mfilename('fullpath'));
milRoot      = fileparts(valScriptDir);
projRoot     = fileparts(milRoot);
plotDir      = fullfile(milRoot, 'plots');
milDataDir   = fullfile(milRoot, 'data');
if ~exist(plotDir, 'dir'),    mkdir(plotDir);    end
if ~exist(milDataDir, 'dir'), mkdir(milDataDir); end

addpath(milDataDir);
addpath(fullfile(milRoot, 'models'));
addpath(fullfile(projRoot, 'bms_model', 'models'));
addpath(fullfile(projRoot, 'plant_model', 'models'));

%% Load workspace
if ~exist('OCV_data', 'var') || ~exist('bms', 'var')
    run(fullfile(valScriptDir, 'init_MIL_model.m'));
end

%% Trip selection
tripNames = sort(fieldnames(trips_meas));
fprintf('Loaded %d measurement trips.\n', numel(tripNames));

if ~isempty(TRIP_ID)
    if ~ismember(TRIP_ID, tripNames)
        error('validate_MIL_model:noTrip', 'Trip "%s" not found.', TRIP_ID);
    end
    tripNames = {TRIP_ID};
    fprintf('Single-trip mode: %s\n', TRIP_ID);
elseif ~strcmpi(CAMPAIGN, 'all')
    prefix    = ['Trip' upper(CAMPAIGN)];
    tripNames = tripNames(startsWith(tripNames, prefix));
    fprintf('Filtered to campaign %s: %d trips.\n', upper(CAMPAIGN), numel(tripNames));
end

%% Load model
mdl = 'MIL_model';
load_system(fullfile(milRoot, 'models', mdl));
fprintf('Model %s loaded.\n\n', mdl);

%% Prepare results table
nTrips  = numel(tripNames);
results = table('Size', [nTrips, 31], ...
    'VariableTypes', repmat({'double'}, 1, 31), ...
    'VariableNames', { ...
        'duration_s','n_samples', ...
        'SoC_init_pct','T_init_C','T_amb_mean_C','T_cool_init_C','R0_fresh_Ohm', ...
        'rmse_V_mV','mae_V_mV','max_err_V_mV','bias_V_mV', ...
        'rmse_SoC_pct','SoC_end_meas','SoC_end_sim', ...
        'rmse_T_C','mae_T_C','max_err_T_C','bias_T_C', ...
        'SoH_final','bal_active_pct', ...
        'max_severity','shutdown_triggered','sim_time_s','sim_ok','n_faults', ...
        'max_OV_sev','max_UV_sev','max_OT_sev','max_UT_sev','max_I_db_sev','max_SC_sev'});
results.trip_id  = tripNames;
results.campaign = repmat({''}, nTrips, 1);

% Fixed temperature dispersion across all trips (same physical pack)
rng(42, 'twister');
dT_base = randn(12, 8);
dT_base = dT_base - mean(dT_base(:));

%% ======
%  MAIN LOOP
%  ======

for k = 1:nTrips
    tid  = tripNames{k};
    trip = trips_meas.(tid);

    % --- Trip data ---
    t_s    = double(trip.time_s(:)) - double(trip.time_s(1));
    I_A    = double(trip.I_A(:));
    V_meas = double(trip.V_pack_V(:));
    SoC_m  = double(trip.SoC_pct(:));
    T_cell = double(trip.T_cell_C(:));
    T_amb  = double(trip.T_amb_C(:));
    T_cool = double(trip.T_cool_C(:));
    camp   = trip.campaign;
    dur    = t_s(end);
    soc0   = SoC_m(1);
    T0     = T_cell(1);

    % --- Initial conditions ---
    T_cells_init_k = T0 + 1.0 * dT_base;

    if ~isnan(T_cool(1)) && T_cool(1) ~= 0
        T_cool_init_k = T_cool(1);
    elseif T0 < T_heat_on
        T_cool_init_k = T0 + 15;
    elseif T0 < T_heat_off
        T_cool_init_k = T0 + 10;
    else
        T_cool_init_k = T0;
    end

    SoC_init_k = soc0;
    ekf_k      = ekf_params;
    ekf_k.SoC0 = soc0 / 100;

    % RC initial state from first sample
    I0 = I_A(1);
    if isfield(trip, 'v_kmh') && double(trip.v_kmh(1)) > 0
        T0_c   = max(min(T0,   T_bp(end)),   T_bp(1));
        soc0_c = max(min(soc0, SoC_bp_ecm(end)), SoC_bp_ecm(1));
        V_RC1_init_k = interp2(T_bp, SoC_bp_ecm, R1_data, T0_c, soc0_c, 'linear') * I0;
        V_RC2_init_k = interp2(T_bp, SoC_bp_ecm, R2_data, T0_c, soc0_c, 'linear') * I0;
    else
        V_RC1_init_k = 0;
        V_RC2_init_k = 0;
    end

    % Balancing ICs from cell dispersion
    soc_12x8 = soc0 + cell_dSoC_pct;
    I_bal_k  = zeros(12, 8);
    for m = 1:8
        soc_mod  = soc_12x8(:, m);
        need_bal = soc_mod - min(soc_mod) > bms.bal_dSoC_thresh;
        I_bal_k(need_bal, m) = bms.bal_I_nom;
    end

    % R0_fresh for this trip's operating point
    T0_clamp   = max(min(T0,   T_bp(end)),   T_bp(1));
    soc0_clamp = max(min(soc0, SoC_bp_ecm(end)), SoC_bp_ecm(1));
    R0_fresh_trip = interp2(T_bp, SoC_bp_ecm, R0_data, T0_clamp, soc0_clamp, 'linear');
    bms_k = bms;
    bms_k.R0_fresh = R0_fresh_trip;

    % --- Inputs ---
    ds = Simulink.SimulationData.Dataset;
    ds = ds.addElement(timeseries(I_A,   t_s, 'Name', 'I_pack'), 'I_pack');
    ds = ds.addElement(timeseries(T_amb, t_s, 'Name', 'T_amb'),  'T_amb');

    % --- Simulate ---
    simIn = Simulink.SimulationInput(mdl);
    simIn = simIn.setModelParameter('StopTime', num2str(dur));
    simIn = simIn.setModelParameter('SaveTime',  'on');
    simIn = simIn.setModelParameter('SaveOutput','on');
    simIn = simIn.setModelParameter('SaveFormat','Dataset');
    simIn = simIn.setModelParameter('ReturnWorkspaceOutputs', 'on');
    simIn = simIn.setModelParameter('ReturnWorkspaceOutputsName', 'out');
    simIn = simIn.setExternalInput(ds);

    % Push per-trip variables to base workspace
    T_cells_init  = T_cells_init_k;
    T_cool_init   = T_cool_init_k;
    V_RC1_init    = V_RC1_init_k;
    V_RC2_init    = V_RC2_init_k;
    SoC_init      = SoC_init_k;
    ekf_params    = ekf_k;
    bms           = bms_k;
    I_bal_default = I_bal_k;

    if VERBOSE
        fprintf('[%2d/%d] %s | camp=%s | dur=%4.0fs | SoC0=%5.1f%% | T0=%5.1f°C\n', ...
            k, nTrips, tid, camp, dur, soc0, T0);
    end

    tic;
    try
        out = sim(simIn);
        sim_ok = true;
    catch ME
        warning('Trip %s FAILED: %s', tid, ME.message);
        results.sim_ok(k)   = 0;
        results.campaign{k} = camp;
        results.trip_id{k}  = tid;
        continue;
    end
    t_sim_elapsed = toc;

    % --- Extract outputs ---
    mo = out.yout.getElement(1).Values;

    t_sim    = mo.V_pack.Time;
    V_sim    = squeeze(double(mo.V_pack.Data));
    SoC_sim  = squeeze(double(mo.SoC_pack.Data)) * 100;
    T_avg_s  = squeeze(double(mo.T_pack_avg.Data));
    T_min_s  = squeeze(double(mo.T_cell_min.Data));
    T_max_s  = squeeze(double(mo.T_cell_max.Data));
    shut_sim = squeeze(double(mo.shutdown_cmd.Data));
    sev_sim  = squeeze(double(mo.fault_severity.Data));
    SoH_sim  = squeeze(double(mo.SoH_pack.Data));

    try
        T_cool_sim = squeeze(double(out.yout.getElement(2).Values.Data));
    catch
        T_cool_sim = T_avg_s;
    end

    % Interpolate measurements onto sim time grid
    V_meas_i   = interp1(t_s, V_meas, t_sim, 'linear', 'extrap');
    SoC_meas_i = interp1(t_s, SoC_m,  t_sim, 'linear', 'extrap');
    T_meas_i   = interp1(t_s, T_cell, t_sim, 'linear', 'extrap');
    T_cool_m_i = interp1(t_s, T_cool, t_sim, 'linear', 'extrap');
    T_amb_i    = interp1(t_s, T_amb,  t_sim, 'linear', 'extrap');

    % --- Post-hoc fault severity (replicate slave monitors + debounce) ---
    V_cell_avg = V_sim / N_series;
    I_sim      = interp1(t_s, I_A, t_sim, 'linear', 'extrap');

    OV_sev = zeros(size(t_sim));
    OV_sev(V_cell_avg >= bms.V_OV_warn)   = 1;
    OV_sev(V_cell_avg >= bms.V_OV_derate)  = 2;
    OV_sev(V_cell_avg >= bms.V_OV_shut)    = 3;

    UV_sev = zeros(size(t_sim));
    UV_sev(V_cell_avg <= bms.V_UV_warn)   = 1;
    UV_sev(V_cell_avg <= bms.V_UV_derate)  = 2;
    UV_sev(V_cell_avg <= bms.V_UV_shut)    = 3;

    OT_sev = zeros(size(t_sim));
    OT_sev(T_max_s >= bms.T_OT_warn)   = 1;
    OT_sev(T_max_s >= bms.T_OT_derate) = 2;
    OT_sev(T_max_s >= bms.T_OT_shut)   = 3;

    UT_sev = zeros(size(t_sim));
    UT_sev(T_min_s <= bms.T_UT_warn)   = 1;
    UT_sev(T_min_s <= bms.T_UT_derate)  = 2;
    UT_sev(T_min_s <= bms.T_UT_shut)    = 3;

    I_db_sev = zeros(size(t_sim));
    abs_I    = abs(I_sim);
    is_chg   = I_sim < 0;
    I_db_sev(~is_chg & abs_I >= bms.I_OC_dchg_warn)   = 1;
    I_db_sev(~is_chg & abs_I >= bms.I_OC_dchg_derate)  = 2;
    I_db_sev(~is_chg & abs_I >= bms.I_OC_dchg_shut)    = 3;
    I_db_sev(is_chg  & abs_I >= bms.I_OC_chg_warn)     = 1;
    I_db_sev(is_chg  & abs_I >= bms.I_OC_chg_derate)   = 2;
    I_db_sev(is_chg  & abs_I >= bms.I_OC_chg_shut)     = 3;

    SC_sev = zeros(size(t_sim));
    SC_sev(abs_I >= bms.I_SC_thresh) = 3;

    % --- Error metrics ---
    errV    = V_sim - V_meas_i;
    rmseV   = sqrt(mean(errV.^2)) * 1e3;
    maeV    = mean(abs(errV)) * 1e3;
    maxErrV = max(abs(errV)) * 1e3;
    biasV   = mean(errV) * 1e3;

    errSoC  = SoC_sim - SoC_meas_i;
    rmseSoC = sqrt(mean(errSoC.^2));

    errT    = T_avg_s - T_meas_i;
    rmseT   = sqrt(mean(errT.^2));
    maeT    = mean(abs(errT));
    maxErrT = max(abs(errT));
    biasT   = mean(errT);

    bal_active_frac = sum(abs(I_bal_k(:)) > 0) / numel(I_bal_k) * 100;

    % --- Store results ---
    results.duration_s(k)         = dur;
    results.n_samples(k)          = numel(t_s);
    results.SoC_init_pct(k)       = soc0;
    results.T_init_C(k)           = T0;
    results.T_amb_mean_C(k)       = mean(T_amb);
    results.T_cool_init_C(k)      = T_cool_init_k;
    results.R0_fresh_Ohm(k)       = R0_fresh_trip;
    results.rmse_V_mV(k)          = rmseV;
    results.mae_V_mV(k)           = maeV;
    results.max_err_V_mV(k)       = maxErrV;
    results.bias_V_mV(k)          = biasV;
    results.rmse_SoC_pct(k)       = rmseSoC;
    results.SoC_end_meas(k)       = SoC_m(end);
    results.SoC_end_sim(k)        = SoC_sim(end);
    results.rmse_T_C(k)           = rmseT;
    results.mae_T_C(k)            = maeT;
    results.max_err_T_C(k)        = maxErrT;
    results.bias_T_C(k)           = biasT;
    results.SoH_final(k)          = SoH_sim(end);
    results.bal_active_pct(k)     = bal_active_frac;
    results.max_severity(k)       = max(sev_sim);
    results.shutdown_triggered(k) = any(shut_sim > 0.5);
    results.sim_time_s(k)         = t_sim_elapsed;
    results.sim_ok(k)             = 1;
    results.n_faults(k)           = sum(diff(sev_sim > 0) > 0);
    results.max_OV_sev(k)         = max(OV_sev);
    results.max_UV_sev(k)         = max(UV_sev);
    results.max_OT_sev(k)         = max(OT_sev);
    results.max_UT_sev(k)         = max(UT_sev);
    results.max_I_db_sev(k)       = max(I_db_sev);
    results.max_SC_sev(k)         = max(SC_sev);
    results.campaign{k}           = camp;

    if VERBOSE
        fprintf('  V RMSE=%6.1f mV | SoC RMSE=%5.2f%% | T RMSE=%5.2f°C | sev_max=%.0f | t_sim=%.1fs\n', ...
            rmseV, rmseSoC, rmseT, max(sev_sim), t_sim_elapsed);
    end

    % --- Per-trip plot ---
    if SAVE_PLOTS
        is_bal_trip = strcmp(tid, 'TripB04');
        nRows = 2 + is_bal_trip;
        fig = figure('Position', [50 50 1500 nRows*300], 'Visible', 'off');

        % Pack voltage
        subplot(nRows, 2, 1);
        plot(t_sim, V_meas_i, 'k', t_sim, V_sim, 'r--', 'LineWidth', 0.8);
        ylabel('V_{pack} [V]');
        title(sprintf('Pack Voltage | RMSE = %.1f mV | Bias = %+.1f mV', rmseV, biasV));
        legend('Measured','BMS','Location','best'); grid on;

        % SoC
        subplot(nRows, 2, 2);
        plot(t_sim, SoC_meas_i, 'k', t_sim, SoC_sim, 'r--', 'LineWidth', 0.8);
        ylabel('SoC [%]');
        title(sprintf('State of Charge | RMSE = %.2f%%', rmseSoC));
        legend('Measured','EKF','Location','best'); grid on;

        % Temperature
        subplot(nRows, 2, 3);
        plot(t_sim, T_meas_i, 'k', 'LineWidth', 0.9); hold on;
        plot(t_sim, T_avg_s, 'r--', 'LineWidth', 0.9);
        plot(t_sim, T_amb_i, ':', 'Color', [0.5 0.5 0.5], 'LineWidth', 0.8);
        plot(t_sim, T_cool_sim, 'b--', 'LineWidth', 0.8);
        ylabel('Temperature [°C]'); xlabel('Time [s]');
        title(sprintf('Temperature | RMSE = %.2f °C | Bias = %+.2f °C', rmseT, biasT));
        legend('T_{pack} meas','T_{pack} sim','T_{amb}','T_{cool}','Location','best'); grid on;

        % Fault severity
        subplot(nRows, 2, 4);
        hold on;
        stairs(t_sim, OV_sev,   'Color', [0.8 0.2 0.2], 'LineWidth', 0.9);
        stairs(t_sim, UV_sev,   'Color', [0.9 0.5 0.0], 'LineWidth', 0.9);
        stairs(t_sim, OT_sev,   'Color', [0.8 0.0 0.5], 'LineWidth', 0.9);
        stairs(t_sim, UT_sev,   'Color', [0.0 0.4 0.8], 'LineWidth', 0.9);
        stairs(t_sim, I_db_sev, 'Color', [0.2 0.7 0.2], 'LineWidth', 0.9);
        stairs(t_sim, SC_sev,   'Color', [0.5 0.0 0.5], 'LineWidth', 0.9);
        stairs(t_sim, sev_sim,  'k-', 'LineWidth', 1.4);
        ylabel('Severity'); xlabel('Time [s]');
        ylim([-0.3 3.5]); yticks(0:3);
        yticklabels({'OK','Warn','Derate','Shut'});
        title(sprintf('Fault Severity | max = %d', max(sev_sim)));
        legend('OV','UV','OT','UT','I_{db}','SC','FSM','Location','best','FontSize',7); grid on;

        % Balancing subplots (TripB04 only)
        if is_bal_trip
            subplot(nRows, 2, 5);
            bar(1:8, sum(I_bal_k > 0, 1), 0.6, 'FaceColor', [0.9 0.3 0.1]);
            xlabel('Module'); ylabel('Cells Balancing');
            n_bal_cells = sum(I_bal_k(:) > 0);
            title(sprintf('Balancing | %d/%d cells active (%.1f%%)', ...
                n_bal_cells, numel(I_bal_k), bal_active_frac));
            set(gca, 'XTick', 1:8); grid on;

            subplot(nRows, 2, 6);
            bar(1:8, max(soc_12x8,[],1) - min(soc_12x8,[],1), 0.6, 'FaceColor', [0.2 0.5 0.8]);
            hold on; yline(bms.bal_dSoC_thresh, 'r--', 'LineWidth', 1.2);
            xlabel('Module'); ylabel('\DeltaSoC [%]');
            title('SoC Spread | Threshold = 1%');
            set(gca, 'XTick', 1:8); grid on;
        end

        sgtitle(sprintf('MIL: %s  (Camp %s | SoC_0=%.1f%% | T_0=%.1f°C)', ...
            tid, camp, soc0, T0), 'FontWeight', 'bold');
        saveas(fig, fullfile(plotDir, sprintf('val_mil_%s.png', tid)));
        if CLOSE_FIGS, close(fig); end
    end
end

%% Save results CSV
csvPath = fullfile(milDataDir, 'mil_validation_results.csv');
writetable(results, csvPath);
fprintf('\nResults saved: %s\n', csvPath);

%% ======
%  SUMMARY
%  ======

valid = results.sim_ok == 1;
res   = results(valid, :);

fprintf('\n======\n');
fprintf('  MIL VALIDATION SUMMARY\n');
fprintf('======\n');
fprintf('  Trips: %d / %d passed\n\n', sum(valid), nTrips);

% Voltage
fprintf('  V_pack RMSE [mV]:\n');
fprintf('    Median: %6.1f  |  Mean: %6.1f  |  Max: %6.1f (%s)\n', ...
    median(res.rmse_V_mV), mean(res.rmse_V_mV), max(res.rmse_V_mV), ...
    res.trip_id{find(res.rmse_V_mV == max(res.rmse_V_mV), 1)});
fprintf('    < 500 mV: %d/%d  |  < 1000 mV: %d/%d\n\n', ...
    sum(res.rmse_V_mV < 500), height(res), sum(res.rmse_V_mV < 1000), height(res));

% SoC
fprintf('  SoC RMSE [%%]:\n');
fprintf('    Median: %6.2f  |  Mean: %6.2f  |  Max: %6.2f (%s)\n\n', ...
    median(res.rmse_SoC_pct), mean(res.rmse_SoC_pct), max(res.rmse_SoC_pct), ...
    res.trip_id{find(res.rmse_SoC_pct == max(res.rmse_SoC_pct), 1)});

% Temperature
fprintf('  T_pack RMSE [°C]:\n');
fprintf('    Median: %6.2f  |  Mean: %6.2f  |  Max: %6.2f (%s)\n\n', ...
    median(res.rmse_T_C), mean(res.rmse_T_C), max(res.rmse_T_C), ...
    res.trip_id{find(res.rmse_T_C == max(res.rmse_T_C), 1)});

% SoH
SoH_A01_idx = find(strcmp(res.trip_id, 'TripA01'));
SoH_B38_idx = find(strcmp(res.trip_id, 'TripB38'));
fprintf('  SoH:\n');
if ~isempty(SoH_A01_idx) && ~isempty(SoH_B38_idx)
    fprintf('    TripA01: %.4f  →  TripB38: %.4f  (Δ = %+.4f)\n\n', ...
        res.SoH_final(SoH_A01_idx), res.SoH_final(SoH_B38_idx), ...
        res.SoH_final(SoH_B38_idx) - res.SoH_final(SoH_A01_idx));
else
    fprintf('    Mean: %.4f  |  Range: [%.4f, %.4f]\n\n', ...
        mean(res.SoH_final), min(res.SoH_final), max(res.SoH_final));
end

% Balancing
B04_idx = find(strcmp(res.trip_id, 'TripB04'));
fprintf('  Balancing (TripB04): ');
if ~isempty(B04_idx)
    fprintf('%.1f%% cells active\n\n', res.bal_active_pct(B04_idx));
else
    fprintf('not found\n\n');
end

% Faults
fprintf('  Faults:\n');
fprintf('    Trips with severity > 0: %d  |  Shutdowns: %d\n', ...
    sum(res.max_severity > 0), sum(res.shutdown_triggered > 0));

fault_types  = {'OV','UV','OT','UT','I_db','SC'};
fault_fields = {'max_OV_sev','max_UV_sev','max_OT_sev','max_UT_sev','max_I_db_sev','max_SC_sev'};
fprintf('\n    %-6s  %s  %s  %s\n', '', 'Warn', 'Derate', 'Shut');
for f = 1:numel(fault_types)
    col = res.(fault_fields{f});
    fprintf('    %-6s  %3d    %3d     %3d\n', fault_types{f}, ...
        sum(col >= 1), sum(col >= 2), sum(col >= 3));
end

% Fault coverage CSV
fc = cell(numel(fault_types), 4);
for f = 1:numel(fault_types)
    col = res.(fault_fields{f});
    fc(f,:) = {fault_types{f}, sum(col>=1), sum(col>=2), sum(col>=3)};
end
writetable(cell2table(fc, 'VariableNames', {'fault_type','n_warn','n_derate','n_shutdown'}), ...
    fullfile(milDataDir, 'fault_coverage_results.csv'));

% SoH trend plot
if SAVE_PLOTS
    fig_soh = figure('Position', [50 50 900 400], 'Visible', 'off');
    colors = zeros(height(res), 3);
    for i = 1:height(res)
        if strcmp(res.campaign{i}, 'A'), colors(i,:) = [0.2 0.5 0.8];
        else,                           colors(i,:) = [0.9 0.3 0.1]; end
    end
    scatter(1:height(res), res.SoH_final, 40, colors, 'filled'); hold on;
    plot(1:height(res), res.SoH_final, '-', 'Color', [0.6 0.6 0.6], 'LineWidth', 0.5);
    ylabel('SoH'); xlabel('Trip Index');
    title('SoH Trend (blue=A, red=B)'); grid on;
    saveas(fig_soh, fullfile(plotDir, 'soh_campaign_trend.png'));
    if CLOSE_FIGS, close(fig_soh); end

    % Fault coverage bar chart
    fig_fc = figure('Position', [50 50 900 400], 'Visible', 'off');
    fc_data = zeros(numel(fault_types), 3);
    for f = 1:numel(fault_types)
        col = res.(fault_fields{f});
        fc_data(f,:) = [sum(col>=1), sum(col>=2), sum(col>=3)];
    end
    bar(fc_data, 'grouped');
    set(gca, 'XTickLabel', fault_types);
    ylabel('Trips'); legend('Warn','Derate','Shut','Location','best');
    title(sprintf('Fault Coverage (%d trips)', height(res))); grid on;
    fcDir = fullfile(plotDir, 'fault_coverage');
    if ~exist(fcDir, 'dir'), mkdir(fcDir); end
    saveas(fig_fc, fullfile(fcDir, 'fault_coverage_summary.png'));
    if CLOSE_FIGS, close(fig_fc); end
end

% Campaign breakdown
for c = {'A','B'}
    cc = c{1};
    mask = strcmp(res.campaign, cc);
    if ~any(mask), continue; end
    rc = res(mask, :);
    fprintf('\n  --- Campaign %s (%d trips) ---\n', cc, height(rc));
    fprintf('    V RMSE:  median=%.1f mV, mean=%.1f mV, bias=%+.1f mV\n', ...
        median(rc.rmse_V_mV), mean(rc.rmse_V_mV), mean(rc.bias_V_mV));
    fprintf('    SoC RMSE: median=%.2f%%, mean=%.2f%%\n', ...
        median(rc.rmse_SoC_pct), mean(rc.rmse_SoC_pct));
    fprintf('    T RMSE:  median=%.2f°C, mean=%.2f°C\n', ...
        median(rc.rmse_T_C), mean(rc.rmse_T_C));
    fprintf('    T_init: [%.1f, %.1f] °C  |  SoC_init: [%.1f, %.1f]%%\n', ...
        min(rc.T_init_C), max(rc.T_init_C), min(rc.SoC_init_pct), max(rc.SoC_init_pct));
end

fprintf('\n  Sim speed: mean=%.1f s/trip, total=%.1f min\n', ...
    mean(res.sim_time_s), sum(res.sim_time_s));
fprintf('\n======\n');

if exist('TRIP_ID', 'var'), clear TRIP_ID; end
