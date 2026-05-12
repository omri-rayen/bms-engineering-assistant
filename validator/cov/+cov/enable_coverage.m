function restoreFn = enable_coverage(mdls)
% cov.enable_coverage  Switch Simulink Coverage on for every model in
% `mdls`, returning a function handle that restores the original
% parameters. Called by both cov.run (standalone) and mil.run (single-
% pass MIL+coverage mode).
params  = {'CovEnable',   'RecordCoverage',  'CovMetricSettings', ...
           'CovModelRefEnable', 'CovSFcnEnable', ...
           'CovSaveSingleToWorkspaceVar', 'CovSaveName'};
desired = {'on', 'on', 'dcmtr', 'all', 'on', 'on', 'covdata'};

saved = struct();
for i = 1:numel(mdls)
    m = mdls{i};
    load_system(m);
    saved.(m) = struct();
    for k = 1:numel(params)
        try
            saved.(m).(params{k}) = get_param(m, params{k});
            set_param(m, params{k}, desired{k});
        catch
            % Parameter not applicable for this model -- skip.
        end
    end
end

restoreFn = @() local_restore(mdls, params, saved);
end

function local_restore(mdls, params, saved)
for i = 1:numel(mdls)
    m = mdls{i};
    if ~bdIsLoaded(m) || ~isfield(saved, m), continue, end
    for k = 1:numel(params)
        if isfield(saved.(m), params{k})
            try
                set_param(m, params{k}, saved.(m).(params{k}));
            catch
            end
        end
    end
    % Toggling coverage flags marks the model dirty even though no real
    % design change happened. Clear the flag so MATLAB does not warn at
    % shutdown / next close_system.
    try, set_param(m, 'Dirty', 'off'); catch, end %#ok<CTCH>
end
end
