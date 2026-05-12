% import_fault_predictor.m -- ONNX -> dlnetwork + flat weights + patch slx.
% Reads  : fault_predictor.onnx, stats.json, thresholds.json
% Writes : fault_predictor.mat (reference net), fault_predictor_weights.mat (codegen)

here     = fileparts(mfilename('fullpath'));
aiRoot   = fileparts(fileparts(fileparts(here)));
projRoot = fileparts(aiRoot);
fpInf    = fullfile(projRoot, 'model', 'fault_predictor', 'inference');

onnxFn  = fullfile(fpInf, 'fault_predictor.onnx');
matFn   = fullfile(fpInf, 'fault_predictor.mat');
wtFn    = fullfile(fpInf, 'fault_predictor_weights.mat');
thrInf  = fullfile(fpInf, 'thresholds.json');
thrTrn  = fullfile(projRoot, 'ai', 'fault_prediction', 'models', 'thresholds.json');
stFn    = fullfile(projRoot, 'ai', 'fault_prediction', 'data', 'preprocessed', 'stats.json');

assert(isfile(onnxFn), 'Missing %s -- run export_onnx.py first.', onnxFn);
assert(isfile(stFn),   'Missing %s -- run preprocess.py first.', stFn);
% sync latest thresholds from training output
if isfile(thrTrn)
    copyfile(thrTrn, thrInf);
end
assert(isfile(thrInf), 'Missing thresholds.json -- run train.py first.');
thrFn = thrInf;

%% Import ONNX
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
mu    = single(stats.mean(:));
sig   = single(stats.std(:));

% layer indices match summary(imported)
lstm = imported.Layers(8);     % LSTMLayer
fc1  = imported.Layers(10);    % FC (H -> 16)
fc2  = imported.Layers(12);    % FC (16 -> C)
H = lstm.NumHiddenUnits;
C = numel(fc2.Bias);

%% Reference dlnetwork (offline predict / debug)
layers = [
    sequenceInputLayer(F, ...
        'Name', 'window', ...
        'Normalization', 'zscore', ...
        'Mean', mu, ...
        'StandardDeviation', sig, ...
        'MinLength', 1)
    lstmLayer(H, 'Name', 'lstm', 'OutputMode', 'last')
    fullyConnectedLayer(numel(fc1.Bias), 'Name', 'dense')
    reluLayer('Name', 'relu')
    fullyConnectedLayer(C, 'Name', 'head')
    sigmoidLayer('Name', 'probOutput')
];
net = dlnetwork(layers, 'Initialize', false);

net = setLearnable(net, 'lstm',  'InputWeights',     lstm.InputWeights);
net = setLearnable(net, 'lstm',  'RecurrentWeights', lstm.RecurrentWeights);
net = setLearnable(net, 'lstm',  'Bias',             lstm.Bias);
net = setLearnable(net, 'dense', 'Weights',          fc1.Weights);
net = setLearnable(net, 'dense', 'Bias',             fc1.Bias);
net = setLearnable(net, 'head',  'Weights',          fc2.Weights);
net = setLearnable(net, 'head',  'Bias',             fc2.Bias);
net = initialize(net);

T = jsondecode(fileread(thrFn));
thresholds = single(T.thresholds(:));
fault_predictor = net;                          %#ok<NASGU>
save(matFn, 'fault_predictor', 'thresholds');
fprintf('Saved %s\n', matFn);

%% Flat weight bundle (codegen)
w = struct();
w.norm_mean = mu;                                % F x 1
w.norm_std  = sig;                               % F x 1
w.Wi   = single(lstm.InputWeights);              % 4H x F  (gates: i,f,g,o stacked)
w.Wr   = single(lstm.RecurrentWeights);          % 4H x H
w.bL   = single(lstm.Bias);                      % 4H x 1
w.Wfc1 = single(fc1.Weights);                    % 16 x H
w.bfc1 = single(fc1.Bias(:));                    % 16 x 1
w.Wfc2 = single(fc2.Weights);                    % C x 16
w.bfc2 = single(fc2.Bias(:));                    % C x 1
w.H    = int32(H);
w.C    = int32(C);
save(wtFn, '-struct', 'w');
fprintf('Saved %s\n', wtFn);

%% Equivalence check: hand-coded LSTM vs dlnetwork (50 steps)
rng(42);
xs = 0.1 * randn(F, 50, 'single');
y_ref = single(extractdata(predict(net, dlarray(xs, 'CT'))));

h = zeros(H, 1, 'single');
c = zeros(H, 1, 'single');
for t = 1:size(xs, 2)
    x  = (xs(:, t) - w.norm_mean) ./ w.norm_std;
    z  = w.Wi * x + w.Wr * h + w.bL;
    ig = single(1) ./ (single(1) + exp(-z(1:H)));
    fg = single(1) ./ (single(1) + exp(-z(H+1:2*H)));
    gg = tanh(z(2*H+1:3*H));
    og = single(1) ./ (single(1) + exp(-z(3*H+1:4*H)));
    c  = fg .* c + ig .* gg;
    h  = og .* tanh(c);
end
y1 = max(w.Wfc1 * h + w.bfc1, single(0));
y2 = w.Wfc2 * y1 + w.bfc2;
y_hand = single(1) ./ (single(1) + exp(-y2));

err = max(abs(y_hand - y_ref));
fprintf('Hand-coded vs dlnetwork: dlnet=[%s] hand=[%s] max|err|=%.2e\n', ...
    sprintf('%.6f ', y_ref), sprintf('%.6f ', y_hand), err);
assert(err < 1e-5, 'Hand-coded LSTM diverges from dlnetwork (err=%.2e).', err);

%% Patch fault_predictor.slx
patch_slx(wtFn, projRoot, H);


function net = setLearnable(net, layerName, paramName, value)
    idx = find(strcmp(net.Learnables.Layer, layerName) & ...
               strcmp(net.Learnables.Parameter, paramName), 1);
    assert(~isempty(idx), 'Learnable %s/%s not found.', layerName, paramName);
    net.Learnables.Value{idx} = dlarray(single(value));
end


function patch_slx(wtFn, projRoot, H)
% Update the inner MLFB chart to run stateful 1-step inference from wtFn.
    mdl    = 'fault_predictor';
    mdlDir = fullfile(projRoot, 'model', 'fault_predictor', 'models');
    load_system(fullfile(mdlDir, mdl));

    % Break library link on Predict block so we can edit the inner chart.
    blk = [mdl '/Predict'];
    if ~strcmp(get_param(blk, 'LinkStatus'), 'none')
        set_param(blk, 'LinkStatus', 'inactive');
        set_param(blk, 'LinkStatus', 'none');
    end
    for cb = {'InitFcn','OpenFcn','CloseFcn','PreSaveFcn','PostSaveFcn'}
        try, set_param(blk, cb{1}, ''); catch, end
    end

    wtStr = strrep(wtFn, '\', '\\');
    sf    = sfroot;

    m = sf.find('-isa', 'Stateflow.EMChart', 'Path', [mdl '/Predict/Predict/MLFB']);
    assert(numel(m) == 1, 'Expected one MLFB chart at %s/Predict/Predict/MLFB.', mdl);
    m.Script = sprintf([ ...
'function p = deepNetwork(u)\n' ...
'%%#codegen\n' ...
'%% Stateful LSTM forward (1 sample/step).\n' ...
'persistent w h c\n' ...
'if isempty(w)\n' ...
'    w = coder.load(''%s'');\n' ...
'    h = zeros(%d, 1, ''single'');\n' ...
'    c = zeros(%d, 1, ''single'');\n' ...
'end\n' ...
'x  = (single(u(:)) - w.norm_mean) ./ w.norm_std;\n' ...
'z  = w.Wi * x + w.Wr * h + w.bL;\n' ...
'ig = single(1) ./ (single(1) + exp(-z(1:%d)));\n' ...
'fg = single(1) ./ (single(1) + exp(-z(%d:%d)));\n' ...
'gg = tanh(z(%d:%d));\n' ...
'og = single(1) ./ (single(1) + exp(-z(%d:%d)));\n' ...
'c  = fg .* c + ig .* gg;\n' ...
'h  = og .* tanh(c);\n' ...
'y1 = max(w.Wfc1 * h + w.bfc1, single(0));\n' ...
'y2 = w.Wfc2 * y1 + w.bfc2;\n' ...
'p  = single(1) ./ (single(1) + exp(-y2));\n' ...
'end'], wtStr, H, H, H, H+1, 2*H, 2*H+1, 3*H, 3*H+1, 4*H);

    save_system(mdl);
    drawnow;
    try, close_system(mdl, 0); catch, end
    fprintf('Patched %s.slx (stateful, 1 sample/step)\n', mdl);
end



