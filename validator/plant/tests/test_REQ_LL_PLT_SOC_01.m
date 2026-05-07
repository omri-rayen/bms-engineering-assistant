function r = test_REQ_LL_PLT_SOC_01()
% REQ-LL-PLT-SOC-01  Median AND mean RMSE(SoC_pack) across 70 trips <= 1 %.
r = val.new_result("plant","PLT-SOC-01","Plant SoC convergence","REQ-LL-PLT-SOC-01");

rep = load_or_run_plant();
tol = evalin('base', 'req.PLT_SOC_RMSE_max_pct');
r = val.check(r, "median_under_tol", rep.SoC_pack.median <= tol, ...
    sprintf('median = %.3f %% (n=%d)', rep.SoC_pack.median, rep.n_trips), rep.SoC_pack.median, tol);
r = val.check(r, "mean_under_tol", rep.SoC_pack.mean <= tol, ...
    sprintf('mean   = %.3f %%', rep.SoC_pack.mean), rep.SoC_pack.mean, tol);
r.metrics.median_pct = rep.SoC_pack.median;
r.metrics.mean_pct   = rep.SoC_pack.mean;
r.metrics.max_pct    = rep.SoC_pack.max;
r.metrics.n_trips    = rep.n_trips;
end

function rep = load_or_run_plant()
here    = fileparts(mfilename('fullpath'));
valRoot = fileparts(fileparts(here));
file    = fullfile(valRoot, 'reports', 'plant_convergence.json');
if ~isfile(file), plant.run('verbose', false); end
rep = jsondecode(fileread(file));
end
