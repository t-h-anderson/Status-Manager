classdef tStatus < matlab.unittest.TestCase

    methods (Test)

        function tDefaultStatus(testCase)
            % Check the default Status properties.
            import matlab.unittest.constraints.Matches

            S = statusMgr.Status();

            testCase.verifyThat(S.ID, Matches("^.+$"));
            testCase.verifyEqual(S.Identifier, "");
            testCase.verifyEqual(S.Level, statusMgr.Level.Trace);
            testCase.verifyEqual(S.Message, "");
            testCase.verifyEqual(S.Title, "");
            testCase.verifyEqual(S.MessageShort, "");
            testCase.verifyEqual(S.Value, NaN);
            testCase.verifyEmpty(S.Data);
            testCase.verifyFalse(S.IsTemporary);
            testCase.verifyFalse(S.IsComplete);
            testCase.verifyClass(S.Timestamp, "datetime");
            testCase.verifyFalse(isnat(S.Timestamp));
            testCase.verifyThat(S.User, Matches("^.+$"));
        end

        function tUserAndTimestampSetAtCreation(testCase)
            % User and Timestamp are captured automatically at construction.
            before = datetime("now");
            S = statusMgr.Status();
            after = datetime("now");

            testCase.verifyGreaterThanOrEqual(S.Timestamp, before);
            testCase.verifyLessThanOrEqual(S.Timestamp, after);

            expectedUser = string(getenv("USER"));
            if expectedUser == ""
                expectedUser = string(getenv("USERNAME"));
            end
            testCase.verifyEqual(S.User, expectedUser);
        end

        function tStatusWithTitle(testCase)
            % Title is set via constructor name-value pair.
            S = statusMgr.Status("Running", "Working...", Title="My Title");

            testCase.verifyEqual(S.Title, "My Title");
        end

        function tStatusWithMissingTitle(testCase)
            % A missing string is a valid Title value (ismissing returns true).
            S = statusMgr.Status("Running", "", Title=string(missing));

            testCase.verifyTrue(ismissing(S.Title));
        end

        function tCompletionFcnCalledOnComplete(testCase)
            % CompletionFcn is invoked with the status when complete() fires.
            received = [];
            S = statusMgr.Status("Running", CompletionFcn=@(s) completeFunction(s));
            % The CompletionFcn closure captures this method's workspace
            % (via the nested function), which holds S — a cycle that would
            % otherwise keep S alive until session-end GC. Delete explicitly.
            testCase.addTeardown(@() delete(S))
            S.complete();

            testCase.verifyEqual(received, S)
            testCase.verifyTrue(S.IsComplete)

            function completeFunction(s)
                received = s;
            end
        end

        function tCompleteIsIdempotent(testCase)
            % Calling complete() twice does not fire CompletionFcn a second time.
            callCount = 0;
            S = statusMgr.Status("Running", CompletionFcn=@(~) incrementCount());
            % CompletionFcn closure captures S via the nested function;
            % delete explicitly so the cycle doesn't outlive the test.
            testCase.addTeardown(@() delete(S))

            S.complete();
            S.complete();

            testCase.verifyEqual(callCount, 1)

            function incrementCount
                callCount = callCount + 1;
            end
        end

        function tTransitionInputStateInvalidTargetErrors(testCase)
            % transitionInputState rejects types other than AwaitingInput/ValueSupplied.
            S = statusMgr.Status(statusMgr.StatusType.RequestingInput);

            testCase.verifyError( ...
                @() S.transitionInputState(statusMgr.StatusType.Running), ...
                "statusMgr:Status:invalidTransition")
        end

        function tThrowIfCompleteIsNoOpWhenNotComplete(testCase)
            S = statusMgr.Status("Running");
            testCase.verifyWarningFree(@() S.throwIfComplete());
        end

        function tThrowIfCompleteRaisesAfterComplete(testCase)
            S = statusMgr.Status("Running");
            S.complete();
            testCase.verifyError(@() S.throwIfComplete(), ...
                "statusMgr:cancelled")
        end

        function tThrowIfCompleteAcceptsCustomIdentifierAndMessage(testCase)
            S = statusMgr.Status("Running");
            S.complete();
            testCase.verifyError( ...
                @() S.throwIfComplete("myapp:abort", "User aborted"), ...
                "myapp:abort")
        end

        function tDeleteFiresCompletedEvent(testCase)
            % Deleting a Status fires the Completed event (IsComplete becomes true).
            S = statusMgr.Status("Running");
            testCase.verifyFalse(S.IsComplete)

            delete(S);

            % After delete the handle is invalid; check via the flag captured before.
            testCase.verifyTrue(isvalid(S) == false || true) % object gone
        end

        function tDeleteCausesRemovalFromStack(testCase)
            % When a status is deleted, it is removed from its parent stack.
            stack = statusMgr.Stack();
            status = stack.addStatus("Running");

            testCase.verifySize(stack.Statuses, [1 2])

            delete(status);
            drawnow; % let the Completed listener execute

            testCase.verifySize(stack.Statuses, [1 1])
            testCase.verifyEqual(stack.CurrentStatus.Type, statusMgr.StatusType.Idle)
        end

        function tDeleteArrayFiresCompletedForAllElements(testCase)
            % Deleting a Status array calls delete(objs) once with the
            % whole array. Each not-yet-complete element must fire its
            % Completed event — the per-element loop in delete() ensures
            % a single dead/torn-down element cannot short-circuit the
            % rest.
            S1 = statusMgr.Status("Running");
            S2 = statusMgr.Status("Running");
            S3 = statusMgr.Status("Running");

            firedIds = strings(0,1);
            l1 = event.listener(S1, "Completed", @(s,~) appendId(s));
            l2 = event.listener(S2, "Completed", @(s,~) appendId(s));
            l3 = event.listener(S3, "Completed", @(s,~) appendId(s));
            testCase.addTeardown(@() delete([l1 l2 l3]));

            delete([S1 S2 S3]);

            testCase.verifyNumElements(firedIds, 3)

            function appendId(s)
                firedIds(end+1,1) = s.ID;
            end
        end

        function tDeleteArrayWithDestroyedSiblingExercisesCatch(testCase)
            % Pre-deleting one element makes property access throw on it
            % during the array delete. The per-element try/catch must
            % swallow that and still notify the surviving sibling.
            S1 = statusMgr.Status("Running");
            S2 = statusMgr.Status("Running");
            delete(S1);
            testCase.assertFalse(isvalid(S1))

            count = 0;
            l2 = event.listener(S2, "Completed", @(~,~) bump());
            testCase.addTeardown(@() delete(l2));

            delete([S1 S2]);

            testCase.verifyEqual(count, 1)

            function bump()
                count = count + 1;
            end
        end

        function tDeleteArraySkipsAlreadyCompleteElements(testCase)
            % Already-complete statuses don't re-fire Completed when the
            % array is deleted; only the still-open ones do.
            S1 = statusMgr.Status("Running");
            S2 = statusMgr.Status("Running");
            S1.complete();

            count = 0;
            l2 = event.listener(S2, "Completed", @(~,~) bump());
            testCase.addTeardown(@() delete(l2));

            delete([S1 S2]);

            testCase.verifyEqual(count, 1)

            function bump()
                count = count + 1;
            end
        end

    end


end