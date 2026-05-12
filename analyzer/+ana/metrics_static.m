function s = metrics_static(mdl)
% ana.metrics_static -- Block-level structural metrics + per-issue lists.
%
% Returns scalar counts (kept so the percentage-style rules still work)
% AND lists of concrete offenders so the analyzer can locate every issue
% inside the Simulink model. List entries always carry the full block
% path so they can be opened with hilite_system in MATLAB.
%
% Field summary:
%   block_count, subsystem_count, atomic_count
%   depth_max, signal_lines, cyclomatic
%   model_refs, blocks_by_type
%   broken_links (count) + broken_links_list
%   unconnected_ports (count) + unconnected_ports_list  [{path, type, port}]
%   large_subsystems_list             [{path, n_blocks, atomic}]
%   deep_blocks_list                  top-3 deepest blocks  [{path, depth}]
%   default_named_blocks_list         [{path, type, name}]
%   high_cyclo_subsystems_list        [{path, value}]
%   algebraic_loops_list              [{path}]

blks = find_system(mdl, 'LookUnderMasks', 'all', ...
                        'FollowLinks',   'on',  ...
                        'MatchFilter',   @Simulink.match.allVariants);
blks = blks(~strcmp(blks, mdl));   % drop the root model handle
s.block_count = numel(blks);

ss = find_system(mdl, 'LookUnderMasks', 'all', 'FollowLinks', 'on', ...
                       'BlockType', 'SubSystem');
s.subsystem_count = numel(ss);
atomicMask = strcmp(get_param(ss, 'TreatAsAtomicUnit'), 'on');
s.atomic_count = sum(atomicMask);

% --- Hierarchy depth + the three deepest blocks (full path).
paths = get_param(blks, 'Parent');
if ischar(paths), paths = {paths}; end
rootDepth = sum(mdl == '/');
depths = cellfun(@(p) sum(p == '/') - rootDepth, paths);
s.depth_max = max([0; depths(:)]);

[depthSorted, order] = sort(depths(:), 'descend');
s.deep_blocks_list = struct('path', {}, 'depth', {});
for i = 1:min(3, numel(order))
    if depthSorted(i) <= 0, break, end
    s.deep_blocks_list(end+1) = struct( ...
        'path',  string(blks{order(i)}), ...
        'depth', depthSorted(i)); %#ok<AGROW>
end

lines = find_system(mdl, 'FindAll', 'on', 'LookUnderMasks', 'all', ...
                         'FollowLinks', 'on', 'Type', 'Line');
s.signal_lines = numel(lines);

% --- Unconnected ports: count + per-port location.
ports = find_system(mdl, 'FindAll', 'on', 'LookUnderMasks', 'all', ...
                         'FollowLinks', 'on', 'Type', 'Port');
s.unconnected_ports_list = struct('path', {}, 'type', {}, 'port', {}, ...
                                   'parent', {}, 'block_type', {});
nUnc = 0;
for i = 1:numel(ports)
    h = ports(i);
    try
        ln = get_param(h, 'Line');
        if ~(isnumeric(ln) && isscalar(ln) && ln == -1), continue, end
        nUnc = nUnc + 1;
        parentPath = get_param(h, 'Parent');
        bt = '';
        try, bt = get_param(parentPath, 'BlockType'); catch, end %#ok<CTCH>
        % `parent` is the path to the block that owns the orphan port; the
        % `parent of that` is the enclosing subsystem -- which is what an
        % engineer wants to navigate to.
        gp = '';
        try, gp = get_param(parentPath, 'Parent'); catch, end %#ok<CTCH>
        s.unconnected_ports_list(end+1) = struct( ...
            'path',       string(parentPath), ...
            'type',       string(get_param(h, 'PortType')), ...
            'port',       double(get_param(h, 'PortNumber')), ...
            'parent',     string(gp), ...
            'block_type', string(bt)); %#ok<AGROW>
    catch
    end
end
s.unconnected_ports = nUnc;

% --- Library refs and broken links (with path).
try
    refs = find_mdlrefs(mdl, 'AllLevels', true, ...
                        'MatchFilter', @Simulink.match.allVariants);
    s.model_refs = string(refs(:)');
catch
    s.model_refs = string([]);
end

s.broken_links_list = struct('path', {}, 'status', {});
try
    info = libinfo(mdl);
    for i = 1:numel(info)
        if isfield(info, 'LinkStatus') && ...
                strcmp(info(i).LinkStatus, 'unresolved')
            s.broken_links_list(end+1) = struct( ...
                'path',   string(info(i).Block), ...
                'status', string(info(i).LinkStatus)); %#ok<AGROW>
        end
    end
catch
end
s.broken_links = numel(s.broken_links_list);

% --- Cyclomatic: top value + per-subsystem hot-spots.
s.cyclomatic = -1;
s.high_cyclo_subsystems_list = struct('path', {}, 'value', {});
try
    diag = sldiagnostics(mdl, 'CyclomaticComplexity');
    if ~isempty(diag)
        s.cyclomatic = double(diag(end).Value);
    end
    for i = 1:numel(diag)-1     % last entry is the model itself
        v = double(diag(i).Value);
        if v >= 20
            s.high_cyclo_subsystems_list(end+1) = struct( ...
                'path',  string(diag(i).Name), ...
                'value', v); %#ok<AGROW>
        end
    end
    if ~isempty(s.high_cyclo_subsystems_list)
        [~, ord] = sort([s.high_cyclo_subsystems_list.value], 'descend');
        s.high_cyclo_subsystems_list = ...
            s.high_cyclo_subsystems_list(ord(1:min(10, numel(ord))));
    end
catch
end

% --- Atomic subsystems with too many blocks (refactor candidates).
s.large_subsystems_list = struct('path', {}, 'n_blocks', {}, 'atomic', {});
threshold = 100;
for i = 1:numel(ss)
    inside = find_system(ss{i}, 'LookUnderMasks', 'all', ...
                                'FollowLinks',    'on', ...
                                'SearchDepth',    1);
    n = numel(inside) - 1;     % minus the subsystem itself
    if n >= threshold
        s.large_subsystems_list(end+1) = struct( ...
            'path',     string(ss{i}), ...
            'n_blocks', n, ...
            'atomic',   atomicMask(i)); %#ok<AGROW>
    end
end

% --- Atomic subsystems with too many I/O ports (cohesion proxy).
% MAB recommends keeping atomic units narrow; > 8 ins or > 6 outs is a
% common refactor threshold and a reliable sign of mixed responsibilities.
s.wide_atomic_subsystems_list = struct('path', {}, 'n_in', {}, 'n_out', {});
ioCap = 12;
for i = 1:numel(ss)
    if ~atomicMask(i), continue, end
    try
        ins  = find_system(ss{i}, 'LookUnderMasks', 'all', ...
                                  'FollowLinks',    'on', ...
                                  'SearchDepth',    1, ...
                                  'BlockType',      'Inport');
        outs = find_system(ss{i}, 'LookUnderMasks', 'all', ...
                                  'FollowLinks',    'on', ...
                                  'SearchDepth',    1, ...
                                  'BlockType',      'Outport');
        nIn  = numel(ins);
        nOut = numel(outs);
        if (nIn > 8 || nOut > 6) && ...
                numel(s.wide_atomic_subsystems_list) < ioCap
            s.wide_atomic_subsystems_list(end+1) = struct( ...
                'path',  string(ss{i}), ...
                'n_in',  nIn, ...
                'n_out', nOut); %#ok<AGROW>
        end
    catch
    end
end

% --- Default-named blocks (Sum1, Gain2, Subsystem3, ...) -- readability.
% Skip blocks that live inside a library / masked container: their
% inner names belong to the library author, not to this model. Also
% skip blocks under a parent whose own name signals it is a wrapper
% around a single named parameter (parent name = leaf is a Constant
% with the same idea).
s.default_named_blocks_list = struct('path', {}, 'type', {}, 'name', {}, ...
                                      'parent', {});
defaultPattern = ['^(Subsystem|Sum|Gain|Product|Constant|Switch|Mux|Demux|', ...
                  'Scope|Logical Operator|Relational Operator|Compare To Zero|', ...
                  'Compare To Constant|Saturation|Memory|Unit Delay|Delay)\d*$'];
for i = 1:numel(blks)
    h = blks{i};
    try
        nm = get_param(h, 'Name');
        if isempty(regexp(nm, defaultPattern, 'once')), continue, end
        par = get_param(h, 'Parent');
        % Skip when the parent is itself a library link or a masked
        % subsystem (the user dropped a library block; the inner names
        % belong to the library author and cannot be edited locally).
        skip = false;
        try
            if ~strcmp(par, mdl)
                refBlk = get_param(par, 'ReferenceBlock');
                if ~isempty(refBlk), skip = true; end
                if ~skip
                    maskType = get_param(par, 'MaskType');
                    if ~isempty(maskType), skip = true; end
                end
            end
        catch
        end
        if skip, continue, end
        s.default_named_blocks_list(end+1) = struct( ...
            'path',   string(h), ...
            'type',   string(get_param(h, 'BlockType')), ...
            'name',   string(nm), ...
            'parent', string(par)); %#ok<AGROW>
    catch
    end
end
if numel(s.default_named_blocks_list) > 15
    s.default_named_blocks_list = s.default_named_blocks_list(1:15);
end

% Aggregate the same data by parent subsystem -- a single finding per
% offending parent reads as one actionable refactor task rather than as
% N noise items. Format: [{parent, count, names_csv, type_csv}].
parents = arrayfun(@(b) char(b.parent), s.default_named_blocks_list, ...
                   'UniformOutput', false);
[uParents, ~, idx] = unique(parents);
s.default_named_by_parent_list = struct( ...
    'parent', {}, 'count', {}, 'names', {}, 'types', {});
for k = 1:numel(uParents)
    sel  = (idx == k);
    item = s.default_named_blocks_list(sel);
    namesArr = arrayfun(@(b) char(b.name), item, 'UniformOutput', false);
    typesArr = arrayfun(@(b) char(b.type), item, 'UniformOutput', false);
    s.default_named_by_parent_list(end+1) = struct( ...
        'parent', string(uParents{k}), ...
        'count',  double(numel(item)), ...
        'names',  string(strjoin(namesArr, ', ')), ...
        'types',  string(strjoin(unique(typesArr), '/'))); %#ok<AGROW>
end

% --- Algebraic loops (rare; always worth flagging).
s.algebraic_loops_list = struct('path', {});
try
    loops = sldiagnostics(mdl, 'AlgebraicLoops');
    if ~isempty(loops)
        for i = 1:numel(loops)
            if isfield(loops(i), 'Name')
                s.algebraic_loops_list(end+1) = struct( ...
                    'path', string(loops(i).Name)); %#ok<AGROW>
            end
        end
    end
catch
end

% --- Top BlockType histogram (cap to 12 to keep JSON small).
types = get_param(blks, 'BlockType');
if ~iscell(types), types = {types}; end
[u, ~, idx] = unique(types);
counts = accumarray(idx, 1);
[counts, order] = sort(counts, 'descend');
u = u(order);
n = min(numel(u), 12);
s.blocks_by_type = struct();
for i = 1:n
    name = matlab.lang.makeValidName(u{i});
    s.blocks_by_type.(name) = counts(i);
end
end
