function export_json(report, file)
% Pretty-print a stripped report struct to JSON. Whitelist only the fields
% required by the validation spec: timestamp, suite, per-test req_id, name,
% status, and per-check name, value, threshold, status. Anything else
% (env, duration_s, mdl, per_suite, metrics, detail, error) is dropped.
[d,~,~] = fileparts(file);
if ~isempty(d) && ~isfolder(d), mkdir(d); end

out = struct();
if isfield(report, 'timestamp'),    out.timestamp = report.timestamp;
elseif isfield(report, 'run_id'),   out.timestamp = report.run_id;
end
if isfield(report, 'suite'),        out.suite = report.suite; end
if isfield(report, 'summary'),      out.summary = report.summary; end

results = report.results;
clean = repmat(struct('req_id',"",'name',"",'status',"",'signals_plot',"",'checks',[]), 0, 1);
for i = 1:numel(results)
    r = results(i);
    cr = struct();
    if isfield(r,'requirement'), cr.req_id = r.requirement;
    elseif isfield(r,'req_id'),  cr.req_id = r.req_id;
    end
    cr.name         = r.name;
    cr.status       = r.status;
    if isfield(r,'signals_plot'), cr.signals_plot = r.signals_plot;
    else,                          cr.signals_plot = ""; end
    cr.checks       = strip_checks(r.checks);
    clean(end+1, 1) = cr; %#ok<AGROW>
end
out.results = clean;

fid = fopen(file, 'w');
if fid < 0, error('val.export_json: cannot open %s', file); end
c = onCleanup(@() fclose(fid));
fwrite(fid, jsonencode(out, 'PrettyPrint', true));
end

function cs = strip_checks(checks)
cs = repmat(struct('name',"",'status',"",'value',[],'threshold',[]), 0, 1);
for i = 1:numel(checks)
    c = checks(i);
    nc = struct( ...
        'name',      c.name, ...
        'status',    c.status, ...
        'value',     c.value, ...
        'threshold', c.expected);
    cs(end+1, 1) = nc; %#ok<AGROW>
end
end
