function build(mdl)
% pil.build  Configure mdl + every model it references for top-model PIL
% on the STM32 Nucleo-H743ZI, then trigger a build (which also flashes
% the .elf to the board via STM32CubeProgrammer). Idempotent.
%
%   pil.build('bms_master')

if nargin < 1
    error('pil:build:noModel', 'Usage: pil.build(modelname)');
end

scriptDir = fileparts(mfilename('fullpath'));      % validator/pil/+pil
pilRoot   = fileparts(scriptDir);                  % validator/pil
valRoot   = fileparts(pilRoot);                    % validator
proj      = fileparts(valRoot);

% Make sure the model parameters (T_stop, bms.*, FP_TARGET, ...) live in
% the base workspace before any load_system / build runs.
if evalin('base', '~exist(''bms'',''var'')')
    initFile = fullfile(proj, 'model', 'system', 'params', 'init_system.m');
    evalin('base', sprintf('run(''%s'')', initFile));
end

% Wipe any stale shared utilities so we don't inherit SIL host settings.
slprj = fullfile(pwd, 'slprj');
if exist(slprj, 'dir'); rmdir(slprj, 's'); end
delete(fullfile(pwd, '*.slxc'));

pil.configure(mdl);

fprintf('Building PIL target for %s ... ', mdl);
t0 = tic;
simIn = Simulink.SimulationInput(mdl);
simIn = simIn.setModelParameter('SimulationMode', 'processor-in-the-loop');
simIn = simIn.setModelParameter('StopTime',       '0');
% Belt + suspenders: cov knobs are also forced off in pil.configure but
% the build sim is the single most likely place to trip the
% "profiling + coverage" Embedded Coder check.
simIn = simIn.setModelParameter('CovEnable',         'off');
simIn = simIn.setModelParameter('CovModelRefEnable', 'off');
buildLog = evalc('sim(simIn);');
fprintf('done (%.1fs)\n', toc(t0));
if any(contains(string(buildLog), ["error", "Error"]))
    fprintf(2, '%s\n', buildLog);
end
end
