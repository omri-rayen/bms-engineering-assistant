function r = test_REQ_LL_BMS_WDG_02()
% REQ-LL-BMS-WDG-02  Slave watchdog severity ladder: number of frozen
% slave channels selects watchdog severity (0 / Warn / Derate or Shut).
% Drives bms_master with three sustained scenarios, each long enough for
% the watchdog timeout, and increasing the count of frozen channels.

r = val.new_result("bms","BMS-WDG-02","Watchdog severity vs disconnected count","REQ-LL-BMS-WDG-02");

mdl = 'bms_master';
load_system(mdl);
bms = evalin('base', 'bms');
dt  = 0.1;

phase = (bms.N_watchdog_timeout + 50) * dt;       % per scenario length
T     = 4 * phase + 1;
t     = (0:dt:T)';
N     = numel(t);
ff    = zeros(N, 8);

% Phase 1: 1 slave frozen (count < N_slave_disconnect_warn=2)
m1 = t <  phase;                                          ff(m1, 1) = 1;
% Phase 2: 2 slaves frozen (Warn)
m2 = t >= phase     & t < 2*phase;                        ff(m2, 1:2) = 1;
% Phase 3: 3 slaves frozen (between warn=2 and derate=4)
m3 = t >= 2*phase   & t < 3*phase;                        ff(m3, 1:3) = 1;
% Phase 4: 5 slaves frozen (>= shut threshold)
m4 = t >= 3*phase;                                        ff(m4, 1:5) = 1;

ds  = val.master_inputs(t, 'fault_flags_8', ff);
out = val.sim_model(mdl, ds, T);
sev = val.signal(out, 'fault_severity').y;

% Check after each watchdog timeout window inside its phase.
i1 = find(t >= bms.N_watchdog_timeout*dt + 1,            1);
i2 = find(t >= phase     + bms.N_watchdog_timeout*dt + 1, 1);
i3 = find(t >= 2*phase   + bms.N_watchdog_timeout*dt + 1, 1);
i4 = find(t >= 3*phase   + bms.N_watchdog_timeout*dt + 1, 1);

s1 = sev(i1);
s2 = sev(i2);
s3 = sev(i3);
s4 = sev(i4);

ok1 = s1 >= 1;                  % even 1 frozen channel raises a warn (slave-flag>0)
ok2 = s2 >= 1;
ok3 = s3 >= 1;                  % 3 frozen between warn and derate count
ok4 = s4 >= 2;                  % 5 frozen >= derate count

r = val.check(r, "phase1_warn",       ok1, sprintf('sev=%g', s1), s1, '>=1');
r = val.check(r, "phase2_warn",       ok2, sprintf('sev=%g', s2), s2, '>=1');
r = val.check(r, "phase3_mid",        ok3, sprintf('sev=%g', s3), s3, '>=1');
r = val.check(r, "phase4_derate_up",  ok4, sprintf('sev=%g', s4), s4, '>=2');

% Per-step count of frozen channels (sum across the 8 columns).
frozen_count = sum(double(ff > 0), 2);
stim = struct('t', t, 'y', frozen_count, 'label', '# frozen slave channels');
resp = struct('t', t, 'y', sev, 'label', 'fault\_severity', ...
    'thresholds', {{1,'warn'; 2,'derate'}});
phases = {0,         phase,    '1 frozen'; ...
          phase,     2*phase,  '2 frozen (warn)'; ...
          2*phase,   3*phase,  '3 frozen (mid)'; ...
          3*phase,   T,        '5 frozen (>=derate)'};
asserts = {t(i1), ok1, 'sev>=1'; ...
           t(i2), ok2, 'sev>=1'; ...
           t(i3), ok3, 'sev>=1'; ...
           t(i4), ok4, 'sev>=2'};
r.signals_plot = string(val.scenario_plot(r, struct( ...
    'plot_dir', val.plot_root('mil','bms'), 'filename', 'BMS-WDG-02.png', ...
    'subtitle', 'watchdog severity ladder vs # of disconnected slaves', ...
    'stim', stim, 'resp', resp, 'phases', {phases}, 'asserts', {asserts})));
end
