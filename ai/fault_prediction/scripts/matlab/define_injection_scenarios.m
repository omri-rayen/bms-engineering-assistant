function scenarios = define_injection_scenarios()
% Fault injection scenarios. Each entry tweaks a few base parameters and
% comes with a filter that picks the trips it makes physical sense to run on.
%
% Fields per scenario:
%   id, fault       label and target fault class ('OT','OV','UV','nominal')
%   R0_scale        internal-resistance multiplier  (1.0 = unchanged)
%   h_cool_fac      coolant convection multiplier   (1.0 = unchanged)
%   Q_nom_Ah        capacity override [Ah]          (NaN = keep)
%   SoC_init        initial SoC [%]                 (NaN = keep trip value)
%   imbal_scale     cell SoC-spread multiplier      (1.0 = unchanged)
%   T_init_C        uniform initial temperature [C] (NaN = keep trip value)
%   filter          @(trip) -> true if the scenario fits the trip

% Trip filters
high_soc  = @(t) t.SoC_init_pct > 60;
low_soc   = @(t) t.SoC_init_pct < 60;
long_low  = @(t) t.duration_s   > 900 & t.SoC_init_pct < 60;

% Long A-campaign trips with enough current to self-heat past 45 C.
% TripA01/A05 are too gentle to heat up in time, so they are excluded.
warm_long = @(t) t.duration_s > 900 & strncmp(t.trip_id, 'TripA', 5) ...
                 & ~ismember(t.trip_id, {'TripA01','TripA05'});

% TripB04 already crosses OV in its measured data, so it would contaminate
% the healthy class. Keep it out of nominal.
nominal_ok = @(t) ~strcmp(t.trip_id, 'TripB04');

s = struct('id',{},'fault',{},'R0_scale',{},'h_cool_fac',{}, ...
           'Q_nom_Ah',{},'SoC_init',{},'imbal_scale',{},'T_init_C',{},'filter',{});

%               id        fault     R0   hcf   Qnom  SoC0  imb  T0   filter

% Over-temperature: progressively kill the coolant loop on warm long drives
s(end+1) = scen('OT-A',   'OT',     1.0, 0.50, NaN,  NaN, 1.0,  44, warm_long);  % 50% cooling loss
s(end+1) = scen('OT-B',   'OT',     1.0, 0.10, NaN,  NaN, 1.0,  44, warm_long);  % 90% cooling loss
s(end+1) = scen('OT-C',   'OT',     1.0, 0.00, NaN,  NaN, 1.0,  44, warm_long);  % total cooling failure

% Over-voltage: high SoC + capacity fade + cell imbalance pushes the
% weakest cell over 4.15 V on the first regen event
s(end+1) = scen('OV-A',   'OV',     1.0, 1.0,  48,   93,  2.0, NaN, high_soc);   % moderate fade + imbalance
s(end+1) = scen('OV-B',   'OV',     1.0, 1.0,  42,   96,  1.0, NaN, high_soc);   % severe fade, very high SoC
s(end+1) = scen('OV-C',   'OV',     1.0, 1.0,  45,   93,  3.0, NaN, high_soc);   % strong imbalance

% Under-voltage: low SoC + fade drains the weakest cell below 2.80 V;
% cold start further depresses OCV
s(end+1) = scen('UV-A',   'UV',     1.0, 1.0,  36,   25,  1.0, NaN, long_low);   % capacity fade
s(end+1) = scen('UV-B',   'UV',     1.0, 1.0,  36,   20,  1.0,  -5, long_low);   % cold + fade
s(end+1) = scen('UV-C',   'UV',     1.0, 1.0,  30,   15,  1.0, -10, long_low);   % severe cold + fade
s(end+1) = scen('UV-D',   'UV',     1.0, 1.0,  30,   15,  2.0, -15, low_soc);    % near-empty, imbalanced
s(end+1) = scen('UV-E',   'UV',     3.0, 1.0,  NaN,  30,  1.5, NaN, long_low);   % high R0 + moderate imbalance

% Nominal: no injection, healthy reference
s(end+1) = scen('nominal','nominal',1.0, 1.0,  NaN,  NaN, 1.0, NaN, nominal_ok);

scenarios = s;
fprintf('Defined %d scenarios  (OT:%d  OV:%d  UV:%d  nominal:%d)\n', numel(s), ...
    sum(strcmp({s.fault},'OT')), sum(strcmp({s.fault},'OV')), ...
    sum(strcmp({s.fault},'UV')), sum(strcmp({s.fault},'nominal')));
end


function s = scen(id, fault, R0, hcf, Qnom, SoC0, imb, T0, filt)
    s = struct('id',id,'fault',fault,'R0_scale',R0,'h_cool_fac',hcf, ...
               'Q_nom_Ah',Qnom,'SoC_init',SoC0,'imbal_scale',imb, ...
               'T_init_C',T0,'filter',filt);
end
