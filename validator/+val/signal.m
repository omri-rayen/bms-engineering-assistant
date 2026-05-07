function s = signal(out, name)
% Pull a logged signal by name from sim output (yout dataset).
% Tries exact match, then logged-block name, then fuzzy contains-match
% (case-insensitive). Aliases SoC_est<->SoC_pack and SoH_est<->SoH_pack.
yo  = out.yout;

aliases = struct( ...
    'SoC_est',  {{'SoC_est','SoC_pack'}}, ...
    'SoC_pack', {{'SoC_pack','SoC_est'}}, ...
    'SoH_est',  {{'SoH_est','SoH_pack'}}, ...
    'SoH_pack', {{'SoH_pack','SoH_est'}});
if isfield(aliases, name)
    candidates = aliases.(name);
else
    candidates = {name};
end

val = [];
for ci = 1:numel(candidates)
    c = candidates{ci};
    val = exact_lookup(yo, c);
    if isempty(val), val = block_lookup(yo, c); end
    if ~isempty(val), break, end
end
if isempty(val), val = fuzzy_lookup(yo, name); end
if isempty(val)
    error('val:signal:notFound', ...
        'Signal "%s" not in sim output.\nAvailable: %s', name, strjoin(list_available(yo), ', '));
end
s.t = val.Time(:);
y   = squeeze(double(val.Data));
if isvector(y), y = y(:); end
if size(y,1) ~= numel(s.t) && size(y,2) == numel(s.t), y = y.'; end
s.y = y;
end

function val = exact_lookup(yo, name)
val = [];
for i = 1:yo.numElements
    el = yo.getElement(i);
    if strcmp(el.Name, name), val = el.Values; return, end
    v = el.Values;
    if isstruct(v) && isfield(v, name), val = v.(name); return, end
    if isobject(v)
        try, val = v.(name); return, catch, end
    end
end
end

function val = block_lookup(yo, name)
% Match by source Outport block name (covers unlabeled signal lines).
val = [];
for i = 1:yo.numElements
    el = yo.getElement(i);
    try
        bp   = el.BlockPath;
        last = bp.getBlock(bp.getLength);   % e.g. 'bms_master/prob_3'
        parts = strsplit(char(last), '/');
        if strcmp(parts{end}, name), val = el.Values; return, end
    catch
    end
end
end

function val = fuzzy_lookup(yo, name)
val = []; needle = lower(name);
for i = 1:yo.numElements
    el = yo.getElement(i);
    n = lower(el.Name);
    if ~isempty(n) && (contains(n, needle) || contains(needle, n))
        val = el.Values; return
    end
    v = el.Values;
    if isstruct(v)
        fns = fieldnames(v);
        for j = 1:numel(fns)
            fn = lower(fns{j});
            if contains(fn, needle) || contains(needle, fn)
                val = v.(fns{j}); return
            end
        end
    end
end
end

function avail = list_available(yo)
avail = strings(0,1);
for i = 1:yo.numElements
    el = yo.getElement(i);
    avail(end+1,1) = string(el.Name);
    v = el.Values;
    if isstruct(v)
        fns = fieldnames(v);
        for j = 1:numel(fns), avail(end+1,1) = string(fns{j}); end
    end
end
end
