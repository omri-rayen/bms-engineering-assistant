function r = test_REQ_LL_RT_WCET_01()
% REQ-LL-RT-WCET-01  On-chip per-step WCET of bms_master, measured by
% Embedded Coder code-execution profiling sampled by the free-running
% 32-bit TIM5 counter on the STM32 H7A3 (280 MHz, 1 tick = 3.57 ns).
% After skipping req.RT_WCET_warmup steps (cold-start: LSTM weight load,
% caches), the MAX step time over >= req.RT_WCET_min_steps consecutive
% PIL steps at Ts = 100 ms SHALL stay below req.RT_WCET_max_us.
r = val.new_result("pil","RT-WCET-01","bms_master per-step WCET","REQ-LL-RT-WCET-01");

mdl = 'bms_master';
load_system(mdl);
req       = evalin('base', 'req');
BUDGET_US = req.RT_WCET_max_us;
N_STEPS   = req.RT_WCET_min_steps;
WARMUP    = req.RT_WCET_warmup;

dt    = 0.1;
RUN_S = (N_STEPS + WARMUP) * dt;
t  = (0:dt:RUN_S)';
N  = numel(t);
ds = val.master_inputs(t, ...
    'I_pack',       30 * ones(N, 1), ...
    'V_cells_96',   linspace(3.95, 3.85, N).' .* ones(1, 96), ...
    'T_sensors_32', 25 * ones(N, 32), ...
    'T_coolant',    25 * ones(N, 1));

set_param(mdl, 'SimulationMode', 'processor-in-the-loop');
cleanup = onCleanup(@() set_param(mdl, 'SimulationMode', 'normal')); %#ok<NASGU>
out = val.sim_model(mdl, ds, RUN_S);

[step_us, section_name] = i_extract_step_us(out, mdl);
if numel(step_us) <= WARMUP
    error('pil:wcet:tooFew', 'only %d samples, need > warmup=%d', numel(step_us), WARMUP);
end
warm_us = step_us(WARMUP+1:end);

max_us  = max(warm_us);
mean_us = mean(warm_us);
p99_us  = prctile(warm_us, 99);

ok = max_us < BUDGET_US;
r  = val.check(r, "wcet_within_budget", ok, ...
    sprintf('max=%.1f us  p99=%.1f us  mean=%.1f us  n=%d (after %d warmup, budget %.0f us, "%s")', ...
        max_us, p99_us, mean_us, numel(warm_us), WARMUP, BUDGET_US, section_name), ...
    max_us, sprintf('< %.0f us', BUDGET_US));

r.metrics.max_us       = max_us;
r.metrics.p99_us       = p99_us;
r.metrics.mean_us      = mean_us;
r.metrics.cold_start_us = step_us(1);
r.metrics.n_steps      = numel(warm_us);
r.metrics.warmup       = WARMUP;
r.metrics.budget_us    = BUDGET_US;
r.metrics.section_name = section_name;

i_plot_wcet(warm_us, BUDGET_US, section_name, step_us(1));
end

% ------------------------------------------------------------------
function [step_us, name] = i_extract_step_us(out, mdl)
if ~isprop(out, 'executionProfile') || isempty(out.executionProfile)
    error('pil:wcet:noProfile', ...
        'out.executionProfile missing - PIL mode + CodeExecutionProfiling required.');
end
sec   = out.executionProfile.Sections;
names = string({sec.Name});
idx = find(contains(names, mdl, 'IgnoreCase', true) & ...
           contains(names, 'step', 'IgnoreCase', true), 1, 'first');
if isempty(idx)
    idx = find(contains(names, mdl, 'IgnoreCase', true), 1, 'first');
end
if isempty(idx), idx = 1; end
name    = char(names(idx));
step_us = sec(idx).ExecutionTimeInSeconds(:) * 1e6;
end

% ------------------------------------------------------------------
function i_plot_wcet(step_us, budget_us, name, cold_us)
try
    here    = fileparts(mfilename('fullpath'));
    valRoot = fileparts(fileparts(here));
    plotDir = fullfile(valRoot, 'reports', 'plots', 'pil');
    if ~isfolder(plotDir), mkdir(plotDir); end

    max_us  = max(step_us);
    mean_us = mean(step_us);

    fig = figure('Visible','off','Position',[100 100 950 360]);
    tiledlayout(fig, 1, 2, 'Padding','compact', 'TileSpacing','compact');

    nexttile;
    bh = barh([cold_us, max_us, mean_us, budget_us]);
    bh.FaceColor = 'flat';
    bh.CData(1,:) = [0.55 0.55 0.55];
    bh.CData(2,:) = [0.85 0.40 0.40];
    bh.CData(3,:) = [0.30 0.65 0.30];
    bh.CData(4,:) = [0.30 0.45 0.85];
    set(gca, 'YTickLabel', {'cold start','warm max','warm mean','budget'});
    xlabel('on-chip step time [us]'); grid on;
    title(sprintf('PIL WCET: warm max=%.1f / mean=%.1f / budget=%.0f us', ...
        max_us, mean_us, budget_us));

    nexttile;
    histogram(step_us, max(20, round(numel(step_us)/10)));
    xline(max_us,    'r-',  sprintf('max %.1f', max_us));
    xline(budget_us, 'b--', sprintf('budget %.0f', budget_us));
    xlabel('on-chip step time [us]'); ylabel('count'); grid on;
    title(sprintf('Per-step distribution (n=%d after warmup, "%s")', numel(step_us), name));

    exportgraphics(fig, fullfile(plotDir, 'wcet.png'), 'Resolution', 120);
    close(fig);
catch ME
    warning('pil:wcet:plot', 'wcet plot failed: %s', ME.message);
end
end
