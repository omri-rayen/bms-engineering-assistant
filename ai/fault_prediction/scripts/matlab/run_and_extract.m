function [X, Y, meta] = run_and_extract(mdl, trip, scen)
% Run one MIL simulation and turn the outputs into features + look-ahead labels.
% Pulls warn-level thresholds and look-ahead horizons from the base
% workspace (init_system.m). The predictor must fire BEFORE the warn-level
% fault flag, so labels are anchored to warn crossings, not shutdown.

bms       = evalin('base', 'bms');
predictor = evalin('base', 'predictor');
THR_OT = bms.T_OT_warn;
THR_OV = bms.V_OV_warn;
THR_UV = bms.V_UV_warn;
H_OT   = predictor.H_OT_samples;
H_OV   = predictor.H_OV_samples;
H_UV   = predictor.H_UV_samples;
H_MAX  = max([H_OT, H_OV, H_UV]);
LAG    = predictor.LAG_samples;
DT     = evalin('base', 'dt');

X    = [];
Y    = [];
meta = struct('scen_id', scen.id, 'fault', scen.fault, ...
              'sim_ok', false, 'N', 0, 'n_OT', 0, 'n_OV', 0, 'n_UV', 0);

t    = trip.time_s;
I    = trip.I_A;
Tamb = trip.T_amb_C;

% If the scenario forces an initial temperature, hold the ambient at it
% (cooling-loss and cold-soak scenarios assume a matching environment).
if ~isnan(scen.T_init_C)
    Tamb(:) = scen.T_init_C;
end

% Drive the model
ds = Simulink.SimulationData.Dataset;
ds = ds.addElement(timeseries(I,    t, 'Name','I_pack'), 'I_pack');
ds = ds.addElement(timeseries(Tamb, t, 'Name','T_amb'),  'T_amb');

simIn = Simulink.SimulationInput(mdl);
simIn = simIn.setModelParameter('StopTime',               num2str(t(end)));
simIn = simIn.setModelParameter('SaveOutput',             'on');
simIn = simIn.setModelParameter('SaveFormat',             'Dataset');
simIn = simIn.setModelParameter('ReturnWorkspaceOutputs', 'on');
simIn = simIn.setExternalInput(ds);

try
    out = sim(simIn);
catch ME
    warning('[%s] sim failed: %s', scen.id, ME.message);
    return
end

% Extract signals
mo    = out.yout.getElement(1).Values;
Vmin  = squeeze(double(mo.V_cell_min.Data));
Vmax  = squeeze(double(mo.V_cell_max.Data));
SoC   = squeeze(double(mo.SoC_pack.Data)) * 100;
Tmax  = squeeze(double(mo.T_cell_max.Data));
Tcool = squeeze(double(mo.T_coolant.Data));
Ipack = squeeze(double(mo.I_pack.Data));
N0    = numel(Vmin);

if N0 <= H_MAX + LAG
    warning('[%s] trip too short (%d samples), skipping.', scen.id, N0);
    meta.N = N0;
    return
end

% Backward-difference rates
dVmin = [zeros(LAG,1); (Vmin(LAG+1:end) - Vmin(1:end-LAG)) / (LAG*DT)];
dTmax = [zeros(LAG,1); (Tmax(LAG+1:end) - Tmax(1:end-LAG)) / (LAG*DT)];

% Drop the tail where the look-ahead window can't be evaluated
N = N0 - H_MAX;

X = single([Vmin(1:N), Vmax(1:N), SoC(1:N), ...
            Tmax(1:N), Tcool(1:N), Ipack(1:N), ...
            dVmin(1:N), dTmax(1:N)]);

% Look-ahead labels: 1 if the threshold is crossed within H samples ahead.
% Only the scenario's target fault is positive; other channels stay zero.
y_OT = false(N,1);
y_OV = false(N,1);
y_UV = false(N,1);

switch scen.fault
    case 'OT', y_OT = lookahead(Tmax, N, H_OT, THR_OT, true);
    case 'OV', y_OV = lookahead(Vmax, N, H_OV, THR_OV, true);
    case 'UV', y_UV = lookahead(Vmin, N, H_UV, THR_UV, false);
end

Y = [y_OT, y_OV, y_UV];

meta.sim_ok = true;
meta.N      = N;
meta.n_OT   = sum(y_OT);
meta.n_OV   = sum(y_OV);
meta.n_UV   = sum(y_UV);
end


function y = lookahead(sig, N, H, thr, is_upper)
    if is_upper
        flag = sig >= thr;
    else
        flag = sig <= thr;
    end
    cs = [0; cumsum(flag)];
    y  = (cs(1+H : N+H) - cs(1:N)) > 0;
end
