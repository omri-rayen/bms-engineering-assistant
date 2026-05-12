function reps = list_reports(varargin)
% orch.list_reports -- list past pipeline runs (newest first).
%
% A "run" is identified by its timestamp. We union timestamps from
% REPORT_PART1_<ts>.html, REPORT_PART2_<ts>.html and
% FULL_REPORT_<ts>.json so JSON-only runs (no LLM key, dry-run, or
% partially-failed runs) still show up.

p = inputParser;
p.addParameter('limit', 200, @isnumeric);
p.parse(varargin{:});

repo = orch.repo_root();
dir1 = fullfile(repo,'doc_generator','reports');

ts_set = containers.Map('KeyType','char','ValueType','any');

% Two-part HTMLs (current format).
for part = 1:2
    pat = sprintf('REPORT_PART%d_*.html', part);
    htmls = dir(fullfile(dir1, pat));
    pfx   = sprintf('REPORT_PART%d_', part);
    for i = 1:numel(htmls)
        ts = local_ts(htmls(i).name, pfx, '.html');
        if isempty(ts), continue, end
        rec = local_rec(ts_set, ts);
        rec.(sprintf('html%d',  part))    = fullfile(htmls(i).folder, htmls(i).name);
        rec.(sprintf('html%d_kb',part))   = round(htmls(i).bytes/1024,1);
        rec.datenum = max(getfield_default(rec,'datenum',0), htmls(i).datenum);
        ts_set(ts) = rec;
    end
end

% Legacy single-file HTMLs (older runs from before the split). Treated
% as part 1 only so they still appear in the table; part 2 just shows
% as missing.
htmls = dir(fullfile(dir1, 'REPORT_*.html'));
for i = 1:numel(htmls)
    nm = htmls(i).name;
    if startsWith(nm, 'REPORT_PART'), continue, end
    ts = local_ts(nm, 'REPORT_', '.html');
    if isempty(ts), continue, end
    rec = local_rec(ts_set, ts);
    if ~isfield(rec,'html1') || isempty(rec.html1)
        rec.html1     = fullfile(htmls(i).folder, nm);
        rec.html1_kb  = round(htmls(i).bytes/1024,1);
    end
    rec.datenum = max(getfield_default(rec,'datenum',0), htmls(i).datenum);
    ts_set(ts) = rec;
end

jsons = dir(fullfile(dir1, 'FULL_REPORT_*.json'));
for i = 1:numel(jsons)
    ts = local_ts(jsons(i).name, 'FULL_REPORT_', '.json');
    if isempty(ts), continue, end
    rec = local_rec(ts_set, ts);
    rec.json    = fullfile(jsons(i).folder, jsons(i).name);
    rec.datenum = max(getfield_default(rec,'datenum',0), jsons(i).datenum);
    ts_set(ts) = rec;
end

keys = ts_set.keys;
reps = repmat(struct('ts',"", 'html1',"", 'html2',"", 'json',"", ...
    'has_html1',false, 'has_html2',false, 'has_json',false, ...
    'size_kb',0, 'age',""), 0, 1);
for i = 1:numel(keys)
    rec = ts_set(keys{i});
    h1 = string(getfield_default(rec,'html1',''));
    h2 = string(getfield_default(rec,'html2',''));
    kb = getfield_default(rec,'html1_kb',0) + getfield_default(rec,'html2_kb',0);
    reps(end+1,1) = struct( ...
        'ts',         string(keys{i}), ...
        'html1',      h1, ...
        'html2',      h2, ...
        'json',       string(getfield_default(rec,'json','')), ...
        'has_html1',  strlength(h1) > 0, ...
        'has_html2',  strlength(h2) > 0, ...
        'has_json',   isfield(rec,'json') && ~isempty(rec.json), ...
        'size_kb',    kb, ...
        'age',        string(datestr(rec.datenum,'yyyy-mm-dd HH:MM:SS')) ); %#ok<AGROW,DATST>
end
if isempty(reps), return, end
[~, ord] = sort([reps.ts], 'descend');
reps = reps(ord);
if numel(reps) > p.Results.limit
    reps = reps(1:p.Results.limit);
end
end

function rec = local_rec(map, k)
if isKey(map, k), rec = map(k); else, rec = struct('datenum',0); end
end

function v = getfield_default(s, f, d)
if isfield(s,f), v = s.(f); else, v = d; end
end

function ts = local_ts(name, prefix, suffix)
ts = '';
if startsWith(name, prefix) && endsWith(name, suffix)
    ts = name(numel(prefix)+1 : end-numel(suffix));
end
end
