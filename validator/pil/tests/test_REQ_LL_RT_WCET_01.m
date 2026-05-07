function r = test_REQ_LL_RT_WCET_01()
% REQ-LL-RT-WCET-01  bms_master per-step execution time on the STM32
% H7A3ZI-Q SHALL be < req.RT_WCET_max_ms over at least
% req.RT_WCET_min_steps consecutive PIL steps at Ts = 100 ms.
%
% Timing = wall_clock / n_steps. This is a conservative upper bound: it
% includes PIL serial round-trip overhead, so the true on-chip step time
% is strictly less than this value.
r = val.new_result("pil","RT-WCET-01","bms_master per-step WCET","REQ-LL-RT-WCET-01");

mdl = 'bms_master';
load_system(mdl);
req = evalin('base', 'req');
WCET_BUDGET_MS = req.RT_WCET_max_ms;

dt    = 0.1;
RUN_S = req.RT_WCET_min_steps * dt;
t  = (0:dt:RUN_S)';
N  = numel(t);
I_pack = 30 * ones(N, 1);
V_cell = linspace(3.95, 3.85, N).' .* ones(1, 96);
T_sens = 25 * ones(N, 32);
T_cool = 25 * ones(N, 1);

ds = val.master_inputs(t, ...
    'I_pack',       I_pack, ...
    'V_cells_96',   V_cell, ...
    'T_sensors_32', T_sens, ...
    'T_coolant',    T_cool);

t0 = tic;
val.sim_model(mdl, ds, RUN_S);
wall_s = toc(t0);

n_steps      = N - 1;
mean_step_ms = wall_s / n_steps * 1000;

ok = mean_step_ms < WCET_BUDGET_MS;
r = val.check(r, "wcet_within_budget", ok, ...
    sprintf('mean_step=%.2f ms (n=%d, wall=%.1f s), budget=%.0f ms', ...
        mean_step_ms, n_steps, wall_s, WCET_BUDGET_MS), ...
    mean_step_ms, sprintf('< %.0f ms', WCET_BUDGET_MS));

r.metrics.mean_step_ms = mean_step_ms;
r.metrics.wall_s       = wall_s;
r.metrics.n_steps      = n_steps;
r.metrics.budget_ms    = WCET_BUDGET_MS;

% Bar: measured per-step time vs budget.
try
    here    = fileparts(mfilename('fullpath'));
    valRoot = fileparts(fileparts(here));
    plotDir = fullfile(valRoot, 'reports', 'plots', 'pil');
    if ~isfolder(plotDir), mkdir(plotDir); end
    fig = figure('Visible','off','Position',[100 100 700 400]);
    bh = barh([mean_step_ms, WCET_BUDGET_MS]);
    bh.FaceColor = 'flat';
    bh.CData(1,:) = [0.30 0.65 0.30];      % measured
    bh.CData(2,:) = [0.85 0.40 0.40];      % budget
    set(gca, 'YTickLabel', {'measured (PIL)','budget'});
    xlabel('per-step time [ms]'); grid on;
    title(sprintf('WCET  -  %.2f ms / %.0f ms  (n=%d)', mean_step_ms, WCET_BUDGET_MS, n_steps));
    text(mean_step_ms,   1, sprintf(' %.2f ms', mean_step_ms),   'VerticalAlignment','middle');
    text(WCET_BUDGET_MS, 2, sprintf(' %.0f ms', WCET_BUDGET_MS), 'VerticalAlignment','middle');
    exportgraphics(fig, fullfile(plotDir, 'wcet.png'), 'Resolution', 120);
    close(fig);
catch ME
    warning('pil:wcet:plot', 'wcet plot failed: %s', ME.message);
end
end
