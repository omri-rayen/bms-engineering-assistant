% output: plant_model/data/ecm_params.mat

scriptDir = fileparts(mfilename('fullpath'));
dataDir   = fullfile(scriptDir, '..', 'data');

% breakpoints
SoC_bp_ocv = (0:1:100).';
SoC_bp_ecm = (0:5:100).';
T_bp       = [0 5 10 15 20 25 30];

% LUT loader (drops the first column - SoC index)
readLUT = @(f) readmatrix(fullfile(dataDir, f), 'NumHeaderLines', 1);

OCV_data = readLUT('ocv_lut.csv'); OCV_data = OCV_data(:, 2:end);
R0_data  = readLUT('r0_lut.csv');  R0_data  = R0_data(:,  2:end);
R1_data  = readLUT('r1_lut.csv');  R1_data  = R1_data(:,  2:end);
C1_data  = readLUT('c1_lut.csv');  C1_data  = C1_data(:,  2:end);
R2_data  = readLUT('r2_lut.csv');  R2_data  = R2_data(:,  2:end);
C2_data  = readLUT('c2_lut.csv');  C2_data  = C2_data(:,  2:end);

outFile = fullfile(dataDir, 'ecm_params.mat');
save(outFile, 'SoC_bp_ocv', 'SoC_bp_ecm', 'T_bp', ...
     'OCV_data', 'R0_data', 'R1_data', 'C1_data', 'R2_data', 'C2_data');

fprintf('ecm_params.mat saved → %s\n', outFile);