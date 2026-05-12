function r = test_REQ_LL_PRD_LT_02()
% REQ-LL-PRD-LT-02  Median per-event alarm_3(OV) lead time vs the BMS
% Nominal->Warn(OV) transition SHALL be >= req.PRD_LT_OV_min_s, aggregated
% across all OV scenarios x test trips.
r = val.new_result("predictor","PRD-LT-02","OV median alarm lead-time vs warn","REQ-LL-PRD-LT-02");
score = val.predictor_score();
r = local_lead_check(r, score(2), evalin('base', 'req.PRD_LT_OV_min_s'));
r.signals_plot = string(val.predictor_summary_plot('PRD-LT-02', score, r));
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
