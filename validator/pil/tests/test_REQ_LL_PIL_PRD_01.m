function r = test_REQ_LL_PIL_PRD_01()
% REQ-LL-PIL-PRD-01  LSTM fault predictor outputs on the STM32 target SHALL
% match the host MIL reference within req.PIL_PRD_prob_abs_tol on prob_3
% over a 30 s deterministic excitation. PIL must already be built before
% this runs.
RUN_S = 30.0;

r = val.new_result("pil","PIL-PRD-01","LSTM prob_3 PIL vs MIL equivalence","REQ-LL-PIL-PRD-01");

mdl = 'bms_master';
load_system(mdl);
ABS_TOL = evalin('base', 'req.PIL_PRD_prob_abs_tol');

dt = 0.1;
t  = (0:dt:RUN_S)';
N  = numel(t);

I_pack = linspace(-50, 80, N)';
V_cell = (3.90 + 0.10 * sin(2*pi*0.05*t)) .* ones(1, 96);
T_amb  = 25;
T_sens = T_amb * ones(N, 32);
T_cool = T_amb * ones(N, 1);
ds = val.master_inputs(t, ...
    'I_pack',       I_pack, ...
    'V_cells_96',   V_cell, ...
    'T_sensors_32', T_sens, ...
    'T_coolant',    T_cool);

% MIL reference
set_param(mdl, 'SimulationMode', 'normal');
out_mil = val.sim_model(mdl, ds, RUN_S);
prob_mil = val.signal(out_mil, 'prob_3').y;

% PIL run (assumes pil.configure + pil.build already executed by pil.run)
set_param(mdl, 'SimulationMode', 'processor-in-the-loop');
cleanup = onCleanup(@()set_param(mdl, 'SimulationMode', 'normal'));
out_pil = val.sim_model(mdl, ds, RUN_S);
prob_pil = val.signal(out_pil, 'prob_3').y;

if ~isequal(size(prob_mil), size(prob_pil))
    L = min(size(prob_mil,1), size(prob_pil,1));
    prob_mil = prob_mil(1:L, :);
    prob_pil = prob_pil(1:L, :);
end

err = abs(prob_pil - prob_mil);
max_err = max(err, [], 'all');
ok = max_err <= ABS_TOL;

r = val.check(r, "prob3_pil_matches_mil", ok, ...
    sprintf('max|prob3_pil - prob3_mil| = %.3e (tol %.1e)', max_err, ABS_TOL), ...
    max_err, ABS_TOL);

r.metrics.max_abs_err = max_err;
r.metrics.mean_abs_err = mean(err, 'all');
r.metrics.run_s = RUN_S;

% Overlay MIL vs PIL prob_3 (3 fault classes).
try
    here    = fileparts(mfilename('fullpath'));
    valRoot = fileparts(fileparts(here));
    plotDir = fullfile(valRoot, 'reports', 'plots', 'pil');
    if ~isfolder(plotDir), mkdir(plotDir); end
    s_mil = val.signal(out_mil, 'prob_3');
    s_pil = val.signal(out_pil, 'prob_3');
    L = min(numel(s_mil.t), numel(s_pil.t));
    fig = figure('Visible','off','Position',[100 100 1100 700]);
    nC  = size(prob_mil, 2);
    for c = 1:nC
        subplot(nC, 1, c);
        plot(s_mil.t(1:L), s_mil.y(1:L, c), 'k-',  'LineWidth', 1.0); hold on;
        plot(s_pil.t(1:L), s_pil.y(1:L, c), 'r--', 'LineWidth', 1.0);
        ylabel(sprintf('prob_{class %d}', c)); grid on;
        if c == 1
            title(sprintf('PIL vs MIL  -  prob\\_3  -  max|err|=%.2e (tol %.1e)', max_err, ABS_TOL));
        end
        if c == nC, xlabel('time [s]'); end
        legend({'MIL','PIL'}, 'Location','best');
    end
    exportgraphics(fig, fullfile(plotDir, 'pil_vs_mil_prob3.png'), 'Resolution', 120);
    close(fig);
catch ME
    warning('pil:prd:plot', 'overlay plot failed: %s', ME.message);
end
end
