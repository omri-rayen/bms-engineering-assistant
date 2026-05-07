function r = check(r, name, ok, detail, value, expected)
% Append a single pass/fail check to a result struct and update overall status.
%   ok       logical  true = pass
%   detail   string   short human description
%   value    numeric/logical/string  observed value (optional)
%   expected numeric/logical/string  expected value (optional)
if nargin < 5, value = []; end
if nargin < 6, expected = []; end

c = struct( ...
    'name',     string(name), ...
    'status',   ternary(ok, "pass", "fail"), ...
    'detail',   string(detail), ...
    'value',    value, ...
    'expected', expected);
r.checks(end+1) = c;

% Overall status: any failed check fails the test (errors set elsewhere).
if ~ok && r.status ~= "error"
    r.status = "fail";
elseif r.status == "skipped"
    r.status = "pass";
end
end

function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end
