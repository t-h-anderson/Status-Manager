classdef StatusEventData < event.EventData
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
