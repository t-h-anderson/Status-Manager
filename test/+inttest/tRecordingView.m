classdef tRecordingView < matlab.unittest.TestCase

    methods (Test)

        function tStartsEmpty(testCase)
            S = statusMgr.Stack();
            view = statusMgr.view.RecordingView(S);
            testCase.addTeardown(@() delete(view))

            testCase.verifyClass(view.RecordedStatuses, "table")
            testCase.verifyEmpty(view.RecordedStatuses)
        end

        function tRecordsStatusesInOrder(testCase)
            S = statusMgr.Stack();
            view = statusMgr.view.RecordingView(S);
            testCase.addTeardown(@() delete(view))

            S.addStatus("Info", Message="hello");
            S.addStatus("Warning", Message="oops");
            S.addStatus("Success", Message="done");

            testCase.assertSize(view.RecordedStatuses, [3 13])
            testCase.verifyEqual(view.RecordedStatuses.Message, ...
                ["hello"; "oops"; "done"])
        end

        function tRecordsAreSnapshots(testCase)
            % Mutating the underlying Status after publication does not
            % change earlier rows: that's the snapshot guarantee the
            % table representation exists to provide (issue #45).
            S = statusMgr.Stack();
            view = statusMgr.view.RecordingView(S);
            testCase.addTeardown(@() delete(view))

            status = S.addStatus("Info", Message="original");
            S.updateStatus(status, Message="mutated");

            firstRowMessage = view.RecordedStatuses.Message(1);
            testCase.verifyEqual(firstRowMessage, "original")
        end

        function tHonoursShowFlags(testCase)
            % ShowWarnings=false suppresses Warning recording without
            % affecting other types.
            S = statusMgr.Stack();
            view = statusMgr.view.RecordingView(S, ShowWarnings=false);
            testCase.addTeardown(@() delete(view))

            S.addStatus("Info", Message="i");
            S.addStatus("Warning", Message="w");
            S.addStatus("Error", Message="e");

            testCase.verifyEqual(view.RecordedStatuses.Type, ...
                ["Info"; "Error"])
        end

        function tShowIdleOptIn(testCase)
            % Explicit Idle entries are recorded; stack-removal refreshes are not.
            stack = statusMgr.Stack();
            testCase.addTeardown(@() delete(stack));
            ordinary = statusMgr.view.RecordingView(stack);
            testCase.addTeardown(@() delete(ordinary));
            withIdle = statusMgr.view.RecordingView(stack, ShowIdle=true);
            testCase.addTeardown(@() delete(withIdle));
            stack.addStatus("Info", Message="hi");
            stack.addStatus("Idle", Message="explicit idle");
            stack.removeAllStatuses();
            testCase.verifyEqual(ordinary.RecordedStatuses.Type, "Info");
            testCase.verifyEqual(withIdle.RecordedStatuses.Type, ["Info"; "Idle"]);
        end

        function tClearEmptiesHistory(testCase)
            S = statusMgr.Stack();
            view = statusMgr.view.RecordingView(S);
            testCase.addTeardown(@() delete(view))

            S.addStatus("Info", Message="hi");
            testCase.assertSize(view.RecordedStatuses, [1 13])

            view.clear();

            testCase.verifyEmpty(view.RecordedStatuses)
            testCase.verifyClass(view.RecordedStatuses, "table")
        end

        function tIncludeIdentifiersGlobAllowList(testCase)
            % With IncludeIdentifiers set, only matching statuses are
            % shown; unidentified statuses are dropped.
            S = statusMgr.Stack();
            view = statusMgr.view.RecordingView(S, ...
                IncludeIdentifiers=["myapp:net:*"]);
            testCase.addTeardown(@() delete(view))

            S.addStatus("Info", Identifier="myapp:net:slow", Message="kept");
            S.addStatus("Info", Identifier="myapp:db:slow", Message="dropped");
            S.addStatus("Info", Message="no id, dropped");

            testCase.verifyEqual(view.RecordedStatuses.Message, "kept")
        end

        function tExcludeIdentifiersGlobBlockList(testCase)
            % With ExcludeIdentifiers, matching statuses are dropped;
            % everything else (including unidentified) is recorded.
            S = statusMgr.Stack();
            view = statusMgr.view.RecordingView(S, ...
                ExcludeIdentifiers=["*timeout*"]);
            testCase.addTeardown(@() delete(view))

            S.addStatus("Info", Identifier="myapp:net:timeout", Message="dropped");
            S.addStatus("Info", Identifier="myapp:db:slow", Message="kept");
            S.addStatus("Info", Message="kept too");

            testCase.verifyEqual(view.RecordedStatuses.Message, ...
                ["kept"; "kept too"])
        end

        function tIncludeAndExcludeCombine(testCase)
            % Include narrows; exclude further removes from that set.
            S = statusMgr.Stack();
            view = statusMgr.view.RecordingView(S, ...
                IncludeIdentifiers=["myapp:*"], ...
                ExcludeIdentifiers=["*:debug"]);
            testCase.addTeardown(@() delete(view))

            S.addStatus("Info", Identifier="myapp:net:slow", Message="kept");
            S.addStatus("Info", Identifier="myapp:net:debug", Message="dropped");
            S.addStatus("Info", Identifier="other:net:slow", Message="dropped");

            testCase.verifyEqual(view.RecordedStatuses.Message, "kept")
        end

        function tRecordsRequestingInputByDefault(testCase)
            % HandleInputRequests defaults to true on the recorder, so
            % the RequestingInput status is fed through handleInputRequest
            % and recorded. The recorder snapshots Type at record time,
            % so even though requestInput's timeout transitions the same
            % Status to ValueSupplied later, the recorded row still
            % reads RequestingInput. (See issue #45.)
            S = statusMgr.Stack();
            view = statusMgr.view.RecordingView(S);
            testCase.addTeardown(@() delete(view))

            S.requestInput("Need value", DefaultValue="x", Timeout=0.1);

            testCase.verifyTrue(any(view.RecordedStatuses.Type == "RequestingInput"))
        end

    end

end
