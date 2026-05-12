function r = test_REQ_LL_BMS_BAL_01()
% REQ-LL-BMS-BAL-01  enable_bal=false -> I_bal_12=0; enable_bal=true ->
% the highest-V cell drains at bms.bal_I_nom.
r = val.new_result("bms","BMS-BAL-01","Slave balancing on/off + target","REQ-LL-BMS-BAL-01");

mdl = 'bms_slave';
load_system(mdl);
bms = evalin('base', 'bms');

dt = 0.1; T = 6;
t  = (0:dt:T)'; N = numel(t);

V12 = repmat(3.70, N, 12);
V12(:, 5) = 3.73;
T4  = 25*ones(N, 4);
en  = zeros(N, 1);
en(t >= 2.0 & t < 4.0) = 1;

ds  = val.dataset_from('V_cells_12', t, V12, 'T_sensors_4', t, T4, 'enable_bal', t, en);
out = val.sim_model(mdl, ds, T);
I_bal = val.signal(out, 'I_bal_12').y;

mask_off_pre  = t <  2.0;
mask_on       = t >= 2.5 & t < 3.9;
mask_off_post = t >= 4.5;

ok1 = all(abs(I_bal(mask_off_pre, :)) < 1e-6, 'all');
r = val.check(r, "no_balancing_when_disabled", ok1, '', max(abs(I_bal(mask_off_pre,:)),[],'all'), 0);

[~, idx_max] = max(mean(abs(I_bal(mask_on, :)), 1));
ok2 = idx_max == 5;
r = val.check(r, "drains_highest_cell", ok2, sprintf('argmax = %d', idx_max), idx_max, 5);

I_target = max(abs(I_bal(mask_on, idx_max)));
ok3 = abs(I_target - bms.bal_I_nom) < 0.05;
r = val.check(r, "drain_at_bal_I_nom", ok3, ...
    sprintf('|I| = %.3f A vs bms.bal_I_nom = %.3f A', I_target, bms.bal_I_nom), ...
    I_target, bms.bal_I_nom);

ok4 = all(abs(I_bal(mask_off_post, :)) < 1e-6, 'all');
r = val.check(r, "stops_when_disabled_again", ok4, '', max(abs(I_bal(mask_off_post,:)),[],'all'), 0);

stim_en  = struct('t', t, 'y', en, 'label', 'enable\_bal');
stim_v   = struct('t', t, 'y', V12(:,5), 'label', 'V_{cell,5} [V]   (highest)');
resp = struct('t', t, 'y', I_bal(:,5), 'label', '|I_{bal,5}| [A]', ...
    'thresholds', {{bms.bal_I_nom,'bal\_I\_nom'}});
phases = {0, 2.0, 'disabled'; 2.0, 4.0, 'enabled'; 4.0, T, 'disabled again'};
t_chk = 3.0;
asserts = {0.5,           ok1, 'I=0 (off)'; ...
           t_chk,         ok2, 'argmax=cell5'; ...
           t_chk + 0.1,   ok3, '|I|~=bal\_I\_nom'; ...
           5.0,           ok4, 'I=0 (off again)'};
r.signals_plot = string(val.scenario_plot(r, struct( ...
    'plot_dir', val.plot_root('mil','bms'), 'filename', 'BMS-BAL-01.png', ...
    'subtitle', 'enable\_bal pulse drains highest cell at bal\_I\_nom', ...
    'stim', [stim_en stim_v], 'resp', resp, 'phases', {phases}, 'asserts', {asserts})));
end
