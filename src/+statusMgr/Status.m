classdef Status < matlab.mixin.SetGet
    %STATUS settings for models
   
    properties (SetAccess = protected)
        Identifier (1,1) string = "" % Semantic identified, for filtering/suppression
        Type (1,1) statusMgr.StatusType = statusMgr.StatusType.Idle
        % Ordered importance, used by views for verbosity gating
        % (status.Level >= view.MinLevel). Defaults from Type via
        % statusMgr.Level.defaultFor; override with the Level= nvp.
        Level (1,1) statusMgr.Level = statusMgr.Level.Trace
        % Message is the canonical text. Views render Message by default;
        % MessageShort is an optional shorter form that views with limited
        % space may prefer (e.g. the StatusBar's inline alert label, or a
        % Popup alert). When MessageShort is unset (the string(NaN)
        % default) those views fall back to Message, so always populate
        % Message and only set MessageShort when a condensed label helps.
        Message (1,1) string = ""
        Title (1,1) string = ""
        MessageShort (1,1) string = string(NaN)
        Value (1,1) double = NaN
        Data = [] % Pocket to store data
        Timestamp (1,1) datetime
        User (1,1) string = ""

        IsTemporary (1,1) logical = false % Remove when next status added
        CompletionFcn (1,:) function_handle {mustBeScalarOrEmpty}
    end

    properties (SetAccess = protected, SetObservable)
        % SetObservable so callers can use `waitfor(status, 'IsComplete', true)`
        % to block until the status is resolved (completed externally or by
        % an input view supplying a value).
        IsComplete (1,1) logical = false
    end

    properties (SetAccess = protected, Hidden)
        ID (1,1) string = "" % unique ID
    end

    events (NotifyAccess = protected)
        Completed % When the status is removed/cleared
    end

    methods
        function obj = Status(condition, message, nvp)
            %STATUS Construct an instance of this class

            arguments
                condition (1,1) statusMgr.StatusType = statusMgr.StatusType.Idle
                message (1,1) string = ""
                nvp.Title (1,1) string = ""
                nvp.Identifier (1,1) string = ""
                nvp.Value (1,1) double = NaN
                % Empty sentinel: when no Level is given, derive it from
                % the status type after `condition` is known.
                nvp.Level (1,:) statusMgr.Level {mustBeScalarOrEmpty} = statusMgr.Level.empty(1,0)
                nvp.IsTemporary (1,1) logical = false
                nvp.Data
                nvp.MessageShort (1,1) string = string(NaN)
                nvp.CompletionFcn (1,:) function_handle {mustBeScalarOrEmpty} = function_handle.empty(1,0)
            end

            % Random string for ID
            obj.ID = statusMgr.util.uuid();

            % Capture who and when the status was created.
            obj.Timestamp = datetime("now");
            user = getenv("USER");
            if isempty(user)
                user = getenv("USERNAME");
            end
            obj.User = string(user);

            obj.Type = condition;
            obj.Message = message;

            if isempty(nvp.Level)
                obj.Level = statusMgr.Level.defaultFor(condition);
            else
                obj.Level = nvp.Level;
            end
            nvp = rmfield(nvp, "Level");

            set(obj, nvp);
        end

        function updateMessage(objs, message)
            arguments
                objs (1,:) statusMgr.Status
                message (1,1) string
            end
            [objs.Message] = deal(message);
        end

        function updateValue(objs, value)
            arguments
                objs (1,:) statusMgr.Status
                value (1,1) double
            end
            [objs.Value] = deal(value);
        end

        function transitionInputState(obj, newType, value)
            % Transition status type for the input request protocol.
            % RequestingInput -> AwaitingInput -> ValueSupplied
            arguments
                obj (1,1) statusMgr.Status
                newType (1,1) statusMgr.StatusType
                value (1,1) string = ""
            end
            validTargets = [statusMgr.StatusType.AwaitingInput, statusMgr.StatusType.ValueSupplied];
            if ~ismember(newType, validTargets)
                error("statusMgr:Status:invalidTransition", ...
                    "transitionInputState only accepts AwaitingInput or ValueSupplied.");
            end
            obj.Type = newType;
            if newType == statusMgr.StatusType.ValueSupplied
                obj.Message = value;
                % Setting IsComplete (which is SetObservable) unblocks any
                % `waitfor` in Stack.requestInput. We deliberately do NOT
                % go through complete(), because that would fire the
                % "Completed" event and trigger Stack.onStatusCompleted to
                % remove the status — the caller's onCleanup already does
                % that, and double-removal is harmless but noisy.
                obj.IsComplete = true;
            end
        end

        function throwIfComplete(obj, identifier, message)
            % Convenience for cancellable user code that prefers error-
            % style propagation. Raises an MException if IsComplete is
            % true. Default identifier mirrors the cancellation idiom:
            %
            %   stack.runCancellable(@(status) work(status));
            %
            %   function work(status)
            %       for i = 1:N
            %           status.throwIfComplete();   % bails out if cancelled
            %           % ...
            %       end
            %   end
            arguments
                obj (1,1) statusMgr.Status
                identifier (1,1) string = "statusMgr:cancelled"
                message (1,1) string = "Operation was cancelled."
            end
            if obj.IsComplete
                error(identifier, message);
            end
        end

        function complete(objs)
            idx = ~[objs.IsComplete];
            toComplete = (objs(idx));

            if ~isempty(toComplete)
                [toComplete.IsComplete] = deal(true);

                % Call any completion functions
                for i = 1:numel(toComplete)
                    this = toComplete(i);
                    if ~isempty(this.CompletionFcn)
                        this.CompletionFcn(this);
                    end
                end

                notify(toComplete, "Completed");
            end
        end

        function tbl = table(objs)
            % Materialise an array of Status handles into a snapshot
            % table. Each row captures the field values at call time;
            % later mutation of the underlying Status (e.g. an input
            % request transitioning Type / Message) does not change
            % the row, which is the contract callers like RecordingView
            % rely on.

            if isempty(objs)
                % CSL expansion on an empty array drops type info
                % (e.g. [objs.Value] -> double []), so seed the
                % schema explicitly. Keeps vertcat with later non-
                % empty rows from coercing column types.
                tbl = table( ...
                    'Size', [0 13], ...
                    'VariableTypes', {'string','string','string', ...
                        'datetime','string','string','string', ...
                        'string','string','double','cell','logical', ...
                        'logical'}, ...
                    'VariableNames', {'ID','Identifier','Title', ...
                        'Timestamp','User','Level','Type', ...
                        'Message','MessageShort','Value','Data', ...
                        'IsTemporary','IsComplete'});
                return
            end

            ID           = string([objs.ID])';
            Identifier   = string([objs.Identifier])';
            Title        = string([objs.Title])';
            Timestamp    = [objs.Timestamp]';
            User         = string([objs.User])';
            Level        = string([objs.Level])';
            Type         = string([objs.Type])';
            Message      = string([objs.Message])';
            MessageShort = string([objs.MessageShort])';
            Value        = [objs.Value]';
            Data         = {objs.Data}';
            IsTemporary  = [objs.IsTemporary]';
            IsComplete   = [objs.IsComplete]';

            tbl = table(ID, Identifier, Title, Timestamp, User, ...
                Level, Type, Message, MessageShort, Value, Data, ...
                IsTemporary, IsComplete);
        end

        function delete(objs)
            % Per-element teardown of a Status array.
            %
            % MATLAB destroys handle arrays in two phases when the
            % destruction is triggered by property/scope cleanup (e.g.
            % a Stack being deleted releases its Statuses property):
            %
            %   1. Every element of the array is pre-marked invalid.
            %   2. This user-defined delete runs.
            %   3. The underlying memory is reclaimed.
            %
            % Between (1) and (3) the property storage is still readable
            % (so `objs(i).IsComplete` works) but `isvalid(objs(i))`
            % already returns false, and any *batched* access like
            % `[objs.IsComplete]` throws — gathering across the array
            % trips the invalid-handle check on the first dead element
            % and aborts the whole expression. We therefore iterate
            % element by element with a try/catch so one torn-down
            % sibling cannot prevent cleanup of the rest.
            for i = 1:numel(objs)
                try
                    if ~objs(i).IsComplete
                        notify(objs(i), "Completed");
                    end
                catch
                    % Element fully torn down — nothing left to notify.
                end
            end
        end

        function val = get.MessageShort(obj)
            if ismissing(obj.MessageShort)
                val = obj.Message;
            else
                val = obj.MessageShort;
            end
        end

    end % methods

end % classdef

