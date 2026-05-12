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

r.signals_plot = string(i_plot_wcet(r, warm_us, BUDGET_US, section_name, step_us(1)));
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
function out_path = i_plot_wcet(r, step_us, budget_us, name, cold_us)
out_path = '';
try
    plotDir = val.plot_root('pil');
    out_path = fullfile(plotDir, 'RT-WCET-01.png');

    max_us  = max(step_us);
    p99_us  = prctile(step_us, 99);
    mean_us = mean(step_us);
    verdict = upper(char(r.status));
    switch lower(verdict)
        case 'pass',  vcol = [0.20 0.55 0.20];
        case 'fail',  vcol = [0.85 0.20 0.20];
        case 'error', vcol = [0.85 0.20 0.20];
        otherwise,    vcol = [0.40 0.40 0.40];
    end

    fig = figure('Visible','off','Position',[100 100 1100 420], 'Color','w');
    tl = tiledlayout(fig, 1, 2, 'Padding','compact', 'TileSpacing','compact');
    title(tl, {sprintf('%s  -  %s', char(r.id), char(r.name)), ...
               sprintf('section: %s', name), ...
               sprintf('verdict: %s', verdict)}, ...
          'Interpreter','none','FontSize',11,'FontWeight','bold','Color',vcol);

    nexttile;
    plot(1:numel(step_us), step_us, '-', 'Color',[0.20 0.40 0.85], 'LineWidth',1.0); hold on;
    plot(0, cold_us, 'sk', 'MarkerFaceColor',[0.5 0.5 0.5], 'MarkerSize',8);
    yline(budget_us, 'r--', sprintf('budget %.0f us', budget_us), ...
          'LabelHorizontalAlignment','left','FontSize',8);
    yline(max_us, 'k:', sprintf('warm max %.1f', max_us), ...
          'LabelHorizontalAlignment','right','FontSize',8);
    yline(p99_us, 'b:', sprintf('p99 %.1f', p99_us), ...
          'LabelHorizontalAlignment','right','FontSize',8);
    text(0, cold_us, '  cold start', 'FontSize',8, 'Color',[0.3 0.3 0.3]);
    xlabel('warm step index'); ylabel('on-chip step time [us]'); grid on;
    title(sprintf('per-step (cold = %.1f us, warm max = %.1f us)', cold_us, max_us));

    nexttile;
    histogram(step_us, max(20, round(numel(step_us)/10)), ...
              'FaceColor',[0.20 0.40 0.85], 'EdgeColor','none');
    xline(max_us,    'k:', sprintf('warm max %.1f', max_us), 'FontSize',8);
    xline(budget_us, 'r--', sprintf('budget %.0f', budget_us), 'FontSize',8);
    xlabel('on-chip step time [us]'); ylabel('count'); grid on;
    title(sprintf('distribution (n=%d, mean=%.1f us)', numel(step_us), mean_us));

    exportgraphics(fig, out_path, 'Resolution', 120);
    close(fig);
catch ME
    warning('pil:wcet:plot', 'wcet plot failed: %s', ME.message);
    out_path = '';
end
end
