% Generate fault-prediction dataset.
% Runs each (trip, scenario) pair, extracts features + labels, writes dataset.mat + log.csv.

%% Paths
scriptDir = fileparts(mfilename('fullpath'));
fpRoot    = fileparts(fileparts(scriptDir));
aiRoot    = fileparts(fpRoot);
projRoot  = fileparts(aiRoot);
modelRoot = fullfile(projRoot, 'model');
sysParams = fullfile(modelRoot, 'system', 'params');
sysModels = fullfile(modelRoot, 'system', 'models');
outDir    = fullfile(fpRoot, 'data');

% The validator module pulls in every model + fault-injection helper.
if ~isfolder(outDir), mkdir(outDir); end

%% Init workspace and load model
% fresh seed-42 cell variability so dataset and MIL eval use identical pack dispersion
cellVarFile = fullfile(sysParams, 'cell_variability.mat');
if isfile(cellVarFile), delete(cellVarFile); end
clear cell_Q_Ah cell_dSoC_pct cell_RO_scale   % don't let stale workspace vars bypass the seed
run(fullfile(sysParams, 'init_system.m'));

mdl = 'system_model';
load_system(fullfile(sysModels, mdl));
set_param(mdl, 'SimulationMode', 'accelerator');

% 28 trips covering OT / OV / UV conditions
trip_ids = { ...
    'TripA06','TripA08','TripA16','TripA19','TripA21','TripA22', ...
    'TripA32','TripA11','TripA05','TripA01', ...
    'TripB01','TripB08','TripB09','TripB12','TripB14','TripB36', ...
    'TripB07','TripB04','TripB26','TripB29', ...
    'TripB17','TripB21','TripB24','TripB25','TripB27','TripB28', ...
    'TripB11','TripB32' ...                                         
};

scenarios = define_injection_scenarios();
n_trips   = numel(trip_ids);
n_scen    = numel(scenarios);

fprintf('Loaded %d trips  x  %d scenarios\n\n', n_trips, n_scen);

%% Run trip x scenario grid
results  = struct('X', {}, 'Y', {}, 'meta', {});
log_rows = {};
run_idx  = 0;

for ti = 1:n_trips
    trip = fp.make_trip(trips_meas, trip_ids{ti});

    % Baseline ICs come from the trip's first sample. Each scenario starts
    % here; apply_injection may then override individual fields.
    fp.set_baseline(trip);

    for si = 1:n_scen
        scen = scenarios(si);

        if ~scen.filter(trip)
            fprintf('  skip  %-10s  %s\n', trip.trip_id, scen.id);
            continue
        end

        run_idx = run_idx + 1;
        fprintf('[%3d]  %-10s  %-8s  ', run_idx, trip.trip_id, scen.id);

        snap = fp.snapshot_ws();
        try
            apply_injection(scen);
            [X, Y, meta] = run_and_extract(mdl, trip, scen);
        catch ME
            warning('failed: %s', ME.message);
            X = []; Y = [];
            meta = struct('scen_id', scen.id, 'fault', scen.fault, ...
                          'sim_ok', false, 'N', 0, ...
                          'n_OT', 0, 'n_OV', 0, 'n_UV', 0);
        end
        fp.restore_ws(snap);

        if meta.sim_ok
            fprintf('OK  N=%-5d  OT=%-4d OV=%-4d UV=%-4d\n', ...
                meta.N, meta.n_OT, meta.n_OV, meta.n_UV);
        else
            fprintf('FAILED\n');
        end

        results(end+1).X  = X; %#ok<SAGROW>
        results(end).Y    = Y;
        results(end).meta = meta;
        log_rows{end+1}   = sprintf('%s,%s,%s,%d,%d,%d,%d,%d', ...
            trip.trip_id, scen.id, scen.fault, meta.sim_ok, ...
            meta.N, meta.n_OT, meta.n_OV, meta.n_UV); %#ok<SAGROW>
    end

    % Save after each trip so a crash mid-run doesn't lose everything.
    save(fullfile(outDir, 'dataset.mat'), 'results', '-v7.3');
end

%% Write log
fid = fopen(fullfile(outDir, 'log.csv'), 'w');
fprintf(fid, 'trip_id,scen_id,fault,sim_ok,N,n_OT,n_OV,n_UV\n');
fprintf(fid, '%s\n', log_rows{:});
fclose(fid);

ok = sum(arrayfun(@(r) r.meta.sim_ok, results));
fprintf('\nDone. %d/%d runs succeeded. Data saved to:\n  %s\n', ok, run_idx, outDir);
