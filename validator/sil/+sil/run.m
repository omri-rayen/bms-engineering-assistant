function report = run(varargin)
% Run the SIL validation suite and write a JSON report.
%   sil.run                 % discover validator/sil/tests/test_*.m
%   sil.run('skip_build', true)
%   sil.run('mdl', 'bms_master')

p = inputParser;
p.addParameter('mdl',       'bms_master');
p.addParameter('skip_build', false);
p.addParameter('filter',    '');
p.addParameter('verbose',   true);
p.addParameter('outFile',   '');
p.addParameter('testsRoot', '');
p.addParameter('on_test',   []);
p.parse(varargin{:});
opt = p.Results;

here    = fileparts(mfilename('fullpath'));
silRoot = fileparts(here);
valRoot = fileparts(silRoot);
proj    = fileparts(valRoot);

testsRoot = opt.testsRoot;
if isempty(testsRoot), testsRoot = fullfile(silRoot, 'tests'); end
repDir = fullfile(valRoot, 'reports');
if ~isfolder(repDir), mkdir(repDir); end

if evalin('base', '~exist(''bms'',''var'')')
    initFile = fullfile(proj, 'model', 'system', 'params', 'init_system.m');
    evalin('base', sprintf('run(''%s'')', initFile));
end

if opt.skip_build
    fprintf('[sil] skip_build=1 -> reusing existing SIL artifacts (no rtwbuild)\n');
else
    fprintf('[sil] skip_build=0 -> running sil.build(%s) (rebuild)\n', opt.mdl);
    sil.build(opt.mdl);
end

results = repmat(val.new_result("","","",""), 0, 1);
files = dir(fullfile(testsRoot, 'test_*.m'));
for f = 1:numel(files)
    [~, fn] = fileparts(files(f).name);
    if ~isempty(opt.filter) ...
            && isempty(regexp(fn, regexptranslate('wildcard', opt.filter), 'once'))
        continue
    end
    if opt.verbose, fprintf('  [sil] %-44s ', fn); end
    snap = val.snapshot_ws();
    setappdata(0, 'val_last_sims', {});
    t0 = tic;
    captured = '';
    try
        captured = evalc('r = feval(fn);');
    catch ME
        if ~isempty(captured), fprintf(2, '%s\n', captured); end
        r = val.new_result("sil", string(fn), string(fn), "");
        r.status = "error";
        r.error  = string(ME.message);
        fprintf(2, '\n    ERROR: %s\n', getReport(ME, 'extended'));
    end
    r.duration_s = toc(t0);
    if isempty(r.suite) || r.suite == "", r.suite = "sil"; end
    val.restore_ws(snap);
    if opt.verbose, fprintf('%-7s  (%.2fs)\n', upper(r.status), r.duration_s); end
    results(end+1, 1) = r; %#ok<AGROW>
    if ~isempty(opt.on_test)
        try, opt.on_test(struct('suite',"sil",'name',string(fn),'status',string(r.status),'duration_s',r.duration_s)); catch, end
    end
end

report.timestamp = string(datetime('now','Format','yyyyMMdd_HHmmss'));
report.suite     = "sil";
report.summary   = val.summarize(results);
report.results   = results;

customOut = ~isempty(opt.outFile);
if ~customOut
    opt.outFile = fullfile(repDir, sprintf('SIL_%s.json', report.timestamp));
end
val.export_json(report, opt.outFile);
if ~customOut
    val.export_json(report, fullfile(repDir, 'SIL.json'));
end

fprintf('\n=== SIL VALIDATION SUMMARY ===\n');
fprintf('Total: %d  pass: %d  fail: %d  error: %d  skipped: %d\n', ...
    report.summary.total, report.summary.pass, report.summary.fail, ...
    report.summary.error, report.summary.skipped);
fprintf('Report: %s\n', opt.outFile);
end
