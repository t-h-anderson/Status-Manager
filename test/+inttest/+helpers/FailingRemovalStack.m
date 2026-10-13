classdef FailingRemovalStack < statusMgr.Stack
    % Stack subclass for tests: removing a Running status completes it and
    % then throws, standing in for a failing CompletionFcn on the status
    % that run() pushes internally (CompletionFcn is not settable there).

    methods
        function removeStatus(objs, toRemove, varargin)
            removeStatus@statusMgr.Stack(objs, toRemove, varargin{:});
            if any([toRemove.Type] == statusMgr.StatusType.Running)
                error("test:completion", "Completion failed.");
            end
        end
    end
end
