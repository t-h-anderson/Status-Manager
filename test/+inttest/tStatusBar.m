classdef tStatusBar < matlab.uitest.TestCase

    properties
        Stack statusMgr.Stack
        Figure matlab.ui.Figure
        Bar statusMgr.view.StatusBar
    end

    methods (TestMethodSetup)
        function setup(testCase)
            testCase.Stack = statusMgr.Stack();
            testCase.Figure = uifigure("Position", [100 100 600 200]);
            testCase.addTeardown(@() delete(testCase.Figure));
            testCase.Bar = statusMgr.view.StatusBar(testCase.Figure, testCase.Stack);
            testCase.addTeardown(@() delete(testCase.Bar));
        end
    end

    methods (Test)

        function tConstructorBuildsLayout(testCase)
            testCase.assertClass(testCase.Bar.Layout, "matlab.ui.container.GridLayout")
            testCase.verifyTrue(isvalid(testCase.Bar.Layout))
            testCase.verifyTrue(testCase.Bar.isVisible())
        end

        function tInfoStatusUpdatesMessage(testCase)
            testCase.Stack.addStatus("Info", Message="hello");
            testCase.verifyEqual(string(testCase.Bar.MessageLabel.Text), "hello")
            testCase.verifyEqual(string(testCase.Bar.ProgressIndicator.Visible), "off")
            testCase.verifyEqual(string(testCase.Bar.CancelButton.Visible), "off")
            testCase.verifyEqual(string(testCase.Bar.DetailsButton.Visible), "off")
            testCase.verifyEqual(string(testCase.Bar.OkButton.Visible), "off")
            testCase.verifyEqual(string(testCase.Bar.CloseAllButton.Visible), "off")
        end

        function tErrorStatusUsesErrorColor(testCase)
            testCase.Stack.addStatus("Error", Message="boom");
            testCase.verifyEqual(string(testCase.Bar.MessageLabel.Text), "boom")
            testCase.verifyEqual(testCase.Bar.MessageLabel.FontColor, ...
                testCase.Bar.ErrorColor)
        end

        function tWarningAndSuccessHaveDistinctColors(testCase)
            testCase.Stack.addStatus("Warning", Message="careful");
            warningColor = testCase.Bar.MessageLabel.FontColor;

            testCase.Stack.addStatus("Success", Message="done");
            successColor = testCase.Bar.MessageLabel.FontColor;

            testCase.verifyEqual(warningColor, testCase.Bar.WarningColor)
            testCase.verifyEqual(successColor, testCase.Bar.SuccessColor)
            testCase.verifyNotEqual(warningColor, successColor)
        end

        function tRunningShowsIndeterminateProgress(testCase)
            testCase.Stack.addStatus("Running", Message="loading");
            testCase.verifyEqual(string(testCase.Bar.ProgressIndicator.Visible), "on")
            testCase.verifyEqual(string(testCase.Bar.ProgressIndicator.Indeterminate), "on")
        end

        function tRunningWithValueShowsDeterminateProgress(testCase)
            testCase.Stack.addStatus("Running", Message="loading", Value=0.4);
            testCase.verifyEqual(string(testCase.Bar.ProgressIndicator.Visible), "on")
            testCase.verifyEqual(string(testCase.Bar.ProgressIndicator.Indeterminate), "off")
            testCase.verifyEqual(testCase.Bar.ProgressIndicator.Value, 0.4)
        end

        function tRunningCancellableShowsCancelButton(testCase)
            testCase.Stack.addStatus("RunningCancellable", Message="long task");
            testCase.verifyEqual(string(testCase.Bar.CancelButton.Visible), "on")
        end

        function tCancelButtonCompletesCurrentStatus(testCase)
            status = testCase.Stack.addStatus("RunningCancellable", Message="long task");
            testCase.assertFalse(status.IsComplete)
            testCase.assertEqual(string(testCase.Bar.CancelButton.Visible), "on")

            testCase.press(testCase.Bar.CancelButton);

            testCase.verifyTrue(status.IsComplete)
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Type, statusMgr.StatusType.Idle)
        end

        function tErrorShowsDetailsAndOkButtonsAndPopulatesPopout(testCase)
            % Error/Warning/Success show the Details button (which
            % toggles the Popout) and the OK button (which dismisses
            % the alert). The Popout content is populated with the
            % full Message wrapped in <pre>.
            testCase.Stack.addStatus("Error", ...
                Message="full error details here", ...
                MessageShort="oops");

            testCase.verifyEqual(string(testCase.Bar.MessageLabel.Text), "oops")
            testCase.verifyEqual(string(testCase.Bar.DetailsButton.Visible), "on")
            testCase.verifyEqual(string(testCase.Bar.OkButton.Visible), "on")
            testCase.verifyEqual(string(testCase.Bar.CloseAllButton.Visible), "off")
            testCase.verifyTrue(contains( ...
                string(testCase.Bar.PopoutText.HTMLSource), ...
                "full error details here"))
        end

        function tWarningShowsOkButton(testCase)
            testCase.Stack.addStatus("Warning", Message="be careful");
            testCase.verifyEqual(string(testCase.Bar.OkButton.Visible), "on")
        end

        function tSuccessShowsOkButton(testCase)
            testCase.Stack.addStatus("Success", Message="all done");
            testCase.verifyEqual(string(testCase.Bar.OkButton.Visible), "on")
        end

        function tOkButtonClearsTheStatus(testCase)
            % Clicking OK completes the status, removing it from the
            % stack and reverting to the previous state (Idle here).
            status = testCase.Stack.addStatus("Error", Message="boom");
            testCase.assertFalse(status.IsComplete)
            testCase.assertEqual(string(testCase.Bar.OkButton.Visible), "on")

            testCase.press(testCase.Bar.OkButton);

            testCase.verifyTrue(status.IsComplete)
            testCase.verifyEqual(testCase.Stack.CurrentStatus.Type, statusMgr.StatusType.Idle)
        end

        function tDetailsButtonHiddenForNonAlertTypes(testCase)
            % Info / Running don't have Details to show, so the
            % button is hidden — the popout has no UI affordance to
            % open it.
            testCase.Stack.addStatus("Info", Message="just info");
            testCase.verifyEqual(string(testCase.Bar.DetailsButton.Visible), "off")

            testCase.Stack.addStatus("Running", Message="working");
            testCase.verifyEqual(string(testCase.Bar.DetailsButton.Visible), "off")
        end

        function tPopoutHasExplicitSize(testCase)
            % The popout has an explicit Position so its size is
            % predictable regardless of content. Default is 400x200;
            % constructor accepts a PopoutSize override.
            testCase.verifyEqual(testCase.Bar.Popout.Position(3:4), [400 200])

            % Capture the parent in a local — teardowns run LIFO and
            % we'd otherwise read customBar.Parent after customBar
            % itself had been deleted.
            customParent = uifigure();
            testCase.addTeardown(@() delete(customParent));
            customBar = statusMgr.view.StatusBar(customParent, testCase.Stack, ...
                PopoutSize=[600 300]);
            testCase.addTeardown(@() delete(customBar));
            testCase.verifyEqual(customBar.Popout.Position(3:4), [600 300])
        end

        function tDismissingAlertClosesOpenPopout(testCase)
            % If the user opened the popout and then clicks OK to
            % dismiss the alert, the popout shouldn't linger after
            % the alert it was describing is gone.
            testCase.Stack.addStatus("Error", Message="boom");
            % drawnow forces the figure to render so Popout.Controller
            % is initialised — without it Controller is a
            % GraphicsPlaceholder and open() errors.
            drawnow;
            testCase.Bar.Popout.open();
            % IsOpen is updated by PopoutController via an async
            % client round-trip, so poll rather than asserting
            % synchronously.
            inttest.tStatusBar.waitForPopoutState(testCase.Bar.Popout, true);
            testCase.assertTrue(testCase.Bar.Popout.IsOpen)

            testCase.press(testCase.Bar.OkButton);

            inttest.tStatusBar.waitForPopoutState(testCase.Bar.Popout, false);
            testCase.verifyFalse(testCase.Bar.Popout.IsOpen)
        end

        function tPopoutContentIsFullMessage(testCase)
            % The Popout shows the full status.Message even when the
            % bar's MessageLabel is showing the short version. The
            % full text is wrapped in <pre> for whitespace/newline
            % preservation, hence the contains() check.
            testCase.Stack.addStatus("Error", ...
                Message="long detail text", MessageShort="short");

            testCase.assertEqual(string(testCase.Bar.MessageLabel.Text), "short")
            testCase.assertTrue(contains( ...
                string(testCase.Bar.PopoutText.HTMLSource), "long detail text"))

            % drawnow so Popout.Controller is initialised before
            % open() is called.
            drawnow;
            testCase.Bar.Popout.open();
            inttest.tStatusBar.waitForPopoutState(testCase.Bar.Popout, true);
            testCase.verifyTrue(testCase.Bar.Popout.IsOpen)

            testCase.Bar.Popout.close();
            inttest.tStatusBar.waitForPopoutState(testCase.Bar.Popout, false);
            testCase.verifyFalse(testCase.Bar.Popout.IsOpen)
        end

        function tMultipleAlertsShowsCloseAllAndCount(testCase)
            % With more than one alert on the stack, the bar shows
            % the Close All button, suffixes the message with the
            % count, and the popout body contains every alert.
            testCase.Stack.addStatus("Error", ...
                Message="first error full", MessageShort="err1");
            testCase.Stack.addStatus("Warning", ...
                Message="warning detail", MessageShort="warn1");
            testCase.Stack.addStatus("Error", ...
                Message="second error full", MessageShort="err2");

            testCase.verifyEqual(string(testCase.Bar.CloseAllButton.Visible), "on")
            testCase.verifyEqual(string(testCase.Bar.MessageLabel.Text), ...
                "err2 (3 alerts)")

            html = string(testCase.Bar.PopoutText.HTMLSource);
            testCase.verifyTrue(contains(html, "first error full"))
            testCase.verifyTrue(contains(html, "warning detail"))
            testCase.verifyTrue(contains(html, "second error full"))
        end

        function tPopoutHtmlEscapesAlertText(testCase)
            % Message / MessageShort come from arbitrary user code
            % and must not be interpreted as HTML when rendered into
            % the popout — otherwise a `<` or `&` in an error message
            % would silently corrupt the layout.
            testCase.Stack.addStatus("Error", ...
                Message="x < y && y > 0", MessageShort="bad");

            html = string(testCase.Bar.PopoutText.HTMLSource);
            testCase.verifyTrue(contains(html, "x &lt; y &amp;&amp; y &gt; 0"))
            testCase.verifyFalse(contains(html, "x < y && y > 0"))
        end

        function tSingleAlertHidesCloseAll(testCase)
            % With exactly one alert, Close All is not offered (OK
            % alone is sufficient).
            testCase.Stack.addStatus("Error", Message="only one");
            testCase.verifyEqual(string(testCase.Bar.CloseAllButton.Visible), "off")
        end

        function tCloseAllButtonRemovesAllAlertsButLeavesRunning(testCase)
            % "Close All" dismisses every Error/Warning/Success but
            % does not touch Running statuses — those represent
            % in-flight work that the user almost certainly does not
            % want killed by clicking a button labelled "Close All".
            running = testCase.Stack.addStatus("Running", Message="working");
            err1 = testCase.Stack.addStatus("Error", Message="boom1");
            err2 = testCase.Stack.addStatus("Error", Message="boom2");
            testCase.assertEqual(string(testCase.Bar.CloseAllButton.Visible), "on")

            testCase.press(testCase.Bar.CloseAllButton);

            testCase.verifyTrue(err1.IsComplete)
            testCase.verifyTrue(err2.IsComplete)
            testCase.verifyFalse(running.IsComplete)
            % Stack should now have just Idle + the Running.
            currentTypes = [testCase.Stack.Statuses.Type];
            testCase.verifyTrue(any(currentTypes == statusMgr.StatusType.Running))
            testCase.verifyFalse(any(ismember(currentTypes, ...
                [statusMgr.StatusType.Error, statusMgr.StatusType.Warning, ...
                 statusMgr.StatusType.Success])))
        end

        function tIdleClearsTheBar(testCase)
            testCase.Stack.addStatus("Info", Message="something");
            testCase.assertEqual(string(testCase.Bar.MessageLabel.Text), "something")

            testCase.Stack.removeAllStatuses();

            testCase.verifyEqual(string(testCase.Bar.MessageLabel.Text), "")
        end

        function tDoesNotClaimRequestingInput(testCase)
            % The bar shows the prompt but does not transition to
            % AwaitingInput, so requestInput times out and falls back
            % to the default. Use a short Timeout so the test is fast.
            value = testCase.Stack.requestInput("Enter your name", ...
                DefaultValue="anonymous", Timeout=0.1);

            testCase.verifyEqual(value, "anonymous")
        end

        function tDeleteRemovesLayout(testCase)
            bar = statusMgr.view.StatusBar(testCase.Figure, testCase.Stack);
            layout = bar.Layout;

            delete(bar);

            testCase.verifyFalse(isvalid(layout))
        end

        function tClearsWhenNothingDisplayable(testCase)
            % With MinLevel raised, dismissing the only displayable
            % status leaves nothing the bar can show (Idle is Trace),
            % so clearDisplay blanks the bar instead of leaving the
            % last alert on screen.
            testCase.Bar.MinLevel = "Warning";
            status = testCase.Stack.addStatus("Error", ...
                Message="boom", MessageShort="boom");
            testCase.assertEqual(string(testCase.Bar.MessageLabel.Text), "boom")

            testCase.Stack.removeStatus(status);

            testCase.verifyEqual(string(testCase.Bar.MessageLabel.Text), "")
        end

    end

    methods (Static, Access = private)

        function waitForPopoutState(popout, target)
            % Poll until Popout.IsOpen reaches target (or 1 s elapses).
            % IsOpen is set by the PopoutController via an async
            % client round-trip, so it's not reliably true/false at
            % the instant open()/close() returns.
            deadline = tic;
            while popout.IsOpen ~= target && toc(deadline) < 1
                drawnow;
                pause(0.05);
            end
        end

    end

end
