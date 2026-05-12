function out_path = scenario_plot(r, opts)
%SCENARIO_PLOT  Render a narrative-timeline figure for one validation
% scenario: stimulus on top, BMS response below, with phase-bands,
% threshold lines, assertion-verdict markers and a verdict banner.
%
% This replaces the old grid-of-separated-I/O picture (val.plot_io)
% with a single, story-oriented figure that makes the test logic
% readable at a glance: "this is what we injected, this is how the
% BMS reacted, here is where the checks fired, PASS/FAIL".
%
%   out_path = val.scenario_plot(r, opts)
%
% r        the val.new_result struct (used for suite, id, status,
%          checks). The function does NOT mutate r; the caller can
%          assign the returned path to r.signals_plot.
%
% opts     struct with the following fields (all optional except
%          plot_dir + at least one of stim/resp):
%   plot_dir   target folder (created if missing)
%   filename   PNG filename (default: char(r.id)+'.png')
%   subtitle   short string under main title
%   stim       struct array, one element per stimulus panel:
%                .t        Nx1 time vector
%                .y        N x M signal (M >= 1; first column is the
%                          highlighted trace, rest plotted faint)
%                .label    y-axis label (e.g. 'V_cell_6 [V]')
%                .units    optional, appended to threshold labels
%                .channels optional cellstr of column names (M)
%                .thresholds optional Mx2 cell { value, label }
%   resp       same shape as stim, for response panels
%   phases     Kx3 cell { t_start, t_end, label } - shaded vertical
%              bands across all axes
%   asserts    Kx3 cell { t, ok_logical, label } - vertical lines +
%              colored markers (green=pass, red=fail) on the bottom axis
%
% The figure has one column. Top half = stim panels, bottom half =
% resp panels. All axes share the x-axis. The figure title carries
% the requirement id and the overall verdict.

if nargin < 2 || ~isstruct(opts), opts = struct(); end
if ~isfield(opts, 'plot_dir') || isempty(opts.plot_dir)
    error('val:scenario_plot:noDir', 'opts.plot_dir is required');
end
if ~isfield(opts, 'filename') || isempty(opts.filename)
    opts.filename = char(r.id) + ".png";
end
if ~isfolder(opts.plot_dir), mkdir(opts.plot_dir); end

stim    = local_get(opts, 'stim',    []);
resp    = local_get(opts, 'resp',    []);
phases  = local_get(opts, 'phases',  {});
asserts = local_get(opts, 'asserts', {});
subtitle = local_get(opts, 'subtitle', '');

% Normalize panel structs to a common field set so vertcat succeeds
% even when callers omit optional fields (thresholds / channels / units).
stim = local_normalize_panels(stim);
resp = local_normalize_panels(resp);
panels = [stim(:); resp(:)];
if isempty(panels), out_path = ''; return, end

n_stim = numel(stim);
n_resp = numel(resp);
nP     = n_stim + n_resp;

out_path = fullfile(opts.plot_dir, char(opts.filename));
fig_h = max(220, 200 + 160*nP);
fig = figure('Visible','off','Position',[100 100 1100 fig_h], 'Color','w');
try
    tl = tiledlayout(fig, nP, 1, 'TileSpacing','compact','Padding','compact');

    % --- Title + verdict banner -----------------------------------
    verdict = upper(char(r.status));
    switch lower(verdict)
        case 'pass',  vcol = [0.20 0.55 0.20];
        case 'fail',  vcol = [0.85 0.20 0.20];
        case 'error', vcol = [0.85 0.20 0.20];
        otherwise,    vcol = [0.40 0.40 0.40];
    end
    main = sprintf('%s  -  %s', char(r.id), char(r.name));
    if isempty(subtitle)
        ttl = {main, sprintf('verdict: %s', verdict)};
    else
        ttl = {main, char(subtitle), sprintf('verdict: %s', verdict)};
    end
    th = title(tl, ttl, 'Interpreter','none','FontSize',11,'FontWeight','bold');
    th.Color = vcol;

    % --- Global x-range across all panels -------------------------
    xmin = inf; xmax = -inf;
    for k = 1:nP
        if ~isempty(panels(k).t)
            xmin = min(xmin, panels(k).t(1));
            xmax = max(xmax, panels(k).t(end));
        end
    end
    if ~isfinite(xmin), xmin = 0; xmax = 1; end

    % --- Render panels --------------------------------------------
    axesAll = gobjects(nP, 1);
    for k = 1:nP
        ax = nexttile(tl);
        axesAll(k) = ax;
        p = panels(k);
        is_stim = (k <= n_stim);
        local_render_phases(ax, phases, xmin, xmax);
        local_render_panel(ax, p, is_stim);
        if k < nP
            ax.XTickLabel = [];
        else
            xlabel(ax, 't [s]');
        end
        xlim(ax, [xmin xmax]);
        grid(ax, 'on');
        ax.GridAlpha = 0.25;
    end

    % --- Assertion markers on the LAST axis (bottom) --------------
    if ~isempty(asserts) && nP > 0
        local_render_asserts(axesAll(end), asserts, xmin, xmax);
    end

    % Legend for phases at the top axis (one entry per unique label).
    if ~isempty(phases) && nP > 0
        local_phase_legend(axesAll(1), phases);
    end

    exportgraphics(fig, out_path, 'Resolution', 120);
catch ME
    warning('val:scenario_plot:render', 'render failed for %s: %s', char(r.id), ME.message);
    out_path = '';
end
close(fig);
end

% ------------------------------------------------------------------
function v = local_get(s, fld, dflt)
if isfield(s, fld) && ~isempty(s.(fld)), v = s.(fld); else, v = dflt; end
end

function local_render_panel(ax, p, is_stim)
hold(ax, 'on');
y = p.y;
if isvector(y), y = y(:); end
t = p.t(:);
M = size(y, 2);
chans = local_get(struct('channels',{[]}), 'channels', {});
if isfield(p, 'channels') && ~isempty(p.channels), chans = p.channels; end

% Faint background traces for non-focus channels.
if M > 1
    for j = 2:M
        plot(ax, t, y(:, j), '-', 'Color', [0.7 0.75 0.82 0.55], 'LineWidth', 0.5);
    end
end
% Focus trace = first column.
if is_stim
    main_col = [0.10 0.45 0.85];
else
    main_col = [0.85 0.33 0.10];
end
plot(ax, t, y(:, 1), '-', 'Color', main_col, 'LineWidth', 1.6);

% Threshold lines.
if isfield(p, 'thresholds') && ~isempty(p.thresholds)
    th = p.thresholds;
    for ti = 1:size(th, 1)
        val_y = th{ti, 1};
        lbl   = char(th{ti, 2});
        yline(ax, val_y, '--', lbl, 'Color',[0.4 0.4 0.4], ...
              'LabelHorizontalAlignment','left', 'LabelVerticalAlignment','bottom', ...
              'FontSize',8, 'Alpha',0.7);
    end
end

if isfield(p, 'label') && ~isempty(p.label)
    ylabel(ax, p.label, 'FontSize',9, 'Interpreter','none');
end

% Ensure y-limits include thresholds + signal range with small margin.
yall = y(:);
if isfield(p, 'thresholds') && ~isempty(p.thresholds)
    yall = [yall; cell2mat(p.thresholds(:,1))];
end
ymin = min(yall); ymax = max(yall);
if ymax - ymin < 1e-9, ymax = ymin + 1; end
m = 0.08*(ymax-ymin);
ylim(ax, [ymin-m, ymax+m]);

if M > 1 && ~isempty(chans)
    % Build a legend matching the number of plotted lines:
    % faint background lines (cols 2..M) + the focus line (col 1) last.
    leg = cell(1, M);
    for j = 2:M
        if numel(chans) >= j, leg{j-1} = char(chans{j}); else, leg{j-1} = sprintf('ch%d', j); end
    end
    leg{M} = char(chans{1});
    legend(ax, leg, 'Location','best', 'FontSize',7, 'Box','off');
end
hold(ax, 'off');
end

function P = local_normalize_panels(P)
%LOCAL_NORMALIZE_PANELS  Force every panel struct to share the same
% field set so [stim(:); resp(:)] vertcat succeeds. Accepts either a
% struct array or a cell array of dissimilar structs (the latter avoids
% the horzcat-of-mismatched-fields error at the call site).
if isempty(P), return, end
flds = {'t','y','label','units','channels','thresholds'};
if iscell(P)
    items = P;
    P = struct('t',{},'y',{},'label',{},'units',{}, ...
               'channels',{},'thresholds',{});
    for k = 1:numel(items)
        s = items{k};
        for f = 1:numel(flds)
            if ~isfield(s, flds{f}), s.(flds{f}) = []; end
        end
        P(k) = orderfields(s, flds); %#ok<AGROW>
    end
    return
end
for k = 1:numel(P)
    for f = 1:numel(flds)
        if ~isfield(P(k), flds{f}), P(k).(flds{f}) = []; end
    end
end
P = orderfields(P, flds);
end

function local_render_phases(ax, phases, xmin, xmax)
if isempty(phases), return, end
hold(ax, 'on');
% A small palette so different phases are visually separable.
pal = [0.92 0.94 0.99;
       0.99 0.94 0.85;
       0.92 0.99 0.92;
       0.99 0.92 0.92;
       0.94 0.92 0.99;
       0.99 0.99 0.85];
yl = ylim(ax);
for i = 1:size(phases, 1)
    t0 = max(phases{i,1}, xmin);
    t1 = min(phases{i,2}, xmax);
    if t1 <= t0, continue, end
    c = pal(mod(i-1, size(pal,1)) + 1, :);
    patch(ax, [t0 t1 t1 t0], [yl(1) yl(1) yl(2) yl(2)], c, ...
          'EdgeColor','none', 'FaceAlpha', 0.55, 'HandleVisibility','off');
end
hold(ax, 'off');
end

function local_phase_legend(ax, phases)
% One labeled patch per phase row, drawn as a small dummy outside the
% data area, just to provide a legend.
labels = phases(:, 3);
hold(ax, 'on');
hh = gobjects(size(phases, 1), 1);
pal = [0.92 0.94 0.99;
       0.99 0.94 0.85;
       0.92 0.99 0.92;
       0.99 0.92 0.92;
       0.94 0.92 0.99;
       0.99 0.99 0.85];
for i = 1:size(phases, 1)
    c = pal(mod(i-1, size(pal,1)) + 1, :);
    hh(i) = patch(ax, NaN(1,4), NaN(1,4), c, 'EdgeColor','none', 'FaceAlpha',0.55);
end
legend(ax, hh, labels, 'Location','northoutside', 'Orientation','horizontal', ...
       'FontSize',8, 'Box','off');
hold(ax, 'off');
end

function local_render_asserts(ax, asserts, xmin, xmax)
hold(ax, 'on');
yl = ylim(ax);
ymark = yl(2);
for i = 1:size(asserts, 1)
    t = asserts{i, 1};
    ok = logical(asserts{i, 2});
    lbl = char(asserts{i, 3});
    if t < xmin || t > xmax, continue, end
    if ok, c = [0.20 0.55 0.20]; sym = 'o'; else, c = [0.85 0.20 0.20]; sym = 'x'; end
    xline(ax, t, ':', 'Color', [0.5 0.5 0.5], 'Alpha', 0.6, 'HandleVisibility','off');
    plot(ax, t, ymark, sym, 'MarkerEdgeColor', c, 'MarkerFaceColor', c, ...
         'MarkerSize', 9, 'LineWidth', 1.5, 'HandleVisibility','off');
    text(ax, t, ymark, ['  ' lbl], 'Color', c, 'FontSize', 8, ...
         'VerticalAlignment','top', 'Interpreter','none');
end
hold(ax, 'off');
end
