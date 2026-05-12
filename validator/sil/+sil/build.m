function build(mdl)
% Configure mdl (and all referenced models) for top-model SIL with the
% Embedded Coder ert.tlc target, then trigger a build by simulating one
% step. Idempotent -- subsequent calls reuse the cached SIL artifacts.
%
%   sil.build('bms_master')
if nargin < 1
    error('sil:build:noModel', 'Usage: sil.build(modelname)');
end
load_system(mdl);

% Wipe stale shared utilities and Simulink cache so we don't inherit
% PIL/ARM settings from a prior pil.build run.
slprj = fullfile(pwd, 'slprj');
if exist(slprj, 'dir'); rmdir(slprj, 's'); end
delete(fullfile(pwd, '*.slxc'));

% Apply ert.tlc + host prod hardware to the top model AND every model it
% references; the build refuses to mix system target files in one tree.
refs = find_mdlrefs(mdl, 'AllLevels', true, ...
    'MatchFilter', @Simulink.match.allVariants);
refs = [refs(:); {mdl}];
for i = 1:numel(refs)
    m = refs{i};
    load_system(m);
    set_param(m, 'SystemTargetFile',  'ert.tlc');
    set_param(m, 'TargetLang',        'C');
    set_param(m, 'GenerateReport',    'off');
    set_param(m, 'HardwareBoard',     'None');
    set_param(m, 'ProdHWDeviceType',  'Intel->x86-64 (Windows64)');
    set_param(m, 'TargetHWDeviceType','Intel->x86-64 (Windows64)');
    % MIL coverage may have left CovEnable on; SIL/PIL builds refuse to
    % mix coverage with profiling and the saved .slx may carry it too.
    try, set_param(m, 'CovEnable',      'off'); catch, end %#ok<CTCH>
    try, set_param(m, 'RecordCoverage', 'off'); catch, end %#ok<CTCH>
end

fprintf('Building SIL target for %s ... ', mdl);
t0 = tic;
simIn = Simulink.SimulationInput(mdl);
simIn = simIn.setModelParameter('SimulationMode', 'software-in-the-loop');
simIn = simIn.setModelParameter('StopTime', '0');
buildLog = evalc('sim(simIn);');
fprintf('done (%.1fs)\n', toc(t0));
if nargout > 0 || any(contains(string(buildLog), ["error", "Error"]))
    % Surface log on suspicion of error.
    fprintf(2, '%s\n', buildLog);
end
% The SIL build dirties the model (storage class / target tweaks). Clear
% the Dirty flag so subsequent PIL find_mdlrefs / build does not warn
% about "unsaved changes".
for i = 1:numel(refs)
    try, set_param(refs{i}, 'Dirty', 'off'); catch, end %#ok<CTCH>
end
end
