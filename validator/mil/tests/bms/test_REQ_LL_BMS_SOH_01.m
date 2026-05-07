function r = test_REQ_LL_BMS_SOH_01()
% REQ-LL-BMS-SOH-01  SoH stays in [req.BMS_SOH_min, req.BMS_SOH_max] and is
% non-increasing within a trip (decay tolerance: req.BMS_SOH_decay_tol_step).
r = val.new_result("bms","BMS-SOH-01","SoH bounded and monotonic","REQ-LL-BMS-SOH-01");

mdl = 'bms_master';
load_system(mdl);
req = evalin('base', 'req');

dt = 0.1; T = 60;
t  = (0:dt:T)'; N = numel(t);
I  = 25*ones(N, 1);

ds  = val.master_inputs(t, 'I_pack', I);
out = val.sim_model(mdl, ds, T);
soh = val.signal(out, 'SoH_pack').y;

ok_lo = all(soh >= req.BMS_SOH_min - 1e-6);
ok_hi = all(soh <= req.BMS_SOH_max + 1e-6);
ok_mono = all(diff(soh) <= req.BMS_SOH_decay_tol_step);

r = val.check(r, "soh_in_bounds_low",  ok_lo, sprintf('min=%.4f', min(soh)), min(soh), req.BMS_SOH_min);
r = val.check(r, "soh_in_bounds_high", ok_hi, sprintf('max=%.4f', max(soh)), max(soh), req.BMS_SOH_max);
r = val.check(r, "soh_non_increasing", ok_mono, ...
    sprintf('max(diff(soh)) = %.2e', max(diff(soh))), max(diff(soh)), req.BMS_SOH_decay_tol_step);

r.metrics.SoH_start = soh(1);
r.metrics.SoH_end   = soh(end);
end
