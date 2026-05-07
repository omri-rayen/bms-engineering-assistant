function r = test_REQ_LL_BMS_THM_01()
% REQ-LL-BMS-THM-01  Heater on cold, chiller on hot, both off in band,
% heater and chiller never both active.
r = val.new_result("bms","BMS-THM-01","Thermal manager heater + chiller","REQ-LL-BMS-THM-01");

mdl = 'bms_master';
load_system(mdl);

dt = 0.1; T = 8;
t  = (0:dt:T)'; N = numel(t);

% Cold case
ds_cold = val.master_inputs(t, 'T_sensors_32', 2*ones(N,32), 'T_coolant', 2*ones(N,1));
out = val.sim_model(mdl, ds_cold, T);
P_h = val.signal(out, 'P_heat_cmd').y;
P_c = val.signal(out, 'P_chill_cmd').y;
ok1 = max(P_h(end-10:end)) > 0;
r = val.check(r, "heater_on_when_cold", ok1, ...
    sprintf('max P_heat tail = %.0f W', max(P_h(end-10:end))), max(P_h(end-10:end)), '>0');
ok1b = all(P_c < 1);
r = val.check(r, "chiller_off_when_cold", ok1b, '', max(P_c), 0);

% Hot case
ds_hot = val.master_inputs(t, 'T_sensors_32', 40*ones(N,32), 'T_coolant', 40*ones(N,1));
out2 = val.sim_model(mdl, ds_hot, T);
P_h2 = val.signal(out2, 'P_heat_cmd').y;
P_c2 = val.signal(out2, 'P_chill_cmd').y;
ok2 = max(P_c2(end-10:end)) > 0;
r = val.check(r, "chiller_on_when_hot", ok2, '', max(P_c2(end-10:end)), '>0');
ok2b = all(P_h2 < 1);
r = val.check(r, "heater_off_when_hot", ok2b, '', max(P_h2), 0);

% Mid-band
ds_mid = val.master_inputs(t, 'T_sensors_32', 22*ones(N,32), 'T_coolant', 22*ones(N,1));
out3 = val.sim_model(mdl, ds_mid, T);
ph3 = val.signal(out3, 'P_heat_cmd').y;
pc3 = val.signal(out3, 'P_chill_cmd').y;
ok3 = max(ph3(end-10:end)) < 1 && max(pc3(end-10:end)) < 1;
r = val.check(r, "both_off_in_band", ok3, '', max([ph3(end-10:end); pc3(end-10:end)]), 0);

% Mutual exclusion across all three runs
mut = max([P_h .* P_c; P_h2 .* P_c2; ph3 .* pc3]);
r = val.check(r, "heater_chiller_mutually_exclusive", mut < 1, ...
    sprintf('max(P_heat * P_chill) = %.2f', mut), mut, 0);
end
