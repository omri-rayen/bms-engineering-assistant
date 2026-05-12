function facts = collect(varargin)
% ana.collect -- Static metrics collection for the smart-BMS models.
%
% Walks bms_master, bms_slave and fault_predictor with Simulink + Stateflow
% APIs and writes the result to analyzer/reports/FACTS_<timestamp>.json
% (plus a sticky FACTS.json). The output is the fact base consumed by the
% Python expert system in analyzer/python/.
%
%   facts = ana.collect
%   facts = ana.collect('models', {'bms_master'})
%   facts = ana.collect('outFile', 'path/to.json')
%   facts = ana.collect('verbose', false)

p = inputParser;
p.addParameter('models',  {'bms_master', 'bms_slave', 'fault_predictor'});
p.addParameter('outFile', '');
p.addParameter('verbose', true);
p.parse(varargin{:});
opt = p.Results;

here    = fileparts(mfilename('fullpath'));   % analyzer/+ana
anaRoot = fileparts(here);                    % analyzer
proj    = fileparts(anaRoot);
repDir  = fullfile(anaRoot, 'reports');
if ~isfolder(repDir), mkdir(repDir); end

facts = struct();
facts.schema_version = "1.0";
facts.timestamp      = string(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
facts.scope          = string(opt.models);
facts.models         = struct();

% Silence the Simulink R2024b deprecation warning about find_system without
% the 'Variants' argument. Every analyzer probe is read-only and we already
% pass MatchFilter where it matters (find_mdlrefs in metrics_static); the
% remaining find_system calls intentionally look at active variants only.
warnId = 'Simulink:Commands:FindSystemVariantsOptionRemoval';
prevWarn = warning('off', warnId);
warnGuard = onCleanup(@() warning(prevWarn)); %#ok<NASGU>

for i = 1:numel(opt.models)
    mdl = opt.models{i};
    if opt.verbose, fprintf('  [ana ] %-20s ', mdl); end
    t0 = tic;

    wasLoaded = bdIsLoaded(mdl);
    wasDirty  = false;
    if wasLoaded, wasDirty = strcmp(get_param(mdl, 'Dirty'), 'on'); end
    load_system(mdl);

    m = struct();
    m.static    = ana.metrics_static(mdl);
    m.stateflow = ana.metrics_stateflow(mdl);
    m.solver    = ana.metrics_solver(mdl);
    m.codegen   = ana.metrics_codegen(proj, mdl);
    m.signals   = ana.metrics_signals(mdl);
    m.rates     = ana.metrics_rates(mdl);
    m.data      = ana.metrics_data(mdl);
    m.codeblock = ana.metrics_codeblock(mdl);
    facts.models.(mdl) = m;

    % Leave the model in the state we found it (don't add a dirty flag).
    if ~wasLoaded
        close_system(mdl, 0);
    elseif ~wasDirty
        try, set_param(mdl, 'Dirty', 'off'); catch, end %#ok<CTCH>
    end

    if opt.verbose
        fprintf('blocks=%-4d depth=%-2d cyclo=%-3d  (%.1fs)\n', ...
            m.static.block_count, m.static.depth_max, ...
            m.static.cyclomatic, toc(t0));
    end
end

% Cross-references to the validator outputs the expert system also reads.
facts.links = struct( ...
    'requirements', "validator/requirements/requirements.json", ...
    'cov_report',   "validator/reports/COV.json", ...
    'mil_report',   "validator/reports/MIL.json", ...
    'sil_report',   "validator/reports/SIL.json", ...
    'pil_report',   "validator/reports/PIL.json");

custom = ~isempty(opt.outFile);
if ~custom
    opt.outFile = fullfile(repDir, sprintf('FACTS_%s.json', facts.timestamp));
end
ana.write_json(facts, opt.outFile);
if ~custom
    ana.write_json(facts, fullfile(repDir, 'FACTS.json'));
end

if opt.verbose
    fprintf('Facts: %s\n', opt.outFile);
end
end
