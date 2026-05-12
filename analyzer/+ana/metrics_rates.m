function s = metrics_rates(mdl)
% ana.metrics_rates -- per-block sample times + rate-transition placement.
%
% Returns:
%   distinct_rates     -- # of distinct sample times across all blocks
%                          (excluding inherited -1 / constant inf).
%   sample_time_set    -- the actual sorted list (string form, for JSON).
%   rate_transition_blocks -- # of explicit RateTransition blocks present.
%   missing_rate_transitions [{path, src_ts, dst_ts}]
%       Lines where source and destination run at different rates but no
%       RateTransition is on the line. ISO 26262-6 §7.4.2 (consistency of
%       interfaces). Capped at 20.

s = struct();
s.distinct_rates             = 0;
s.sample_time_set            = string([]);
s.rate_transition_blocks     = 0;
s.missing_rate_transitions   = struct('path', {}, 'src_ts', {}, 'dst_ts', {});

% --- collect explicit Rate Transitions
try
    rts = find_system(mdl, 'LookUnderMasks', 'all', 'FollowLinks', 'on', ...
                            'BlockType', 'RateTransition');
    s.rate_transition_blocks = numel(rts);
catch
end

% --- compile model to read sample times (cleanup guaranteed)
ci = []; %#ok<NASGU>
sts = struct('blk', {}, 'ts', {});
needTerm = false;
try
    feval(mdl, [], [], [], 'compile');
    needTerm = true;

    blks = find_system(mdl, 'LookUnderMasks', 'all', 'FollowLinks', 'on', ...
                              'Type', 'Block');
    blks = blks(~strcmp(blks, mdl));

    rateSet = containers.Map('KeyType', 'char', 'ValueType', 'logical');
    for i = 1:numel(blks)
        bp = blks{i};
        try
            ci = get_param(bp, 'CompiledSampleTime');
            if isnumeric(ci) && ~isempty(ci)
                ts = ci(1);
                if ts > 0 && isfinite(ts)
                    rateSet(num2str(ts)) = true;
                end
                sts(end+1) = struct('blk', bp, 'ts', ts); %#ok<AGROW>
            end
        catch
        end
    end

    keys = rateSet.keys;
    if ~isempty(keys)
        nums = cellfun(@str2double, keys);
        nums = sort(nums);
        s.distinct_rates  = numel(nums);
        s.sample_time_set = string(arrayfun(@(x) sprintf('%g', x), ...
                                            nums, 'UniformOutput', false));
    end

    % --- look for cross-rate lines lacking a Rate Transition
    cap = 20;
    lookup = containers.Map({sts.blk}, {sts.ts});
    lines = find_system(mdl, 'FindAll', 'on', 'LookUnderMasks', 'all', ...
                              'FollowLinks', 'on', 'Type', 'Line');
    for i = 1:numel(lines)
        h = lines(i);
        try
            srcH = get_param(h, 'SrcBlockHandle');
            dsts = get_param(h, 'DstBlockHandle');
            if srcH < 0 || isempty(dsts), continue, end
            srcPath = getfullname(srcH);
            if ~isKey(lookup, srcPath), continue, end
            srcTs = lookup(srcPath);
            for k = 1:numel(dsts)
                dh = dsts(k);
                if dh < 0, continue, end
                dstPath = getfullname(dh);
                if ~isKey(lookup, dstPath), continue, end
                dstTs = lookup(dstPath);
                if srcTs > 0 && dstTs > 0 && ...
                        isfinite(srcTs) && isfinite(dstTs) && ...
                        abs(srcTs - dstTs) > 1e-9
                    srcType = get_param(srcH, 'BlockType');
                    dstType = get_param(dh,   'BlockType');
                    if strcmp(srcType, 'RateTransition') || ...
                       strcmp(dstType, 'RateTransition')
                        continue
                    end
                    if numel(s.missing_rate_transitions) < cap
                        s.missing_rate_transitions(end+1) = struct( ...
                            'path',   string(srcPath), ...
                            'src_ts', srcTs, ...
                            'dst_ts', dstTs); %#ok<AGROW>
                    end
                end
            end
        catch
        end
    end
catch
end

if needTerm
    try, feval(mdl, [], [], [], 'term'); catch, end %#ok<CTCH>
end
end
