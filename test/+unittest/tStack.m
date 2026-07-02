classdef tStack < matlab.unittest.TestCase

    methods (Test)

        function tDefaultStack(testCase)
            % Check the default properties of a Stack. The default
            % Idle status carries its own per-instance Completed
            % listener, so StatusListeners is a 1-element array
            % rather than empty.
            S = statusMgr.Stack();

            testCase.assertSize(S.Statuses, [1 1]);
            testCase.assertSize(S.StatusListeners, [1 1]);
            testCase.assertTrue(isvalid(S.StatusListeners));
            testCase.assertEmpty(S.StackMonitorableListeners);
            testCase.verifyEqual(S.Statuses, S.CurrentStatus);
        end

        function tIdleStatusByDefault(testCase)
            % Status on a new stack is Idle by default.
            S = statusMgr.Stack();

            testCase.verifyEqual(S.CurrentStatus.Type, statusMgr.StatusType.Idle)
        end

        function tAddStatus(testCase)
            % Add default status with no other input.
            S = statusMgr.Stack();
            S.addStatus();
            
            testCase.verifySize(S.Statuses, [1 2])
            testCase.verifyEqual(S.CurrentStatus.Type, statusMgr.StatusType.Info)
            testCase.verifyEqual(S.CurrentStatus.Message, "")
            testCase.verifyEqual(S.CurrentStatus.MessageShort, "")
        end

        function tAddStatusWithProperties(testCase)
            % Add a status with non-default inputs.
            S = statusMgr.Stack();
            S.addStatus("Info", Message="t1", Value=10, IsTemporary=true, ...
                Identifier="id1", Data={1,2}, MessageShort="m1", ...
                Level="Debug");

            testCase.verifySize(S.Statuses, [1 2])
            testCase.verifyEqual(S.CurrentStatus.Type, statusMgr.StatusType.Info)
            testCase.verifyEqual(S.CurrentStatus.Message, "t1")
            testCase.verifyEqual(S.CurrentStatus.MessageShort, "m1")
            testCase.verifyTrue(S.CurrentStatus.IsTemporary)
            testCase.verifyEqual(S.CurrentStatus.Level, statusMgr.Level.Debug)
            testCase.verifyEqual(S.CurrentStatus.Value, 10)
            testCase.verifyEqual(S.CurrentStatus.Identifier, "id1")
            testCase.verifyEqual(S.CurrentStatus.Data, {1,2})
        end

        function tAddStatusWithTitle(testCase)
            % Title is threaded through addStatus to the Status object.
            S = statusMgr.Stack();
            S.addStatus("Running", Title="Phase 1");

            testCase.verifyEqual(S.CurrentStatus.Title, "Phase 1")
        end

        function tAddStatusDefaultTitle(testCase)
            % Default Title is an empty string.
            S = statusMgr.Stack();
            S.addStatus("Running");

            testCase.verifyEqual(S.CurrentStatus.Title, "")
        end

        function tAddStatusWithCleanup(testCase)
            % Request the second output (cleanup object) when adding a
            % status.
            S = statusMgr.Stack();
            [~, cleanupObj] = S.addStatus("Warning"); %#ok<ASGLU>

            testCase.verifySize(S.Statuses, [1 2])
            testCase.verifyEqual(S.Statuses(end), S.CurrentStatus)

            clear cleanupObj

            testCase.verifySize(S.Statuses, [1 1])
            testCase.verifyEqual(S.CurrentStatus.Type, statusMgr.StatusType.Idle)
        end

        function tAddMultipleStatuses(testCase)
            S = statusMgr.Stack();
            S.addStatus("Error", Message="S1");
            S.addStatus("Success", Message="S2");
            S.addStatus("Success", Message="S3");

            testCase.verifySize(S.Statuses, [1 4])
            testCase.verifyEqual(S.CurrentStatus.Message, "S3")
        end

        function tRemoveStatus(testCase)
            % Remove a specific status in the stack.
            S = statusMgr.Stack();
            statusToRemove = S.addStatus("Success", Message="S1");
            S.addStatus("Success", Message="S2");
            S.addStatus("Success", Message="S3");

            S.removeStatus(statusToRemove);

            testCase.verifySize(S.Statuses, [1 3])
            testCase.verifyEqual(S.CurrentStatus.Message, "S3")
            testCase.verifyEqual(S.Statuses(2).Message, "S2")
        end

        function tRemoveLastStatus(testCase)
            S = statusMgr.Stack();
            S.addStatus("Success", Message="S1");
            status = S.addStatus("Success", Message="S2");

            S.removeLastStatus();

            testCase.verifySize(S.Statuses, [1 2])
            testCase.verifyEqual(S.CurrentStatus.Message, "S1")
            testCase.verifyTrue(status.IsComplete)
        end

        function tCompleteStatus(testCase)
            % Manually complete a status.
            S = statusMgr.Stack();
            status = S.addStatus("Running");

            testCase.verifyFalse(status.IsComplete)

            status.complete();

            testCase.verifyTrue(status.IsComplete)
            testCase.verifySize(S.Statuses, [1 1])
            testCase.verifyEqual(S.CurrentStatus.Type, statusMgr.StatusType.Idle)
        end

        function tRemoveAllStatuses(testCase)
            S = statusMgr.Stack();
            S.addStatus("Success", Message="S1");
            S.addStatus("Success", Message="S2");

            testCase.verifySize(S.Statuses, [1 3])

            S.removeAllStatuses();

            testCase.verifySize(S.Statuses, [1 1])
            testCase.verifyEqual(S.CurrentStatus.Type, statusMgr.StatusType.Idle)
        end

        function tPrintTable(testCase)
            % Display summary table of statuses.
            S = statusMgr.Stack();
            S.addStatus("RunningCancellable", Message="S1");
            S.addStatus("Warning", Message="S2");

            t = S.table();

            testCase.assertSize(t, [3 13])
            testCase.verifyEqual(t.Type, ["Idle"; "RunningCancellable"; "Warning"])
            testCase.verifyEqual(t.Message, ["";"S1";"S2"])
            testCase.verifyClass(t.Timestamp, "datetime")
            testCase.verifyClass(t.User, "string")
            testCase.verifyClass(t.Identifier, "string")
            testCase.verifyClass(t.Title, "string")
            testCase.verifyClass(t.MessageShort, "string")
        end

        function tAddError(testCase)
            S = statusMgr.Stack();
            S.addError(MException("a:b:c", "test"));

            testCase.verifyEqual(S.CurrentStatus.Type, statusMgr.StatusType.Error)
            testCase.verifyEqual(S.CurrentStatus.Message, "test")
            testCase.assertClass(S.CurrentStatus.Data, "MException")
            testCase.verifyEqual(S.CurrentStatus.Data.identifier, 'a:b:c')
            testCase.verifyEqual(S.CurrentStatus.Identifier, "a:b:c")
        end

        function tRunCommand(testCase)
            S = statusMgr.Stack();
            result = S.run(@() 1+1);

            testCase.verifyEqual(result, 2)
            testCase.assertSize(S.Statuses, [1 1])
            testCase.verifyEqual(S.CurrentStatus.Type, statusMgr.StatusType.Idle)
        end

        function tRunCommandWithWarning(testCase)
            S = statusMgr.Stack();
            S.run(@() warning("test"));

            testCase.assertEqual(S.CurrentStatus.Type, statusMgr.StatusType.Warning)
            testCase.verifyEqual(S.CurrentStatus.Message, "test")
        end

        function tRunCommandWithError(testCase)
            S = statusMgr.Stack();
            S.run(@() error("test"));

            testCase.assertEqual(S.CurrentStatus.Type, statusMgr.StatusType.Error)
            testCase.verifyEqual(S.CurrentStatus.Data.message, 'test')
        end

        function tRunMultipleCommands(testCase)
            S = statusMgr.Stack();
            S.run(@() 1+1);
            S.run(@() error("test 1"));
            S.run(@() error("test 2"));
            S.run(@() 1+1);
            S.run(@() warning("test"));

            testCase.assertSize(S.Statuses, [1 4])
            testCase.verifyEqual(S.CurrentStatus.Type, statusMgr.StatusType.Warning)
            testCase.verifyEqual(S.Statuses(2).MessageShort, "test 1")
        end

        function tRunCommandWithMultipleOutputs(testCase)
            S = statusMgr.Stack();
            [a, b, c] = S.run(@() fileparts("a/b.c"));
             
            testCase.verifyEqual(a, "a")
            testCase.verifyEqual(b, "b")
            testCase.verifyEqual(c, ".c")
        end

        function tUpdateStatus(testCase)
            % Update value and message of the current status.
            S = statusMgr.Stack();
            status = S.addStatus("Running", Message="m1", Value=1);

            testCase.verifyEqual(S.CurrentStatus.Message, "m1")
            testCase.verifyEqual(S.CurrentStatus.Value, 1)

            S.updateStatus(status, Value=2);
            S.updateStatus(status, Message="m2");

            testCase.verifyEqual(S.CurrentStatus.Message, "m2")
            testCase.verifyEqual(S.CurrentStatus.Value, 2)
        end

        function tUpdateOldStatus(testCase)
            % Update message and value of a status that no longer exists.
            S = statusMgr.Stack();
            status = S.addStatus("Running", Message="m1", Value=1);
            status.complete();

            S.addStatus("Warning");

            S.updateStatus(status, Value=2);
            S.updateStatus(status, Message="m2");

            testCase.assertSize(S.Statuses, [1, 2])
            testCase.assertEqual(S.CurrentStatus.Type, statusMgr.StatusType.Warning)
        end

        function tUpdateWithNoInputs(testCase)
            % Calling the update method without specifying a value or
            % message does nothing.
            S = statusMgr.Stack();
            status = S.addStatus("Running", Message="m1", Value=1);
            
            S.updateStatus(status);

            testCase.verifyEqual(S.CurrentStatus.Message, "m1")
            testCase.verifyEqual(S.CurrentStatus.Value, 1)
        end

        function tAddStatusToMultipleStacks(testCase)
            % Add the same status to an array of stacks.
            S1 = statusMgr.Stack();
            S2 = statusMgr.Stack();
            StackArray = [S1, S2];

            status = StackArray.addStatus("Warning", Message="m1", Value=1);

            testCase.assertSize(status, [1 1])
            testCase.verifyEqual(S1.CurrentStatus.ID, status.ID)
            testCase.verifyEqual(S2.CurrentStatus.ID, status.ID)
            testCase.verifyEqual(S2.CurrentStatus.Message, "m1")
            testCase.verifyEqual(S2.CurrentStatus.Type, statusMgr.StatusType.Warning)
            testCase.verifyEqual(S1.CurrentStatus.Value, 1)
        end

        function tUpdateMultipleStacks(testCase)
            % Call the update method on an array of stacks.
            S1 = statusMgr.Stack();
            S2 = statusMgr.Stack();
            StackArray = [S1, S2];

            status = StackArray.addStatus("Running", Message="m1", Value=1);
            StackArray.updateStatus(status, Message="m2", Value=2);

            testCase.verifyEqual(S1.CurrentStatus.Message, "m2")
            testCase.verifyEqual(S1.CurrentStatus.Value, 2)
            testCase.verifyEqual(S2.CurrentStatus.Message, "m2")
            testCase.verifyEqual(S2.CurrentStatus.Value, 2)
        end

        function tEmptyStack(testCase)
            % Call the main methods on an empty stack.
            S = statusMgr.Stack.empty(1,0);

            status = S.addStatus("Running");
            testCase.verifyEmpty(status);

            S.updateStatus(statusMgr.Status("Running"), Message="m", Value=1);
            S.removeStatus(statusMgr.Status("Running"));

            testCase.verifyEmpty(S);
        end

        function tSuppressIdentifier(testCase)
            % Suppression never mutates statuses: the stack records
            % everything, and the suppression list is seeded into the
            % excludes of views bound afterwards.
            S = statusMgr.Stack();
            S.suppressIdentifier("my:id");

            view = statusMgr.view.RecordingView(S);
            testCase.addTeardown(@() delete(view))

            S.addStatus("Warning", Identifier="my:id", Message="suppressed");
            S.addStatus("Warning", Identifier="other:id", Message="visible");

            testCase.assertSize(S.Statuses, [1 3])   % stack keeps both
            testCase.verifyTrue(ismember("my:id", view.ExcludeIdentifiers))
            testCase.verifyEqual(view.RecordedStatuses.Message, "visible")
        end

        function tSuppressAfterBindDoesNotAffectExistingView(testCase)
            % Seeding happens at bind time only: a view attached before
            % suppressIdentifier keeps displaying the identifier.
            S = statusMgr.Stack();
            view = statusMgr.view.RecordingView(S);
            testCase.addTeardown(@() delete(view))

            S.suppressIdentifier("my:id");
            S.addStatus("Warning", Identifier="my:id", Message="still recorded");

            testCase.verifyEqual(view.RecordedStatuses.Message, "still recorded")
        end

        function tSuppressDuplicateIdentifier(testCase)
            % Suppressing the same identifier twice only adds it once.
            S = statusMgr.Stack();
            S.suppressIdentifier("my:id");
            S.suppressIdentifier("my:id");

            testCase.verifySize(S.SuppressedIdentifiers, [1 1])
        end

        function tUnsuppressIdentifier(testCase)
            % After unsuppressing, views bound afterwards are not seeded
            % with the identifier and display it normally.
            S = statusMgr.Stack();
            S.suppressIdentifier("my:id");
            S.unsuppressIdentifier("my:id");
            testCase.verifyEmpty(S.SuppressedIdentifiers)

            view = statusMgr.view.RecordingView(S);
            testCase.addTeardown(@() delete(view))

            S.addStatus("Warning", Identifier="my:id", Message="visible again");

            testCase.verifyEqual(view.RecordedStatuses.Message, "visible again")
        end

        function tSuppressGlobMatchesNamespacePrefix(testCase)
            % "myapp:net:*" matches any identifier with that prefix.
            S = statusMgr.Stack();
            S.suppressIdentifier("myapp:net:*");

            view = statusMgr.view.RecordingView(S);
            testCase.addTeardown(@() delete(view))

            S.addStatus("Warning", Identifier="myapp:net:timeout", Message="hidden");
            S.addStatus("Warning", Identifier="myapp:db:slow", Message="visible");

            testCase.verifyEqual(view.RecordedStatuses.Message, "visible")
        end

        function tSuppressGlobMatchesAnywhere(testCase)
            % "*timeout*" matches an identifier containing "timeout".
            S = statusMgr.Stack();
            S.suppressIdentifier("*timeout*");

            view = statusMgr.view.RecordingView(S);
            testCase.addTeardown(@() delete(view))

            S.addStatus("Warning", Identifier="myapp:net:timeout", Message="hidden");
            S.addStatus("Warning", Identifier="other:timeout:detail", Message="hidden");
            S.addStatus("Warning", Identifier="unrelated", Message="visible");

            testCase.verifyEqual(view.RecordedStatuses.Message, "visible")
        end

        function tSuppressGlobLiteralStringStillWorks(testCase)
            % Adding an identifier without "*" continues to require an
            % exact match (backward-compatible behaviour).
            S = statusMgr.Stack();
            S.suppressIdentifier("a:b");

            view = statusMgr.view.RecordingView(S);
            testCase.addTeardown(@() delete(view))

            S.addStatus("Warning", Identifier="a:b", Message="hidden");
            S.addStatus("Warning", Identifier="a:b:c", Message="visible");

            testCase.verifyEqual(view.RecordedStatuses.Message, "visible")
        end

        function tSuppressDoesNotAffectNoIdentifier(testCase)
            % Statuses with no identifier are never affected by suppression.
            S = statusMgr.Stack();
            S.suppressIdentifier("my:id");

            view = statusMgr.view.RecordingView(S);
            testCase.addTeardown(@() delete(view))

            S.addStatus("Warning", Message="no id");

            testCase.verifyEqual(view.RecordedStatuses.Message, "no id")
        end

        function tMonitorable(testCase)
            % If a monitorable class calls setStatus within its code it
            % gets picked up by the status stack.
            S = statusMgr.Stack();
            obj = statusMgr.demo.DemoMonitorable;
            S.monitor(obj);

            obj.showError("test");

            testCase.verifyEqual(S.CurrentStatus.Type, statusMgr.StatusType.Error)
            testCase.verifyEqual(S.CurrentStatus.Message, "test")
        end

        % --- requestInput ---------------------------------------------------

        function tRequestInputNoArgsUsesEmptyPromptAndDefaults(testCase)
            % Calling requestInput() with no arguments applies the prompt,
            % DefaultValue, Title, and Timeout defaults.
            S = statusMgr.Stack();
            value = S.requestInput();

            testCase.verifyEqual(value, "")
        end

        function tRequestInputReturnsDefaultWhenNoViewAttached(testCase)
            % With no views listening, requestInput returns DefaultValue
            % once the timeout elapses.
            S = statusMgr.Stack();
            value = S.requestInput("Prompt", DefaultValue="fallback", Timeout=0.1);

            testCase.verifyEqual(value, "fallback")
        end

        function tRequestInputDefaultIsEmptyStringWhenNotSpecified(testCase)
            % Default value is "" when not supplied by the caller.
            S = statusMgr.Stack();
            value = S.requestInput("Prompt", Timeout=0.1);

            testCase.verifyEqual(value, "")
        end

        function tRequestInputCleansUpStatusAfterReturn(testCase)
            % The RequestingInput status is removed from the stack once
            % requestInput returns.
            S = statusMgr.Stack();
            S.requestInput("Prompt", Timeout=0.1);

            testCase.verifyEqual(S.CurrentStatus.Type, statusMgr.StatusType.Idle)
            testCase.verifySize(S.Statuses, [1 1])
        end

        function tRequestInputReturnedValueFromSimulatedView(testCase)
            % Simulate a view that claims RequestingInput and supplies a
            % value. Verify requestInput returns that value.
            S = statusMgr.Stack();

            % After a short delay, a timer acts as a mock view.
            t = timer("StartDelay", 0.1, "TimerFcn", @(~,~) claimAndSupply(S));
            testCase.addTeardown(@() delete(t));
            start(t);

            value = S.requestInput("Enter name", DefaultValue="default", Timeout=3);

            testCase.verifyEqual(value, "supplied-value")

            function claimAndSupply(stack)
                s = stack.CurrentStatus;
                if s.Type == statusMgr.StatusType.RequestingInput
                    s.transitionInputState(statusMgr.StatusType.AwaitingInput);
                    s.transitionInputState(statusMgr.StatusType.ValueSupplied, "supplied-value");
                end
            end
        end

        function tRequestInputUsesDefaultWhenViewClaimsButStackRemoved(testCase)
            % If the status is removed externally while AwaitingInput,
            % requestInput falls through and returns the default.
            S = statusMgr.Stack();

            t = timer("StartDelay", 0.1, "TimerFcn", @(~,~) claimOnly(S));
            t2 = timer("StartDelay", 0.3, "TimerFcn", @(~,~) S.removeAllStatuses());
            testCase.addTeardown(@() delete(t));
            testCase.addTeardown(@() delete(t2));
            start(t);
            start(t2);

            value = S.requestInput("Prompt", DefaultValue="safe", Timeout=3);

            testCase.verifyEqual(value, "safe")

            function claimOnly(stack)
                s = stack.CurrentStatus;
                if s.Type == statusMgr.StatusType.RequestingInput
                    s.transitionInputState(statusMgr.StatusType.AwaitingInput);
                end
            end
        end

        function tRunCommandWithArguments(testCase)
            % run() passes Args through to the function handle.
            S = statusMgr.Stack();
            result = S.run(@(a, b) a + b, Args={3, 4});

            testCase.verifyEqual(result, 7)
            testCase.verifyEqual(S.CurrentStatus.Type, statusMgr.StatusType.Idle)
        end

        function tRunCatchErrorsFalseRethrows(testCase)
            % With CatchErrors=false, errors raised inside fcn propagate
            % to the caller instead of being captured as an Error status.
            % The Running status is still cleaned up on the way out via
            % its onCleanup, so the stack returns to Idle.
            S = statusMgr.Stack();

            testCase.verifyError( ...
                @() S.run(@() error("test:err", "boom"), CatchErrors=false), ...
                "test:err")
            testCase.verifyEqual(S.CurrentStatus.Type, statusMgr.StatusType.Idle)
        end

        function tRunCatchWarningsFalseSkipsWarningStatus(testCase)
            % With CatchWarnings=false, warnings raised inside fcn do not
            % become Warning statuses on the stack.
            S = statusMgr.Stack();

            S.run(@() warning("test:w", "hi"), CatchWarnings=false);

            testCase.verifyEqual(S.CurrentStatus.Type, statusMgr.StatusType.Idle)
        end

        function tRunCancellablePassesStatusAsFirstArg(testCase)
            % The wrapped function receives the RunningCancellable
            % Status as its first argument; Args from the call site
            % are appended after.
            S = statusMgr.Stack();
            seenStatus = [];
            seenArgs = {};

            S.runCancellable(@(status, a, b) capture(status, a, b), Args={3, 4});

            testCase.assertClass(seenStatus, "statusMgr.Status")
            testCase.verifyEqual(seenStatus.Type, statusMgr.StatusType.RunningCancellable)
            testCase.verifyEqual(seenArgs, {3, 4})

            function capture(status, a, b)
                seenStatus = status;
                seenArgs = {a, b};
            end
        end

        function tRunCancellablePushesRunningCancellableStatus(testCase)
            % While the function runs, the current status is
            % RunningCancellable; after run, the stack is back to Idle.
            S = statusMgr.Stack();
            typeAtRunTime = [];

            S.runCancellable(@(status) capture(status));

            testCase.verifyEqual(typeAtRunTime, statusMgr.StatusType.RunningCancellable)
            testCase.verifyEqual(S.CurrentStatus.Type, statusMgr.StatusType.Idle)

            function capture(status) %#ok<INUSD>
                typeAtRunTime = S.CurrentStatus.Type;
            end
        end

        function tRunCancellableStatusCompleteObservedByPolling(testCase)
            % If something completes the status while the function is
            % running (the cancel signal), the function can poll
            % status.IsComplete and exit early.
            S = statusMgr.Stack();
            iterationsBeforeCancel = 0;

            S.runCancellable(@(status) loopUntilComplete(status));

            testCase.verifyGreaterThan(iterationsBeforeCancel, 0)
            testCase.verifyLessThan(iterationsBeforeCancel, 100)

            function loopUntilComplete(status)
                for i = 1:100
                    if i == 5
                        % Simulate an external cancel signal.
                        status.complete();
                    end
                    if status.IsComplete
                        iterationsBeforeCancel = i;
                        return
                    end
                end
            end
        end

        function tRemoveStatusFromMultipleStacks(testCase)
            % removeStatus on a stack array removes the status from every stack.
            S1 = statusMgr.Stack();
            S2 = statusMgr.Stack();
            StackArray = [S1, S2];

            status = StackArray.addStatus("Warning", Message="m1");
            StackArray.removeStatus(status);

            testCase.verifySize(S1.Statuses, [1 1])
            testCase.verifyEqual(S1.CurrentStatus.Type, statusMgr.StatusType.Idle)
            testCase.verifySize(S2.Statuses, [1 1])
            testCase.verifyEqual(S2.CurrentStatus.Type, statusMgr.StatusType.Idle)
            testCase.verifyTrue(status.IsComplete)
        end

        function tAddStatusCleanupObjFalseReturnsOnCleanupType(testCase)
            % When CreateCleanupObj=false, the second output is an empty
            % onCleanup (consistent with the empty-stack branch), not a cell.
            S = statusMgr.Stack();
            [~, cleanupObj] = S.addStatus("Warning", CreateCleanupObj=false);

            testCase.verifyClass(cleanupObj, "onCleanup")
            testCase.verifyEmpty(cleanupObj)
        end

        function tStackDeleteCleansUpMonitorableListeners(testCase)
            % Stack.delete must dispose of StackMonitorableListeners as well
            % as StatusListeners; otherwise monitorable listeners leak.
            S = statusMgr.Stack();
            obj = statusMgr.demo.DemoMonitorable;
            S.monitor(obj);

            listeners = S.StackMonitorableListeners;
            testCase.assertNotEmpty(listeners)
            testCase.assertTrue(all(isvalid(listeners)))

            delete(S);

            testCase.verifyFalse(any(isvalid(listeners)))
        end

        function tStackDeleteCleansUpStatusListeners(testCase)
            % Companion check for the existing StatusListeners cleanup.
            S = statusMgr.Stack();
            S.addStatus("Running");

            listeners = S.StatusListeners;
            testCase.assertNotEmpty(listeners)
            testCase.assertTrue(all(isvalid(listeners)))

            delete(S);

            testCase.verifyFalse(any(isvalid(listeners)))
        end

        function tRequestInputStatusPushedWithCorrectProperties(testCase)
            % The RequestingInput status carries the prompt in Message,
            % the title in Title, and the default in Data.
            S = statusMgr.Stack();
            capturedStatus = [];

            t = timer("StartDelay", 0.05, "TimerFcn", @(~,~) captureAndSupply(S));
            testCase.addTeardown(@() delete(t));
            start(t);

            S.requestInput("My prompt", DefaultValue="def", Title="My title", Timeout=3);

            testCase.verifyEqual(capturedStatus.Message, "Entered Value")
            testCase.verifyEqual(capturedStatus.Title, "My title")
            testCase.verifyEqual(string(capturedStatus.Data), "def")

            function captureAndSupply(stack)
                s = stack.CurrentStatus;
                if s.Type == statusMgr.StatusType.RequestingInput
                    capturedStatus = s;
                    s.transitionInputState(statusMgr.StatusType.AwaitingInput);
                    s.transitionInputState(statusMgr.StatusType.ValueSupplied, "Entered Value");
                end
            end
        end

    end


end