classdef tCommandWindow < matlab.uitest.TestCase

    properties
        Stack statusMgr.Stack
        CommandWindowView statusMgr.view.CommandWindow
    end

    methods (TestMethodSetup)
        function setup(testCase)
            testCase.Stack = statusMgr.Stack();
            testCase.CommandWindowView = statusMgr.view.CommandWindow(testCase.Stack);
            testCase.addTeardown(@() delete(testCase.CommandWindowView))
        end
    end

    methods (Test)

        function tDefaultValues(testCase)
            testCase.verifyTrue(testCase.CommandWindowView.ShowInfo)
            testCase.verifyTrue(testCase.CommandWindowView.ShowWarnings)
            testCase.verifyTrue(testCase.CommandWindowView.ShowErrors)
            testCase.verifyTrue(testCase.CommandWindowView.ShowSuccess)
            testCase.verifyTrue(testCase.CommandWindowView.ShowRunning)
            testCase.verifyFalse(testCase.CommandWindowView.ShowIdle)
        end

        function tDisplaySuccess(testCase)
            testCase.Stack.addStatus("Success", Message="s1");
            testCase.verifyEqual(testCase.CommandWindowView.PreviousMessage, "s1");
        end

        function tDisplayInfo(testCase)
            testCase.Stack.addStatus("Info", Message="i1");
            testCase.verifyTrue(testCase.CommandWindowView.ShowInfo)
            testCase.verifyEqual(testCase.CommandWindowView.PreviousMessage, "i1");

            testCase.CommandWindowView.ShowInfo = false;
            testCase.Stack.addStatus("Info", Message="i2");
            testCase.verifyFalse(testCase.CommandWindowView.ShowInfo)
            testCase.verifyEqual(testCase.CommandWindowView.IncomingStatus.Message, "i1");
            % "i2" was suppressed by ShowInfo=false, so PreviousMessage
            % keeps tracking the last *displayed* message ("i1"). This
            % is what the dot-collapse logic in writeToTerminal needs.
            testCase.verifyEqual(testCase.CommandWindowView.PreviousMessage, "i1")
        end

        function tDisplayRunning(testCase)
            status = testCase.Stack.addStatus("Running", Message="r1");
            pause(0.5)

            testCase.verifyEqual(testCase.CommandWindowView.RunningTimer.Running, 'on')
            testCase.verifyEqual(testCase.CommandWindowView.PreviousMessage, "r1");

            testCase.Stack.CurrentStatus.complete()
            pause(0.5)

            testCase.verifyTrue(status.IsComplete)
            testCase.verifyFalse(isvalid(testCase.CommandWindowView.RunningTimer))
        end
        
        function tDisplayWarning(testCase)
            output = evalc('testCase.verifyWarningFree(@() testCase.Stack.addStatus("Warning", Message="w1", Identifier="a:b"));');
            testCase.verifyEqual(string(output), "Warning: w1" + newline);
        end

        function tDisplayError(testCase)
            cause = MException("a:b:c", "test error a:b:c");
            output = evalc('testCase.Stack.addError(cause);');
            testCase.verifySubstring(output, "test error a:b:c");
            testCase.verifyEqual(testCase.CommandWindowView.PreviousMessage, string(cause.getReport()));
        end

        function tDisplayIdle(testCase)
            % Idle status is not displayed by default.
            testCase.Stack.addStatus("Idle", Message="idle 1");
            testCase.verifyTrue(ismissing(testCase.CommandWindowView.PreviousMessage))

            newview = statusMgr.view.CommandWindow(testCase.Stack, ShowIdle=true);
            testCase.addTeardown(@() delete(newview))
            testCase.Stack.addStatus("Idle", Message="idle 2");
            testCase.verifyEqual(newview.PreviousMessage, "idle 2");
        end

        function tNonVisibleStatus(testCase)
            % A status with IsVisible=false is not printed to the terminal.
            testCase.Stack.addStatus("Warning", Message="hidden", IsVisible=false);
            testCase.verifyTrue(ismissing(testCase.CommandWindowView.PreviousMessage))
        end

        function tSuppressedIdentifier(testCase)
            % Statuses whose identifier is suppressed on the stack are not
            % printed to the terminal.
            testCase.Stack.suppressIdentifier("my:id");
            testCase.Stack.addStatus("Warning", Identifier="my:id", Message="suppressed");
            testCase.verifyTrue(ismissing(testCase.CommandWindowView.PreviousMessage))
        end

        function tUpdateMessageAndValue(testCase)
            status = testCase.Stack.addStatus("Running", Message="r1", Value=1);

            testCase.verifyEqual(testCase.Stack.CurrentStatus.Message, "r1")
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Value, 1)

            testCase.Stack.updateStatus(status, Message="r2", Value=2);

            testCase.verifyEqual(testCase.Stack.CurrentStatus.Message, "r2")
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Value, 2)
        end

        % --- handleInputRequest ---------------------------------------------

        function tDeleteCleansUpStackListener(testCase)
            % Destroying a view must dispose of its StackListener so it no
            % longer responds to events on its (still-alive) Stack. Prior
            % to the fix, the cleanup was a nested function inside
            % standardDisplay and never ran.
            view = statusMgr.view.CommandWindow(testCase.Stack);
            listener = view.StackListener;
            testCase.assertTrue(isvalid(listener))

            delete(view);

            testCase.verifyFalse(isvalid(listener))
        end

        function tHandleInputRequestDefaultValues(testCase)
            % HandleInputRequests is true by default.
            testCase.verifyTrue(testCase.CommandWindowView.HandleInputRequests)
        end

        function tHandleInputRequestDisabled(testCase)
            % When HandleInputRequests is false the view does not claim the
            % request; requestInput returns the default after the timeout.
            testCase.CommandWindowView.HandleInputRequests = false;

            value = testCase.Stack.requestInput("Prompt", ...
                DefaultValue="default", Timeout=0.1);

            testCase.verifyEqual(value, "default")
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Type, ...
                statusMgr.StatusType.Idle)
        end

        function tHandleInputRequestTransitionsToAwaitingThenSupplied(testCase)
            % Verify the protocol transitions via a timer-driven mock that
            % intercepts the claim before CommandWindow's blocking input()
            % can run. Replace the view's handleInputRequest with a spy.
            %
            % Strategy: disable the real view, wire up a mock directly.
            testCase.CommandWindowView.HandleInputRequests = false;

            observedTypes = statusMgr.StatusType.empty(1,0);
            t = timer("StartDelay", 0.05, "TimerFcn", @(~,~) mockView(testCase.Stack));
            testCase.addTeardown(@() delete(t));
            start(t);

            value = testCase.Stack.requestInput("Enter x", ...
                DefaultValue="d", Timeout=3);

            testCase.verifyEqual(value, "mock-value")

            function mockView(stack)
                s = stack.CurrentStatus;
                if s.Type == statusMgr.StatusType.RequestingInput
                    s.transitionInputState(statusMgr.StatusType.AwaitingInput);
                    s.transitionInputState(statusMgr.StatusType.ValueSupplied, "mock-value");
                end
            end
        end

        function tHandleInputRequestUsesReadUserInput(testCase)
            % CommandWindow's real handleInputRequest reads from stdin via
            % the readUserInput seam. A subclass that returns a canned
            % response lets us exercise the full claim/transition path.
            mock = inttest.helpers.MockCommandWindow(testCase.Stack);
            testCase.addTeardown(@() delete(mock));
            mock.Responses = "typed answer";

            % Disable the real (test-fixture) view so the mock claims the
            % request first and produces a deterministic value.
            testCase.CommandWindowView.HandleInputRequests = false;

            value = testCase.Stack.requestInput("Enter x", ...
                DefaultValue="d", Timeout=3);

            testCase.verifyEqual(value, "typed answer")
        end

        function tHandleInputRequestEmptyInputUsesDefault(testCase)
            % If readUserInput returns "" the default value is used.
            mock = inttest.helpers.MockCommandWindow(testCase.Stack);
            testCase.addTeardown(@() delete(mock));
            mock.Responses = "";

            testCase.CommandWindowView.HandleInputRequests = false;

            value = testCase.Stack.requestInput("Enter x", ...
                DefaultValue="defaulted", Timeout=3);

            testCase.verifyEqual(value, "defaulted")
        end

        function tHandleInputRequestEmptyPromptUsesPlaceholder(testCase)
            % Empty Message gets replaced with "Enter value" when prompting.
            mock = inttest.helpers.MockCommandWindow(testCase.Stack);
            testCase.addTeardown(@() delete(mock));
            mock.Responses = "ok";

            testCase.CommandWindowView.HandleInputRequests = false;

            value = testCase.Stack.requestInput("", DefaultValue="d", Timeout=3);

            testCase.verifyEqual(value, "ok")
        end

        function tDisplayErrorWithoutMException(testCase)
            output = evalc('testCase.Stack.addStatus("Error", Message="bare message");');
            testCase.verifyEqual(string(output), "Error: bare message" + newline);
        end

        function tWriteToTerminalRepeatedMessagePrintsDot(testCase)
            output = evalc('testCase.Stack.addStatus("Info", Message="same"); testCase.Stack.addStatus("Info", Message="same");');
            testCase.verifyEqual(string(output), "same" + newline + ".");
        end

        function tInfoMessageWithPercentSignWritesLiterally(testCase)
            output = evalc('testCase.Stack.addStatus("Info", Message="100% done, %s %d");');
            testCase.verifyEqual(string(output), "100% done, %s %d" + newline);
        end

        function tErrorMessageWithPercentSignWritesLiterally(testCase)
            output = evalc('testCase.Stack.addStatus("Error", Message="boom 50% %d");');
            testCase.verifyEqual(string(output), "Error: boom 50% %d" + newline);
        end

        function tWarningMessageWithPercentSignFiresWithoutError(testCase)
            output = evalc('testCase.verifyWarningFree(@() testCase.Stack.addStatus("Warning", Message="50% off %s", Identifier="a:b"));');
            testCase.verifyEqual(string(output), "Warning: 50% off %s" + newline);
        end

        function tShowRepeatedAsDotsDisabledPrintsFullMessage(testCase)
            testCase.CommandWindowView.ShowRepeatedAsDots = false;
            output = evalc('testCase.Stack.addStatus("Info", Message="same"); testCase.Stack.addStatus("Info", Message="same");');
            testCase.verifyEqual(string(output), "same" + newline + "same" + newline);
        end

    end


end

