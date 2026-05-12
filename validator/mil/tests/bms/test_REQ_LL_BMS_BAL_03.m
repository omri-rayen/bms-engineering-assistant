function r = test_REQ_LL_BMS_BAL_03()
% REQ-LL-BMS-BAL-03  Master Balancing_Arbitrator selects different
% modules for balancing as the cell-spread pattern moves across the
% pack. Stays at SoC>0.80 (above bms.bal_SoC_min) and near rest current
% so the arbitrator is enabled.

r = val.new_result("bms","BMS-BAL-03","Master arbitrator module sweep","REQ-LL-BMS-BAL-03");

mdl = 'bms_master';
load_system(mdl);
bms = evalin('base', 'bms');

% Cell voltages must be consistent with SoC >= bal_SoC_min (0.80) so the
% EKF does not converge below threshold and block the arbitrator.
% OCV at SoC=82% is ~4.05 V (from cell_ocv data). Spike one module at a
% time +30 mV > bal_dV_module_thresh (0.02 V).
V_base  = 4.05;
V_spike = V_base + 0.03;

% Align EKF initial guess to the cell voltage so it settles quickly.
ekf      = evalin('base', 'ekf_params');
ekf.SoC0 = 0.82;
assignin('base', 'ekf_params', ekf);
assignin('base', 'SoC_init', 82);

dt      = 0.1;
settle  = 2;             % steps with all cells flat before first spike
W       = 10;            % steps per module window (1 s)
% Total steps: settle + 8*W + tail. Must stay < N_watchdog_timeout (100
% steps = 10 s) to prevent the slave-watchdog from firing and blocking
% balancing via fault_severity = 3.
T    = (settle + 8*W + 5) * dt;   % 8.7 s < 10 s
t    = (0:dt:T)'; N = numel(t);

V96 = repmat(V_base, N, 96);
for m = 1:8
    a = settle + 1 + (m-1)*W;     % 1-based index, leave settle flat
    b = min(N, a + W - 1);
    V96(a:b, (m-1)*12+(1:12)) = V_spike;
end

ds  = val.master_inputs(t, 'V_cells_96', V96, 'I_pack', zeros(N,1), ...
                       'T_sensors_32', 25*ones(N,32), 'T_coolant', 25*ones(N,1));
out = val.sim_model(mdl, ds, T);

en = val.signal(out, 'enable_bal_8').y;   % N x 8

% Each of the 8 modules must have been enabled at least once.
modules_active = any(en > 0.5, 1);
ok_each = all(modules_active);
r = val.check(r, "every_module_balanced_once", ok_each, ...
    sprintf('active=[%s]', strjoin(arrayfun(@num2str, modules_active, 'uni', 0), ',')), ...
    sum(modules_active), 8);

% At t=0 (settle steps before any spike) all modules must be off.
ok_off = all(en(1, :) < 0.5);
r = val.check(r, "all_off_at_t0", ok_off, '', max(en(1,:)), 0);

r.metrics.modules_active = sum(modules_active);

% Storyboard: which module is being spiked vs which module the
% arbitrator enables. Show the per-module "any cell spiked" mask
% and overlay enable_bal_8 (with module index encoded in y).
mod_spike = zeros(N, 8);
for m = 1:8
    a = settle + 1 + (m-1)*W;
    b = min(N, a + W - 1);
    mod_spike(a:b, m) = m;
end
spike_idx = sum(mod_spike, 2);     % which module index is currently spiked
en_idx    = en .* (1:8);           % per-module enable, weighted by index
enabled_any = sum(en_idx, 2) ./ max(sum(en > 0.5, 2), 1);
enabled_any(isnan(enabled_any)) = 0;
stim = struct('t', t, 'y', spike_idx, 'label', 'spiked module #');
resp = struct('t', val.signal(out,'enable_bal_8').t, 'y', enabled_any, ...
    'label', 'enabled module #');
phases = cell(8, 3);
for m = 1:8
    a = settle*dt + (m-1)*W*dt;
    b = a + W*dt;
    phases(m,:) = {a, b, sprintf('mod%d', m)};
end
asserts = {T, ok_each, sprintf('all 8 modules active (%d/8)', sum(modules_active)); ...
           0.05, ok_off, 'all off at t=0'};
r.signals_plot = string(val.scenario_plot(r, struct( ...
    'plot_dir', val.plot_root('mil','bms'), 'filename', 'BMS-BAL-03.png', ...
    'subtitle', 'cell spike sweeps modules 1..8; arbitrator must select each in turn', ...
    'stim', stim, 'resp', resp, 'phases', {phases}, 'asserts', {asserts})));
end
