function snap = snapshot(varargin)
% orch.snapshot -- back up editable model files into model/.snapshots/.
%
% Creates one .bak per editable model the first time it is called; later
% calls are no-ops (the original "as-shipped" snapshot is preserved).
%
%   orch.snapshot              % all editable models
%   orch.snapshot('force',true)% overwrite existing snapshots
%
% Returns a struct array with fields name, src, bak, created.

p = inputParser;
p.addParameter('force', false, @islogical);
p.parse(varargin{:});

repo  = orch.repo_root();
snDir = fullfile(repo, 'model', '.snapshots');
if ~isfolder(snDir), mkdir(snDir); end

models = orch.editable_models();
snap   = repmat(struct('name',"",'src',"",'bak',"",'created',false), 0, 1);
for i = 1:numel(models)
    m   = models(i);
    bak = fullfile(snDir, [m.name '.slx.bak']);
    created = false;
    if p.Results.force || ~isfile(bak)
        copyfile(m.src, bak);
        created = true;
    end
    snap(end+1,1) = struct('name', string(m.name), 'src', string(m.src), ...
                           'bak', string(bak), 'created', created); %#ok<AGROW>
end
end
