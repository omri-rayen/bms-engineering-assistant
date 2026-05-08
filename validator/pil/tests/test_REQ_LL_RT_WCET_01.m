function r = test_REQ_LL_RT_WCET_01()
% REQ-LL-RT-WCET-01  Mean PIL step time (host wall-clock incl. UART
% round-trip) SHALL stay below req.RT_WCET_max_ms over at least
% req.RT_WCET_min_steps consecutive PIL steps at Ts = 100 ms.
%
% This is a host-side end-to-end measurement: it bounds the *observable*
% per-step latency including USART3 + DMA1_Stream0 transport. The on-
% chip BMS step itself executes in microseconds; the dominant term is
% the serial round-trip. The HAL timebase has been moved from TIM5 to
% TIM7 (see validator/pil/board/nucleo_h7a3zit_q.ioc) and NVIC priorities
% set so the HAL tick can never preempt the USART3/DMA1 PIL path.
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
elapsed_s = toc(t0);

n_steps      = req.RT_WCET_min_steps;
mean_step_ms = (elapsed_s / n_steps) * 1000;

ok = mean_step_ms < WCET_BUDGET_MS;
r  = val.check(r, "wcet_within_budget", ok, ...
    sprintf('mean=%.4f ms over %d steps (budget %.2f ms)', ...
        mean_step_ms, n_steps, WCET_BUDGET_MS), ...
    mean_step_ms, sprintf('< %.2f ms', WCET_BUDGET_MS));

r.metrics.mean_step_ms = mean_step_ms;
r.metrics.n_steps      = n_steps;
r.metrics.budget_ms    = WCET_BUDGET_MS;
r.metrics.elapsed_s    = elapsed_s;

try
    here    = fileparts(mfilename('fullpath'));
    valRoot = fileparts(fileparts(here));
    plotDir = fullfile(valRoot, 'reports', 'plots', 'pil');
    if ~isfolder(plotDir), mkdir(plotDir); end
    fig = figure('Visible','off','Position',[100 100 700 350]);
    bh = barh([mean_step_ms, WCET_BUDGET_MS]);
    bh.FaceColor = 'flat';
    bh.CData(1,:) = [0.30 0.65 0.30];
    bh.CData(2,:) = [0.85 0.40 0.40];
    set(gca, 'YTickLabel', {'measured (PIL mean)','budget'});
    xlabel('per-step time [ms]'); grid on;
    title(sprintf('PIL WCET  -  %.3f ms / %.2f ms  (n=%d)', ...
        mean_step_ms, WCET_BUDGET_MS, n_steps));
    text(mean_step_ms,    1, sprintf(' %.3f ms', mean_step_ms),    'VerticalAlignment','middle');
    text(WCET_BUDGET_MS,  2, sprintf(' %.2f ms', WCET_BUDGET_MS),  'VerticalAlignment','middle');
    exportgraphics(fig, fullfile(plotDir, 'wcet.png'), 'Resolution', 120);
    close(fig);
catch ME
    warning('pil:wcet:plot', 'wcet plot failed: %s', ME.message);
end
end
