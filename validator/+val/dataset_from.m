function ds = dataset_from(varargin)
% Build a Simulink.SimulationData.Dataset from (name, time, data) triplets.
%   ds = val.dataset_from('I_pack', t, I, 'T_amb', t, T)
ds = Simulink.SimulationData.Dataset;
assert(mod(numel(varargin), 3) == 0, 'val.dataset_from: args must be triplets (name,t,data)');
for k = 1:3:numel(varargin)
    name = varargin{k};
    t    = varargin{k+1}(:);
    d    = varargin{k+2};
    if isvector(d), d = d(:); end
    ts = timeseries(d, t, 'Name', name);
    ds = ds.addElement(ts, name);
end
end
