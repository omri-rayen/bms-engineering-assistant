function report = run(varargin)
% Run the MIL validation suites and write a JSON report.
%   mil.run                                    % all suites
%   mil.run('suites', {'bms'})                 % subset
%   mil.run('filter', 'REQ_LL_BMS_*')          % wildcard match on test name
%   mil.run('outFile', 'validator/reports/...')
%
% Discovers test functions under validator/mil/tests/<suite>/test_*.m,
% runs each with workspace snapshot/restore, and writes the report.

p = inputParser;
p.addParameter('suites',    {'bms','predictor'});
p.addParameter('filter',    '');
p.addParameter('verbose',   true);
p.addParameter('outFile',   '');
p.addParameter('testsRoot', '');
p.addParameter('on_test',   []);
% Single-pass MIL+coverage: when true, Simulink Coverage is enabled on
% the smart-BMS models for the duration of the MIL run and the per-test
% cvdata is collected on report.cvdata. orch.run consumes that array via
% cov.from_cvdata to produce the COV verdict report -- avoiding a second
% full MIL re-run.
p.addParameter('coverage',  false, @islogical);
p.addParameter('cov_models', {'bms_master','bms_slave','fault_predictor'});
p.parse(varargin{:});
opt = p.Results;

here    = fileparts(mfilename('fullpath'));   % validator/mil/+mil
milRoot = fileparts(here);                    % validator/mil
valRoot = fileparts(milRoot);                 % validator
proj    = fileparts(valRoot);

testsRoot = opt.testsRoot;
if isempty(testsRoot), testsRoot = fullfile(milRoot, 'tests'); end
repDir = fullfile(valRoot, 'reports');
if ~isfolder(repDir), mkdir(repDir); end

if evalin('base', '~exist(''bms'',''var'')')
    initFile = fullfile(proj, 'model', 'system', 'params', 'init_system.m');
    evalin('base', sprintf('run(''%s'')', initFile));
end

% Single-pass MIL+coverage: enable Simulink Coverage on the BMS test
% drivers + the requested verdict scope. The same instrumentation is
% reused across all MIL tests instead of doing a second re-run in cov.
cvAll = {};
covCleanup = []; %#ok<NASGU>
if opt.coverage
    if ~license('test', 'Simulink_Coverage')
        error('mil:run:noCovLicense', ...
            'mil.run(''coverage'',true) requires a Simulink Coverage license.');
    end
    drivers  = {'bms_master', 'bms_slave', 'system_model'};
    allMdls  = unique([cellstr(opt.cov_models), drivers], 'stable');
    fprintf('[mil] coverage=on  scope=%s\n', strjoin(allMdls, ' + '));
    restorer   = cov.enable_coverage(allMdls);
    covCleanup = onCleanup(restorer); %#ok<NASGU>
end

results = repmat(val.new_result("","","",""), 0, 1);
for s = 1:numel(opt.suites)
    suite    = opt.suites{s};
    suiteDir = fullfile(testsRoot, suite);
    if ~isfolder(suiteDir)
        warning('Suite folder missing: %s', suiteDir);
        continue
    end
    files = dir(fullfile(suiteDir, 'test_*.m'));
    for f = 1:numel(files)
        [~, fn] = fileparts(files(f).name);
        if ~isempty(opt.filter) && ~local_filter_match(fn, opt.filter)
            continue
        end
        if opt.verbose, fprintf('  [%-10s] %-44s ', suite, fn); end
        snap = val.snapshot_ws();
        if opt.coverage, evalin('base', 'clear covdata'); end
        t0 = tic;
        captured = '';
        try
            % evalc swallows the verbose Simulink build/codegen log that
            % pack_96s emits on every parameter change between scenarios.
            % We only re-surface it on test error.
            captured = evalc('r = feval(fn);');
        catch ME
            if ~isempty(captured), fprintf(2, '%s\n', captured); end
            r = val.new_result(string(suite), string(fn), string(fn), "");
            r.status = "error";
            r.error  = string(ME.message);
            fprintf(2, '\n    ERROR: %s\n', getReport(ME, 'extended'));
        end
        r.duration_s = toc(t0);
        if isempty(r.suite) || r.suite == "", r.suite = string(suite); end
        if opt.coverage && evalin('base', 'exist(''covdata'',''var'')')
            cd = evalin('base', 'covdata');
            for jj = 1:numel(cd)
                cvAll{end+1} = cd(jj); %#ok<AGROW>
            end
        end
        val.restore_ws(snap);
        if opt.verbose, fprintf('%-7s  (%.2fs)\n', upper(r.status), r.duration_s); end
        results(end+1, 1) = r; %#ok<AGROW>
        if ~isempty(opt.on_test)
            try, opt.on_test(struct('suite',string(suite),'name',string(fn),'status',string(r.status),'duration_s',r.duration_s)); catch, end
        end
    end
end

report.timestamp = string(datetime('now','Format','yyyyMMdd_HHmmss'));
report.suite     = "mil";
report.summary   = val.summarize(results);
report.results   = results;
% Coverage payload (single-pass MIL+cov): kept off-disk; orch.run consumes
% it via cov.from_cvdata. Empty when coverage was disabled.
report.cvdata    = cvAll;

suites = unique(arrayfun(@(x) x.suite, results));
ps = struct('suite',{},'total',{},'pass',{},'fail',{},'error',{},'skipped',{});
for i = 1:numel(suites)
    mask = arrayfun(@(x) x.suite == suites(i), results);
    s = val.summarize(results(mask));
    s.suite = suites(i);
    ps(end+1) = s; %#ok<AGROW>
end

customOut = ~isempty(opt.outFile);
if ~customOut
    opt.outFile = fullfile(repDir, sprintf('MIL_%s.json', report.timestamp));
end
% cvdata is opaque (cvdata objects) and irrelevant to disk -- strip it.
report_disk = rmfield(report, 'cvdata');
val.export_json(report_disk, opt.outFile);
if ~customOut
    val.export_json(report_disk, fullfile(repDir, 'MIL.json'));
end

fprintf('\n=== MIL VALIDATION SUMMARY ===\n');
fprintf('Total: %d  pass: %d  fail: %d  error: %d  skipped: %d\n', ...
    report.summary.total, report.summary.pass, report.summary.fail, ...
    report.summary.error, report.summary.skipped);
for i = 1:numel(ps)
    fprintf('  %-10s  pass=%d/%d  fail=%d  err=%d\n', ...
        ps(i).suite, ps(i).pass, ps(i).total, ps(i).fail, ps(i).error);
end
fprintf('Report: %s\n', opt.outFile);

% Stacked bar: pass / fail / error per suite.
try
    plotDir = fullfile(repDir, 'plots', 'mil');
    if ~isfolder(plotDir), mkdir(plotDir); end
    fig = figure('Visible','off','Position',[100 100 800 400]);
    data = [[ps.pass]', [ps.fail]', [ps.error]'];
    labels = {'pass','fail','error'};
    h = bar(data, 'stacked');
    set(gca, 'XTickLabel', cellstr([ps.suite]));
    % Only include legend entries for series that have at least one non-zero
    % bar; otherwise MATLAB warns "Ignoring extra legend entries".
    nonzero = any(data > 0, 1);
    if any(nonzero)
        legend(h(nonzero), labels(nonzero), 'Location','northeast');
    end
    ylabel('tests'); title(sprintf('MIL summary  -  %d pass / %d total', report.summary.pass, report.summary.total));
    grid on;
    exportgraphics(fig, fullfile(plotDir, 'summary.png'), 'Resolution', 120);
    close(fig);
    fprintf('Plot  : %s\n', fullfile(plotDir, 'summary.png'));
catch ME
    warning('mil:run:plot', 'summary plot failed: %s', ME.message);
end
end

% Match a test name against either a single wildcard string or a
% cellstr of wildcards. Empty filter is handled by the caller.
function tf = local_filter_match(name, filter)
if iscell(filter), filters = filter; else, filters = {char(filter)}; end
tf = false;
for i = 1:numel(filters)
    fi = strtrim(filters{i});
    if isempty(fi), tf = true; return, end
    re = regexptranslate('wildcard', fi);
    if ~isempty(regexp(name, re, 'once')), tf = true; return, end
end
end
