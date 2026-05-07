function r = test_REQ_LL_PRD_FAR_01()
% REQ-LL-PRD-FAR-01  On nominal trips, fraction of trip duration during
% which any alarm_3(c) is asserted SHALL be <= req.PRD_FAR_max.
r = val.new_result("predictor","PRD-FAR-01","Predictor false-alarm rate on nominal trips","REQ-LL-PRD-FAR-01");

mdl = 'system_model';
load_system(mdl);
FAR_MAX = evalin('base', 'req.PRD_FAR_max');

trips = evalin('base', 'trips_meas');
scens = define_injection_scenarios();
nom = scens(strcmp({scens.fault}, 'nominal'));
nom = nom(1);

% Evaluate only on the held-out test trips (matches evaluate.py).
fn_trips = intersect(fieldnames(trips), val.test_trip_ids(), 'stable');
total_samples = 0;
total_alarms  = 0;
trip_count = 0;

for i = 1:numel(fn_trips)
    tr = fp.make_trip(trips, fn_trips{i});
    if ~nom.filter(tr) || tr.duration_s < 600, continue, end

    snap = val.snapshot_ws();
    try
        fp.set_baseline(tr);
        apply_injection(nom);
        t = tr.time_s;
        ds  = val.dataset_from('I_pack', t, tr.I_A, 'T_amb', t, tr.T_amb_C);
        out = val.sim_model(mdl, ds, t(end));
        A   = val.signal(out, 'alarm_3').y;
        any_alarm = any(A > 0.5, 2);
        total_samples = total_samples + numel(any_alarm);
        total_alarms  = total_alarms  + nnz(any_alarm);
        trip_count = trip_count + 1;
    catch ME
        warning('PRD-FAR-01:simFail', '%s: %s', fn_trips{i}, ME.message);
    end
    val.restore_ws(snap);
end

if total_samples == 0
    r = val.check(r, "nominal_trips_available", false, "no nominal trip simulated");
    return
end

far = total_alarms / total_samples;
ok = far <= FAR_MAX;
r = val.check(r, "false_alarm_rate_under_threshold", ok, ...
    sprintf('FAR = %.4f over %d trips (%d / %d samples)', far, trip_count, total_alarms, total_samples), ...
    far, FAR_MAX);
r.metrics.FAR        = far;
r.metrics.alarm_n    = total_alarms;
r.metrics.sample_n   = total_samples;
r.metrics.trip_count = trip_count;
end
