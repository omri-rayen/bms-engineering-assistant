function r = test_REQ_LL_BMS_IMON_01()
% REQ-LL-BMS-IMON-01  OC charge warn / derate / shut after debounce.
% Charge convention: I_pack < 0 means charging.
r = val.new_result("bms","BMS-IMON-01","OC charge debounce ladder","REQ-LL-BMS-IMON-01");

mdl = 'bms_master';
load_system(mdl);
bms = evalin('base', 'bms');
dt  = 0.1;

t_warn_on   = 1.0;  t_warn_off   = t_warn_on   + (bms.N_debounce_warn   + 5)*dt + 1.0;
t_derate_on = t_warn_off + 0.5;  t_derate_off = t_derate_on + (bms.N_debounce_derate + 5)*dt + 1.0;
t_shut_on   = t_derate_off + 0.5;  T = t_shut_on + (bms.N_debounce_shut + 5)*dt + 1.0;

t = (0:dt:T)'; N = numel(t);
I = zeros(N, 1);
I(t >= t_warn_on   & t < t_warn_off)   = -(bms.I_OC_chg_warn   + 5);
I(t >= t_derate_on & t < t_derate_off) = -(bms.I_OC_chg_derate + 5);
I(t >= t_shut_on)                      = -(bms.I_OC_chg_shut   + 5);

ds  = val.master_inputs(t, 'I_pack', I);
out = val.sim_model(mdl, ds, T);
sev = val.signal(out, 'fault_severity').y;

ok_warn   = sev(idx_after(t, t_warn_on,   bms.N_debounce_warn,   dt))  >= 1;
ok_derate = sev(idx_after(t, t_derate_on, bms.N_debounce_derate, dt)) >= 2;
ok_shut   = sev(idx_after(t, t_shut_on,   bms.N_debounce_shut,   dt)) >= 3;

r = val.check(r, "warn_after_debounce",   ok_warn,   '', [], '>=1');
r = val.check(r, "derate_after_debounce", ok_derate, '', [], '>=2');
r = val.check(r, "shut_after_debounce",   ok_shut,   '', [], '>=3');
end

function i = idx_after(t, t0, N_db, dt)
i = find(t >= t0 + N_db*dt + dt, 1);
end
