function out_path = predictor_summary_plot(test_id, score, r)
%PREDICTOR_SUMMARY_PLOT  Per-class predictor summary figure.
% 3 panels: confusion counts (TP/FN/FP) per class, recall vs req
% (DR_min line), median lead time vs req (per-class min line).
% Used by all predictor MIL tests so the verdict figure is consistent.

plot_dir = val.plot_root('mil','predictor');
out_path = fullfile(plot_dir, [char(test_id) '.png']);
classes  = {'OT','OV','UV'};

req = evalin('base', 'req');
DR_MIN  = req.PRD_DR_min;
FAR_MAX = req.PRD_FAR_max;
LEAD_MIN = [req.PRD_LT_OT_min_s, req.PRD_LT_OV_min_s, req.PRD_LT_UV_min_s];

tp = arrayfun(@(s) s.tp, score);
fn = arrayfun(@(s) s.fn, score);
fp = arrayfun(@(s) s.fp, score);
recall = arrayfun(@(s) s.recall, score);
leads  = arrayfun(@(s) s.median_lead_s, score);

verdict = upper(char(r.status));
switch lower(verdict)
    case 'pass',  vcol = [0.20 0.55 0.20];
    case 'fail',  vcol = [0.85 0.20 0.20];
    case 'error', vcol = [0.85 0.20 0.20];
    otherwise,    vcol = [0.40 0.40 0.40];
end

fig = figure('Visible','off','Position',[100 100 1100 380],'Color','w');
try
    tl = tiledlayout(fig, 1, 3, 'TileSpacing','compact','Padding','compact');
    main = sprintf('%s  -  %s', char(r.id), char(r.name));
    title(tl, {main, sprintf('verdict: %s', verdict)}, ...
          'Interpreter','none','FontSize',11,'FontWeight','bold','Color',vcol);

    nexttile;
    bar([tp(:), fn(:), fp(:)]); grid on;
    set(gca,'XTickLabel',classes);
    legend({'TP','FN','FP'},'Location','best','Box','off');
    ylabel('event count'); title('confusion (sample-level)');

    nexttile;
    bar(recall(:)); grid on; hold on;
    set(gca,'XTickLabel',classes); ylim([0 1.05]);
    yline(DR_MIN, 'r--', sprintf('DR\\_min=%.2f', DR_MIN), 'LabelHorizontalAlignment','left');
    if isfield(r.metrics,'FAR')
        yline(FAR_MAX, 'b:', sprintf('FAR observed=%.3f / max=%.3f', r.metrics.FAR, FAR_MAX), ...
              'LabelHorizontalAlignment','right','Color',[0.20 0.40 0.85]);
    end
    ylabel('detection rate'); title('recall vs requirement');

    nexttile;
    b = bar(leads(:)); grid on; hold on;
    set(gca,'XTickLabel',classes);
    plot(1:3, LEAD_MIN, 'r--s', 'MarkerSize',8, 'LineWidth',1.4);
    legend([b, plot(NaN,NaN,'r--s','MarkerSize',8,'LineWidth',1.4)], ...
        {'median observed','min req'}, 'Location','best','Box','off');
    ylabel('lead time [s]'); title('alarm lead-time vs req');

    exportgraphics(fig, out_path, 'Resolution', 120);
catch ME
    warning('val:predictor_summary_plot:render', '%s plot failed: %s', char(test_id), ME.message);
    out_path = '';
end
close(fig);
end
