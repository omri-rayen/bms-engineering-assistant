function r = test_REQ_LL_PRD_LT_03()
% REQ-LL-PRD-LT-03  Median per-event alarm_3(UV) lead time vs the BMS
% Nominal->Warn(UV) transition SHALL be >= req.PRD_LT_UV_min_s, aggregated
% across all UV scenarios x test trips.
r = val.new_result("predictor","PRD-LT-03","UV median alarm lead-time vs warn","REQ-LL-PRD-LT-03");
score = val.predictor_score();
r = local_lead_check(r, score(3), evalin('base', 'req.PRD_LT_UV_min_s'));
end


function r = local_lead_check(r, s, lead_min_s)
ok = s.n_events > 0 && s.median_lead_s >= lead_min_s;
if s.n_events == 0
    detail = 'no positive events in test split';
else
    detail = sprintf('median lead = %.2f s over %d events (min req %.1f)', ...
        s.median_lead_s, s.n_events, lead_min_s);
end
r = val.check(r, "median_lead_ge_min", ok, detail, s.median_lead_s, lead_min_s);
r.metrics.median_lead_s = s.median_lead_s;
r.metrics.n_events      = s.n_events;
r.metrics.lead_min_s    = lead_min_s;
end
