# Status Manager

[![Open in MATLAB Online](https://www.mathworks.com/images/responsive/global/open-in-matlab-online.svg)](https://matlab.mathworks.com/open/github/v1?repo=t-h-anderson/AppStatusStack&project=AppStatusStack.prj&file=doc/GettingStarted.m)

Status Manager is a lightweight MATLAB&reg; toolbox for tracking and displaying application state in MVC-style apps. Push typed status objects (Running, Error, Warning, Success, …) onto a shared stack; one or more views observe the stack and automatically update progress dialogs, command-window output, or log files in response.

## Setup

### MathWorks Products (https://www.mathworks.com)

Requires MATLAB release R2025a or newer.

- [MATLAB](https://www.mathworks.com/products/matlab.html)

## Installation

Install Status Manager directly from the MATLAB Add-On Explorer, or install the `.mltbx` file manually:

1. Download `StatusManager 1.5.0.mltbx` from the [releases](releases/) folder.
2. Double-click the file in MATLAB to open the Add-On installer and follow the prompts.

**Programmatic installation** — to pin a specific version as a dependency of another project, copy `src/installStatusManager.m` into that project's startup script:

```matlab
installStatusManager(RequiredVersion="1.5.0", ToolboxPath="dependencies")
```

## Getting Started

Open the interactive getting-started guide:

```matlab
open doc/GettingStarted.m
```

Or follow the quick-start steps below.

**1. Create a status stack**

```matlab
stack = statusMgr.Stack();
```

**2. Attach a view**

```matlab
% GUI progress dialogs and alerts (recommended for App Designer apps)
f = uifigure();
statusMgr.view.Popup(f, stack);

% Inline non-modal status bar — give it a sized container (e.g. a
% row in your own uigridlayout) and it auto-fills it
g = uigridlayout(f, [2, 1], "RowHeight", {"1x", 28});
mainContent = uipanel(g);
statusMgr.view.StatusBar(g, stack);

% Plain-text output to the command window
statusMgr.view.CommandWindow(stack);

% Append every status to a log file
statusMgr.view.FileLog(stack, LogFolder=pwd);
```

**3. Push and remove statuses**

```matlab
% Second output is an onCleanup object — status is removed when it goes out of scope
[status, cleanup] = stack.addStatus("Running", Message="Loading data…");
loadMyData();
clear cleanup  % removes the Running status; view updates automatically

% Or remove explicitly
stack.removeStatus(status);
```

**4. Capture errors and warnings automatically**

```matlab
result = stack.run(@myFunction);                    % Running → clears on success, Error on failure
result = stack.run(@myFunction, Args={a, b});       % pass function arguments via Args
result = stack.run(@myFunction, CatchErrors=false); % rethrow instead of capturing
```

**5. Cooperative cancellation**

```matlab
% The RunningCancellable Status is passed as the first argument.
% Cancel-aware views (e.g. the Popup progress dialog Cancel button)
% call status.complete() when the user requests cancellation; the
% running function polls status.IsComplete and bails out.
stack.runCancellable(@(status) doWork(status));

function doWork(status)
    for i = 1:N
        if status.IsComplete; return; end
        % ... do step i ...
    end
end
```

**6. Background work (parfeval + DataQueue)**

```matlab
% Convenience: parfeval on the backgroundPool and monitor the future.
[future, status] = stack.runInBackground(@myFcn, ...
    Args={a, b}, NumOutputs=1, Message="Loading data");

% Status is RunningCancellable while the future runs; the StatusBar's
% Cancel button cancels the future. fetchOutputs gets the result.
result = fetchOutputs(future);

% Streaming progress: pass a DataQueue both to your worker (so it can
% send updates) and to runInBackground (so the monitor can listen).
q = parallel.pool.DataQueue;
stack.runInBackground(@workerWithProgress, ...
    Args={q, x}, ProgressQueue=q);

function out = workerWithProgress(q, x)
    for i = 1:N
        send(q, i/N);    % numeric → status Value
        % ... or: send(q, "Step " + i)         % string → Message
        % ... or: send(q, struct(Value=i/N, Message="Step " + i))
    end
    out = ...;
end

% Or monitor a future you already have:
future = parfeval(backgroundPool, @longJob, 1, x);
stack.monitorFuture(future, Message="Long job");
```

### Available status types

| Type | Popup view behaviour |
|---|---|
| `Running` | Indeterminate progress dialog |
| `RunningCancellable` | Progress dialog with Cancel button |
| `Error` | Alert dialog with red icon |
| `Warning` | Alert dialog with yellow icon |
| `Success` | Alert dialog with green icon |
| `Info` | Alert dialog with info icon |
| `Idle` | Clears any active dialog (default state) |

The enum also defines `RequestingInput`, `AwaitingInput`, and `ValueSupplied`. These are **transitional, internal states** used to drive the user-input handshake (see *User input* below) and are marked `Hidden` on `statusMgr.StatusType` — do not push them directly.

### Key features

- **Stack semantics** — statuses stack; removing the top status reveals the one beneath, so nested operations compose naturally.
- **Multiple views** — attach as many views as needed to the same stack; each updates independently.
- **Array stacks** — broadcast a status to several stacks at once: `[stack1, stack2].addStatus("Running")`.
- **Suppression** — hide specific identifiers without removing them. Exact match or glob patterns:
  ```matlab
  stack.suppressIdentifier("my:warning:id")    % exact
  stack.suppressIdentifier("myapp:network:*")  % any identifier with that prefix
  stack.suppressIdentifier("*timeout*")        % anywhere
  ```
- **Monitorable classes** — any class that extends `statusMgr.monitorable.Monitorable` can emit statuses that are automatically forwarded to a watching stack.
- **User input** — request a string from the user through whichever view is active, with a timeout and default fallback. Use `statusMgr.view.InputField` for an inline, non-modal edit field embedded in your app (doubles as a status line: shows the current message read-only, becomes editable when input is requested), or `statusMgr.view.Popup` for a modal dialog.
- **Cancellation** — `stack.runCancellable(@(status) work(status))` runs work cooperatively; cancel-aware views call `status.complete()`, user code polls `status.IsComplete` (or calls `status.throwIfComplete()` for error-style propagation).
- **Recording view** — `statusMgr.view.RecordingView` captures every status it sees into a `RecordedStatuses` array, useful for activity logs in apps and assertions in tests.
- **Background work** — `stack.runInBackground(@fcn, Args={a, b})` launches a `parfeval` future, pushes a `RunningCancellable` status, streams progress through a `DataQueue`, and converts failures into Error statuses. Cancel-aware views cancel the future. Or use `stack.monitorFuture(future)` for a future you already have. `runInBackground` and synchronous `stack.run(@fcn, Args={a, b})` both take worker/function arguments as a cell via `Args={...}`.
- **Per-view filters** — every view supports `IncludeIdentifiers` / `ExcludeIdentifiers` glob lists that complement the stack-level `suppressIdentifier`. Have a CommandWindow show only `myapp:debug:*` while a FileLog records everything.
- **Structured / rotating logs** — `FileLog` accepts `Format="json-lines"` for one-JSON-object-per-line output, and `MaxBytes` triggers rotation (`Log.txt` → `Log_1.txt`) when the file would otherwise grow without bound.

## Examples

See [`doc/GettingStarted.m`](doc/GettingStarted.m) for a full walkthrough including progress bars, cancellable operations, error capture, and monitorable classes.

## License

The license is available in the [license.txt](license.txt) file in this GitHub repository.

## Community Support

[MATLAB Central](https://www.mathworks.com/matlabcentral)

Copyright 2025 The MathWorks, Inc.
