function snap = snapshot_ws()
% Snapshot the base workspace vars touched by fp.set_baseline / injection.
    vars = {'R0_data','h_cool','Q_nom_Ah','cell_Q_Ah','cell_dSoC_pct', ...
            'SoC_init','ekf_params','bms','T_cells_init','T_cool_init', ...
            'V_RC1_init','V_RC2_init'};
    snap = struct();
    for i = 1:numel(vars)
        snap.(vars{i}) = evalin('base', vars{i});
    end
end
