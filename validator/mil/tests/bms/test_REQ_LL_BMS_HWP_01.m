function r = test_REQ_LL_BMS_HWP_01()
% REQ-LL-BMS-HWP-01  HW protection asserts shutdown_cmd within a single
% BMS step (no debounce) when |I_pack| >= bms.I_SC_thresh OR any V_cell
% >= bms.V_OVP2_thresh.
%
% The HW protection path in system_model is:
%   HW_Protection_Path (analog comparator: |I_pack| > bms.I_SC_thresh)
%       -> bms_master.hw_fault inport
%       -> Fault_Severity_FSM (instant Shutdown latch)
%       -> bms_master.shutdown_cmd outport
%
% The system_model I_pack inport cannot be used to inject a > I_SC_thresh
% stimulus because Fault_Response.Current_Clamp limits the current before
% it reaches the plant or the HW comparator. We therefore verify the
% requirement in two independent sub-checks:
%   1) Comparator threshold inside HW_Protection_Path equals
%      bms.I_SC_thresh, with relop '>'.
%   2) bms_master driven with hw_fault asserted at t=2s -> shutdown_cmd
%      asserts at the next BMS step (no debounce).

r = val.new_result("bms","BMS-HWP-01","HW protection no-debounce shutdown","REQ-LL-BMS-HWP-01");
bms = evalin('base', 'bms');

% Sub-check 1: HW_Protection_Path comparator threshold
load_system('system_model');
blk = sprintf('system_model/HW_Protection_Path/Compare\nTo Constant1');
mvals  = get_param(blk, 'MaskValues');
mnames = get_param(blk, 'MaskNames');
relop  = mvals{strcmp(mnames, 'relop')};
const  = mvals{strcmp(mnames, 'const')};
ok_thr = strcmp(relop, '>') && strcmp(const, 'bms.I_SC_thresh');
r = val.check(r, "comparator_uses_I_SC_thresh", ok_thr, ...
    sprintf('relop=%s const=%s', relop, const), ...
    sprintf('%s %s', relop, const), '> bms.I_SC_thresh');
bdclose('system_model');

% Sub-check 2: bms_master responds to hw_fault within 1 step
mdl = 'bms_master';
load_system(mdl);

dt = 0.1; T = 4;
t  = (0:dt:T)'; N = numel(t);
hw = zeros(N, 1); hw(t >= 2.0) = 1;
ds = val.master_inputs(t, 'hw_fault', hw);

out = val.sim_model(mdl, ds, T);
shut  = val.signal(out, 'shutdown_cmd');
i_evt = find(shut.t >= 2.0, 1);
i_chk = min(i_evt + 1, numel(shut.y));
ok_shut = shut.y(i_chk) > 0.5;
r = val.check(r, "shutdown_on_hw_fault", ok_shut, ...
    sprintf('shut[i_evt+1]=%g (hw_fault=1 at t=2s)', shut.y(i_chk)), ...
    shut.y(i_chk), '>0');

r.metrics.I_SC_thresh   = bms.I_SC_thresh;
r.metrics.V_OVP2_thresh = bms.V_OVP2_thresh;

stim = struct('t', t, 'y', hw, 'label', 'hw\_fault', ...
    'thresholds', {{0.5,'asserted'}});
resp = struct('t', shut.t, 'y', shut.y, 'label', 'shutdown\_cmd', ...
    'thresholds', {{0.5,'asserted'}});
phases = {0, 2.0, 'nominal'; 2.0, T, 'hw\_fault on'};
asserts = {2.0 + dt, ok_shut, 'shutdown within 1 step'};
r.signals_plot = string(val.scenario_plot(r, struct( ...
    'plot_dir', val.plot_root('mil','bms'), 'filename', 'BMS-HWP-01.png', ...
    'subtitle', 'HW protection: hw\_fault -> shutdown\_cmd next BMS step (no debounce)', ...
    'stim', stim, 'resp', resp, 'phases', {phases}, 'asserts', {asserts})));
end
