function r = test_REQ_LL_BMS_AGG_02()
% REQ-LL-BMS-AGG-02  Slave-level voltage / temperature aggregator sweep
% and balancer cell argmax sweep. Targets the bms_slave MinMax decision
% trees and the per-cell Compare branch.

r = val.new_result("bms","BMS-AGG-02","Slave aggregator + balancer cell sweep","REQ-LL-BMS-AGG-02");

mdl = 'bms_slave';
load_system(mdl);

dt = 0.1;
W  = 3;
N  = 1 + 2*12*W + 2*4*W;
t  = (0:dt:T_end(N, dt))';
V12 = repmat(3.70, N, 12);
T4  = repmat(25.0, N, 4);

base = 1;
% V high spike per cell
for k = 1:12
    V12(base + (k-1)*W : base + k*W - 1, k) = 4.00;
end
base = base + 12*W;
% V low dip per cell
for k = 1:12
    V12(base + (k-1)*W : base + k*W - 1, k) = 3.20;
end
base = base + 12*W;
% T hot spot per sensor
for k = 1:4
    T4(base + (k-1)*W : base + k*W - 1, k) = 40.0;
end
base = base + 4*W;
% T cold spot per sensor
for k = 1:4
    T4(base + (k-1)*W : base + k*W - 1, k) = 5.0;
end

% Always-on balancing so the per-cell argmax gets exercised in step.
en = ones(N, 1);
ds  = val.dataset_from('V_cells_12', t, V12, 'T_sensors_4', t, T4, 'enable_bal', t, en);
out = val.sim_model(mdl, ds, t(end));

Vrep = val.signal(out, 'V_cells_rpt_12').y;
I_bal = val.signal(out, 'I_bal_12').y;

% Each cell took the spike value at some point.
peak_per_cell = max(Vrep, [], 1);
dip_per_cell  = min(Vrep, [], 1);
ok_peaks = all(peak_per_cell >= 3.99);
ok_dips  = all(dip_per_cell  <= 3.21);
r = val.check(r, "all_cells_peaked", ok_peaks, sprintf('min(peak)=%.3f', min(peak_per_cell)), min(peak_per_cell), '>=3.99');
r = val.check(r, "all_cells_dipped", ok_dips,  sprintf('max(dip)=%.3f',  max(dip_per_cell)),  max(dip_per_cell),  '<=3.21');

% Each cell drained at the bal current at least once during its peak window.
drained_per_cell = max(abs(I_bal), [], 1);
ok_drain = all(drained_per_cell > 0.05);
r = val.check(r, "every_cell_drained_once", ok_drain, ...
    sprintf('min |I_bal_max| = %.3f', min(drained_per_cell)), ...
    min(drained_per_cell), '>0.05');

time_out = val.signal(out, 'V_cells_rpt_12').t;
stim = struct('t', t, 'y', [max(V12,[],2), min(V12,[],2)], ...
    'label', 'V_{cell} sweep min/max [V]', 'channels', {{'spike','dip'}});
resp_v = struct('t', time_out, 'y', [max(Vrep,[],2), min(Vrep,[],2)], ...
    'label', 'V_{cells,rpt} reported min/max [V]', 'channels', {{'rpt_max','rpt_min'}});
resp_i = struct('t', time_out, 'y', max(abs(I_bal),[],2), ...
    'label', 'max |I_{bal,k}| [A]', 'thresholds', {{0.05,'>0.05 A'}});
asserts = {time_out(end), ok_peaks, 'all cells peaked'; ...
           time_out(end), ok_dips,  'all cells dipped'; ...
           time_out(end), ok_drain, 'all cells drained once'};
r.signals_plot = string(val.scenario_plot(r, struct( ...
    'plot_dir', val.plot_root('mil','bms'), 'filename', 'BMS-AGG-02.png', ...
    'subtitle', 'slave aggregator + balancer per-cell argmax sweep (12 cells)', ...
    'stim', stim, 'resp', {{resp_v, resp_i}}, 'asserts', {asserts})));
end

function te = T_end(N, dt)
te = (N-1) * dt;
end
