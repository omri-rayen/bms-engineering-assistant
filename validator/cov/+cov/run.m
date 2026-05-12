function report = run(varargin)
% cov.run -- BMS dead-code coverage (Simulink Coverage).
%
% Re-runs the BMS MIL stimulus (validator/mil/tests/bms/test_*.m) with
% coverage instrumentation enabled on the smart-BMS models
%   bms_master, bms_slave, fault_predictor
% and writes a JSON report to validator/reports/COV_<timestamp>.json
% (plus a sticky COV.json). Verdict is "pass" iff the worst execution
% dead-code fraction is <= req.COV_dead_pct_max (default 0 %).
% Decision, Condition and MCDC are recorded in the report as
% informational stimulus-coverage metrics only.
%
%   cov.run                          % defaults
%   cov.run('threshold', 0.0)        % accepted dead fraction [%]
%   cov.run('filter', 'REQ_LL_BMS_VMON*')
%   cov.run('outFile', 'path/to.json')

p = inputParser;
p.addParameter('threshold', []);
p.addParameter('filter',    '');
p.addParameter('models',    {});      % subset of {'bms_master','bms_slave','fault_predictor'}
p.addParameter('outFile',   '');
p.addParameter('verbose',   true);
p.addParameter('on_test',   []);
p.parse(varargin{:});
opt = p.Results;

if ~license('test', 'Simulink_Coverage')
    error('cov:run:noLicense', ...
        'Simulink Coverage is required but is not licensed in this MATLAB.');
end

here    = fileparts(mfilename('fullpath'));   % validator/cov/+cov
covRoot = fileparts(here);                    % validator/cov
valRoot = fileparts(covRoot);                 % validator
proj    = fileparts(valRoot);

testsDir = fullfile(valRoot, 'mil', 'tests', 'bms');
repDir   = fullfile(valRoot, 'reports');
if ~isfolder(repDir), mkdir(repDir); end

if evalin('base', '~exist(''bms'',''var'')')
    initFile = fullfile(proj, 'model', 'system', 'params', 'init_system.m');
    evalin('base', sprintf('run(''%s'')', initFile));
end

if isempty(opt.threshold)
    opt.threshold = evalin('base', 'req.COV_dead_pct_max');
end

% Models we want a verdict on (the smart BMS = BMS + embedded AI).
allScope = {'bms_master', 'bms_slave', 'fault_predictor'};
if isempty(opt.models)
    scope = allScope;
else
    scope = intersect(allScope, cellstr(opt.models), 'stable');
    if isempty(scope), scope = allScope; end
end

% Models that the BMS MIL tests load directly. Coverage must be enabled
% on each driver so the referenced models in `scope` are instrumented too.
drivers = {'bms_master', 'bms_slave', 'system_model'};

allMdls  = unique([scope, drivers], 'stable');
restorer = cov.enable_coverage(allMdls);
cleanup  = onCleanup(restorer); %#ok<NASGU>

% Collect cvdata per test (clear between runs to keep things explicit).
files  = dir(fullfile(testsDir, 'test_*.m'));
cvAll  = {};
runLog = repmat(struct('name',"", 'status',"", 'duration_s',0, 'error',""), 0, 1);
nPass = 0; nErr = 0;

for i = 1:numel(files)
    [~, fn] = fileparts(files(i).name);
    if ~isempty(opt.filter) ...
            && isempty(regexp(fn, regexptranslate('wildcard', opt.filter), 'once'))
        continue
    end
    if opt.verbose, fprintf('  [cov ] %-44s ', fn); end

    evalin('base', 'clear covdata');
    snap   = val.snapshot_ws();
    entry  = struct('name', string(fn), 'status', "pass", 'duration_s', 0, 'error', "");
    t0     = tic;
    captured = '';
    try
        captured = evalc('r = feval(fn);');
        if isstruct(r) && isfield(r, 'status')
            entry.status = r.status;
        end
        nPass = nPass + 1;
    catch ME
        if ~isempty(captured), fprintf(2, '%s\n', captured); end
        entry.status = "error";
        entry.error  = string(ME.message);
        nErr = nErr + 1;
        fprintf(2, '\n    ERROR: %s\n', ME.message);
    end
    entry.duration_s = toc(t0);
    val.restore_ws(snap);

    if evalin('base', 'exist(''covdata'',''var'')')
        cd = evalin('base', 'covdata');
        for j = 1:numel(cd)
            cvAll{end+1} = cd(j); %#ok<AGROW>
        end
    end

    if opt.verbose
        fprintf('%-7s  (%.2fs)\n', upper(entry.status), entry.duration_s);
    end
    runLog(end+1, 1) = entry; %#ok<AGROW>
    if ~isempty(opt.on_test)
        try, opt.on_test(struct('suite',"cov",'name',entry.name,'status',entry.status,'duration_s',entry.duration_s)); catch, end
    end
end

if isempty(cvAll)
    error('cov:run:noData', ...
        'No coverage data was produced. Were any BMS MIL tests run?');
end

% Merge into one cvdata per root model (the `+` overload only accepts
% cvdata from the same root). We probe by trying to add; if it fails we
% start a new group. Heterogeneous cvdata (master, slave, system_model)
% land in separate groups; collect() picks the right one per model.
groups = {};
for i = 1:numel(cvAll)
    placed = false;
    for g = 1:numel(groups)
        try
            groups{g} = groups{g} + cvAll{i}; %#ok<AGROW>
            placed = true;
            break
        catch
        end
    end
    if ~placed, groups{end+1} = cvAll{i}; end %#ok<AGROW>
end

% Per-model metrics.
byModel = cov.collect(groups, scope);

% Build the standard test result + roll up the verdict.
% Verdict is scoped to Execution only: an unexecuted block = unreachable
% design = dead code. Decision/Condition/MCDC gaps may reflect missing
% test cases rather than dead logic, so they are recorded as informational.
result = val.new_result("cov", "COV-DEAD-01", ...
    "BMS dead-code coverage (model level)", "REQ-LL-COV-DEAD-01");

worst = 0;
for i = 1:numel(scope)
    m  = scope{i};
    mt = byModel.(m).execution;
    if mt.total == 0, continue, end
    ok = mt.dead_pct <= opt.threshold;
    result = val.check(result, ...
        sprintf('%s_exec_dead_pct', m), ok, ...
        sprintf('%.2f%% dead (%d/%d unexecuted blocks)', ...
            mt.dead_pct, mt.total - mt.covered, mt.total), ...
        mt.dead_pct, opt.threshold);
    if mt.dead_pct > worst, worst = mt.dead_pct; end
end

% Informational: collect worst dec/cond/mcdc (not verdict criteria).
worst_dec = 0; worst_cond = 0; worst_mcdc = 0;
for i = 1:numel(scope)
    m = scope{i};
    if byModel.(m).decision.total  > 0, worst_dec  = max(worst_dec,  byModel.(m).decision.dead_pct);  end
    if byModel.(m).condition.total > 0, worst_cond = max(worst_cond, byModel.(m).condition.dead_pct); end
    if byModel.(m).mcdc.total      > 0, worst_mcdc = max(worst_mcdc, byModel.(m).mcdc.dead_pct);      end
end

result.metrics.dead_code_pct      = worst;
result.metrics.threshold          = opt.threshold;
result.metrics.info_dec_dead_pct  = worst_dec;
result.metrics.info_cond_dead_pct = worst_cond;
result.metrics.info_mcdc_dead_pct = worst_mcdc;

% Report envelope (mirrors mil.run / sil.run).
report = struct();
report.timestamp = string(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
report.suite     = "cov";
report.scope     = string(scope);
report.stimulus  = struct( ...
    'source',  "validator/mil/tests/bms/test_*.m", ...
    'n_tests', numel(runLog), ...
    'n_pass',  nPass, ...
    'n_error', nErr);
report.summary  = val.summarize(result);
report.by_model = byModel;
report.verdict  = struct( ...
    'dead_code_pct',      worst, ...
    'threshold_pct',      opt.threshold, ...
    'info_dec_dead_pct',  worst_dec, ...
    'info_cond_dead_pct', worst_cond, ...
    'info_mcdc_dead_pct', worst_mcdc, ...
    'status',             result.status);
report.results  = result;

% Write JSON (timestamped + sticky).
custom = ~isempty(opt.outFile);
if ~custom
    opt.outFile = fullfile(repDir, sprintf('COV_%s.json', report.timestamp));
end
write_json(report, opt.outFile);
if ~custom
    write_json(report, fullfile(repDir, 'COV.json'));
end

fprintf('\n=== COVERAGE SUMMARY ===\n');
fprintf('Tests: %d  pass: %d  error: %d\n', numel(runLog), nPass, nErr);
for i = 1:numel(scope)
    m  = scope{i};
    md = byModel.(m);
    fprintf('  %-16s exec=%5.1f%%  dec=%5.1f%%  cond=%5.1f%%  mcdc=%5.1f%%\n', ...
        m, md.execution.coverage_pct, md.decision.coverage_pct, ...
        md.condition.coverage_pct, md.mcdc.coverage_pct);
end
fprintf('Worst dead-code: %.2f%%   threshold: %.2f%%   verdict: %s\n', ...
    worst, opt.threshold, upper(report.verdict.status));
fprintf('  (informational) dec=%.1f%%  cond=%.1f%%  mcdc=%.1f%%\n', ...
    worst_dec, worst_cond, worst_mcdc);
fprintf('Report: %s\n', opt.outFile);
end


function restoreFn = enable_coverage(mdls)
% Switch coverage on for every model in `mdls`. Returns a function handle
% that restores the original parameter values.
params  = {'CovEnable',   'RecordCoverage',  'CovMetricSettings', ...
           'CovModelRefEnable', 'CovSFcnEnable', ...
           'CovSaveSingleToWorkspaceVar', 'CovSaveName'};
desired = {'on', 'on', 'dcmtr', 'all', 'on', 'on', 'covdata'};

saved = struct();
for i = 1:numel(mdls)
    m = mdls{i};
    load_system(m);
    saved.(m) = struct();
    for k = 1:numel(params)
        try
            saved.(m).(params{k}) = get_param(m, params{k});
            set_param(m, params{k}, desired{k});
        catch
            % Parameter not applicable for this model -- skip.
        end
    end
end

restoreFn = @() restore_params(mdls, params, saved);
end


function restore_params(mdls, params, saved)
for i = 1:numel(mdls)
    m = mdls{i};
    if ~bdIsLoaded(m) || ~isfield(saved, m), continue, end
    for k = 1:numel(params)
        if isfield(saved.(m), params{k})
            try
                set_param(m, params{k}, saved.(m).(params{k}));
            catch
            end
        end
    end
end
end


function write_json(s, file)
[d, ~, ~] = fileparts(file);
if ~isempty(d) && ~isfolder(d), mkdir(d); end
fid = fopen(file, 'w');
if fid < 0, error('cov:run:write', 'cannot open %s', file); end
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(s, 'PrettyPrint', true));
end
