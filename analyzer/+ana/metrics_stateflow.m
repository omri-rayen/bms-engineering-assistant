function s = metrics_stateflow(mdl)
% ana.metrics_stateflow -- Stateflow chart counts (defensive, optional).
%
%   s.chart_count, s.state_count, s.transition_count, s.junction_count
%   s.charts : struct array, one entry per chart, with the same per-chart
%              metrics plus 'name' and the full Simulink block 'path'
%              (so rules can locate a heavy chart inside the model).

s = struct('chart_count', 0, 'state_count', 0, ...
           'transition_count', 0, 'junction_count', 0, ...
           'charts', struct('name', {}, 'path', {}, 'states', {}, ...
                            'transitions', {}, 'junctions', {}));

if exist('sfroot', 'file') ~= 2
    return;     % Stateflow not installed -- nothing to do
end

try
    rt     = sfroot();
    mObj   = rt.find('-isa', 'Simulink.BlockDiagram', '-and', 'Name', mdl);
    if isempty(mObj), return; end
    charts = mObj.find('-isa', 'Stateflow.Chart');
catch
    return;
end

s.chart_count = numel(charts);
for i = 1:numel(charts)
    c = charts(i);
    nStates = numel(c.find('-isa', 'Stateflow.State'));
    nTrans  = numel(c.find('-isa', 'Stateflow.Transition'));
    nJunc   = numel(c.find('-isa', 'Stateflow.Junction'));

    chartPath = "";
    try
        chartPath = string(c.Path) + "/" + string(c.Name);
    catch
    end

    s.charts(end+1) = struct( ...
        'name',        string(c.Name), ...
        'path',        chartPath, ...
        'states',      nStates, ...
        'transitions', nTrans, ...
        'junctions',   nJunc); %#ok<AGROW>
    s.state_count      = s.state_count      + nStates;
    s.transition_count = s.transition_count + nTrans;
    s.junction_count   = s.junction_count   + nJunc;
end
end
