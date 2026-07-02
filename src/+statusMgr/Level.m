classdef Level < int32
    %LEVEL Ordered importance of a Status, for per-view verbosity gating.
    %
    % Views display a status only when status.Level >= view.MinLevel
    % (composed with the view's identifier filters and Show* type flags —
    % see statusMgr.internal.view.StatusViewBase.shouldDisplay). One stack
    % can therefore drive views at different verbosities: a terse
    % CommandWindow at MinLevel="Warning" next to a FileLog recording
    % everything at the default MinLevel="Trace".
    %
    % Every Status gets a default Level derived from its StatusType (see
    % defaultFor); pass Level= to addStatus to override. Only the members
    % below are valid — the integer backing exists for ordering, not as a
    % raw-number escape hatch. Gaps between values leave room for future
    % members.

    enumeration
        Trace    (10)
        Debug    (20)
        Info     (30)
        Notice   (40)
        Warning  (50)
        Error    (60)
        Critical (70)
    end

    methods (Static)

        function lvl = defaultFor(type)
            %DEFAULTFOR Default Level for a StatusType.
            arguments
                type (1,1) statusMgr.StatusType
            end
            switch type
                case statusMgr.StatusType.Error
                    lvl = statusMgr.Level.Error;
                case statusMgr.StatusType.Warning
                    lvl = statusMgr.Level.Warning;
                case {statusMgr.StatusType.Running, ...
                        statusMgr.StatusType.RunningCancellable, ...
                        statusMgr.StatusType.Success, ...
                        statusMgr.StatusType.RequestingInput}
                    % Running is deliberately Notice rather than Info: it
                    % marks a key state in which the app may be
                    % unresponsive, so it must clear a "normal" verbosity
                    % threshold. (RequestingInput's level is nominal —
                    % input requests are control flow and are exempt from
                    % MinLevel gating in the views.)
                    lvl = statusMgr.Level.Notice;
                case statusMgr.StatusType.Info
                    lvl = statusMgr.Level.Info;
                otherwise
                    % Idle and the transitional input states.
                    lvl = statusMgr.Level.Trace;
            end
        end

    end

end
