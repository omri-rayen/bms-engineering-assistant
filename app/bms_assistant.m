classdef bms_assistant < matlab.apps.AppBase
    % bms_assistant -- BMS Engineering Assistant UI.
    %
    %   bms_assistant         % launch the app
    %
    % Light, modern layout: left sidebar nav (Dashboard / Validate /
    % Reports / Model) + main content card. The console is collapsible
    % and hidden by default during a run; press "Show log" to expand.

    % ---- palette --------------------------------------------------
    properties (Constant, Access = private)
        BG       = [0.96 0.97 0.98]    % page bg
        SIDE     = [0.18 0.22 0.28]    % sidebar bg
        SIDE_HI  = [0.10 0.45 0.74]    % active nav indicator
        SIDE_FG  = [0.86 0.89 0.93]
        SIDE_MUT = [0.55 0.60 0.66]
        CARD     = [1.00 1.00 1.00]
        BORDER   = [0.88 0.90 0.93]
        INK      = [0.13 0.16 0.20]
        MUTED    = [0.45 0.50 0.55]
        ACCENT   = [0.00 0.45 0.74]
        ACCENT2  = [0.85 0.33 0.10]
        OK       = [0.13 0.55 0.27]
        WARN     = [0.85 0.45 0.10]
        ERR      = [0.78 0.20 0.20]
        BTN_BG   = [0.95 0.96 0.97]    % subtle ghost button
        FONT     = 'Segoe UI'
        MONO     = 'Cascadia Mono'
    end

    properties (Access = public)
        UIFigure        matlab.ui.Figure
        StatusLabel     matlab.ui.control.Label

        % Sidebar
        SideBar         matlab.ui.container.Panel
        NavBtns         struct = struct()       % per-page button handles
        BrandLabel      matlab.ui.control.Label
        BrandSub        matlab.ui.control.Label

        % Pages (visibility toggled by nav)
        DashboardPage   matlab.ui.container.Panel
        ValidatePage    matlab.ui.container.Panel
        ReportsPage     matlab.ui.container.Panel
        PlotsPage       matlab.ui.container.Panel
        ModelPage       matlab.ui.container.Panel
        Pages           struct = struct()

        % Dashboard
        DashStatusValue matlab.ui.control.Label
        DashLastRunLbl  matlab.ui.control.Label
        DashReportsLbl  matlab.ui.control.Label
        DashRunBtn      matlab.ui.control.Button

        % Validate page
        MilCheck        matlab.ui.control.CheckBox
        SilCheck        matlab.ui.control.CheckBox
        PilCheck        matlab.ui.control.CheckBox
        MilSelectedLbl  matlab.ui.control.Label
        MilChooseBtn    matlab.ui.control.Button
        MilSelectedFilters cell        % active MIL filters (cellstr; {''} = all)
        SilDD           matlab.ui.control.DropDown
        PilDD           matlab.ui.control.DropDown
        SkipBuildCheck  matlab.ui.control.CheckBox
        RunBtn          matlab.ui.control.Button
        DownloadJsonBtn matlab.ui.control.Button
        DownloadHtmlBtn matlab.ui.control.Button

        ProgressBarBg   matlab.ui.container.Panel
        ProgressBarFill matlab.ui.container.Panel
        ProgressLabel   matlab.ui.control.Label
        PhaseChips      struct = struct()    % per-phase status pill (uipanel + uilabel)

        ToggleLogBtn    matlab.ui.control.Button
        LogPanel        matlab.ui.container.Panel
        ConsoleArea     matlab.ui.control.TextArea
        LogVisible      logical = false
        ValidateGrid    matlab.ui.container.GridLayout

        % Reports page
        ReportsTable      matlab.ui.control.Table
        RefreshBtn        matlab.ui.control.Button
        OpenHtmlBtn       matlab.ui.control.Button
        SaveJsonBtn       matlab.ui.control.Button
        SaveHtmlBtn       matlab.ui.control.Button
        DeleteReportBtn   matlab.ui.control.Button

        % Plots page (per-test signal previews from latest validation run)
        PlotsSuiteDD      matlab.ui.control.DropDown
        PlotsList         matlab.ui.control.ListBox
        PlotsImage        matlab.ui.control.Image
        PlotsRefreshBtn   matlab.ui.control.Button
        PlotsEmptyLbl     matlab.ui.control.Label

        % Model page
        EditMasterBtn   matlab.ui.control.Button
        EditSlaveBtn    matlab.ui.control.Button
        EditPredictorBtn matlab.ui.control.Button
        SavePilCBtn     matlab.ui.control.Button
        ResetBtn        matlab.ui.control.Button
        ModelInfo       matlab.ui.control.TextArea
    end

    properties (Access = private)
        Scenarios
        LastRun
        ReportRows
        LogBuffer cell = {}
        ActivePage char = 'dashboard'
        % Last-run path selection (for resetting phase chips, etc.).
        PipePaths cell = {}
    end

    methods (Access = public)
        function app = bms_assistant
            createComponents(app);
            registerApp(app, app.UIFigure);
            initState(app);
            if nargout == 0, clear app, end
        end
    end

    methods (Access = private)

        % ===================== state ===============================
        function initState(app)
            app.Scenarios = orch.scenarios();
            populateScenarioDropdowns(app);
            refreshReports(app);
            describeModels(app);
            updateDashboard(app);
            showPage(app, 'dashboard');
            setStatus(app, 'Ready');
        end

        function describeModels(app)
            m = orch.editable_models();
            txt = strings(0,1);
            txt(end+1,1) = "Editable Simulink models:";
            for i = 1:numel(m)
                tag = "OK"; if ~isfile(m(i).src), tag = "MISSING"; end
                txt(end+1,1) = sprintf("  [%s]  %-20s  %s", tag, m(i).name, m(i).src);
            end
            snDir = fullfile(orch.repo_root(),'model','.snapshots');
            txt(end+1,1) = "";
            if isfolder(snDir)
                baks = dir(fullfile(snDir,'*.bak'));
                if isempty(baks)
                    txt(end+1,1) = "Snapshot: none yet (created on first edit).";
                else
                    txt(end+1,1) = sprintf("Snapshot: %d .bak file(s) in %s", numel(baks), snDir);
                end
            else
                txt(end+1,1) = "Snapshot: created on first edit.";
            end
            app.ModelInfo.Value = cellstr(txt);
        end

        function populateScenarioDropdowns(app)
            mil = app.Scenarios(strcmp({app.Scenarios.path},'mil'));
            sil = app.Scenarios(strcmp({app.Scenarios.path},'sil'));
            pil = app.Scenarios(strcmp({app.Scenarios.path},'pil'));
            % MIL scenarios are picked through a checklist popup so the
            % Validate page stays compact. Default = first entry (which
            % is the "All BMS + predictor" wildcard with empty filter).
            if ~isempty(mil)
                app.MilSelectedFilters = {mil(1).filter};
                refreshMilLabel(app);
            end
            app.SilDD.Items     = {sil.label};
            app.SilDD.ItemsData = {sil.filter};
            app.PilDD.Items     = {pil.label};
            app.PilDD.ItemsData = {pil.filter};
        end

        function updateDashboard(app)
            % Status defaults to "Ready" only when no run has happened
            % yet in this session; otherwise leave the value the
            % pipeline set (OK / Failed / Crashed / Cancelled) alone.
            if isempty(app.LastRun)
                app.DashStatusValue.Text = 'Ready';
                app.DashStatusValue.FontColor = app.OK;
            end
            n = 0;
            try, n = numel(orch.list_reports()); catch, end
            app.DashReportsLbl.Text = sprintf('%d report%s available', n, ternary(n==1,'','s'));
            if isempty(app.LastRun) || ~isstruct(app.LastRun)
                app.DashLastRunLbl.Text = 'No run yet in this session';
                return
            end
            % Prefer the doc-phase timestamp; fall back to the wall-clock
            % stamp captured at finalize time so MIL-only / skip-doc runs
            % still update the label.
            ts = '';
            if isfield(app.LastRun,'ts') && ~isempty(app.LastRun.ts)
                ts = char(app.LastRun.ts);
            elseif isfield(app.LastRun,'finished_at') && ~isempty(app.LastRun.finished_at)
                ts = char(app.LastRun.finished_at);
            end
            elapsed = '';
            if isfield(app.LastRun,'elapsed_s') && isnumeric(app.LastRun.elapsed_s)
                elapsed = sprintf(' (%.1fs)', app.LastRun.elapsed_s);
            end
            paths = '';
            if isfield(app.LastRun,'paths') && isstruct(app.LastRun.paths)
                paths = sprintf(' [%s]', strjoin(fieldnames(app.LastRun.paths), '+'));
            end
            if isempty(ts), ts = '-'; end
            app.DashLastRunLbl.Text = sprintf('Last run: %s%s%s', ts, elapsed, paths);
        end

        % ===================== Validate page =======================
        function onRun(app, ~, ~)
            paths = {};
            if app.MilCheck.Value, paths{end+1} = 'mil'; end %#ok<*AGROW>
            if app.SilCheck.Value, paths{end+1} = 'sil'; end
            if app.PilCheck.Value, paths{end+1} = 'pil'; end
            if isempty(paths)
                uialert(app.UIFigure, 'Select at least one validation path.', 'Nothing to run');
                return
            end
            app.PipePaths = paths;
            app.LogBuffer = {};
            app.ConsoleArea.Value = {''};
            updateProgress(app, 'starting', 0);
            resetPhaseChips(app, paths);
            app.DownloadJsonBtn.Enable = 'off';
            app.DownloadHtmlBtn.Enable = 'off';
            app.RunBtn.Enable = 'off';
            app.RunBtn.Text   = 'Running ...';
            app.DashRunBtn.Enable = 'off';
            setStatus(app, 'Pipeline running ...');
            app.DashStatusValue.Text = 'Running'; app.DashStatusValue.FontColor = app.ACCENT;
            drawnow;

            % NOTE: orch.run uses evalin('base', ...) to load init_system,
            % which is unsupported on R2024b backgroundPool (thread-based).
            % Without Parallel Computing Toolbox we cannot get a true
            % async worker, so the pipeline runs in the main thread. UI
            % responsiveness is preserved by:
            %   * a non-recursive ProgressBar SizeChangedFcn (see
            %     createComponents -> local_resize_fill)
            %   * full `drawnow` (not `drawnow limitrate`) inside
            %     appendLog/updateProgress so queued button callbacks --
            %     show/hide log, page nav, etc. -- get processed between
            %     log lines.
            logCb  = @(s) appendLog(app, s);
            progCb = @(name, frac) updateProgress(app, name, frac);
            try
                out = orch.run( ...
                    'paths',       paths, ...
                    'mil_filter',  app.selectedMilFilter(), ...
                    'sil_filter',  app.SilDD.Value, ...
                    'pil_filter',  app.PilDD.Value, ...
                    'skip_build',  app.SkipBuildCheck.Value, ...
                    'log_cb',      logCb, ...
                    'progress_cb', progCb);
                finalizePipeline(app, out, '');
            catch ME
                finalizePipeline(app, [], ME.message);
            end
        end

        function f = selectedMilFilter(app)
            % Translate the current MIL selection into the form mil.run
            % expects: '' (all), single string, or cellstr.
            v = app.MilSelectedFilters;
            if isempty(v), f = ''; return, end
            for i = 1:numel(v)
                if isempty(v{i}), f = ''; return, end
            end
            v = unique(v, 'stable');
            if isscalar(v), f = v{1}; else, f = v; end
        end

        function refreshMilLabel(app)
            % Summarise the current MIL selection on the Validate page.
            v = app.MilSelectedFilters;
            if isempty(v) || (isscalar(v) && isempty(v{1}))
                txt = 'All BMS + predictor';
            elseif isscalar(v)
                txt = labelForFilter(app, v{1});
            else
                txt = sprintf('%d scenarios selected', numel(v));
            end
            app.MilSelectedLbl.Text = txt;
        end

        function lbl = labelForFilter(app, filter)
            mil = app.Scenarios(strcmp({app.Scenarios.path},'mil'));
            ix  = find(strcmp({mil.filter}, filter), 1);
            if isempty(ix), lbl = filter; else, lbl = mil(ix).label; end
        end

        function onChooseMil(app, ~, ~)
            % Modal checklist: one checkbox per MIL scenario. The first
            % entry is the "All" wildcard (empty filter); checking it
            % short-circuits the others.
            mil = app.Scenarios(strcmp({app.Scenarios.path},'mil'));
            if isempty(mil), return, end
            n = numel(mil);

            dlg = uifigure('Name','Select MIL scenarios', ...
                'Position', centerOn(app.UIFigure, 460, min(560, 90+n*26)), ...
                'WindowStyle','modal', 'Color', app.BG);
            g = uigridlayout(dlg, [3 1]);
            g.RowHeight   = {'fit','1x','fit'};
            g.ColumnWidth = {'1x'};
            g.Padding     = [14 14 14 14];
            g.RowSpacing  = 10;
            g.BackgroundColor = app.BG;

            uilabel(g, 'Text','Tick the scenarios to include in this MIL run.', ...
                'FontName', app.FONT, 'FontSize', 12, 'FontColor', app.MUTED);

            scroll = uipanel(g, 'BackgroundColor', app.CARD, ...
                'BorderType','line', 'HighlightColor', app.BORDER); % Removed Scrollable from here
            sg = uigridlayout(scroll, [n 1]);
            sg.Scrollable = 'on'; % Added Scrollable directly to the grid layout
            sg.RowHeight   = repmat({26}, 1, n);
            sg.ColumnWidth = {'1x'};
            sg.Padding     = [10 10 10 10];
            sg.RowSpacing  = 4;
            sg.BackgroundColor = app.CARD;

            current = app.MilSelectedFilters;
            if isempty(current), current = {''}; end
            cbs = gobjects(n,1);
            for i = 1:n
                cbs(i) = uicheckbox(sg, 'Text', mil(i).label, ...
                    'FontName', app.FONT, 'FontSize', 12, ...
                    'Value', any(strcmp(current, mil(i).filter)));
            end

            actions = uipanel(g, 'BackgroundColor', app.BG, 'BorderType','none');
            ag = uigridlayout(actions, [1 4]);
            ag.RowHeight   = {32};
            ag.ColumnWidth = {110, 110, '1x', 110};
            ag.Padding     = [0 0 0 0];
            ag.ColumnSpacing = 8;
            ag.BackgroundColor = app.BG;
            uibutton(ag,'Text','Select all', 'FontName', app.FONT, ...
                'ButtonPushedFcn', @(s,e) arrayfun(@(c) set(c,'Value',true),  cbs));
            uibutton(ag,'Text','Clear',      'FontName', app.FONT, ...
                'ButtonPushedFcn', @(s,e) arrayfun(@(c) set(c,'Value',false), cbs));
            uilabel(ag,'Text','');
            uibutton(ag, 'Text','OK', 'FontName', app.FONT, ...
                'BackgroundColor', app.ACCENT, 'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @(s,e) acceptMilSel(cbs));

            uiwait(dlg);

            function acceptMilSel(cbsLocal)
                picked = {};
                for k = 1:numel(cbsLocal)
                    if cbsLocal(k).Value, picked{end+1} = mil(k).filter; end %#ok<AGROW>
                end
                if isempty(picked), picked = {mil(1).filter}; end
                app.MilSelectedFilters = picked;
                refreshMilLabel(app);
                delete(dlg);
            end
        end

        function finalizePipeline(app, out, err)
            % Always stamp wall-clock for the dashboard, regardless of
            % whether the doc phase ran.
            now_str = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
            if isempty(err) && ~isempty(out) && isstruct(out)
                out.finished_at = now_str;
                app.LastRun = out;
            elseif ~isempty(err)
                app.LastRun = struct('ok', false, 'finished_at', now_str, ...
                                     'error', err);
            end
            if ~isempty(err)
                appendLog(app, sprintf('[orch] FATAL: %s', err));
                setStatus(app, 'Pipeline crashed');
                app.DashStatusValue.Text = 'Crashed'; app.DashStatusValue.FontColor = app.ERR;
            elseif ~isempty(out) && isstruct(out) && isfield(out,'ok') && out.ok
                setStatus(app, sprintf('Pipeline OK in %.1f s', out.elapsed_s));
                app.DashStatusValue.Text = 'OK'; app.DashStatusValue.FontColor = app.OK;
                if isfield(out,'html_part1') && isfile(out.html_part1)
                    app.DownloadHtmlBtn.Enable = 'on';
                elseif isfield(out,'html') && isfile(out.html)
                    app.DownloadHtmlBtn.Enable = 'on';
                end
                if isfield(out,'json') && isfile(out.json), app.DownloadJsonBtn.Enable = 'on'; end
                refreshReports(app);
            else
                setStatus(app, 'Pipeline FAILED');
                app.DashStatusValue.Text = 'Failed'; app.DashStatusValue.FontColor = app.ERR;
            end
            app.RunBtn.Enable = 'on';
            app.RunBtn.Text   = 'Run pipeline';
            app.DashRunBtn.Enable = 'on';
            updateDashboard(app);
        end

        function appendLog(app, line)
            line = char(string(line));
            app.LogBuffer{end+1} = line;
            if numel(app.LogBuffer) > 1500
                app.LogBuffer = app.LogBuffer(end-1499:end);
            end
            if app.LogVisible
                if isempty(app.LogBuffer)
                    app.ConsoleArea.Value = {''};
                else
                    app.ConsoleArea.Value = app.LogBuffer(:);
                end
                try, scroll(app.ConsoleArea, 'bottom'); catch, end
            end
            % Full drawnow (NOT limitrate): processes queued button
            % callbacks so show/hide log, page nav, etc. respond mid-
            % pipeline. Cost is ~1-2 ms per log line, negligible vs sim.
            drawnow;
        end

        function updateProgress(app, name, frac)
            frac = max(0, min(1, frac));
            try
                inner = app.ProgressBarBg.InnerPosition;
            catch
                inner = app.ProgressBarBg.Position;
            end
            W = max(inner(3), 2); H = max(inner(4), 2);
            fillW = max(2, round(W * frac));
            app.ProgressBarFill.Position = [0 0 fillW H];
            if frac >= 0.999
                app.ProgressBarFill.BackgroundColor = app.OK;
            elseif strcmp(name,'error')
                app.ProgressBarFill.BackgroundColor = app.ERR;
            else
                app.ProgressBarFill.BackgroundColor = app.ACCENT;
            end
            app.ProgressLabel.Text = sprintf('%s   %d%%', name, round(100*frac));
            % Mark phase chip active/done
            if isfield(app.PhaseChips, name)
                if frac >= 0.999
                    setPhaseChip(app, name, 'done');
                else
                    setPhaseChip(app, name, 'active');
                end
            end
            % Full drawnow so the user sees progress and can still click
            % buttons between progress ticks.
            drawnow;
        end

        function resetPhaseChips(app, paths)
            % Active phase plan: paths + facts/analyzer/doc.
            % If MIL is selected, also light the COV chip -- coverage now
            % runs in lockstep with MIL (orch.run emits 'cov' progress).
            keys = {};
            for i = 1:numel(paths), keys{end+1} = paths{i}; end %#ok<AGROW>
            if any(strcmp(paths,'mil')), keys{end+1} = 'cov'; end
            keys = [keys, {'facts','analyzer','doc'}];
            for k = 1:numel(keys)
                if isfield(app.PhaseChips, keys{k})
                    setPhaseChip(app, keys{k}, 'pending');
                end
            end
            % Phases not in plan -> hide chip
            allPhases = fieldnames(app.PhaseChips);
            for i = 1:numel(allPhases)
                if ~ismember(allPhases{i}, keys)
                    setPhaseChip(app, allPhases{i}, 'inactive');
                end
            end
        end

        function setPhaseChip(app, name, state)
            chip = app.PhaseChips.(name);
            switch state
                case 'pending'
                    chip.Label.BackgroundColor = [0.94 0.95 0.96];
                    chip.Label.FontColor       = app.MUTED;
                case 'active'
                    chip.Label.BackgroundColor = [0.86 0.93 0.99];
                    chip.Label.FontColor       = app.ACCENT;
                case 'done'
                    chip.Label.BackgroundColor = [0.86 0.96 0.89];
                    chip.Label.FontColor       = app.OK;
                case 'inactive'
                    chip.Label.BackgroundColor = [0.97 0.97 0.98];
                    chip.Label.FontColor       = [0.78 0.80 0.83];
            end
        end

        function onToggleLog(app, ~, ~)
            app.LogVisible = ~app.LogVisible;
            if app.LogVisible
                app.ToggleLogBtn.Text = 'Hide log';
                app.LogPanel.Visible  = 'on';
                app.ValidateGrid.RowHeight = {'fit','fit',26,'fit','1x'};
                if isempty(app.LogBuffer), app.ConsoleArea.Value = {''};
                else, app.ConsoleArea.Value = app.LogBuffer(:); end
                try, scroll(app.ConsoleArea, 'bottom'); catch, end
            else
                app.ToggleLogBtn.Text = 'Show log';
                app.LogPanel.Visible  = 'off';
                app.ValidateGrid.RowHeight = {'fit','fit',26,'fit','1x'};
            end
        end

        function onDownloadJson(app, ~, ~)
            saveCopy(app, app.LastRun.json, 'FULL_REPORT.json');
        end
        function onDownloadHtml(app, ~, ~)
            % Two-part HTML report: copy both files into a folder the
            % user picks. Falls back to the single-part legacy field if
            % only one file exists (older runs).
            parts = {};
            if isfield(app.LastRun,'html_part1') && isfile(char(app.LastRun.html_part1))
                parts{end+1} = char(app.LastRun.html_part1);
            end
            if isfield(app.LastRun,'html_part2') && isfile(char(app.LastRun.html_part2))
                parts{end+1} = char(app.LastRun.html_part2);
            end
            if isempty(parts) && isfield(app.LastRun,'html') ...
                    && isfile(char(app.LastRun.html))
                parts{end+1} = char(app.LastRun.html);
            end
            saveHtmlSet(app, parts);
        end

        % ===================== Reports page ========================
        function refreshReports(app)
            app.ReportRows = orch.list_reports();
            n = numel(app.ReportRows);
            data = cell(n,4);
            for i = 1:n
                r = app.ReportRows(i);
                data{i,1} = char(r.age);
                data{i,2} = char(r.ts);
                if r.has_html1 || r.has_html2
                    data{i,3} = sprintf('%.1f kB', r.size_kb);
                else
                    data{i,3} = '-';
                end
                tags = {};
                if r.has_html1, tags{end+1} = 'HTML p1'; end %#ok<AGROW>
                if r.has_html2, tags{end+1} = 'HTML p2'; end %#ok<AGROW>
                if r.has_json,  tags{end+1} = 'JSON';    end %#ok<AGROW>
                if isempty(tags), data{i,4} = '-'; else, data{i,4} = strjoin(tags,' + '); end
            end
            app.ReportsTable.Data = data;
            updateDashboard(app);
        end

        function row = selectedReport(app)
            row = [];
            sel = app.ReportsTable.Selection;
            if isempty(sel), return, end
            i = sel(1);
            if i >= 1 && i <= numel(app.ReportRows)
                row = app.ReportRows(i);
            end
        end

        function onOpenHtml(app, ~, ~)
            r = selectedReport(app);
            if isempty(r), uialert(app.UIFigure,'Select a row first.','No selection'); return, end
            opened = false;
            if r.has_html1 && isfile(char(r.html1))
                web(char(r.html1), '-browser'); opened = true;
            end
            if r.has_html2 && isfile(char(r.html2))
                web(char(r.html2), '-browser'); opened = true;
            end
            if ~opened
                uialert(app.UIFigure,'This run has no HTML.','Missing HTML');
            end
        end
        function onSaveHtml(app, ~, ~)
            r = selectedReport(app);
            if isempty(r), uialert(app.UIFigure,'Select a row first.','No selection'); return, end
            parts = {};
            if r.has_html1 && isfile(char(r.html1)), parts{end+1} = char(r.html1); end
            if r.has_html2 && isfile(char(r.html2)), parts{end+1} = char(r.html2); end
            if isempty(parts)
                uialert(app.UIFigure,'No HTML for this run.','Missing HTML'); return
            end
            saveHtmlSet(app, parts);
        end
        function onSaveJson(app, ~, ~)
            r = selectedReport(app);
            if isempty(r), uialert(app.UIFigure,'Select a row first.','No selection'); return, end
            if ~r.has_json, uialert(app.UIFigure,'No JSON for this run.','Missing JSON'); return, end
            saveCopy(app, char(r.json), sprintf('FULL_REPORT_%s.json', r.ts));
        end

        function onDeleteReport(app, ~, ~)
            r = selectedReport(app);
            if isempty(r), uialert(app.UIFigure,'Select a row first.','No selection'); return, end
            sel = uiconfirm(app.UIFigure, ...
                sprintf('Delete report "%s"? This cannot be undone.', char(r.ts)), ...
                'Confirm delete', ...
                'Options', {'Delete','Cancel'}, ...
                'DefaultOption', 'Cancel', 'CancelOption', 'Cancel', ...
                'Icon', 'warning');
            if ~strcmp(sel,'Delete'), return, end
            try
                if r.has_html1 && isfile(char(r.html1)), delete(char(r.html1)); end
                if r.has_html2 && isfile(char(r.html2)), delete(char(r.html2)); end
                if r.has_json  && isfile(char(r.json)),  delete(char(r.json));  end
                setStatus(app, sprintf('Deleted report: %s', char(r.ts)));
                refreshReports(app);
            catch ME
                uialert(app.UIFigure, ME.message, 'Delete failed');
            end
        end

        function saveCopy(app, src, suggested)
            if isempty(src) || ~isfile(src)
                uialert(app.UIFigure, sprintf('Source missing: %s', src), 'Save failed');
                return
            end
            [f,p] = uiputfile(suggested, 'Save report as');
            if isequal(f,0), return, end
            try
                copyfile(src, fullfile(p,f));
                setStatus(app, sprintf('Saved: %s', fullfile(p,f)));
            catch ME
                uialert(app.UIFigure, ME.message, 'Save failed');
            end
        end

        function saveHtmlSet(app, srcPaths)
            % Copy a set of HTML files (1 or 2 parts of the report) into
            % a folder picked by the user. Originals keep their basename
            % so the cross-references between part 1 and part 2 still
            % resolve when the user opens the saved copy.
            srcPaths = srcPaths(~cellfun('isempty', srcPaths));
            srcPaths = srcPaths(cellfun(@isfile, srcPaths));
            if isempty(srcPaths)
                uialert(app.UIFigure, 'Source HTML missing.', 'Save failed');
                return
            end
            dstDir = uigetdir('', 'Choose folder for the report');
            if isequal(dstDir, 0), return, end
            saved = 0;
            for i = 1:numel(srcPaths)
                [~, base, ext] = fileparts(srcPaths{i});
                try
                    copyfile(srcPaths{i}, fullfile(dstDir, [base ext]));
                    saved = saved + 1;
                catch ME
                    uialert(app.UIFigure, ME.message, 'Save failed');
                    return
                end
            end
            setStatus(app, sprintf('Saved %d HTML file(s) to %s', saved, dstDir));
        end

        % ===================== Model page ==========================
        function onEditMaster(app, ~, ~),    openModel(app, 'bms_master');     end
        function onEditSlave(app, ~, ~),     openModel(app, 'bms_slave');      end
        function onEditPredictor(app, ~, ~), openModel(app, 'fault_predictor'); end

        function openModel(app, name)
            try
                setStatus(app, sprintf('Opening %s ...', name));
                drawnow;
                orch.open_model(name);
                describeModels(app);
                setStatus(app, sprintf('%s opened in Simulink', name));
            catch ME
                uialert(app.UIFigure, ME.message, 'Open failed');
                setStatus(app, 'Open failed');
            end
        end

        function onReset(app, ~, ~)
            sel = uiconfirm(app.UIFigure, ...
                'Reset all editable models to the original snapshot? Unsaved Simulink changes will be lost.', ...
                'Confirm reset', ...
                'Options', {'Reset','Cancel'}, ...
                'DefaultOption', 'Cancel', 'CancelOption', 'Cancel', ...
                'Icon', 'warning');
            if ~strcmp(sel,'Reset'), return, end
            try
                info = orch.restore();
                msgs = arrayfun(@(r) sprintf('  %-20s %s', r.name, ...
                    ternary(r.restored,'restored',char(r.reason))), info, ...
                    'UniformOutput', false);
                uialert(app.UIFigure, strjoin(msgs, newline), ...
                    'Reset complete', 'Icon', 'success');
                describeModels(app);
                setStatus(app, 'Models reset to snapshot');
            catch ME
                uialert(app.UIFigure, ME.message, 'Reset failed');
            end
        end

        function onSavePilC(app, ~, ~)
            srcDir = fullfile(orch.repo_root(), 'bms_master_ert_rtw');
            if ~isfolder(srcDir)
                uialert(app.UIFigure, ...
                    sprintf(['No PIL build folder yet at\n  %s\n\n' ...
                             'Run a PIL scenario first (skip_build off) ' ...
                             'to generate the C code.'], srcDir), ...
                    'Nothing to export');
                return
            end
            defaultName = sprintf('bms_master_pil_code_%s.zip', datestr(now,'yyyymmdd_HHMMSS')); %#ok<TNOW1,DATST>
            [f, p] = uiputfile({'*.zip','ZIP archive (*.zip)'}, ...
                'Save PIL C source', defaultName);
            if isequal(f, 0), return, end
            target = fullfile(p, f);
            try
                zip(target, srcDir);
                uialert(app.UIFigure, sprintf('Saved:\n%s', target), ...
                    'PIL code exported', 'Icon', 'success');
                setStatus(app, 'PIL C source exported');
            catch ME
                uialert(app.UIFigure, ME.message, 'Export failed');
            end
        end

        % ===================== nav / misc ==========================
        function showPage(app, key)
            app.ActivePage = key;
            pp = fieldnames(app.Pages);
            for i = 1:numel(pp)
                app.Pages.(pp{i}).Visible = ternaryStr(strcmp(pp{i},key),'on','off');
            end
            % Highlight nav button
            nb = fieldnames(app.NavBtns);
            for i = 1:numel(nb)
                b = app.NavBtns.(nb{i});
                if strcmp(nb{i}, key)
                    b.BackgroundColor = [0.27 0.32 0.40];
                    b.FontColor       = [1 1 1];
                else
                    b.BackgroundColor = app.SIDE;
                    b.FontColor       = app.SIDE_FG;
                end
            end
            % Lazy refresh: when entering Plots page, scan latest PNG set.
            if strcmp(key,'plots')
                try, refreshPlots(app); catch, end
            end
        end

        function setStatus(app, s)
            app.StatusLabel.Text = ['  ' s];
            drawnow limitrate;
        end

        % ===================== layout ==============================
        function createComponents(app)
            app.UIFigure = uifigure('Visible','off', ...
                'Position',[60 50 1280 800], ...
                'Color', app.BG, ...
                'Name','BMS Engineering Assistant');

            outer = uigridlayout(app.UIFigure, [2 2]);
            outer.RowHeight   = {'1x', 24};
            outer.ColumnWidth = {220, '1x'};
            outer.Padding     = [0 0 0 0];
            outer.RowSpacing  = 0;
            outer.ColumnSpacing = 0;

            % ---- sidebar
            buildSideBar(app, outer);

            % ---- content host
            content = uipanel(outer, 'BackgroundColor', app.BG, 'BorderType','none');
            content.Layout.Row = 1; content.Layout.Column = 2;
            cg = uigridlayout(content, [1 1]);
            cg.Padding = [24 20 24 20];
            cg.BackgroundColor = app.BG;

            host = uipanel(cg, 'BackgroundColor', app.BG, 'BorderType','none');
            
            % Give 'host' a grid layout so that nested panels stretch to full scale
            hostGrid = uigridlayout(host, [1 1]);
            hostGrid.Padding = [0 0 0 0];

            % Build pages — Pass hostGrid as the parent so the Layout property is populated
            buildDashboard(app, hostGrid);
            app.DashboardPage.Layout.Row = 1;
            app.DashboardPage.Layout.Column = 1;
            
            buildValidatePage(app, hostGrid);
            app.ValidatePage.Layout.Row = 1;
            app.ValidatePage.Layout.Column = 1;
            
            buildReportsPage(app, hostGrid);
            app.ReportsPage.Layout.Row = 1;
            app.ReportsPage.Layout.Column = 1;
            
            buildPlotsPage(app, hostGrid);
            app.PlotsPage.Layout.Row = 1;
            app.PlotsPage.Layout.Column = 1;

            buildModelPage(app, hostGrid);
            app.ModelPage.Layout.Row = 1;
            app.ModelPage.Layout.Column = 1;

            app.Pages.dashboard = app.DashboardPage;
            app.Pages.validate  = app.ValidatePage;
            app.Pages.reports   = app.ReportsPage;
            app.Pages.plots     = app.PlotsPage;
            app.Pages.model     = app.ModelPage;

            % ---- status bar (footer)
            statusBar = uipanel(outer, 'BackgroundColor', [0.92 0.93 0.95], ...
                'BorderType','none');
            statusBar.Layout.Row = 2; statusBar.Layout.Column = [1 2];
            sbg = uigridlayout(statusBar, [1 2]);
            sbg.ColumnWidth = {'1x','fit'};
            sbg.Padding = [16 2 16 2];
            app.StatusLabel = uilabel(sbg, 'Text','  Ready', ...
                'FontName', app.FONT, 'FontSize', 11, 'FontColor', app.MUTED);
            ver = uilabel(sbg, 'Text', 'v1.0', ...
                'FontName', app.FONT, 'FontSize', 11, 'FontColor', app.MUTED);
            ver.HorizontalAlignment = 'right';

            % Resize callback for progress bar fill: ONLY recompute width
            % of the fill panel; do NOT call updateProgress (which would
            % re-trigger the SizeChangedFcn recursively and starve the UI
            % thread).
            app.ProgressBarBg.SizeChangedFcn = @(~,~) local_resize_fill( ...
                app.ProgressBarBg, app.ProgressBarFill, ...
                local_extract_pct(app.ProgressLabel.Text));

            app.UIFigure.Visible = 'on';
        end

        function buildSideBar(app, parent)
            app.SideBar = uipanel(parent, 'BackgroundColor', app.SIDE, ...
                'BorderType', 'none');
            app.SideBar.Layout.Row = 1; app.SideBar.Layout.Column = 1;
            sg = uigridlayout(app.SideBar, [8 1]);
            sg.RowHeight   = {54, 18, 38, 38, 38, 38, 38, '1x', 28};
            sg.ColumnWidth = {'1x'};
            sg.Padding     = [14 18 14 18];
            sg.RowSpacing  = 6;
            sg.BackgroundColor = app.SIDE;

            app.BrandLabel = uilabel(sg, 'Text','BMS Assistant', ...
                'FontName', app.FONT, 'FontSize', 15, 'FontWeight','bold', ...
                'FontColor', [1 1 1]);
            app.BrandSub = uilabel(sg, 'Text','Engineering toolkit', ...
                'FontName', app.FONT, 'FontSize', 10, 'FontColor', app.SIDE_MUT);

            % Nav buttons (icon + label, left aligned)
            keys   = {'dashboard','validate','reports','plots','model'};
            icons  = char([9632 9658 9776 9707 9881]);   % ■ ▶ ☰ ☋ ⚙ (☋ as plot glyph)
            names  = {'Dashboard','Validate','Reports','Plots','Model'};
            for i = 1:numel(keys)
                k = keys{i};
                txt = ['  ' icons(i) '   ' names{i}];
                b = uibutton(sg, 'Text', txt, ...
                    'FontName', app.FONT, 'FontSize', 12, ...
                    'BackgroundColor', app.SIDE, 'FontColor', app.SIDE_FG, ...
                    'HorizontalAlignment', 'left', ...
                    'ButtonPushedFcn', @(s,e) showPage(app, k));
                app.NavBtns.(k) = b;
            end

            % filler row 7 — just leave empty
            uilabel(sg,'Text','','BackgroundColor', app.SIDE);
            % footer
            uilabel(sg,'Text','MATLAB R2024b', ...
                'FontName', app.FONT, 'FontSize', 9, 'FontColor', app.SIDE_MUT);
        end

        % --------- pages
        function buildDashboard(app, host)
            app.DashboardPage = uipanel(host, 'BackgroundColor', app.BG, ...
                'BorderType','none', 'Visible','off');
            g = uigridlayout(app.DashboardPage, [4 3]);
            g.RowHeight   = {44, 110, 110, '1x'};
            g.ColumnWidth = {'1x','1x','1x'};
            g.Padding     = [0 0 0 0];
            g.RowSpacing  = 14;
            g.ColumnSpacing = 14;
            g.BackgroundColor = app.BG;

            % Page title
            title = uilabel(g, 'Text', 'Dashboard', ...
                'FontName', app.FONT, 'FontSize', 20, 'FontWeight','bold', ...
                'FontColor', app.INK);
            title.Layout.Row = 1; title.Layout.Column = [1 3];

            % KPI cards
            [c1, c1g] = makeCard(app, g, 'Status');
            c1.Layout.Row = 2; c1.Layout.Column = 1;
            app.DashStatusValue = uilabel(c1g, 'Text','Ready', ...
                'FontName', app.FONT, 'FontSize', 22, 'FontWeight','bold', ...
                'FontColor', app.OK);

            [c2, c2g] = makeCard(app, g, 'Last run');
            c2.Layout.Row = 2; c2.Layout.Column = 2;
            app.DashLastRunLbl = uilabel(c2g, 'Text','No run yet in this session', ...
                'FontName', app.FONT, 'FontSize', 13, 'FontColor', app.INK);

            [c3, c3g] = makeCard(app, g, 'Reports');
            c3.Layout.Row = 2; c3.Layout.Column = 3;
            app.DashReportsLbl = uilabel(c3g, 'Text','0 reports available', ...
                'FontName', app.FONT, 'FontSize', 13, 'FontColor', app.INK);

            % Quick actions card
            [qa, qg] = makeCard(app, g, 'Quick actions');
            qa.Layout.Row = 3; qa.Layout.Column = [1 3];
            qg2 = uigridlayout(qg, [1 4]);
            qg2.ColumnWidth = {180, 180, 180, '1x'};
            qg2.RowHeight   = {32};
            qg2.Padding     = [0 0 0 0];
            qg2.ColumnSpacing = 10;
            qg2.BackgroundColor = app.CARD;
            app.DashRunBtn = makeAccentButton(qg2, [], 'Run pipeline (MIL)', @(s,e)quickRun(app));
            makeGhostButton(app, qg2, 'View reports',  @(s,e) showPage(app,'reports'));
            makeGhostButton(app, qg2, 'Open Validate', @(s,e) showPage(app,'validate'));
            uilabel(qg2,'Text',''); % spacer

            % Tip card with Image
            [tp, tg] = makeCard(app, g, 'Notes');
            tp.Layout.Row = 4; tp.Layout.Column = [1 3];
            
            % Split the notes card into two columns: Text and Image
            notesGrid = uigridlayout(tg, [1 2]);
            % Increased to 800 to make the image significantly larger
            notesGrid.ColumnWidth = {'1x', 500}; 
            notesGrid.Padding = [0 0 0 0];
            notesGrid.BackgroundColor = app.CARD;

            uilabel(notesGrid, ...
                'Text', sprintf([ ...
                'Coverage runs automatically with MIL and is scoped to the selected MIL filter and the relevant model(s).\n' ...
                'Reports include only the validation paths you actually ran (MIL / SIL / PIL).\n' ...
                'The console output during a run is hidden by default. Click "Show log" on the Validate page to expand it.']), ...
                'FontName', app.FONT, 'FontSize', 12, 'FontColor', app.MUTED, ...
                'WordWrap','on', 'VerticalAlignment','top');

            % Determine the directory where this app file is located
            [appPath, ~, ~] = fileparts(mfilename('fullpath'));
            imagePath = fullfile(appPath, 'figures', 'bmw_i3.png');

            % Blend image against white background at 15% opacity (uiimage requires RGB)
            [imgData, ~, alpha] = imread(imagePath);
            if ~isempty(alpha)
                alphaNorm = double(alpha) / 255 * 0.75;
                imgData = uint8(alphaNorm .* double(imgData) + (1 - alphaNorm) .* 255);
            else
                imgData = uint8(0.75 * double(imgData) + 0.85 * 255);
            end

            % The Car Image
            img = uiimage(notesGrid, 'ImageSource', imgData);
            img.HorizontalAlignment = 'right';
            img.VerticalAlignment = 'bottom';
        end

        function quickRun(app)
            app.MilCheck.Value = true;
            app.SilCheck.Value = false;
            app.PilCheck.Value = false;
            app.MilSelectedFilters = {''};
            refreshMilLabel(app);
            showPage(app,'validate');
            onRun(app);
        end

        function buildValidatePage(app, host)
            app.ValidatePage = uipanel(host, 'BackgroundColor', app.BG, ...
                'BorderType','none', 'Visible','off');
            app.ValidateGrid = uigridlayout(app.ValidatePage, [5 1]);
            app.ValidateGrid.RowHeight   = {'fit','fit',26,'fit','1x'}; % Replaced 0 with '1x' so components align to top
            app.ValidateGrid.ColumnWidth = {'1x'};
            app.ValidateGrid.Padding     = [0 0 0 0];
            app.ValidateGrid.RowSpacing  = 14;
            app.ValidateGrid.BackgroundColor = app.BG;

            % --- Page title row
            title = uilabel(app.ValidateGrid, 'Text','Validate', ...
                'FontName', app.FONT, 'FontSize', 20, 'FontWeight','bold', ...
                'FontColor', app.INK);
            title.Layout.Row = 1;

            % --- Scenario card
            [card1, c1g] = makeCard(app, app.ValidateGrid, 'Scenario');
            card1.Layout.Row = 2;
            cg = uigridlayout(c1g, [4 4]);
            cg.RowHeight   = {32,32,32,32};
            cg.ColumnWidth = {110, '1x', 190, 150};
            cg.Padding     = [0 4 0 4];
            cg.RowSpacing  = 8;
            cg.ColumnSpacing = 12;
            cg.BackgroundColor = app.CARD;
            app.MilCheck = uicheckbox(cg,'Text','MIL','Value',true, ...
                'FontName', app.FONT, 'FontSize', 12);
            app.MilCheck.Layout.Row = 1; app.MilCheck.Layout.Column = 1;
            % Compact summary of the current MIL selection + a button
            % that opens a checklist dialog. Keeps this row one line tall
            % so the log panel below has room to breathe.
            app.MilSelectedLbl = uilabel(cg, 'Text', 'All BMS + predictor', ...
                'FontName', app.FONT, 'FontSize', 12, 'FontColor', app.INK);
            app.MilSelectedLbl.Layout.Row = 1; app.MilSelectedLbl.Layout.Column = [2 3];
            app.MilChooseBtn = makeGhostButton(app, cg, 'Choose...', @app.onChooseMil);
            app.MilChooseBtn.Layout.Row = 1; app.MilChooseBtn.Layout.Column = 4;

            app.SilCheck = uicheckbox(cg,'Text','SIL','Value',false, ...
                'FontName', app.FONT, 'FontSize', 12);
            app.SilCheck.Layout.Row = 2; app.SilCheck.Layout.Column = 1;
            app.SilDD    = uidropdown(cg,'Items',{'-'}, 'FontName', app.FONT, 'FontSize', 12);
            app.SilDD.Layout.Row = 2; app.SilDD.Layout.Column = [2 4];

            app.PilCheck = uicheckbox(cg,'Text','PIL','Value',false, ...
                'FontName', app.FONT, 'FontSize', 12);
            app.PilCheck.Layout.Row = 3; app.PilCheck.Layout.Column = 1;
            app.PilDD    = uidropdown(cg,'Items',{'-'}, 'FontName', app.FONT, 'FontSize', 12);
            app.PilDD.Layout.Row = 3; app.PilDD.Layout.Column = [2 4];

            note = uilabel(cg, ...
                'Text', 'Coverage runs automatically with MIL.', ...
                'FontName', app.FONT, 'FontSize', 11, 'FontColor', app.MUTED);
            note.Layout.Row = 4; note.Layout.Column = [1 2];
            app.SkipBuildCheck = uicheckbox(cg, 'Text','Skip codegen rebuild', ...
                'Value',true, 'FontName', app.FONT, 'FontSize', 11);
            app.SkipBuildCheck.Layout.Row = 4; app.SkipBuildCheck.Layout.Column = 3;
            app.RunBtn = makeAccentButton(cg, [], 'Run pipeline', @app.onRun);
            app.RunBtn.Layout.Row = 4; app.RunBtn.Layout.Column = 4;

            % --- Phase chip strip
            chipsHost = uipanel(app.ValidateGrid, 'BackgroundColor', app.BG, ...
                'BorderType','none');
            chipsHost.Layout.Row = 3;
            chg = uigridlayout(chipsHost, [1 7]);
            chg.RowHeight   = {26};
            chg.ColumnWidth = {'fit','fit','fit','fit','fit','fit','1x'};
            chg.Padding     = [0 0 0 0];
            chg.ColumnSpacing = 8;
            chg.BackgroundColor = app.BG;
            app.PhaseChips = struct();
            phaseKeys   = {'mil','sil','pil','cov','facts','analyzer','doc'};
            phaseLabels = {'MIL','SIL','PIL','COV','Facts','Analyzer','Doc'};
            for i = 1:numel(phaseKeys)-1
                makePhaseChip(app, chg, phaseKeys{i}, phaseLabels{i}, i);
            end
            % Last (doc) takes its own col, then spacer
            makePhaseChip(app, chg, phaseKeys{end}, phaseLabels{end}, numel(phaseKeys));

            % --- Progress card
            [card2, c2g] = makeCard(app, app.ValidateGrid, 'Progress');
            card2.Layout.Row = 4;
            pg = uigridlayout(c2g, [3 4]);
            pg.RowHeight   = {26, 22, 36};
            pg.ColumnWidth = {'1x', 110, 200, 200};
            pg.Padding     = [0 4 0 4];
            pg.RowSpacing  = 8;
            pg.ColumnSpacing = 10;
            pg.BackgroundColor = app.CARD;

            app.ProgressBarBg = uipanel(pg, ...
                'BackgroundColor', [0.92 0.94 0.96], ...
                'BorderType','line', 'HighlightColor', app.BORDER, ...
                'AutoResizeChildren','off');
            app.ProgressBarBg.Layout.Row = 1; app.ProgressBarBg.Layout.Column = [1 4];
            app.ProgressBarFill = uipanel(app.ProgressBarBg, ...
                'BackgroundColor', app.ACCENT, 'BorderType','none', ...
                'Units','pixels', 'Position', [0 0 2 22]);

            app.ProgressLabel = uilabel(pg, 'Text','idle   0%', ...
                'FontName', app.FONT, 'FontSize', 11, 'FontColor', app.MUTED);
            app.ProgressLabel.Layout.Row = 2; app.ProgressLabel.Layout.Column = [1 4];

            app.ToggleLogBtn = makeGhostButton(app, pg, 'Show log', @app.onToggleLog);
            app.ToggleLogBtn.Layout.Row = 3; app.ToggleLogBtn.Layout.Column = 2;

            app.DownloadJsonBtn = makeGhostButton(app, pg, 'Save JSON', @app.onDownloadJson);
            app.DownloadJsonBtn.Layout.Row = 3; app.DownloadJsonBtn.Layout.Column = 3;
            app.DownloadJsonBtn.Enable = 'off';
            app.DownloadHtmlBtn = makeAccentButton(pg, [], 'Save HTML', @app.onDownloadHtml);
            app.DownloadHtmlBtn.Layout.Row = 3; app.DownloadHtmlBtn.Layout.Column = 4;
            app.DownloadHtmlBtn.Enable = 'off';

            % --- Log panel (collapsible)
            app.LogPanel = uipanel(app.ValidateGrid, 'BackgroundColor', app.CARD, ...
                'BorderType','line', 'HighlightColor', app.BORDER, ...
                'Visible','off');
            app.LogPanel.Layout.Row = 5;
            lg = uigridlayout(app.LogPanel, [1 1]);
            lg.Padding = [10 10 10 10];
            lg.BackgroundColor = app.CARD;
            app.ConsoleArea = uitextarea(lg, 'Editable','off', ...
                'FontName', app.MONO, 'FontSize', 11, ...
                'BackgroundColor', [0.98 0.98 0.99], 'FontColor', app.INK);
        end

        function makePhaseChip(app, parent, key, label, col)
            lb = uilabel(parent, 'Text', ['  ' label '  '], ...
                'FontName', app.FONT, 'FontSize', 11, ...
                'FontColor', app.MUTED, ...
                'BackgroundColor', [0.94 0.95 0.96], ...
                'HorizontalAlignment','center', ...
                'VerticalAlignment','center');
            lb.Layout.Row = 1; lb.Layout.Column = col;
            app.PhaseChips.(key) = struct('Label', lb);
            setPhaseChip(app, key, 'inactive');
        end

        function buildReportsPage(app, host)
            app.ReportsPage = uipanel(host, 'BackgroundColor', app.BG, ...
                'BorderType','none', 'Visible','off');
            g = uigridlayout(app.ReportsPage, [3 1]);
            g.RowHeight   = {44, '1x', 44};
            g.ColumnWidth = {'1x'};
            g.Padding     = [0 0 0 0];
            g.RowSpacing  = 14;
            g.BackgroundColor = app.BG;

            title = uilabel(g, 'Text','Reports', ...
                'FontName', app.FONT, 'FontSize', 20, 'FontWeight','bold', ...
                'FontColor', app.INK);
            title.Layout.Row = 1;

            [card, cg] = makeCard(app, g, 'Past runs');
            card.Layout.Row = 2;
            tg = uigridlayout(cg, [1 1]);
            tg.Padding = [0 4 0 4];
            tg.BackgroundColor = app.CARD;
            app.ReportsTable = uitable(tg, ...
                'ColumnName',{'Generated','Run ID','HTML size','Artefacts'}, ...
                'SelectionType','row','Multiselect','off', ...
                'FontName', app.FONT, 'FontSize', 11, ...
                'RowStriping','on');

            % Action row
            ah = uipanel(g, 'BackgroundColor', app.BG, 'BorderType','none');
            ah.Layout.Row = 3;
            ag = uigridlayout(ah, [1 6]);
            ag.RowHeight   = {32};
            ag.ColumnWidth = {'1x', 130, 170, 150, 150, 130};
            ag.Padding     = [0 0 0 0];
            ag.ColumnSpacing = 10;
            ag.BackgroundColor = app.BG;
            uilabel(ag,'Text',''); % spacer
            app.RefreshBtn = makeGhostButton(app, ag, 'Refresh', @(s,e) refreshReports(app));
            app.OpenHtmlBtn = makeAccentButton(ag, [], 'Open HTML', @app.onOpenHtml);
            app.SaveHtmlBtn = makeGhostButton(app, ag, 'Save HTML', @app.onSaveHtml);
            app.SaveJsonBtn = makeGhostButton(app, ag, 'Save JSON', @app.onSaveJson);
            app.DeleteReportBtn = uibutton(ag, 'Text','Delete', ...
                'FontName', app.FONT, 'FontSize', 12, ...
                'BackgroundColor', app.ERR, 'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @app.onDeleteReport);
        end

        function buildPlotsPage(app, host)
            % Per-test signal previews. Each MIL/SIL/PIL test renders one
            % verdict figure via val.scenario_plot / val.equivalence_plot
            % into validator/reports/plots/<suite>/. This page browses them.
            app.PlotsPage = uipanel(host, 'BackgroundColor', app.BG, ...
                'BorderType','none', 'Visible','off');
            
            g = uigridlayout(app.PlotsPage, [3 1]);
            g.RowHeight   = {44, 56, '1x'};
            g.ColumnWidth = {'1x'};
            g.Padding     = [0 0 0 0];
            g.RowSpacing  = 14;
            g.BackgroundColor = app.BG;

            title = uilabel(g, 'Text','Validation plots', ...
                'FontName', app.FONT, 'FontSize', 20, 'FontWeight','bold', ...
                'FontColor', app.INK);
            title.Layout.Row = 1;

            % --- toolbar: suite picker + refresh
            tb = uipanel(g, 'BackgroundColor', app.BG, 'BorderType','none');
            tb.Layout.Row = 2;
            tg = uigridlayout(tb, [1 4]);
            tg.RowHeight   = {32};
            tg.ColumnWidth = {90, 220, '1x', 130};
            tg.Padding     = [0 0 0 0];
            tg.ColumnSpacing = 10;
            tg.BackgroundColor = app.BG;
            
            uilabel(tg, 'Text','Suite:', 'FontName', app.FONT, 'FontSize', 12, ...
                'FontColor', app.INK, 'HorizontalAlignment','right');
            
            app.PlotsSuiteDD = uidropdown(tg, 'Items', {'mil','sil','pil'}, ...
                'Value', 'mil', 'FontName', app.FONT, 'FontSize', 12, ...
                'ValueChangedFcn', @(s,e) refreshPlots(app));
            
            uilabel(tg,'Text','');  % spacer
            app.PlotsRefreshBtn = makeGhostButton(app, tg, 'Refresh', ...
                @(s,e) refreshPlots(app));

            % --- body: list left, image right
            body = uipanel(g, 'BackgroundColor', app.BG, 'BorderType','none');
            body.Layout.Row = 3;
            
            bg = uigridlayout(body, [1 2]);
            bg.RowHeight   = {'1x'};
            % Reduced list width from 320 to 240 to maximize plot area
            bg.ColumnWidth = {240, '1x'}; 
            bg.Padding     = [0 0 0 0];
            bg.ColumnSpacing = 14;
            bg.BackgroundColor = app.BG;

            [listCard, lcg] = makeCard(app, bg, 'Tests');
            listCard.Layout.Row = 1; 
            listCard.Layout.Column = 1;
            
            app.PlotsList = uilistbox(lcg, 'Items', {}, ...
                'FontName', app.FONT, 'FontSize', 11, ...
                'ValueChangedFcn', @(s,e) showSelectedPlot(app));

            [imgCard, icg] = makeCard(app, bg, 'Signals');
            imgCard.Layout.Row = 1; 
            imgCard.Layout.Column = 2;
            
            % Inner grid for the image to ensure it fills the card
            ig = uigridlayout(icg, [1 1]);
            ig.RowHeight   = {'1x'};
            ig.ColumnWidth = {'1x'};
            ig.Padding     = [10 10 10 10]; % Slight padding so it doesn't touch edges
            ig.BackgroundColor = app.CARD;
            
            app.PlotsImage = uiimage(ig, 'ScaleMethod','fit', ...
                'BackgroundColor', app.CARD);
            app.PlotsImage.Layout.Row = 1;
            app.PlotsImage.Layout.Column = 1;

            app.PlotsEmptyLbl = uilabel(ig, 'Text','(no plot selected)', ...
                'FontName', app.FONT, 'FontSize', 12, 'FontColor', app.MUTED, ...
                'HorizontalAlignment','center', 'VerticalAlignment','center', ...
                'Visible','on');
            app.PlotsEmptyLbl.Layout.Row = 1;
            app.PlotsEmptyLbl.Layout.Column = 1;
        end

        function refreshPlots(app)
            % Enumerate PNGs under validator/reports/plots/<suite>/**
            % and (optionally) flatten one level (e.g. mil has bms/, predictor/).
            suite = app.PlotsSuiteDD.Value;
            base  = fullfile(orch.repo_root(), 'validator', 'reports', ...
                'plots', suite);
            items = {};
            paths = {};
            if isfolder(base)
                files = dir(fullfile(base, '**', '*.png'));
                for i = 1:numel(files)
                    p = fullfile(files(i).folder, files(i).name);
                    rel = strrep(p, [base filesep], '');
                    items{end+1} = rel; %#ok<AGROW>
                    paths{end+1} = p;   %#ok<AGROW>
                end
            end
            app.PlotsList.Items = items;
            app.PlotsList.ItemsData = paths;
            if isempty(items)
                app.PlotsImage.ImageSource = '';
                app.PlotsImage.Visible = 'off';
                app.PlotsEmptyLbl.Text = sprintf('(no plots in validator/reports/plots/%s)', suite);
                app.PlotsEmptyLbl.Visible = 'on';
            else
                app.PlotsList.Value = paths{1};
                showSelectedPlot(app);
            end
        end

        function showSelectedPlot(app)
            p = app.PlotsList.Value;
            if isempty(p) || ~ischar(p) && ~isstring(p)
                app.PlotsImage.Visible = 'off';
                app.PlotsEmptyLbl.Visible = 'on';
                return
            end
            if isfile(p)
                app.PlotsImage.ImageSource = char(p);
                app.PlotsImage.Visible = 'on';
                app.PlotsEmptyLbl.Visible = 'off';
            else
                app.PlotsImage.Visible = 'off';
                app.PlotsEmptyLbl.Text = '(file missing)';
                app.PlotsEmptyLbl.Visible = 'on';
            end
        end

        function buildModelPage(app, host)
            app.ModelPage = uipanel(host, 'BackgroundColor', app.BG, ...
                'BorderType','none', 'Visible','off');
            g = uigridlayout(app.ModelPage, [4 1]);
            g.RowHeight   = {44, 'fit', 'fit', '1x'};
            g.ColumnWidth = {'1x'};
            g.Padding     = [0 0 0 0];
            g.RowSpacing  = 14;
            g.BackgroundColor = app.BG;

            title = uilabel(g, 'Text','Model editing', ...
                'FontName', app.FONT, 'FontSize', 20, 'FontWeight','bold', ...
                'FontColor', app.INK);
            title.Layout.Row = 1;

            [card1, c1g] = makeCard(app, g, 'Open in Simulink');
            card1.Layout.Row = 2;
            mg = uigridlayout(c1g, [2 5]);
            mg.RowHeight   = {32, 32};
            mg.ColumnWidth = {180, 180, 180, '1x', 180};
            mg.Padding     = [0 4 0 4];
            mg.RowSpacing  = 10;
            mg.ColumnSpacing = 10;
            mg.BackgroundColor = app.CARD;
            app.EditMasterBtn    = makeGhostButton(app, mg, 'BMS Master',     @app.onEditMaster);
            app.EditSlaveBtn     = makeGhostButton(app, mg, 'BMS Slave',      @app.onEditSlave);
            app.EditPredictorBtn = makeGhostButton(app, mg, 'Fault Predictor',@app.onEditPredictor);

            note = uilabel(mg, ...
                'Text','On first open, model/.snapshots/<name>.slx.bak is created. Reset copies it back over the live .slx.', ...
                'FontName', app.FONT, 'FontSize', 11, 'FontColor', app.MUTED, ...
                'WordWrap','on');
            note.Layout.Row = 2; note.Layout.Column = [1 4];
            app.ResetBtn = uibutton(mg, 'Text','Reset to snapshot ...', ...
                'FontName', app.FONT, 'FontSize', 12, ...
                'BackgroundColor', app.ERR, 'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @app.onReset);
            app.ResetBtn.Layout.Row = 2; app.ResetBtn.Layout.Column = 5;

            [card2, c2g] = makeCard(app, g, 'PIL artefacts');
            card2.Layout.Row = 3;
            pg = uigridlayout(c2g, [2 2]);
            pg.RowHeight   = {32, 'fit'};
            pg.ColumnWidth = {220, '1x'};
            pg.Padding     = [0 4 0 4];
            pg.RowSpacing  = 8;
            pg.ColumnSpacing = 12;
            pg.BackgroundColor = app.CARD;
            app.SavePilCBtn = uibutton(pg, 'Text','Save PIL C code (zip) ...', ...
                'FontName', app.FONT, 'FontSize', 12, ...
                'BackgroundColor', app.ACCENT, 'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @app.onSavePilC);
            app.SavePilCBtn.Layout.Row = 1; app.SavePilCBtn.Layout.Column = 1;
            pilNote = uilabel(pg, ...
                'Text','Bundles the latest bms_master_ert_rtw/ folder (Embedded Coder C output flashed to the STM32) into a single .zip you choose. Only the most recent build is exported -- no version history.', ...
                'FontName', app.FONT, 'FontSize', 11, 'FontColor', app.MUTED, ...
                'WordWrap','on');
            pilNote.Layout.Row = 1; pilNote.Layout.Column = 2;

            [card3, c3g] = makeCard(app, g, 'Snapshot status');
            card3.Layout.Row = 4;
            ig = uigridlayout(c3g, [1 1]);
            ig.Padding = [0 4 0 4];
            ig.BackgroundColor = app.CARD;
            app.ModelInfo = uitextarea(ig, 'Editable','off', ...
                'FontName', app.MONO, 'FontSize', 11, ...
                'BackgroundColor', [0.98 0.98 0.99]);
        end
    end
end

% =================== free helpers ==================================
function v = ternary(cond, a, b)
if cond, v = a; else, v = b; end
end
function v = ternaryStr(cond, a, b)
if cond, v = a; else, v = b; end
end
function f = local_extract_pct(label)
m = regexp(label, '(\d+)%', 'tokens', 'once');
if isempty(m), f = 0; else, f = str2double(m{1})/100; end
end

function local_resize_fill(bg, fill, frac)
% Recompute the progress-bar fill width on resize. Pure layout op --
% does NOT touch progress label or status, so it cannot recurse.
try
    inner = bg.InnerPosition;
catch
    inner = bg.Position;
end
W = max(inner(3), 2); H = max(inner(4), 2);
fillW = max(2, round(W * max(0, min(1, frac))));
fill.Position = [0 0 fillW H];
end

function [card, bodyGrid] = makeCard(app, parent, titleStr)
% A clean white card with a thin border and a small title strip.
% Returns the card panel + a 1x1 uigridlayout body where children go.
card = uipanel(parent, 'BackgroundColor', app.CARD, ...
    'BorderType','line', 'HighlightColor', app.BORDER);
g = uigridlayout(card, [2 1]);
g.RowHeight   = {18, '1x'};
g.ColumnWidth = {'1x'};
g.Padding     = [16 12 16 14];
g.RowSpacing  = 6;
g.BackgroundColor = app.CARD;
uilabel(g, 'Text', upper(titleStr), ...
    'FontName', app.FONT, 'FontSize', 10, 'FontWeight', 'bold', ...
    'FontColor', app.MUTED);
bodyHost = uipanel(g, 'BackgroundColor', app.CARD, 'BorderType','none');
bodyGrid = uigridlayout(bodyHost, [1 1]);
bodyGrid.Padding = [0 0 0 0];
bodyGrid.BackgroundColor = app.CARD;
end

function b = makeAccentButton(parent, layout, txt, cb)
b = uibutton(parent, 'Text', txt, ...
    'FontName', 'Segoe UI', 'FontSize', 12, 'FontWeight','bold', ...
    'BackgroundColor', [0.00 0.45 0.74], 'FontColor', [1 1 1], ...
    'ButtonPushedFcn', cb);
if ~isempty(layout)
    b.Layout = layout;
end
end

function b = makeGhostButton(app, parent, txt, cb)
b = uibutton(parent, 'Text', txt, ...
    'FontName', app.FONT, 'FontSize', 12, ...
    'BackgroundColor', app.BTN_BG, 'FontColor', app.INK, ...
    'ButtonPushedFcn', cb);
end

function pos = centerOn(parentFig, w, h)
try
    pp = parentFig.Position;
    cx = pp(1) + pp(3)/2;
    cy = pp(2) + pp(4)/2;
    pos = [round(cx - w/2), round(cy - h/2), w, h];
catch
    pos = [200 200 w h];
end
end