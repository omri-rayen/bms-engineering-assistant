function r = test_REQ_LL_BMS_FSM_01()
% REQ-LL-BMS-FSM-01  Severity ladder Nominal->Warn->Derate->Shut + auto
% recovery Warn->Nominal once flags clear; Shutdown latches.
r = val.new_result("bms","BMS-FSM-01","Severity FSM escalation + recovery + latch","REQ-LL-BMS-FSM-01");

mdl = 'bms_master';
load_system(mdl);
bms = evalin('base', 'bms');
dt  = 0.1;

% Stage 1: warn-only window then clear (recovery test, stay under wdg).
T1  = (bms.N_watchdog_timeout - 10)*dt;
t1  = (0:dt:T1)';
ff1 = zeros(numel(t1), 8);
warn_on  = t1 >= 1 & t1 < 1 + (bms.N_debounce_warn + 5)*dt + 0.5;
ff1(warn_on, 2) = 1;
ds1 = val.master_inputs(t1, 'fault_flags_8', ff1);
out1 = val.sim_model(mdl, ds1, T1);
sev1 = val.signal(out1, 'fault_severity').y;

i_warn  = find(t1 >= 1 + bms.N_debounce_warn*dt + dt, 1);
ok_warn = sev1(i_warn) >= 1 && sev1(i_warn) <= 2;
ok_recover = sev1(end) == 0;
r = val.check(r, "warn_after_debounce",  ok_warn,    sprintf('sev=%g', sev1(i_warn)), [], '[1,2]');
r = val.check(r, "warn_recovers_to_ok",  ok_recover, sprintf('sev_end=%g', sev1(end)), [], 0);

% Stage 2: derate persistence then escalation to shut + latch.
T2  = (bms.N_debounce_warn + bms.N_debounce_derate + bms.N_debounce_shut + 50)*dt + 5;
t2  = (0:dt:T2)';
ff2 = zeros(numel(t2), 8);
ff2(t2 >= 1  & t2 < 1 + (bms.N_debounce_warn   + 5)*dt + 0.5, 1) = 1;
ff2(t2 >= 4  & t2 < 4 + (bms.N_debounce_derate + 5)*dt + 0.5, 1) = 2;
t_shut_on = 4 + (bms.N_debounce_derate + 10)*dt + 1.0;
ff2(t2 >= t_shut_on,   1) = 3;
% Inject a "clear" tail to test latch behaviour
t_clear = t_shut_on + (bms.N_debounce_shut + 20)*dt + 1.0;
ff2(t2 >= t_clear, 1) = 0;

ds2  = val.master_inputs(t2, 'fault_flags_8', ff2);
out2 = val.sim_model(mdl, ds2, T2);
sev2 = val.signal(out2, 'fault_severity').y;

i_der  = find(t2 >= 4 + bms.N_debounce_derate*dt + dt, 1);
i_shut = find(t2 >= t_shut_on + bms.N_debounce_shut*dt + dt, 1);
ok_der  = sev2(i_der)  >= 2;
ok_shut = sev2(i_shut) >= 3;
ok_latch = sev2(end) >= 3;
r = val.check(r, "escalates_to_derate", ok_der,   sprintf('sev=%g', sev2(i_der)),  [], '>=2');
r = val.check(r, "escalates_to_shut",   ok_shut,  sprintf('sev=%g', sev2(i_shut)), [], '>=3');
r = val.check(r, "shut_latches",        ok_latch, sprintf('sev_end=%g after clear', sev2(end)), [], '>=3');

r.metrics.max_severity = max(sev2);
end
