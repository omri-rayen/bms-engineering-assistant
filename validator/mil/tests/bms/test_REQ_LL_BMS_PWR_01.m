function r = test_REQ_LL_BMS_PWR_01()
% REQ-LL-BMS-PWR-01  P_limit_* drop by >=req.BMS_PWR_derate_min_drop at
% Derate, both -> 0 at Shutdown.
r = val.new_result("bms","BMS-PWR-01","Power limiter derate + shutdown","REQ-LL-BMS-PWR-01");

mdl = 'bms_master';
load_system(mdl);
bms = evalin('base', 'bms');
req = evalin('base', 'req');
dt  = 0.1;
T   = (bms.N_debounce_derate + bms.N_debounce_shut + 50)*dt + 5;

t = (0:dt:T)'; N = numel(t);
ff = zeros(N, 8);
t_der_on  = 1.0;
t_shut_on = t_der_on + (bms.N_debounce_derate + 20)*dt + 0.5;
ff(t >= t_der_on  & t < t_shut_on, 1) = 2;
ff(t >= t_shut_on,                 1) = 3;

ds  = val.master_inputs(t, 'fault_flags_8', ff);
out = val.sim_model(mdl, ds, T);

P_chg  = val.signal(out, 'P_limit_chg').y;
P_dchg = val.signal(out, 'P_limit_dchg').y;
shut   = val.signal(out, 'shutdown_cmd').y;
P_nom  = max(P_dchg(1), 1);

i_der = find(t >= t_der_on + bms.N_debounce_derate*dt + dt, 1);
derate_max = (1 - req.BMS_PWR_derate_min_drop) * P_nom;
ok_der = P_dchg(i_der) <= derate_max + 1e-6;
r = val.check(r, "p_dchg_derated", ok_der, ...
    sprintf('P_dchg = %.0f W vs P_nom = %.0f W (drop >= %.0f %%)', ...
        P_dchg(i_der), P_nom, 100*req.BMS_PWR_derate_min_drop), ...
    P_dchg(i_der), derate_max);

i_shut = find(shut > 0.5, 1);
if isempty(i_shut)
    r = val.check(r, "shutdown_asserted", false, "shutdown_cmd never high");
else
    j = min(i_shut + 10, N);
    ok_z = abs(P_chg(j)) < 1e-3 && abs(P_dchg(j)) < 1e-3;
    r = val.check(r, "limits_zero_under_shutdown", ok_z, ...
        sprintf('P=(%.1f, %.1f) W', P_chg(j), P_dchg(j)), max(abs([P_chg(j),P_dchg(j)])), 0);
end

ok_nn = all(P_chg >= -1e-6) && all(P_dchg >= -1e-6);
r = val.check(r, "limits_non_negative", ok_nn, '', min([P_chg;P_dchg]), '>=0');

r.metrics.P_nom_W = P_nom;
end
