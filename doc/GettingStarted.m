%[text] # Getting Started with App Status Stack
%[text] ## Description
%[text] App Status Stack provides a simple framework for app developers (devs) to manage the current status (e.g. idle or running) of models in their MVC apps. It also provides a simple method for the devs to notify the app users (users) of this current state via modal dialog popups.
%[text] Statuses are added to a shared stack and are removed once that status no longer applies. The status on top of the stack, i.e. the last status added, defines the current state. Consequently, if this top status is removed, the next status in the stack become current.
%[text] Note: While statuses are added to the stack, with the top status defining the current state of a model, they *may* be removed in any order.
%[text] ## Installation
%[text] An installation function is included - installStatusManager. Copy this into projects and add to start-up script to make sure that the toolbox is installed and up-to-date.
% This will only run as is if you are in the toolbox directory. 
% Replace "releases" with a folder on the path containing your
% appStatus mltbx.
% installStatusManager("ToolboxPath", "releases")
%%
%[text] ## StatusStack
%[text] Create a status stack via
myStack = statusMgr.Stack();
%[text] This should then be passed to and stored in a property of the any models which need to share a state, e.g. 
%[text]  myModel = MyModel(myStack);
%%
%[text] ## StatusView
%[text] The status view should be stored as a property of the app launcher or main view. Create a state view via statusMgr.ConditionView(myGraphicsHandle, myStack); where myGraphicsHandle is a handle to a graphics object and myStack in an instance of statusMgr.StatusStack that the view should watch. For example,
f = uifigure("Visible","on");
%%
myStateView = statusMgr.view.Popup(f, myStack);
%%
commandLineView = statusMgr.view.CommandWindow(myStack);
%%
%[text] Or render an inline non-modal status bar (color-coded message + optional progress + Cancel button for RunningCancellable). The bar's top-level child is a uigridlayout, which auto-resizes with its parent — so for a "bar at the bottom of a figure" layout, give StatusBar a row in your own outer uigridlayout:
outer = uigridlayout(f, [2, 1], "RowHeight", {"1x", 28});
mainContent = uipanel(outer);
statusBar = statusMgr.view.StatusBar(outer, myStack);
%%
%[text] ## Adding a status
%[text] To add a status, use the addStatus method of StatusStack. There are two possible ways to call the method:
try
    error("a:b:c", "An error has occured")
catch me
    status = myStack.addError(me);
end
%[text] Or
[status, cleanupObj] = myStack.addStatus(statusMgr.StatusType.Error, "Message" , "My Second Error Message", "MessageShort", "Summary of error");
%[text] Here, statusID is a (quasi-) unique identifier for the status, while cleanupObj is created using onCleanup, such that the status will be automatically removed from the stack whenever cleanupObj is deleted or goes out of scope (see removing a status below).
%%
%[text] ### Available States
%[text] Available states with default behaviour:
%[text] Idle:
myStack.addStatus(statusMgr.StatusType.Idle, "Message", "Nothing to show here", "IsTemporary", true);
%[text] Running:
cancelState = myStack.addStatus(statusMgr.StatusType.RunningCancellable, "Message", "Show a cancellable progress bar");
l = addlistener(cancelState, "Completed", @(~,~) cancelClicked);
while ~cancelState.IsComplete %[output:group:1cf35814]
    fprintf(".") %[output:356e866a]
    pause(1);
end %[output:group:1cf35814]

function cancelClicked(varargin)
    disp("Cancel Clicked")
end
%[text] Error:
myStack.addStatus(statusMgr.StatusType.Error, "Message", "Show a uialert with a red exclamation mark");
%[text] Warning:
myStack.addStatus(statusMgr.StatusType.Warning, "Message", "Show a uialert with a yellow exclamation mark");
%[text] Success:
myStack.addStatus(statusMgr.StatusType.Success, "Message", "Show a uialert with a green tick");
%%
%[text] ## Removing a status
%[text] To remove a status, you can delete a cleanupObj associated with a status, 
[~, cleanup] = myStack.addStatus(statusMgr.StatusType.Running, "Message", "Preparing to delete the cleanup obj"); %[output:4ff2e088]
pause(1);
[~, cleanup] = myStack.addStatus(statusMgr.StatusType.Running, "Message", "Delete in 1"); %[output:94629033]
pause(1);
[~, cleanup] = myStack.addStatus(statusMgr.StatusType.Running, "Message", "Deleting"); %[output:8db7733c]
delete(cleanup); %[output:85a3296c]
%[text] Note: if a second output argument is not requested, the cleanup object is not created. If this object goes out of scope, e.g. you leave a function in which is was created as a local variable, it will automatically remove the status from the stack as it is cleaned up.
%%
%[text] Alternatively, you can delete the status manually by passing it to removeStatus:
status = myStack.addStatus(statusMgr.StatusType.Running, "Message", "Preparing to delete the status"); %[output:945570be]
pause(2);
myStack.removeStatus(status); %[output:2dc53d11]
%%
%[text] You can also simply remove the last status by using
myStack.removeLastStatus();
%%
%[text] Finally, you can complete the status manually:
status = myStack.addStatus(statusMgr.StatusType.Running, "Message", "Preparing to complete the status"); %[output:81f474b3]
pause(2);
status.complete();
%%
%[text] It may occasionally be useful to clear the stack of all statuses using
myStack.removeAllStatuses();
%%
%[text] You can also set a status stack to monitor a monitorable class
myObj = statusMgr.demo.DemoMonitorable;
myStack.monitor(myObj);

myObj.showError("Showing error"); %[output:0347b964]
%%
%[text] You can also use the status stack monitor to run arbitrary code
% No popup
[a, b, c] = myStack.run(@() fileparts("a/b.c")); %[output:6cc028ea]

% Waitbar
myStack.run(@() pause(3)); %[output:35541758]

% Error
myStack.run(@() error("hello world error")); %[output:0b046aa0]
% Warning
myStack.run(@() warning("mywarn:test","hello world warning")); %[output:0446e47d]
% Skip auto-capture and rethrow / silently ignore instead
myStack.run(@() error("boom"), CatchErrors=false);
myStack.run(@() warning("test:w","ignored"), CatchWarnings=false);
%%
%[text] ## Cooperative cancellation
%[text] runCancellable wraps a function with a RunningCancellable status and passes that Status as the first argument. A cancel-aware view (e.g. the Popup progress dialog Cancel button) calls status.complete(); the running function polls status.IsComplete and exits. While the function is running, IsComplete=true unambiguously means "cancel requested" — the natural-completion path only fires after the function returns.
myStack.runCancellable(@(status) doSlowWork(status));

function doSlowWork(status)
    for i = 1:100
        status.throwIfComplete();   % or: if status.IsComplete; return; end
        pause(0.05);
    end
end
%%
%[text] ## Suppressing identifiers
%[text] Suppress noisy statuses by identifier. Glob patterns (`*`) match across colons, so namespace-prefixed identifiers are easy to filter. The suppression list is copied into a view's ExcludeIdentifiers when the view binds to the stack, so call suppressIdentifier before creating views (to hide on an existing view, edit its ExcludeIdentifiers). The statuses themselves are always kept on the stack.
myStack.suppressIdentifier("myapp:network:*")  % everything under myapp:network
myStack.suppressIdentifier("*timeout*")        % anything mentioning timeout
myStack.unsuppressIdentifier("myapp:network:*") % must match the entry exactly
%%
%[text] ## Recording history
%[text] RecordingView is a non-rendering view that snapshots every status it receives into RecordedStatuses, a MATLAB table. Each row captures the status's fields at publication time, so later mutation of the underlying Status doesn't change earlier rows. Useful for activity-log panels in apps, and for tests that want to assert on what was published rather than poking at internal stack state.
recorder = statusMgr.view.RecordingView(myStack);
myStack.addStatus("Info", Message="hello");
recorder.RecordedStatuses.Message(end)  % "hello"
recorder.clear();  % drop the captured history
%%
%[text] ## Per-view filters and verbosity
%[text] Every view supports IncludeIdentifiers / ExcludeIdentifiers glob lists, plus a MinLevel verbosity threshold (Trace \< Debug \< Info \< Notice \< Warning \< Error \< Critical). Each status carries a Level defaulted from its type (Running is Notice; override with Level=). One stack can therefore drive a terse view and a record-everything view side by side. Input requests ignore MinLevel — a terse view still collects input.
chatty = statusMgr.view.CommandWindow(myStack, ...
    IncludeIdentifiers=["myapp:debug:*"]);
audit = statusMgr.view.FileLog(myStack, ...
    ExcludeIdentifiers=["*:debug"]);
terse = statusMgr.view.CommandWindow(myStack, MinLevel="Warning");
myStack.addStatus("Info", Message="only audit sees this");
myStack.addStatus("Info", Message="everyone sees this", Level="Critical");
%%
%[text] ## Structured / rotating logs
%[text] FileLog accepts a JSON-lines format and a byte-cap that rotates the log when it grows past MaxBytes. Rotation appends "\_N" before the file extension, e.g. Log.txt → Log\_1.txt → Log\_2.txt.
statusMgr.view.FileLog(myStack, LogFolder=pwd, ...
    Format="json-lines", MaxBytes=1e6);
%%
%[text] ## Background work via parfeval
%[text] runInBackground launches a parfeval future on the backgroundPool, pushes a RunningCancellable status, and converts the future's terminal state into either status completion (success) or an Error status (failure). The StatusBar's Cancel button cancels the future. For streaming progress, pass a parallel.pool.DataQueue to both the worker (which calls send) and runInBackground (which calls afterEach internally to update the status):
q = parallel.pool.DataQueue;
[future, status] = myStack.runInBackground(@workerFcn, ...
    Args={q, x, y}, NumOutputs=1, ...
    Message="Crunching numbers", ProgressQueue=q);

function out = workerFcn(q, x, y)
    for i = 1:100
        send(q, i/100);          % numeric -> Value
        % send(q, "Step " + i)    % string  -> Message
        % send(q, struct(Value=i/100, Message="Step " + i))
    end
    out = doFinalWork(x, y);
end

% Fetch the result when ready (blocks):
result = fetchOutputs(future);

% Or monitor a future you launched yourself:
f = parfeval(backgroundPool, @longJob, 1, x);
myStack.monitorFuture(f, Message="Long job");

%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"inline","rightPanelPercent":40}
%---
%[output:356e866a]
%   data: {"dataType":"text","outputData":{"text":"......","truncated":false}}
%---
%[output:4ff2e088]
%   data: {"dataType":"text","outputData":{"text":"Preparing to delete the cleanup obj\n","truncated":false}}
%---
%[output:94629033]
%   data: {"dataType":"text","outputData":{"text":"Delete in 1\nDelete in 1\n","truncated":false}}
%---
%[output:8db7733c]
%   data: {"dataType":"text","outputData":{"text":"Deleting\nDeleting\n","truncated":false}}
%---
%[output:85a3296c]
%   data: {"dataType":"text","outputData":{"text":"Show a uialert with a green tick\n","truncated":false}}
%---
%[output:945570be]
%   data: {"dataType":"text","outputData":{"text":"Preparing to delete the status\n","truncated":false}}
%---
%[output:2dc53d11]
%   data: {"dataType":"text","outputData":{"text":"Show a uialert with a green tick\n","truncated":false}}
%---
%[output:81f474b3]
%   data: {"dataType":"text","outputData":{"text":"Preparing to complete the status\n","truncated":false}}
%---
%[output:0347b964]
%   data: {"dataType":"text","outputData":{"text":"Error: Showing error\n","truncated":false}}
%---
%[output:6cc028ea]
%   data: {"dataType":"text","outputData":{"text":"Running: fileparts(\"a\/b.c\")\nError: Showing error\n","truncated":false}}
%---
%[output:35541758]
%   data: {"dataType":"text","outputData":{"text":"Running: pause(3)\nError: Showing error\n","truncated":false}}
%---
%[output:0b046aa0]
%   data: {"dataType":"text","outputData":{"text":"Running: error(\"hello world error\")\nError using <strong>LiveEditorEvaluationHelperEeditor48CA285Bmotw>@()error(\"hello world error\")<\/strong> (<a href=\"matlab: opentoline('C:\\Users\\toma\\AppData\\Local\\Temp\\Editor_lzxip\\LiveEditorEvaluationHelperEeditor48CA285Bmotw.m',50,0)\">line 50<\/a>)\nhello world error\n\nError in <a href=\"matlab:matlab.lang.internal.introspective.errorDocCallback('statusMgr.Stack\/run', 'C:\\Users\\toma\\Documents\\AppStatusStack\\src\\+statusMgr\\Stack.m', 356)\" style=\"font-weight:bold\">statusMgr.Stack\/run<\/a> (<a href=\"matlab: opentoline('C:\\Users\\toma\\Documents\\AppStatusStack\\src\\+statusMgr\\Stack.m',356,0)\">line 356<\/a>)\n                    fcnHandle(varargin{:});\n                    ^^^^^^^^^^^^^^^^^^^^^^\nError in <a href=\"matlab:matlab.lang.internal.introspective.errorDocCallback('LiveEditorEvaluationHelperEeditor48CA285Bmotw', 'C:\\Users\\toma\\AppData\\Local\\Temp\\Editor_lzxip\\LiveEditorEvaluationHelperEeditor48CA285Bmotw.m', 50)\" style=\"font-weight:bold\">LiveEditorEvaluationHelperEeditor48CA285Bmotw<\/a> (<a href=\"matlab: opentoline('C:\\Users\\toma\\AppData\\Local\\Temp\\Editor_lzxip\\LiveEditorEvaluationHelperEeditor48CA285Bmotw.m',50,0)\">line 50<\/a>)\nmyStack.run(@() error(\"hello world error\"));\n^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\nError using <strong>LiveEditorEvaluationHelperEeditor48CA285Bmotw>@()error(\"hello world error\")<\/strong> (<a href=\"matlab: opentoline('C:\\Users\\toma\\AppData\\Local\\Temp\\Editor_lzxip\\LiveEditorEvaluationHelperEeditor48CA285Bmotw.m',50,0)\">line 50<\/a>)\nhello world error\n\nError in <a href=\"matlab:matlab.lang.internal.introspective.errorDocCallback('statusMgr.Stack\/run', 'C:\\Users\\toma\\Documents\\AppStatusStack\\src\\+statusMgr\\Stack.m', 356)\" style=\"font-weight:bold\">statusMgr.Stack\/run<\/a> (<a href=\"matlab: opentoline('C:\\Users\\toma\\Documents\\AppStatusStack\\src\\+statusMgr\\Stack.m',356,0)\">line 356<\/a>)\n                    fcnHandle(varargin{:});\n                    ^^^^^^^^^^^^^^^^^^^^^^\nError in <a href=\"matlab:matlab.lang.internal.introspective.errorDocCallback('LiveEditorEvaluationHelperEeditor48CA285Bmotw', 'C:\\Users\\toma\\AppData\\Local\\Temp\\Editor_lzxip\\LiveEditorEvaluationHelperEeditor48CA285Bmotw.m', 50)\" style=\"font-weight:bold\">LiveEditorEvaluationHelperEeditor48CA285Bmotw<\/a> (<a href=\"matlab: opentoline('C:\\Users\\toma\\AppData\\Local\\Temp\\Editor_lzxip\\LiveEditorEvaluationHelperEeditor48CA285Bmotw.m',50,0)\">line 50<\/a>)\nmyStack.run(@() error(\"hello world error\"));\n^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n","truncated":false}}
%---
%[output:0446e47d]
%   data: {"dataType":"text","outputData":{"text":"Running: warning(\"mywarn:test\",\"hello world warning\")\n","truncated":false}}
%---
