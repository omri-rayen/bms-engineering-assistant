function r = test_REQ_LL_BMS_IMON_02()
% REQ-LL-BMS-IMON-02  OC discharge warn / derate / shut after debounce.
r = val.new_result("bms","BMS-IMON-02","OC discharge debounce ladder","REQ-LL-BMS-IMON-02");

mdl = 'bms_master';
load_system(mdl);
bms = evalin('base', 'bms');
dt  = 0.1;

t_warn_on   = 1.0;  t_warn_off   = t_warn_on   + (bms.N_debounce_warn   + 5)*dt + 1.0;
t_derate_on = t_warn_off + 0.5;  t_derate_off = t_derate_on + (bms.N_debounce_derate + 5)*dt + 1.0;
t_shut_on   = t_derate_off + 0.5;  T = t_shut_on + (bms.N_debounce_shut + 5)*dt + 1.0;

t = (0:dt:T)'; N = numel(t);
I = zeros(N, 1);
I(t >= t_warn_on   & t < t_warn_off)   = bms.I_OC_dchg_warn   + 5;
I(t >= t_derate_on & t < t_derate_off) = bms.I_OC_dchg_derate + 5;
I(t >= t_shut_on)                      = bms.I_OC_dchg_shut   + 5;

ds  = val.master_inputs(t, 'I_pack', I);
out = val.sim_model(mdl, ds, T);
sev = val.signal(out, 'fault_severity').y;

ok_warn   = sev(idx_after(t, t_warn_on,   bms.N_debounce_warn,   dt))  >= 1;
ok_derate = sev(idx_after(t, t_derate_on, bms.N_debounce_derate, dt)) >= 2;
ok_shut   = sev(idx_after(t, t_shut_on,   bms.N_debounce_shut,   dt)) >= 3;

r = val.check(r, "warn_after_debounce",   ok_warn,   '', [], '>=1');
r = val.check(r, "derate_after_debounce", ok_derate, '', [], '>=2');
r = val.check(r, "shut_after_debounce",   ok_shut,   '', [], '>=3');

stim = struct('t', t, 'y', I, 'label', 'I_{pack} [A]   (discharge > 0)', ...
    'thresholds', {{bms.I_OC_dchg_warn,'warn'; bms.I_OC_dchg_derate,'derate'; bms.I_OC_dchg_shut,'shut'}});
resp = struct('t', t, 'y', sev, 'label', 'fault\_severity', ...
    'thresholds', {{1,'warn'; 2,'derate'; 3,'shut'}});
phases = {t_warn_on,   t_warn_off,   'I>warn'; ...
          t_derate_on, t_derate_off, 'I>derate'; ...
          t_shut_on,   T,            'I>shut'};
asserts = {t_warn_on   + bms.N_debounce_warn  *dt + dt, ok_warn,   'sev>=1'; ...
           t_derate_on + bms.N_debounce_derate*dt + dt, ok_derate, 'sev>=2'; ...
           t_shut_on   + bms.N_debounce_shut  *dt + dt, ok_shut,   'sev>=3'};
r.signals_plot = string(val.scenario_plot(r, struct( ...
    'plot_dir', val.plot_root('mil','bms'), 'filename', 'BMS-IMON-02.png', ...
    'subtitle', 'OC discharge: warn / derate / shut after debounce', ...
    'stim', stim, 'resp', resp, 'phases', {phases}, 'asserts', {asserts})));
end

function i = idx_after(t, t0, N_db, dt)
i = find(t >= t0 + N_db*dt + dt, 1);
end
