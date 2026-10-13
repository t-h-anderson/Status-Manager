classdef tStatusLifecycle < matlab.uitest.TestCase
    properties (TestParameter)
        clearGroup = struct(Named=@() statusMgr.util.StatusManager.clear("retained"), ...
            All=@() statusMgr.util.StatusManager.clear())
        addFiltered = struct(Info=@(s) s.addStatus("Info"), ...
            Identifier=@(s) s.addStatus("Warning", Identifier="filtered"), ...
            Invisible=@(s) s.addStatus("Error", IsVisible=false))
    end
    methods (TestMethodSetup)
        function isolateRegistry(testCase)
            token = statusMgr.util.StatusManager.snapshot();
            testCase.addTeardown(@() statusMgr.util.StatusManager.restore(token));
            statusMgr.util.StatusManager.clear();
            testCase.addTeardown(@() statusMgr.util.StatusManager.shutdown());
        end
    end
    methods (Test)
        function tCompletionFailureStillRemovesStatus(testCase)
            stack = statusMgr.Stack();
            testCase.addTeardown(@() delete(stack));
            status = stack.addStatus("Running", CompletionFcn=@(~) error("test:completion", "failed"));
            testCase.verifyError(@() status.complete(), "test:completion");
            testCase.verifyEqual(stack.CurrentStatus.Type, statusMgr.StatusType.Idle);
            testCase.verifyWarningFree(@() status.complete());
        end

        function tRemovalFailureStillRefreshesView(testCase)
            stack = statusMgr.Stack();
            testCase.addTeardown(@() delete(stack));
            terminal = statusMgr.view.CommandWindow(stack);
            testCase.addTeardown(@() delete(terminal));
            evalc('status = stack.addStatus("Running", CompletionFcn=@(~) error("test:completion", "failed"));');
            runningTimer = terminal.RunningTimer;
            testCase.verifyError(@() stack.removeStatus(status), "test:completion");
            testCase.verifyFalse(isvalid(runningTimer));
            testCase.verifyEqual(stack.CurrentStatus.Type, statusMgr.StatusType.Idle);
        end

        function tArrayCompletionRunsAllCallbacksDespiteFailures(testCase)
            stack = statusMgr.Stack();
            testCase.addTeardown(@() delete(stack));
            first = stack.addStatus("Info", CompletionFcn=@(~) error("test:first", "first"));
            second = stack.addStatus("Info", CompletionFcn=@(~) error("test:second", "second"));
            cause = captureError(@() complete([first second]));
            testCase.verifyEqual(cause.identifier, 'test:first');
            testCase.assertNumElements(cause.cause, 1);
            testCase.verifyEqual(cause.cause{1}.identifier, 'test:second');
            testCase.verifyEqual(stack.CurrentStatus.Type, statusMgr.StatusType.Idle);
        end

        function tRemovalRefreshDoesNotRepeatDiagnostics(testCase)
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            stack = statusMgr.Stack();
            testCase.addTeardown(@() delete(stack));
            recorder = statusMgr.view.RecordingView(stack);
            testCase.addTeardown(@() delete(recorder));
            log = statusMgr.view.FileLog(stack, LogFolder=folder.Folder, LogFilename="events.jsonl", Format="json-lines", ShowRunning=false);
            testCase.addTeardown(@() delete(log));
            terminal = statusMgr.view.CommandWindow(stack, ShowRunning=false);
            testCase.addTeardown(@() delete(terminal));
            output = evalc('stack.run(@publish);');
            testCase.verifyEqual(string(output), "Warning: repeated" + newline + "Warning: repeated" + newline);
            testCase.verifyEqual(recorder.RecordedStatuses.Type, ["Running"; "Warning"; "Warning"]);
            testCase.verifyEqual(numel(readlines(fullfile(folder.Folder, "events.jsonl"), EmptyLineRule="skip")), 2);
            function publish()
                statusMgr.util.StatusManager.warning("test:warning", "repeated");
                statusMgr.util.StatusManager.warning("test:warning", "repeated");
            end
        end

        function tNestedRunnersKeepAuthoredErrorOnce(testCase)
            stack = statusMgr.Stack();
            testCase.addTeardown(@() delete(stack));
            recorder = statusMgr.view.RecordingView(stack);
            testCase.addTeardown(@() delete(recorder));
            stack.run(@() stack.run(@publish));
            testCase.verifyEqual(recorder.RecordedStatuses.Type, ["Running"; "Running"; "Error"]);
            function publish()
                statusMgr.util.StatusManager.reportError(MException("test:authored", "authored error"));
            end
        end

        function tTerminalProgressSurvivesRemovalBeneathIt(testCase)
            stack = statusMgr.Stack();
            testCase.addTeardown(@() delete(stack));
            terminal = statusMgr.view.CommandWindow(stack);
            testCase.addTeardown(@() delete(terminal));
            underlying = stack.addStatus("Info", Message="underneath", Silent=true);
            output = evalc('running = stack.addStatus("Running", Message="working");');
            testCase.verifySubstring(output, "working" + newline);
            timer = terminal.RunningTimer;
            stack.removeStatus(underlying);
            testCase.verifyTrue(isvalid(timer));
            testCase.verifyEqual(timer.Running, 'on');
            running.complete();
            testCase.verifyFalse(isvalid(timer));
        end

        function tRestorationRefreshAndExplicitUpdateAreDistinct(testCase)
            stack = statusMgr.Stack();
            testCase.addTeardown(@() delete(stack));
            recorder = statusMgr.view.RecordingView(stack);
            testCase.addTeardown(@() delete(recorder));
            changes = strings(1,0);
            observer = addlistener(stack, "StatusUpdated", @capture);
            testCase.addTeardown(@() delete(observer));
            first = stack.addStatus("Warning", Message="first");
            second = stack.addStatus("Warning", Message="second");
            stack.updateStatus(first, Message="updated beneath second");
            stack.removeStatus(second);
            stack.updateStatus(first, Message="updated beneath second");
            testCase.verifyEqual(changes, ["Added", "Added", "Updated", "Refresh", "Updated"]);
            testCase.verifyEqual(recorder.RecordedStatuses.Message, ...
                ["first"; "second"; "updated beneath second"; "updated beneath second"]);
            testCase.verifyEqual(stack.CurrentStatus, first);
            function capture(~, event)
                changes(end+1) = event.Change;
            end
        end

        function tRunCanReportFailureAfterAppCloses(testCase)
            fallback = statusMgr.util.StatusManager.make();
            stack = statusMgr.Stack();
            output = evalc('stack.run(@closeAndFail);');
            testCase.verifyEmpty(output);
            testCase.verifyEqual(fallback.CurrentStatus.Identifier, "test:status:closed");
            function closeAndFail()
                delete(stack);
                error("test:status:closed", "Failure after closing.");
            end
        end

        function tRunPublishesSuccessOnceAfterCompletingProgress(testCase)
            stack = statusMgr.Stack();
            testCase.addTeardown(@() delete(stack));
            recorder = statusMgr.view.RecordingView(stack);
            testCase.addTeardown(@() delete(recorder));
            output = evalc('value = stack.run(@() 42, Message="Working", SuccessMessage="Done", SuccessIsTemporary=false);');
            testCase.verifyEmpty(output);
            testCase.verifyEqual(value, 42);
            testCase.verifyEqual(recorder.RecordedStatuses.Type, ["Running"; "Success"]);
            testCase.verifyFalse(any([stack.Statuses.Type] == statusMgr.StatusType.Running));
        end

        function tRunPublishesFailureOnceWithoutSuccess(testCase)
            stack = statusMgr.Stack();
            testCase.addTeardown(@() delete(stack));
            recorder = statusMgr.view.RecordingView(stack);
            testCase.addTeardown(@() delete(recorder));
            output = evalc('stack.run(@fail, SuccessMessage="Must not appear");');
            testCase.verifyEmpty(output);
            testCase.verifyEqual(recorder.RecordedStatuses.Type, ["Running"; "Error"]);
            testCase.verifyEqual(stack.CurrentStatus.Identifier, "test:status:failed");
            function fail()
                error("test:status:failed", "Failure.");
            end
        end

        function tRunPreservesNativeWarningAlongsideFailure(testCase)
            stack = statusMgr.Stack();
            testCase.addTeardown(@() delete(stack));
            recorder = statusMgr.view.RecordingView(stack);
            testCase.addTeardown(@() delete(recorder));
            output = evalc('stack.run(@fail);');
            testCase.verifyEmpty(output);
            testCase.verifyEqual(recorder.RecordedStatuses.Type, ["Running"; "Warning"; "Error"]);
            function fail()
                warning("test:status:warning", "Before failure.");
                error("test:status:failed", "Failure.");
            end
        end

        function tCancellableRunCompletesItsOwnStatus(testCase)
            stack = statusMgr.Stack();
            testCase.addTeardown(@() delete(stack));
            status = stack.runCancellable(@(status) status, Message="Work");
            testCase.verifyTrue(status.IsComplete);
            testCase.verifyEqual(stack.CurrentStatus.Type, statusMgr.StatusType.Idle);
        end

        function tFailureAfterClosingStackUsesDefaultLogger(testCase)
            fallback = statusMgr.util.StatusManager.make();
            stack = statusMgr.Stack();
            output = evalc('stack.invoke(@closeAndFail);');
            testCase.verifyEmpty(output);
            testCase.verifyEqual(fallback.CurrentStatus.Identifier, "eLumina:test:closed");
            function closeAndFail()
                delete(stack);
                error("eLumina:test:closed", "Failed after closing the app.");
            end
        end

        function tRunRoutesWarningsAndPreservesThrowingContract(testCase)
            stack = statusMgr.Stack();
            testCase.addTeardown(@() delete(stack));
            view = statusMgr.view.RecordingView(stack);
            testCase.addTeardown(@() delete(view));
            testCase.verifyError(@() stack.run(@fail, CatchErrors=false), "eLumina:test:failure");
            testCase.verifyEqual(view.RecordedStatuses.Identifier(end), "eLumina:test:beforeFailure");
            testCase.verifyNotEqual(statusMgr.util.StatusManager.currentStack(), stack);
            function fail()
                statusMgr.util.StatusManager.warning("eLumina:test:beforeFailure", "logged before throwing");
                error("eLumina:test:failure", "failure");
            end
        end

        function tLibraryWarningsUseScopedLogger(testCase)
            stack = statusMgr.Stack();
            testCase.addTeardown(@() delete(stack));
            view = statusMgr.view.RecordingView(stack);
            testCase.addTeardown(@() delete(view));
            route = statusMgr.util.StatusManager.withStack(stack); %#ok<NASGU>
            output = evalc('issueWarnings();');
            testCase.verifyEmpty(output);
            testCase.verifyEqual(view.RecordedStatuses.Identifier, ...
                ["eLumina:test:first"; "eLumina:test:second"]);
            testCase.verifyEqual(view.RecordedStatuses.Message, ...
                ["100% complete: C:\temp\file"; "Value: 17"]);
            function issueWarnings()
                statusMgr.util.StatusManager.warning("eLumina:test:first", "100% complete: C:\temp\file");
                statusMgr.util.StatusManager.warning("eLumina:test:second", "Value: %d", 17);
            end
        end

        function tNestedRoutesRestoreAfterFailure(testCase)
            first = statusMgr.Stack();
            second = statusMgr.Stack();
            testCase.addTeardown(@() delete(first));
            testCase.addTeardown(@() delete(second));
            outer = statusMgr.util.StatusManager.withStack(first); %#ok<NASGU>
            testCase.verifyError(@nested, "eLumina:test:failure");
            testCase.verifyEqual(statusMgr.util.StatusManager.currentStack(), first);
            function nested()
                inner = statusMgr.util.StatusManager.withStack(second); %#ok<NASGU>
                testCase.verifyEqual(statusMgr.util.StatusManager.currentStack(), second);
                error("eLumina:test:failure", "failure");
            end
        end

        function tCallbackReportsWarningsAndErrorOnce(testCase)
            stack = statusMgr.Stack();
            testCase.addTeardown(@() delete(stack));
            view = statusMgr.view.RecordingView(stack);
            testCase.addTeardown(@() delete(view));
            cause = MException("eLumina:test:failure", "callback failed");
            output = evalc('stack.invoke(@callback);');
            testCase.verifyEmpty(output);
            testCase.verifyEqual(view.RecordedStatuses.Identifier, ...
                ["eLumina:test:logged"; "eLumina:test:native"; "eLumina:test:failure"]);
            testCase.verifyEqual(stack.CurrentStatus.Data.identifier, cause.identifier);
            testCase.verifyEqual(stack.CurrentStatus.Data.message, cause.message);
            testCase.verifyNotEmpty(stack.CurrentStatus.Data.stack);
            function callback()
                statusMgr.util.StatusManager.warning("eLumina:test:logged", "logged");
                warning("eLumina:test:native", "native dependency warning");
                throw(cause);
            end
        end

        function tCommandViewDoesNotReissueWarnings(testCase)
            stack = statusMgr.Stack();
            testCase.addTeardown(@() delete(stack));
            view = statusMgr.view.CommandWindow(stack, ShowRunning=false);
            testCase.addTeardown(@() delete(view));
            recorder = statusMgr.view.RecordingView(stack);
            testCase.addTeardown(@() delete(recorder));
            output = evalc('stack.invoke(@callback);');
            testCase.verifyEqual(string(output), "Warning: 100% complete: C:\temp\file" + newline);
            testCase.verifyEqual(height(recorder.RecordedStatuses), 1);
            function callback()
                statusMgr.util.StatusManager.warning("eLumina:test:logged", "100% complete: C:\temp\file");
            end
        end

        function tNestedNativeCaptureDoesNotDuplicate(testCase)
            stack = statusMgr.Stack();
            testCase.addTeardown(@() delete(stack));
            view = statusMgr.view.RecordingView(stack);
            testCase.addTeardown(@() delete(view));
            output = evalc('stack.invoke(@() stack.invoke(@callback));');
            testCase.verifyEmpty(output);
            testCase.verifyEqual(height(view.RecordedStatuses), 1);
            testCase.verifyEqual(view.RecordedStatuses.Identifier, "eLumina:test:native");
            function callback()
                warning("eLumina:test:native", "native dependency warning");
            end
        end

        function tDefaultRouteRespectsConfiguredViews(testCase)
            stack = statusMgr.util.StatusManager.make();
            output = evalc('statusMgr.util.StatusManager.reportError(MException("eLumina:test:failure", "failure"));');
            testCase.verifyEmpty(output);
            testCase.verifyEqual(stack.CurrentStatus.Identifier, "eLumina:test:failure");
        end

        function tShutdownReleasesRegistryWithoutRecreatingIt(testCase)
            stack = statusMgr.util.StatusManager.make("shutdown");
            statusMgr.util.StatusManager.shutdown();
            testCase.verifyFalse(isvalid(stack));
            token = statusMgr.util.StatusManager.snapshot();
            testCase.verifyFalse(token.hasInstance);
            testCase.verifyWarningFree(@() statusMgr.util.StatusManager.shutdown());
        end


        function tRegistryClearReleasesOwnedResources(testCase)
            stack = statusMgr.util.StatusManager.make("lifecycle", EnableCommandWindow=true);
            views = statusMgr.util.StatusManager.get("lifecycle", Type="Views");
            statusMgr.util.StatusManager.clear("lifecycle");
            testCase.verifyTrue(isvalid(stack));
            testCase.verifyFalse(any(isvalid(views)));
            delete(stack);
        end

        function tStacksHaveIndependentIdleStatuses(testCase)
            first = statusMgr.Stack();
            second = statusMgr.Stack();
            testCase.addTeardown(@() delete(first));
            testCase.addTeardown(@() delete(second));
            testCase.verifyNotEqual(first.CurrentStatus, second.CurrentStatus);
            first.CurrentStatus.updateMessage("first only");
            testCase.verifyEqual(second.CurrentStatus.Message, "");
        end

        function tRemovingStatusNotifiesOnce(testCase)
            stack = statusMgr.Stack();
            testCase.addTeardown(@() delete(stack));
            status = stack.addStatus("Info", Message="temporary");
            count = 0;
            listener = addlistener(stack,"StatusUpdated",@countUpdate);
            testCase.addTeardown(@() delete(listener));
            stack.removeStatus(status);
            testCase.verifyEqual(count, 1);
            testCase.verifyTrue(status.IsComplete);
            function countUpdate(~,~)
                count = count + 1;
            end
        end

        function tRebindingViewDetachesPreviousStack(testCase)
            first = statusMgr.Stack();
            second = statusMgr.Stack();
            testCase.addTeardown(@() delete(first));
            testCase.addTeardown(@() delete(second));
            view = statusMgr.view.RecordingView(first);
            testCase.addTeardown(@() delete(view));
            view.setStack(second);
            first.addStatus("Info", Message="old stack");
            testCase.verifyEmpty(view.RecordedStatuses);
            second.addStatus("Info", Message="new stack");
            testCase.verifyEqual(height(view.RecordedStatuses), 1);
        end


        function tSharedStatusSurvivesOneStackClosing(testCase)
            first = statusMgr.Stack();
            second = statusMgr.Stack();
            testCase.addTeardown(@() delete(second));
            status = first.addStatus("Info", Message="shared");
            second.add(status);
            delete(first);
            testCase.verifyTrue(isvalid(status));
            status.complete();
            testCase.verifyEqual(second.CurrentStatus.Type, statusMgr.StatusType.Idle);
        end

        function tHiddenStatusesPreservePopupAndProgress(testCase)
            figure = uifigure();
            testCase.addTeardown(@() delete(figure));
            stack = statusMgr.Stack();
            testCase.addTeardown(@() delete(stack));
            popup = statusMgr.view.Popup(figure, stack, ShowInfo=false, ...
                ExcludeIdentifiers="test:hidden");
            testCase.addTeardown(@() delete(popup));
            warningStatus = stack.addStatus("Warning", Message="visible warning");
            stack.addStatus("Info", Message="hidden info");
            testCase.verifyTrue(popup.HasPopup);
            warningStatus.complete();
            testCase.verifyFalse(popup.HasPopup);
            running = stack.addStatus("Running", Message="working");
            dialog = popup.ProgressDlg;
            stack.addStatus("Warning", Identifier="test:hidden", Message="filtered warning");
            testCase.verifyTrue(isvalid(dialog));
            stack.addStatus("Error", IsVisible=false, Message="invisible error");
            testCase.verifyTrue(isvalid(dialog));
            running.complete();
            testCase.verifyFalse(isvalid(dialog));
        end

        function tHiddenFigureStillCleansCompletedProgress(testCase)
            figure = uifigure();
            testCase.addTeardown(@() delete(figure));
            stack = statusMgr.Stack();
            testCase.addTeardown(@() delete(stack));
            popup = statusMgr.view.Popup(figure, stack);
            testCase.addTeardown(@() delete(popup));
            running = stack.addStatus("Running", Message="working");
            dialog = popup.ProgressDlg;
            figure.Visible = "off";
            running.complete();
            testCase.verifyFalse(isvalid(dialog));
        end

        function tPopupClosesProgressBeneathHiddenInfo(testCase)
            figure = uifigure();
            testCase.addTeardown(@() delete(figure));
            stack = statusMgr.Stack();
            testCase.addTeardown(@() delete(stack));
            popup = statusMgr.view.Popup(figure, stack, ShowInfo=false);
            testCase.addTeardown(@() delete(popup));
            running = stack.addStatus("Running", Message="working");
            dialog = popup.ProgressDlg;
            testCase.assertTrue(isvalid(dialog));
            stack.addStatus("Info", Message="hidden");
            testCase.verifyTrue(isvalid(dialog));
            running.complete();
            testCase.verifyFalse(isvalid(dialog));
        end

        function tUpdateBeneathTopDoesNotRedrawPopup(testCase)
            figure = uifigure();
            testCase.addTeardown(@() delete(figure));
            stack = statusMgr.Stack();
            testCase.addTeardown(@() delete(stack));
            popup = statusMgr.view.Popup(figure, stack);
            testCase.addTeardown(@() delete(popup));
            running = stack.addStatus("Running", Message="working");
            warningStatus = stack.addStatus("Warning", Message="on top");
            testCase.assertEqual(popup.PreviousStatus, running);
            stack.updateStatus(running, Value=0.3);
            testCase.verifyEqual(popup.IncomingStatus, warningStatus);
            testCase.verifyEqual(popup.PreviousStatus, running);
            testCase.verifyTrue(popup.HasPopup);
        end

        function tTerminalUpdateBeneathKeepsRunningIndicator(testCase)
            stack = statusMgr.Stack();
            testCase.addTeardown(@() delete(stack));
            terminal = statusMgr.view.CommandWindow(stack);
            testCase.addTeardown(@() delete(terminal));
            evalc('outer = stack.addStatus("Running", Message="outer");');
            evalc('inner = stack.addStatus("Running", Message="inner");');
            timer = terminal.RunningTimer;
            output = evalc('stack.updateStatus(outer, Message="outer progress");');
            testCase.verifySubstring(output, "outer progress");
            testCase.verifyTrue(isvalid(timer));
            testCase.verifyEqual(terminal.IncomingStatus, inner);
            evalc('inner.complete();');
            testCase.verifyFalse(isvalid(timer));
            testCase.verifyTrue(isempty(terminal.RunningTimer) || ~isvalid(terminal.RunningTimer));
            evalc('outer.complete();');
        end

        function tBorrowedViewSurvivesRemovalAndClear(testCase)
            stack = statusMgr.util.StatusManager.make("borrowed");
            other = statusMgr.Stack();
            testCase.addTeardown(@() delete(other));
            view = statusMgr.view.RecordingView(other);
            testCase.addTeardown(@() delete(view));
            statusMgr.util.StatusManager.addView("borrowed", view);
            statusMgr.util.StatusManager.removeView("borrowed", 1);
            testCase.verifyTrue(isvalid(view));
            cleanup = statusMgr.util.StatusManager.addViewScoped("borrowed", view); %#ok<NASGU>
            statusMgr.util.StatusManager.clear("borrowed");
            clear cleanup
            testCase.verifyTrue(isvalid(view));
            testCase.verifyTrue(isvalid(stack));
            delete(stack);
        end

        function tSnapshotRestoreKeepsStackHandles(testCase)
            stack = statusMgr.util.StatusManager.make("kept", EnableCommandWindow=true);
            views = statusMgr.util.StatusManager.get("kept", Type="Views");
            token = statusMgr.util.StatusManager.snapshot();
            statusMgr.util.StatusManager.clear();
            testCase.verifyTrue(isvalid(stack));
            statusMgr.util.StatusManager.restore(token);
            testCase.verifyEqual(statusMgr.util.StatusManager.get("kept"), stack);
            testCase.verifyTrue(all(isvalid(views)));
        end

        function tSharedStatusRemovalFailureCleansAllStacks(testCase)
            first = statusMgr.Stack();
            second = statusMgr.Stack();
            testCase.addTeardown(@() delete(first));
            testCase.addTeardown(@() delete(second));
            shared = first.addStatus("Info", CompletionFcn=@(~) error("test:completion", "failed"));
            second.add(shared);
            testCase.verifyError(@() removeStatus([first second], shared), "test:completion");
            testCase.verifyEqual(first.CurrentStatus.Type, statusMgr.StatusType.Idle);
            testCase.verifyEqual(second.CurrentStatus.Type, statusMgr.StatusType.Idle);
        end

        function tRemovalFailureStillCleansLaterStacks(testCase)
            first = statusMgr.Stack();
            second = statusMgr.Stack();
            testCase.addTeardown(@() delete(first));
            testCase.addTeardown(@() delete(second));
            failing = first.addStatus("Info", CompletionFcn=@(~) error("test:completion", "failed"));
            other = second.addStatus("Info", Message="other");
            testCase.verifyError(@() removeStatus([first second], [failing other]), "test:completion");
            testCase.verifyTrue(other.IsComplete);
            testCase.verifyEqual(second.CurrentStatus.Type, statusMgr.StatusType.Idle);
        end

        function tRunCompletionFailureFollowsCatchErrors(testCase)
            stack = inttest.helpers.FailingRemovalStack();
            testCase.addTeardown(@() delete(stack));
            recorder = statusMgr.view.RecordingView(stack);
            testCase.addTeardown(@() delete(recorder));
            testCase.verifyError(@() stack.run(@() 42, CatchErrors=false, ...
                SuccessMessage="Must not appear"), "test:completion");
            evalc('stack.run(@() 42, SuccessMessage="Must not appear");');
            testCase.verifyEqual(recorder.RecordedStatuses.Type, ["Running"; "Running"; "Error"]);
            testCase.verifyEqual(stack.CurrentStatus.Identifier, "test:completion");
        end

        function tRunKeepsWorkAndCompletionFailures(testCase)
            stack = inttest.helpers.FailingRemovalStack();
            testCase.addTeardown(@() delete(stack));
            cause = captureError(@() stack.run(@fail, CatchErrors=false));
            testCase.verifyEqual(cause.identifier, 'test:work');
            testCase.assertNumElements(cause.cause, 1);
            testCase.verifyEqual(cause.cause{1}.identifier, 'test:completion');
            function fail()
                error("test:work", "Work failed.");
            end
        end

        function tRunRejectsPositionalArguments(testCase)
            stack = statusMgr.Stack();
            testCase.addTeardown(@() delete(stack));
            testCase.verifyError(@() stack.run(@(x) x, 1), ?MException);
            testCase.verifyError(@() stack.runCancellable(@(~, x) x, 1), ?MException);
            testCase.verifyEqual(stack.run(@(varargin) numel(varargin), Args={"Message", "hello"}), 2);
        end

        function tShutdownPreservesAndDisconnectsBorrowedView(testCase)
            stack = statusMgr.util.StatusManager.make("borrowedShutdown");
            other = statusMgr.Stack();
            testCase.addTeardown(@() delete(other));
            view = statusMgr.view.RecordingView(stack);
            testCase.addTeardown(@() delete(view));
            cleanup = statusMgr.util.StatusManager.addViewScoped("borrowedShutdown", view); %#ok<NASGU>

            statusMgr.util.StatusManager.shutdown();
            clear cleanup

            testCase.verifyTrue(isvalid(view));
            testCase.verifyEmpty(view.Stack);
            testCase.verifyEmpty(view.StackListener);
            view.setStack(other);
            other.addStatus("Info", Message="reused");
            testCase.verifyEqual(view.RecordedStatuses.Message, "reused");
        end

        function tShutdownStopsBorrowedPopupWithoutDeletingIt(testCase)
            figure = uifigure();
            testCase.addTeardown(@() delete(figure));
            stack = statusMgr.util.StatusManager.make("borrowedPopup");
            popup = statusMgr.view.Popup(figure, stack);
            testCase.addTeardown(@() delete(popup));
            statusMgr.util.StatusManager.addView("borrowedPopup", popup);
            stack.addStatus("Running", Value=0.1);
            dialog = popup.ProgressDlg;
            timer = popup.CancelTimer;

            statusMgr.util.StatusManager.shutdown();

            testCase.verifyTrue(isvalid(popup));
            testCase.verifyTrue(isvalid(figure));
            testCase.verifyEmpty(popup.Stack);
            testCase.verifyFalse(isvalid(dialog));
            testCase.verifyFalse(isvalid(timer));
        end

        function tRetainedClearedGroupStopsLoggingImmediately(testCase, clearGroup)
            stack = statusMgr.util.StatusManager.make("retained", EnableCommandWindow=true);
            testCase.addTeardown(@() delete(stack));
            group = statusMgr.util.StatusManager.get("retained", Type="StatusManagerGroup");
            testCase.addTeardown(@() delete(group));
            view = group.Views;
            evalc('stack.addStatus("Running", Message="working");');
            timer = view.RunningTimer;

            clearGroup();

            testCase.verifyFalse(isvalid(timer));
            testCase.verifyEmpty(evalc('stack.addStatus("Info", Message="after clear");'));
            statusMgr.util.StatusManager.shutdown();
            testCase.verifyEmpty(evalc('stack.addStatus("Info", Message="after shutdown");'));
        end

        function tSnapshotRestoreReconnectsWithoutReplayingLog(testCase)
            stack = statusMgr.util.StatusManager.make("restoreLog");
            view = statusMgr.view.RecordingView(stack);
            testCase.addTeardown(@() delete(view));
            statusMgr.util.StatusManager.addView("restoreLog", view);
            stack.addStatus("Info", Message="before");
            token = statusMgr.util.StatusManager.snapshot();
            statusMgr.util.StatusManager.clear();
            stack.addStatus("Info", Message="while detached");

            statusMgr.util.StatusManager.restore(token);

            testCase.verifyEqual(view.Stack, stack);
            testCase.verifyEqual(view.RecordedStatuses.Message, "before");
            stack.addStatus("Info", Message="after");
            testCase.verifyEqual(view.RecordedStatuses.Message, ["before"; "after"]);
        end

        function tSnapshotRestoreRecreatesVisibleProgress(testCase)
            figure = uifigure();
            testCase.addTeardown(@() delete(figure));
            stack = statusMgr.util.StatusManager.make("restorePopup", PopupParent=figure);
            popup = statusMgr.util.StatusManager.get("restorePopup", Type="Views");
            running = stack.addStatus("Running", Value=0.1);
            dialog = popup.ProgressDlg;
            token = statusMgr.util.StatusManager.snapshot();
            statusMgr.util.StatusManager.clear();
            testCase.verifyFalse(isvalid(dialog));
            stack.updateStatus(running, Value=0.8);

            statusMgr.util.StatusManager.restore(token);

            testCase.verifyTrue(isvalid(popup.ProgressDlg));
            testCase.verifyEqual(popup.ProgressDlg.Value, 0.8);
            testCase.verifyEqual(popup.Stack, stack);
        end

        function tRestoreDoesNotDisturbUnchangedGroupDisplay(testCase)
            figure = uifigure();
            testCase.addTeardown(@() delete(figure));
            stack = statusMgr.util.StatusManager.make("unchanged", PopupParent=figure);
            popup = statusMgr.util.StatusManager.get("unchanged", Type="Views");
            stack.addStatus("Running", Value=0.4);
            dialog = popup.ProgressDlg;
            token = statusMgr.util.StatusManager.snapshot();
            statusMgr.util.StatusManager.make("temporary");

            statusMgr.util.StatusManager.restore(token);

            testCase.verifyTrue(isvalid(dialog));
            testCase.verifyEqual(popup.ProgressDlg, dialog);
            testCase.verifyEqual(dialog.Value, 0.4);
        end

        function tRestoreDisconnectsDiscardedRetainedGroup(testCase)
            token = statusMgr.util.StatusManager.snapshot();
            stack = statusMgr.util.StatusManager.make("discarded");
            testCase.addTeardown(@() delete(stack));
            group = statusMgr.util.StatusManager.get("discarded", Type="StatusManagerGroup");
            testCase.addTeardown(@() delete(group));
            view = statusMgr.view.RecordingView(stack);
            testCase.addTeardown(@() delete(view));
            group.addView(view);

            statusMgr.util.StatusManager.restore(token);

            stack.addStatus("Info", Message="discarded");
            testCase.verifyEmpty(view.RecordedStatuses);
            testCase.verifyEmpty(view.Stack);
        end

        function tRemovingBorrowedViewDisconnectsListener(testCase)
            group = statusMgr.util.StatusManagerGroup();
            testCase.addTeardown(@() delete(group));
            stack = group.Stack;
            testCase.addTeardown(@() delete(stack));
            view = statusMgr.view.RecordingView(stack);
            testCase.addTeardown(@() delete(view));
            group.addView(view);

            group.removeView(1);
            stack.addStatus("Info", Message="removed");

            testCase.verifyTrue(isvalid(view));
            testCase.verifyEmpty(view.Stack);
            testCase.verifyEmpty(view.RecordedStatuses);
        end

        function tDisplayedProgressUpdatesBeneathFilteredStatus(testCase, addFiltered)
            figure = uifigure();
            testCase.addTeardown(@() delete(figure));
            stack = statusMgr.Stack();
            testCase.addTeardown(@() delete(stack));
            popup = statusMgr.view.Popup(figure, stack, ShowInfo=false, ExcludeIdentifiers="filtered");
            testCase.addTeardown(@() delete(popup));
            running = stack.addStatus("Running", Message="working", Value=0.1);
            dialog = popup.ProgressDlg;
            addFiltered(stack);

            stack.updateStatus(running, Message="updated work", Value=0.8);

            testCase.verifyEqual(popup.ProgressDlg, dialog);
            testCase.verifyEqual(dialog.Value, 0.8);
            testCase.verifyEqual(string(dialog.Message), "updated work");
            testCase.verifyEqual(popup.IncomingStatus, running);
        end

        function tWorkerProgressUpdatesDisplayedStatusBeneathInfo(testCase)
            figure = uifigure();
            testCase.addTeardown(@() delete(figure));
            stack = statusMgr.Stack();
            testCase.addTeardown(@() delete(stack));
            popup = statusMgr.view.Popup(figure, stack, ShowInfo=false);
            testCase.addTeardown(@() delete(popup));
            recorder = statusMgr.view.RecordingView(stack);
            testCase.addTeardown(@() delete(recorder));
            running = stack.addStatus("Running", Value=0.1);
            dialog = popup.ProgressDlg;
            stack.addStatus("Info", Message="hidden");

            % Drive the callback the DataQueue subscription uses in production.
            statusMgr.internal.futureProgressRegistry("register", running.ID, stack, running);
            testCase.addTeardown(@() statusMgr.internal.futureProgressRegistry("unregister", running.ID));
            statusMgr.internal.onFutureProgress(running.ID, struct(Value=0.8, Message="worker update"));

            testCase.verifyEqual(popup.ProgressDlg, dialog);
            testCase.verifyEqual(dialog.Value, 0.8);
            testCase.verifyEqual(string(dialog.Message), "worker update");
            testCase.verifyEqual(recorder.RecordedStatuses.Message(end), "worker update");
        end
    end
end

function cause = captureError(action)
    cause = MException.empty(0,1);
    try
        action();
    catch cause
    end
end
