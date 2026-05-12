function r = test_REQ_LL_BMS_PRD_01()
% REQ-LL-BMS-PRD-01  Walk every fault class (OV/UV/OT/UT) through
% none -> warn -> derate -> shut on one slave at a time using the
% encoded fault_flags_8 input. Encoding (per slave, 8-bit packed):
%   bits 0-1 = OV severity, bits 2-3 = UV, bits 4-5 = OT, bits 6-7 = UT
%   each field: 0=none, 1=warn, 2=derate, 3=shut.
% This drives every per-class debounce compare (warn/derate/shut) in
% Fault_Debounce to both true and false outcomes. V/T extremes are
% applied in parallel so the fault_predictor also fires.

r = val.new_result("bms","BMS-PRD-01","Per-class fault ladder via fault_flags_8 + predictor","REQ-LL-BMS-PRD-01");

mdl = 'bms_master';
load_system(mdl);
bms = evalin('base', 'bms');
dt  = 0.1;

% One step long enough for shut debounce + slack.
step = (bms.N_debounce_derate + 20) * dt;        % ~5 s
recv = 1.5;                                      % recovery between classes
% Final broadcast phase: all 8 slaves get all 4 classes at warn, then
% derate, then shut, so every per-slave debounce compare lane evaluates
% to true (covers T-outcomes on slaves not exercised by the per-class loop).
T    = 4 * (3*step + recv) + 3*step + 5;
t    = (0:dt:T)'; N = numel(t);

% Per-class encoded values (severity << bit_offset).
shifts  = struct('OV', 0, 'UV', 2, 'OT', 4, 'UT', 6);
classes = {'OV','UV','OT','UT'};

ff  = zeros(N, 8);
V96 = repmat(3.70, N, 96);
T32 = repmat(25.0, N, 32);

for ci = 1:4
    cls  = classes{ci};
    sh   = shifts.(cls);
    base = (ci-1) * (3*step + recv) + 1.0;
    a = base;            b = base + step;        % warn
    c = b;               d = c + step;           % derate
    e = d;               f = e + step;           % shut
    sl = 1 + 2*(ci-1);   % spread across slaves 1,3,5,7
    ff(t >= a & t < b, sl) = bitshift(uint8(1), sh);
    ff(t >= c & t < d, sl) = bitshift(uint8(2), sh);
    ff(t >= e & t < f, sl) = bitshift(uint8(3), sh);

    switch cls
        case 'OV', V96(t >= a & t < f, :) = bms.V_OV_shut + 0.02;
        case 'UV', V96(t >= a & t < f, :) = bms.V_UV_shut - 0.02;
        case 'OT', T32(t >= a & t < f, :) = bms.T_OT_shut + 1;
        case 'UT', T32(t >= a & t < f, :) = bms.T_UT_shut - 1;
    end
end

% Broadcast ladder on ALL slaves: warn -> derate -> shut for every class.
bcastBase = 4 * (3*step + recv) + 1.0;
broadcast_levels = [1, 2, 3];
for li = 1:3
    a = bcastBase + (li-1) * step;
    b = a + step;
    sev_field = broadcast_levels(li);
    enc = bitor(bitor(sev_field, bitshift(sev_field, 2)), ...
                bitor(bitshift(sev_field, 4), bitshift(sev_field, 6)));
    ff(t >= a & t < b, :) = enc;
end

ds  = val.master_inputs(t, 'fault_flags_8', ff, ...
                          'V_cells_96', V96, 'T_sensors_32', T32, ...
                          'T_coolant', 25*ones(N,1));
out = val.sim_model(mdl, ds, T);

sev   = val.signal(out, 'fault_severity').y;
alarm = val.signal(out, 'alarm_3').y;

ok_shut = max(sev) >= 3;
r = val.check(r, "fsm_reaches_shut", ok_shut, sprintf('max(sev)=%g', max(sev)), max(sev), '>=3');

per_class_fired = any(alarm > 0.5, 1);
r = val.check(r, "predictor_at_least_one_class", sum(per_class_fired) >= 1, ...
    sprintf('classes fired = %d', sum(per_class_fired)), sum(per_class_fired), '>=1');

ok_quiet = max(alarm(t < 0.8, :), [], 'all') < 0.5;
r = val.check(r, "predictor_quiet_baseline", ok_quiet, '', max(alarm(t<0.8,:),[],'all'), '<0.5');

r.metrics.classes_fired = sum(per_class_fired);
r.metrics.max_severity  = max(sev);

% Storyboard: per-class fault encoding amplitude on the spiked slave +
% FSM severity + alarm activity (count of asserted classes).
stim_levels = max(double(ff), [], 2);
stim = struct('t', t, 'y', stim_levels, 'label', 'max(fault\_flags\_8) raw byte');
alarm_count = sum(alarm > 0.5, 2);
resp_sev   = struct('t', t, 'y', sev,         'label', 'fault\_severity', ...
    'thresholds', {{1,'warn'; 2,'derate'; 3,'shut'}});
resp_alarm = struct('t', t, 'y', alarm_count, 'label', '#predictor classes alarming', ...
    'thresholds', {{1,'>=1 class'}});
phases = cell(4+3, 3);
for ci = 1:4
    base = (ci-1) * (3*step + recv) + 1.0;
    phases(ci,:) = {base, base + 3*step, classes{ci}};
end
bcastBase = 4 * (3*step + recv) + 1.0;
sev_names = {'warn','derate','shut'};
for li = 1:3
    a = bcastBase + (li-1) * step;
    phases(4+li,:) = {a, a + step, sprintf('all-slave %s', sev_names{li})};
end
asserts = {bcastBase + 3*step, ok_shut, 'sev>=3'; ...
           bcastBase,           sum(per_class_fired)>=1, '>=1 class fired'};
r.signals_plot = string(val.scenario_plot(r, struct( ...
    'plot_dir', val.plot_root('mil','bms'), 'filename', 'BMS-PRD-01.png', ...
    'subtitle', 'OV/UV/OT/UT walked through warn/derate/shut + LSTM predictor', ...
    'stim', stim, 'resp', [resp_sev resp_alarm], 'phases', {phases}, 'asserts', {asserts})));
end
