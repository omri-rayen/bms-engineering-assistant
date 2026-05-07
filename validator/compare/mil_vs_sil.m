function out = mil_vs_sil(milPath, silPath, outPath)
% Compare a MIL.json and a SIL.json by test id and metric.
%   compare.mil_vs_sil('validator/reports/MIL.json', ...
%                      'validator/reports/SIL.json', ...
%                      'validator/reports/MIL_vs_SIL.json')
%
% Phase 2 will populate metric tolerances from acceptance_criteria.yaml.
% For Phase 1 this is a thin status-only diff that still produces the
% report shape promised in the refactor plan.

if nargin < 3, outPath = fullfile('validator','reports','MIL_vs_SIL.json'); end
out = compare_runs(milPath, silPath, "MIL", "SIL", outPath);
end

function out = compare_runs(pathA, pathB, labelA, labelB, outPath)
A = jsondecode(fileread(pathA));
B = jsondecode(fileread(pathB));

mapA = index_by_id(A.results);
mapB = index_by_id(B.results);
ids  = intersect(keys(mapA), keys(mapB));

tests = struct('id',{},'status_match',{},'status_a',{},'status_b',{},'metrics',{});
matches = 0; mismatches = 0;
for i = 1:numel(ids)
    id = ids{i};
    rA = mapA(id);
    rB = mapB(id);
    sm = strcmp(rA.status, rB.status);
    if sm, matches = matches + 1; else, mismatches = mismatches + 1; end
    tests(end+1) = struct( ...
        'id',           string(id), ...
        'status_match', sm, ...
        'status_a',     string(rA.status), ...
        'status_b',     string(rB.status), ...
        'metrics',      diff_metrics(rA, rB));  %#ok<AGROW>
end

out = struct( ...
    'run_id_a', A.run_id, ...
    'run_id_b', B.run_id, ...
    'label_a',  labelA, ...
    'label_b',  labelB, ...
    'summary',  struct( ...
        'tests_compared',    numel(ids), ...
        'status_matches',    matches, ...
        'status_mismatches', mismatches), ...
    'tests',    tests);

[d,~,~] = fileparts(outPath);
if ~isempty(d) && ~isfolder(d), mkdir(d); end
fid = fopen(outPath, 'w');
c = onCleanup(@() fclose(fid));
fwrite(fid, jsonencode(out, 'PrettyPrint', true));
fprintf('Compare report: %s\n', outPath);
end

function m = index_by_id(results)
m = containers.Map('KeyType','char','ValueType','any');
for i = 1:numel(results)
    r = results(i);
    if isfield(r,'id') && ~isempty(r.id)
        m(char(r.id)) = r;
    end
end
end

function ms = diff_metrics(rA, rB)
ms = struct('name',{},'value_a',{},'value_b',{},'abs_diff',{},'rel_diff_pct',{});
if ~isstruct(rA.metrics) || ~isstruct(rB.metrics), return, end
fn = intersect(fieldnames(rA.metrics), fieldnames(rB.metrics));
for k = 1:numel(fn)
    a = rA.metrics.(fn{k});  b = rB.metrics.(fn{k});
    if ~isnumeric(a) || ~isnumeric(b) || ~isscalar(a) || ~isscalar(b), continue, end
    d = abs(a - b);
    rel = 100 * d / max(abs(a), eps);
    ms(end+1) = struct( ...
        'name',         string(fn{k}), ...
        'value_a',      a, ...
        'value_b',      b, ...
        'abs_diff',     d, ...
        'rel_diff_pct', rel); %#ok<AGROW>
end
end
