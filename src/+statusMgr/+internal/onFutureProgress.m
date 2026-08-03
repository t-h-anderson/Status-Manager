function onFutureProgress(statusID, value)
%ONFUTUREPROGRESS Apply a DataQueue progress update to a monitored Status.
[stack, status] = statusMgr.internal.futureProgressRegistry("resolve", statusID);
if isempty(stack) || isempty(status)
    return
end

didUpdate = false;
if isnumeric(value) && isscalar(value)
    status.updateValue(double(value));
    didUpdate = true;
elseif isstring(value) || (ischar(value) && (isrow(value) || isempty(value)))
    status.updateMessage(string(value));
    didUpdate = true;
elseif isstruct(value)
    if isfield(value, "Value")
        status.updateValue(double(value.Value));
        didUpdate = true;
    end
    if isfield(value, "Message")
        status.updateMessage(string(value.Message));
        didUpdate = true;
    end
    if ~didUpdate
        warning("statusMgr:Stack:unhandledProgressValue", ...
            "Progress struct has neither a Value nor a Message field; " + ...
            "no update applied. Send a numeric scalar, a string, or a " + ...
            "struct with Value and/or Message fields.");
    end
else
    warning("statusMgr:Stack:unhandledProgressValue", ...
        "Progress value of type '%s' (size %s) was ignored. Send a " + ...
        "numeric scalar, a string, or a struct with Value and/or " + ...
        "Message fields.", class(value), mat2str(size(value)));
end

if ~didUpdate
    return
end

statusMgr.Stack.notifyIfCurrentStatus(stack, status);
