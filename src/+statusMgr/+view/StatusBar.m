classdef StatusBar < statusMgr.internal.view.StatusViewBase
    %STATUSBAR Inline non-modal status view rendered in a figure container.
    %
    % Renders the current status as a thin bar with:
    %   * A message label (colour-coded by status type) showing
    %     status.MessageShort. Clicking the label opens a Popout with
    %     the full status.Message for Error / Warning / Success types.
    %   * A linear progress indicator (visible only for Running statuses)
    %   * A Cancel button (visible only for RunningCancellable statuses)
    %   * An OK button (visible only for Error / Warning / Success
    %     statuses) that completes the status — i.e. dismisses the
    %     alert by removing it from the stack.
    %   * A "Close All" button (only when more than one alert is on the
    %     stack) that removes every Error / Warning / Success in one
    %     click. Running / Idle / RequestingInput are left alone.
    %     When count > 1, the bar also appends "(N alerts)" to the
    %     message and the popout shows every alert's full Message
    %     stacked as one HTML document.
    %
    % Unlike Popup, no modal dialogs appear — every update happens
    % inline so user code can keep interacting with the rest of the UI.
    %
    % The bar's top-level child of `parent` is a uigridlayout, which
    % auto-resizes when its parent does (uipanel does not, which is a
    % long-standing MATLAB limitation). For a "bar at the bottom of a
    % figure" layout, give StatusBar a parent that's already sized to
    % the bar's footprint — typically a row in your own outer
    % uigridlayout:
    %
    %   fig = uifigure;
    %   outer = uigridlayout(fig, [2, 1], "RowHeight", {"1x", 28});
    %   mainContent = uipanel(outer);   % goes in row 1
    %   stack = statusMgr.Stack();
    %   bar = statusMgr.view.StatusBar(outer, stack);  % goes in row 2
    %
    % Pass any uifigure / uipanel / uigridlayout cell as the parent.
    %
    % Implementation note: the linear progress indicator and the
    % popout container are matlab.ui.control.internal.ProgressIndicator
    % and matlab.ui.container.internal.Popout — both are internal
    % Mathworks APIs. They work in current MATLAB releases but may
    % move or change without notice.

    properties (SetAccess = protected)
        Parent
        Layout matlab.ui.container.GridLayout {mustBeScalarOrEmpty} = matlab.ui.container.GridLayout.empty(1,0)
        MessageLabel matlab.ui.control.Label {mustBeScalarOrEmpty} = matlab.ui.control.Label.empty(1,0)
        ProgressIndicator matlab.ui.control.internal.ProgressIndicator {mustBeScalarOrEmpty} = matlab.ui.control.internal.ProgressIndicator.empty(1,0)
        CancelButton matlab.ui.control.Button {mustBeScalarOrEmpty} = matlab.ui.control.Button.empty(1,0)
        DetailsButton matlab.ui.control.Button {mustBeScalarOrEmpty} = matlab.ui.control.Button.empty(1,0)
        OkButton matlab.ui.control.Button {mustBeScalarOrEmpty} = matlab.ui.control.Button.empty(1,0)
        CloseAllButton matlab.ui.control.Button {mustBeScalarOrEmpty} = matlab.ui.control.Button.empty(1,0)
        Popout matlab.ui.container.internal.Popout {mustBeScalarOrEmpty} = matlab.ui.container.internal.Popout.empty(1,0)
        PopoutText matlab.ui.control.HTML {mustBeScalarOrEmpty} = matlab.ui.control.HTML.empty(1,0)
    end

    properties
        InfoColor (1,3) double = [0 0 0]
        WarningColor (1,3) double = [0.85 0.5 0]
        ErrorColor (1,3) double = [0.78 0 0]
        SuccessColor (1,3) double = [0 0.55 0]
        % Width and height of the details Popout, in pixels.
        PopoutSize (1,2) double {mustBePositive} = [400 200]
    end

    methods

        function obj = StatusBar(parent, stack, nvp)
            arguments
                parent = uifigure
                stack (1,1) statusMgr.internal.StackInterface = statusMgr.Stack
                nvp.InfoColor (1,3) double = [0 0 0]
                nvp.WarningColor (1,3) double = [0.85 0.5 0]
                nvp.ErrorColor (1,3) double = [0.78 0 0]
                nvp.SuccessColor (1,3) double = [0 0.55 0]
                nvp.PopoutSize (1,2) double {mustBePositive} = [400 200]
                nvp.ShowInfo (1,1) logical = true
                nvp.ShowWarnings (1,1) logical = true
                nvp.ShowErrors (1,1) logical = true
                nvp.ShowRunning (1,1) logical = true
                nvp.ShowSuccess (1,1) logical = true
                nvp.ShowIdle (1,1) logical = true   % default true: clears the bar
                % HandleInputRequests=true means the bar will display
                % the prompt; the override only updates the label, it
                % does not transition the status, so a claim-capable
                % view (Popup, CommandWindow) can still claim.
                nvp.HandleInputRequests (1,1) logical = true
                nvp.IncludeIdentifiers (1,:) string = string.empty(1,0)
                nvp.ExcludeIdentifiers (1,:) string = string.empty(1,0)
            end

            obj.Parent = parent;
            set(obj, nvp);
            obj.buildUI();
            obj.setStack(stack);
            obj.standardDisplay();
        end

        function tf = isVisible(obj)
            tf = ~isempty(obj.Layout) && isvalid(obj.Layout);
        end

        function delete(obj)
            delete(obj.Popout);
            delete(obj.Layout);
        end

    end

    methods (Static, Access = protected)

        function s = escapeHtml(text)
            % Minimal HTML escape for status text interpolated into the
            % popout's HTMLSource. & must be replaced first to avoid
            % double-escaping the entities introduced by the other
            % replacements.
            s = string(text);
            s = replace(s, "&", "&amp;");
            s = replace(s, "<", "&lt;");
            s = replace(s, ">", "&gt;");
        end

    end

    methods (Access = protected)

        function buildUI(obj)
            % uigridlayout auto-resizes with its parent — that's why
            % we use it as the top-level child rather than a uipanel.
            % Columns: message (flex), progress, cancel, details, ok, close-all.
            obj.Layout = uigridlayout(obj.Parent, [1, 6], ...
                "ColumnWidth", {"1x", 0, 0, 0, 0, 0}, ...
                "Padding", [6, 2, 6, 2], ...
                "ColumnSpacing", 6, ...
                "RowHeight", {"1x"});

            obj.MessageLabel = uilabel(obj.Layout, "Text", "");
            obj.MessageLabel.Layout.Column = 1;

            obj.ProgressIndicator = matlab.ui.control.internal.ProgressIndicator( ...
                "Parent", obj.Layout, ...
                "Visible", "off");
            obj.ProgressIndicator.Layout.Column = 2;

            obj.CancelButton = uibutton(obj.Layout, ...
                "Text", "Cancel", ...
                "Visible", "off", ...
                "ButtonPushedFcn", @(~,~) obj.onCancelClicked());
            obj.CancelButton.Layout.Column = 3;

            % Details button: small, opens the Popout that shows the
            % full status.Message. Visible only when the current
            % status has details worth showing (Error / Warning /
            % Success). The Popout's own Trigger="click" mechanism
            % handles the click — we don't add a ButtonPushedFcn,
            % because layering our own toggle on top fights the
            % Popout's built-in click-outside-to-close behaviour
            % (clicking the trigger button is treated as "outside",
            % which would close-then-reopen).
            obj.DetailsButton = uibutton(obj.Layout, ...
                "ButtonPushedFcn", @(~,~) obj.onDetailsButtonPressed(), ...
                "Text", "...", ...
                "Visible", "off");
            obj.DetailsButton.Layout.Column = 4;

            obj.OkButton = uibutton(obj.Layout, ...
                "Text", "OK", ...
                "Visible", "off", ...
                "ButtonPushedFcn", @(~,~) obj.onOkClicked());
            obj.OkButton.Layout.Column = 5;

            % Close All: visible only when more than one alert is on
            % the stack. Removes every Error / Warning / Success in
            % one click; leaves Running / Idle / RequestingInput
            % alone (matches the spirit of Popup's "Close All" but
            % more surgical).
            obj.CloseAllButton = uibutton(obj.Layout, ...
                "Text", "Close All", ...
                "Visible", "off", ...
                "ButtonPushedFcn", @(~,~) obj.onCloseAllClicked());
            obj.CloseAllButton.Layout.Column = 6;

            % Popout for showing the full status.Message. Anchored to
            % the Details button with Trigger="click" — clicking the
            % button opens the popout, clicking outside closes it.
            % An explicit Position is required: without it the
            % popout's preferred size depends on its content at
            % construction time (empty here) and ends up too small
            % for typical error reports.
            obj.Popout = matlab.ui.container.internal.Popout( ...
                "Target", obj.DetailsButton, ...
                "Placement", "auto", ...
                "Position", [0, 0, obj.PopoutSize(1), obj.PopoutSize(2)]);

            % RowHeight and ColumnWidth of "1x" make the inner uilabel
            % fill the popout's interior. Without explicit sizing the
            % grid defaults to "fit", which collapses to zero height
            % when the label's WordWrap content is initially empty —
            % so the text never appears even after Text is set later.
            popoutGrid = uigridlayout(obj.Popout, [1, 1], ...
                "Padding", 0, ...
                "RowHeight", {"1x"}, ...
                "ColumnWidth", {"1x"});
            obj.PopoutText = uihtml(popoutGrid, ...
                "HTMLSource", "");
        end

        function onCancelClicked(obj)
            % The most recent visible status is what the bar is showing;
            % completing it signals cancel to runCancellable's user code.
            s = obj.IncomingStatus;
            if isscalar(s) && isvalid(s) && ~s.IsComplete
                s.complete();
            end
        end

        function onOkClicked(obj)
            % Acknowledge an error/warning/success — completes the
            % status and removes it from the stack.
            s = obj.IncomingStatus;
            if isscalar(s) && isvalid(s) && ~s.IsComplete
                s.complete();
            end
        end

        function onCloseAllClicked(obj)
            % Dismiss every alert (Error/Warning/Success) on the
            % stack in one click. Running and other lifecycle
            % statuses are intentionally left alone — Close All is a
            % "clear the noise" gesture, not a kill switch.
            alerts = obj.alertStatuses();
            if ~isempty(alerts)
                obj.Stack.removeStatus(alerts);
            end
        end

        function alerts = alertStatuses(obj)
            % Statuses on the stack that the bar treats as alerts:
            % Error, Warning, Success. Used to decide whether
            % "Close All" should be shown and to populate the
            % multi-alert popout.
            if isempty(obj.Stack) || ~isvalid(obj.Stack)
                alerts = statusMgr.Status.empty(1,0);
                return
            end
            statuses = obj.Stack.Statuses;
            types = [statuses.Type];
            alerts = statuses(ismember(types, obj.AlertStatusTypes));
        end

        function html = buildAlertsHtml(obj, alerts)
            % HTML body rendered inside the popout. For one alert,
            % just the message; for several, a list with each
            % alert's Type and MessageShort as a header and Message
            % as a <pre>-formatted body so newlines / stack traces
            % survive intact. Message / MessageShort come from
            % arbitrary user code, so they're HTML-escaped before
            % being interpolated into the markup.
            if isempty(alerts)
                html = "";
                return
            end
            if isscalar(alerts)
                html = "<pre>" + obj.escapeHtml(alerts.Message) + "</pre>";
                return
            end
            parts = strings(0,1);
            for i = 1:numel(alerts)
                a = alerts(i);
                parts(end+1,1) = "<h4>" + obj.escapeHtml(string(a.Type)) + ...
                    ": " + obj.escapeHtml(a.MessageShort) + "</h4>"; %#ok<AGROW>
                parts(end+1,1) = "<pre>" + obj.escapeHtml(a.Message) + "</pre>"; %#ok<AGROW>
                if i < numel(alerts)
                    parts(end+1,1) = "<hr>"; %#ok<AGROW>
                end
            end
            html = strjoin(parts, newline);
        end

        function onDetailsButtonPressed(obj)
            if obj.Popout.IsOpen
                obj.Popout.close();
            else
                obj.Popout.open();
            end
        end

        function present(obj, message, color, progressVisible, progressValue, cancelVisible, okVisible, closeAllVisible, popoutText)
            % The listener on the Stack can fire after the bar's UI
            % has been torn down (e.g. parent figure closed, or a
            % stale instance). Guard against half-constructed /
            % half-destroyed state up front so a single dangling
            % listener doesn't error out the addStatus call.
            if ~obj.uiHandlesValid()
                return
            end
            obj.MessageLabel.Text = message;
            obj.MessageLabel.FontColor = color;
            obj.setProgress(progressVisible, progressValue);
            obj.setCancelVisible(cancelVisible);
            obj.setDetails(popoutText);
            obj.setOkVisible(okVisible);
            obj.setCloseAllVisible(closeAllVisible);
        end

        function tf = uiHandlesValid(obj)
            tf = ~isempty(obj.MessageLabel) && isvalid(obj.MessageLabel) ...
                && ~isempty(obj.ProgressIndicator) && isvalid(obj.ProgressIndicator) ...
                && ~isempty(obj.CancelButton) && isvalid(obj.CancelButton) ...
                && ~isempty(obj.DetailsButton) && isvalid(obj.DetailsButton) ...
                && ~isempty(obj.OkButton) && isvalid(obj.OkButton) ...
                && ~isempty(obj.CloseAllButton) && isvalid(obj.CloseAllButton) ...
                && ~isempty(obj.Popout) && isvalid(obj.Popout) ...
                && ~isempty(obj.PopoutText) && isvalid(obj.PopoutText);
        end

        function setProgress(obj, visible, value)
            obj.setControlVisible(obj.ProgressIndicator, 2, visible, 100);
            if ~visible
                return
            end
            if isnan(value)
                obj.ProgressIndicator.Indeterminate = "on";
            else
                obj.ProgressIndicator.Indeterminate = "off";
                obj.ProgressIndicator.Value = value;
            end
        end

        function setCancelVisible(obj, visible)
            obj.setControlVisible(obj.CancelButton, 3, visible, 70);
        end

        function setOkVisible(obj, visible)
            obj.setControlVisible(obj.OkButton, 5, visible, 50);
        end

        function setCloseAllVisible(obj, visible)
            obj.setControlVisible(obj.CloseAllButton, 6, visible, 80);
        end

        function setDetails(obj, text)
            % Show the Details button (and populate the popout) when
            % there's full text to show. Hiding the button removes
            % the only way to open the popout from the UI; if the
            % popout was open we close it explicitly so it doesn't
            % linger after the alert is gone.
            obj.PopoutText.HTMLSource = text;
            if text == ""
                obj.setControlVisible(obj.DetailsButton, 4, false, 30);
                if obj.Popout.IsOpen
                    obj.Popout.close();
                end
            else
                obj.setControlVisible(obj.DetailsButton, 4, true, 30);
            end
        end

        function setControlVisible(obj, control, column, visible, width)
            if visible
                control.Visible = "on";
                obj.Layout.ColumnWidth{column} = width;
            else
                control.Visible = "off";
                obj.Layout.ColumnWidth{column} = 0;
            end
        end

        function displayInfo(obj, status)
            obj.present(status.Message, obj.InfoColor, false, NaN, false, false, false, "");
        end

        function displayRunning(obj, status, cancellable)
            obj.present(status.Message, obj.InfoColor, true, status.Value, cancellable, false, false, "");
        end

        function displayError(obj, status)
            obj.presentAlert(status, obj.ErrorColor);
        end

        function displayWarning(obj, status)
            obj.presentAlert(status, obj.WarningColor);
        end

        function displaySuccess(obj, status)
            obj.presentAlert(status, obj.SuccessColor);
        end

        function displayIdle(obj, ~)
            obj.present("", obj.InfoColor, false, NaN, false, false, false, "");
        end

        function handleInputRequest(obj, status)
            % Don't claim — just show the prompt. A claim-capable view
            % attached to the same stack (Popup, CommandWindow) will
            % do the actual input collection.
            obj.present(status.Message, obj.InfoColor, false, NaN, false, false, false, "");
        end

        function presentAlert(obj, status, color)
            % Shared rendering for Error / Warning / Success. Counts
            % concurrent alerts on the stack so that:
            %   * the message label gets a "(N alerts)" suffix
            %   * the popout shows every alert's full body, not just
            %     this one's
            %   * the Close All button is offered when there's more
            %     than one alert to dismiss.
            alerts = obj.alertStatuses();
            n = numel(alerts);
            label = status.MessageShort;
            if n > 1
                label = label + " (" + n + " alerts)";
            end
            popoutHtml = obj.buildAlertsHtml(alerts);
            obj.present(label, color, false, NaN, false, true, n > 1, popoutHtml);
        end

    end

end
