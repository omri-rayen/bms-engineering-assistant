% run_full_pipeline.m -- end-to-end: preprocess -> train -> evaluate ->
% export ONNX -> import to dlnetwork + flat weights + patch slx -> PIL/MIL.
%
% Run from repo root: matlab -batch "run_full_pipeline"
here  = fileparts(mfilename('fullpath'));
proj  = here;            % this script lives at repo root
pyDir = fullfile(proj, 'ai', 'fault_prediction', 'scripts', 'python');
mlDir = fullfile(proj, 'ai', 'fault_prediction', 'scripts', 'matlab');

cd(proj);
addpath(genpath(fullfile(proj, 'validator')));
addpath(genpath(fullfile(proj, 'model')));

t0 = tic;
fprintf('\n========== [1/5] preprocess.py ==========\n');
runPy(pyDir, 'preprocess.py');

fprintf('\n========== [2/5] train.py ==========\n');
runPy(pyDir, 'train.py');

fprintf('\n========== [3/5] evaluate.py ==========\n');
runPy(pyDir, 'evaluate.py');

fprintf('\n========== [4/5] export_onnx.py ==========\n');
runPy(pyDir, 'export_onnx.py');

fprintf('\n========== [5/5] import_fault_predictor.m ==========\n');
old = cd(mlDir);
oc  = onCleanup(@() cd(old));
import_fault_predictor;
clear oc

fprintf('\n========== Pipeline OK in %.1f s ==========\n', toc(t0));


function runPy(pyDir, script)
    cmd = sprintf('python "%s"', fullfile(pyDir, script));
    [s, out] = system(cmd, '-echo');
    if s ~= 0
        error('Python script %s failed (exit=%d).', script, s);
    end
    fprintf('%s -> exit 0 (%d chars)\n', script, numel(out));
end
