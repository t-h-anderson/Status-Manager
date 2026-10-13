classdef (Abstract) StatusViewBase < ...
        statusMgr.internal.view.StatusViewInterface ...
        & matlab.mixin.SetGet
    %STATUSVIEWBASE Shared implementation for concrete status views.
    %
    % Provides the Stack/StackListener storage, the standardDisplay
    % dispatch loop, and the Show*/identifier gate (shouldDisplayStatus)
    % applied before any display is replaced. Concrete views (Popup,
    % CommandWindow, FileLog, ...) implement the abstract display methods
    % declared at the bottom of this file.
    %
    % Display model (set RefreshOnRemoval before calling setStack):
    %   true  - display views show the top of the stack and redraw when a
    %           status is removed. Updates beneath the top are ignored,
    %           unless a filtered status on top hides the one on screen.
    %   false - log views record every Added/Updated event, including
    %           updates beneath the top, and ignore Refresh events.
    %
    % Optional protected hooks:
    %   beforeDisplay           - a new status is about to replace the display
    %   cleanupCompletedStatus  - every event, even while hidden; release
    %                             resources of completed statuses
    %   clearDisplay            - disconnected or rebound; release all active
    %                             displays without deleting the view
    %   displayBackgroundUpdate - log views: a status beneath the top changed
    %   updateDisplayedStatus   - display views: the status on screen changed
    %                             while a filtered status is on top
    %
    % setStack([]) disconnects the view without deleting it. Binding to a
    % stack shows its current status (display views) without replaying
    % history (log views).

    properties (SetAccess = protected)
        Stack = statusMgr.Stack.empty(1,0)
        StackListener event.listener = event.listener.empty(1,0)
    end

    properties (SetAccess = protected)
        % true for display views, false for log views (see class help).
        RefreshOnRemoval (1,1) logical = true
        % Empty (not a default-constructed Status) so the class doesn't
        % hold a shared Status instance alive for the whole session, which
        % warns at teardown once the path is gone. standardDisplay assigns
        % the real status before any display method reads it.
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

            if isempty(obj.Stack) || ~isvalid(obj.Stack) || ~obj.isVisible()
                return
            end

            stack = obj.Stack;

            %Get the latest status
            latestStatus = stack.CurrentStatus;
            isStatusEvent = isa(eventData, "statusMgr.monitorable.StatusEventData");
            if isStatusEvent && eventData.Change == "Updated" ...
                    && eventData.Status.ID ~= latestStatus.ID
                % An explicit update beneath the top of the stack. Log
                % views record it without disturbing the status they are
                % tracking; views showing the top have nothing new to show.
                if ~obj.RefreshOnRemoval && obj.shouldDisplayStatus(eventData.Status)
                    obj.displayBackgroundUpdate(eventData.Status);
                elseif obj.RefreshOnRemoval && ~isempty(obj.IncomingStatus) ...
                        && isvalid(obj.IncomingStatus) ...
                        && obj.IncomingStatus.ID == eventData.Status.ID ...
                        && obj.shouldDisplayStatus(eventData.Status)
                    % A filtered status can be on top while this view still
                    % displays the status being updated. Keep its resources.
                    obj.updateDisplayedStatus(eventData.Status);
                end
                return
            end
            if ~obj.RefreshOnRemoval && isStatusEvent
                latestStatus = eventData.Status;
            end

            if ~obj.shouldDisplayStatus(latestStatus)
                return
            end

            % Only replace the current display when its replacement will
            % actually be shown. Filtered statuses leave it intact.
            obj.beforeDisplay();

            % Save the status in case this is needed for a view
            obj.PreviousStatus = obj.IncomingStatus;
            obj.IncomingStatus = latestStatus;

            obj.dispatchDisplay(latestStatus);

        end % standardDisplay

        function delete(obj)
            delete(obj.StackListener);
        end

        function setStack(obj, stack)
            % An empty stack disconnects the view without deleting it.
            if isequal(obj.Stack, stack) && ~isempty(obj.StackListener) ...
                    && all(isvalid(obj.StackListener))
                return
            end
            delete(obj.StackListener);
            obj.StackListener = event.listener.empty(1,0);
            obj.clearDisplay();
            obj.IncomingStatus = statusMgr.Status.empty(1,0);
            obj.PreviousStatus = statusMgr.Status.empty(1,0);
            obj.Stack = stack;
            if ~isempty(stack)
                updateStatusFn = @(src, event) obj.standardDisplay(event);
                obj.StackListener = listener(stack, "StatusUpdated", updateStatusFn);
                % Restore UI state on reattachment without replaying log entries.
                obj.standardDisplay(statusMgr.monitorable.StatusEventData(stack.CurrentStatus, "Refresh"));
            end
        end

    end

    methods (Access = protected)

        function clearDisplay(obj) %#ok<MANU>
            % Release active resources when detached or rebound.
        end

        function updateDisplayedStatus(obj, status)
            obj.dispatchDisplay(status);
        end

        function displayBackgroundUpdate(obj, status)
            % Display an update to a status beneath the top of the stack.
            % Overload when a display has side effects tied to the current
            % status (e.g. progress indicators). Input requests are only
            % handled when they reach the top of the stack.
            if status.Type ~= statusMgr.StatusType.RequestingInput
                obj.dispatchDisplay(status);
            end
        end

        function dispatchDisplay(obj, status)
            % Callers gate on shouldDisplayStatus (which applies the Show*
            % flags) before reaching here.
            switch status.Type
                case statusMgr.StatusType.Info
                    obj.displayInfo(status);
                case statusMgr.StatusType.Running
                    obj.displayRunning(status, false);
                case statusMgr.StatusType.RunningCancellable
                    obj.displayRunning(status, true);
                case statusMgr.StatusType.Error
                    obj.displayError(status);
                case statusMgr.StatusType.Warning
                    obj.displayWarning(status);
                case statusMgr.StatusType.Success
                    obj.displaySuccess(status);
                case statusMgr.StatusType.Idle
                    obj.displayIdle(status);
                case statusMgr.StatusType.RequestingInput
                    obj.handleInputRequest(status);
                case {statusMgr.StatusType.AwaitingInput, statusMgr.StatusType.ValueSupplied}
                    % Intermediate input states — no display action needed.
                otherwise
                    error("Unknown status type");
            end % switch
        end

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

        function beforeDisplay(obj) %#ok<MANU>
            % Overload to do something before each display trigger
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
