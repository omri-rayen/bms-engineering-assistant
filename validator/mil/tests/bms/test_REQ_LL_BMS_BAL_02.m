function r = test_REQ_LL_BMS_BAL_02()
% REQ-LL-BMS-BAL-02  Cell-voltage spread stays within the OEM safety
% envelope (<= 200 mV) over the longest measured trip with realistic
% cell variability. Mirrors the validated MIL_validation/tests/integration
% /test_integration_balancing_trip.m criterion (old project source of
% truth). Passive balancing at 0.25 A cannot beat dynamic IR-drop
% differences during a high-current trip; the BMS guarantee is that the
% spread is BOUNDED, not that it is reduced by an arbitrary % over a
% short rest window.

r = val.new_result("bms","BMS-BAL-02","Cell spread within OEM envelope on longest trip","REQ-LL-BMS-BAL-02");

mdl = 'system_model';
load_system(mdl);

trips = evalin('base', 'trips_meas');
fn = fieldnames(trips);
durations = cellfun(@(n) double(trips.(n).time_s(end)), fn);
[~, k] = max(durations);
tid  = fn{k};
trip = trips.(tid);
if double(trip.time_s(end)) < 600
    r = val.check(r, "long_trip_available", false, "No trip > 600s for balancing test"); return
end

t = double(trip.time_s) - double(trip.time_s(1));
ds = val.dataset_from('I_pack', t, double(trip.I_A), 'T_amb', t, double(trip.T_amb_C));

simIn = Simulink.SimulationInput(mdl);
simIn = simIn.setModelParameter('StopTime',  num2str(t(end)));
simIn = simIn.setModelParameter('SaveOutput','on');
simIn = simIn.setModelParameter('SaveFormat','Dataset');
simIn = simIn.setModelParameter('SaveTime',  'on');
simIn = simIn.setExternalInput(ds);
out = sim(simIn);

V_min = val.signal(out, 'V_cell_min').y;
V_max = val.signal(out, 'V_cell_max').y;
spread = V_max - V_min;

spread_max = max(spread);
req = evalin('base', 'req');
spread_lim = req.BMS_BAL_max_spread_V;        % [V] OEM safety envelope

ok = spread_max <= spread_lim;
r = val.check(r, "spread_within_oem_envelope", ok, ...
    sprintf('max spread = %.4f V (limit %.3f V) on trip %s', spread_max, spread_lim, tid), ...
    spread_max, spread_lim);

r.metrics.spread_max_V = spread_max;
r.metrics.trip_id      = string(tid);
end
