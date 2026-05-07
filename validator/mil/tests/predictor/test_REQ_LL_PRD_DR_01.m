function r = test_REQ_LL_PRD_DR_01()
% REQ-LL-PRD-DR-01  Per-class detection rate (TP / (TP + FN)) on the
% injected-fault test set SHALL be >= req.PRD_DR_min. Sample-level
% aggregation across all (class scenario) x (test trip) runs, mirroring
% ai/fault_prediction/scripts/python/evaluate.py.
r = val.new_result("predictor","PRD-DR-01","Per-class predictor detection rate","REQ-LL-PRD-DR-01");

DR_MIN  = evalin('base', 'req.PRD_DR_min');
score   = val.predictor_score();
classes = {'OT','OV','UV'};

for c = 1:3
    n  = score(c).tp + score(c).fn;
    ok = n > 0 && score(c).recall >= DR_MIN;
    r = val.check(r, sprintf("dr_%s_ge_min", lower(classes{c})), ok, ...
        sprintf('DR(%s) = %.3f (TP=%d FN=%d FP=%d)', classes{c}, ...
                score(c).recall, score(c).tp, score(c).fn, score(c).fp), ...
        score(c).recall, DR_MIN);
    r.metrics.(sprintf('DR_%s', classes{c})) = score(c).recall;
    r.metrics.(sprintf('TP_%s', classes{c})) = score(c).tp;
    r.metrics.(sprintf('FN_%s', classes{c})) = score(c).fn;
    r.metrics.(sprintf('FP_%s', classes{c})) = score(c).fp;
end
end
