classdef StatusManagerGroup < handle
    %STATUSMANAGERGROUP A single Stack with a heterogeneous array of views.
    %
    % Managed by statusMgr.util.StatusManager; not intended for direct use.
    %
    % All views in the group are connected to the same Stack. Adding a view
    % (including an existing one) re-connects it to this group's Stack.
    %
    % Ownership: views added with Owned=true (as StatusManager does for
    % views it creates) are deleted when removed or when the group is
    % deleted. Other views are only disconnected (setStack([])) and can be
    % reused. Deleting the group never deletes its Stack.

    properties (SetAccess = protected)
        Stack
        Views (1,:) statusMgr.internal.view.StatusViewInterface = ...
            statusMgr.internal.view.StatusViewInterface.empty(1,0)
    end

    properties (Access = private)
        % Parallel to Views: true for views the group created or was
        % handed ownership of. Only owned views are deleted with the group.
        IsOwned (1,:) logical = false(1,0)
    end

    methods
        function delete(obj)
            % Release owned views only. The Stack is left untouched:
            % callers may still hold the handle returned by make(). Use
            % StatusManager.shutdown() to destroy stacks explicitly.
            obj.disconnectViews();
            owned = obj.Views(obj.IsOwned);
            delete(owned(isvalid(owned)));
        end


        function disconnectViews(obj)
            %DISCONNECTVIEWS Detach views still bound to this group's Stack.
            % Keeps the handles so reconnectViews (used by restore) can
            % rebind them, but stops their listeners and active displays.
            % Views since rebound to another stack are left alone.
            for view = obj.Views
                if isvalid(view) && isequal(view.Stack, obj.Stack)
                    view.setStack(statusMgr.Stack.empty(1,0));
                end
            end
        end

        function reconnectViews(obj)
            %RECONNECTVIEWS Rebind disconnected views to this group's Stack.
            for view = obj.Views
                if isvalid(view) && isempty(view.Stack)
                    view.setStack(obj.Stack);
                end
            end
        end

        function obj = StatusManagerGroup()
            obj.Stack = statusMgr.Stack();
        end

        function addView(obj, view, nvp)
            %ADDVIEW Connect view to this group's Stack and register it.
            %   group.addView(view)              % caller keeps ownership
            %   group.addView(view, Owned=true)  % deleted with the group
            arguments
                obj  (1,1)
                view (1,1) statusMgr.internal.view.StatusViewInterface
                nvp.Owned (1,1) logical = false
            end
            view.setStack(obj.Stack);
            obj.Views = [obj.Views, view];
            obj.IsOwned = [obj.IsOwned, nvp.Owned];
        end

        function removeView(obj, idx)
            %REMOVEVIEW Remove the view at position idx.
            % Views the group owns are deleted; borrowed views are only
            % detached from the group, so the caller can reuse them.
            arguments
                obj (1,1)
                idx (1,1) double {mustBeInteger, mustBePositive}
            end
            if idx > numel(obj.Views)
                error("statusMgr:StatusManagerGroup:indexOutOfRange", ...
                    "View index %d exceeds number of views (%d).", ...
                    idx, numel(obj.Views));
            end
            view = obj.Views(idx);
            owned = obj.IsOwned(idx);
            obj.Views(idx) = [];
            obj.IsOwned(idx) = [];
            if isvalid(view) && isequal(view.Stack, obj.Stack)
                view.setStack(statusMgr.Stack.empty(1,0));
            end
            if owned
                delete(view);
            end
        end

        function views = findViews(obj, nvp)
            %FINDVIEWS Return views matching a class name and/or instance.
            %   group.findViews(Class="statusMgr.view.Popup")
            %   group.findViews(Instance=viewObj)
            %   group.findViews()  % every view in the group
            % Class matching uses isa, so subclasses match too. When both
            % Class and Instance are given a view must satisfy both.
            arguments
                obj (1,1)
                nvp.Class (1,1) string = ""
                nvp.Instance statusMgr.internal.view.StatusViewInterface ...
                    {mustBeScalarOrEmpty} = ...
                    statusMgr.internal.view.StatusViewInterface.empty(1,0)
            end
            views = obj.Views(obj.matchMask(nvp.Class, nvp.Instance));
        end

        function tf = hasView(obj, nvp)
            %HASVIEW True if any view matches the class name and/or instance.
            arguments
                obj (1,1)
                nvp.Class (1,1) string = ""
                nvp.Instance statusMgr.internal.view.StatusViewInterface ...
                    {mustBeScalarOrEmpty} = ...
                    statusMgr.internal.view.StatusViewInterface.empty(1,0)
            end
            tf = any(obj.matchMask(nvp.Class, nvp.Instance));
        end

        function removed = removeViews(obj, nvp)
            %REMOVEVIEWS Remove views matching a class name and/or instance.
            %   group.removeViews(Class="statusMgr.view.Popup")
            %   group.removeViews(Instance=viewObj)
            %   group.removeViews(Class="...", Delete=true)  % also delete
            % At least one of Class/Instance must be supplied, to guard
            % against accidentally clearing every view. Delete=true deletes
            % the removed view objects (ownership is explicit). Returns the
            % removed views.
            arguments
                obj (1,1)
                nvp.Class (1,1) string = ""
                nvp.Instance statusMgr.internal.view.StatusViewInterface ...
                    {mustBeScalarOrEmpty} = ...
                    statusMgr.internal.view.StatusViewInterface.empty(1,0)
                nvp.Delete (1,1) logical = false
            end
            if nvp.Class == "" && isempty(nvp.Instance)
                error("statusMgr:StatusManagerGroup:noMatchCriteria", ...
                    "removeViews requires a Class and/or Instance to match; " + ...
                    "refusing to remove every view.");
            end
            mask = obj.matchMask(nvp.Class, nvp.Instance);
            % Logical-mask deletion removes matches in one shot, avoiding
            % the index-shifting that reverse-order looping guards against.
            removed = obj.Views(mask);
            obj.Views(mask) = [];
            obj.IsOwned(mask) = [];
            for view = removed
                if isvalid(view) && isequal(view.Stack, obj.Stack)
                    view.setStack(statusMgr.Stack.empty(1,0));
                end
            end
            if nvp.Delete
                delete(removed);
            end
        end

        function cleanup = addViewScoped(obj, view, nvp)
            %ADDVIEWSCOPED Add a view and return an onCleanup that removes it.
            %   cleanup = group.addViewScoped(view);
            %   cleanup = group.addViewScoped(view, Delete=true);
            % The view is connected to this group's Stack (like addView).
            % When the returned onCleanup is destroyed (cleared or goes out
            % of scope) only that view instance is removed from the group;
            % Delete=true also deletes the view object itself.
            arguments
                obj (1,1)
                view (1,1) statusMgr.internal.view.StatusViewInterface
                nvp.Delete (1,1) logical = false
            end
            obj.addView(view, Owned=nvp.Delete);
            doDelete = nvp.Delete;
            cleanup = onCleanup(@() ...
                statusMgr.util.StatusManagerGroup.scopedRemove(obj, view, doDelete));
        end

    end

    methods (Access = private)

        function mask = matchMask(obj, className, instance)
            % Row logical mask over obj.Views. A view matches when it
            % satisfies every supplied criterion (AND). No criteria => all.
            n = numel(obj.Views);
            mask = true(1, n);
            for i = 1:n
                v = obj.Views(i);
                if className ~= "" && ~isa(v, className)
                    mask(i) = false;
                elseif ~isempty(instance) && v ~= instance
                    mask(i) = false;
                end
            end
        end

    end

    methods (Static, Access = private)

        function scopedRemove(group, view, doDelete)
            % Teardown for addViewScoped's onCleanup. Detach the view from
            % the group if the group is still alive, then honour the
            % explicit Delete request regardless of the group's state.
            if isvalid(group)
                group.removeViews(Instance=view);
            end
            if doDelete && isvalid(view)
                delete(view);
            end
        end

    end

end
