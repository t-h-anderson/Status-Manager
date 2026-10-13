classdef tFileLog < matlab.uitest.TestCase

    properties
        Stack statusMgr.Stack
        FileLogView statusMgr.view.FileLog
        Folder
    end

    methods (TestMethodSetup)
        function setup(testCase)
            import matlab.unittest.fixtures.WorkingFolderFixture
            fx = testCase.applyFixture(WorkingFolderFixture);
            testCase.Folder = fx.Folder;
            testCase.Stack = statusMgr.Stack();
            testCase.FileLogView = statusMgr.view.FileLog(testCase.Stack, ...
                LogFolder=testCase.Folder);
        end
    end

    methods (Test)

        function tDefaultValues(testCase)
            testCase.verifyTrue(testCase.FileLogView.IncludeTimestamp)
            testCase.verifyTrue(testCase.FileLogView.IncludeUser)
            testCase.verifyTrue(testCase.FileLogView.IncludeIdentifier)
            testCase.verifyTrue(testCase.FileLogView.IncludeValue)
            testCase.verifyTrue(testCase.FileLogView.ShowInfo)
            testCase.verifyTrue(testCase.FileLogView.ShowWarnings)
            testCase.verifyTrue(testCase.FileLogView.ShowErrors)
            testCase.verifyTrue(testCase.FileLogView.ShowSuccess)
            testCase.verifyTrue(testCase.FileLogView.ShowRunning)
            testCase.verifyFalse(testCase.FileLogView.ShowIdle)
            testCase.verifyEqual(testCase.FileLogView.LogFolder, string(testCase.Folder))
        end

        function tDisplayInfo(testCase)
            import matlab.unittest.constraints.IsFile
            testCase.Stack.addStatus("Info", Message="s1");
            
            logfile = fullfile(testCase.FileLogView.LogFolder, testCase.FileLogView.LogFilename);
            testCase.assertThat(logfile, IsFile)
            lines = readlines(logfile);
            
            testCase.verifyTrue(endsWith(lines(1), "[Info] s1"))
            testCase.verifyEqual(lines(2), "")
        end

        function tDisplayIdleDisabledByDefault(testCase)
            import matlab.unittest.constraints.IsFile
            testCase.Stack.addStatus("Idle");
            logfile = fullfile(testCase.FileLogView.LogFolder, testCase.FileLogView.LogFilename);
            testCase.verifyThat(logfile, ~IsFile)
        end

        function tDoNotIncludeIdentifierOrTimestamp(testCase)
            import matlab.unittest.constraints.IsFile
            testCase.FileLogView.IncludeTimestamp = false;
            testCase.FileLogView.IncludeUser = false;
            testCase.FileLogView.IncludeIdentifier = false;
            testCase.FileLogView.IncludeValue = false;

            testCase.Stack.addStatus("Error", Message="s1", Identifier="a:b");
            testCase.Stack.addStatus("Running", Message="s2", Value=1);

            logfile = fullfile(testCase.FileLogView.LogFolder, testCase.FileLogView.LogFilename);
            testCase.assertThat(logfile, IsFile)
            lines = readlines(logfile);

            testCase.verifyEqual(lines(1), "[Error] s1")
            testCase.verifyEqual(lines(2), "[Running] s2")
            testCase.verifyEqual(lines(3), "")
        end

        function tIncludeUser(testCase)
            % User appears in the log line when IncludeUser is true (default).
            import matlab.unittest.constraints.IsFile
            testCase.FileLogView.IncludeTimestamp = false;

            testCase.Stack.addStatus("Info", Message="msg");

            logfile = fullfile(testCase.FileLogView.LogFolder, testCase.FileLogView.LogFilename);
            testCase.assertThat(logfile, IsFile)
            lines = readlines(logfile);

            expectedUser = string(getenv("USER"));
            if expectedUser == ""
                expectedUser = string(getenv("USERNAME"));
            end
            testCase.verifyTrue(startsWith(lines(1), "[" + expectedUser + "] "))
        end

        function tExcludeUser(testCase)
            % Setting IncludeUser=false omits the user field.
            import matlab.unittest.constraints.IsFile
            testCase.FileLogView.IncludeTimestamp = false;
            testCase.FileLogView.IncludeUser = false;

            testCase.Stack.addStatus("Info", Message="msg");

            logfile = fullfile(testCase.FileLogView.LogFolder, testCase.FileLogView.LogFilename);
            lines = readlines(logfile);

            testCase.verifyEqual(lines(1), "[Info] msg")
        end

        function tAddError(testCase)
            import matlab.unittest.constraints.IsFile
            testCase.Stack.addError(MException("a:b:c", "e1"));

            logfile = fullfile(testCase.FileLogView.LogFolder, testCase.FileLogView.LogFilename);
            testCase.assertThat(logfile, IsFile)
            lines = readlines(logfile);

            testCase.verifyTrue(endsWith(lines(1), "[Error] [a:b:c] e1"))
            testCase.verifyEqual(lines(2), "")
        end

        function tAddMultipleStatuses(testCase)
            import matlab.unittest.constraints.IsFile
            testCase.Stack.addStatus("Success", Message="s1");
            testCase.Stack.addStatus("Warning", Message="s2", Identifier="a:b");
            testCase.Stack.addStatus("Running", Message="s3", Value=2);

            logfile = fullfile(testCase.FileLogView.LogFolder, testCase.FileLogView.LogFilename);
            testCase.assertThat(logfile, IsFile)
            lines = readlines(logfile);

            testCase.verifyTrue(endsWith(lines(1), "[Success] s1"))
            testCase.verifyTrue(endsWith(lines(2), "[Warning] [a:b] s2"))
            testCase.verifyTrue(endsWith(lines(3), "[Running] [Value=2] s3"))
            testCase.verifyEqual(lines(4), "")
        end

        function tUpdateValueAndMessage(testCase)
            % Add a "running" status and update its value and message after
            % creation.
            import matlab.unittest.constraints.IsFile
            status = testCase.Stack.addStatus("Running", Message="s1", Value=1);

            testCase.Stack.updateStatus(status, Message="s2")
            testCase.Stack.updateStatus(status, Value=2)
            testCase.Stack.updateStatus(status, Value=3, Message="s3");

            logfile = fullfile(testCase.FileLogView.LogFolder, testCase.FileLogView.LogFilename);
            testCase.assertThat(logfile, IsFile)
            lines = readlines(logfile);

            testCase.verifyTrue(endsWith(lines(1), "[Running] [Value=1] s1"))
            testCase.verifyTrue(endsWith(lines(2), "[Running] [Value=1] s2"))
            testCase.verifyTrue(endsWith(lines(3), "[Running] [Value=2] s2"))
            testCase.verifyTrue(endsWith(lines(4), "[Running] [Value=3] s3"))
            testCase.verifyEqual(lines(5), "")
        end

        function tUpdateOldStatusValueAndMessage(testCase)
            % Update a status when there are more recent statuses.
            import matlab.unittest.constraints.IsFile
            testCase.Stack.addStatus("Info", Message="i1");
            status = testCase.Stack.addStatus("Running", Message="r1", Value=1);
            testCase.Stack.addStatus("Warning", Message="w1");
            testCase.Stack.addStatus("Error", Message="e1");

            testCase.Stack.updateStatus(status, Message="r2")

            logfile = fullfile(testCase.FileLogView.LogFolder, testCase.FileLogView.LogFilename);
            testCase.assertThat(logfile, IsFile)
            lines = readlines(logfile);

            testCase.verifyTrue(endsWith(lines(1), "[Info] i1"))
            testCase.verifyTrue(endsWith(lines(2), "[Running] [Value=1] r1"))
            testCase.verifyTrue(endsWith(lines(3), "[Warning] w1"))
            testCase.verifyTrue(endsWith(lines(4), "[Error] e1"))
            testCase.verifyTrue(endsWith(lines(5), "[Running] [Value=1] r2"))
            testCase.verifyEqual(lines(6), "")
        end

        function tReuseExistingLogFile(testCase)
            import matlab.unittest.constraints.IsFile
            testCase.Stack.addStatus("Error", Message="e1", Data={1,2});
            testCase.Stack.addStatus("Success", Message="s1");

            % Create new stack and new file log and point it to the same
            % log file.
            newStack = statusMgr.Stack();
            newFileLogView = statusMgr.view.FileLog(newStack, ...
                LogFolder=testCase.Folder, LogFilename=testCase.FileLogView.LogFilename);
            testCase.addTeardown(@() delete(newFileLogView))

            newStack.addStatus("Info", Message="i1");

            logfile = fullfile(testCase.FileLogView.LogFolder, testCase.FileLogView.LogFilename);
            testCase.assertThat(logfile, IsFile)
            lines = readlines(logfile);

            testCase.verifyTrue(endsWith(lines(1), "[Error] e1"))
            testCase.verifyTrue(endsWith(lines(2), "[Success] s1"))
            testCase.verifyEqual(lines(3), "")
            testCase.verifyTrue(endsWith(lines(4), "[Info] i1"))
            testCase.verifyEqual(lines(5), "")
        end

        function tNonVisibleStatus(testCase)
            % A status with IsVisible=false is not written to the log file.
            import matlab.unittest.constraints.IsFile
            testCase.Stack.addStatus("Warning", Message="hidden", IsVisible=false);
            logfile = fullfile(testCase.FileLogView.LogFolder, testCase.FileLogView.LogFilename);
            testCase.verifyThat(logfile, ~IsFile)
        end

        function tSuppressedIdentifier(testCase)
            % A status whose identifier is suppressed on the stack is not
            % written to the log file.
            import matlab.unittest.constraints.IsFile
            testCase.Stack.suppressIdentifier("my:id");
            testCase.Stack.addStatus("Warning", Identifier="my:id", Message="suppressed");
            logfile = fullfile(testCase.FileLogView.LogFolder, testCase.FileLogView.LogFilename);
            testCase.verifyThat(logfile, ~IsFile)
        end

        function tDisplayIdle(testCase)
            import matlab.unittest.constraints.IsFile
            newFileLogView = statusMgr.view.FileLog(testCase.Stack, ...
                LogFilename="test.txt", ShowIdle=true);
            testCase.addTeardown(@() delete(newFileLogView))

            testCase.Stack.addStatus("Idle", Message="i1");

            logfile = fullfile(newFileLogView.LogFolder, "test.txt");
            testCase.assertThat(logfile, IsFile)
            lines = readlines(logfile);

            testCase.verifyTrue(endsWith(lines(1), "[Idle] i1"))
            testCase.verifyEqual(lines(2), "")
        end

        function tJsonLinesFormatProducesParseableRecords(testCase)
            % Format="json-lines" emits one JSON object per line.
            import matlab.unittest.constraints.IsFile
            view = statusMgr.view.FileLog(testCase.Stack, ...
                LogFolder=testCase.Folder, ...
                LogFilename="json.log", ...
                Format="json-lines");
            testCase.addTeardown(@() delete(view))

            testCase.Stack.addStatus("Info", Identifier="a:b", ...
                Message="hello", Value=0.5);
            testCase.Stack.addStatus("Warning", Message="oops");

            logfile = fullfile(testCase.Folder, "json.log");
            testCase.assertThat(logfile, IsFile)
            lines = readlines(logfile);
            % readlines may include a trailing empty line.
            lines = lines(strlength(lines) > 0);
            testCase.assertEqual(numel(lines), 2)

            r1 = jsondecode(lines(1));
            testCase.verifyEqual(string(r1.type), "Info")
            testCase.verifyEqual(string(r1.identifier), "a:b")
            testCase.verifyEqual(string(r1.message), "hello")
            testCase.verifyEqual(r1.value, 0.5)

            r2 = jsondecode(lines(2));
            testCase.verifyEqual(string(r2.type), "Warning")
            testCase.verifyEqual(string(r2.message), "oops")
        end

        function tJsonLinesDefaultFilenameUsesJsonlExtension(testCase)
            % When LogFilename is not given, Format="json-lines" picks
            % .jsonl so the file is recognised by jsonl tooling. The
            % default for "text" is still .txt.
            view = statusMgr.view.FileLog(testCase.Stack, ...
                LogFolder=testCase.Folder, ...
                Format="json-lines");
            testCase.addTeardown(@() delete(view))

            testCase.verifyTrue(endsWith(view.LogFilename, ".jsonl"), ...
                "Expected default json-lines filename to end with .jsonl, got " + view.LogFilename)
        end

        function tMaxBytesRotatesLog(testCase)
            % When a write would push the log past MaxBytes, the
            % current file is renamed with a "_1" suffix and a fresh
            % file starts. MaxBytes is intentionally tiny here so each
            % message triggers a rotation.
            import matlab.unittest.constraints.IsFile
            view = statusMgr.view.FileLog(testCase.Stack, ...
                LogFolder=testCase.Folder, ...
                LogFilename="rot.log", ...
                MaxBytes=10, ...
                IncludeTimestamp=false, IncludeUser=false);
            testCase.addTeardown(@() delete(view))

            testCase.Stack.addStatus("Info", Message="first message");
            testCase.Stack.addStatus("Info", Message="second message");
            testCase.Stack.addStatus("Info", Message="third message");

            current = fullfile(testCase.Folder, "rot.log");
            rotated1 = fullfile(testCase.Folder, "rot_1.log");
            rotated2 = fullfile(testCase.Folder, "rot_2.log");

            testCase.assertThat(current, IsFile)
            testCase.assertThat(rotated1, IsFile)
            testCase.assertThat(rotated2, IsFile)
        end

        function tMaxBytesInfNeverRotates(testCase)
            % Default MaxBytes=Inf keeps everything in one file.
            import matlab.unittest.constraints.IsFile
            view = statusMgr.view.FileLog(testCase.Stack, ...
                LogFolder=testCase.Folder, ...
                LogFilename="single.log");
            testCase.addTeardown(@() delete(view))

            for i = 1:5
                testCase.Stack.addStatus("Info", Message="m" + i);
            end

            single = fullfile(testCase.Folder, "single.log");
            rotated = fullfile(testCase.Folder, "single_1.log");
            testCase.assertThat(single, IsFile)
            testCase.verifyThat(rotated, ~IsFile)
        end

        function tHandleInputRequestLogsRequest(testCase)
            % FileLog cannot supply interactive input. Its handleInputRequest
            % logs the prompt and leaves the request unclaimed, so
            % requestInput times out and returns the default.
            import matlab.unittest.constraints.IsFile
            value = testCase.Stack.requestInput("Need input", ...
                DefaultValue="fallback", Timeout=0.1);

            testCase.verifyEqual(value, "fallback")

            logfile = fullfile(testCase.FileLogView.LogFolder, testCase.FileLogView.LogFilename);
            testCase.assertThat(logfile, IsFile)
            lines = strjoin(readlines(logfile), newline);
            testCase.verifyTrue(contains(lines, "Need input"))
        end

    end
end

