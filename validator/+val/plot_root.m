function dir_path = plot_root(varargin)
%PLOT_ROOT  Resolve a per-suite plot directory under validator/reports/plots/.
%
%   val.plot_root('mil','bms')  ->  <repo>/validator/reports/plots/mil/bms
%   val.plot_root('sil')        ->  <repo>/validator/reports/plots/sil
%
% The directory is created if it does not exist. Tests use this so that
% the same path is computed regardless of the caller cwd.

here    = fileparts(mfilename('fullpath'));   % validator/+val
valRoot = fileparts(here);                    % validator
dir_path = fullfile(valRoot, 'reports', 'plots', varargin{:});
if ~isfolder(dir_path), mkdir(dir_path); end
end
