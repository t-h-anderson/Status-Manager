classdef (Abstract) StatusViewBase < ...
        statusMgr.internal.view.StatusViewInterface ...
        & matlab.mixin.SetGet
    %STATUSVIEWBASE Shared implementation for concrete status views.
    %
    % Provides the Stack/StackListener storage, the standardDisplay
    % dispatch loop, and the per-StatusType dispatcher methods that
    % gate on the Show* flags. Concrete views (Popup, CommandWindow,
    % FileLog) implement the abstract display methods declared at the
    % bottom of this file.

    properties (SetAccess = protected)
        Stack = statusMgr.Stack.empty(1,0)
        StackListener event.listener = event.listener.empty(1,0)
    end

    properties (SetAccess = protected)
        % Empty (not a default-constructed Status) so the class doesn't
        % hold a shared Status instance alive for the whole session, which
        % warns at teardown once the path is gone. standardDisplay assigns
        % the real status before any display method reads it.
        RefreshOnRemoval (1,1) logical = true
        IncomingStatus (1,:) statusMgr.Status {mustBeScalarOrEmpty} = statusMgr.Status.empty(1,0)
        PreviousStatus (1,:) statusMgr.Status {mustBeScalarOrEmpty} = statusMgr.Status.empty(1,0)
    end

    properties
        ShowInfo (1,1) logical = true
        ShowWarnings (1,1) logical = true
        ShowErrors (1,1) logical = true
        ShowRunning (1,1) logical = true
        ShowSuccess (1,1) logical = true
        ShowIdle (1,1) logical = false
        HandleInputRequests (1,1) logical = true

        % Per-view identifier filters (glob patterns). Complement the
        % stack-level SuppressedIdentifiers: stack-level hides for
        % everyone; these let one view be more permissive or more
        % restrictive than another.
        %   IncludeIdentifiers — if non-empty, only statuses whose
        %       Identifier matches at least one entry are displayed.
        %       Statuses with no Identifier are NOT shown.
        %   ExcludeIdentifiers — statuses whose Identifier matches
        %       any entry are not displayed.
        % Both lists accept globs (e.g. "myapp:net:*", "*timeout*").
        IncludeIdentifiers (1,:) string = string.empty(1,0)
        ExcludeIdentifiers (1,:) string = string.empty(1,0)
    end

    properties (Constant, Access = protected)
        AlertStatusTypes (1,:) statusMgr.StatusType = [...
            statusMgr.StatusType.Error, ...
            statusMgr.StatusType.Warning, ...
            statusMgr.StatusType.Success ...
            ]
    end

    methods

        function standardDisplay(obj, eventData)
            % Method for displaying the status supplied to the Stack manager
            arguments
                obj (1,1)
                eventData = []
            end

            if ~isvalid(obj)
                return
            end
            % Release completed resources even while the view is hidden.
            obj.cleanupCompletedStatus();

            if ~obj.RefreshOnRemoval && isa(eventData, "statusMgr.monitorable.StatusEventData") ...
                    && eventData.Change == "Refresh"
                return
            end

            if ~obj.isVisible()
                return
            end

            stack = obj.Stack;

            %Get the latest status
            latestStatus = stack.CurrentStatus;
            if ~obj.RefreshOnRemoval && isa(eventData, "statusMgr.monitorable.StatusEventData")
                latestStatus = eventData.Status;
            end

            if ~obj.shouldDisplayStatus(latestStatus)
                return
            end

            % Only replace the current display when its replacement will
            % actually be shown. Filtered statuses leave it intact.
            obj.beforeDisplay();
            latestType = latestStatus.Type;

            % Save the status in case this is needed for a view
            obj.PreviousStatus = obj.IncomingStatus;
            obj.IncomingStatus = latestStatus;

            % Display a pop-up
            switch latestType
                case statusMgr.StatusType.Info
                    obj.displayInfo_(latestStatus);
                case statusMgr.StatusType.Running
                    obj.displayRunning_(latestStatus, false);
                case statusMgr.StatusType.RunningCancellable
                    obj.displayRunning_(latestStatus, true);
                case statusMgr.StatusType.Error
                    obj.displayError_(latestStatus);
                case statusMgr.StatusType.Warning
                    obj.displayWarning_(latestStatus);
                case statusMgr.StatusType.Success
                    obj.displaySuccess_(latestStatus);
                case statusMgr.StatusType.Idle
                    obj.displayIdle_(latestStatus);
                case statusMgr.StatusType.RequestingInput
                    obj.handleInputRequest_(latestStatus);
                case {statusMgr.StatusType.AwaitingInput, statusMgr.StatusType.ValueSupplied}
                    % Intermediate input states — no display action needed.
                otherwise
                    error("Unknown status type");
            end % switch

        end % standardDisplay

        function delete(obj)
            delete(obj.StackListener);
        end

        function setStack(obj, stack)
            delete(obj.StackListener);
            updateStatusFn = @(src, event) obj.standardDisplay(event);
            obj.Stack = stack;
            obj.StackListener = listener(stack, "StatusUpdated", updateStatusFn);
        end

    end

    methods (Access = protected)

        function cleanupCompletedStatus(obj) %#ok<MANU>
            % Release resources belonging to completed statuses.
        end

        function tf = shouldDisplayStatus(obj, status)
            tf = status.IsVisible && obj.passesIdentifierFilters(status.Identifier);
            if ~tf
                return
            end
            switch status.Type
                case statusMgr.StatusType.Info
                    tf = obj.ShowInfo;
                case {statusMgr.StatusType.Running, statusMgr.StatusType.RunningCancellable}
                    tf = obj.ShowRunning;
                case statusMgr.StatusType.Error
                    tf = obj.ShowErrors;
                case statusMgr.StatusType.Warning
                    tf = obj.ShowWarnings;
                case statusMgr.StatusType.Success
                    tf = obj.ShowSuccess;
                case statusMgr.StatusType.Idle
                    tf = obj.ShowIdle;
                case statusMgr.StatusType.RequestingInput
                    tf = obj.HandleInputRequests;
                otherwise
                    tf = false;
            end
        end


        function tf = passesIdentifierFilters(obj, identifier)
            % Apply IncludeIdentifiers + ExcludeIdentifiers globs.
            % Identifier is the empty string for unidentified statuses.
            if ~isempty(obj.IncludeIdentifiers)
                tf = false;
                if identifier == ""
                    return
                end
                for inc = obj.IncludeIdentifiers
                    if statusMgr.util.globMatches(identifier, inc)
                        tf = true;
                        break
                    end
                end
                if ~tf
                    return
                end
            end
            for exc = obj.ExcludeIdentifiers
                if identifier ~= "" && statusMgr.util.globMatches(identifier, exc)
                    tf = false;
                    return
                end
            end
            tf = true;
        end

        function displayInfo_(obj, status)
            if obj.ShowInfo
                obj.displayInfo(status);
            end
        end

        function displayRunning_(obj, status, cancellable)
            if obj.ShowRunning
                obj.displayRunning(status, cancellable);
            end
        end

        function displayError_(obj, status)
            if obj.ShowErrors
                obj.displayError(status);
            end
        end

        function displayWarning_(obj, status)
            if obj.ShowWarnings
                obj.displayWarning(status);
            end
        end

        function displaySuccess_(obj, status)
            if obj.ShowSuccess
                obj.displaySuccess(status);
            end
        end

        function displayIdle_(obj, status)
            if obj.ShowIdle
                obj.displayIdle(status);
            end
        end

        function beforeDisplay(obj) %#ok<MANU>
            % Overload to do something before each display trigger
        end

        function handleInputRequest_(obj, status)
            if obj.HandleInputRequests
                obj.handleInputRequest(status);
            end
        end

    end

    methods (Abstract, Access = protected)

        displayInfo(obj, status)

        displayRunning(obj, status, cancellable)

        displayError(obj, status)

        displayWarning(obj, status)

        displaySuccess(obj, status)

        displayIdle(obj, status)

        % Called when a RequestingInput status is seen and HandleInputRequests
        % is true. Claim the request by calling status.transitionInputState
        % (AwaitingInput), collect input, then call transitionInputState
        % (ValueSupplied, value). Do nothing (no claim) to let it time out.
        handleInputRequest(obj, status)

    end

end
