function r = test_REQ_LL_BMS_SOH_02()
% REQ-LL-BMS-SOH-02  Sustained discharge accumulates a >=10 % SoC swing
% so the SoH coulomb-counting branch updates SoH_cap_est once. Also
% covers the high-current EMA R0 branch.

r = val.new_result("bms","BMS-SOH-02","SoH dSoC>10% update branch","REQ-LL-BMS-SOH-02");

mdl = 'bms_master';
load_system(mdl);

% Start near full so a sustained discharge spans the dSoC threshold.
ekf      = evalin('base', 'ekf_params');
ekf.SoC0 = 0.95;
assignin('base', 'ekf_params', ekf);
assignin('base', 'SoC_init', 95);

dt = 0.1; T = 600;                          % 10 min
t  = (0:dt:T)'; N = numel(t);
I  = 100 * ones(N, 1);                      % steady discharge -> ~16 % swing

ds  = val.master_inputs(t, 'I_pack', I);
out = val.sim_model(mdl, ds, T);
soc = val.signal(out, 'SoC_pack').y;
soh = val.signal(out, 'SoH_pack').y;

dSoC_pct = (soc(1) - min(soc)) * 100;
ok_swing = dSoC_pct >= 10.5;
r = val.check(r, "soc_swing_above_threshold", ok_swing, ...
    sprintf('dSoC = %.2f %%', dSoC_pct), dSoC_pct, '>=10.5');

ok_bounded = all(soh >= 0 & soh <= 1.0001);
r = val.check(r, "soh_in_unit_interval", ok_bounded, ...
    sprintf('range=[%.3f, %.3f]', min(soh), max(soh)), 1, 1);

r.metrics.dSoC_pct = dSoC_pct;
r.metrics.SoH_end  = soh(end);

time_out = val.signal(out, 'SoC_pack').t;
stim = struct('t', t, 'y', I, 'label', 'I_{pack} [A]   (sustained discharge)');
resp_soc = struct('t', time_out, 'y', soc * 100, 'label', 'SoC [%]');
resp_soh = struct('t', time_out, 'y', soh,       'label', 'SoH', ...
    'thresholds', {{1,'1.0'; 0,'0'}});
asserts = {time_out(end), ok_swing,    sprintf('dSoC=%.1f%% (>=10.5)', dSoC_pct); ...
           time_out(end), ok_bounded,  'SoH in [0,1]'};
r.signals_plot = string(val.scenario_plot(r, struct( ...
    'plot_dir', val.plot_root('mil','bms'), 'filename', 'BMS-SOH-02.png', ...
    'subtitle', 'sustained 100 A discharge -> SoC swing > 10% -> SoH coulomb-counting branch', ...
    'stim', stim, 'resp', {{resp_soc, resp_soh}}, 'asserts', {asserts})));
end
