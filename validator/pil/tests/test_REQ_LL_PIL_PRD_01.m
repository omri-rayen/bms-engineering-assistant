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

% MIL vs PIL: prob_3 (one row per class).
s_mil = val.signal(out_mil, 'prob_3');
s_pil = val.signal(out_pil, 'prob_3');
L = min(numel(s_mil.t), numel(s_pil.t));
nC = size(prob_mil, 2);
sigs = repmat(struct('name','','t',[],'y_ref',[],'y_tgt',[]), nC, 1);
labels = {'OT (class 1)','OV (class 2)','UV (class 3)'};
for c = 1:nC
    sigs(c).name  = labels{min(c,numel(labels))};
    sigs(c).t     = s_mil.t(1:L);
    sigs(c).y_ref = s_mil.y(1:L, c);
    sigs(c).y_tgt = s_pil.y(1:L, c);
end
r.signals_plot = string(val.equivalence_plot(r, struct( ...
    'plot_dir', val.plot_root('pil'), 'filename', 'PIL-PRD-01.png', ...
    'ref_label','MIL host', 'tgt_label','PIL STM32', ...
    'tol_abs', ABS_TOL, ...
    'signals', sigs)));
end
