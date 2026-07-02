classdef (Abstract) StatusViewBase < ...
        statusMgr.internal.view.StatusViewInterface ...
        & matlab.mixin.SetGet
    %STATUSVIEWBASE Shared implementation for concrete status views.
    %
    % Provides the Stack/StackListener storage and the standardDisplay
    % loop, which scans the stack for the topmost status passing this
    % view's shouldDisplay gate (MinLevel verbosity threshold, identifier
    % Include/Exclude filters, and the per-type Show* flags, all AND-ed)
    % and dispatches it — or falls back to clearDisplay when nothing is
    % displayable. Concrete views (Popup, CommandWindow, FileLog)
    % implement the abstract display methods declared at the bottom of
    % this file.

    properties (SetAccess = protected)
        Stack = statusMgr.Stack.empty(1,0)
        StackListener event.listener = event.listener.empty(1,0)
    end

    properties (SetAccess = protected)
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

        % Verbosity threshold: only statuses with Level >= MinLevel are
        % displayed. Defaults to Trace (show everything), so verbosity
        % is strictly opt-in. Complements the Show* flags: MinLevel is
        % the coarse verbosity knob, Show* is surgical per-type control;
        % both must pass. Input requests are exempt (control flow, not
        % verbosity) — they are gated by HandleInputRequests and the
        % identifier filters only.
        MinLevel (1,1) statusMgr.Level = statusMgr.Level.Trace

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

        function standardDisplay(obj)
            % Render this view's reaction to the current stack state.
            %
            % Scans from the top of the stack for the first status this
            % view can act on (shouldDisplay), so a status that is
            % filtered out or below MinLevel for THIS view does not mask
            % a state change underneath it. If nothing is actionable the
            % view falls back to its cleared state rather than leaving
            % the last-rendered status on screen. beforeDisplay() runs on
            % every update, before either path, so transient running
            % state (timers, dialogs) is always torn down first.
            arguments
                obj (1,1)
            end

            if ~obj.isVisible() || ~isvalid(obj)
                return
            end

            statuses = obj.Stack.Statuses;
            toDisplay = statusMgr.Status.empty(1,0);
            isInputRequest = false;
            for i = numel(statuses):-1:1
                s = statuses(i);
                switch s.Type
                    case {statusMgr.StatusType.AwaitingInput, ...
                            statusMgr.StatusType.ValueSupplied}
                        % Transitional input states: never displayable,
                        % never blocking — keep scanning below them.
                        continue
                    case statusMgr.StatusType.RequestingInput
                        % Control flow, not verbosity: exempt from
                        % MinLevel. A view that doesn't handle input
                        % skips it and keeps showing the state below
                        % while another view collects the value.
                        if obj.HandleInputRequests ...
                                && obj.passesIdentifierFilters(s.Identifier)
                            toDisplay = s;
                            isInputRequest = true;
                            break
                        end
                    otherwise
                        if obj.shouldDisplay(s)
                            toDisplay = s;
                            break
                        end
                end
            end

            % Save the chosen status in case a view needs it (e.g. the
            % StatusBar buttons complete IncomingStatus).
            obj.PreviousStatus = obj.IncomingStatus;
            obj.IncomingStatus = toDisplay;

            obj.beforeDisplay();

            if isempty(toDisplay)
                obj.clearDisplay();
                return
            end

            if isInputRequest
                obj.handleInputRequest(toDisplay);
                return
            end

            switch toDisplay.Type
                case statusMgr.StatusType.Info
                    obj.displayInfo(toDisplay);
                case statusMgr.StatusType.Running
                    obj.displayRunning(toDisplay, false);
                case statusMgr.StatusType.RunningCancellable
                    obj.displayRunning(toDisplay, true);
                case statusMgr.StatusType.Error
                    obj.displayError(toDisplay);
                case statusMgr.StatusType.Warning
                    obj.displayWarning(toDisplay);
                case statusMgr.StatusType.Success
                    obj.displaySuccess(toDisplay);
                case statusMgr.StatusType.Idle
                    obj.displayIdle(toDisplay);
                otherwise
                    error("statusMgr:view:unknownStatusType", ...
                        "Unknown status type");
            end % switch

        end % standardDisplay

        function tf = shouldDisplay(obj, status)
            % The single display gate: verbosity threshold, identifier
            % filters, and the per-type Show* flag, all AND-ed. Input
            % requests are gated separately in standardDisplay.
            arguments
                obj (1,1)
                status (1,1) statusMgr.Status
            end
            tf = status.Level >= obj.MinLevel ...
                && obj.passesIdentifierFilters(status.Identifier) ...
                && obj.showsType(status.Type);
        end

        function delete(obj)
            delete(obj.StackListener);
        end

        function setStack(obj, stack)
            % Detach from any previous stack before rebinding so a
            % re-bound view does not keep firing for the old stack.
            delete(obj.StackListener);
            updateStatusFn = @(src, event) obj.standardDisplay();
            obj.Stack = stack;
            % Seed the stack's default suppressions into this view's own
            % excludes. Seeded once at bind time, not read live: after
            % this the view owns its excludes outright. Union keeps a
            % rebind idempotent (but note it re-adds stack defaults a
            % caller removed from the view by hand). Guarded because the
            % interface doesn't require the property (e.g. stack mocks).
            if isprop(stack, "SuppressedIdentifiers")
                obj.ExcludeIdentifiers = reshape(union( ...
                    obj.ExcludeIdentifiers, stack.SuppressedIdentifiers), 1, []);
            end
            obj.StackListener = listener(stack, "StatusUpdated", updateStatusFn);
        end

    end

    methods (Access = protected)

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

        function tf = showsType(obj, type)
            % Map a StatusType onto its per-view Show* flag.
            arguments
                obj (1,1)
                type (1,1) statusMgr.StatusType
            end
            switch type
                case statusMgr.StatusType.Info
                    tf = obj.ShowInfo;
                case {statusMgr.StatusType.Running, ...
                        statusMgr.StatusType.RunningCancellable}
                    tf = obj.ShowRunning;
                case statusMgr.StatusType.Error
                    tf = obj.ShowErrors;
                case statusMgr.StatusType.Warning
                    tf = obj.ShowWarnings;
                case statusMgr.StatusType.Success
                    tf = obj.ShowSuccess;
                case statusMgr.StatusType.Idle
                    tf = obj.ShowIdle;
                otherwise
                    tf = false;
            end
        end

        function beforeDisplay(obj) %#ok<MANU>
            % Overload to do something before each display trigger
        end

        function clearDisplay(obj) %#ok<MANU>
            % Called when no status on the stack is displayable for this
            % view (all filtered out, below MinLevel, or Show*-disabled).
            % Default no-op: beforeDisplay has already torn down transient
            % running state. Views that paint persistent state (StatusBar,
            % InputField) override this to blank their UI.
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
