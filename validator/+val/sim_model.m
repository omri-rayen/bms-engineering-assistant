function out = sim_model(mdl, ds, stop_time, extra)
% sim() wrapper for normal-mode (MIL) tests.
%   ds         Simulink.SimulationData.Dataset for root inports (or [])
%   stop_time  scalar [s]
%   extra      optional struct of model-parameter name/value pairs
if nargin < 4, extra = struct(); end
simIn = Simulink.SimulationInput(mdl);
simIn = simIn.setModelParameter('StopTime',  num2str(stop_time));
simIn = simIn.setModelParameter('SaveOutput','on');
simIn = simIn.setModelParameter('SaveFormat','Dataset');
simIn = simIn.setModelParameter('SaveTime',  'on');
if ~isempty(ds)
    simIn = simIn.setExternalInput(ds);
end
fn = fieldnames(extra);
for i = 1:numel(fn)
    simIn = simIn.setModelParameter(fn{i}, extra.(fn{i}));
end
out = sim(simIn);
end
