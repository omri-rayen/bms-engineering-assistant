function req = requirement(reqId)
% Look up a requirement by ID in validator/requirements/requirements.json.
% Returns the matching low_level (or high_level) entry as a struct.
persistent cache
if isempty(cache)
    here = fileparts(mfilename('fullpath'));
    file = fullfile(here, '..', 'requirements', 'requirements.json');
    cache = jsondecode(fileread(file));
end
all = [cache.low_level(:); cache.high_level(:)];
for i = 1:numel(all)
    if strcmp(all(i).id, reqId)
        req = all(i);
        return
    end
end
error('val:requirement:notFound', 'Requirement %s not in requirements.json', reqId);
end
