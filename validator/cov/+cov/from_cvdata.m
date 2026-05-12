function report = from_cvdata(cvAll, scope, threshold, varargin)
% cov.from_cvdata  Build a coverage verdict report from cvdata that has
% already been collected by an external test loop (typically mil.run in
% single-pass MIL+coverage mode). Pure function -- does not run any
% tests.
%
%   report = cov.from_cvdata(cvAll, scope, threshold)
%   report = cov.from_cvdata(cvAll, scope, threshold, ...
%                'stimulus_n', N, 'stimulus_pass', NP, 'stimulus_err', NE, ...
%                'outFile', path)
%
% Inputs:
%   cvAll      - cell array of cvdata objects collected during stimulus.
%   scope      - cellstr of model names that need a verdict.
%   threshold  - dead-code percentage allowed (e.g. req.COV_dead_pct_max).

p = inputParser;
p.addParameter('stimulus_n',     0);
p.addParameter('stimulus_pass',  0);
p.addParameter('stimulus_err',   0);
p.addParameter('stimulus_source', "");
p.addParameter('outFile',        '');
p.addParameter('verbose',        true);
p.parse(varargin{:});
opt = p.Results;

if isempty(cvAll)
    error('cov:from_cvdata:noData', 'No coverage data was collected.');
end

% Merge into one cvdata per root model. The `+` overload only accepts
% cvdata sharing a root, so heterogeneous samples land in separate groups.
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

byModel = cov.collect(groups, scope);

result = val.new_result("cov", "COV-DEAD-01", ...
    "BMS dead-code coverage (model level)", "REQ-LL-COV-DEAD-01");

worst = 0;
for i = 1:numel(scope)
    m  = scope{i};
    mt = byModel.(m).execution;
    if mt.total == 0, continue, end
    ok = mt.dead_pct <= threshold;
    result = val.check(result, ...
        sprintf('%s_exec_dead_pct', m), ok, ...
        sprintf('%.2f%% dead (%d/%d unexecuted blocks)', ...
            mt.dead_pct, mt.total - mt.covered, mt.total), ...
        mt.dead_pct, threshold);
    if mt.dead_pct > worst, worst = mt.dead_pct; end
end

worst_dec = 0; worst_cond = 0; worst_mcdc = 0;
for i = 1:numel(scope)
    m = scope{i};
    if byModel.(m).decision.total  > 0, worst_dec  = max(worst_dec,  byModel.(m).decision.dead_pct);  end
    if byModel.(m).condition.total > 0, worst_cond = max(worst_cond, byModel.(m).condition.dead_pct); end
    if byModel.(m).mcdc.total      > 0, worst_mcdc = max(worst_mcdc, byModel.(m).mcdc.dead_pct);      end
end

result.metrics.dead_code_pct      = worst;
result.metrics.threshold          = threshold;
result.metrics.info_dec_dead_pct  = worst_dec;
result.metrics.info_cond_dead_pct = worst_cond;
result.metrics.info_mcdc_dead_pct = worst_mcdc;

report = struct();
report.timestamp = string(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
report.suite     = "cov";
report.scope     = string(scope);
report.stimulus  = struct( ...
    'source',  string(opt.stimulus_source), ...
    'n_tests', opt.stimulus_n, ...
    'n_pass',  opt.stimulus_pass, ...
    'n_error', opt.stimulus_err);
report.summary  = val.summarize(result);
report.by_model = byModel;
report.verdict  = struct( ...
    'dead_code_pct',      worst, ...
    'threshold_pct',      threshold, ...
    'info_dec_dead_pct',  worst_dec, ...
    'info_cond_dead_pct', worst_cond, ...
    'info_mcdc_dead_pct', worst_mcdc, ...
    'status',             result.status);
report.results  = result;

if ~isempty(opt.outFile)
    [d, ~, ~] = fileparts(opt.outFile);
    if ~isempty(d) && ~isfolder(d), mkdir(d); end
    fid = fopen(opt.outFile, 'w');
    if fid < 0, error('cov:from_cvdata:write', 'cannot open %s', opt.outFile); end
    c = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fwrite(fid, jsonencode(report, 'PrettyPrint', true));
end

if opt.verbose
    fprintf('\n=== COVERAGE SUMMARY ===\n');
    fprintf('Stimulus: %d tests  (pass=%d  err=%d)\n', ...
        opt.stimulus_n, opt.stimulus_pass, opt.stimulus_err);
    for i = 1:numel(scope)
        m  = scope{i};
        md = byModel.(m);
        fprintf('  %-16s exec=%5.1f%%  dec=%5.1f%%  cond=%5.1f%%  mcdc=%5.1f%%\n', ...
            m, md.execution.coverage_pct, md.decision.coverage_pct, ...
            md.condition.coverage_pct, md.mcdc.coverage_pct);
    end
    fprintf('Worst dead-code: %.2f%%   threshold: %.2f%%   verdict: %s\n', ...
        worst, threshold, upper(report.verdict.status));
    fprintf('  (informational) dec=%.1f%%  cond=%.1f%%  mcdc=%.1f%%\n', ...
        worst_dec, worst_cond, worst_mcdc);
    if ~isempty(opt.outFile)
        fprintf('Report: %s\n', opt.outFile);
    end
end
end
