function ds = master_inputs(t, varargin)
% Build a Simulink dataset with all 6 root inports of bms_master populated
% to nominal values, then override any caller-specified channels.
%
%   ds = val.master_inputs(t, 'I_pack', I, 'V_cells_96', V96)
%
% Defaults: I_pack=0, T_coolant=25, fault_flags_8=0, T_sensors_32=25,
%           V_cells_96=3.7, hw_fault=0.

p = inputParser;
p.addParameter('I_pack',         []);
p.addParameter('T_coolant',      []);
p.addParameter('fault_flags_8',  []);
p.addParameter('T_sensors_32',   []);
p.addParameter('V_cells_96',     []);
p.addParameter('hw_fault',       []);
p.parse(varargin{:});
o = p.Results;

t = t(:); N = numel(t);
def = struct( ...
    'I_pack',         zeros(N,1), ...
    'T_coolant',      25*ones(N,1), ...
    'fault_flags_8',  zeros(N,8), ...
    'T_sensors_32',   25*ones(N,32), ...
    'V_cells_96',     3.7*ones(N,96), ...
    'hw_fault',       zeros(N,1));

names = fieldnames(def);
ds = Simulink.SimulationData.Dataset;
for i = 1:numel(names)
    n = names{i};
    val = o.(n);
    if isempty(val), val = def.(n); end
    if isvector(val) && size(val,1) ~= N, val = val(:); end
    if strcmp(n, 'hw_fault'), val = logical(val); end
    ds = ds.addElement(timeseries(val, t, 'Name', n), n);
end
end
