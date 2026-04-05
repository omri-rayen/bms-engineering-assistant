% outputs:
%   plant_model/data/drivecycles_meas.mat
%   plant_model/data/drivecycles_sim.mat

scriptDir   = fileparts(mfilename('fullpath'));
dataDir     = fullfile(scriptDir, '..', 'data');
cleanedRoot = fullfile(scriptDir, '..', '..', 'data', 'cleaned');

measFile = fullfile(cleanedRoot, 'measurement', 'measurement_clean.csv');
simFile  = fullfile(cleanedRoot, 'simulation',  'simulation_clean.csv');

% measurement trips
opts = detectImportOptions(measFile);
opts = setvartype(opts, 'trip_id', 'categorical');
T_meas  = readtable(measFile, opts);
tripIDs = categories(T_meas.trip_id);

trips_meas = struct();
for k = 1:numel(tripIDs)
    tid  = tripIDs{k};
    sub  = T_meas(T_meas.trip_id == tid, :);
    fn   = matlab.lang.makeValidName(tid);

    if      startsWith(tid, 'TripA'), camp = 'A';
    elseif  startsWith(tid, 'TripB'), camp = 'B';
    else,                             camp = 'unknown';
    end

    trips_meas.(fn).time_s    = sub.time_s;
    trips_meas.(fn).I_A       = -sub.battery_current_a;
    trips_meas.(fn).V_pack_V  = sub.battery_voltage_v;
    trips_meas.(fn).SoC_pct   = sub.soc_pct;
    trips_meas.(fn).T_cell_C  = sub.battery_temperature_c;
    trips_meas.(fn).T_amb_C   = sub.ambient_temperature_c;
    trips_meas.(fn).T_cool_C  = sub.coolant_temp_inlet_c;
    trips_meas.(fn).v_kmh     = sub.velocity_kmh;
    trips_meas.(fn).campaign  = camp;
end

outMeas = fullfile(dataDir, 'drivecycles_meas.mat');
save(outMeas, '-struct', 'trips_meas');
fprintf('meas: %d trips => %s\n', numel(tripIDs), outMeas);

% simulation trips
opts = detectImportOptions(simFile);
opts = setvartype(opts, {'sim_id','scenario','bus_type'}, 'categorical');
T_sim  = readtable(simFile, opts);
simIDs = categories(T_sim.sim_id);

trips_sim = struct();
for k = 1:numel(simIDs)
    sid = simIDs{k};
    sub = T_sim(T_sim.sim_id == sid, :);
    fn  = matlab.lang.makeValidName(sid);

    trips_sim.(fn).time_s    = sub.time_s;
    trips_sim.(fn).I_A       = sub.battery_current_a;
    trips_sim.(fn).V_pack_V  = sub.pack_voltage_v;
    trips_sim.(fn).SoC_pct   = sub.soc_pct;
    trips_sim.(fn).T_cell_C  = sub.mean_cell_temperature_c;
    trips_sim.(fn).T_amb_C   = sub.ambient_temperature_c;
    trips_sim.(fn).campaign  = char(sub.scenario(1));
end

outSim = fullfile(dataDir, 'drivecycles_sim.mat');
save(outSim, '-struct', 'trips_sim');
fprintf('sim:  %d trips => %s\n', numel(simIDs), outSim);