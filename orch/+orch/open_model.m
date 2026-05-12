function open_model(name)
% orch.open_model -- ensure snapshot exists, then open .slx in Simulink.
arguments
    name (1,:) char
end
orch.snapshot();              % first-edit safety net
models = orch.editable_models();
idx = find(strcmp({models.name}, name), 1);
if isempty(idx)
    error('orch:open_model:unknown', 'Unknown model "%s".', name);
end
open_system(models(idx).src);
end
