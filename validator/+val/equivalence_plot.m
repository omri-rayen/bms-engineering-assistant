function out_path = equivalence_plot(r, opts)
%EQUIVALENCE_PLOT  Side-by-side MIL vs SIL / MIL vs PIL signal overlay
% with shaded tolerance envelope and verdict banner. Used by SIL-EQ-01,
% PIL-PRD-01 (and any future host vs target equivalence test).
%
%   out_path = val.equivalence_plot(r, opts)
%
% opts fields:
%   plot_dir  (required) target folder, mkdir'd if missing
%   filename  png filename, default = char(r.id)+'.png'
%   ref_label  e.g. 'MIL'
%   tgt_label  e.g. 'SIL' or 'PIL'
%   tol_abs    scalar absolute tolerance (drawn as +/- band on err)
%   tol_rel    optional, displayed in subtitle
%   signals   Kx1 struct array, each element:
%       .name    signal name
%       .t       time vector
%       .y_ref   reference samples
%       .y_tgt   target samples (same size, truncated if needed)
%
% Renders K rows x 2 cols: left = overlay, right = abs error vs tol.

if nargin<2 || ~isstruct(opts), error('val:equivalence_plot:opts','opts required'); end
if ~isfield(opts,'plot_dir') || isempty(opts.plot_dir), error('val:equivalence_plot:noDir','plot_dir required'); end
if ~isfield(opts,'filename') || isempty(opts.filename), opts.filename = char(r.id) + ".png"; end
if ~isfolder(opts.plot_dir), mkdir(opts.plot_dir); end

ref = local_get(opts,'ref_label','MIL');
tgt = local_get(opts,'tgt_label','SIL');
tol_abs = local_get(opts,'tol_abs',0);
tol_rel = local_get(opts,'tol_rel',[]);
sigs = opts.signals;
K = numel(sigs);

verdict = upper(char(r.status));
switch lower(verdict)
    case 'pass',  vcol = [0.20 0.55 0.20];
    case 'fail',  vcol = [0.85 0.20 0.20];
    case 'error', vcol = [0.85 0.20 0.20];
    otherwise,    vcol = [0.40 0.40 0.40];
end

out_path = fullfile(opts.plot_dir, char(opts.filename));
fig = figure('Visible','off','Position',[100 100 1200 max(280, 200*K)], 'Color','w');
try
    tl = tiledlayout(fig, K, 2, 'TileSpacing','compact','Padding','compact');
    main = sprintf('%s  -  %s', char(r.id), char(r.name));
    sub = sprintf('%s vs %s   |   abs tol = %.1e', ref, tgt, tol_abs);
    if ~isempty(tol_rel)
        sub = sprintf('%s   |   rel tol = %.1e', sub, tol_rel);
    end
    title(tl, {main, sub, sprintf('verdict: %s', verdict)}, ...
          'Interpreter','none','FontSize',11,'FontWeight','bold','Color',vcol);

    for k = 1:K
        s = sigs(k);
        L = min(size(s.y_ref,1), size(s.y_tgt,1));
        t = s.t(1:L);
        a = s.y_ref(1:L,:); b = s.y_tgt(1:L,:);
        e = abs(a - b);

        ax1 = nexttile(tl, (k-1)*2 + 1);
        hold(ax1,'on');
        for c = 1:size(a,2)
            plot(ax1, t, a(:,c), '-',  'Color',[0.10 0.10 0.10 0.85], 'LineWidth',1.0);
        end
        for c = 1:size(b,2)
            plot(ax1, t, b(:,c), '--', 'Color',[0.85 0.33 0.10 0.85], 'LineWidth',1.0);
        end
        grid(ax1,'on'); ylabel(ax1, char(s.name), 'Interpreter','none','FontSize',9);
        if k == 1, legend(ax1, {ref, tgt}, 'Location','best','Box','off','FontSize',8); end
        if k == K, xlabel(ax1,'t [s]'); else, ax1.XTickLabel = []; end

        ax2 = nexttile(tl, (k-1)*2 + 2);
        hold(ax2,'on');
        for c = 1:size(e,2)
            plot(ax2, t, e(:,c), '-', 'Color',[0.20 0.40 0.85 0.85], 'LineWidth',1.0);
        end
        yline(ax2, tol_abs, 'r--', sprintf('abs tol = %.1e', tol_abs), ...
              'LabelHorizontalAlignment','right','FontSize',8);
        max_e = max(e,[],'all');
        if max_e == 0, max_e = tol_abs; end
        ylim(ax2, [0, max(1.1*max_e, 1.5*tol_abs)]);
        grid(ax2,'on'); ylabel(ax2, sprintf('|err| max=%.2e', max_e), 'FontSize',9);
        if k == K, xlabel(ax2,'t [s]'); else, ax2.XTickLabel = []; end
    end

    exportgraphics(fig, out_path, 'Resolution',120);
catch ME
    warning('val:equivalence_plot:render','%s render failed: %s', char(r.id), ME.message);
    out_path = '';
end
close(fig);
end

function v = local_get(s,fld,dflt)
if isfield(s,fld) && ~isempty(s.(fld)), v = s.(fld); else, v = dflt; end
end
