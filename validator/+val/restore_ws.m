function restore_ws(snap)
% Restore variables previously captured by val.snapshot_ws.
fn = fieldnames(snap);
for i = 1:numel(fn)
    assignin('base', fn{i}, snap.(fn{i}));
end
end
