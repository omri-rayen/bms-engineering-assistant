function [score, byclass] = predictor_score(varargin)
% Run all (class scenario) x (test trip) MIL sims and return aggregated
% sample-level TP/FP/FN counts and per-event lead times per class. Mirrors
% ai/fault_prediction/scripts/python/evaluate.py.
%
%   score    1x3 struct array (one per class OT/OV/UV) with fields
%              tp, fp, fn, recall, leads (vector of per-event lead [s]),
%              n_events, median_lead_s
%   byclass  struct with the same content keyed by name (.OT/.OV/.UV)
%
% Result is cached for the MATLAB session; pass 'force', true to recompute.
p = inputParser;
p.addParameter('force', false);
p.parse(varargin{:});

persistent cached
if ~p.Results.force && ~isempty(cached)
    score   = cached.score;
    byclass = cached.byclass;
    return
end

CLASSES = {'OT','OV','UV'};
score = struct('class',CLASSES, ...
               'tp',{0,0,0},'fp',{0,0,0},'fn',{0,0,0}, ...
               'recall',{0,0,0}, ...
               'leads',{[],[],[]},'n_events',{0,0,0},'median_lead_s',{NaN,NaN,NaN});

mdl = 'system_model';
load_system(mdl);

trips = evalin('base', 'trips_meas');
test_trip_ids = val.test_trip_ids();
scens = define_injection_scenarios();
fault_scens = scens(~strcmp({scens.fault}, 'nominal'));

bms       = evalin('base', 'bms');
predictor = evalin('base', 'predictor');
THR     = [bms.T_OT_warn, bms.V_OV_warn, bms.V_UV_warn];
H       = [predictor.H_OT_samples, predictor.H_OV_samples, predictor.H_UV_samples];
LOOKBACK = predictor.LOOKBACK_samples;
DT       = evalin('base', 'dt');
H_MAX    = max(H);

for s = 1:numel(fault_scens)
    scen = fault_scens(s);
    cls  = find(strcmp(CLASSES, scen.fault), 1);
    for i = 1:numel(test_trip_ids)
        tid = test_trip_ids{i};
        if ~isfield(trips, tid), continue, end
        tr = fp.make_trip(trips, tid);
        if ~scen.filter(tr), continue, end

        snap = val.snapshot_ws();
        try
            fp.set_baseline(tr);
            apply_injection(scen);

            t = tr.time_s;
            Tamb = tr.T_amb_C;
            if ~isnan(scen.T_init_C), Tamb(:) = scen.T_init_C; end
            ds = val.dataset_from('I_pack', t, tr.I_A, 'T_amb', t, Tamb);
            out = val.sim_model(mdl, ds, t(end));

            Vmin = val.signal(out, 'V_cell_min').y;
            Vmax = val.signal(out, 'V_cell_max').y;
            Tmax = val.signal(out, 'T_cell_max').y;
            A    = val.signal(out, 'alarm_3').y;
            sig  = {Tmax, Vmax, Vmin};
            is_upper = [true, true, false];

            N0 = numel(Vmin);
            if N0 <= H_MAX, continue, end
            N = N0 - H_MAX;
            if size(A, 1) < N, continue, end
            a = A(1:N, cls) > 0.5;
            y = local_lookahead(sig{cls}, N, H(cls), THR(cls), is_upper(cls));

            score(cls).tp = score(cls).tp + nnz(a &  y);
            score(cls).fp = score(cls).fp + nnz(a & ~y);
            score(cls).fn = score(cls).fn + nnz(~a & y);

            score(cls).leads = [score(cls).leads; local_event_leads(y, a, LOOKBACK, DT)];
        catch ME
            warning('predictor_score:simFail', '%s/%s: %s', scen.id, tid, ME.message);
        end
        val.restore_ws(snap);
    end
end

for c = 1:3
    n = score(c).tp + score(c).fn;
    if n > 0, score(c).recall = score(c).tp / n; end
    score(c).n_events = numel(score(c).leads);
    if score(c).n_events > 0, score(c).median_lead_s = median(score(c).leads); end
end

byclass = struct();
for c = 1:3, byclass.(CLASSES{c}) = score(c); end

cached = struct('score', score, 'byclass', byclass);
end


function y = local_lookahead(sig, N, H, thr, is_upper)
if is_upper, flag = sig >= thr; else, flag = sig <= thr; end
cs = [0; cumsum(flag(:))];
y  = (cs(1+H : N+H) - cs(1:N)) > 0;
end


function leads = local_event_leads(y, a, LOOKBACK, DT)
% Per-event lead time: for each contiguous y-run, find first alarm sample
% in [start-LOOKBACK, end-1]; lead = (start - first_alarm_idx) * DT.
leads = [];
padded = [false; y(:); false];
edges  = diff(int8(padded));
starts = find(edges ==  1);
ends   = find(edges == -1);
for k = 1:numel(starts)
    s = starts(k); e = ends(k);
    lo = max(1, s - LOOKBACK);
    hits = find(a(lo : e-1), 1, 'first');
    if ~isempty(hits)
        leads(end+1, 1) = (s - (lo + hits - 1)) * DT; %#ok<AGROW>
    end
end
end
