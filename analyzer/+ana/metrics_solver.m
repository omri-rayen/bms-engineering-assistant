function s = metrics_solver(mdl)
% ana.metrics_solver -- Solver and sample-time fingerprint.

s = struct();
fields = {'SolverType', 'Solver', 'FixedStep', 'StartTime', 'StopTime'};
for k = 1:numel(fields)
    try
        s.(lower(fields{k})) = string(get_param(mdl, fields{k}));
    catch
        s.(lower(fields{k})) = "";
    end
end

% Fundamental sample time + count of distinct discrete rates.
try
    info = Simulink.BlockDiagram.getSampleTimes(mdl);
    rates = unique(round([info.Value], 12));
    rates = rates(isfinite(rates) & rates > 0);
    s.sample_times      = rates(:)';
    s.distinct_rates    = numel(rates);
    if ~isempty(rates)
        s.fundamental_step = min(rates);
    else
        s.fundamental_step = NaN;
    end
catch
    s.sample_times      = [];
    s.distinct_rates    = 0;
    s.fundamental_step  = NaN;
end
end
