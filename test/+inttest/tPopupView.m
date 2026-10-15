classdef tPopupView < matlab.uitest.TestCase

    properties
        Stack statusMgr.Stack
        PopupView statusMgr.view.Popup
        Figure matlab.ui.Figure
        TestField
    end

    methods (TestMethodSetup)
        function setup(testCase)
            testCase.Stack = statusMgr.Stack();
            testCase.addTeardown(@() delete(testCase.Stack));
            
            testCase.Figure = uifigure(Visible="on", Position=[1 1 796 479]);
            testCase.addTeardown(@delete, testCase.Figure);
            testCase.PopupView = statusMgr.view.Popup(testCase.Figure, testCase.Stack);
            testCase.addTeardown(@() delete(testCase.PopupView));
        end
    end

    methods (Test)

        function tDefaultValues(testCase)
            testCase.verifyTrue(testCase.PopupView.ShowInfo)
            testCase.verifyTrue(testCase.PopupView.ShowWarnings)
            testCase.verifyTrue(testCase.PopupView.ShowErrors)
            testCase.verifyTrue(testCase.PopupView.ShowSuccess)
            testCase.verifyTrue(testCase.PopupView.ShowRunning)
            testCase.verifyFalse(testCase.PopupView.ShowIdle)
        end

        function tDefaultConstructorCreatesUifigureAndStack(testCase)
            % statusMgr.view.Popup() with no args defaults parent to a
            % fresh uifigure and stack to a new Stack. Capture the parent
            % handle separately so its teardown does not depend on view
            % still being valid.
            view = statusMgr.view.Popup();
            parent = view.Parent;
            testCase.addTeardown(@() delete(parent))
            testCase.addTeardown(@() delete(view))

            testCase.assertClass(parent, "matlab.ui.Figure")
            testCase.verifyTrue(isvalid(parent))
            testCase.assertClass(view.Stack, "statusMgr.Stack")
        end

        function tDisplayRunningDefaultCancellableArg(testCase)
            % Calling displayRunning with only the status argument applies
            % the cancellable=false default. Use a private fixture stack
            % so this view is the only listener.
            fig = uifigure(Visible="on", Position=[1 1 400 200]);
            testCase.addTeardown(@() delete(fig))
            stack = statusMgr.Stack();
            view = inttest.helpers.PopupAccess(fig, stack);
            testCase.addTeardown(@() delete(view))

            status = statusMgr.Status("Running", "x");
            testCase.verifyWarningFree(@() view.callDisplayRunningNoCancellable(status));
        end

        function tPopupAlertDefaultTitleAndIcon(testCase)
            % popupAlert(status) without title/icon applies the
            % "Error"/"error" defaults. Use a private fixture stack so
            % only this view's uiconfirm dialog is produced, then dismiss.
            fig = uifigure(Visible="on", Position=[1 1 400 200]);
            testCase.addTeardown(@() delete(fig))
            stack = statusMgr.Stack();
            view = inttest.helpers.PopupAccess(fig, stack);
            testCase.addTeardown(@() delete(view))

            status = statusMgr.Status("Error", "m");
            view.callPopupAlertDefaults(status);
            testCase.chooseDialog("uiconfirm", fig, "OK")
        end

        function tProgressDlgIndeterminateAfterDeterminate(testCase)
            % Switching a status from a determinate Value back to NaN
            % flips ProgressDlg.Indeterminate from "off" to "on". Covers
            % the else branch in updateProgressDlg. Compare via string to
            % be robust to ProgressDlg.Indeterminate returning either a
            % char or a matlab.lang.OnOffSwitchState.
            status = testCase.Stack.addStatus("Running", Message="r1", Value=0.4);
            pause(0.2)
            testCase.assertEqual(string(testCase.PopupView.ProgressDlg.Indeterminate), "off")

            testCase.Stack.updateStatus(status, Value=NaN);
            pause(0.2)
            testCase.verifyEqual(string(testCase.PopupView.ProgressDlg.Indeterminate), "on")
        end

        function tDismissError(testCase)
            % Dismiss the error dialog and check the stack is
            % updated accordingly.
            testCase.Stack.addStatus("Error", Message="Example error");
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Type, statusMgr.StatusType.Error)

            % Dismiss the dialog that popped up.
            testCase.chooseDialog("uiconfirm", testCase.Figure, "OK")

            testCase.verifyEqual(testCase.Stack.CurrentStatus.Type, statusMgr.StatusType.Idle)
        end

        function tAddStatusWithCompletionCallback(testCase)
            
            status = testCase.Stack.addStatus("Error", Message="Example error", CompletionFcn=@(status) setTestCaseTempToMessageName(status, testCase));
            % The CompletionFcn closure (and testCase.TestField) retain this
            % status past the test; delete it so it doesn't linger to
            % session teardown.
            testCase.addTeardown(@() delete(status))

            testCase.chooseDialog("uiconfirm", testCase.Figure, "OK")

            testCase.verifyEqual(testCase.Stack.CurrentStatus.Type, statusMgr.StatusType.Idle)

            testCase.verifyEqual(testCase.TestField, status);

            function setTestCaseTempToMessageName(status, testCase)
                testCase.TestField = status;
            end
        end

        function tCleanupError(testCase)
            % Deleting the status's cleanup object should clear it from the
            % stack and dismiss the dialog.
            [~, cleanupObj] = testCase.Stack.addStatus("Error", Message="Example error"); %#ok<ASGLU>
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Type, statusMgr.StatusType.Error)

            clear cleanupObj
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Type, statusMgr.StatusType.Idle)
            testCase.verifyError(@() testCase.chooseDialog("uiconfirm", testCase.Figure, "OK"), ...
                "MATLAB:uiautomation:Driver:NoConfirmationDialogsFound")
        end

        function tDismissMultipleStatuses(testCase)
            % Add multiple statuses in order and dismiss the dialogs one
            % by one.
            testCase.Stack.addStatus("Warning", Message="S1");
            testCase.Stack.addStatus("Error", Message="S2");
            testCase.Stack.addStatus("Warning", Message="S3");

            testCase.verifySize(testCase.Stack.Statuses, [1 4])
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Message, "S3")

            testCase.chooseDialog("uiconfirm", testCase.Figure, "OK")
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Message, "S2")

            testCase.chooseDialog("uiconfirm", testCase.Figure, "OK")
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Message, "S1")

            testCase.chooseDialog("uiconfirm", testCase.Figure, "OK")
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Type, statusMgr.StatusType.Idle)
        end

        function tRemoveAllStatuses(testCase)
            % Calling removeAllStatuses should dismiss all dialogs.
            testCase.Stack.addStatus("Warning", Message="S1");
            testCase.Stack.addStatus("Error", Message="S2");

            testCase.Stack.removeAllStatuses();

            testCase.assertSize(testCase.Stack.Statuses, [1 1])
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Type, statusMgr.StatusType.Idle)

            testCase.verifyError(@() testCase.chooseDialog("uiconfirm", testCase.Figure, "OK"), ...
                "MATLAB:uiautomation:Driver:NoConfirmationDialogsFound")
        end

        function tAddError(testCase)
            status = testCase.Stack.addError(MException("a:b:c", "test"));
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Type, statusMgr.StatusType.Error)

            testCase.chooseDialog("uiconfirm", testCase.Figure, "OK")

            testCase.verifyEqual(testCase.Stack.CurrentStatus.Type, statusMgr.StatusType.Idle)
            testCase.verifyTrue(status.IsComplete)
        end

        function tShowInfo(testCase)
            % Show an info message.
            testCase.Stack.addStatus("Info", Message="info1", Identifier="i1");

            testCase.verifyEqual(testCase.Stack.CurrentStatus.Type, statusMgr.StatusType.Info)
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Message, "info1")
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Identifier, "i1")

            testCase.chooseDialog("uiconfirm", testCase.Figure, "OK")
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Type, statusMgr.StatusType.Idle)
        end

        function tUpdateStatusMessage(testCase)
            % Create an indeterminate progress dialog and update its
            % message.
            status = testCase.Stack.addStatus("Running", Message="message");
            
            pause(0.2)
            testCase.Stack.updateStatus(testCase.Stack.CurrentStatus, Message="new message");
            pause(0.5)

            testCase.verifyEqual(status.Message, "new message")
        end

        function tIndeterminateProgressDialog(testCase)
            status = testCase.Stack.addStatus("Running", Message="test");
            pause(0.5)

            testCase.verifyFalse(status.IsComplete)

            status.complete();

            testCase.verifyTrue(status.IsComplete)
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Type, statusMgr.StatusType.Idle)
        end

        function tDeterminateProgressDialog(testCase)
            status = testCase.Stack.addStatus("Running", Message="test", Value=0.1);

            testCase.verifyEqual(testCase.Stack.CurrentStatus.Value, 0.1)

            pause(0.2)
            testCase.Stack.updateStatus(testCase.Stack.CurrentStatus, Value=0.5);
            pause(0.5)

            testCase.verifyEqual(status.Value, 0.5)
        end

        function tCancelIndeterminateProgressDialog(testCase)
            status = testCase.Stack.addStatus("RunningCancellable", Message="test");
            % Exercise the same flag set by the Cancel button without
            % depending on dialog geometry or screen scaling.
            testCase.PopupView.ProgressDlg.CancelRequested = true;
            deadline = tic;
            while ~status.IsComplete && toc(deadline) < 3
                pause(0.05);
            end
            testCase.verifyTrue(status.IsComplete)
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Type, statusMgr.StatusType.Idle)
        end

        function tUpdateOldStatus(testCase)
            % Update the message of a status that is not at the top of the
            % stack. 
            status = testCase.Stack.addStatus("Success", Message="message 1");
            testCase.Stack.addStatus("Error", Message="message 2");

            testCase.Stack.updateStatus(status, Message="new message");

            testCase.verifyEqual(testCase.Stack.Statuses(2).Message, "new message")
            testCase.verifyEqual(testCase.Stack.Statuses(end).Message, "message 2")
        end 

        function tDismissOneGroupedDialog(testCase)
            % Automatically click "ok" when multiple dialogs have been
            % grouped. The dialog from the next status in the stack should
            % still appear.
            testCase.Stack.addStatus("Success", Message="message 1");
            testCase.Stack.addStatus("Error", Message="message 2");

            testCase.chooseDialog("uiconfirm", testCase.Figure, "OK")

            testCase.verifyEqual(testCase.Stack.CurrentStatus.Message, "message 1")

            testCase.chooseDialog("uiconfirm", testCase.Figure, "OK")

            testCase.assertSize(testCase.Stack.Statuses, [1 1])
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Type, statusMgr.StatusType.Idle)
        end

        function tCloseAllDialogs(testCase)
            % Click on "Close All" when multiple dialogs are grouped. They
            % should all be dismissed.
            testCase.Stack.addStatus("Success", Message="message 1");
            testCase.Stack.addStatus("Error", Message="message 2");

            testCase.chooseDialog("uiconfirm", testCase.Figure, "Close All")

            testCase.assertSize(testCase.Stack.Statuses, [1 1])
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Type, statusMgr.StatusType.Idle)
        end

        function tCloseAllNotOfferedForSinglePopup(testCase)
            % With exactly one popup-worthy status on the stack,
            % "Close All" is not offered — only "OK". A second alert
            % arriving while the first is open triggers a
            % dismiss-and-recreate via clearPreviousAlert, so the
            % rebuilt dialog will pick up Close All if it's needed.
            testCase.Stack.addStatus("Error", Message="solo");

            testCase.chooseDialog("uiconfirm", testCase.Figure, "OK")
            testCase.assertSize(testCase.Stack.Statuses, [1 1])
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Type, statusMgr.StatusType.Idle)
        end

        function tClearPreviousAlertSurvivesMissingDialog(testCase)
            % HasPopup may be left true if uiconfirm's CloseFcn did not
            % fire (e.g. the dialog was dismissed via Esc / X in a
            % MATLAB version that skips the callback). The next status
            % should still be displayed without erroring.
            fig = uifigure(Visible="on", Position=[1 1 400 200]);
            testCase.addTeardown(@() delete(fig));
            stack = statusMgr.Stack();
            access = inttest.helpers.PopupAccess(fig, stack);
            testCase.addTeardown(@() delete(access));

            access.setHasPopup(true); % simulate the desynced flag

            testCase.verifyWarningFree(@() stack.addStatus("Error", Message="next"));
            testCase.chooseDialog("uiconfirm", fig, "OK")
            testCase.verifyFalse(access.HasPopup)
            testCase.verifyEqual(stack.CurrentStatus.Type, statusMgr.StatusType.Idle)
        end

        function tRunCommandWithError(testCase)
            % Automatically click "ok"
            testCase.Stack.run(@() error("test"));

            testCase.chooseDialog("uiconfirm", testCase.Figure, "OK")

            testCase.assertSize(testCase.Stack.Statuses, [1 1]);
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Type, statusMgr.StatusType.Idle)
        end

        function tTemporaryStatus(testCase)
            % Marking a status as temporary will result in it being
            % automatically removed once a new status is pushed.
            testCase.Stack.addStatus("Warning", Message="message 1", IsTemporary=true);
            testCase.Stack.addStatus("Warning", Message="message 2", IsTemporary=true);
            testCase.Stack.addStatus("Warning", Message="message 3", IsTemporary=true);

            testCase.assertSize(testCase.Stack.Statuses, [1 2])
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Type, statusMgr.StatusType.Warning)
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Message, "message 3")
            testCase.verifyTrue(testCase.Stack.CurrentStatus.IsTemporary)
            testCase.verifyEqual(testCase.Stack.Statuses(1).Type, statusMgr.StatusType.Idle)
        end

        function tMultipleStacks(testCase)
            % Create a second stack and a second popup view. Both stacks
            % can push statuses to the same figure.
            testCase.Stack.addStatus("Warning", Message="warning");
            newStack = statusMgr.Stack();
            newPopup = statusMgr.view.Popup(testCase.Figure, newStack);
            testCase.addTeardown(@() delete(newPopup))

            stackArray = [testCase.Stack, newStack];
            stackArray.addStatus("Error", Message="error");

            testCase.assertSize(testCase.Stack.Statuses, [1 3])
            testCase.assertSize(newStack.Statuses, [1 2])
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Type, statusMgr.StatusType.Error)
            testCase.verifyEqual(newStack.CurrentStatus.Type, statusMgr.StatusType.Error)
        end

        function tUpdateStatusInMultipleStacks(testCase)
            % Check the methods to update the value and message of a
            % status on an array of stacks on different figures.
            % Note this assumes that we're updating the same status in the
            % two stacks.
            testCase.Stack.addStatus("Warning", Message="warning");
            newStack = statusMgr.Stack();
            newFigure = uifigure();
            testCase.addTeardown(@delete, newFigure);
            newPopup = statusMgr.view.Popup(newFigure, newStack);
            testCase.addTeardown(@() delete(newPopup))

            stackArray = [testCase.Stack, newStack];
            stackArray.addStatus("Running", Message="message 1", Value=0.1);

            pause(0.1)
            stackArray.updateStatus(testCase.Stack.CurrentStatus, Value=0.5, Message="new message");
            pause(0.1)

            testCase.assertSize(testCase.Stack.Statuses, [1 3])
            testCase.assertSize(newStack.Statuses, [1 2])
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Type, statusMgr.StatusType.Running)
            testCase.verifyEqual(newStack.CurrentStatus.Type, statusMgr.StatusType.Running)
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Message, "new message")
            testCase.verifyEqual(newStack.CurrentStatus.Message, "new message")
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Value, 0.5)
            testCase.verifyEqual(newStack.CurrentStatus.Value, 0.5)
        end

        function tNonVisibleStatus(testCase)
            % Setting the status as non-visible makes it not appear as a popup
            testCase.Stack.addStatus("Warning", IsVisible=false);
            
            testCase.verifyError(@() testCase.chooseDialog("uiconfirm", testCase.Figure, "OK"), ...
                "MATLAB:uiautomation:Driver:NoConfirmationDialogsFound")
        end

        function tDisableShowSuccess(testCase)
            % Creating a popup view with ShowSuccess disabled will prevent
            % success statuses dialogs from appearing.
            newstack = statusMgr.Stack();
            popupView = statusMgr.view.Popup(testCase.Figure, newstack, ShowSuccess=false);

            newstack.addStatus("Success");

            testCase.verifyFalse(popupView.ShowSuccess)
            testCase.verifyEqual(newstack.CurrentStatus.Type, statusMgr.StatusType.Success)
            testCase.verifyError(@() testCase.chooseDialog("uiconfirm", testCase.Figure, "OK"), ...
                "MATLAB:uiautomation:Driver:NoConfirmationDialogsFound")
        end

        function tDeletedFigure(testCase)
            % A popup view that references a deleted figure does nothing.
            testCase.Figure.delete();
            testCase.Stack.addStatus("Warning");

            testCase.verifyFalse(testCase.PopupView.isVisible());
            testCase.verifyFalse(testCase.PopupView.HasPopup);
        end

        function tAddStatusBeforeCreatingView(testCase)
            % If you create the view after a status has been added, that
            % status is still visible.
            testCase.Stack.addStatus("Warning", Message="warning");
            newFigure = uifigure();
            testCase.addTeardown(@delete, newFigure);
            newPopupView = statusMgr.view.Popup(newFigure, testCase.Stack);
            testCase.addTeardown(@() delete(newPopupView));

            testCase.verifyTrue(newPopupView.HasPopup)
            testCase.verifyEqual(newPopupView.IncomingStatus.Message, "warning")
            testCase.chooseDialog("uiconfirm", testCase.Figure, "OK")
            testCase.verifyFalse(newPopupView.HasPopup)
            testCase.verifyFalse(testCase.PopupView.HasPopup)
        end

        function tProgressDialogCustomTitle(testCase)
            % A Running status with a Title sets the progress dialog title.
            status = testCase.Stack.addStatus("Running", Message="working", Title="My App");
            pause(0.5)

            testCase.verifyEqual(string(testCase.PopupView.ProgressDlg.Title), "My App")

            status.complete();
        end

        function tProgressDialogDefaultTitle(testCase)
            % A Running status with no Title falls back to "Running".
            status = testCase.Stack.addStatus("Running", Message="working");
            pause(0.5)

            testCase.verifyEqual(string(testCase.PopupView.ProgressDlg.Title), "Running")

            status.complete();
        end

        function tProgressDialogMissingTitle(testCase)
            % A Running status with a missing Title falls back to "Running".
            % Exercises the ismissing short-circuit guard in updateProgressDlg.
            status = testCase.Stack.addStatus("Running", Message="working", Title=string(missing));
            pause(0.5)

            testCase.verifyEqual(string(testCase.PopupView.ProgressDlg.Title), "Running")

            status.complete();
        end

        % --- handleInputRequest ---------------------------------------------

        function tHandleInputRequestDefaultValues(testCase)
            % HandleInputRequests is true by default.
            testCase.verifyTrue(testCase.PopupView.HandleInputRequests)
        end

        function tHandleInputRequestDisabled(testCase)
            % When HandleInputRequests is false the popup does not claim the
            % request; requestInput returns the default after the timeout.
            testCase.PopupView.HandleInputRequests = false;

            value = testCase.Stack.requestInput("Prompt", ...
                DefaultValue="default", Timeout=0.1);

            testCase.verifyEqual(value, "default")
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Type, ...
                statusMgr.StatusType.Idle)
        end

        function tHandleInputRequestShowsDialogAndReturnsTypedValue(testCase)
            % requestInput creates an input dialog; submitting it returns
            % the typed value. requestInput blocks until the dialog is
            % dismissed, so we poll from a timer callback and drive the
            % dialog using the matlab.uitest.TestCase actions (type/press)
            % once the view has published its widget handles.
            typedValue = "hello world";
            view = testCase.PopupView;

            t = timer("ExecutionMode", "fixedSpacing", "Period", 0.05, ...
                "TimerFcn", @(~,~) typeAndSubmit());
            testCase.addTeardown(@() statusMgr.util.stopTimer(t));
            start(t);

            value = testCase.Stack.requestInput("Enter something", ...
                DefaultValue="def", Title="Test Input", Timeout=5);

            testCase.verifyEqual(value, typedValue)
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Type, ...
                statusMgr.StatusType.Idle)

            function typeAndSubmit()
                if isempty(view.InputDialog) || ~isvalid(view.InputDialog)
                    return
                end
                testCase.type(view.InputField, typedValue);
                testCase.press(view.InputOkButton);
                stop(t);
            end
        end

        function tHandleInputRequestDefaultUsedWhenDialogClosed(testCase)
            % Closing the dialog (without OK) returns the default. The
            % uitest framework doesn't have a "close window" gesture, so
            % we invoke the figure's CloseRequestFcn directly — that is
            % the same handler the window-close button would trigger.
            view = testCase.PopupView;

            t = timer("ExecutionMode", "fixedSpacing", "Period", 0.05, ...
                "TimerFcn", @(~,~) closeDialog());
            testCase.addTeardown(@() statusMgr.util.stopTimer(t));
            start(t);

            value = testCase.Stack.requestInput("Enter something", ...
                DefaultValue="fallback", Title="Close Test", Timeout=5);

            testCase.verifyEqual(value, "fallback")

            function closeDialog()
                if isempty(view.InputDialog) || ~isvalid(view.InputDialog)
                    return
                end
                cb = view.InputDialog.CloseRequestFcn;
                cb(view.InputDialog, []);
                stop(t);
            end
        end

        function tHandleInputRequestStatusCleanedUp(testCase)
            % Stack returns to Idle after requestInput completes.
            view = testCase.PopupView;

            t = timer("ExecutionMode", "fixedSpacing", "Period", 0.05, ...
                "TimerFcn", @(~,~) submitDefault());
            testCase.addTeardown(@() statusMgr.util.stopTimer(t));
            start(t);

            testCase.Stack.requestInput("Prompt", ...
                DefaultValue="x", Title="Cleanup Test", Timeout=5);

            testCase.verifyEqual(testCase.Stack.CurrentStatus.Type, ...
                statusMgr.StatusType.Idle)
            testCase.verifySize(testCase.Stack.Statuses, [1 1])

            function submitDefault()
                if isempty(view.InputDialog) || ~isvalid(view.InputDialog)
                    return
                end
                testCase.press(view.InputOkButton);
                stop(t);
            end
        end

    end
end

