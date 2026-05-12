function s = metrics_codeblock(mdl)
% ana.metrics_codeblock -- code-quality metrics for embedded code blocks.
%
% Returns:
%   matlab_function_blocks_list [{path, loc, max_nesting, has_eml}]
%       For every Stateflow EmbeddedMATLAB block (= MATLAB Function in
%       the diagram): line count and maximum control-flow nesting depth
%       of the embedded script. ISO 26262-6 Annex C.4 tags large embedded
%       scripts as a hand-off boundary that needs the same scrutiny as
%       generated code. Capped at 15.

s = struct();
s.matlab_function_blocks_list = struct( ...
    'path', {}, 'loc', {}, 'max_nesting', {}, 'name', {});

try
    rt = sfroot;
catch
    return
end

try
    % Get the model's Stateflow Machine, then every chart it owns. EML
    % (MATLAB Function) blocks live as charts with type='EM'.
    mdlObj = rt.find('-isa', 'Stateflow.Machine', '-and', 'Name', mdl);
    if isempty(mdlObj), return, end

    charts = mdlObj.find('-isa', 'Stateflow.EMChart');
    cap = 15;
    for i = 1:numel(charts)
        c = charts(i);
        try
            src = c.Script;
            if isempty(src), continue, end
            txt = char(src);
            lines = strsplit(txt, newline);
            % LoC = non-empty, non-comment lines
            loc = 0;
            depth = 0;
            maxDepth = 0;
            for k = 1:numel(lines)
                ln = strtrim(lines{k});
                if isempty(ln), continue, end
                if startsWith(ln, '%'), continue, end
                loc = loc + 1;
                tok = regexp(ln, '^\s*(if|for|while|switch|try|function)\b', 'tokens', 'once');
                if ~isempty(tok)
                    depth = depth + 1;
                    if depth > maxDepth, maxDepth = depth; end
                end
                if ~isempty(regexp(ln, '^\s*end\b', 'once')) && depth > 0
                    depth = depth - 1;
                end
            end
            if numel(s.matlab_function_blocks_list) < cap
                s.matlab_function_blocks_list(end+1) = struct( ...
                    'path',        string(c.Path), ...
                    'name',        string(c.Name), ...
                    'loc',         double(loc), ...
                    'max_nesting', double(maxDepth)); %#ok<AGROW>
            end
        catch
        end
    end
catch
end
end
