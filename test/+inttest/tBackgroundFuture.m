classdef tBackgroundFuture < matlab.unittest.TestCase
    % Integration tests for Stack.monitorFuture / Stack.runInBackground.
    % Uses backgroundPool, which is available without the Parallel
    % Computing Toolbox.

    methods (Test)

        function tMonitorFuturePushesRunningCancellableStatus(testCase)
            S = statusMgr.Stack();
            f = parfeval(backgroundPool, @() pause(0.5), 0);
            testCase.addTeardown(@() cancel(f));

            status = S.monitorFuture(f, Message="hello", PollPeriod=0.05);

            testCase.verifyEqual(S.CurrentStatus.Type, ...
                statusMgr.StatusType.RunningCancellable)
            testCase.verifyEqual(S.CurrentStatus.Message, "hello")
            testCase.verifyEqual(status.Data, f)
        end

        function tMonitorFutureCompletesStatusOnSuccess(testCase)
            S = statusMgr.Stack();
            f = parfeval(backgroundPool, @() 1 + 1, 1);
            testCase.addTeardown(@() cancel(f));

            status = S.monitorFuture(f, PollPeriod=0.05);

            wait(f);
            testCase.waitUntil(@() S.CurrentStatus.Type == statusMgr.StatusType.Idle, 3);

            testCase.verifyTrue(status.IsComplete)
            testCase.verifyEqual(S.CurrentStatus.Type, statusMgr.StatusType.Idle)
        end

        function tMonitorFuturePushesErrorOnFailure(testCase)
            S = statusMgr.Stack();
            f = parfeval(backgroundPool, @() error("test:err", "boom"), 0);
            testCase.addTeardown(@() cancel(f));

            S.monitorFuture(f, PollPeriod=0.05);

            testCase.waitUntil(@() S.CurrentStatus.Type == statusMgr.StatusType.Error, 3);

            testCase.verifyEqual(S.CurrentStatus.Type, statusMgr.StatusType.Error)
            testCase.verifyEqual(S.CurrentStatus.Identifier, "test:err")
        end

        function tCancellingStatusCancelsFuture(testCase)
            % Completing the status (e.g. via a StatusBar Cancel
            % button) propagates to the future via cancel().
            S = statusMgr.Stack();
            f = parfeval(backgroundPool, @() pause(60), 0);
            testCase.addTeardown(@() cancel(f));

            status = S.monitorFuture(f, PollPeriod=0.05);
            % The future is queued or already running by now — both
            % are pre-terminal states.
            testCase.assertTrue(ismember(string(f.State), ["queued", "running"]))

            status.complete();

            testCase.waitUntil(@() ismember(string(f.State), ["finished", "unavailable"]), 3);
            testCase.verifyTrue(ismember(string(f.State), ["finished", "unavailable"]))
        end

        function tProgressQueueNumericUpdatesValue(testCase)
            S = statusMgr.Stack();
            queue = parallel.pool.DataQueue;
            f = parfeval(backgroundPool, @sendNumeric, 0, queue);
            testCase.addTeardown(@() cancel(f));

            status = S.monitorFuture(f, ProgressQueue=queue, PollPeriod=0.05);

            wait(f);
            testCase.waitUntil(@() status.IsComplete, 3);

            testCase.verifyEqual(status.Value, 1.0)

            function sendNumeric(q)
                for i = 1:5
                    send(q, i / 5);
                    pause(0.02);
                end
            end
        end

        function tProgressQueueStructUpdatesBoth(testCase)
            S = statusMgr.Stack();
            queue = parallel.pool.DataQueue;
            f = parfeval(backgroundPool, @sendStruct, 0, queue);
            testCase.addTeardown(@() cancel(f));

            status = S.monitorFuture(f, ProgressQueue=queue, PollPeriod=0.05);

            wait(f);
            testCase.waitUntil(@() status.IsComplete, 3);

            testCase.verifyEqual(status.Message, "step 3 of 3")
            testCase.verifyEqual(status.Value, 1.0)

            function sendStruct(q)
                for i = 1:3
                    send(q, struct("Value", i/3, "Message", "step " + i + " of 3"));
                    pause(0.02);
                end
            end
        end

        function tProgressQueueUpdatesReachViews(testCase)
            % End to end through the DataQueue subscription: views must
            % be notified of each progress update, not just the Status.
            S = statusMgr.Stack();
            recorder = statusMgr.view.RecordingView(S);
            testCase.addTeardown(@() delete(recorder));
            queue = parallel.pool.DataQueue;
            % A local (not nested) worker function: a nested one would
            % carry the recorder and its listener to the worker.
            f = parfeval(backgroundPool, @sendProgressSteps, 0, queue);
            testCase.addTeardown(@() cancel(f));

            status = S.monitorFuture(f, ProgressQueue=queue, PollPeriod=0.05);

            wait(f);
            testCase.waitUntil(@() status.IsComplete, 3);

            testCase.verifyEqual(recorder.RecordedStatuses.Message(2:end), ...
                ["step 1 of 3"; "step 2 of 3"; "step 3 of 3"])
        end

        function tRunInBackgroundLaunchesAndMonitors(testCase)
            % runInBackground = parfeval + monitorFuture.
            S = statusMgr.Stack();

            [future, status] = S.runInBackground(@() 6 * 7, ...
                Message="answer", PollPeriod=0.05);
            testCase.addTeardown(@() cancel(future));

            % Check via the captured status — the future is fast and
            % may already be off the stack by the time we assert.
            testCase.assertEqual(status.Message, "answer")

            wait(future);
            testCase.waitUntil(@() status.IsComplete, 3);

            testCase.verifyEqual(fetchOutputs(future), 42)
            testCase.verifyEqual(S.CurrentStatus.Type, statusMgr.StatusType.Idle)
        end

        function tRunInBackgroundForwardsArgsAndProgressQueue(testCase)
            S = statusMgr.Stack();
            queue = parallel.pool.DataQueue;
            [future, status] = S.runInBackground(@addAndReport, ...
                Args={queue, 3, 4}, NumOutputs=1, PollPeriod=0.05, ...
                ProgressQueue=queue);
            testCase.addTeardown(@() cancel(future));

            % Wait for the progress message to actually land in the
            % status BEFORE waiting for completion. Once the future
            % finishes the poll timer marks status.IsComplete and tears
            % down monitoring, after which onFutureProgress early-returns
            % and any still-in-flight queue messages would be dropped.
            testCase.waitUntil(@() status.Message == "done", 3);

            wait(future);
            testCase.waitUntil(@() status.IsComplete, 3);

            testCase.verifyEqual(fetchOutputs(future), 7)
            testCase.verifyEqual(status.Message, "done")

            function out = addAndReport(q, a, b)
                % Two pauses bracket the send():
                % * Before — backgroundPool starts the worker almost
                %   immediately, so we need to wait until the calling
                %   side (monitorFuture) has registered afterEach on
                %   the queue. Otherwise the first send fires while
                %   nobody is listening and is dropped.
                % * After — give the message round-trip time to land
                %   before the future completes; if the future
                %   finishes first, the poll timer marks the status
                %   IsComplete and onFutureProgress drops the
                %   incoming update.
                pause(0.1);
                send(q, "done");
                pause(0.05);
                out = a + b;
            end
        end

        function tMonitorFutureDoesNotPinStack(testCase)
            % Clearing the user's Stack handle while a future is in
            % flight must let the stack be GC'd. The poll-timer /
            % afterEach closures previously captured `obj` strongly,
            % pinning the stack until the future ran to completion.
            S = statusMgr.Stack();
            queue = parallel.pool.DataQueue;
            f = parfeval(backgroundPool, @() pause(5), 0);
            testCase.addTeardown(@() cancel(f));

            S.monitorFuture(f, ProgressQueue=queue, PollPeriod=0.05);

            weakS = matlab.lang.WeakReference(S);
            clear S

            releasedHandle = weakS.Handle;
            testCase.verifyTrue( ...
                isempty(releasedHandle) || ~isvalid(releasedHandle), ...
                "monitorFuture closure is pinning the Stack — " + ...
                "see Stack.monitorFuture WeakReference usage.")
        end

        function tNonCancellableUsesRunningType(testCase)
            S = statusMgr.Stack();
            f = parfeval(backgroundPool, @() 1, 1);
            testCase.addTeardown(@() cancel(f));

            status = S.monitorFuture(f, Cancellable=false, PollPeriod=0.05);

            % Use the captured status — the trivial future is fast
            % and may be off the stack by the assertion. status.Type
            % is set at construction and isn't mutated by complete().
            testCase.verifyEqual(status.Type, statusMgr.StatusType.Running)
        end

    end

    methods (Access = protected)

        function waitUntil(testCase, conditionFcn, timeoutSec)
            % Helper: poll a condition until it's true or timeout
            % expires. Lets test bodies stay declarative.
            deadline = tic;
            while ~conditionFcn() && toc(deadline) < timeoutSec
                pause(0.05);
                drawnow;
            end
            testCase.verifyTrue(conditionFcn(), ...
                "Condition not met within " + timeoutSec + "s")
        end

    end

end

function sendProgressSteps(q)
    for i = 1:3
        send(q, "step " + i + " of 3");
        pause(0.02);
    end
end
