scriptDir = fileparts(mfilename('fullpath'));
milRoot   = fileparts(scriptDir);
projRoot  = fileparts(milRoot);
plotDir   = fullfile(milRoot, 'plots', 'fault_coverage');
milData   = fullfile(milRoot, 'data');

if ~exist(plotDir, 'dir'), mkdir(plotDir); end

addpath(fullfile(milRoot, 'models'));
addpath(fullfile(projRoot, 'plant_model', 'models'));
addpath(fullfile(projRoot, 'bms_model',   'models'));

if ~exist('bms', 'var') || ~exist('ekf_params', 'var')
    run(fullfile(scriptDir, 'init_MIL_model.m'));
end

TRIP_ID    = 'TripB04';
SIM_DUR    = 60;
INJ_START  = 5;
INJ_END    = 25;
N_SERIES   = 96;
SAVE_PLOTS = true;

mdl = 'MIL_model';
load_system(fullfile(milRoot, 'models', mdl));

%% === TRIP SEGMENTS ======

trip        = trips_meas.(TRIP_ID);
t_full      = double(trip.time_s(:)) - double(trip.time_s(1));
I_full      = double(trip.I_A(:));
T_amb_full  = double(trip.T_amb_C(:));
SoC_full    = double(trip.SoC_pct(:));
T_cell_full = double(trip.T_cell_C(:));

segDef = struct( ...
    'name',   {'Discharge',                            'Charge'}, ...
    'offset', {200,                                     1800}, ...
    'desc',   {'trip t=[200,260] - discharge, I~27 A', ...
               'trip t=[1800,1860] - charge, I~-48 A'});

rng(42, 'twister');
dT_spread = randn(12, 8);
dT_spread = dT_spread - mean(dT_spread(:));

seg = struct();
for s = 1:numel(segDef)
    off = segDef(s).offset;
    idx = find(t_full >= off, 1);
    m   = t_full >= off & t_full <= off + SIM_DUR;

    seg(s).name   = segDef(s).name;
    seg(s).offset = off;
    seg(s).desc   = segDef(s).desc;
    seg(s).t_s    = t_full(m) - off;
    seg(s).I_A    = I_full(m);
    seg(s).T_amb  = T_amb_full(m);
    seg(s).soc0   = SoC_full(idx);
    seg(s).T0     = T_cell_full(idx);

    ds = Simulink.SimulationData.Dataset;
    ds = ds.addElement(timeseries(seg(s).I_A,   seg(s).t_s, 'Name', 'I_pack'), 'I_pack');
    ds = ds.addElement(timeseries(seg(s).T_amb, seg(s).t_s, 'Name', 'T_amb'),  'T_amb');
    seg(s).ds = ds;

    seg(s).T_cells_init = seg(s).T0 + 1.0 * dT_spread;
    seg(s).T_cool_init  = seg(s).T0;

    T0c = max(min(seg(s).T0,   T_bp(end)),       T_bp(1));
    s0c = max(min(seg(s).soc0, SoC_bp_ecm(end)), SoC_bp_ecm(1));
    seg(s).R0_fresh = interp2(T_bp, SoC_bp_ecm, R0_data, T0c, s0c, 'linear');

    soc_12x8 = seg(s).soc0 + cell_dSoC_pct;
    I_bal = zeros(12, 8);
    for mm = 1:8
        smod = soc_12x8(:, mm);
        nb   = smod - min(smod) > bms.bal_dSoC_thresh;
        I_bal(nb, mm) = bms.bal_I_nom;
    end
    seg(s).I_bal_default = I_bal;
end

fprintf('\nSegments:\n');
for s = 1:numel(seg)
    fprintf('  [%d] %s | SoC0=%.1f%% | T0=%.1f C | I_mean=%.1f A\n', ...
        s, seg(s).desc, seg(s).soc0, seg(s).T0, mean(seg(s).I_A));
end

%%  SCENARIO DEFINITIONS =
%
%  {name, dV [V/cell], dT [degC], dI [A], expected_severity, segment}

scenarios = {
    % --- Baseline (no fault) ---
    'Baseline',         0,      0,      0,    0, 1

    % --- Overvoltage  (V_cell ~ 3.98 V, Segment 2) ---
    'OV_warn',         +0.15,   0,      0,    1, 2   % V~4.13 -> warn
    'OV_derate',       +0.2,   0,      0,    2, 2   % V~4.17 -> derate
    'OV_shut',         +0.32,   0,      0,    3, 2   % V~4.26 -> shut

    % --- Undervoltage (V_cell ~ 3.81 V, Segment 1) ---
    'UV_warn',         -1.03,   0,      0,    1, 1   % V~2.78
    'UV_derate',       -1.23,   0,      0,    2, 1   % V~2.58
    'UV_shut',         -1.35,   0,      0,    3, 1   % V~2.46

    % --- Overtemperature (T0 = 12 degC, Segment 1) ---
    'OT_warn',          0,    +35,      0,    1, 1   % T~47
    'OT_derate',        0,    +45,      0,    2, 1   % T~57
    'OT_shut',          0,    +50,      0,    3, 1   % T~62

    % --- Undertemperature ---
    'UT_warn',          0,    -15,      0,    1, 1   % T~-3
    'UT_derate',        0,    -25,      0,    2, 1   % T~-13
    'UT_shut',          0,    -35,      0,    3, 1   % T~-23

    % --- Overcurrent discharge (I_base ~ 27 A, Segment 1) ---
    'OC_dchg_warn',     0,      0,   +340,    1, 1   % I~367
    'OC_dchg_derate',   0,      0,   +410,    2, 1   % I~437
    'OC_dchg_shut',     0,      0,   +520,    3, 1   % I~517

    % --- Overcurrent charge (I_base ~ -48 A, Segment 2) ---
    'OC_chg_warn',      0,      0,   -120,    1, 2   % |I|~168
    'OC_chg_derate',    0,      0,   -190,    2, 2   % |I|~238
    'OC_chg_shut',      0,      0,   -320,    3, 2   % |I|~318

    % --- Short circuit (Segment 1) ---
    'SC',               0,      0,   +790,    3, 1   % I~817
};

nTests = size(scenarios, 1);

%% ==== RESULTS TABLE =====

results = table( ...
    'Size', [nTests, 8], ...
    'VariableTypes', {'string','double','double','double','double','double','logical','double'}, ...
    'VariableNames', {'scenario','segment','dV','dT','dI','expected_sev','pass','actual_max_sev'});

%% ===== MAIN LOOP ========

fprintf('\n=== Fault Injection Validation (%d scenarios) ===\n\n', nTests);
fprintf('%-22s  Seg  dV      dT      dI     Exp  Act  Result\n', 'Scenario');
fprintf('%s\n', repmat('-', 1, 78));

bms.N_watchdog_timeout = 1e8;
prevSeg = 0;

for k = 1:nTests
    name   = scenarios{k, 1};
    dV     = scenarios{k, 2};
    dT     = scenarios{k, 3};
    dI     = scenarios{k, 4};
    expSev = scenarios{k, 5};
    segIdx = scenarios{k, 6};

    if segIdx ~= prevSeg
        T_cells_init    = seg(segIdx).T_cells_init;
        T_cool_init     = seg(segIdx).T_cool_init;
        V_RC1_init      = 0;
        V_RC2_init      = 0;
        SoC_init        = seg(segIdx).soc0;
        ekf_params.SoC0 = seg(segIdx).soc0 / 100;
        bms.R0_fresh    = seg(segIdx).R0_fresh;
        I_bal_default   = seg(segIdx).I_bal_default;
        prevSeg         = segIdx;
        fprintf('  [Segment %d: %s]\n', segIdx, seg(segIdx).desc);
    end

    t_inj = [0; INJ_START - 0.01; INJ_START; INJ_END; INJ_END + 0.01; SIM_DUR + 10];
    fault_inj_dV = timeseries([0; 0; dV; dV; 0; 0], t_inj);
    fault_inj_dT = timeseries([0; 0; dT; dT; 0; 0], t_inj);
    fault_inj_dI = timeseries([0; 0; dI; dI; 0; 0], t_inj);

    simIn = Simulink.SimulationInput(mdl);
    simIn = simIn.setModelParameter('StopTime',  num2str(SIM_DUR));
    simIn = simIn.setModelParameter('SaveTime',  'on');
    simIn = simIn.setModelParameter('SaveOutput', 'on');
    simIn = simIn.setModelParameter('SaveFormat', 'Dataset');
    simIn = simIn.setModelParameter('ReturnWorkspaceOutputs',     'on');
    simIn = simIn.setModelParameter('ReturnWorkspaceOutputsName', 'out');
    simIn = simIn.setExternalInput(seg(segIdx).ds);

    try
        out = sim(simIn);
    catch ME
        fprintf('%-22s  %d    %+6.2f %+5.0f  %+5.0f  %d    ERR  FAIL (%s)\n', ...
            name, segIdx, dV, dT, dI, expSev, ME.message);
        results.scenario(k)       = name;
        results.segment(k)        = segIdx;
        results.dV(k)             = dV;
        results.dT(k)             = dT;
        results.dI(k)             = dI;
        results.expected_sev(k)   = expSev;
        results.pass(k)           = false;
        results.actual_max_sev(k) = -1;
        continue;
    end

    mo      = out.yout.getElement(1).Values;
    t_sim   = mo.fault_severity.Time;
    sev_sim = squeeze(double(mo.fault_severity.Data));

    inj_mask = t_sim >= INJ_START & t_sim <= INJ_END + 5;
    maxSev   = max(sev_sim(inj_mask));
    passed   = (maxSev == expSev);

    results.scenario(k)       = name;
    results.segment(k)        = segIdx;
    results.dV(k)             = dV;
    results.dT(k)             = dT;
    results.dI(k)             = dI;
    results.expected_sev(k)   = expSev;
    results.pass(k)           = passed;
    results.actual_max_sev(k) = maxSev;

    tag = 'PASS'; if ~passed, tag = 'FAIL'; end
    fprintf('%-22s  %d    %+6.2f %+5.0f  %+5.0f  %d    %d    %s\n', ...
        name, segIdx, dV, dT, dI, expSev, maxSev, tag);

    % --- Per-scenario plot ---
    if SAVE_PLOTS
        V_max = squeeze(double(out.yout.getElement('V_cell_max').Values.Data));
        V_min = squeeze(double(out.yout.getElement('V_cell_min').Values.Data));
        T_max = squeeze(double(mo.T_cell_max.Data));
        T_min = squeeze(double(mo.T_cell_min.Data));
        I_bms = squeeze(double(mo.I_pack.Data));

        fig = figure('Position', [50 50 1400 650], 'Visible', 'off');
        sgtitle(sprintf('%s   [Seg %d: %s, t_{trip}=%d s]   dV=%+.2f   dT=%+.0f   dI=%+.0f   ->  sev=%d (%s)', ...
            name, segIdx, seg(segIdx).name, seg(segIdx).offset, dV, dT, dI, maxSev, tag), ...
            'FontWeight', 'bold', 'FontSize', 11);

        injPatch = @(ax, col) localInjPatch(ax, INJ_START, INJ_END, col);

        % ---- (1) Cell Voltage ----
        ax1 = subplot(2, 2, 1);
        plot(t_sim, V_max, 'b', 'LineWidth', 1.2); hold on;
        plot(t_sim, V_min, 'Color', [0 .55 .55], 'LineWidth', 1.2);
        yline(bms.V_OV_warn,   '--', 'OV warn',   'Color', [.8 .2 .2], 'LineWidth', .6, 'FontSize', 7, 'LabelHorizontalAlignment', 'left');
        yline(bms.V_OV_derate, '-.', 'OV derate', 'Color', [.8 .2 .2], 'LineWidth', .6, 'FontSize', 7, 'LabelHorizontalAlignment', 'left');
        yline(bms.V_OV_shut,   '-',  'OV shut',   'Color', [.8 .2 .2], 'LineWidth', .6, 'FontSize', 7, 'LabelHorizontalAlignment', 'left');
        yline(bms.V_UV_warn,   '--', 'UV warn',   'Color', [.6 0 .6],  'LineWidth', .6, 'FontSize', 7, 'LabelHorizontalAlignment', 'left');
        yline(bms.V_UV_derate, '-.', 'UV derate', 'Color', [.6 0 .6],  'LineWidth', .6, 'FontSize', 7, 'LabelHorizontalAlignment', 'left');
        yline(bms.V_UV_shut,   '-',  'UV shut',   'Color', [.6 0 .6],  'LineWidth', .6, 'FontSize', 7, 'LabelHorizontalAlignment', 'left');
        injPatch(ax1, [.85 .92 1]);
        legend('V_{max}', 'V_{min}', 'Location', 'best', 'FontSize', 7);
        ylabel('V_{cell} [V]'); xlabel('Time [s]');
        title('Cell Voltage (V_{max} / V_{min})'); grid on;

        % ---- (2) Temperature ----
        ax2 = subplot(2, 2, 2);
        plot(t_sim, T_max, 'r', 'LineWidth', 1.2); hold on;
        plot(t_sim, T_min, 'Color', [.2 .2 .8], 'LineWidth', 1.2);
        yline(bms.T_OT_warn,   '--', 'OT warn',   'Color', [.8 .2 .2], 'LineWidth', .6, 'FontSize', 7, 'LabelHorizontalAlignment', 'left');
        yline(bms.T_OT_derate, '-.', 'OT derate', 'Color', [.8 .2 .2], 'LineWidth', .6, 'FontSize', 7, 'LabelHorizontalAlignment', 'left');
        yline(bms.T_OT_shut,   '-',  'OT shut',   'Color', [.8 .2 .2], 'LineWidth', .6, 'FontSize', 7, 'LabelHorizontalAlignment', 'left');
        yline(bms.T_UT_warn,   '--', 'UT warn',   'Color', [.2 .2 .8], 'LineWidth', .6, 'FontSize', 7, 'LabelHorizontalAlignment', 'left');
        yline(bms.T_UT_derate, '-.', 'UT derate', 'Color', [.2 .2 .8], 'LineWidth', .6, 'FontSize', 7, 'LabelHorizontalAlignment', 'left');
        yline(bms.T_UT_shut,   '-',  'UT shut',   'Color', [.2 .2 .8], 'LineWidth', .6, 'FontSize', 7, 'LabelHorizontalAlignment', 'left');
        injPatch(ax2, [1 .92 .85]);
        legend('T_{max}', 'T_{min}', 'Location', 'best', 'FontSize', 7);
        ylabel('T [degC]'); xlabel('Time [s]');
        title('Temperature (T_{max} / T_{min})'); grid on;

        % ---- (3) Pack Current ----
        ax3 = subplot(2, 2, 3);
        plot(t_sim, I_bms, 'Color', [0 .45 0], 'LineWidth', 1.0); hold on;
        yline( bms.I_OC_dchg_warn,   '--', 'OC dchg warn',   'Color', [.8 .2 .2], 'LineWidth', .6, 'FontSize', 7, 'LabelHorizontalAlignment', 'left');
        yline( bms.I_OC_dchg_derate, '-.', 'OC dchg derate', 'Color', [.8 .2 .2], 'LineWidth', .6, 'FontSize', 7, 'LabelHorizontalAlignment', 'left');
        yline( bms.I_OC_dchg_shut,   '-',  'OC dchg shut',   'Color', [.8 .2 .2], 'LineWidth', .6, 'FontSize', 7, 'LabelHorizontalAlignment', 'left');
        yline(-bms.I_OC_chg_warn,    '--', 'OC chg warn',    'Color', [.2 .2 .8], 'LineWidth', .6, 'FontSize', 7, 'LabelHorizontalAlignment', 'left');
        yline(-bms.I_OC_chg_derate,  '-.', 'OC chg derate',  'Color', [.2 .2 .8], 'LineWidth', .6, 'FontSize', 7, 'LabelHorizontalAlignment', 'left');
        yline(-bms.I_OC_chg_shut,    '-',  'OC chg shut',    'Color', [.2 .2 .8], 'LineWidth', .6, 'FontSize', 7, 'LabelHorizontalAlignment', 'left');
        injPatch(ax3, [.85 1 .85]);
        ylabel('I_{pack} [A]'); xlabel('Time [s]');
        title('Pack Current (BMS view)'); grid on;

        % ---- (4) Fault Severity ----
        subplot(2, 2, 4);
        stairs(t_sim, sev_sim, 'k', 'LineWidth', 1.5); hold on;
        yline(expSev, 'r--', sprintf('expected = %d', expSev), ...
            'LineWidth', 1.2, 'FontSize', 8, 'LabelHorizontalAlignment', 'left');
        ylim([-0.3 3.5]); yticks(0:3);
        yticklabels({'OK', 'Warn', 'Derate', 'Shut'});
        ylabel('Severity'); xlabel('Time [s]');
        title(sprintf('Severity | max=%d | expected=%d | %s', maxSev, expSev, tag));
        grid on;

        saveas(fig, fullfile(plotDir, sprintf('fi_%02d_%s.png', k, name)));
        close(fig);
    end
end

%% ====== SUMMARY =========

nPass = sum(results.pass);
nFail = nTests - nPass;

fprintf('\n======\n');
fprintf('  FAULT INJECTION VALIDATION SUMMARY\n');
fprintf('======\n');
fprintf('  Tests: %d / %d PASS   (%d FAIL)\n\n', nPass, nTests, nFail);

if nFail > 0
    fprintf('  FAILED scenarios:\n');
    for k = 1:nTests
        if ~results.pass(k)
            fprintf('    %-22s  seg=%d  expected=%d  actual=%d\n', ...
                results.scenario(k), results.segment(k), ...
                results.expected_sev(k), results.actual_max_sev(k));
        end
    end
    fprintf('\n');
end

faultTypes = {'Baseline', 'OV', 'UV', 'OT', 'UT', 'OC_dchg', 'OC_chg', 'SC'};
faultCount = [1, 3, 3, 3, 3, 3, 3, 1];

fprintf('  Coverage by fault type:\n');
for f = 1:numel(faultTypes)
    ft  = faultTypes{f};
    idx = startsWith(results.scenario, ft);
    nP  = sum(results.pass(idx));
    nT  = faultCount(f);
    if nP == nT, status = 'COMPLETE'; else, status = 'INCOMPLETE'; end
    fprintf('    %-14s  %d/%d %s\n', ft, nP, nT, status);
end
fprintf('\n======\n');

writetable(results, fullfile(milData, 'fault_injection_results.csv'));
fprintf('Results saved: %s\n', fullfile(milData, 'fault_injection_results.csv'));

% Coverage summary bar chart
if SAVE_PLOTS
    fig2 = figure('Position', [100 100 1000 450], 'Visible', 'off');

    cats   = categorical(results.scenario, results.scenario);
    colors = zeros(nTests, 3);
    colors( results.pass, :) = repmat([0.2 0.7 0.2], sum( results.pass), 1);
    colors(~results.pass, :) = repmat([0.8 0.2 0.2], sum(~results.pass), 1);

    b = bar(cats, results.actual_max_sev, 'FaceColor', 'flat');
    b.CData = colors; hold on;
    plot(cats, results.expected_sev, 'kx', 'MarkerSize', 10, 'LineWidth', 2);

    ylabel('Fault Severity'); ylim([-0.5 4]);
    yticks(0:3); yticklabels({'OK', 'Warn', 'Derate', 'Shut'});
    legend({'Actual', 'Expected'}, 'Location', 'northwest');
    title(sprintf('Fault Injection Coverage - %d/%d PASS', nPass, nTests));
    grid on; set(gca, 'XTickLabelRotation', 45);

    saveas(fig2, fullfile(plotDir, 'fault_coverage_summary.png'));
    close(fig2);
    fprintf('Coverage plot saved: %s\n', fullfile(plotDir, 'fault_coverage_summary.png'));
end

%% === LOCAL HELPERS ======

function localInjPatch(ax, t0, t1, col)
% Adds a shaded injection-window patch behind existing axes content.
    yl = ylim(ax);
    patch(ax, [t0 t1 t1 t0], [yl(1) yl(1) yl(2) yl(2)], ...
        col, 'EdgeColor', 'none', 'FaceAlpha', .20);
    uistack(ax.Children(end), 'bottom');
    ylim(ax, yl);
end