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
            % Idle is off by default; turning it on records the Idle
            % statuses that the stack falls back to.
            S = statusMgr.Stack();
            viewDefault = statusMgr.view.RecordingView(S);
            testCase.addTeardown(@() delete(viewDefault))
            viewWithIdle = statusMgr.view.RecordingView(S, ShowIdle=true);
            testCase.addTeardown(@() delete(viewWithIdle))

            S.addStatus("Info", Message="hi");
            S.removeAllStatuses(); % returns stack to Idle

            testCase.verifySize(viewDefault.RecordedStatuses, [1 13])
            % viewWithIdle saw the Idle pushed at construction-time
            % too via the same listener path.
            testCase.verifyGreaterThan(height(viewWithIdle.RecordedStatuses), 1)
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

            % Each non-matching push re-renders the topmost displayable
            % status ("kept"), so it is recorded once per update.
            testCase.verifyEqual(view.RecordedStatuses.Message, ...
                ["kept"; "kept"; "kept"])
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

            % Each non-matching push re-renders the topmost displayable
            % status ("kept"), so it is recorded once per update.
            testCase.verifyEqual(view.RecordedStatuses.Message, ...
                ["kept"; "kept"; "kept"])
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

        % --- Level / verbosity gating (issue #59) ---------------------------

        function tMinLevelGatesVerbosity(testCase)
            % One stack, two verbosities: the terse view records only
            % Warning-and-above, the default view records everything.
            S = statusMgr.Stack();
            terse = statusMgr.view.RecordingView(S, MinLevel="Warning");
            testCase.addTeardown(@() delete(terse))
            verbose = statusMgr.view.RecordingView(S);
            testCase.addTeardown(@() delete(verbose))

            S.addStatus("Info", Message="detail");
            S.addStatus("Error", Message="boom");

            testCase.verifyEqual(terse.RecordedStatuses.Message, "boom")
            testCase.verifyEqual(verbose.RecordedStatuses.Message, ...
                ["detail"; "boom"])
        end

        function tRunningDefaultsToNotice(testCase)
            % Running marks a key state (the app may be unresponsive), so
            % it defaults to Notice: visible at MinLevel=Notice, hidden
            % at MinLevel=Warning.
            S = statusMgr.Stack();
            atNotice = statusMgr.view.RecordingView(S, MinLevel="Notice");
            testCase.addTeardown(@() delete(atNotice))
            atWarning = statusMgr.view.RecordingView(S, MinLevel="Warning");
            testCase.addTeardown(@() delete(atWarning))

            S.addStatus("Running", Message="busy");

            testCase.verifyEqual(atNotice.RecordedStatuses.Message, "busy")
            testCase.verifyEmpty(atWarning.RecordedStatuses)
        end

        function tLevelOverridePromotesStatus(testCase)
            % An explicit Level overrides the type default: a Critical
            % Info clears an Error-level threshold.
            S = statusMgr.Stack();
            view = statusMgr.view.RecordingView(S, MinLevel="Error");
            testCase.addTeardown(@() delete(view))

            S.addStatus("Info", Message="promoted", Level="Critical");

            testCase.verifyEqual(view.RecordedStatuses.Message, "promoted")
        end

        function tFilteredTopStatusRevealsStatusBeneath(testCase)
            % Regression for issue #58: a top status this view filters
            % out must not mask the state underneath. The view re-renders
            % the topmost displayable status instead.
            S = statusMgr.Stack();
            view = statusMgr.view.RecordingView(S, ...
                ExcludeIdentifiers="noise:*");
            testCase.addTeardown(@() delete(view))

            S.addStatus("Running", Identifier="app:load", Message="loading");
            S.addStatus("Info", Identifier="noise:debug", Message="chatter");

            testCase.verifyEqual(view.RecordedStatuses.Message, ...
                ["loading"; "loading"])
        end

    end

end
