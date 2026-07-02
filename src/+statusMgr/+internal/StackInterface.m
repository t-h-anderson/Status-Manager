classdef (Abstract) StackInterface < handle

    properties (Abstract, SetAccess = protected)
        Statuses(1,:) statusMgr.Status
        StatusListeners (1,:) event.listener
        StackMonitorableListeners (1,:) event.listener
    end

    properties (Abstract, Hidden)
        ID (1,1) string
    end

    properties (Abstract, Dependent)
        CurrentStatus statusMgr.Status
    end

    events (NotifyAccess = protected)
        StatusUpdated
    end

    methods (Abstract)
        
        % Adding
        [status, cleanupObj] = addStatus(objs, type, nvp)

        [newStatus, cleanupObj] = add(obj, status, nvp)

        [newStatus, cleanupObj] = addError(obj, err)

        % Updating
        updateStatus(obj, status, nvp)

        % Removal
        removeStatus(objs, status)

        removeLastStatus(obj)

        removeAllStatuses(obj)

        % Monitoring
        monitor(obj, monitorable)

        run(obj, fcnHandle, nvp)

        % User input
        value = requestInput(obj, prompt, nvp)

        % Util
        tbl = table(obj)
    end

end
