% calibrate_thermal_params.m — Calibrate cell thermal parameters via forward-ODE grid search
%
% Evaluates candidate [Cth, h_cool, h_amb] parameter sets against
% measurement trips that show meaningful temperature dynamics.
% Saves the best-fit result to thermal_params.csv.

addpath(fileparts(mfilename('fullpath')));
run('init_plant_model.m');

%% Load data
dataRoot = fullfile(fileparts(mfilename('fullpath')), '..', 'data');
D  = load(fullfile(dataRoot, 'drivecycles_meas.mat'));
fn = fieldnames(D);

% ECM resistance/capacitance maps
R0_tbl = readtable(fullfile(dataRoot, 'r0_lut.csv'));
R1_tbl = readtable(fullfile(dataRoot, 'r1_lut.csv'));
R2_tbl = readtable(fullfile(dataRoot, 'r2_lut.csv'));
C1_tbl = readtable(fullfile(dataRoot, 'c1_lut.csv'));
C2_tbl = readtable(fullfile(dataRoot, 'c2_lut.csv'));

ecm = struct( ...
    'R0', table2array(R0_tbl(:,2:end)), ...
    'R1', table2array(R1_tbl(:,2:end)), ...
    'R2', table2array(R2_tbl(:,2:end)), ...
    'C1', table2array(C1_tbl(:,2:end)), ...
    'C2', table2array(C2_tbl(:,2:end)), ...
    'SoC_bp', R0_tbl.SoC_pct, ...
    'T_bp',   [0 5 10 15 20 25 30]);

%% Select calibration trips (downsample for speed)
DS    = 20;
calib = {};
for k = 1:numel(fn)
    s   = D.(fn{k});
    if all(s.T_cool_C == 0), continue; end
    dur = s.time_s(end) - s.time_s(1);
    dT  = max(s.T_cell_C) - min(s.T_cell_C);
    if dur > 2000 && dT >= 2
        idx = 1:DS:numel(s.time_s);
        sd.time_s   = s.time_s(idx);
        sd.I_A      = s.I_A(idx);
        sd.SoC_pct  = s.SoC_pct(idx);
        sd.T_cell_C = s.T_cell_C(idx);
        sd.T_cool_C = s.T_cool_C(idx);
        sd.T_amb_C  = s.T_amb_C(idx);
        if isfield(s, 'v_kmh')
            sd.v_kmh = s.v_kmh(idx);
        else
            sd.v_kmh = zeros(size(idx(:)));
        end
        sd.name = fn{k};
        calib{end+1} = sd; %#ok<AGROW>
    end
end
fprintf('Calibration trips: %d (downsampled %dx)\n', numel(calib), DS);

%% Candidate parameter grid [Cth, h_cool, h_amb]
candidates = [
    1300, 0.020, 0.15;  1300, 0.025, 0.15;  1300, 0.025, 0.20;
    1300, 0.030, 0.15;  1300, 0.030, 0.20;  1300, 0.035, 0.20;
    1400, 0.020, 0.15;  1400, 0.025, 0.15;  1400, 0.025, 0.20;
    1400, 0.030, 0.15;  1400, 0.030, 0.20;  1400, 0.035, 0.20;
    1500, 0.020, 0.15;  1500, 0.025, 0.15;  1500, 0.025, 0.20;
    1500, 0.030, 0.15;  1500, 0.030, 0.20;  1500, 0.035, 0.15;
    1500, 0.035, 0.20;  1500, 0.040, 0.20;
    1600, 0.025, 0.15;  1600, 0.025, 0.20;  1600, 0.030, 0.15;
    1600, 0.030, 0.20;  1600, 0.035, 0.20;
    1700, 0.030, 0.15;  1700, 0.030, 0.20;  1700, 0.035, 0.20;
];

%% Evaluate candidates
fprintf('Evaluating %d candidates...\n', size(candidates,1));
bestMSE = Inf;
bestIdx = 1;
for c = 1:size(candidates,1)
    p   = candidates(c,:);
    mse = sim_error(p, calib, ecm);
    fprintf('  [%5.0f, %.3f, %.3f] => RMSE=%.3f\n', p(1), p(2), p(3), sqrt(mse));
    if mse < bestMSE
        bestMSE = mse;
        bestIdx = c;
    end
end

xopt = candidates(bestIdx,:);
fprintf('\n=== Best Parameters ===\n');
fprintf('  Cth    = %.1f J/K\n',    xopt(1));
fprintf('  h_cool = %.4f W/K\n',    xopt(2));
fprintf('  h_amb  = %.4f W/K\n',    xopt(3));
fprintf('  m_cell = %.3f kg (cp=1000)\n', xopt(1)/1000);
fprintf('  RMSE   = %.3f degC\n',   sqrt(bestMSE));

%% Per-trip breakdown
fprintf('\n=== Per-Trip RMSE ===\n');
for i = 1:numel(calib)
    s      = calib{i};
    Tc_sim = run_thermal_ode(xopt, s, ecm);
    rmse   = sqrt(mean((Tc_sim - s.T_cell_C).^2));
    fprintf('  %s: %.3f degC\n', s.name, rmse);
end

%% Save calibrated parameters
cp_val = 1000;
calibResults = table( ...
    xopt(1), xopt(1)/cp_val, cp_val, xopt(2), xopt(3), ...
    sqrt(bestMSE), numel(calib), ...
    'VariableNames', {'Cth_JK','m_cell_kg','cp_cell_JkgK', ...
                      'h_cool_WK','h_amb_WK','rmse_C','n_trips'});

csvPath = fullfile(dataRoot, 'thermal_params.csv');
writetable(calibResults, csvPath);
fprintf('\nSaved: %s\n', csvPath);


%% === Local functions ===

function mse = sim_error(params, calib, ecm)
    totalErr = 0;
    totalN   = 0;
    for i = 1:numel(calib)
        Tc_sim = run_thermal_ode(params, calib{i}, ecm);
        err    = (Tc_sim - calib{i}.T_cell_C).^2;
        ok     = isfinite(err);
        totalErr = totalErr + sum(err(ok));
        totalN   = totalN + sum(ok);
    end
    mse = totalErr / max(totalN, 1);
end

function Tc = run_thermal_ode(params, s, ecm)
    Cth = params(1);  hcl = params(2);  hamb = params(3);

    t   = s.time_s;
    I   = s.I_A;
    SoC = s.SoC_pct;
    Tcl = s.T_cool_C;
    Ta  = s.T_amb_C;
    N   = numel(t);

    SoC_bp = ecm.SoC_bp;
    T_bp   = ecm.T_bp;

    Tc    = zeros(N,1);
    Tc(1) = s.T_cell_C(1);

    % RC initial state: steady-state if vehicle already moving
    if isfield(s, 'v_kmh') && s.v_kmh(1) > 0
        soc_0 = clamp_val(SoC(1), SoC_bp);
        t_0   = clamp_val(s.T_cell_C(1), T_bp);
        Vrc1  = interp2(T_bp', SoC_bp, ecm.R1, t_0, soc_0, 'linear') * I(1);
        Vrc2  = interp2(T_bp', SoC_bp, ecm.R2, t_0, soc_0, 'linear') * I(1);
    else
        Vrc1 = 0;
        Vrc2 = 0;
    end

    for j = 1:N-1
        dt_j = max(t(j+1) - t(j), 1e-3);

        soc_q = clamp_val(SoC(j), SoC_bp);
        t_q   = clamp_val(Tc(j), T_bp);

        R0 = interp2(T_bp', SoC_bp, ecm.R0, t_q, soc_q, 'linear');
        R1 = interp2(T_bp', SoC_bp, ecm.R1, t_q, soc_q, 'linear');
        R2 = interp2(T_bp', SoC_bp, ecm.R2, t_q, soc_q, 'linear');
        C1 = interp2(T_bp', SoC_bp, ecm.C1, t_q, soc_q, 'linear');
        C2 = interp2(T_bp', SoC_bp, ecm.C2, t_q, soc_q, 'linear');

        % Exact exponential RC update (stable for large dt)
        exp1 = exp(-dt_j / (R1*C1));
        exp2 = exp(-dt_j / (R2*C2));
        Vrc1 = I(j)*R1*(1 - exp1) + Vrc1*exp1;
        Vrc2 = I(j)*R2*(1 - exp2) + Vrc2*exp2;

        % Heat generation: I^2*R0 + V_RC^2/R
        Qgen = I(j)^2 * R0 + Vrc1^2/R1 + Vrc2^2/R2;

        dTdt   = (Qgen - hcl*(Tc(j)-Tcl(j)) - hamb*(Tc(j)-Ta(j))) / Cth;
        Tc(j+1) = Tc(j) + dTdt * dt_j;

        if abs(Tc(j+1)) > 200
            Tc(j+1:end) = 200 * sign(Tc(j+1));
            break;
        end
    end
end

function v = clamp_val(x, bp)
    v = max(min(x, max(bp)), min(bp));
end
