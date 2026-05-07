function apply_injection(scen)
% Mutate the base workspace to inject the scenario's fault before sim.
% The caller (generate_fault_dataset) is responsible for snapshot/restore.

% Internal-resistance scaling (aging proxy)
if scen.R0_scale ~= 1.0
    assignin('base', 'R0_data', evalin('base','R0_data') * scen.R0_scale);
    bms = evalin('base','bms');
    bms.R0_fresh = bms.R0_fresh * scen.R0_scale;
    assignin('base', 'bms', bms);
end

% Coolant convection scaling (degraded / failed cooling loop)
if scen.h_cool_fac ~= 1.0
    assignin('base', 'h_cool', evalin('base','h_cool') * scen.h_cool_fac);
end

% Capacity fade (also rescale per-cell capacities consistently)
if ~isnan(scen.Q_nom_Ah)
    ratio = scen.Q_nom_Ah / evalin('base','Q_nom_Ah');
    assignin('base', 'Q_nom_Ah',  scen.Q_nom_Ah);
    assignin('base', 'cell_Q_Ah', evalin('base','cell_Q_Ah') * ratio);
    bms = evalin('base','bms');
    bms.Q_nom_Ah = scen.Q_nom_Ah;
    assignin('base', 'bms', bms);
end

% Force initial SoC. Reset the RC voltages so we don't get a t=0 transient
% from values computed at the previous operating point.
if ~isnan(scen.SoC_init)
    SoC = max(min(scen.SoC_init, 100), 5);
    assignin('base', 'SoC_init', SoC);
    ekf      = evalin('base','ekf_params');
    ekf.SoC0 = SoC / 100;
    assignin('base', 'ekf_params', ekf);
    assignin('base', 'V_RC1_init', 0);
    assignin('base', 'V_RC2_init', 0);
end

% Amplify cell-to-cell SoC spread (clamped to +/-15 %)
if scen.imbal_scale ~= 1.0
    dSoC = evalin('base','cell_dSoC_pct') * scen.imbal_scale;
    assignin('base', 'cell_dSoC_pct', max(min(dSoC, 15), -15));
end

% Force initial temperature (uniform across cells and coolant)
if ~isnan(scen.T_init_C)
    assignin('base', 'T_cells_init', scen.T_init_C * ones(12, 8));
    assignin('base', 'T_cool_init',  scen.T_init_C);
    assignin('base', 'V_RC1_init',   0);
    assignin('base', 'V_RC2_init',   0);
end
end
