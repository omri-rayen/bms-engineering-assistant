function r = test_REQ_LL_BMS_VMON_01()
% REQ-LL-BMS-VMON-01  OV warn / derate / shut after their debounce windows.
r = val.new_result("bms","BMS-VMON-01","OV monitor debounce ladder","REQ-LL-BMS-VMON-01");

mdl = 'bms_slave';
load_system(mdl);
bms = evalin('base', 'bms');
dt  = 0.1;

% Three back-to-back fault windows on cell #6, each above the next
% threshold, separated by enough samples for the previous flag to relax.
t_warn_on   = 1.0;  t_warn_off   = t_warn_on   + (bms.N_debounce_warn   + 5)*dt + 1.0;
t_derate_on = t_warn_off + 0.5;  t_derate_off = t_derate_on + (bms.N_debounce_derate + 5)*dt + 1.0;
t_shut_on   = t_derate_off + 0.5;  T = t_shut_on + (bms.N_debounce_shut + 5)*dt + 1.0;

t = (0:dt:T)'; N = numel(t);
V12 = repmat(3.70, N, 12);
V12(t >= t_warn_on   & t < t_warn_off,   6) = bms.V_OV_warn   + 0.01;
V12(t >= t_derate_on & t < t_derate_off, 6) = bms.V_OV_derate + 0.01;
V12(t >= t_shut_on,                      6) = bms.V_OV_shut   + 0.01;
T4  = 25*ones(N, 4);
en  = zeros(N, 1);

ds  = val.dataset_from('V_cells_12', t, V12, 'T_sensors_4', t, T4, 'enable_bal', t, en);
out = val.sim_model(mdl, ds, T);
flag = val.signal(out, 'fault_flag').y;

ok_warn   = flag(idx_after(t, t_warn_on,   bms.N_debounce_warn,   dt))  >= 1;
ok_derate = flag(idx_after(t, t_derate_on, bms.N_debounce_derate, dt)) >= 2;
ok_shut   = flag(idx_after(t, t_shut_on,   bms.N_debounce_shut,   dt)) >= 3;

r = val.check(r, "warn_after_debounce",   ok_warn,   sprintf('flag = %g', flag(idx_after(t,t_warn_on,bms.N_debounce_warn,dt))),     [], '>=1');
r = val.check(r, "derate_after_debounce", ok_derate, sprintf('flag = %g', flag(idx_after(t,t_derate_on,bms.N_debounce_derate,dt))), [], '>=2');
r = val.check(r, "shut_after_debounce",   ok_shut,   sprintf('flag = %g', flag(idx_after(t,t_shut_on,bms.N_debounce_shut,dt))),     [], '>=3');

stim = struct('t', t, 'y', V12(:,6), 'label', 'V_{cell,6} [V]', ...
    'thresholds', {{bms.V_OV_warn,'OV warn'; bms.V_OV_derate,'OV derate'; bms.V_OV_shut,'OV shut'}});
resp = struct('t', t, 'y', flag, 'label', 'fault\_flag', ...
    'thresholds', {{1,'warn'; 2,'derate'; 3,'shut'}});
phases = {t_warn_on,   t_warn_off,   'warn injected'; ...
          t_derate_on, t_derate_off, 'derate injected'; ...
          t_shut_on,   T,            'shut injected'};
asserts = {t_warn_on   + bms.N_debounce_warn  *dt + dt, ok_warn,   'flag>=1'; ...
           t_derate_on + bms.N_debounce_derate*dt + dt, ok_derate, 'flag>=2'; ...
           t_shut_on   + bms.N_debounce_shut  *dt + dt, ok_shut,   'flag>=3'};
r.signals_plot = string(val.scenario_plot(r, struct( ...
    'plot_dir', val.plot_root('mil','bms'), 'filename', 'BMS-VMON-01.png', ...
    'subtitle', 'cell-6 OV: warn / derate / shut after debounce', ...
    'stim', stim, 'resp', resp, 'phases', {phases}, 'asserts', {asserts})));
end

function i = idx_after(t, t0, N_db, dt)
i = find(t >= t0 + N_db*dt + dt, 1);
end
