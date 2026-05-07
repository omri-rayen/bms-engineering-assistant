function restore_ws(snap)
% Restore vars saved by fp.snapshot_ws back to the base workspace.
    f = fieldnames(snap);
    for i = 1:numel(f)
        assignin('base', f{i}, snap.(f{i}));
    end
end
