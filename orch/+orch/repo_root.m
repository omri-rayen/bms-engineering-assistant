function r = repo_root()
% orch.repo_root -- absolute path to the repository root.
r = fileparts(fileparts(fileparts(mfilename('fullpath'))));
end
