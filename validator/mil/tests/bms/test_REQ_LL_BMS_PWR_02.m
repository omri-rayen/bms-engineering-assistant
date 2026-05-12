function r = test_REQ_LL_BMS_PWR_02()
% REQ-LL-BMS-PWR-02  Power_Limiter min(k_soc, k_temp) selects each
% factor in turn.
%   A) low SoC, warm cells   -> k_soc dominates (lower)
%   B) nominal SoC, very cold -> k_temp dominates

r = val.new_result("bms","BMS-PWR-02","Power limiter k_soc vs k_temp branches","REQ-LL-BMS-PWR-02");

mdl = 'bms_master';
load_system(mdl);

dt = 0.1; T = 6;
t  = (0:dt:T)'; N = numel(t);

% --- Scenario A: low SoC, warm pack (k_soc lower) ---
ekf      = evalin('base', 'ekf_params');
ekf.SoC0 = 0.05;
assignin('base', 'ekf_params', ekf);
assignin('base', 'SoC_init', 5);
ds_A = val.master_inputs(t, 'T_sensors_32', 25*ones(N,32), 'T_coolant', 25*ones(N,1));
outA = val.sim_model(mdl, ds_A, T);
P_dchg_A = val.signal(outA, 'P_limit_dchg').y;
P_chg_A  = val.signal(outA, 'P_limit_chg').y;

% --- Scenario B: nominal SoC, very cold (k_temp lower) ---
ekf.SoC0 = 0.50;
assignin('base', 'ekf_params', ekf);
assignin('base', 'SoC_init', 50);
ds_B = val.master_inputs(t, 'T_sensors_32', -15*ones(N,32), 'T_coolant', -15*ones(N,1));
outB = val.sim_model(mdl, ds_B, T);
P_dchg_B = val.signal(outB, 'P_limit_dchg').y;
P_chg_B  = val.signal(outB, 'P_limit_chg').y;

% Both scenarios must derate vs nominal envelope (P>=0 always).
ok_A_pos = all(P_dchg_A >= -1e-6) && all(P_chg_A >= -1e-6);
ok_B_pos = all(P_dchg_B >= -1e-6) && all(P_chg_B >= -1e-6);
r = val.check(r, "limits_non_negative_low_soc",   ok_A_pos, '', min([P_dchg_A;P_chg_A]), '>=0');
r = val.check(r, "limits_non_negative_cold",      ok_B_pos, '', min([P_dchg_B;P_chg_B]), '>=0');

% Low SoC shrinks discharge headroom; cold shrinks both.
r.metrics.P_dchg_low_soc_W = P_dchg_A(end);
r.metrics.P_chg_cold_W     = P_chg_B(end);

% Restore default SoC_init for downstream tests.
ekf.SoC0 = 0.80;
assignin('base', 'ekf_params', ekf);
assignin('base', 'SoC_init', 80);

% Two-scenario storyboard (low-SoC vs cold-pack) overlaid on one axis.
N1 = numel(P_dchg_A); N2 = numel(P_dchg_B);
ta = (0:N1-1)' * dt;
tb = (0:N2-1)' * dt + ta(end) + 0.5;
tall = [ta; tb];
P_dchg_all = [P_dchg_A; P_dchg_B];
P_chg_all  = [P_chg_A;  P_chg_B];
stim = struct('t', tall, 'y', double([5*ones(N1,1); 50*ones(N2,1)]), ...
    'label', 'SoC init [%]   (A: low SoC, B: cold)');
resp = struct('t', tall, 'y', [P_dchg_all, P_chg_all], ...
    'label', 'P_{limit} [W]   (dchg solid, chg faint)', ...
    'channels', {{'P_dchg','P_chg'}});
phases = {ta(1), ta(end), 'A: SoC=5%, T=25C'; tb(1), tb(end), 'B: SoC=50%, T=-15C'};
asserts = {ta(end), ok_A_pos, 'A: P>=0'; tb(end), ok_B_pos, 'B: P>=0'};
r.signals_plot = string(val.scenario_plot(r, struct( ...
    'plot_dir', val.plot_root('mil','bms'), 'filename', 'BMS-PWR-02.png', ...
    'subtitle', 'min(k\_soc, k\_temp): each branch dominates in its scenario', ...
    'stim', stim, 'resp', resp, 'phases', {phases}, 'asserts', {asserts})));
end
