function r = test_REQ_LL_BMS_AGG_01()
% REQ-LL-BMS-AGG-01  Signal aggregator min/max trees report the correct
% extremum when the spike or dip is moved across every cell / temp index.
%
% Drives bms_master with a moving spike (cell becomes the highest), a
% moving dip (cell becomes the lowest), and the same pattern on the 32
% temperature sensors. Each cell / sensor is the extremum at least once,
% which is what the MinMax trees in Signal_Aggregator need to evaluate
% every internal comparison.

r = val.new_result("bms","BMS-AGG-01","Aggregator min/max sweep across cells & temps","REQ-LL-BMS-AGG-01");

mdl = 'bms_master';
load_system(mdl);
dt = 0.1;

% Per-index window: 3 samples = enough for the MinMax to settle.
W = 3;
phaseSamples_V = 96 * W;
phaseSamples_T = 32 * W;
N = 1 + 4 * (phaseSamples_V + phaseSamples_T) / 4;  % 4 sweep phases
N = 1 + phaseSamples_V * 2 + phaseSamples_T * 2;
t = (0:N-1)' * dt;

V96  = repmat(3.70, N, 96);
T32  = repmat(25.0, N, 32);

base = 1;
% Phase 1: V high spike sweep
for k = 1:96
    V96(base + (k-1)*W : base + k*W - 1, k) = 4.00;
end
base = base + phaseSamples_V;
% Phase 2: V low dip sweep
for k = 1:96
    V96(base + (k-1)*W : base + k*W - 1, k) = 3.20;
end
base = base + phaseSamples_V;
% Phase 3: T hot spot sweep
for k = 1:32
    T32(base + (k-1)*W : base + k*W - 1, k) = 40.0;
end
base = base + phaseSamples_T;
% Phase 4: T cold spot sweep
for k = 1:32
    T32(base + (k-1)*W : base + k*W - 1, k) = 5.0;
end

ds  = val.master_inputs(t, 'V_cells_96', V96, 'T_sensors_32', T32, 'T_coolant', 25*ones(N,1));
out = val.sim_model(mdl, ds, t(end));

Vmax = val.signal(out, 'V_cell_max').y;
Vmin = val.signal(out, 'V_cell_min').y;
Tmax = val.signal(out, 'T_cell_max').y;
Tmin = val.signal(out, 'T_cell_min').y;

ok_vmax = max(Vmax) >= 3.99;
ok_vmin = min(Vmin) <= 3.21;
ok_tmax = max(Tmax) >= 39.5;
ok_tmin = min(Tmin) <= 5.5;

r = val.check(r, "spike_reaches_v_max",  ok_vmax, sprintf('max(V_cell_max)=%.3f V', max(Vmax)), max(Vmax), '>=3.99');
r = val.check(r, "dip_reaches_v_min",    ok_vmin, sprintf('min(V_cell_min)=%.3f V', min(Vmin)), min(Vmin), '<=3.21');
r = val.check(r, "hot_spot_reaches_max", ok_tmax, sprintf('max(T_cell_max)=%.2f C', max(Tmax)), max(Tmax), '>=39.5');
r = val.check(r, "cold_spot_reaches_min",ok_tmin, sprintf('min(T_cell_min)=%.2f C', min(Tmin)), min(Tmin), '<=5.5');

time_out = val.signal(out, 'V_cell_max').t;
stim_v = struct('t', t, 'y', [max(V96,[],2), min(V96,[],2)], ...
    'label', 'V_{cell} sweep min/max [V]', 'channels', {{'spike','dip'}});
stim_T = struct('t', t, 'y', [max(T32,[],2), min(T32,[],2)], ...
    'label', 'T_{sensor} sweep min/max [\circC]', 'channels', {{'hot','cold'}});
resp_v = struct('t', time_out, 'y', [Vmax, Vmin], ...
    'label', 'V_{cell,max/min} reported [V]', 'channels', {{'V_max','V_min'}});
resp_T = struct('t', time_out, 'y', [Tmax, Tmin], ...
    'label', 'T_{cell,max/min} reported [\circC]', 'channels', {{'T_max','T_min'}});
phases = {0, phaseSamples_V*dt, 'V high sweep (96 cells)'; ...
          phaseSamples_V*dt, 2*phaseSamples_V*dt, 'V low sweep'; ...
          2*phaseSamples_V*dt, 2*phaseSamples_V*dt + phaseSamples_T*dt, 'T hot sweep (32 sensors)'; ...
          2*phaseSamples_V*dt + phaseSamples_T*dt, t(end), 'T cold sweep'};
asserts = {phaseSamples_V*dt,                                                    ok_vmax, 'spike sees V_max'; ...
           2*phaseSamples_V*dt,                                                  ok_vmin, 'dip sees V_min'; ...
           2*phaseSamples_V*dt + phaseSamples_T*dt,                              ok_tmax, 'hot sees T_max'; ...
           t(end),                                                               ok_tmin, 'cold sees T_min'};
r.signals_plot = string(val.scenario_plot(r, struct( ...
    'plot_dir', val.plot_root('mil','bms'), 'filename', 'BMS-AGG-01.png', ...
    'subtitle', 'master min/max trees: spike + dip per cell, hot + cold per sensor', ...
    'stim', [stim_v stim_T], 'resp', [resp_v resp_T], 'phases', {phases}, 'asserts', {asserts})));
end
