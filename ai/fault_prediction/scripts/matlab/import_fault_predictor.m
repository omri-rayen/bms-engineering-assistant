% import_fault_predictor.m  --  ONNX -> native dlnetwork for the Simulink Predict block.
%
% Reads:
%   model/fault_predictor/inference/fault_predictor.onnx
%   ai/fault_prediction/data/preprocessed/stats.json
%   model/fault_predictor/inference/thresholds.json
%
% Writes:
%   model/fault_predictor/inference/fault_predictor.mat   (net, thresholds)
%
% importNetworkFromONNX produces a dlnetwork that mixes built-in layers with
% auto-generated custom layers (Shape/Gather/Squeeze around the LSTM). Those
% custom layers break type propagation when the Predict block is referenced
% from system_model and are not codegen-friendly for SIL/PIL.
%
% This script imports the ONNX once, then rebuilds an idiomatic dlnetwork
% from scratch using only built-in layers, copying the LSTM/FC weights and
% the z-score (mu, sig) from the import. The result is fully codegen-able.

here     = fileparts(mfilename('fullpath'));                            % ai/fault_prediction/scripts/matlab
aiRoot   = fileparts(fileparts(fileparts(here)));                       % ai/
projRoot = fileparts(aiRoot);                                           % repo root
fpInf    = fullfile(projRoot, 'model', 'fault_predictor', 'inference');

onnxFn = fullfile(fpInf, 'fault_predictor.onnx');
matFn  = fullfile(fpInf, 'fault_predictor.mat');
thrFn  = fullfile(fpInf, 'thresholds.json');
stFn   = fullfile(projRoot, 'ai', 'fault_prediction', 'data', 'preprocessed', 'stats.json');

assert(isfile(onnxFn), 'Missing %s -- run export_onnx.py first.', onnxFn);
assert(isfile(thrFn),  'Missing %s.', thrFn);
assert(isfile(stFn),   'Missing %s -- run preprocess.py first.', stFn);

%% Import ONNX as scratch -- we only need its weight tensors.
% importNetworkFromONNX writes a +<PackageName> folder of auto-generated
% custom layers into the current directory. We discard those layers
% (only LSTM/FC weights are kept), so route the package into a temp dir
% to avoid littering the repo.
tmpPkgDir = fullfile(tempdir, 'fp_onnx_import');
if ~isfolder(tmpPkgDir), mkdir(tmpPkgDir); end
oldCd = cd(tmpPkgDir);
cleanupCd = onCleanup(@() cd(oldCd));
imported = importNetworkFromONNX(onnxFn, ...
        'InputDataFormats',  "BTC", ...
        'OutputDataFormats', "BC");
if ~imported.Initialized
    imported = initialize(imported);
end
clear cleanupCd
cd(oldCd);

stats = jsondecode(fileread(stFn));
F     = numel(stats.mean);
W     = stats.W;
mu    = single(stats.mean(:));
sig   = single(stats.std(:));

% Pull the trained tensors out of the imported graph (layer indices match
% the network printed by `summary(imported)`).
lstm = imported.Layers(8);     % LSTMLayer
fc1  = imported.Layers(10);    % FullyConnectedLayer (H -> 16)
fc2  = imported.Layers(12);    % FullyConnectedLayer (16 -> C)
H = lstm.NumHiddenUnits;
C = numel(fc2.Bias);

%% Build a clean dlnetwork using only built-in layers
layers = [
    sequenceInputLayer(F, ...
        'Name', 'window', ...
        'Normalization', 'zscore', ...
        'Mean', mu, ...
        'StandardDeviation', sig, ...
        'MinLength', W)
    lstmLayer(H, 'Name', 'lstm', 'OutputMode', 'last')
    fullyConnectedLayer(numel(fc1.Bias), 'Name', 'dense')
    reluLayer('Name', 'relu')
    fullyConnectedLayer(C, 'Name', 'head')
    sigmoidLayer('Name', 'probOutput')   % name kept for the Simulink Predict block port
];
net = dlnetwork(layers, 'Initialize', false);

% Copy trained weights
net = setLearnable(net, 'lstm',  'InputWeights',     lstm.InputWeights);
net = setLearnable(net, 'lstm',  'RecurrentWeights', lstm.RecurrentWeights);
net = setLearnable(net, 'lstm',  'Bias',             lstm.Bias);
net = setLearnable(net, 'dense', 'Weights',          fc1.Weights);
net = setLearnable(net, 'dense', 'Bias',             fc1.Bias);
net = setLearnable(net, 'head',  'Weights',          fc2.Weights);
net = setLearnable(net, 'head',  'Bias',             fc2.Bias);

net = initialize(net);

%% Sanity check on a zero window (probabilities must lie in [0,1])
y = extractdata(predict(net, dlarray(zeros(F, W, 'single'), 'CT')));
assert(all(y(:) >= 0 & y(:) <= 1), 'Predict output outside [0,1].');
fprintf('Zero-window probs (OT, OV, UV) = [%.4f %.4f %.4f]\n', y);

%% Thresholds for the alarm comparator block
T = jsondecode(fileread(thrFn));
thresholds = single(T.thresholds(:));    % 3x1

save(matFn, 'net', 'thresholds');
fprintf('Saved %s\n', matFn);
fprintf('  input  : sequence [%d x %d]  (CT)\n', F, W);
fprintf('  output : vector   [%d x 1]   (CB)\n', C);

%% Patch fault_predictor.slx so its MLFB calls predict() directly.
% The library Predict block's helper (deep.blocks.internal.deepNetwork) does
% not propagate types correctly when the model is referenced from system_model.
% We replace its inner script with a plain codegen-friendly predict() call.
patch_slx(matFn, projRoot);


function net = setLearnable(net, layerName, paramName, value)
% Overwrite one entry in net.Learnables.
    idx = find(strcmp(net.Learnables.Layer, layerName) & ...
               strcmp(net.Learnables.Parameter, paramName), 1);
    assert(~isempty(idx), 'Learnable %s/%s not found.', layerName, paramName);
    net.Learnables.Value{idx} = dlarray(single(value));
end


function patch_slx(matFn, projRoot)
% Update fault_predictor.slx so its inner MLFB loads our .mat and calls
% predict() directly. Runs idempotently.
    mdl = 'fault_predictor';
    load_system(fullfile(projRoot, 'model', 'fault_predictor', 'models', mdl));

    % Break the library link the first time so we can edit the inner chart.
    blk = [mdl '/Predict'];
    if ~strcmp(get_param(blk, 'LinkStatus'), 'none')
        set_param(blk, 'LinkStatus', 'inactive');
        set_param(blk, 'LinkStatus', 'none');
    end

    % After breaking the link the Deep Learning Toolbox leaves callbacks on
    % the block (InitFcn, OpenFcn, etc.) that call into deep.blocks.internal.
    % Clear them so they don't fire asynchronously during save/close and
    % produce spurious "Unrecognized field name 'internal'" errors.
    for cb = {'InitFcn','OpenFcn','CloseFcn','PreSaveFcn','PostSaveFcn'}
        try, set_param(blk, cb{1}, ''); catch, end
    end

    matStr = strrep(matFn, '\', '\\');

    sf = sfroot;

    % Inner predictor: [F x T] window -> [C] probabilities
    m = sf.find('-isa', 'Stateflow.EMChart', 'Path', [mdl '/Predict/Predict/MLFB']);
    assert(numel(m) == 1, 'Expected exactly one MLFB chart at %s/Predict/Predict/MLFB, found %d.', mdl, numel(m));
    m.Script = sprintf([ ...
'function p = deepNetwork(window)\n' ...
'%%#codegen\n' ...
'persistent net\n' ...
'if isempty(net)\n' ...
'    net = coder.loadDeepLearningNetwork(''%s'', ''fault_predictor'');\n' ...
'end\n' ...
'y = predict(net, dlarray(single(window), ''CT''));\n' ...
'p = single(extractdata(y));\n' ...
'end'], matStr);

    % Windower: 1x8 sample -> [F x T] window
    mw = sf.find('-isa', 'Stateflow.EMChart', 'Path', [mdl '/MATLAB Function']);
    mw.Script = [ ...
'function W = sliding_window(u)' newline ...
'%#codegen' newline ...
'persistent buf' newline ...
'if isempty(buf)' newline ...
'    buf = zeros(8, 50, ''single'');' newline ...
'end' newline ...
'buf = [buf(:, 2:end), single(u(:))];' newline ...
'W = buf;' newline ...
'end'];

    save_system(mdl);
    drawnow;                             % flush any pending Simulink events
    try, close_system(mdl, 0); catch, end   % close is best-effort; save already happened
    fprintf('Patched %s.slx\n', mdl);
end
