function info = collect(groups, models)
% cov.collect -- Aggregate Simulink Coverage metrics for a list of models.
%
%   groups : cell array of merged cvdata (one per root model), or a
%            single cvdata object
%   models : cellstr of model names to report on
%
%   info.<model>.<metric> = struct(covered, total, coverage_pct, dead_pct)
%   info.<model>.uncovered_blocks = struct array
%       [{path, metric, hit, total}]   -- one entry per (block, metric)
%       pair where the block is partly or fully uncovered. Capped at 50
%       entries per model so the JSON stays readable.
%   metric in {execution, decision, condition, mcdc}

if isa(groups, 'cvdata'), groups = {groups}; end

info = struct();
metrics = {'execution', 'decision', 'condition', 'mcdc'};
for i = 1:numel(models)
    m = models{i};
    info.(m) = struct();
    cv = pick_for_model(groups, m);
    for k = 1:numel(metrics)
        info.(m).(metrics{k}) = one_metric(cv, m, metrics{k});
    end
    info.(m).uncovered_blocks = uncovered_blocks(cv, m);
end
end


function cv = pick_for_model(groups, mdl)
% Return the cvdata that actually contains coverage for `mdl`. If no
% group sees the model, return [] (collect treats it as 0/0 -> trivially
% covered).
cv = [];
for i = 1:numel(groups)
    for probe = {@decisioninfo, @executioninfo}
        try
            v = probe{1}(groups{i}, mdl);
            if numel(v) >= 2 && v(2) > 0
                cv = groups{i};
                return
            end
        catch
        end
    end
end
end


function s = one_metric(cdata, mdl, metric)
covered = 0;
total   = 0;
if ~isempty(cdata)
    try
        switch metric
            case 'execution', vec = executioninfo(cdata, mdl);
            case 'decision',  vec = decisioninfo(cdata, mdl);
            case 'condition', vec = conditioninfo(cdata, mdl);
            case 'mcdc',      vec = mcdcinfo(cdata, mdl);
        end
        if numel(vec) >= 2
            covered = vec(1);
            total   = vec(2);
        end
    catch
    end
end

if total == 0
    pct  = 100;     % nothing of this kind in the model -> trivially covered
    dead = 0;
else
    pct  = 100 * covered / total;
    dead = 100 - pct;
end

s = struct( ...
    'covered',      covered, ...
    'total',        total, ...
    'coverage_pct', pct, ...
    'dead_pct',     dead);
end


function out = uncovered_blocks(cdata, mdl)
% Walk every block in `mdl` and ask Simulink Coverage for its execution /
% decision / condition / mcdc count. Anything that is partly or fully
% uncovered is emitted as one row of the result so the analyzer can name
% the offending block by its full Simulink path.
out = struct('path', {}, 'metric', {}, 'hit', {}, 'total', {}, ...
             'parent', {}, 'block_type', {});
if isempty(cdata) || ~bdIsLoaded(mdl), return, end

try
    blks = find_system(mdl, 'LookUnderMasks', 'all', 'FollowLinks', 'on', ...
                            'MatchFilter',    @Simulink.match.allVariants);
catch
    return
end
blks = blks(~strcmp(blks, mdl));

probes = { ...
    'execution', @executioninfo; ...
    'decision',  @decisioninfo;  ...
    'condition', @conditioninfo; ...
    'mcdc',      @mcdcinfo};

cap = 50;
for i = 1:numel(blks)
    if numel(out) >= cap, break, end
    h = blks(i);
    p = '';
    try, p = getfullname(h); catch, end %#ok<CTCH>
    if isempty(p), continue, end
    par = '';
    bt  = '';
    try, par = get_param(h, 'Parent');    catch, end %#ok<CTCH>
    try, bt  = get_param(h, 'BlockType'); catch, end %#ok<CTCH>
    for k = 1:size(probes, 1)
        try
            v = probes{k, 2}(cdata, p);
        catch
            continue
        end
        if numel(v) < 2 || v(2) == 0, continue, end
        if v(1) >= v(2), continue, end       % fully covered for this metric
        out(end+1) = struct( ...
            'path',       string(p), ...
            'metric',     string(probes{k, 1}), ...
            'hit',        double(v(1)), ...
            'total',      double(v(2)), ...
            'parent',     string(par), ...
            'block_type', string(bt)); %#ok<AGROW>
        if numel(out) >= cap, break, end
    end
end
end
