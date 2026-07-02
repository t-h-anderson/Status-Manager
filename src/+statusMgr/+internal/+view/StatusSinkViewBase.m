classdef (Abstract) StatusSinkViewBase < statusMgr.internal.view.StatusViewBase
    %STATUSSINKVIEWBASE Base for views that handle display statuses uniformly.
    %
    % Some views do not need type-specific rendering once StatusViewBase has
    % applied Show* flags and identifier filters. They only need a single
    % sink method that receives every displayed Status.

    methods (Access = protected)

        function displayInfo(obj, status)
            obj.displayStatus(status, false);
        end

        function displayRunning(obj, status, cancellable)
            obj.displayStatus(status, cancellable);
        end

        function displayError(obj, status)
            obj.displayStatus(status, false);
        end

        function displayWarning(obj, status)
            obj.displayStatus(status, false);
        end

        function displaySuccess(obj, status)
            obj.displayStatus(status, false);
        end

        function displayIdle(obj, status)
            obj.displayStatus(status, false);
        end

    end

    methods (Abstract, Access = protected)

        displayStatus(obj, status, cancellable)

    end

end
