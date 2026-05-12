function s = metrics_data(mdl)
% ana.metrics_data -- data dictionary hygiene.
%
% Returns:
%   magic_constants_list [{path, value, parent}]
%       Constant blocks holding hard-coded numeric literals (no MATLAB
%       variable, no Simulink.Parameter). MAB jc_0224 wants tunable
%       parameters in a data dictionary so they can be calibrated /
%       reviewed. Capped at 20.
%   data_store_globals_list [{path, name}]
%       DataStoreMemory blocks at model root: globals across the whole
%       model -- visibility hidden from the diagram. Capped at 10.
%   goto_global_list [{path, tag}]
%       Goto blocks with global TagVisibility (data flow invisible from
%       the diagram). Capped at 10.

s = struct();
s.magic_constants_list   = struct('path', {}, 'value', {}, 'parent', {});
s.data_store_globals_list = struct('path', {}, 'name',  {});
s.goto_global_list       = struct('path', {}, 'tag',   {});

% --- magic numbers
% A "magic" constant is an *unnamed* literal: a Constant block whose
% own name is the default (Constant / Constant3 / etc) AND whose value
% is a numeric literal that is not a workspace variable. A Constant
% named `V_cell_max` already documents the parameter -- the block name
% IS the identifier; not magic. We also skip constants under a masked
% library subsystem (they are part of the library's internal wiring).
trivial = {'0','1','-1','0.0','1.0','-1.0','true','false','[]'};
defaultName = '^Constant\d*$';
try
    consts = find_system(mdl, 'LookUnderMasks', 'all', 'FollowLinks', 'on', ...
                                'BlockType', 'Constant');
    for i = 1:numel(consts)
        bp = consts{i};
        try
            nm = get_param(bp, 'Name');
            if isempty(regexp(nm, defaultName, 'once')), continue, end
            v = get_param(bp, 'Value');
            if ~ischar(v) || isempty(v), continue, end
            clean = strtrim(v);
            if any(strcmp(clean, trivial)), continue, end
            if isempty(regexp(clean, '^[\-\+0-9eE.\s\[\];,]+$', 'once')) ...
                    || ~isempty(regexp(clean, '[a-zA-Z_]', 'once'))
                continue
            end
            par = get_param(bp, 'Parent');
            % skip if parent is a masked library block (Compare To,
            % Detect *, Debounce, custom mask, etc).
            try
                if ~strcmp(par, mdl)
                    if ~isempty(get_param(par, 'ReferenceBlock')), continue, end
                    if ~isempty(get_param(par, 'MaskType')),       continue, end
                end
            catch
            end
            if numel(s.magic_constants_list) < 20
                s.magic_constants_list(end+1) = struct( ...
                    'path',   string(bp), ...
                    'value',  string(clean), ...
                    'parent', string(par)); %#ok<AGROW>
            end
        catch
        end
    end
catch
end

% --- DataStoreMemory at the root (= model-global)
try
    dsm = find_system(mdl, 'LookUnderMasks', 'all', 'FollowLinks', 'on', ...
                            'BlockType', 'DataStoreMemory');
    for i = 1:numel(dsm)
        bp = dsm{i};
        try
            par = get_param(bp, 'Parent');
            % Root = parent equals model name (no '/' inside).
            if strcmp(par, mdl)
                if numel(s.data_store_globals_list) < 10
                    s.data_store_globals_list(end+1) = struct( ...
                        'path', string(bp), ...
                        'name', string(get_param(bp, 'DataStoreName'))); %#ok<AGROW>
                end
            end
        catch
        end
    end
catch
end

% --- Goto with global / scoped visibility
try
    gotos = find_system(mdl, 'LookUnderMasks', 'all', 'FollowLinks', 'on', ...
                              'BlockType', 'Goto');
    for i = 1:numel(gotos)
        bp = gotos{i};
        try
            vis = get_param(bp, 'TagVisibility');
            if any(strcmp(vis, {'global', 'scoped'}))
                if numel(s.goto_global_list) < 10
                    s.goto_global_list(end+1) = struct( ...
                        'path', string(bp), ...
                        'tag',  string(get_param(bp, 'GotoTag'))); %#ok<AGROW>
                end
            end
        catch
        end
    end
catch
end
end
