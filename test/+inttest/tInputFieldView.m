classdef tInputFieldView < matlab.unittest.TestCase
    % Tests for statusMgr.view.InputField: an inline, non-modal status line
    % with an embedded edit field that doubles as a user-input collector.

    properties
        Stack statusMgr.Stack
        Figure matlab.ui.Figure
        View statusMgr.view.InputField
    end

    methods (TestMethodSetup)
        function setup(testCase)
            testCase.Stack = statusMgr.Stack();
            testCase.Figure = uifigure("Visible", "off");
            testCase.addTeardown(@() delete(testCase.Figure));
            testCase.View = statusMgr.view.InputField(testCase.Figure, testCase.Stack);
            testCase.addTeardown(@() delete(testCase.View));
        end
    end

    methods (Test)

        % --- defaults / construction ---------------------------------------

        function tDefaults(testCase)
            testCase.verifyTrue(testCase.View.ShowIdle)            % clears the line
            testCase.verifyTrue(testCase.View.HandleInputRequests)
            testCase.verifyTrue(testCase.View.isVisible())
            testCase.verifyEqual(string(testCase.View.Field.Editable), "off")
        end

        function tDefaultConstructorCreatesUifigureParent(testCase)
            view = statusMgr.view.InputField();
            parent = view.Parent;
            testCase.addTeardown(@() delete(parent))
            testCase.addTeardown(@() delete(view))

            testCase.assertClass(parent, "matlab.ui.Figure")
            testCase.assertClass(view.Stack, "statusMgr.Stack")
        end

        % --- message display ------------------------------------------------

        function tShowsMessageReadOnly(testCase)
            testCase.Stack.addStatus("Info", Message="hello");

            testCase.verifyEqual(string(testCase.View.Field.Value), "hello")
            testCase.verifyEqual(string(testCase.View.Field.Editable), "off")
            testCase.verifyEqual(string(testCase.View.OkButton.Visible), "off")
        end

        function tLatestMessageWins(testCase)
            testCase.Stack.addStatus("Info", Message="first");
            testCase.Stack.addStatus("Warning", Message="second");
            testCase.verifyEqual(string(testCase.View.Field.Value), "second")
        end

        function tIdleClearsField(testCase)
            testCase.Stack.addStatus("Info", Message="hi");
            testCase.Stack.addStatus(statusMgr.StatusType.Idle);
            testCase.verifyEqual(string(testCase.View.Field.Value), "")
        end

        % --- input requests -------------------------------------------------

        function tInputRequestShowsEditableFieldThenReturnsValue(testCase)
            % requestInput blocks until a value is supplied; a timer drives
            % the field while it blocks. The view claims the request
            % synchronously inside requestInput, so PendingStatus is set by
            % the time the timer first fires.
            typedValue = "hello world";
            view = testCase.View;

            t = timer("ExecutionMode", "fixedSpacing", "Period", 0.05, ...
                "TimerFcn", @(~,~) fillAndSubmit());
            testCase.addTeardown(@() statusMgr.util.stopTimer(t));
            start(t);

            value = testCase.Stack.requestInput("Enter something", ...
                DefaultValue="def", Title="Test Input", Timeout=5);

            testCase.verifyEqual(value, typedValue)
            % Back to read-only display, nothing pending.
            testCase.verifyEqual(string(view.Field.Editable), "off")
            testCase.verifyEmpty(view.PendingStatus)
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Type, ...
                statusMgr.StatusType.Idle)

            function fillAndSubmit()
                if isempty(view.PendingStatus) || ~isvalid(view.PendingStatus)
                    return
                end
                % Simulate the user typing and pressing OK.
                view.Field.Value = typedValue;
                cb = view.OkButton.ButtonPushedFcn;
                cb(view.OkButton, []);
                stop(t);
            end
        end

        function tInputRequestPrefillsDefaultValue(testCase)
            % While the request is pending the field is editable and
            % pre-filled with the request's default value.
            view = testCase.View;
            observed = struct("editable", "", "value", "", "promptVisible", "");

            t = timer("ExecutionMode", "fixedSpacing", "Period", 0.05, ...
                "TimerFcn", @(~,~) capture());
            testCase.addTeardown(@() statusMgr.util.stopTimer(t));
            start(t);

            testCase.Stack.requestInput("Name?", DefaultValue="Anon", Timeout=5);

            testCase.verifyEqual(observed.editable, "on")
            testCase.verifyEqual(observed.value, "Anon")
            testCase.verifyEqual(observed.promptVisible, "on")

            function capture()
                if isempty(view.PendingStatus) || ~isvalid(view.PendingStatus)
                    return
                end
                observed.editable = string(view.Field.Editable);
                observed.value = string(view.Field.Value);
                observed.promptVisible = string(view.PromptLabel.Visible);
                % Resolve so requestInput can return.
                cb = view.OkButton.ButtonPushedFcn;
                cb(view.OkButton, []);
                stop(t);
            end
        end

        function tInputRequestDisabledReturnsDefault(testCase)
            % With HandleInputRequests off the view does not claim, so the
            % request times out to its default value.
            testCase.View.HandleInputRequests = false;

            value = testCase.Stack.requestInput("Prompt", ...
                DefaultValue="default", Timeout=0.1);

            testCase.verifyEqual(value, "default")
            testCase.verifyEmpty(testCase.View.PendingStatus)
        end

        function tInputCollectedRegardlessOfMinLevel(testCase)
            % Input requests are control flow, not verbosity: even a
            % maximally terse view still collects input.
            typedValue = "still collected";
            testCase.View.MinLevel = "Critical";
            view = testCase.View;

            t = timer("ExecutionMode", "fixedSpacing", "Period", 0.05, ...
                "TimerFcn", @(~,~) fillAndSubmit());
            testCase.addTeardown(@() statusMgr.util.stopTimer(t));
            start(t);

            value = testCase.Stack.requestInput("Enter something", ...
                DefaultValue="def", Timeout=5);

            testCase.verifyEqual(value, typedValue)

            function fillAndSubmit()
                if isempty(view.PendingStatus) || ~isvalid(view.PendingStatus)
                    return
                end
                view.Field.Value = typedValue;
                cb = view.OkButton.ButtonPushedFcn;
                cb(view.OkButton, []);
                stop(t);
            end
        end

    end

end
