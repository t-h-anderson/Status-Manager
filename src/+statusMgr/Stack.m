classdef Stack < statusMgr.internal.StackInterface
    %STACK
    % Use example:
    % statusStack = statusMgr.Stack();
    % [newStatus, cleanObj] = statusStack.addStatus(statusMgr.StatusType.Running, "Initialising");
    % statusStack.updateStatus(newStatus, Message="Working...");

    properties (SetAccess = protected)
        % Empty default rather than statusMgr.Status("Idle"): a handle
        % object used as a property default is constructed once at class
        % load and shared by every instance (and never freed until the
        % class is cleared, which warns at session teardown when the path
        % is already gone). get.Statuses lazily refills the Idle default
        % per instance instead.
        Statuses = statusMgr.Status.empty(1,0)
    end

    properties (SetAccess = protected, Transient)
        StatusListeners
        StackMonitorableListeners
    end

    properties (SetAccess = protected)
        % Use suppressIdentifier / unsuppressIdentifier to mutate. The
        % setter is protected so callers can read the list but cannot
        % bypass the de-duplication / removal helpers.
        SuppressedIdentifiers (1,:) string = string.empty(1,0)
    end

    properties (Hidden)
        ID
    end

    properties (Access = private, Transient)
        FutureMonitorResources (1,:) struct = struct( ...
            "StatusID", {}, ...
            "PollTimer", {}, ...
            "ProgressSubscription", {}, ...
            "CompletionListener", {})
    end

    properties (Dependent)
        CurrentStatus
    end

    methods
        function obj = Stack()
            obj.ID = matlab.lang.internal.uuid();
            % Attach a listener to the default-initialised Idle status.
            % The property default expression runs through the auto-setter
            % before the constructor body, so the listener bookkeeping
            % below has to catch up here.
            obj.StatusListeners = obj.makeCompletedListener(obj.Statuses(1));
        end

        function delete(obj)
            obj.cleanupFutureMonitorResources();
            if ~isempty(obj.StatusListeners)
                delete(obj.StatusListeners);
            end
            obj.StatusListeners = event.listener.empty(1,0);
            if ~isempty(obj.StackMonitorableListeners)
                delete(obj.StackMonitorableListeners);
            end
            obj.StackMonitorableListeners = event.listener.empty(1,0);
            obj.Statuses = statusMgr.Status.empty(1,0);
        end
    end

    methods % get/set

        % Ensure there is always an idle status
        function val = get.Statuses(obj)
            if isempty(obj.Statuses)
                % Refill inline rather than via attachStatus: attachStatus
                % reads obj.Statuses, which would re-enter this getter while
                % the array is still empty and recurse without bound.
                idle = statusMgr.Status("Idle");
                obj.Statuses = idle;
                obj.StatusListeners = obj.makeCompletedListener(idle);
            end
            val = obj.Statuses;
        end

        % Get the latest status
        function value = get.CurrentStatus(obj)
            % Note, statuses can never be empty as it will default to idle
            % if this ever occurs, see get.Statuses
            value = obj.Statuses(end);
        end

    end

    methods % Adding

        function [status, cleanupObj] = addStatus(objs, type, nvp)
            % Push a new Status of the given type to the stack
            % [status, cleanupObj] = addStatus(StatusType, nvp)
            % cleanupObj is an optional output that creates a cleanup object
            % Name value pairs:
            %   Message (Running) - set the Status message
            %   IsVisible (true) - set the Status visibility
            %   Value (double) - Used for setting progress bar values
            %   Data (Status data) - Store data in the Status
            %   Silent (logical) - whether to notify the Status has
            %   changed
            arguments
                objs (1,:) statusMgr.Stack
                type (1,1) statusMgr.StatusType = statusMgr.StatusType.Info
                nvp.Identifier (1,1) string = ""
                nvp.Message (1,1) string = ""
                nvp.Title (1,1) string = ""
                nvp.MessageShort(1,1) string = string(nan)
                nvp.IsVisible (1,1) logical = true
                nvp.IsTemporary (1,:) logical {mustBeScalarOrEmpty} = false
                nvp.Value (1,1) double = NaN
                nvp.Data = []
                nvp.Silent (1,1) logical = false
                nvp.CreateCleanupObj (1,1) logical = true
                nvp.CompletionFcn (1,:) function_handle {mustBeScalarOrEmpty} = function_handle.empty(1,0)
            end

            if nargout < 2
                nvp.CreateCleanupObj = false;
            end

            newStatus = statusMgr.Status(type, nvp.Message, ...
                "Title", nvp.Title, ...
                "Identifier", nvp.Identifier, ...
                "MessageShort", nvp.MessageShort, ...
                "IsVisible", nvp.IsVisible, ...
                "Value", nvp.Value, ...
                "IsTemporary", nvp.IsTemporary, ...
                "Data", nvp.Data, ...
                "CompletionFcn", nvp.CompletionFcn);

            [status, cleanupObj] = objs.add(newStatus, ...
                "Silent", nvp.Silent, ...
                "CreateCleanupObj", nvp.CreateCleanupObj);

        end

        function [newStatus, cleanupObj] = add(objs, newStatus, nvp)
            % Push a new status onto each stack in objs.
            % [newStatus, cleanupObj] = add(args, newStatus)
            % cleanupObj is an optional output that creates a cleanup object
            % Name value pairs:
            %   Silent (logical) - whether to notify the Status has changed
            arguments
                objs (1,:) statusMgr.Stack
                newStatus (1,1) statusMgr.Status
                nvp.Silent (1,1) logical = false
                nvp.CreateCleanupObj (1,1) logical = true
            end

            if nargout < 2
                nvp.CreateCleanupObj = false;
            end

            % Empty objs returns an empty Status to keep the contract.
            if isempty(objs)
                newStatus = statusMgr.Status.empty(1,0);
            end

            cleanupObj = onCleanup.empty(1,0);
            for i = 1:numel(objs)
                obj = objs(i);
                obj.appendStatus(newStatus);
                if nvp.CreateCleanupObj
                    cleanupObj(end+1) = onCleanup(@() obj.removeStatus(newStatus)); %#ok<AGROW>
                end
                if ~nvp.Silent
                    notify(obj, "StatusUpdated", statusMgr.monitorable.StatusEventData(newStatus, "Added"));
                end
            end
        end

        function [newStatus, cleanupObj] = addError(objs, err, nvp)
            arguments
                objs (1,:)
                err (1,1) MException
                nvp.IsVisible (1,1) logical = true
                nvp.IsTemporary (1,1) logical = false
                nvp.Silent (1,1) logical = false
                nvp.CreateCleanupObj (1,1) logical = true
            end

            % Remove test infrastructure
            messageShort = err.message;

            % Trim the extended report at the first frame mentioning
            % "matlab.unittest" so unit-test stack frames don't drown
            % the user's actual error. This is a textual heuristic on
            % MATLAB's report formatting — if the framework is ever
            % renamed (or user code legitimately contains that string
            % in a path) the trim would no-op or be wrong. Refine to
            % a structural marker if that becomes a problem.
            message = getReport(err, "extended");
            message = string(message);
            message = strsplit(message, newline);
            idx = find(contains(message, "matlab.unittest"), 1);
            message(idx:end) = [];
            message = strjoin(message, newline);

            if nargout < 2
                nvp.CreateCleanupObj = false;
            end

            nvpCell = namedargs2cell(nvp);
            [newStatus, cleanupObj] = objs.addStatus("Error", ...
                "Identifier", err.identifier, ...
                "Data", err, ...
                "Message", message, ...
                "MessageShort", messageShort, ...
                nvpCell{:});

        end

    end

    methods % Updating

        function updateStatus(objs, status, nvp)
            arguments
                objs (1,:) statusMgr.Stack
                status (1,1) statusMgr.Status
                nvp.Message (1,1) string
                nvp.Value (1,1) double
            end

            for i = 1:numel(objs)
                obj = objs(i);
                % obj.CurrentStatus is guaranteed non-empty by
                % get.Statuses (which restores an Idle default if the
                % array is ever cleared).
                if obj.CurrentStatus.ID == status.ID
                    % Quickest to just update the current status.
                    if isfield(nvp, "Message")
                        obj.CurrentStatus.updateMessage(nvp.Message);
                    end
                    if isfield(nvp, "Value")
                        obj.CurrentStatus.updateValue(nvp.Value);
                    end
                    if isfield(nvp, "Message") || isfield(nvp, "Value")
                        notify(obj, "StatusUpdated", statusMgr.monitorable.StatusEventData(status, "Updated"));
                    end
                else
                    % Log an explicit update even underneath the current
                    % status. UI views still read the top of the stack.
                    idx = ([obj.Statuses.ID] == status.ID);
                    if isfield(nvp, "Message")
                        obj.Statuses(idx).updateMessage(nvp.Message);
                    end
                    if isfield(nvp, "Value")
                        obj.Statuses(idx).updateValue(nvp.Value);
                    end
                    if any(idx) && (isfield(nvp, "Message") || isfield(nvp, "Value"))
                        notify(obj, "StatusUpdated", statusMgr.monitorable.StatusEventData(status, "Updated"));
                    end
                end
            end
        end

    end

    methods % Removing

        function removeStatus(objs, toRemove, nvp)
            % Remove a status from the stack
            % - doesn't have to be top of the stack!

            arguments
                objs (1,:) statusMgr.Stack
                toRemove (1,:) statusMgr.Status
                nvp.Silent (1,1) logical = false
            end

            % Clean up every stack before reporting a completion failure.
            failure = MException.empty(0,1);
            for ii = 1:numel(objs)
                obj = objs(ii);
                if ~isvalid(obj)
                    continue
                end

                % Check if last status
                if isscalar(toRemove) ...
                        && obj.CurrentStatus.ID == toRemove.ID
                    matchingIdx = numel(obj.Statuses);
                else
                    % Find matching statuses by ID
                    allIds = string([obj.Statuses.ID]);
                    idsToRemove = string([toRemove.ID]);
                    matchingIdx = matches(allIds, idsToRemove);
                end

                toComplete = obj.Statuses(matchingIdx);
                obj.Statuses(matchingIdx) = [];
                % StatusListeners is kept parallel to Statuses by
                % attachStatus; drop the matching slots in lockstep.
                delete(obj.StatusListeners(matchingIdx));
                obj.StatusListeners(matchingIdx) = [];
                try
                    toComplete.complete();
                catch cause
                    if isempty(failure)
                        failure = cause;
                    else
                        failure = addCause(failure, cause);
                    end
                end

                if ~nvp.Silent && isvalid(obj)
                    notify(obj, "StatusUpdated", statusMgr.monitorable.StatusEventData(obj.CurrentStatus, "Refresh"));
                end

            end
            if ~isempty(failure)
                rethrow(failure);
            end

        end

        function removeLastStatus(obj, nvp)
            % Remove the last status from the stack
            arguments
                obj (1,1) statusMgr.Stack
                nvp.Silent (1,1) logical = false
            end

            obj.removeStatus(obj.CurrentStatus, Silent=nvp.Silent);

        end

        function removeAllStatuses(obj)
            arguments
                obj (1,:) statusMgr.Stack
            end

            % Remove all the statuses
            statuses = [obj.Statuses];
            obj.removeStatus(statuses);
        end

    end

    methods % Monitoring

        function monitor(obj, monitorable)
            arguments
                obj (1,1) statusMgr.Stack
                monitorable (1,1) statusMgr.monitorable.Monitorable
            end
            % Weak Stack ref in the callback, as in makeCompletedListener:
            % the Stack owns this listener, so capturing the Stack strongly
            % would form a cycle that defers collection to session end.
            weakStack = matlab.lang.WeakReference(obj);
            obj.StackMonitorableListeners(end+1) = event.listener(monitorable, ...
                "StatusChanged", ...
                @(s,e) statusMgr.Stack.onMonitorableStatusChangedFromWeak(weakStack, s, e));
        end

        function status = monitorFuture(obj, future, nvp)
            % Push a status that mirrors a parallel.Future's lifecycle.
            %
            %   status = stack.monitorFuture(future)
            %   status = stack.monitorFuture(future, ProgressQueue=q, ...)
            %
            % The returned Status is held on the stack as
            % RunningCancellable (or Running, if Cancellable=false)
            % while the future is queued or running. When the future
            % finishes the status is completed; if it failed,
            % future.Error is converted into an Error status. If user
            % code completes the status (e.g. via the StatusBar Cancel
            % button) the future is cancelled.
            %
            % Progress updates: pass an optional parallel.pool.DataQueue
            % that the worker calls send() on. Numeric scalars set the
            % status's Value; strings update Message; structs with
            % Value/Message fields update both.
            %
            % Terminal detection uses a periodic poll (PollPeriod
            % seconds, default 0.5) on future.State so we catch both
            % success and failure uniformly — afterEach/afterAll fire
            % only on success.
            %
            % Pass Message to give the status a meaningful label; this is
            % recommended because monitorFuture only has the future (not
            % the function handle) to fall back on. Without it the status
            % shows a generic "Background task". (runInBackground, which
            % does have the handle, derives a label from it automatically.)
            arguments
                obj (1,1) statusMgr.Stack
                future (1,1) parallel.Future
                nvp.Message (1,1) string = ""
                nvp.Cancellable (1,1) logical = true
                nvp.ProgressQueue = parallel.pool.DataQueue.empty(1,0)
                nvp.PollPeriod (1,1) double {mustBePositive} = 0.5
            end

            msg = nvp.Message;
            if msg == ""
                % No useful handle here; future.ID is a session-scoped
                % integer that means nothing to end users, so use a plain
                % generic label and let callers supply a real Message.
                msg = "Background task";
            end

            statusType = "Running";
            if nvp.Cancellable
                statusType = "RunningCancellable";
            end

            % addStatus with one output: no auto-cleanup. The poll
            % timer / cancel listener manage status lifetime.
            status = obj.addStatus(statusType, ...
                "Message", msg, ...
                "Data", future);

            progressSubscription = [];
            if ~isempty(nvp.ProgressQueue)
                progressSubscription = obj.makeProgressSubscription(status, nvp.ProgressQueue);
            end

            obj.attachFutureMonitoring(status, future, nvp.PollPeriod, progressSubscription, nvp.ProgressQueue);
        end

        function [future, status] = runInBackground(obj, fcnHandle, nvp)
            % Convenience: parfeval + monitorFuture in one call.
            %
            %   [future, status] = stack.runInBackground(@myFcn, ...
            %       Args={a, b}, NumOutputs=1, Message="Loading data");
            %
            % The worker's arguments are passed as a cell via Args={...},
            % matching run().
            %
            % To stream progress, create a DataQueue and pass it both
            % into Args (the worker calls send() on it) and as
            % ProgressQueue (the monitor listens):
            %
            %   q = parallel.pool.DataQueue;
            %   stack.runInBackground(@workerFcn, ...
            %       Args={q, x, y}, ProgressQueue=q);
            %
            % By default the work runs on the backgroundPool (no
            % Parallel Computing Toolbox required). Pass Pool=parpool
            % or any other parallel.Pool to override.
            arguments
                obj (1,1) statusMgr.Stack
                fcnHandle (1,1) function_handle
                nvp.Args (1,:) cell = {}
                nvp.NumOutputs (1,1) double {mustBeNonnegative, mustBeInteger} = 1
                nvp.Pool = backgroundPool
                nvp.Message (1,1) string = ""
                nvp.Cancellable (1,1) logical = true
                nvp.ProgressQueue = parallel.pool.DataQueue.empty(1,0)
                nvp.PollPeriod (1,1) double {mustBePositive} = 0.5
            end

            msg = nvp.Message;
            if msg == ""
                msg = "Running: " + statusMgr.Stack.functionLabel(fcnHandle);
            end

            statusType = "Running";
            if nvp.Cancellable
                statusType = "RunningCancellable";
            end

            status = obj.addStatus(statusType, ...
                "Message", msg, ...
                "Data", []);

            future = parfeval(nvp.Pool, fcnHandle, nvp.NumOutputs, nvp.Args{:});
            status.updateData(future);

            progressSubscription = [];
            if ~isempty(nvp.ProgressQueue)
                progressSubscription = obj.makeProgressSubscription(status, nvp.ProgressQueue);
            end

            obj.attachFutureMonitoring(status, future, nvp.PollPeriod, progressSubscription, nvp.ProgressQueue);
        end

        function varargout = run(obj, fcnHandle, nvp)
            % Run a function while pushing a Running status onto the
            % stack. By default, errors are caught and pushed as Error
            % statuses, and any warning issued during the call is
            % pushed as a Warning status.
            %
            %   stack.run(@myFcn)
            %   stack.run(@myFcn, Args={arg1, arg2})
            %   stack.run(@myFcn, CatchErrors=false)
            %   stack.run(@myFcn, Args={arg1, arg2}, CatchWarnings=false)
            %
            % Args is a cell of positional arguments forwarded to
            % fcnHandle (matching runInBackground's spelling). For a
            % zero-arg call, omit Args. Function arguments are only taken
            % via Args, so they can never be mistaken for runner options.
            arguments
                obj (1,1) statusMgr.Stack
                fcnHandle (1,1) function_handle
                nvp.Args (1,:) cell = {}
                nvp.CatchErrors (1,1) logical = true
                nvp.CatchWarnings (1,1) logical = true
                nvp.Message (1,1) string = ""
                nvp.Identifier (1,1) string = ""
                nvp.SuccessMessage (1,1) string = ""
                nvp.SuccessIdentifier (1,1) string = ""
                nvp.SuccessIsTemporary (1,1) logical = true
            end

            varargout = cell(1, nargout);
            [varargout{:}] = obj.runWithStatus("Running", false, ...
                fcnHandle, nvp.Args, nvp);
        end

        function varargout = runCancellable(obj, fcnHandle, nvp)
            % Like run(), but pushes a RunningCancellable status and
            % passes that Status as the FIRST argument to fcnHandle.
            % Cancel-aware views (e.g. Popup) call status.complete()
            % when the user clicks Cancel; user code is expected to
            % poll status.IsComplete (or listen on Completed) and bail
            % out gracefully:
            %
            %   stack.runCancellable(@(status) work(status));
            %   stack.runCancellable(@(status, a, b) work(status, a, b), ...
            %       Args={a, b});
            %
            %   function work(status)
            %       for i = 1:N
            %           if status.IsComplete; return; end
            %           % ... do step i ...
            %       end
            %   end
            %
            % While the function is running, status.IsComplete=true
            % unambiguously means "cancel requested" — the natural-
            % completion path (the onCleanup created internally) fires
            % only after fcnHandle returns. Otherwise behaves
            % identically to run() — same name-value flags, same
            % warning capture, same status cleanup.
            arguments
                obj (1,1) statusMgr.Stack
                fcnHandle (1,1) function_handle
                nvp.Args (1,:) cell = {}
                nvp.CatchErrors (1,1) logical = true
                nvp.CatchWarnings (1,1) logical = true
                nvp.Message (1,1) string = ""
                nvp.Identifier (1,1) string = ""
                nvp.SuccessMessage (1,1) string = ""
                nvp.SuccessIdentifier (1,1) string = ""
                nvp.SuccessIsTemporary (1,1) logical = true
            end

            varargout = cell(1, nargout);
            [varargout{:}] = obj.runWithStatus("RunningCancellable", true, ...
                fcnHandle, nvp.Args, nvp);
        end

    end

    methods (Access = protected)

        function varargout = runWithStatus(obj, statusType, passStatusFirst, ...
                fcnHandle, fcnArgs, options)
            % Shared body of run() and runCancellable(): push a status,
            % run fcnHandle, capture errors/warnings, clean up.
            %   statusType        - StatusType to push for the duration
            %   passStatusFirst   - true to inject the Status as the
            %                       first arg to fcnHandle (cancellable
            %                       work uses this to read IsComplete)
            %   fcnArgs (cell)    - positional args from the caller

            route = statusMgr.util.StatusManager.withStack(obj); %#ok<NASGU>

            message = options.Message;
            if message == ""
                message = "Running: " + statusMgr.Stack.functionLabel(fcnHandle);
            end
            status = obj.addStatus(statusType, ...
                Message=message, Identifier=options.Identifier);
            % Only acts if the explicit removal below is never reached
            % (e.g. Ctrl+C while fcnHandle runs).
            runningStack = obj;
            statusGuard = onCleanup(@() ...
                statusMgr.Stack.removeUnlessComplete(runningStack, status)); %#ok<NASGU>
            captor = [];
            if options.CatchWarnings
                captor = statusMgr.util.WarningCapture();
            end
            if passStatusFirst
                fcnArgs = [{status}, fcnArgs];
            end
            varargout = cell(1, nargout);
            failure = [];
            try
                [varargout{:}] = fcnHandle(fcnArgs{:});
            catch cause
                failure = cause;
            end

            warningMsg = "";
            if options.CatchWarnings
                [warningMsg, warningId] = captor.warning();
                delete(captor);
            end

            % Finish progress before publishing the outcome. Removing it
            % afterwards redisplays the outcome through StatusUpdated.
            % Remove it explicitly, after warnings are restored, so a
            % failing CompletionFcn reaches the caller instead of being
            % swallowed by an onCleanup destructor.
            % A completion failure is a failure of the run: it suppresses
            % Success and follows CatchErrors. If the work failed too,
            % keep both, with the work's error as the primary one.
            try
                statusMgr.Stack.removeUnlessComplete(obj, status);
            catch cause
                if isempty(failure)
                    failure = cause;
                else
                    failure = addCause(failure, cause);
                end
            end

            if ~isvalid(obj)
                obj = statusMgr.util.StatusManager.currentStack();
            end
            if warningMsg ~= ""
                obj.addStatus("Warning", Identifier=warningId, Message=warningMsg);
            end
            if ~isempty(failure)
                if ~options.CatchErrors
                    rethrow(failure);
                end
                obj.addError(failure);
            elseif options.SuccessMessage ~= ""
                obj.addStatus("Success", Identifier=options.SuccessIdentifier, ...
                    Message=options.SuccessMessage, MessageShort=options.SuccessMessage, ...
                    IsTemporary=options.SuccessIsTemporary);
            end
        end

    end

    methods
        function invoke(obj, action)
            % UI callback boundary: route library diagnostics and report
            % uncaught exceptions through the configured status views.
            route = statusMgr.util.StatusManager.withStack(obj); %#ok<NASGU>
            captor = statusMgr.util.WarningCapture();
            failure = [];
            try
                action();
            catch cause
                failure = cause;
            end
            [message, identifier] = captor.warning();
            delete(captor);
            % The action may have closed its owning app and stack.
            if message == "" && isempty(failure)
                return
            end
            if ~isvalid(obj)
                obj = statusMgr.util.StatusManager.currentStack();
            end
            if message ~= ""
                obj.addStatus("Warning", Identifier=identifier, Message=message);
            end
            if ~isempty(failure)
                obj.addError(failure);
            end
        end
    end

    methods % User input

        function value = requestInput(obj, prompt, nvp)
            % Block until a view supplies user input, or return DefaultValue
            % after Timeout seconds if no view claims the request.
            %
            % value = requestInput(prompt)
            % value = requestInput(prompt, DefaultValue="fallback", Timeout=5, Title="...")
            arguments
                obj (1,1) statusMgr.Stack
                prompt (1,1) string = ""
                nvp.DefaultValue (1,1) string = ""
                nvp.Title (1,1) string = "Input Required"
                nvp.Timeout (1,1) double {mustBePositive} = 0.5
            end

            % Push RequestingInput. Listeners fire synchronously here, so
            % a view may have already claimed (or even completed) the
            % request by the time addStatus returns.
            status = obj.addStatus(statusMgr.StatusType.RequestingInput, ...
                Message=prompt, ...
                Title=nvp.Title, ...
                Data=nvp.DefaultValue);
            cleanupStatus = onCleanup(@() obj.removeStatus(status));

            % If no view has claimed the request after Timeout seconds,
            % auto-resolve with the default value. The handler is a no-op
            % once the status has already been resolved (IsComplete=true)
            % or a view has claimed it (Type=AwaitingInput).
            weakStatus = matlab.lang.WeakReference(status);
            timeoutTimer = timer( ...
                "StartDelay", nvp.Timeout, ...
                "ExecutionMode", "singleShot", ...
                "TimerFcn", @(~,~) statusMgr.Stack.resolveOnTimeout(weakStatus, nvp.DefaultValue));
            cleanupTimer = onCleanup(@() statusMgr.util.stopTimer(timeoutTimer));
            start(timeoutTimer);

            % Block until the status is resolved. A view supplying a value
            % via transitionInputState(ValueSupplied) sets IsComplete=true,
            % as does external completion (e.g. removeAllStatuses) and the
            % timeout above. waitfor yields to the event loop while it
            % blocks, so timers and UI callbacks still fire.
            if ~status.IsComplete
                waitfor(status, "IsComplete", true);
            end

            if status.Type == statusMgr.StatusType.ValueSupplied
                value = status.Message;
            else
                value = nvp.DefaultValue;
            end
        end

    end

    methods % Suppression

        function suppressIdentifier(obj, id)
            % Hide statuses whose Identifier matches `id`.
            %
            %   stack.suppressIdentifier("myapp:network:timeout")
            %   stack.suppressIdentifier("myapp:network:*")  % glob
            %   stack.suppressIdentifier("*:timeout")
            %
            % `id` is matched against each new status's Identifier as
            % a glob: `*` matches any run of characters (including
            % none); other characters match literally. A status with
            % a matching identifier is added to the stack with
            % IsVisible=false so views skip displaying it.
            arguments
                obj (1,1) statusMgr.Stack
                id (1,1) string
            end
            if ~ismember(id, obj.SuppressedIdentifiers)
                obj.SuppressedIdentifiers(end+1) = id;
            end
        end

        function unsuppressIdentifier(obj, id)
            % Remove an exact `id` from the suppression list. The
            % string must match a previously-added entry exactly
            % (including any wildcards).
            arguments
                obj (1,1) statusMgr.Stack
                id (1,1) string
            end
            obj.SuppressedIdentifiers(obj.SuppressedIdentifiers == id) = [];
        end

        function tf = isIdentifierSuppressed(obj, identifier)
            % True if `identifier` matches any entry in
            % SuppressedIdentifiers (treating each entry as a glob).
            arguments
                obj (1,1) statusMgr.Stack
                identifier (1,1) string
            end
            tf = false;
            if identifier == "" || isempty(obj.SuppressedIdentifiers)
                return
            end
            for sup = obj.SuppressedIdentifiers
                if statusMgr.util.globMatches(identifier, sup)
                    tf = true;
                    return
                end
            end
        end

    end

    methods % Util

        function tbl = table(obj)
            arguments
                obj (1,1) statusMgr.Stack
            end
            tbl = obj.Statuses.table();
        end

    end

    methods (Access = protected)

        function appendStatus(obj, newStatus)

            % Pop any temporary statuses currently on top of the stack.
            % Cap iterations at the stack depth: we can never need to
            % pop more entries than exist, and the cap is a safety net
            % against an invariant violation (e.g. if the default Idle
            % were ever marked IsTemporary by a future change, this
            % loop would otherwise spin forever).
            for i = 1:numel(obj.Statuses)
                if ~obj.CurrentStatus.IsTemporary
                    break
                end
                obj.removeLastStatus(Silent=true);
            end

            % Hide status if its identifier is suppressed.
            if newStatus.Identifier ~= "" && obj.isIdentifierSuppressed(newStatus.Identifier)
                newStatus.IsVisible = false;
            end

            % Add the status (and its per-instance Completed listener).
            obj.attachStatus(newStatus);
        end

        function attachStatus(obj, newStatus)
            % Append a Status and start listening for its Completed
            % event. Per-instance listeners avoid the O(N) rebuild
            % of the whole listener bundle on every push/pop.
            obj.Statuses = [obj.Statuses, newStatus];
            obj.StatusListeners(end+1) = obj.makeCompletedListener(newStatus);
        end

        function progressSubscription = makeProgressSubscription(obj, status, progressQueue)
            arguments
                obj (1,1) statusMgr.Stack
                status (1,1) statusMgr.Status
                progressQueue (1,1) parallel.pool.DataQueue
            end

            statusID = status.ID;
            statusMgr.internal.futureProgressRegistry("register", statusID, obj, status);
            progressSubscription = afterEach(progressQueue, ...
                @(v) statusMgr.internal.onFutureProgress(statusID, v));
        end

        function attachFutureMonitoring(obj, status, future, pollPeriod, progressSubscription, progressQueue)
            arguments
                obj (1,1) statusMgr.Stack
                status (1,1) statusMgr.Status
                future (1,1) parallel.Future
                pollPeriod (1,1) double {mustBePositive}
                progressSubscription = []
                progressQueue = []
            end

            weakStack = matlab.lang.WeakReference(obj);
            weakStatus = matlab.lang.WeakReference(status);

            pollTimer = timer( ...
                "ExecutionMode", "fixedSpacing", ...
                "Period", pollPeriod, ...
                "TimerFcn", @(t,~) statusMgr.Stack.pollFutureState(t, weakStack, weakStatus, future, progressQueue));
            start(pollTimer);

            completionListener = addlistener(status, "Completed", ...
                @(src,~) statusMgr.Stack.onStatusCompletedCancelFuture( ...
                    weakStack, src, future, pollTimer));

            obj.registerFutureMonitorResource(status.ID, pollTimer, progressSubscription, completionListener);
        end

        function lis = makeCompletedListener(obj, status)
            % Build the Completed listener for a Status. The callback holds
            % the Stack via a WeakReference so the listener (which the Stack
            % owns) does not capture the Stack back — that strong cycle is
            % what kept Stacks alive until session-end cycle GC, producing
            % the "delete is not defined" destructor warnings at teardown.
            % The Stack is always rooted elsewhere while in use, so holding
            % it weakly here does not orphan a live Stack.
            weakStack = matlab.lang.WeakReference(obj);
            lis = event.listener(status, "Completed", ...
                @(s,e) statusMgr.Stack.onStatusCompletedFromWeak(weakStack, s, e));
        end

        function onStatusCompleted(obj, s, ~)
            idx = isvalid(obj);
            obj = obj(idx);
            obj.removeStatus(s);
        end

        function onMonitorableStatusChanged(obj, ~, e)
            status = e.Status;
            obj.add(status);
        end

        function registerFutureMonitorResource(obj, statusID, pollTimer, progressSubscription, completionListener)
            resource = struct( ...
                "StatusID", string(statusID), ...
                "PollTimer", pollTimer, ...
                "ProgressSubscription", progressSubscription, ...
                "CompletionListener", completionListener);
            obj.FutureMonitorResources(end+1) = resource;
        end

        function unregisterFutureMonitorResource(obj, statusID)
            if isempty(obj.FutureMonitorResources)
                return
            end

            ids = string({obj.FutureMonitorResources.StatusID});
            idx = ids == string(statusID);
            if ~any(idx)
                return
            end

            resources = obj.FutureMonitorResources(idx);
            obj.FutureMonitorResources(idx) = [];
            for i = 1:numel(resources)
                obj.cleanupFutureMonitorResource(resources(i));
            end
        end

        function cleanupFutureMonitorResources(obj)
            resources = obj.FutureMonitorResources;
            obj.FutureMonitorResources = struct( ...
                "StatusID", {}, ...
                "PollTimer", {}, ...
                "ProgressSubscription", {}, ...
                "CompletionListener", {});
            for i = 1:numel(resources)
                obj.cleanupFutureMonitorResource(resources(i));
            end
        end

        function cleanupFutureMonitorResource(~, resource)
            statusMgr.internal.futureProgressRegistry("unregister", resource.StatusID);
            if isfield(resource, "PollTimer") && ~isempty(resource.PollTimer)
                statusMgr.util.stopTimer(resource.PollTimer);
            end
            if isfield(resource, "ProgressSubscription") && ~isempty(resource.ProgressSubscription)
                try
                    delete(resource.ProgressSubscription);
                catch
                end
            end
            if isfield(resource, "CompletionListener") && ~isempty(resource.CompletionListener)
                try
                    delete(resource.CompletionListener);
                catch
                end
            end
        end

    end

    methods (Static, Hidden)

        function onStatusCompletedFromWeak(weakStack, s, e)
            % Deref the WeakReference set up in makeCompletedListener and
            % forward to onStatusCompleted. If the Stack has already been
            % collected there is nothing left to update, so drop the event.
            stack = weakStack.Handle;
            if isempty(stack) || ~isvalid(stack)
                return
            end
            stack.onStatusCompleted(s, e);
        end

        function onMonitorableStatusChangedFromWeak(weakStack, s, e)
            % Weak-ref counterpart for monitor()'s StatusChanged listener.
            stack = weakStack.Handle;
            if isempty(stack) || ~isvalid(stack)
                return
            end
            stack.onMonitorableStatusChanged(s, e);
        end

        function resolveOnTimeout(weakStatus, defaultValue)
            % requestInput timeout handler. Resolves with the default
            % value only if no view has claimed the request yet
            % (Type still RequestingInput). If a view has claimed
            % (AwaitingInput), the wait is unbounded by design.
            s = weakStatus.Handle;
            if isempty(s) || ~isvalid(s) || s.IsComplete
                return
            end
            if s.Type == statusMgr.StatusType.RequestingInput
                s.transitionInputState( ...
                    statusMgr.StatusType.ValueSupplied, defaultValue);
            end
        end

        function pollFutureState(pollTimer, weakStack, weakStatus, future, progressQueue)
            % monitorFuture's poll callback. Stops the timer and
            % completes the status when the future reaches a terminal
            % state. Failures are converted into an Error status on
            % the stack via addError. weakStack / weakStatus may
            % resolve to empty if the user cleared them — in that
            % case the work behind the future may still complete on
            % its own; we just stop monitoring.
            stack = weakStack.Handle;
            status = weakStatus.Handle;
            if isempty(stack) || isempty(status) ...
                    || ~isvalid(stack) || ~isvalid(status) || ~isvalid(future) ...
                    || status.IsComplete
                statusMgr.util.stopTimer(pollTimer);
                return
            end
            terminalStates = ["finished", "failed", "unavailable"];
            if ~ismember(string(future.State), terminalStates)
                return
            end
            % Worker completion can precede delivery of its queued progress.
            % Let the event loop drain those callbacks before disposing of
            % the subscription and completing the status. The wait is
            % bounded: a queue shared with other producers may never empty.
            if ~isempty(progressQueue) && progressQueue.QueueLength > 0
                drainLimit = 2; % seconds
                if isempty(pollTimer.UserData)
                    pollTimer.UserData = tic;
                    return
                elseif toc(pollTimer.UserData) < drainLimit
                    return
                end
            end
            statusMgr.util.stopTimer(pollTimer);
            if ~isempty(future.Error)
                stack.addError(future.Error);
            end
            status.complete();
        end

        function notifyStatusUpdated(stack, status)
            if isempty(stack) || ~isvalid(stack)
                return
            end
            statuses = stack.Statuses;
            idx = string([statuses.ID]) == status.ID;
            if ~any(idx)
                return
            end
            notify(stack, "StatusUpdated", statusMgr.monitorable.StatusEventData(status, "Updated"));
        end

        function onStatusCompletedCancelFuture(weakStack, status, future, pollTimer)
            % If the status is completed externally (e.g. user clicks
            % Cancel on the StatusBar), stop the poll timer and
            % cancel any not-yet-finished future.
            statusMgr.util.stopTimer(pollTimer);
            stack = weakStack.Handle;
            if ~isempty(stack) && isvalid(stack)
                stack.unregisterFutureMonitorResource(status.ID);
            end
            if isvalid(future) && ismember(string(future.State), ["queued", "running"])
                cancel(future);
            end
        end

        function label = functionLabel(fcnHandle)
            label = eraseBetween(func2str(fcnHandle), textBoundary, ")", ...
                "Boundaries", "inclusive");
        end

        function removeUnlessComplete(stack, status)
            % Remove a run() status unless it has already been completed.
            if isvalid(stack) && isvalid(status) && ~status.IsComplete
                stack.removeStatus(status);
            end
        end

    end

end
