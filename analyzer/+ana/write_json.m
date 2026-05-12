function write_json(s, file)
% ana.write_json -- Pretty-printed JSON dump (creates parent folder).
[d, ~, ~] = fileparts(file);
if ~isempty(d) && ~isfolder(d), mkdir(d); end
fid = fopen(file, 'w');
if fid < 0, error('ana:write_json', 'cannot open %s', file); end
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(s, 'PrettyPrint', true));
end
