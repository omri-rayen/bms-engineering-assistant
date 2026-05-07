function s = summarize(results)
% Roll up a list of result structs into counts.
s = struct('total', numel(results), 'pass', 0, 'fail', 0, 'error', 0, 'skipped', 0);
for i = 1:numel(results)
    switch results(i).status
        case "pass",    s.pass    = s.pass + 1;
        case "fail",    s.fail    = s.fail + 1;
        case "error",   s.error   = s.error + 1;
        case "skipped", s.skipped = s.skipped + 1;
    end
end
end
