function r = test_REQ_LL_PLT_V_01()
% REQ-LL-PLT-V-01  Median AND mean RMSE(V_pack) across the 70 trips <= 4 V.
r = val.new_result("plant","PLT-V-01","Plant V_pack convergence","REQ-LL-PLT-V-01");

rep = load_or_run_plant();
tol = evalin('base', 'req.PLT_V_RMSE_max_V');
r = val.check(r, "median_under_tol", rep.V_pack.median <= tol, ...
    sprintf('median = %.3f V (n=%d)', rep.V_pack.median, rep.n_trips), rep.V_pack.median, tol);
r = val.check(r, "mean_under_tol", rep.V_pack.mean <= tol, ...
    sprintf('mean   = %.3f V', rep.V_pack.mean), rep.V_pack.mean, tol);
r.metrics.median_V = rep.V_pack.median;
r.metrics.mean_V   = rep.V_pack.mean;
r.metrics.max_V    = rep.V_pack.max;
r.metrics.n_trips  = rep.n_trips;
end

function rep = load_or_run_plant()
here    = fileparts(mfilename('fullpath'));
valRoot = fileparts(fileparts(here));
file    = fullfile(valRoot, 'reports', 'plant_convergence.json');
if ~isfile(file)
    plant.run('verbose', false);
end
rep = jsondecode(fileread(file));
end
