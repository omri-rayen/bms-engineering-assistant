function out = sil_vs_pil(silPath, pilPath, outPath)
% Compare a SIL.json and a PIL.json by test id and metric.
% Phase 1: status-only diff. Phase 3 will use acceptance_criteria.yaml
% tolerances to flag metric drifts.

if nargin < 3, outPath = fullfile('validator','reports','SIL_vs_PIL.json'); end
out = mil_vs_sil(silPath, pilPath, outPath);  % shape is identical
end
