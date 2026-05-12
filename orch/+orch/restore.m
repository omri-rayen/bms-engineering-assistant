function info = restore()
% orch.restore -- restore editable models from model/.snapshots/.
%
% Closes the model in Simulink (without saving), then copies the .bak
% back over the live .slx. Errors if no snapshot exists yet.

repo   = orch.repo_root();
snDir  = fullfile(repo, 'model', '.snapshots');
models = orch.editable_models();
info   = repmat(struct('name',"",'restored',false,'reason',""), 0, 1);

for i = 1:numel(models)
    m   = models(i);
    bak = fullfile(snDir, [m.name '.slx.bak']);
    rec = struct('name', string(m.name), 'restored', false, 'reason', "");
    if ~isfile(bak)
        rec.reason = "no snapshot";
    else
        try
            if bdIsLoaded(m.name)
                close_system(m.name, 0);
            end
        catch
            % If close fails the copyfile will surface the real reason.
        end
        try
            copyfile(bak, m.src);
            rec.restored = true;
        catch ME
            rec.reason = string(ME.message);
        end
    end
    info(end+1,1) = rec; %#ok<AGROW>
end
end
