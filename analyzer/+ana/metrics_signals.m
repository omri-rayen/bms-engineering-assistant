function s = metrics_signals(mdl)
% ana.metrics_signals -- signal/line hygiene metrics.
%
% Returns:
%   unnamed_inter_subsys_list [{path, src, dst}]
%       Lines crossing a subsystem boundary that have no name. MAB jc_0281
%       requires labels on signals that leave their defining subsystem
%       (so downstream readers can trace the data without opening every
%       parent). Capped at 30 entries.
%   total_lines        -- count of non-virtual lines in the model.
%   unnamed_count      -- raw count before the cap (useful for severity).

s = struct();
s.unnamed_inter_subsys_list = struct('path', {}, 'src', {}, 'dst', {});
s.total_lines   = 0;
s.unnamed_count = 0;

try
    lines = find_system(mdl, 'FindAll', 'on', ...
                              'LookUnderMasks', 'all', ...
                              'FollowLinks',    'on', ...
                              'Type', 'Line');
    s.total_lines = numel(lines);
catch
    return
end

cap = 30;
for i = 1:numel(lines)
    h = lines(i);
    try
        nm = get_param(h, 'Name');
        if ~isempty(nm), continue, end

        srcH = get_param(h, 'SrcBlockHandle');
        dstHs = get_param(h, 'DstBlockHandle');
        if isempty(srcH) || srcH < 0 || isempty(dstHs)
            continue
        end
        if ~isnumeric(dstHs), continue, end
        % Only interesting when source and destination are in different
        % subsystems (i.e. the signal crosses a boundary).
        srcParent = get_param(srcH, 'Parent');
        for k = 1:numel(dstHs)
            dh = dstHs(k);
            if dh < 0, continue, end
            dstParent = get_param(dh, 'Parent');
            if ~strcmp(srcParent, dstParent)
                s.unnamed_count = s.unnamed_count + 1;
                if numel(s.unnamed_inter_subsys_list) < cap
                    s.unnamed_inter_subsys_list(end+1) = struct( ...
                        'path', string(getfullname(srcH)), ...
                        'src',  string(getfullname(srcH)), ...
                        'dst',  string(getfullname(dh))); %#ok<AGROW>
                end
                break
            end
        end
    catch
    end
end
end
