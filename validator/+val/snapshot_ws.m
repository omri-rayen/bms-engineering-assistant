function snap = snapshot_ws()
% Capture the parameter variables MIL tests are allowed to mutate, so we
% can restore them after a test and keep tests independent.
vars = { ...
    'SoC_init','T_cells_init','T_cool_init','V_RC1_init','V_RC2_init', ...
    'I_bal_default','ekf_params','bms','cell_Q_Ah','cell_dSoC_pct', ...
    'cell_RO_scale','Q_nom_Ah','R0_data','h_cool','T_stop','fp_thresholds'};
snap = struct();
for i = 1:numel(vars)
    v = vars{i};
    if evalin('base', sprintf('exist(''%s'',''var'')', v))
        snap.(v) = evalin('base', v);
    end
end
end
