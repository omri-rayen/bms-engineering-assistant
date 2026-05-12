function r = test_REQ_LL_BMS_SOC_01()
% REQ-LL-BMS-SOC-01  EKF SoC converges within req.BMS_SOC_err_max_pct by
% req.BMS_SOC_settle_time_s, with req.BMS_SOC_init_offset_pct init offset
% on a constant 30 A discharge.
r = val.new_result("bms","BMS-SOC-01","EKF SoC convergence on constant 30 A","REQ-LL-BMS-SOC-01");

mdl = 'bms_master';
load_system(mdl);
req = evalin('base', 'req');

SoC_true_init = 0.80;
SoC_ekf_init  = SoC_true_init - req.BMS_SOC_init_offset_pct/100;
ekf      = evalin('base', 'ekf_params');
ekf.SoC0 = SoC_ekf_init;
assignin('base', 'ekf_params', ekf);
assignin('base', 'SoC_init', SoC_true_init * 100);

dt = 0.1; T = 2 * req.BMS_SOC_settle_time_s;
t  = (0:dt:T)'; N = numel(t);
I_const = 30;

Q_nom_Ah   = evalin('base', 'Q_nom_Ah');
SoC_bp_ocv = evalin('base', 'SoC_bp_ocv');
T_bp       = evalin('base', 'T_bp');
OCV_data   = evalin('base', 'OCV_data');
R0_data    = evalin('base', 'R0_data');
R1_data    = evalin('base', 'R1_data');
R2_data    = evalin('base', 'R2_data');
C1_data    = evalin('base', 'C1_data');
C2_data    = evalin('base', 'C2_data');
SoC_bp_ecm = evalin('base', 'SoC_bp_ecm');
T_amb      = 25;

SoC_true = 100 * (SoC_true_init - I_const * t / (Q_nom_Ah * 3600));
OCV_cell = interp2(T_bp, SoC_bp_ocv, OCV_data, T_amb*ones(N,1), SoC_true);
R0_cell  = interp2(T_bp, SoC_bp_ecm, R0_data,  T_amb*ones(N,1), SoC_true);
R1_cell  = interp2(T_bp, SoC_bp_ecm, R1_data,  T_amb*ones(N,1), SoC_true);
R2_cell  = interp2(T_bp, SoC_bp_ecm, R2_data,  T_amb*ones(N,1), SoC_true);
C1_cell  = interp2(T_bp, SoC_bp_ecm, C1_data,  T_amb*ones(N,1), SoC_true);
C2_cell  = interp2(T_bp, SoC_bp_ecm, C2_data,  T_amb*ones(N,1), SoC_true);
% Synthesise V_cell with full ECM dynamics so the plant matches the EKF
% process model exactly. Discrete-time first-order RC with the same dt as
% the EKF sample (0.1 s).
VRC1 = zeros(N,1); VRC2 = zeros(N,1);
for k = 2:N
    a1 = exp(-dt / (R1_cell(k) * C1_cell(k)));
    a2 = exp(-dt / (R2_cell(k) * C2_cell(k)));
    VRC1(k) = a1 * VRC1(k-1) + R1_cell(k) * (1 - a1) * I_const;
    VRC2(k) = a2 * VRC2(k-1) + R2_cell(k) * (1 - a2) * I_const;
end
V_cell   = OCV_cell - I_const * R0_cell - VRC1 - VRC2;
V96      = V_cell .* ones(1, 96);

ds  = val.master_inputs(t, 'I_pack', I_const*ones(N,1), 'V_cells_96', V96, ...
        'T_sensors_32', T_amb*ones(N,32), 'T_coolant', T_amb*ones(N,1));
out = val.sim_model(mdl, ds, T);
soc = val.signal(out, 'SoC_pack').y * 100;

i60 = find(t >= req.BMS_SOC_settle_time_s, 1);
err_60 = abs(soc(i60) - SoC_true(i60));
tol = req.BMS_SOC_err_max_pct;
ok = err_60 < tol;
r = val.check(r, "soc_err_under_tol_at_settle", ok, ...
    sprintf('|err(%.0fs)| = %.2f %% (tol %.1f %%)', req.BMS_SOC_settle_time_s, err_60, tol), err_60, tol);

r.metrics.err_at_settle_pct = err_60;
r.metrics.rmse_pct          = sqrt(mean((soc(i60:end) - SoC_true(i60:end)).^2));
r.metrics.bias_pct          = mean(soc(i60:end) - SoC_true(i60:end));

time_out = val.signal(out, 'SoC_pack').t;
stim = struct('t', t, 'y', I_const*ones(size(t)), 'label', 'I_{pack} [A]   (constant 30 A)');
resp = struct('t', time_out, 'y', [soc, SoC_true], 'label', 'SoC [%]   (estimate solid, truth faint)', ...
    'channels', {{'EKF','true'}}, ...
    'thresholds', {{SoC_ekf_init*100,'EKF init'}});
phases = {0, req.BMS_SOC_settle_time_s, 'transient'; req.BMS_SOC_settle_time_s, T, 'settled'};
asserts = {req.BMS_SOC_settle_time_s, ok, sprintf('|err|=%.2f%% < %.1f%%', err_60, tol)};
r.signals_plot = string(val.scenario_plot(r, struct( ...
    'plot_dir', val.plot_root('mil','bms'), 'filename', 'BMS-SOC-01.png', ...
    'subtitle', sprintf('EKF SoC convergence on constant 30 A discharge (init offset = %.1f%%)', req.BMS_SOC_init_offset_pct), ...
    'stim', stim, 'resp', resp, 'phases', {phases}, 'asserts', {asserts})));
end
