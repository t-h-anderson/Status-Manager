classdef Popup < statusMgr.internal.view.StatusViewBase
    %StatusVIEW View a status Stack

    properties
        Parent % Graphics object
    end

    properties (SetAccess = protected)
        CancelListener event.listener
        CancelTimer timer % Due to known bug - see below
    end

    properties (SetAccess = protected)
        ProgressDlg matlab.ui.dialog.ProgressDialog
        ProgressDlgStatus (1,:) statusMgr.Status

        HasPopup (1,1) logical = false

        % Input dialog widgets are held on the view so tests (and any
        % programmatic driver) can interact with them directly.
        % findall(0, "Name", ...) is unreliable for modal uifigures
        % across MATLAB versions, so prefer these handles for automation.
        InputDialog matlab.ui.Figure {mustBeScalarOrEmpty}
        InputField matlab.ui.control.EditField {mustBeScalarOrEmpty}
        InputOkButton matlab.ui.control.Button {mustBeScalarOrEmpty}
    end

    properties (Dependent)
        Figure
    end

    properties (Access = private)
        TestCase = statusMgr.internal.view.TestCase()
        SkipComplete (1,1) logical = false
    end

    methods

        function obj = Popup(parent, stack, nvp)
            arguments
                parent = uifigure
                stack (1,1) statusMgr.internal.StackInterface = statusMgr.Stack
                nvp.ShowInfo (1,1) logical = true
                nvp.ShowWarnings (1,1) logical = true
                nvp.ShowErrors (1,1) logical = true
                nvp.ShowRunning (1,1) logical = true
                nvp.ShowSuccess (1,1) logical = true
                nvp.ShowIdle (1,1) logical = false
                nvp.HandleInputRequests (1,1) logical = true
                nvp.IncludeIdentifiers (1,:) string = string.empty(1,0)
                nvp.ExcludeIdentifiers (1,:) string = string.empty(1,0)
            end

            % Set view parent and stack properties
            obj.Parent = parent;
            set(obj, nvp);

            % Add listener to stack
            obj.setStack(stack);

            obj.standardDisplay();
        end

        function tf = isVisible(obj)
            tf = ~isempty(obj.Figure) && isvalid(obj.Figure) && obj.Figure.Visible == "on";
        end

        function value = get.Figure(obj)
            % Get the handle for the parent's figure
            value = ancestor(obj.Parent, "figure");
        end

        function delete(obj)
            obj.deleteProgressDlg();
        end

    end

    methods (Access = protected)
        % These methods can be overloaded to tailor the view behaviour
        function cleanupCompletedStatus(obj)
            if ~isempty(obj.ProgressDlgStatus) && ...
                    (~isvalid(obj.ProgressDlgStatus) || obj.ProgressDlgStatus.IsComplete)
                obj.deleteProgressDlg();
            end
            if obj.HasPopup && ~isempty(obj.IncomingStatus) && ...
                    (~isvalid(obj.IncomingStatus) || obj.IncomingStatus.IsComplete)
                obj.clearPreviousAlert(obj.Figure);
            end
        end

        function beforeDisplay(obj)
            obj.clearPreviousAlert(obj.Figure);
            obj.checkProgressDlg();
        end

        function displayRunning(obj, status, cancellable)
            % displayRunning: displays a uiwaitbar in the main window
            arguments
                obj
                status statusMgr.Status
                cancellable (1,1) logical = false
            end % arguments

            % Check figure exists and is visible
            if obj.isVisible()
                obj.createProgressDlg();
                obj.updateProgressDlg(status, cancellable);
            end % figure exists

        end % displayProgress

        function displayError(obj, status)
            obj.popupAlert(status, "Error", "error");
        end

        function displayWarning(obj, status)
            obj.popupAlert(status, "Warning", "warning");
        end

        function displaySuccess(obj, status)
            obj.popupAlert(status, "Success", "success");
        end

        function displayInfo(obj, status)
            obj.popupAlert(status, "Info", "info");
        end

        function displayIdle(~, ~)
            % Do nothing
        end

        function handleInputRequest(obj, status)
            % standardDisplay already guards on isVisible() before
            % dispatching, so we don't repeat the check here.
            status.transitionInputState(statusMgr.StatusType.AwaitingInput);

            titleStr = status.Title;
            if titleStr == "", titleStr = "Input Required"; end
            defaultVal = string(status.Data);

            d = uifigure("Name", titleStr, "Position", [0 0 340 160], ...
                "Resize", "off", "WindowStyle", "modal");
            movegui(d, "center");

            uilabel(d, "Text", status.Message, ...
                "Position", [15 110 310 35], "WordWrap", "on");
            field = uieditfield(d, "text", ...
                "Position", [15 65 310 30], "Value", defaultVal);
            okBtn = uibutton(d, "push", "Text", "OK", ...
                "Position", [130 15 80 35], ...
                "ButtonPushedFcn", @(~,~) onSubmit(field.Value));
            d.CloseRequestFcn = @(~,~) onSubmit(defaultVal);

            % Expose the widgets so tests / programmatic drivers can
            % interact without relying on findall(0, ...), which does
            % not consistently surface modal uifigures.
            obj.InputDialog = d;
            obj.InputField = field;
            obj.InputOkButton = okBtn;

            function onSubmit(value)
                delete(d);
                status.transitionInputState( ...
                    statusMgr.StatusType.ValueSupplied, value);
            end
        end

    end

    methods (Access = protected)

        function popupAlert(obj, status, title, icon)
            % popupAlert displays a popup in the main window

            arguments
                obj
                status statusMgr.Status
                title (1,1) string = "Error"
                icon (1,1) string = "error"
            end % arguments

            if isvalid(obj.Figure)

                numPopups = obj.numberDialogues(obj.Stack);

                if numPopups > 1
                    title = title + " (" + numPopups + " alerts)";
                end

                removeStatusFn = @(src, event) obj.completeIfClicked(src, event, status);

                % Only offer "Close All" when there's actually more
                % than one alert to dismiss. clearPreviousAlert
                % dismisses-and-recreates the dialog when a new
                % popup-worthy status fires, so the offered options
                % stay in sync with numPopups on every refresh.
                if numPopups > 1
                    options = ["Close All", "OK"];
                else
                    options = "OK";
                end

                uiconfirm(obj.Figure, ...
                    status.MessageShort, ...
                    title, ...
                    "Options", options, ...
                    "DefaultOption", "OK", ...
                    "CancelOption", "OK", ...
                    "Icon", icon, ...
                    "CloseFcn", removeStatusFn);

                obj.HasPopup = true;

            end

        end % popupAlert

        function clearPreviousAlert(obj, f)
            % Should only ever have one uialert
            if obj.HasPopup

                obj.SkipComplete = true;
                c = onCleanup(@() setSkipCompleteToFalse(obj));
                % See g1622345.
                tt = obj.TestCase;
                obj.HasPopup = false; % Avoid triggering the complete if clicked
                try
                    tt.dismissDialog("uiconfirm", f)
                catch err
                    % HasPopup may be true while no dialog is actually
                    % present — e.g. the user dismissed the dialog via
                    % Esc / the window X without uiconfirm's CloseFcn
                    % firing in some MATLAB versions. Swallow the
                    % "no dialogs found" case; rethrow anything else.
                    if ~strcmp(err.identifier, "MATLAB:uiautomation:Driver:NoConfirmationDialogsFound")
                        rethrow(err);
                    end
                end
                drawnow
            end

            function setSkipCompleteToFalse(obj)
                 obj.SkipComplete = false;
            end
        end

    end

    methods (Access = protected)
        function completeIfClicked(obj, ~, event, status)
            % CloseFcn fires for every dismissal route uiconfirm
            % surfaces (button click, Esc, window X), so always
            % drop the flag here rather than gating on HasPopup.
            obj.HasPopup = false;
            if ~obj.SkipComplete
                switch event.SelectedOption
                    case "OK"
                        status.complete();
                    case "Close All"
                        obj.Stack.removeAllStatuses();
                end
            end
        end
    end

    % progress dlg
    methods (Access = protected)
        function deleteProgressDlg(obj)
            delete(obj.ProgressDlg);
            delete(obj.CancelListener);
            statusMgr.util.stopTimer(obj.CancelTimer);
        end

        function createProgressDlg(obj)

            if ~obj.hasValidProgressDlg()
                % No progress dlg, so create
                defaultProps = struct("Title", "Running");
                defaultProps = namedargs2cell(defaultProps);
                obj.ProgressDlg = uiprogressdlg(obj.Figure, 'Indeterminate','on', defaultProps{:});
                
                % TODO: Add timer so progress dlg only made/shown after a
                % delay to avoid flashing the screen

                % This doesn't work - Known bug https://komodo.mathworks.com/main/gecko/view?Record=2984852
                % obj.CancelListener = addlistener(obj.ProgressDlg, "CancelRequested", "PostSet", @(src, event) obj.notifyStackOfCancel());

                % Wrap obj in a WeakReference so the closure does not hold a strong
                % reference to it. Without this, obj → timer → closure → obj prevents
                % MATLAB from garbage-collecting the view when the caller clears it.
                s = warning();
                warning("off");
                statusMgr.util.stopTimer(obj.CancelTimer);
                weakObj = matlab.lang.WeakReference(obj);
                obj.CancelTimer = timer("TimerFcn", @(~,~)checkCancelTimerFcn(weakObj), ...
                    "Period", 1, "TasksToExecute", inf, "ExecutionMode", "fixedSpacing");
                obj.CancelTimer.start();
                warning(s)

            end

        end

        function updateProgressDlg(obj, status, cancellable)
            obj.ProgressDlgStatus = status;

            if ~ismissing(status.Title) && status.Title ~= ""
                obj.ProgressDlg.Title = status.Title;
            else
                obj.ProgressDlg.Title = "Running";
            end

            if ~strcmp(string([obj.ProgressDlg.Message]), status.Message)
                obj.ProgressDlg.Message = status.Message;
            end

            if obj.ProgressDlg.Cancelable ~= cancellable
                obj.ProgressDlg.Cancelable = cancellable;
            end

            if ~ismissing(status.Value)
                obj.ProgressDlg.Value = status.Value;

                if ~strcmp(obj.ProgressDlg.Indeterminate, 'off')
                    obj.ProgressDlg.Indeterminate = 'off';
                end

            else
                if ~strcmp(obj.ProgressDlg.Indeterminate, 'on')
                    obj.ProgressDlg.Indeterminate = 'on';
                end
            end
        end

        function tf = hasValidProgressDlg(obj)
            tf = ~isempty(obj.ProgressDlg) && isvalid(obj.ProgressDlg);
        end

        function tf = isProgressDlgNeeded(~, status)
            tf = (status.Type == statusMgr.StatusType.Running || ...
                status.Type == statusMgr.StatusType.RunningCancellable);
        end

        function checkProgressDlg(obj)
            status = obj.Stack.CurrentStatus;
            if ~obj.isProgressDlgNeeded(status)
                obj.deleteProgressDlg();
            end
        end

        function checkIfCancelPressed(obj)
            if obj.hasValidProgressDlg() && obj.ProgressDlg.CancelRequested
                statusMgr.util.stopTimer(obj.CancelTimer);
                status = obj.ProgressDlgStatus;
                status.complete();
                obj.Stack.removeStatus(status);
            end
        end
    end % methods

    methods (Access = protected)

        function num = numberDialogues(obj, stack)
            statusTypes = [stack.Statuses.Type];
            idx = ismember(statusTypes, obj.AlertStatusTypes);
            num = sum(idx);
        end

    end

end % classdef

function checkCancelTimerFcn(weakRef)
% File-local function used as the CancelTimer callback.
% Resolves the WeakReference each time it fires: if obj has been collected
% the Value is empty and the callback is a no-op, otherwise delegates to the
% method that has full access to current object state.
    obj = weakRef.Handle;
    if ~isempty(obj)
        obj.checkIfCancelPressed();
    end
end
