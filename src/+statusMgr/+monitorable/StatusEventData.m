classdef StatusEventData < event.EventData
    %STATUSEVENTDATA Payload of a Stack's StatusUpdated event.
    %
    %   Change    Raised by                        Status
    %   "Added"   addStatus, add                   the new status
    %   "Updated" updateStatus, worker progress    the updated status (may
    %                                              be beneath the top)
    %   "Refresh" removeStatus, completion         the new top of the stack
    %
    % Log views record Added and Updated events; display views redraw from
    % the top of the stack and treat Refresh as a cue to do so.

    properties
        Status (1,1) statusMgr.Status
        Change (1,1) string {mustBeMember(Change, ["Added", "Updated", "Refresh"])} = "Added"
    end

    methods
        function data = StatusEventData(status, change)
            arguments
                status (1,1) statusMgr.Status
                change (1,1) string = "Added"
            end
            data.Status = status;
            data.Change = change;
        end
    end

end
