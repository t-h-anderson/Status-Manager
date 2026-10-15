classdef WarningCapture < handle
    %WARNINGCAPTURE Detect any MATLAB warning issued in a scope.
    %
    % The constructor saves the current warning state, silences warnings
    % so they do not pollute the command window during the captured
    % region, and snapshots `lastwarn` so any later change can be
    % attributed to a warning issued during the scope.
    %
    % Usage:
    %   captor = statusMgr.util.WarningCapture();
    %   ... code that might issue warnings ...
    %   [msg, id] = captor.warning();
    %   if msg ~= ""
    %       % a warning was issued during the captured region
    %   end
    %   % warning() state is restored automatically when captor is deleted
    %
    % While a capture is active the live warning state is "all off", so
    % use statusMgr.util.WarningCapture.isEnabled(id) to ask whether the
    % caller had a warning enabled before the outermost capture began.

    properties (Access = private)
        SavedState
        InitialMessage
        InitialId
        SavedMessage
        SavedId
        Token
    end

    methods
        function obj = WarningCapture()
            obj.SavedState = warning();
            [obj.SavedMessage, obj.SavedId] = lastwarn;
            obj.Token = statusMgr.util.uuid();
            statusMgr.util.WarningCapture.activeStates("push", obj.Token, obj.SavedState);
            warning("off");
            % Seed lastwarn directly without emitting a warning. Restore
            % the caller's value on deletion so nested captures do not
            % report the same native warning twice.
            sentinel = statusMgr.util.uuid();
            lastwarn(sentinel, "statusMgr:WarningCapture:sentinel");
            [obj.InitialMessage, obj.InitialId] = lastwarn;
        end

        function [msg, id] = warning(obj)
            % Return the warning message and identifier of the last
            % warning issued since this capture started, or empty
            % strings if none. "MATLAB:callback:error" is filtered out
            % — those come from errors raised inside unrelated callbacks
            % during the captured region.
            [w, c] = lastwarn;
            unchanged = strcmp(w, obj.InitialMessage) ...
                && strcmp(c, obj.InitialId);
            if unchanged || strcmp(c, "MATLAB:callback:error")
                msg = "";
                id = "";
            else
                msg = string(w);
                id = string(c);
            end
        end

        function delete(obj)
            if ~isempty(obj.Token)
                statusMgr.util.WarningCapture.activeStates("pop", obj.Token);
            end
            if ~isempty(obj.SavedState)
                warning(obj.SavedState);
                lastwarn(obj.SavedMessage, obj.SavedId);
            end
        end
    end

    methods (Static)
        function tf = isEnabled(identifier)
            %ISENABLED True unless the caller's warning state disables identifier.
            %
            % Outside any capture this reads the live warning state. Inside
            % one it reads the state saved by the outermost active capture,
            % which is the state the caller set before warnings were
            % silenced. An empty identifier follows the "all" state.
            arguments
                identifier (1,1) string
            end
            state = statusMgr.util.WarningCapture.activeStates("outermost");
            if isempty(state)
                state = warning();
            end
            tf = statusMgr.util.WarningCapture.stateFor(state, identifier) ~= "off";
        end
    end

    methods (Static, Access = private)
        function value = stateFor(state, identifier)
            ids = string({state.identifier});
            states = string({state.state});
            match = states(ids == identifier & identifier ~= "");
            if isempty(match)
                match = states(ids == "all");
            end
            value = "on";
            if ~isempty(match)
                value = match(end);
            end
        end

        function state = activeStates(action, token, saved)
            % Ordered registry of the warning states saved by active
            % captures, so isEnabled can see past the silencing.
            persistent tokens states
            if isempty(tokens)
                tokens = strings(1, 0);
                states = {};
            end
            state = [];
            switch action
                case "push"
                    tokens(end+1) = token;
                    states{end+1} = saved;
                case "pop"
                    keep = tokens ~= token;
                    tokens = tokens(keep);
                    states = states(keep);
                case "outermost"
                    if ~isempty(states)
                        state = states{1};
                    end
            end
        end
    end
end
