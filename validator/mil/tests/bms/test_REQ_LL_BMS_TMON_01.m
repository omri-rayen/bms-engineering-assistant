function r = test_REQ_LL_BMS_TMON_01()
% REQ-LL-BMS-TMON-01  OT warn / derate / shut after their debounce windows.
r = val.new_result("bms","BMS-TMON-01","OT monitor debounce ladder","REQ-LL-BMS-TMON-01");

mdl = 'bms_slave';
load_system(mdl);
bms = evalin('base', 'bms');
dt  = 0.1;

t_warn_on   = 1.0;  t_warn_off   = t_warn_on   + (bms.N_debounce_warn   + 5)*dt + 1.0;
t_derate_on = t_warn_off + 0.5;  t_derate_off = t_derate_on + (bms.N_debounce_derate + 5)*dt + 1.0;
t_shut_on   = t_derate_off + 0.5;  T = t_shut_on + (bms.N_debounce_shut + 5)*dt + 1.0;

t = (0:dt:T)'; N = numel(t);
V12 = repmat(3.70, N, 12);
T4  = repmat(25,   N, 4);
T4(t >= t_warn_on   & t < t_warn_off,   2) = bms.T_OT_warn   + 1;
T4(t >= t_derate_on & t < t_derate_off, 2) = bms.T_OT_derate + 1;
T4(t >= t_shut_on,                      2) = bms.T_OT_shut   + 1;
en  = zeros(N, 1);

ds  = val.dataset_from('V_cells_12', t, V12, 'T_sensors_4', t, T4, 'enable_bal', t, en);
out = val.sim_model(mdl, ds, T);
flag = val.signal(out, 'fault_flag').y;

ok_warn   = flag(idx_after(t, t_warn_on,   bms.N_debounce_warn,   dt))  >= 1;
ok_derate = flag(idx_after(t, t_derate_on, bms.N_debounce_derate, dt)) >= 2;
ok_shut   = flag(idx_after(t, t_shut_on,   bms.N_debounce_shut,   dt)) >= 3;

r = val.check(r, "warn_after_debounce",   ok_warn,   '', [], '>=1');
r = val.check(r, "derate_after_debounce", ok_derate, '', [], '>=2');
r = val.check(r, "shut_after_debounce",   ok_shut,   '', [], '>=3');

stim = struct('t', t, 'y', T4(:,2), 'label', 'T_{sensor,2} [\circC]', ...
    'thresholds', {{bms.T_OT_warn,'OT warn'; bms.T_OT_derate,'OT derate'; bms.T_OT_shut,'OT shut'}});
resp = struct('t', t, 'y', flag, 'label', 'fault\_flag', ...
    'thresholds', {{1,'warn'; 2,'derate'; 3,'shut'}});
phases = {t_warn_on,   t_warn_off,   'warn injected'; ...
          t_derate_on, t_derate_off, 'derate injected'; ...
          t_shut_on,   T,            'shut injected'};
asserts = {t_warn_on   + bms.N_debounce_warn  *dt + dt, ok_warn,   'flag>=1'; ...
           t_derate_on + bms.N_debounce_derate*dt + dt, ok_derate, 'flag>=2'; ...
           t_shut_on   + bms.N_debounce_shut  *dt + dt, ok_shut,   'flag>=3'};
r.signals_plot = string(val.scenario_plot(r, struct( ...
    'plot_dir', val.plot_root('mil','bms'), 'filename', 'BMS-TMON-01.png', ...
    'subtitle', 'sensor-2 OT: warn / derate / shut after debounce', ...
    'stim', stim, 'resp', resp, 'phases', {phases}, 'asserts', {asserts})));
end

function i = idx_after(t, t0, N_db, dt)
i = find(t >= t0 + N_db*dt + dt, 1);
end
