function out = run(varargin)
% orch.run -- run the BMS validation pipeline end-to-end.
%
% Drives MIL/SIL/PIL (selectable). When MIL is selected, dead-code
% coverage (cov) runs automatically right after. Then ana.collect ->
% python analyzer -> python doc_generator.

p = inputParser;
p.addParameter('paths',       {'mil','sil','pil'});
% mil_filter accepts a single wildcard string OR a cellstr of wildcards
% (multi-select scenarios from the UI). Empty / '' means "all".
p.addParameter('mil_filter',  '');
p.addParameter('sil_filter',  '');
p.addParameter('pil_filter',  '');
p.addParameter('mil_suites',  {});
p.addParameter('skip_build',  false, @islogical);
p.addParameter('do_cov',      true,  @islogical);
p.addParameter('do_analyzer', true,  @islogical);
p.addParameter('do_doc',      true,  @islogical);
p.addParameter('log_cb',      []);
p.addParameter('progress_cb', []);
p.addParameter('api_key',     '');
p.parse(varargin{:});
opt = p.Results;
opt.mil_filter = local_norm_filter(opt.mil_filter);

repo = orch.repo_root();
log  = @(s) local_log(opt.log_cb, s);
prog = @(name, f) local_progress(opt.progress_cb, name, f);

if evalin('base', '~exist(''bms'',''var'')')
    log('[orch] loading init_system.m');
    evalin('base', sprintf('run(''%s'')', ...
        fullfile(repo,'model','system','params','init_system.m')));
end

phases = local_plan(opt, repo);
total_w = sum(cellfun(@(ph) ph.weight, phases));
if total_w == 0, total_w = 1; end

out = struct('paths', struct(), 'summary', struct(), 'ok', false, ...
             'html', '', 'json', '', 'ts', '');

t0 = tic;
log(sprintf('[orch] %s pipeline start (%d phases)', ...
            char(datetime('now','Format','HH:mm:ss')), numel(phases)));

cum_w = 0;
counters = containers.Map('KeyType','char','ValueType','double');
for k = 1:numel(phases)
    ph = phases{k};
    base_frac = cum_w / total_w;
    next_frac = (cum_w + ph.weight) / total_w;
    prog(ph.name, base_frac);
    log(sprintf('[orch] === phase %d/%d : %s ===', k, numel(phases), ph.name));

    counters(ph.name) = 0;
    sub_cb = @(info) local_subprogress(prog, log, counters, ph.name, ...
                                       base_frac, next_frac, ph.test_count, info);
    try
        % phase_mil also drives the synthetic 'cov' chip, so it needs
        % direct access to the progress callback. The other phases ignore
        % the extra arg.
        out.paths.(ph.name) = ph.fcn(opt, repo, log, sub_cb, prog);
    catch ME
        log(sprintf('[orch] %s FAILED: %s', ph.name, ME.message));
        out.error      = ME.message;
        out.failed_phase = ph.name;
        out.elapsed_s  = toc(t0);
        prog('error', next_frac);
        return
    end
    cum_w = cum_w + ph.weight;
    prog(ph.name, next_frac);
end

prog('done', 1);
out.ok        = true;
out.summary   = local_summary(out.paths);
out.elapsed_s = toc(t0);
log(sprintf('[orch] pipeline OK in %.1f s', out.elapsed_s));

if isfield(out.paths, 'doc')
    out.html = out.paths.doc.html;
    out.json = out.paths.doc.json;
    out.ts   = out.paths.doc.ts;
end
end

% ----------------------------------------------------------------- planning
function phases = local_plan(opt, repo)
phases = {};
ran_mil = false;

if any(strcmp(opt.paths, 'mil'))
    n = local_count_tests(fullfile(repo,'validator','mil','tests','bms'),       opt.mil_filter) ...
      + local_count_tests(fullfile(repo,'validator','mil','tests','predictor'), opt.mil_filter);
    phases{end+1} = struct('name','mil', 'fcn', @phase_mil, ...
                           'weight', max(n,1)*4, 'test_count', max(n,1)); %#ok<*AGROW>
    ran_mil = true;
end
if any(strcmp(opt.paths, 'sil'))
    n = local_count_tests(fullfile(repo,'validator','sil','tests'), opt.sil_filter);
    w = max(n,1)*4 + (~opt.skip_build) * 30;
    phases{end+1} = struct('name','sil', 'fcn', @phase_sil, ...
                           'weight', w, 'test_count', max(n,1));
end
if any(strcmp(opt.paths, 'pil'))
    n = local_count_tests(fullfile(repo,'validator','pil','tests'), opt.pil_filter);
    w = max(n,1)*15 + (~opt.skip_build) * 60;
    phases{end+1} = struct('name','pil', 'fcn', @phase_pil, ...
                           'weight', w, 'test_count', max(n,1));
end
% Coverage is collected in-line during the MIL phase (single pass);
% phase_mil itself writes COV.json when opt.do_cov is true. There is
% no separate 'cov' phase any more -- the chip is driven by phase_mil.
phases{end+1} = struct('name','facts',    'fcn', @phase_facts,    'weight', 8,  'test_count',1);
if opt.do_analyzer
    phases{end+1} = struct('name','analyzer','fcn',@phase_analyzer,'weight', 6,  'test_count',1);
end
if opt.do_doc
    phases{end+1} = struct('name','doc',     'fcn',@phase_doc,     'weight', 12, 'test_count',1);
end
end

function n = local_count_tests(dirpath, filter)
n = 0;
if ~isfolder(dirpath), return, end
files = dir(fullfile(dirpath, 'test_*.m'));
if isempty(files), return, end
filter = local_norm_filter(filter);
if isempty(filter) || (iscell(filter) && any(cellfun(@isempty, filter)))
    n = numel(files);
    return
end
filters = local_filter_cell(filter);
for i = 1:numel(files)
    [~, fn] = fileparts(files(i).name);
    if local_match_any(fn, filters), n = n + 1; end
end
end

% Normalise a 'filter' parameter into a value that mil.run / sil.run /
% pil.run can consume directly. Accepts: '' | 'glob' | {'g1','g2',...}.
% Empty cells, whitespace-only entries, and the catch-all '' are
% collapsed away. Returns '' when the result is "match everything",
% a single string when only one glob remains, otherwise a cellstr.
function f = local_norm_filter(f)
if isempty(f), f = ''; return, end
if ischar(f) || isstring(f)
    f = strtrim(char(f));
    return
end
if ~iscell(f), f = ''; return, end
clean = {};
for i = 1:numel(f)
    s = strtrim(char(f{i}));
    if isempty(s), f = ''; return, end   % '' means "all" -> short-circuit
    clean{end+1} = s; %#ok<AGROW>
end
clean = unique(clean, 'stable');
if isscalar(clean), f = clean{1}; else, f = clean; end
end

function c = local_filter_cell(f)
if iscell(f), c = f; else, c = {char(f)}; end
end

function tf = local_match_any(name, filters)
tf = false;
for i = 1:numel(filters)
    re = regexptranslate('wildcard', filters{i});
    if ~isempty(regexp(name, re, 'once')), tf = true; return, end
end
end

function [filt, models] = local_cov_scope(mil_filter)
% Map a MIL filter to (cov_filter, cov_models). Empty mil_filter means
% "run all BMS MIL tests against all 3 models". A cellstr filter is
% treated as the union of its members' scopes.
filt   = '';
models = {};
if isempty(mil_filter), return, end
if iscell(mil_filter)
    fs = {};
    ms = {};
    for i = 1:numel(mil_filter)
        [fi, mi] = local_cov_scope(mil_filter{i});
        if ~isempty(fi), fs{end+1} = fi; end %#ok<AGROW>
        if ~isempty(mi), ms = [ms mi]; end %#ok<AGROW>
    end
    if ~isempty(fs), filt = unique(fs, 'stable'); end
    if isscalar(filt), filt = filt{1}; end
    models = unique(ms, 'stable');
    return
end
f = upper(mil_filter);
if startsWith(f, 'REQ_LL_PRD')
    % Predictor MIL tests live outside cov.run's testsDir; use the BMS-side
    % predictor stimulus (BMS_PRD_*) which exercises fault_predictor.
    filt   = 'REQ_LL_BMS_PRD_*';
    models = {'fault_predictor'};
    return
end
if startsWith(f, 'REQ_LL_BMS_')
    filt = mil_filter;
    if startsWith(f,'REQ_LL_BMS_VMON') || startsWith(f,'REQ_LL_BMS_TMON')
        models = {'bms_slave'};
    elseif startsWith(f,'REQ_LL_BMS_BAL')
        models = {'bms_master','bms_slave'};
    elseif startsWith(f,'REQ_LL_BMS_PRD')
        models = {'bms_master','fault_predictor'};
    else
        models = {'bms_master'};
    end
end
end

% ----------------------------------------------------------------- phases
function rep = phase_mil(opt, repo, log, on_test, prog)
suites = opt.mil_suites;
if isempty(suites)
    suites = local_suites_for_filter(opt.mil_filter);
end
[~, cov_models] = local_cov_scope(opt.mil_filter);
if isempty(cov_models)
    cov_models = {'bms_master','bms_slave','fault_predictor'};
end
log(sprintf('[mil] suites=%s filter=%s coverage=%d', ...
    strjoin(suites,','), local_filter_str(opt.mil_filter), opt.do_cov));
% Mark the COV chip 'active' (blue) for the duration of the MIL phase --
% dead-code coverage is collected in lockstep with every MIL test.
if opt.do_cov, prog('cov', 0); end
rep = mil.run('suites', suites, 'filter', opt.mil_filter, ...
    'coverage', opt.do_cov, 'cov_models', cov_models, 'on_test', on_test);

% Single-pass: mil.run captured cvdata; build & write COV.json now.
if opt.do_cov && isfield(rep,'cvdata') && ~isempty(rep.cvdata)
    try
        threshold = evalin('base', 'req.COV_dead_pct_max');
    catch
        threshold = 0;
    end
    repDir = fullfile(repo,'validator','reports');
    ts     = char(datetime('now','Format','yyyyMMdd_HHmmss'));
    outFile = fullfile(repDir, sprintf('COV_%s.json', ts));
    nP = sum(arrayfun(@(x) x.status=="pass",  rep.results));
    nE = sum(arrayfun(@(x) x.status=="error", rep.results));
    cov_rep = cov.from_cvdata(rep.cvdata, cov_models, threshold, ...
        'stimulus_n',     numel(rep.results), ...
        'stimulus_pass',  nP, ...
        'stimulus_err',   nE, ...
        'stimulus_source', "mil.run (single-pass)", ...
        'outFile', outFile, ...
        'verbose', true);
    % Sticky copy.
    sticky = fullfile(repDir, 'COV.json');
    [d, ~, ~] = fileparts(sticky);
    if ~isfolder(d), mkdir(d); end
    fid = fopen(sticky, 'w');
    fwrite(fid, jsonencode(cov_rep, 'PrettyPrint', true));
    fclose(fid);
    log(sprintf('[mil] coverage verdict: %s   dead=%.2f%%   thr=%.2f%%', ...
        upper(char(cov_rep.verdict.status)), cov_rep.verdict.dead_code_pct, ...
        cov_rep.verdict.threshold_pct));
    % Mark the COV chip 'done' (green) once the verdict has been written.
    prog('cov', 1);
end
% Strip cvdata from the orch return value (it's opaque + bulky).
if isfield(rep,'cvdata'), rep = rmfield(rep,'cvdata'); end
end

function rep = phase_sil(opt, ~, log, on_test, ~)
log(sprintf('[sil] filter=''%s'' skip_build=%d', opt.sil_filter, opt.skip_build));
rep = sil.run('skip_build', opt.skip_build, 'filter', opt.sil_filter, 'on_test', on_test);
end

function rep = phase_pil(opt, ~, log, on_test, ~)
log(sprintf('[pil] filter=''%s'' skip_build=%d', opt.pil_filter, opt.skip_build));
rep = pil.run('skip_build', opt.skip_build, 'filter', opt.pil_filter, 'on_test', on_test);
end

function rep = phase_facts(opt, repo, log, ~, ~)
[~, scope] = local_cov_scope(opt.mil_filter);
if isempty(scope)
    scope = {'bms_master','bms_slave','fault_predictor'};
end
log(sprintf('[facts] collecting static analysis facts (scope=%s)', ...
    strjoin(scope,' + ')));
rep = ana.collect('models', scope, 'verbose', false);
end

function rep = phase_analyzer(~, repo, log, ~, ~)
log('[analyzer] python -m analyzer');
env = struct('PYTHONPATH', fullfile(repo,'analyzer','python'));
[rc, ~] = local_run_python(repo, 'analyzer', {}, env, log);
if rc ~= 0
    j = fullfile(repo,'analyzer','reports','ANALYSIS.json');
    if ~isfile(j)
        error('orch:analyzer:no_json','analyzer rc=%d and ANALYSIS.json missing', rc);
    end
    log(sprintf('[analyzer] rc=%d (gate verdict, ANALYSIS.json present)', rc));
end
rep = struct('analysis', fullfile(repo,'analyzer','reports','ANALYSIS.json'));
end

function rep = phase_doc(opt, repo, log, ~, ~)
log('[doc] python -m doc_generator');
env = struct();
key = opt.api_key;
if isempty(key), try, key = orch.api_key(); catch, key = ''; end, end
if isempty(key), key = getenv('LLM_API_KEY'); end
if isempty(key), key = getenv('GROQ_API_KEY'); end
extra = {};
if ~any(strcmp(opt.paths, 'mil')), extra{end+1} = '--skip-mil'; end %#ok<*AGROW>
if ~any(strcmp(opt.paths, 'sil')), extra{end+1} = '--skip-sil'; end
if ~any(strcmp(opt.paths, 'pil')), extra{end+1} = '--skip-pil'; end
if isempty(key)
    log('[doc] no API key -> running with --dry-run (JSON only)');
    extra{end+1} = '--dry-run';
else
    env.LLM_API_KEY     = key;
    env.WISGATE_API_KEY = key;
end
[rc, captured] = local_run_python(repo, 'doc_generator', extra, env, log);
if rc ~= 0
    error('orch:doc:fail','doc_generator rc=%d', rc);
end
docDir = fullfile(repo,'doc_generator','reports');
ts = local_extract_ts(captured);
if isempty(ts)
    % Fallback: take the newest FULL_REPORT_<ts>.json on disk.
    f = dir(fullfile(docDir,'FULL_REPORT_*.json'));
    if ~isempty(f)
        [~,ix] = max([f.datenum]);
        m = regexp(f(ix).name, 'FULL_REPORT_(\d{8}_\d{6})\.json', 'tokens', 'once');
        if ~isempty(m), ts = m{1}; end
    end
end
% Two-part HTML output: REPORT_PART1 (data tables) +
% REPORT_PART2 (analysis & verdict). The sticky paths are what the UI
% "Save HTML" buttons hand out; the timestamped copies are kept for
% history under list_reports().
rep = struct( ...
    'json',       fullfile(docDir,'FULL_REPORT.json'), ...
    'html_part1', fullfile(docDir,'REPORT_PART1.html'), ...
    'html_part2', fullfile(docDir,'REPORT_PART2.html'), ...
    'ts',         ts);
% Back-compat alias: a few callers still read rep.html. Point it at
% part 1 so opening it in a browser still shows a real report.
rep.html = rep.html_part1;
if ~isempty(ts)
    tj  = fullfile(docDir, sprintf('FULL_REPORT_%s.json', ts));
    th1 = fullfile(docDir, sprintf('REPORT_PART1_%s.html', ts));
    th2 = fullfile(docDir, sprintf('REPORT_PART2_%s.html', ts));
    if isfile(tj),  rep.json       = tj;  end
    if isfile(th1), rep.html_part1 = th1; rep.html = th1; end
    if isfile(th2), rep.html_part2 = th2; end
end
end

% Pick the MIL test suites that contain at least one test matching the
% requested filter. Accepts string or cellstr. Empty filter -> both
% suites. Used so a multi-select that contains only predictor scenarios
% does not waste a full bms-suite pass.
function suites = local_suites_for_filter(filter)
if isempty(filter)
    suites = {'bms','predictor'};
    return
end
if iscell(filter), fs = filter; else, fs = {char(filter)}; end
bms = false; prd = false;
for i = 1:numel(fs)
    f = upper(fs{i});
    if startsWith(f, 'REQ_LL_PRD'),     prd = true;
    elseif startsWith(f, 'REQ_LL_BMS'), bms = true;
    else,                                bms = true; prd = true;
    end
end
suites = {};
if bms, suites{end+1} = 'bms'; end
if prd, suites{end+1} = 'predictor'; end
end

function s = local_filter_str(f)
if isempty(f), s = '''(all)'''; return, end
if iscell(f), s = ['{' strjoin(f, ',') '}']; else, s = ['''' char(f) '''']; end
end

% ----------------------------------------------------------------- helpers
function [rc, captured] = local_run_python(repo, modname, extra, env, log)
cmd = sprintf('python -m %s', modname);
for i = 1:numel(extra), cmd = [cmd ' ' extra{i}]; end %#ok<AGROW>
fns = fieldnames(env);
prefix = '';
for i = 1:numel(fns)
    if ispc
        prefix = [prefix sprintf('set %s=%s && ', fns{i}, env.(fns{i}))]; %#ok<AGROW>
    else
        prefix = [prefix sprintf('%s="%s" ', fns{i}, env.(fns{i}))]; %#ok<AGROW>
    end
end
if ispc
    full = sprintf('%scd /d "%s" && %s', prefix, repo, cmd);
else
    full = sprintf('cd "%s" && %s%s', repo, prefix, cmd);
end
log(sprintf('[exec] %s', cmd));
[rc, captured] = system(full);
lines = regexp(captured, '\r?\n', 'split');
for i = 1:numel(lines)
    if ~isempty(strtrim(lines{i})), log(lines{i}); end
end
end

function ts = local_extract_ts(captured)
ts = '';
m = regexp(captured, 'FULL_REPORT_(\d{8}_\d{6})\.json', 'tokens', 'once');
if ~isempty(m), ts = m{1}; end
end

function s = local_summary(paths)
s = struct('mil',[],'sil',[],'pil',[],'cov',[]);
for fld = {'mil','sil','pil','cov'}
    f = fld{1};
    if isfield(paths, f) && isstruct(paths.(f)) && isfield(paths.(f),'summary')
        s.(f) = paths.(f).summary;
    end
end
end

function local_log(cb, s)
fprintf('%s\n', s);
if ~isempty(cb)
    try, cb(s); catch, end
end
end

function local_progress(cb, name, frac)
if ~isempty(cb)
    try, cb(name, max(0,min(1,frac))); catch, end
end
end

function local_subprogress(prog, log, counters, phase, base, next, ntests, info)
counters(phase) = counters(phase) + 1;
done = counters(phase);
frac = base + (next - base) * min(done, ntests) / max(ntests,1);
prog(phase, frac);
log(sprintf('  [%s] %d/%d %-44s %-7s (%.2fs)', ...
    phase, done, ntests, char(info.name), upper(char(info.status)), info.duration_s));
end
