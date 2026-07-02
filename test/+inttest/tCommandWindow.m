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
            testCase.verifyEqual(testCase.CommandWindowView.IncomingStatus.Message, "i2");
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
            fcn = @() testCase.Stack.addStatus("Warning", Message="w1", Identifier="a:b");
            testCase.verifyWarning(fcn, "a:b")
        end

        function tDisplayError(testCase)

            me = MException("a:b:c", "test error a:b:c");

            diaryFile = testCase.diaryFixture();

            testCase.Stack.addError(me);

            lines = strjoin(readlines(diaryFile), newline);
            testCase.verifyTrue(contains(lines, "test error a:b:c"));

            testCase.verifyEqual(testCase.CommandWindowView.PreviousMessage, string(me.getReport()));

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

        function tBelowMinLevelStatus(testCase)
            % A status below the view's MinLevel is not printed.
            testCase.CommandWindowView.MinLevel = "Info";
            testCase.Stack.addStatus("Warning", Message="hidden", Level="Trace");
            testCase.verifyTrue(ismissing(testCase.CommandWindowView.PreviousMessage))
        end

        function tSuppressedIdentifier(testCase)
            % Stack suppression seeds the excludes of views bound after
            % the call: a fresh view does not print the identifier.
            S = statusMgr.Stack();
            S.suppressIdentifier("my:id");
            view = statusMgr.view.CommandWindow(S);
            testCase.addTeardown(@() delete(view))

            S.addStatus("Warning", Identifier="my:id", Message="suppressed");

            testCase.verifyTrue(ismissing(view.PreviousMessage))
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
            % Error statuses with non-MException (or empty) Data take the
            % "Error: <message>" branch instead of the getReport path.
            diaryFile = testCase.diaryFixture();

            testCase.Stack.addStatus("Error", Message="bare message");

            lines = strjoin(readlines(diaryFile), newline);
            testCase.verifyTrue(contains(lines, "Error: bare message"));
        end

        function tWriteToTerminalRepeatedMessagePrintsDot(testCase)
            % Two consecutive identical messages produce a "." for the
            % second when ShowRepeatedAsDots is true (the default).
            diaryFile = testCase.diaryFixture();

            testCase.Stack.addStatus("Info", Message="same");
            testCase.Stack.addStatus("Info", Message="same");
            diary off

            lines = strjoin(readlines(diaryFile), newline);
            testCase.verifyTrue(contains(lines, "same"));
            testCase.verifyTrue(contains(lines, "."));
        end

        function tInfoMessageWithPercentSignWritesLiterally(testCase)
            % `%` in a message must NOT be interpreted as a printf format
            % spec. Pre-fix this would consume an arg / produce garbage.
            diaryFile = testCase.diaryFixture();

            testCase.Stack.addStatus("Info", Message="100% done, %s %d");
            diary off

            lines = strjoin(readlines(diaryFile), newline);
            testCase.verifyTrue(contains(lines, "100% done, %s %d"))
        end

        function tErrorMessageWithPercentSignWritesLiterally(testCase)
            diaryFile = testCase.diaryFixture();

            testCase.Stack.addStatus("Error", Message="boom 50% %d");
            diary off

            lines = strjoin(readlines(diaryFile), newline);
            testCase.verifyTrue(contains(lines, "Error: boom 50% %d"))
        end

        function tWarningMessageWithPercentSignFiresWithoutError(testCase)
            % `warning(id, msg)` treats msg as a format string; a `%`
            % in user content used to error or produce garbage.
            fcn = @() testCase.Stack.addStatus("Warning", ...
                Message="50% off %s", Identifier="a:b");
            testCase.verifyWarning(fcn, "a:b")
        end

        function tShowRepeatedAsDotsDisabledPrintsFullMessage(testCase)
            % With ShowRepeatedAsDots=false, a repeated message is printed
            % in full instead of being collapsed to a dot.
            testCase.CommandWindowView.ShowRepeatedAsDots = false;
            diaryFile = testCase.diaryFixture();

            testCase.Stack.addStatus("Info", Message="same");
            testCase.Stack.addStatus("Info", Message="same");
            diary off

            lines = readlines(diaryFile);
            % Expect "same" on at least two separate lines.
            sameLines = sum(contains(lines, "same"));
            testCase.verifyGreaterThanOrEqual(sameLines, 2)
        end

    end

    methods (Access = protected)

        function diaryFile = diaryFixture(testCase)
            % Use diary to capture the output to the command window
            testCase.addTeardown(@() diary(get(0,'Diary')));

            wff = matlab.unittest.fixtures.WorkingFolderFixture;
            testCase.applyFixture(wff);
            diaryFile = fullfile(wff.Folder, "diary.txt");
            testCase.addTeardown(@() delete(diaryFile));

            testCase.addTeardown(@() diary("off")); % Ensure the diary is closed before trying to delete the file
            diary(diaryFile);
        end

    end

end

