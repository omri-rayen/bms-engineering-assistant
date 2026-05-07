function r = test_REQ_LL_SIL_EQ_01()
% REQ-LL-SIL-EQ-01  Generated C of bms_master in SIL mode SHALL match the
% MIL reference on TripA02 within req.SIL_EQ_rel_tol or req.SIL_EQ_abs_tol
% on every monitored signal.
TRIP_ID = 'TripA02';
SIGS = {'fault_severity','SoC_pack','SoH_pack','P_limit_chg', ...
        'P_limit_dchg','enable_bal_8','prob_3','alarm_3'};

r = val.new_result("sil","SIL-EQ-01","SIL/MIL equivalence on TripA02","REQ-LL-SIL-EQ-01");

req     = evalin('base', 'req');
REL_TOL = req.SIL_EQ_rel_tol;
ABS_TOL = req.SIL_EQ_abs_tol;

mdl = 'bms_master';
load_system(mdl);

trips = evalin('base', 'trips_meas');
if ~isfield(trips, TRIP_ID)
    r = val.check(r, "trip_available", false, sprintf('%s not in trips_meas', TRIP_ID));
    return
end

trip = fp.make_trip(trips, TRIP_ID);
fp.set_baseline(trip);
t  = trip.time_s;
N  = numel(t);
ds = val.master_inputs(t, ...
    'I_pack',       trip.I_A, ...
    'V_cells_96',   repmat(3.90, N, 96), ...
    'T_sensors_32', repmat(trip.T_amb_C, 1, 32), ...
    'T_coolant',    trip.T_amb_C);

set_param(mdl, 'SimulationMode', 'normal');
out_mil = val.sim_model(mdl, ds, t(end));

set_param(mdl, 'SimulationMode', 'software-in-the-loop');
cleanup = onCleanup(@()set_param(mdl, 'SimulationMode', 'normal'));
out_sil = val.sim_model(mdl, ds, t(end));

worst = struct();
all_ok = true;
for k = 1:numel(SIGS)
    nm = SIGS{k};
    a = val.signal(out_mil, nm).y;
    b = val.signal(out_sil, nm).y;
    if ~isequal(size(a), size(b))
        L = min(size(a,1), size(b,1));
        a = a(1:L, :); b = b(1:L, :);
    end
    err     = abs(a - b);
    tol     = max(ABS_TOL, REL_TOL * max(abs(a), abs(b)));
    ok_sig  = all(err <= tol, 'all');
    worst.(nm) = max(err, [], 'all');
    r = val.check(r, sprintf("eq_%s", nm), ok_sig, ...
        sprintf('max|err|=%.3e (tol=%.1e rel + %.1e abs)', max(err,[],'all'), REL_TOL, ABS_TOL), ...
        max(err,[],'all'), sprintf('<=%.1e rel + %.1e abs', REL_TOL, ABS_TOL));
    all_ok = all_ok && ok_sig;
end

r.metrics.max_abs_err = worst;
r.metrics.trip_id     = string(TRIP_ID);
r.metrics.rel_tol     = REL_TOL;
r.metrics.abs_tol     = ABS_TOL;

% Overlay MIL vs SIL for SoC_pack and fault_severity.
try
    here    = fileparts(mfilename('fullpath'));
    valRoot = fileparts(fileparts(here));
    plotDir = fullfile(valRoot, 'reports', 'plots', 'sil');
    if ~isfolder(plotDir), mkdir(plotDir); end
    PLOT_SIGS = {'SoC_pack','fault_severity'};
    fig = figure('Visible','off','Position',[100 100 1100 600]);
    for ii = 1:numel(PLOT_SIGS)
        nm = PLOT_SIGS{ii};
        sa = val.signal(out_mil, nm); sb = val.signal(out_sil, nm);
        subplot(numel(PLOT_SIGS), 1, ii);
        plot(sa.t, sa.y, 'k-',  'LineWidth', 1.0); hold on;
        plot(sb.t, sb.y, 'r--', 'LineWidth', 1.0);
        ylabel(nm, 'Interpreter','none'); grid on;
        if ii == 1
            title(sprintf('SIL vs MIL  -  %s  -  max|err|: SoC=%.2e, fault=%.2e', ...
                TRIP_ID, worst.SoC_pack, worst.fault_severity), 'Interpreter','none');
        end
        if ii == numel(PLOT_SIGS), xlabel('time [s]'); end
        legend({'MIL','SIL'}, 'Location','best');
    end
    exportgraphics(fig, fullfile(plotDir, 'sil_vs_mil.png'), 'Resolution', 120);
    close(fig);
catch ME
    warning('sil:eq:plot', 'overlay plot failed: %s', ME.message);
end
end
