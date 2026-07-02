classdef InputField < statusMgr.internal.view.StatusSinkViewBase
    %INPUTFIELD Inline, non-modal status line with an embedded edit field.
    %
    % Renders the current status as a single-line message inside a
    % uieditfield, embedded in a parent container (uifigure / uipanel /
    % uigridlayout). Unlike Popup, nothing modal appears: the field
    % updates in place while the rest of the UI stays interactive.
    %
    % The edit field is read-only while it is just displaying a message.
    % When a RequestingInput status arrives (e.g. from Stack.requestInput)
    % and HandleInputRequests is true, the view claims the request: a
    % prompt label appears, the field becomes editable (pre-filled with the
    % request's default value), and an OK button is shown. Pressing OK — or
    % Enter in the field — supplies the value back to the waiting caller,
    % after which the field returns to read-only message display.
    %
    % Typical use as the input view for an app, alongside another view
    % (e.g. CommandWindow or FileLog) for richer history:
    %
    %   fig   = uifigure;
    %   stack = statusMgr.Stack();
    %   input = statusMgr.view.InputField(fig, stack);
    %   name  = stack.requestInput("What is your name?", DefaultValue="Anon");
    %
    % Give it a parent already sized to a single row — typically a row in
    % your own outer uigridlayout — since the field fills its container.

    properties (SetAccess = protected)
        Parent
        Layout matlab.ui.container.GridLayout {mustBeScalarOrEmpty} = ...
            matlab.ui.container.GridLayout.empty(1,0)
        PromptLabel matlab.ui.control.Label {mustBeScalarOrEmpty} = ...
            matlab.ui.control.Label.empty(1,0)
        Field matlab.ui.control.EditField {mustBeScalarOrEmpty} = ...
            matlab.ui.control.EditField.empty(1,0)
        OkButton matlab.ui.control.Button {mustBeScalarOrEmpty} = ...
            matlab.ui.control.Button.empty(1,0)
        % The RequestingInput status currently being collected, if any.
        % Empty whenever the view is just displaying messages.
        PendingStatus (1,:) statusMgr.Status {mustBeScalarOrEmpty} = ...
            statusMgr.Status.empty(1,0)
    end

    methods

        function obj = InputField(parent, stack, nvp)
            arguments
                parent = uifigure
                stack (1,1) statusMgr.internal.StackInterface = statusMgr.Stack
                nvp.ShowInfo (1,1) logical = true
                nvp.ShowWarnings (1,1) logical = true
                nvp.ShowErrors (1,1) logical = true
                nvp.ShowRunning (1,1) logical = true
                nvp.ShowSuccess (1,1) logical = true
                nvp.ShowIdle (1,1) logical = true   % default true: clears the field
                nvp.HandleInputRequests (1,1) logical = true
                nvp.MinLevel (1,1) statusMgr.Level = statusMgr.Level.Trace
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
            % Tear down the owned layout (and its children) if it is still
            % alive. The parent itself is not ours to delete.
            if ~isempty(obj.Layout) && isvalid(obj.Layout)
                delete(obj.Layout);
            end
        end

    end

    methods (Access = protected)

        function buildUI(obj)
            % A two-row grid: prompt label across the top (only visible
            % while collecting input), field + OK button on the bottom row.
            obj.Layout = uigridlayout(obj.Parent, [2, 2], ...
                "ColumnWidth", {"1x", "fit"}, ...
                "RowHeight", {"fit", "fit"}, ...
                "Padding", [4 4 4 4], "RowSpacing", 4);

            obj.PromptLabel = uilabel(obj.Layout, "Text", "", ...
                "WordWrap", "on", "Visible", "off");
            obj.PromptLabel.Layout.Row = 1;
            obj.PromptLabel.Layout.Column = [1 2];

            obj.Field = uieditfield(obj.Layout, "text", ...
                "Editable", "off", ...
                "ValueChangedFcn", @(~,~) obj.submitInput());
            obj.Field.Layout.Row = 2;
            obj.Field.Layout.Column = 1;

            obj.OkButton = uibutton(obj.Layout, "push", "Text", "OK", ...
                "Visible", "off", ...
                "ButtonPushedFcn", @(~,~) obj.submitInput());
            obj.OkButton.Layout.Row = 2;
            obj.OkButton.Layout.Column = 2;
        end

        function displayStatus(obj, status, ~)
            % Display a status's message in the read-only field and make
            % sure no stale input widgets are showing.
            arguments
                obj (1,1) statusMgr.view.InputField
                status (1,1) statusMgr.Status
                ~
            end
            obj.PromptLabel.Visible = "off";
            obj.OkButton.Visible = "off";
            obj.Field.Editable = "off";
            obj.Field.Value = status.Message;
        end

        function displayIdle(obj, ~)
            % Idle clears the line back to an empty, read-only field.
            obj.clearDisplay();
        end

        function clearDisplay(obj)
            % Nothing displayable (or Idle): blank, read-only field.
            obj.PromptLabel.Visible = "off";
            obj.OkButton.Visible = "off";
            obj.Field.Editable = "off";
            obj.Field.Value = "";
        end

        function handleInputRequest(obj, status)
            % Claim the request and switch the field into edit mode,
            % pre-filled with the supplied default value.
            status.transitionInputState(statusMgr.StatusType.AwaitingInput);

            prompt = status.Message;
            if prompt == "", prompt = "Enter value"; end

            obj.PendingStatus = status;
            obj.PromptLabel.Text = prompt;
            obj.PromptLabel.Visible = "on";

            valueChangedFcn = obj.Field.ValueChangedFcn;
            obj.Field.ValueChangedFcn = [];
            restoreValueChangedFcn = onCleanup(@() set(obj.Field, ...
                "ValueChangedFcn", valueChangedFcn));
            obj.Field.Value = string(status.Data);

            obj.Field.Editable = "on";
            obj.OkButton.Visible = "on";
        end

        function submitInput(obj)
            % Supply the field's current value to the pending request.
            % Guarded so it is a no-op when nothing is pending (e.g. a
            % ValueChanged firing on the read-only field) and so a second
            % trigger — OK press followed by the field's focus-loss
            % ValueChanged — cannot double-resolve the same request.
            status = obj.PendingStatus;
            if isempty(status) || ~isvalid(status) || status.IsComplete
                return
            end

            value = string(obj.Field.Value);
            obj.PendingStatus = statusMgr.Status.empty(1,0);

            % Revert to read-only display immediately; the status being
            % removed by requestInput will publish the next status (often
            % Idle), which refreshes the field again.
            obj.Field.Editable = "off";
            obj.OkButton.Visible = "off";
            obj.PromptLabel.Visible = "off";

            status.transitionInputState(statusMgr.StatusType.ValueSupplied, value);
        end

    end

end
