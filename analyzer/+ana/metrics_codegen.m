function s = metrics_codegen(proj, mdl)
% ana.metrics_codegen -- Lightweight generated-C metrics for `mdl`.
%
% Walks <proj>/<mdl>_ert_rtw/ if it exists and counts files, total LoC
% (excluding blank + comment-only lines) and the size of the main C file.
% Returns zeros if no codegen folder is present.

s = struct('present',     false, ...
           'root',        "", ...
           'n_c_files',   0, ...
           'n_h_files',   0, ...
           'loc_total',   0, ...
           'loc_main_c',  0);

candidates = { ...
    fullfile(proj, [mdl '_ert_rtw']), ...
    fullfile(proj, 'slprj', 'ert', mdl)};
codeRoot = '';
for i = 1:numel(candidates)
    if isfolder(candidates{i}), codeRoot = candidates{i}; break, end
end
if isempty(codeRoot), return; end

s.present = true;
s.root    = string(codeRoot);

cFiles = dir(fullfile(codeRoot, '*.c'));
hFiles = dir(fullfile(codeRoot, '*.h'));
s.n_c_files = numel(cFiles);
s.n_h_files = numel(hFiles);

for i = 1:numel(cFiles)
    n = count_loc(fullfile(cFiles(i).folder, cFiles(i).name));
    s.loc_total = s.loc_total + n;
    if strcmpi(cFiles(i).name, [mdl '.c'])
        s.loc_main_c = n;
    end
end
for i = 1:numel(hFiles)
    s.loc_total = s.loc_total + count_loc(fullfile(hFiles(i).folder, hFiles(i).name));
end
end


function n = count_loc(file)
% Effective LoC: non-blank, non comment-only lines. Tolerant of any error.
n = 0;
try
    fid = fopen(file, 'r');
    if fid < 0, return, end
    c = onCleanup(@() fclose(fid)); %#ok<NASGU>
    while true
        line = fgetl(fid);
        if ~ischar(line), break, end
        t = strtrim(line);
        if isempty(t),                continue, end
        if startsWith(t, '//'),       continue, end
        if startsWith(t, '/*') && endsWith(t, '*/'), continue, end
        if startsWith(t, '*'),        continue, end
        n = n + 1;
    end
catch
end
end
