function report = run(varargin)
% plant.run  Plant-model convergence phase against the BMW i3 trips.
%
% Steps:
%   1. Simulate the closed-loop plant on every trip, compute per-trip
%      RMSE on V_pack, SoC and T_pack, write plant_convergence.json.
%   2. Save a 3-subplot PNG per trip (V, SoC, T+coolant) under
%      validator/reports/plots/plant/.
%   3. Run the 3 acceptance tests in validator/plant/tests/ and write
%      PLANT.json (+ a timestamped copy).
%
% Options:
%   plant.run('trips',{'TripA01','TripA02'})  subset of trips
%   plant.run('plots',false)                  skip per-trip figures
%   plant.run('skip_sim',true)                reuse cached JSON
%
% Standalone phase, independent from the BMS MIL/SIL/PIL pipeline.

p = inputParser;
p.addParameter('trips',    {});
p.addParameter('plots',    true);
p.addParameter('skip_sim', false);
p.addParameter('verbose',  true);
p.addParameter('outFile',  '');
p.parse(varargin{:});
opt = p.Results;

here      = fileparts(mfilename('fullpath'));   % validator/plant/+plant
plantRoot = fileparts(here);                    % validator/plant
valRoot   = fileparts(plantRoot);               % validator
proj      = fileparts(valRoot);
repDir    = fullfile(valRoot, 'reports');
testsDir  = fullfile(plantRoot, 'tests');
if ~isfolder(repDir), mkdir(repDir); end

if evalin('base', '~exist(''bms'',''var'')')
    initFile = fullfile(proj, 'model', 'system', 'params', 'init_system.m');
    evalin('base', sprintf('run(''%s'')', initFile));
end

cacheJson = fullfile(repDir, 'plant_convergence.json');
if opt.skip_sim && isfile(cacheJson)
    if opt.verbose, fprintf('plant.run: reusing %s\n', cacheJson); end
else
    plant_convergence(opt, repDir);
end

% --- run acceptance tests ---
results = repmat(val.new_result("","","",""), 0, 1);
files = dir(fullfile(testsDir, 'test_*.m'));
if opt.verbose, fprintf('\n--- acceptance tests ---\n'); end
for f = 1:numel(files)
    [~, fn] = fileparts(files(f).name);
    if opt.verbose, fprintf('  [plant] %-40s ', fn); end
    snap = val.snapshot_ws();
    t0 = tic;
    try
        r = feval(fn);
    catch ME
        r = val.new_result("plant", string(fn), string(fn), "");
        r.status = "error";
        r.error  = string(ME.message);
        fprintf(2, '\n    ERROR: %s\n', getReport(ME, 'extended'));
    end
    r.duration_s = toc(t0);
    if isempty(r.suite) || r.suite == "", r.suite = "plant"; end
    val.restore_ws(snap);
    if opt.verbose, fprintf('%-7s  (%.2fs)\n', upper(r.status), r.duration_s); end
    results(end+1, 1) = r; %#ok<AGROW>
end

report.timestamp = string(datetime('now','Format','yyyyMMdd_HHmmss'));
report.suite     = "plant";
report.summary   = val.summarize(results);
report.results   = results;
report.convergence = jsondecode(fileread(cacheJson));

customOut = ~isempty(opt.outFile);
if ~customOut
    opt.outFile = fullfile(repDir, sprintf('PLANT_%s.json', report.timestamp));
end
val.export_json(report, opt.outFile);
if ~customOut
    val.export_json(report, fullfile(repDir, 'PLANT.json'));
end

if opt.verbose
    fprintf('\n=== PLANT VALIDATION SUMMARY ===\n');
    fprintf('Total: %d  pass: %d  fail: %d  error: %d  skipped: %d\n', ...
        report.summary.total, report.summary.pass, report.summary.fail, ...
        report.summary.error, report.summary.skipped);
    fprintf('Report: %s\n', opt.outFile);
end
end


function plant_convergence(opt, repDir)
% Per-trip simulation + RMSE + figures, dumped to plant_convergence.json.

plotDir = fullfile(repDir, 'plots', 'plant');
if opt.plots && ~isfolder(plotDir), mkdir(plotDir); end

mdl = 'system_model';
load_system(mdl);

trips = evalin('base', 'trips_meas');
ids = fieldnames(trips);
if ~isempty(opt.trips), ids = intersect(ids, opt.trips, 'stable'); end

if opt.verbose
    fprintf('\n=== PLANT CONVERGENCE  (%d trips) ===\n', numel(ids));
end

per_trip = struct('id',{},'rmse_V',{},'rmse_SoC',{},'rmse_T',{},'duration_s',{});
for k = 1:numel(ids)
    tid = ids{k};
    tr  = trips.(tid);
    t   = double(tr.time_s) - double(tr.time_s(1));
    fp.set_baseline(fp.make_trip(trips, tid));
    ds  = val.dataset_from('I_pack', t, double(tr.I_A), 'T_amb', t, double(tr.T_amb_C));
    try
        out = val.sim_model(mdl, ds, t(end));
    catch ME
        if opt.verbose, fprintf('  [%2d/%d] %-12s SIM-FAIL  (%s)\n', k, numel(ids), tid, ME.message); end
        continue
    end

    V_sim   = val.signal(out, 'V_pack').y;
    SoC_sim = val.signal(out, 'SoC_pack').y * 100;
    T_sim   = val.signal(out, 'T_pack').y;
    t_sim   = val.signal(out, 'V_pack').t;
    try
        Tc_sim = val.signal(out, 'T_coolant').y;
    catch
        Tc_sim = [];
    end

    V_meas   = interp1(t, double(tr.V_pack_V),  t_sim, 'linear', 'extrap');
    SoC_meas = interp1(t, double(tr.SoC_pct),   t_sim, 'linear', 'extrap');
    T_meas   = interp1(t, double(tr.T_cell_C),  t_sim, 'linear', 'extrap');

    rmse_V   = sqrt(mean((V_sim   - V_meas).^2));
    rmse_SoC = sqrt(mean((SoC_sim - SoC_meas).^2));
    rmse_T   = sqrt(mean((T_sim   - T_meas).^2));

    per_trip(end+1) = struct( ...
        'id',         string(tid), ...
        'rmse_V',     rmse_V, ...
        'rmse_SoC',   rmse_SoC, ...
        'rmse_T',     rmse_T, ...
        'duration_s', t(end)); %#ok<AGROW>

    if opt.verbose
        fprintf('  [%2d/%d] %-12s  V=%.3f V   SoC=%.3f %%   T=%.3f degC\n', ...
            k, numel(ids), tid, rmse_V, rmse_SoC, rmse_T);
    end

    if opt.plots
        plot_trip(plotDir, tid, t_sim, ...
            V_sim, V_meas, rmse_V, ...
            SoC_sim, SoC_meas, rmse_SoC, ...
            T_sim, T_meas, Tc_sim, rmse_T);
    end
end

if isempty(per_trip)
    error('plant:run:empty', 'No trip simulated successfully.');
end

rV = [per_trip.rmse_V];   rS = [per_trip.rmse_SoC];   rT = [per_trip.rmse_T];
out_report.run_id   = string(datetime('now','Format','yyyyMMdd_HHmmss'));
out_report.env      = val.env_info();
out_report.n_trips  = numel(per_trip);
out_report.V_pack   = struct('median', median(rV), 'mean', mean(rV), 'max', max(rV), 'units', 'V');
out_report.SoC_pack = struct('median', median(rS), 'mean', mean(rS), 'max', max(rS), 'units', '%');
out_report.T_pack   = struct('median', median(rT), 'mean', mean(rT), 'max', max(rT), 'units', 'degC');
out_report.per_trip = per_trip;

cacheFile = fullfile(repDir, 'plant_convergence.json');
fid = fopen(cacheFile, 'w');
if fid < 0, error('plant:run:io', 'cannot open %s', cacheFile); end
c_ = onCleanup(@() fclose(fid));
fwrite(fid, jsonencode(out_report, 'PrettyPrint', true));
clear c_;

if opt.verbose
    fprintf('\n--- aggregate ---\n');
    fprintf('  V_pack   median=%.3f V    mean=%.3f V    max=%.3f V\n', out_report.V_pack.median, out_report.V_pack.mean, out_report.V_pack.max);
    fprintf('  SoC_pack median=%.3f %%   mean=%.3f %%   max=%.3f %%\n', out_report.SoC_pack.median, out_report.SoC_pack.mean, out_report.SoC_pack.max);
    fprintf('  T_pack   median=%.3f degC mean=%.3f degC max=%.3f degC\n', out_report.T_pack.median, out_report.T_pack.mean, out_report.T_pack.max);
    fprintf('Cache : %s\n', cacheFile);
    if opt.plots
        fprintf('Plots : %s (%d trip figures)\n', plotDir, numel(per_trip));
    end
end
end


function plot_trip(plotDir, tid, t, V_sim, V_meas, rV, ...
                   SoC_sim, SoC_meas, rS, ...
                   T_sim, T_meas, Tc_sim, rT)
fig = figure('Visible','off','Position',[100 100 1100 800]);
subplot(3,1,1);
plot(t, V_meas, 'k-',  'LineWidth', 1.0); hold on;
plot(t, V_sim,  'r--', 'LineWidth', 1.2);
ylabel('V_{pack} [V]'); legend({'measured','simulated'}, 'Location','best');
title(sprintf('%s  -  RMSE(V_{pack}) = %.3f V', tid, rV), 'Interpreter','none');
grid on;
subplot(3,1,2);
plot(t, SoC_meas, 'k-',  'LineWidth', 1.0); hold on;
plot(t, SoC_sim,  'r--', 'LineWidth', 1.2);
ylabel('SoC_{pack} [%]'); legend({'measured','simulated'}, 'Location','best');
title(sprintf('RMSE(SoC_{pack}) = %.3f %%', rS));
grid on;
subplot(3,1,3);
plot(t, T_meas, 'k-',  'LineWidth', 1.0); hold on;
plot(t, T_sim,  'r--', 'LineWidth', 1.2);
leg = {'measured','simulated'};
if ~isempty(Tc_sim)
    plot(t, Tc_sim, 'b:', 'LineWidth', 1.0);
    leg{end+1} = 'simulated coolant';
end
ylabel('T_{pack} [\circC]'); xlabel('time [s]');
legend(leg, 'Location','best');
title(sprintf('RMSE(T_{pack}) = %.3f \\circC', rT));
grid on;

outFile = fullfile(plotDir, sprintf('%s.png', char(tid)));
exportgraphics(fig, outFile, 'Resolution', 120);
close(fig);
end
