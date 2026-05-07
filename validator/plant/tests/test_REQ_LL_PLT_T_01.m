function r = test_REQ_LL_PLT_T_01()
% REQ-LL-PLT-T-01  Median AND mean RMSE(T_pack) across 70 trips <= 1 degC.
r = val.new_result("plant","PLT-T-01","Plant T_pack convergence","REQ-LL-PLT-T-01");

rep = load_or_run_plant();
tol = evalin('base', 'req.PLT_T_RMSE_max_C');
r = val.check(r, "median_under_tol", rep.T_pack.median <= tol, ...
    sprintf('median = %.3f degC (n=%d)', rep.T_pack.median, rep.n_trips), rep.T_pack.median, tol);
r = val.check(r, "mean_under_tol", rep.T_pack.mean <= tol, ...
    sprintf('mean   = %.3f degC', rep.T_pack.mean), rep.T_pack.mean, tol);
r.metrics.median_C = rep.T_pack.median;
r.metrics.mean_C   = rep.T_pack.mean;
r.metrics.max_C    = rep.T_pack.max;
r.metrics.n_trips  = rep.n_trips;
end

function rep = load_or_run_plant()
here    = fileparts(mfilename('fullpath'));
valRoot = fileparts(fileparts(here));
file    = fullfile(valRoot, 'reports', 'plant_convergence.json');
if ~isfile(file), plant.run('verbose', false); end
rep = jsondecode(fileread(file));
end
