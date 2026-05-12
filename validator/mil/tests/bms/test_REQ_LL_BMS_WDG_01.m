function r = test_REQ_LL_BMS_WDG_01()
% REQ-LL-BMS-WDG-01  Watchdog escalates severity to >=Warn when any
% slave fault_flag stream is frozen for >= bms.N_watchdog_timeout steps.
r = val.new_result("bms","BMS-WDG-01","Slave watchdog detects frozen flag","REQ-LL-BMS-WDG-01");

mdl = 'bms_master';
load_system(mdl);
bms = evalin('base', 'bms');

dt = 0.1;
T  = max(20, (bms.N_watchdog_timeout + 50)*dt);
t  = (0:dt:T)'; N = numel(t);
ff = zeros(N, 8);
ff(:, 1) = 1;   % stuck non-zero on slave 1

ds  = val.master_inputs(t, 'fault_flags_8', ff);
out = val.sim_model(mdl, ds, T);
sev = val.signal(out, 'fault_severity').y;

i_wd = find(t >= bms.N_watchdog_timeout*dt + 1, 1);
ok = max(sev(i_wd:end)) >= 1;
r = val.check(r, "watchdog_escalates_severity", ok, ...
    sprintf('max(sev) after t=%.1fs = %g', t(i_wd), max(sev(i_wd:end))), ...
    max(sev(i_wd:end)), '>=1');

stim = struct('t', t, 'y', double(ff(:,1)), 'label', 'fault\_flags\_8(slave1) (stuck=1)');
resp = struct('t', t, 'y', sev, 'label', 'fault\_severity', ...
    'thresholds', {{1,'warn'}});
phases = {0, bms.N_watchdog_timeout*dt, 'pre-timeout'; bms.N_watchdog_timeout*dt, T, 'timeout exceeded'};
asserts = {bms.N_watchdog_timeout*dt + dt, ok, 'watchdog escalates >=warn'};
r.signals_plot = string(val.scenario_plot(r, struct( ...
    'plot_dir', val.plot_root('mil','bms'), 'filename', 'BMS-WDG-01.png', ...
    'subtitle', 'frozen slave-flag stream -> watchdog raises severity after N_{wdg} steps', ...
    'stim', stim, 'resp', resp, 'phases', {phases}, 'asserts', {asserts})));
end
