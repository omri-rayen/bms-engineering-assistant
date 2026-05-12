function r = test_REQ_LL_BMS_THM_02()
% REQ-LL-BMS-THM-02  Thermal manager hits saturation limits and crosses
% both relay edges. Exercises the heater/chiller saturation blocks and
% relay hysteresis turn-on / turn-off branches.

r = val.new_result("bms","BMS-THM-02","Thermal manager saturation + hysteresis","REQ-LL-BMS-THM-02");

mdl = 'bms_master';
load_system(mdl);
P_h_max = evalin('base', 'P_heater_max');
P_c_max = evalin('base', 'P_chiller_max');

dt = 0.1;
T  = 30;
t  = (0:dt:T)'; N = numel(t);

% Profile: very cold -> band -> very hot -> band -> very cold.
T_prof = zeros(N, 1);
T_prof(t <  6)               = -20;       % heater saturates
T_prof(t >= 6 & t < 12)      =  20;       % both off
T_prof(t >= 12 & t < 18)     =  60;       % chiller saturates
T_prof(t >= 18 & t < 24)     =  20;       % both off (chiller turn-off edge)
T_prof(t >= 24)              = -20;       % heater turn-on edge again

ds  = val.master_inputs(t, ...
        'T_sensors_32', T_prof .* ones(1,32), ...
        'T_coolant',    T_prof);
out = val.sim_model(mdl, ds, T);

P_h = val.signal(out, 'P_heat_cmd').y;
P_c = val.signal(out, 'P_chill_cmd').y;

ok_h_sat  = max(P_h) >= P_h_max - 1;
ok_c_sat  = max(P_c) >= P_c_max - 1;
ok_h_off  = min(P_h(t >= 9 & t < 12)) < 1;
ok_c_off  = min(P_c(t >= 21 & t < 24)) < 1;
ok_h_on2  = max(P_h(t >= 28))         > 1;       % turn-on edge crossed twice

r = val.check(r, "heater_saturates",     ok_h_sat,  sprintf('max P_heat=%.0f W',  max(P_h)), max(P_h), P_h_max);
r = val.check(r, "chiller_saturates",    ok_c_sat,  sprintf('max P_chill=%.0f W', max(P_c)), max(P_c), P_c_max);
r = val.check(r, "heater_off_in_band",   ok_h_off,  '', max(P_h(t >= 9 & t < 12)),  0);
r = val.check(r, "chiller_off_in_band",  ok_c_off,  '', max(P_c(t >= 21 & t < 24)), 0);
r = val.check(r, "heater_turns_on_again",ok_h_on2,  '', max(P_h(t >= 28)),         '>1');

stim = struct('t', t, 'y', T_prof, 'label', 'T_{coolant} [\circC]');
resp = struct('t', t, 'y', [P_h, P_c], ...
    'label', 'P_{heat} (solid) vs P_{chill} (faint) [W]', ...
    'channels', {{'P_heat','P_chill'}}, ...
    'thresholds', {{P_h_max,'P\_heater\_max'; P_c_max,'P\_chiller\_max'}});
phases = {0, 6, 'cold (-20)'; 6, 12, 'band'; 12, 18, 'hot (+60)'; 18, 24, 'band'; 24, T, 'cold again'};
asserts = {6,  ok_h_sat,  'heater sat'; ...
           18, ok_c_sat,  'chiller sat'; ...
           24, ok_c_off,  'chiller off'; ...
           T,  ok_h_on2,  'heater turns on again'};
r.signals_plot = string(val.scenario_plot(r, struct( ...
    'plot_dir', val.plot_root('mil','bms'), 'filename', 'BMS-THM-02.png', ...
    'subtitle', 'thermal saturation + relay hysteresis edges', ...
    'stim', stim, 'resp', resp, 'phases', {phases}, 'asserts', {asserts})));
end
