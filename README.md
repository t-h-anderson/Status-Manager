# Status Manager

[![Open in MATLAB Online](https://www.mathworks.com/images/responsive/global/open-in-matlab-online.svg)](https://matlab.mathworks.com/open/github/v1?repo=t-h-anderson/AppStatusStack&project=AppStatusStack.prj&file=doc/GettingStarted.m)

Status Manager is a lightweight MATLAB&reg; toolbox for tracking and displaying application state in MVC-style apps. Push typed status objects (Running, Error, Warning, Success, …) onto a shared stack; one or more views observe the stack and automatically update progress dialogs, command-window output, or log files in response.

## Setup

### MathWorks Products (https://www.mathworks.com)

Requires MATLAB release R2025a or newer.

- [MATLAB](https://www.mathworks.com/products/matlab.html)

## Installation

Install Status Manager directly from the MATLAB Add-On Explorer, or install the `.mltbx` file manually:

1. Download `StatusManager 1.6.0.mltbx` from the [releases](releases/) folder.
2. Double-click the file in MATLAB to open the Add-On installer and follow the prompts.

**Programmatic installation** — to pin a specific version as a dependency of another project, copy `src/installStatusManager.m` into that project's startup script:

```matlab
installStatusManager(RequiredVersion="1.6.0", ToolboxPath="dependencies")
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

% Name the progress status and announce success
stack.run(@saveProject, Args={project}, ...
    Message="Saving project…", SuccessMessage="Project saved");
```

Function arguments are only accepted through `Args={...}`. Positional arguments
are rejected, so a forwarded string such as `"Message"` can never be mistaken
for a `run` option. See [Running work](#running-work) for the full contract.

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

**7. UI callbacks**

```matlab
% Report anything a callback throws or warns through the stack's views,
% instead of losing it to the command window.
button.ButtonPushedFcn = @(~, ~) stack.invoke(@() app.loadFile());
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
- **Named groups** — `statusMgr.util.StatusManager` keeps a registry of named stacks with their views, so separate parts of an app can share a stack without passing it around. See [Named groups](#named-groups-statusmanager).
- **Scoped diagnostics** — library code can report warnings and errors to whichever stack the current workflow is using, without a reference to it. See [Routing diagnostics](#routing-diagnostics).

## Running work

`stack.run(@fcn)` and `stack.runCancellable(@(status) fcn(status))` wrap a call in a progress status and turn its outcome into statuses.

| Option | Default | Effect |
|---|---|---|
| `Args` | `{}` | Cell of arguments forwarded to the function. The only way to pass arguments. |
| `Message`, `Identifier` | `"Running: <function>"`, `""` | Text and identifier of the progress status. |
| `SuccessMessage`, `SuccessIdentifier` | `""` | When set, a Success status is published if the call succeeds. |
| `SuccessIsTemporary` | `true` | Whether that Success status is replaced by the next status pushed. |
| `CatchErrors` | `true` | Publish an error as an Error status. `false` rethrows it instead. |
| `CatchWarnings` | `true` | Publish the last MATLAB warning issued during the call as a Warning status. |

The order of events is fixed: the progress status is removed first, then the captured warning is published, then the Error or Success status. A view therefore never shows the outcome underneath a stale progress dialog.

If the progress status's completion callback throws, the run counts as failed: no Success is published, and the failure follows `CatchErrors`. If the function also failed, its error is the one reported, with the completion failure attached as a cause.

While the function runs, the stack is the active [diagnostics route](#routing-diagnostics). If the function deletes the stack (for example by closing its app), the outcome is reported to the enclosing route, or to the Default group if there is none.

`stack.invoke(@action)` is the equivalent for UI callbacks. It routes diagnostics to the stack, publishes the last native warning, and publishes an uncaught exception as an Error status instead of rethrowing it. Nothing is published when the callback succeeds without warnings.

## Named groups (StatusManager)

`statusMgr.util.StatusManager` is a registry of named groups. Each group is a stack plus the views attached to it:

```matlab
import statusMgr.util.StatusManager
stack = StatusManager.make("Editor", PopupParent=fig, EnableCommandWindow=true);
stack = StatusManager.get("Editor");               % the same stack, from anywhere
StatusManager.addFileLog("Editor", LogFolder=logDir);
StatusManager.addView("Editor", app.StatusBar);    % a view you created yourself
```

**Ownership.** A group owns the views it creates (`make`, `addPopup`, `addCommandWindow`, `addFileLog`) and any view added with `addViewScoped(..., Delete=true)`. Views you pass to `addView` or `addViewScoped` stay yours.

| Operation | Owned views | Your views | Stack |
|---|---|---|---|
| `removeView(name, idx)` | Deleted | Disconnected, still usable | Kept |
| `removeViews(name, ..., Delete=false)` | Disconnected | Disconnected | Kept |
| `removeViews(name, ..., Delete=true)` | Deleted | Deleted | Kept |
| `clear(name)` / `clear()` | Disconnected now; deleted once the group is released | Disconnected | Kept |
| `shutdown()` | Deleted | Disconnected | Deleted |

A disconnected view stops listening and closes any dialog, progress bar or timer it was showing. Call `view.setStack(otherStack)` to reuse it. `clear` never deletes a stack, so a handle returned by `make` stays valid. `shutdown` is the only operation that destroys stacks. It acts on the groups registered at the time; groups removed earlier by `clear` are already inactive, and whoever still holds them controls their lifetime.

**Tests.** The hidden `snapshot()` and `restore(token)` methods isolate the registry between tests:

```matlab
token = statusMgr.util.StatusManager.snapshot();
testCase.addTeardown(@() statusMgr.util.StatusManager.restore(token));
```

`restore` reconnects the snapshotted groups' views to their original stacks without replaying log entries. Groups created since the snapshot are dropped and their views disconnected.

## Routing diagnostics

Library code that has no stack handle can still report through the status views:

```matlab
statusMgr.util.StatusManager.warning("mylib:io:retry", "Retrying %s", file);
statusMgr.util.StatusManager.reportError(exception);  % caller still decides whether to rethrow
```

These go to the innermost active route:

```matlab
route = statusMgr.util.StatusManager.withStack(stack);  % active while `route` exists
```

Routes nest, and leaving a scope restores the caller's route, even when an error unwinds it. `run`, `runCancellable` and `invoke` set a route for the duration of the call. With no active route, diagnostics go to the Default group. If that group does not exist yet, they create it with a command-window view; call `make("Default", ...)` early to configure it differently. The message is only passed through `sprintf` when format arguments are supplied, so a literal `%` or a Windows path is printed unchanged.

## Writing a custom view

Subclass `statusMgr.internal.view.StatusViewBase` and implement `isVisible`, `displayInfo`, `displayRunning(status, cancellable)`, `displayError`, `displayWarning`, `displaySuccess`, `displayIdle` and `handleInputRequest`. If the view treats every type the same (a log, say), subclass `statusMgr.internal.view.StatusSinkViewBase` and implement `displayStatus(status, cancellable)` instead.

Choose a display model by setting `RefreshOnRemoval` in the constructor, before calling `setStack`:

- **Display views** (`true`, the default; `Popup`, `StatusBar`, `InputField`) show the status on top of the stack and redraw when a status is removed. Updates to statuses below the top are ignored. The exception is when a filtered status sits on top: the view keeps showing, and updating, the status underneath it.
- **Log views** (`false`; `CommandWindow`, `FileLog`, `RecordingView`) record each status as it is added or updated, including updates below the top, and ignore removals so nothing is logged twice.

The base class runs every display through the `Show*` flags and the identifier filters before anything on screen is replaced, so a filtered status never tears down the current display. Optional protected hooks:

| Hook | Called when |
|---|---|
| `beforeDisplay()` | A new status is about to replace the current display. |
| `cleanupCompletedStatus()` | On every event, even while the view is hidden. Release resources belonging to completed statuses. |
| `clearDisplay()` | The view is disconnected or rebound. Release all active displays; do not delete the view. |
| `displayBackgroundUpdate(status)` | Log views: a status below the top was updated. Avoid side effects tied to the current status. |
| `updateDisplayedStatus(status)` | Display views: the status currently on screen was updated while a filtered status sits on top. |

`setStack([])` must disconnect the view without deleting it. When a view is bound to a stack, display views show its current status; log views do not replay history.

Views listen to the stack's `StatusUpdated` event. Its `statusMgr.monitorable.StatusEventData` carries the `Status` and a `Change`:

| `Change` | Raised by | `Status` |
|---|---|---|
| `"Added"` | `addStatus`, `add` | The new status |
| `"Updated"` | `updateStatus`, background progress | The updated status, which may be below the top |
| `"Refresh"` | `removeStatus` and completion | The new top of the stack |

## Behaviour notes

- **Completion callbacks.** `status.complete()` runs every `CompletionFcn` and raises `Completed` even if one throws. Afterwards it rethrows the first failure, with any others attached as causes. `removeStatus` across several stacks finishes cleaning up every stack before it rethrows.
- **Background progress.** Progress sent on a `ProgressQueue` updates the status and notifies views whether or not the status is on top. When the future finishes, the monitor waits up to 2 seconds for queued progress to be delivered before completing the status, so the final update is not lost. A queue shared with other producers cannot hold a status open indefinitely.
- **Pending input on disconnect.** If an `InputField` or `Popup` that is collecting input for `requestInput` is disconnected (by `clear`, `removeView` or `shutdown`), the request is answered with its `DefaultValue` instead of waiting for the timeout.
- **Hidden figures.** Completed progress dialogs are cleaned up even while the parent figure is hidden.
- **Command window output.** `CommandWindow` prints warnings to standard error without raising a MATLAB warning of its own. Identical consecutive messages collapse to dots (`ShowRepeatedAsDots`, on by default), except warnings and errors, which are always printed in full.

## Examples

See [`doc/GettingStarted.m`](doc/GettingStarted.m) for a full walkthrough including progress bars, cancellable operations, error capture, and monitorable classes.

## License

The license is available in the [license.txt](license.txt) file in this GitHub repository.

## Community Support

[MATLAB Central](https://www.mathworks.com/matlabcentral)

Copyright 2025 The MathWorks, Inc.
