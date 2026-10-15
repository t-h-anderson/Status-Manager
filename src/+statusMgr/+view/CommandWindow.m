classdef CommandWindow < statusMgr.internal.view.StatusViewBase
    %CommandWindow View a status Stack in the command window

    properties (SetAccess = protected)
        RunningTimer timer
    end

    properties
        PreviousMessage (1,1) string = string(NaN)
        % When true, an identical successive message is replaced by a
        % single "." to indicate progress without spamming the terminal.
        ShowRepeatedAsDots (1,1) logical = true
    end

    methods

        function obj = CommandWindow(stack, nvp)
            arguments
                stack = statusMgr.Stack
                nvp.ShowInfo (1,1) logical = true
                nvp.ShowWarnings (1,1) logical = true
                nvp.ShowErrors (1,1) logical = true
                nvp.ShowRunning (1,1) logical = true
                nvp.ShowSuccess (1,1) logical = true
                nvp.ShowIdle (1,1) logical = false
                nvp.HandleInputRequests (1,1) logical = true
                nvp.ShowRepeatedAsDots (1,1) logical = true
                nvp.IncludeIdentifiers (1,:) string = string.empty(1,0)
                nvp.ExcludeIdentifiers (1,:) string = string.empty(1,0)
            end

            % Set view parent and stack properties
            obj.RefreshOnRemoval = false;
            obj.setStack(stack);
            set(obj, nvp);
        end

        function tf = isVisible(~)
            tf = true;
        end

        function delete(obj)
            % Destructor - delete any running timers before destroying.
            obj.clearRunning();
        end

    end

    methods (Access = protected)
        function clearDisplay(obj)
            obj.clearRunning();
        end

        function cleanupCompletedStatus(obj)
            if ~isempty(obj.IncomingStatus) && ...
                    (~isvalid(obj.IncomingStatus) || obj.IncomingStatus.IsComplete)
                obj.clearRunning();
            end
        end

        function beforeDisplay(obj)
            obj.clearRunning();
        end

        function displayBackgroundUpdate(obj, status)
            % Print progress beneath the top of the stack without touching
            % the running indicator, which belongs to the current status.
            if ismember(status.Type, [statusMgr.StatusType.Running, ...
                    statusMgr.StatusType.RunningCancellable])
                obj.writeToTerminal(status.Message);
            else
                displayBackgroundUpdate@statusMgr.internal.view.StatusViewBase(obj, status);
            end
        end

        function displayRunning(obj, status, ~)
            arguments
                obj (1,1) statusMgr.view.CommandWindow
                status (1,1) statusMgr.Status
                ~ % No cancellable option for the terminal
            end

            message = status.Message;
            obj.writeToTerminal(message);

            s = warning();
            warning("off");
            statusMgr.util.stopTimer(obj.RunningTimer);

            % Use a plain fprintf callback to avoid capturing obj in the closure.
            % Capturing obj would create a strong reference cycle (obj → timer → obj)
            % that prevents MATLAB from garbage-collecting the view when cleared.
            obj.RunningTimer = timer("TimerFcn", @(~,~)fprintf("."), ...
                "Period", 1, "TasksToExecute", inf, "ExecutionMode", "fixedRate");
            
            start(obj.RunningTimer);
            warning(s)
            
        end % displayRunning

        function clearRunning(obj)
            % Stop the auto-progress dot timer set up by displayRunning.
            % PreviousMessage is intentionally NOT reset here: that
            % belongs to writeToTerminal's repeated-message tracking,
            % which is independent of the running-progress timer.
            statusMgr.util.stopTimer(obj.RunningTimer);
        end

        function displayError(obj, status)
            arguments
                obj (1,1) statusMgr.view.CommandWindow
                status (1,1) statusMgr.Status
            end

            if ~isempty(status.Data) ...
                    && isa(status.Data, "MException")

                rep = string(status.Data.getReport);
                obj.writeToTerminal(rep, 2);
            else
                message = "Error: " + status.Message;
                obj.writeToTerminal(message, 2);
            end
        end

        function displayWarning(obj, status)
            arguments
                obj (1,1) statusMgr.view.CommandWindow
                status (1,1) statusMgr.Status
            end
            obj.writeToTerminal("Warning: " + status.Message, 2);
        end

        function displaySuccess(obj, status)
            arguments
                obj (1,1) statusMgr.view.CommandWindow
                status (1,1) statusMgr.Status
            end
            message = status.Message;
            obj.writeToTerminal(message);
        end

        function displayInfo(obj, status)
            arguments
                obj (1,1) statusMgr.view.CommandWindow
                status (1,1) statusMgr.Status
            end
            message = status.Message;
            obj.writeToTerminal(message);
        end

        function displayIdle(obj,status)
            arguments
                obj (1,1)
                status (1,1) statusMgr.Status
            end
            message = status.Message;
            obj.writeToTerminal(message);
        end

        function handleInputRequest(obj, status)
            arguments
                obj (1,1) statusMgr.view.CommandWindow
                status (1,1) statusMgr.Status
            end

            status.transitionInputState(statusMgr.StatusType.AwaitingInput);

            prompt = status.Message;
            if prompt == "", prompt = "Enter value"; end
            defaultVal = string(status.Data);

            raw = obj.readUserInput(prompt + ": ");
            if raw == ""
                raw = defaultVal;
            end

            status.transitionInputState(statusMgr.StatusType.ValueSupplied, raw);
        end

        function raw = readUserInput(~, prompt)
            % Read a single line from stdin. Extracted as a seam so tests
            % can subclass and override without monkey-patching `input`.
            raw = string(input(prompt, "s"));
        end

        function writeToTerminal(obj, message, id)
            arguments
                obj (1,1)
                message (1,1) string
                id (1,1) double {mustBeMember(id, [1,2])} = 1 % 1 for normal, 2 for error
            end
            if id == 2 || message ~= obj.PreviousMessage || ~obj.ShowRepeatedAsDots
                % First time we've seen this message (or the toggle is
                % off): print it on its own line.
                fprintf(id, "%s\n", message);
            else
                % Same message as last time: collapse to a single "."
                % so successive identical updates don't spam the terminal.
                fprintf(".");
            end
            obj.PreviousMessage = message;
        end

    end % methods

end % classdef
