function varargout = futureProgressRegistry(action, statusID, varargin)
%FUTUREPROGRESSREGISTRY Track progress callbacks by Status ID.
% The DataQueue callback must not close over handle objects or
% WeakReference instances, because that callback workspace is serialized
% alongside the queue when nested/local worker functions receive it.

persistent registry
if isempty(registry)
    registry = containers.Map("KeyType", "char", "ValueType", "any");
end

key = char(string(statusID));

switch string(action)
    case "register"
        stack = varargin{1};
        status = varargin{2};
        registry(key) = struct( ...
            "Stack", matlab.lang.WeakReference(stack), ...
            "Status", matlab.lang.WeakReference(status));
    case "resolve"
        if ~isKey(registry, key)
            varargout = {[], []};
            return
        end

        entry = registry(key);
        stack = entry.Stack.Handle;
        status = entry.Status.Handle;
        if isempty(stack) || isempty(status) ...
                || ~isvalid(stack) || ~isvalid(status)
            remove(registry, key);
            varargout = {[], []};
            return
        end

        varargout = {stack, status};
    case "unregister"
        if isKey(registry, key)
            remove(registry, key);
        end
    otherwise
        error("statusMgr:internal:futureProgressRegistry:invalidAction", ...
            "Unsupported action '%s'.", string(action));
end
