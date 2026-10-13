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

    properties (Access = private)
        SavedState
        InitialMessage
        InitialId
        SavedMessage
        SavedId
    end

    methods
        function obj = WarningCapture()
            obj.SavedState = warning();
            [obj.SavedMessage, obj.SavedId] = lastwarn;
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
            warning(obj.SavedState);
            lastwarn(obj.SavedMessage, obj.SavedId);
        end
    end
end
