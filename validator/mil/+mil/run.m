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
        if ~isempty(opt.filter) ...
                && isempty(regexp(fn, regexptranslate('wildcard', opt.filter), 'once'))
            continue
        end
        if opt.verbose, fprintf('  [%-10s] %-44s ', suite, fn); end
        snap = val.snapshot_ws();
        t0 = tic;
        try
            r = feval(fn);
        catch ME
            r = val.new_result(string(suite), string(fn), string(fn), "");
            r.status = "error";
            r.error  = string(ME.message);
            fprintf(2, '\n    ERROR: %s\n', getReport(ME, 'extended'));
        end
        r.duration_s = toc(t0);
        if isempty(r.suite) || r.suite == "", r.suite = string(suite); end
        val.restore_ws(snap);
        if opt.verbose, fprintf('%-7s  (%.2fs)\n', upper(r.status), r.duration_s); end
        results(end+1, 1) = r; %#ok<AGROW>
    end
end

report.timestamp = string(datetime('now','Format','yyyyMMdd_HHmmss'));
report.suite     = "mil";
report.summary   = val.summarize(results);
report.results   = results;

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
val.export_json(report, opt.outFile);
if ~customOut
    val.export_json(report, fullfile(repDir, 'MIL.json'));
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
    bar([[ps.pass]', [ps.fail]', [ps.error]'], 'stacked');
    set(gca, 'XTickLabel', cellstr([ps.suite]));
    legend({'pass','fail','error'}, 'Location','northeast');
    ylabel('tests'); title(sprintf('MIL summary  -  %d pass / %d total', report.summary.pass, report.summary.total));
    grid on;
    exportgraphics(fig, fullfile(plotDir, 'summary.png'), 'Resolution', 120);
    close(fig);
    fprintf('Plot  : %s\n', fullfile(plotDir, 'summary.png'));
catch ME
    warning('mil:run:plot', 'summary plot failed: %s', ME.message);
end
end
