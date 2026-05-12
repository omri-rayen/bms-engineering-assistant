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

% Concatenate the three sub-runs into one storyboard.
N1 = numel(P_h); N2 = numel(P_h2); N3 = numel(ph3);
ta = (0:N1-1)' * dt;
tb = ta(end) + 0.5 + (0:N2-1)' * dt;
tc = tb(end) + 0.5 + (0:N3-1)' * dt;
tall = [ta; tb; tc];
T_amb_all = [2*ones(N1,1); 40*ones(N2,1); 22*ones(N3,1)];
P_h_all = [P_h; P_h2; ph3];
P_c_all = [P_c; P_c2; pc3];
stim = struct('t', tall, 'y', T_amb_all, 'label', 'T_{coolant} [\circC]   (cold / hot / band)');
resp = struct('t', tall, 'y', [P_h_all, P_c_all], ...
    'label', 'P_{heat} (solid)  vs  P_{chill} (faint) [W]', ...
    'channels', {{'P_heat','P_chill'}});
phases = {ta(1), ta(end), 'cold (2 \circC)'; ...
          tb(1), tb(end), 'hot (40 \circC)'; ...
          tc(1), tc(end), 'band (22 \circC)'};
asserts = {ta(end), ok1 && ok1b, 'heat on, chill off'; ...
           tb(end), ok2 && ok2b, 'chill on, heat off'; ...
           tc(end), ok3,         'both off'; ...
           tc(end), mut < 1,     'mutually exclusive'};
r.signals_plot = string(val.scenario_plot(r, struct( ...
    'plot_dir', val.plot_root('mil','bms'), 'filename', 'BMS-THM-01.png', ...
    'subtitle', 'thermal manager: heater on cold, chiller on hot, both off in band', ...
    'stim', stim, 'resp', resp, 'phases', {phases}, 'asserts', {asserts})));
end
