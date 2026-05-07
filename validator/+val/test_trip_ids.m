function ids = test_trip_ids()
% Return the predictor test-split trip ids, exactly as written by
% ai/fault_prediction/scripts/python/preprocess.py. Used by the predictor
% MIL tests so they evaluate on the held-out trips only -- never on the
% training or validation splits (matches evaluate.py).

here     = fileparts(mfilename('fullpath'));            % validator/+val
projRoot = fileparts(fileparts(here));                  % repo root
splitFn  = fullfile(projRoot, 'ai', 'fault_prediction', ...
                    'data', 'preprocessed', 'split.json');
S = jsondecode(fileread(splitFn));
ids = cellstr(string(S.trips.test));
end
