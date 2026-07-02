classdef tLevel < matlab.unittest.TestCase
    % Tests for statusMgr.Level and the Status/Stack Level plumbing.

    methods (Test)

        function tOrdering(testCase)
            % Levels are strictly ordered for MinLevel comparisons.
            import statusMgr.Level
            ladder = [Level.Trace, Level.Debug, Level.Info, ...
                Level.Notice, Level.Warning, Level.Error, Level.Critical];
            for i = 2:numel(ladder)
                testCase.verifyTrue(ladder(i) > ladder(i-1))
            end
        end

        function tDefaultForMapping(testCase)
            % The per-type default table. Running is deliberately Notice:
            % it marks a key state where the app may be unresponsive.
            import statusMgr.StatusType
            import statusMgr.Level
            testCase.verifyEqual(Level.defaultFor(StatusType.Error), Level.Error)
            testCase.verifyEqual(Level.defaultFor(StatusType.Warning), Level.Warning)
            testCase.verifyEqual(Level.defaultFor(StatusType.Running), Level.Notice)
            testCase.verifyEqual(Level.defaultFor(StatusType.RunningCancellable), Level.Notice)
            testCase.verifyEqual(Level.defaultFor(StatusType.Success), Level.Notice)
            testCase.verifyEqual(Level.defaultFor(StatusType.Info), Level.Info)
            testCase.verifyEqual(Level.defaultFor(StatusType.Idle), Level.Trace)
        end

        function tStatusDefaultsLevelFromType(testCase)
            testCase.verifyEqual(statusMgr.Status("Error").Level, ...
                statusMgr.Level.Error)
            testCase.verifyEqual(statusMgr.Status("Running").Level, ...
                statusMgr.Level.Notice)
            testCase.verifyEqual(statusMgr.Status().Level, ...
                statusMgr.Level.Trace)   % default Status is Idle
        end

        function tStatusLevelOverride(testCase)
            S = statusMgr.Status("Info", "m", Level="Critical");
            testCase.verifyEqual(S.Level, statusMgr.Level.Critical)
        end

        function tAddStatusLevelOverride(testCase)
            S = statusMgr.Stack();
            S.addStatus("Info", Message="m", Level=statusMgr.Level.Critical);
            testCase.verifyEqual(S.CurrentStatus.Level, statusMgr.Level.Critical)
        end

        function tAddErrorLevelOverride(testCase)
            S = statusMgr.Stack();
            S.addError(MException("a:b:c", "boom"), Level="Critical");
            testCase.verifyEqual(S.CurrentStatus.Level, statusMgr.Level.Critical)
        end

        function tTableHasLevelColumn(testCase)
            % Status.table swapped the removed IsVisible column for Level
            % (schema stays 13 columns).
            tbl = statusMgr.Status("Running", "busy").table();
            testCase.verifySize(tbl, [1 13])
            testCase.verifyEqual(tbl.Level, "Notice")
            testCase.verifyFalse(ismember("IsVisible", tbl.Properties.VariableNames))
        end

    end

end
