function r = test_REQ_LL_PRD_LT_01()
% REQ-LL-PRD-LT-01  Median per-event alarm_3(OT) lead time vs the BMS
% Nominal->Warn(OT) transition SHALL be >= req.PRD_LT_OT_min_s, aggregated
% across all OT scenarios x test trips. Mirrors evaluate.py lead_time_gate.
r = val.new_result("predictor","PRD-LT-01","OT median alarm lead-time vs warn","REQ-LL-PRD-LT-01");
score = val.predictor_score();
lead_min = evalin('base', 'req.PRD_LT_OT_min_s');
r = local_lead_check(r, score(1), lead_min);

% Median lead time per fault class vs requirement.
try
    here    = fileparts(mfilename('fullpath'));
    valRoot = fileparts(fileparts(fileparts(here)));
    plotDir = fullfile(valRoot, 'reports', 'plots', 'mil');
    if ~isfolder(plotDir), mkdir(plotDir); end
    req     = evalin('base', 'req');
    leads   = [score(1).median_lead_s, score(2).median_lead_s, score(3).median_lead_s];
    mins    = [req.PRD_LT_OT_min_s,    req.PRD_LT_OV_min_s,    req.PRD_LT_UV_min_s];
    cls     = {'OT','OV','UV'};
    fig = figure('Visible','off','Position',[100 100 800 400]);
    bar([leads(:), mins(:)]); grid on;
    set(gca, 'XTickLabel', cls);
    ylabel('lead time [s]'); legend({'median','min req'}, 'Location','best');
    title('Predictor median alarm lead time vs requirement (per fault class)');
    exportgraphics(fig, fullfile(plotDir, 'predictor_lead_time.png'), 'Resolution', 120);
    close(fig);
catch ME
    warning('mil:prd:plot', 'plot failed: %s', ME.message);
end
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
