function set_baseline(trip)
% Push the trip's natural starting state into the base workspace so
% MIL_model initialises consistently for that trip.

    % Cell + coolant temperatures
    assignin('base', 'T_cells_init', trip.T_init_C * ones(12, 8));
    assignin('base', 'T_cool_init',  trip.T_init_C);

    % SoC and EKF init
    assignin('base', 'SoC_init', trip.SoC_init_pct);
    ekf      = evalin('base', 'ekf_params');
    ekf.SoC0 = trip.SoC_init_pct / 100;
    assignin('base', 'ekf_params', ekf);

    % RC voltages start at rest
    assignin('base', 'V_RC1_init', 0);
    assignin('base', 'V_RC2_init', 0);

    % Fresh-cell R0 at the trip's operating point (used by SoH estimator)
    R0  = evalin('base', 'R0_data');
    Tbp = evalin('base', 'T_bp');
    Sbp = evalin('base', 'SoC_bp_ecm');
    Tc  = max(min(trip.T_init_C,     Tbp(end)), Tbp(1));
    Sc  = max(min(trip.SoC_init_pct, Sbp(end)), Sbp(1));
    bms = evalin('base', 'bms');
    bms.R0_fresh = interp2(Tbp, Sbp, R0, Tc, Sc, 'linear');
    assignin('base', 'bms', bms);
end
