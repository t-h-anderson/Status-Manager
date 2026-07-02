classdef FileLog < statusMgr.internal.view.StatusSinkViewBase
    %FILELOG Append statuses to a log file.
    %
    % Two output formats are supported:
    %   "text"        Human-readable bracketed text (default).
    %                 Toggleable Include* fields control which columns
    %                 appear in each line.
    %   "json-lines"  One JSON object per line, with all the Status
    %                 fields. Easy to ingest with tools like jq or
    %                 jsondecode(readlines(...)). The Include* flags
    %                 are ignored in this format — every field is
    %                 emitted unconditionally for downstream tooling.
    %
    % Optional MaxBytes triggers rotation: when a write would push the
    % file past MaxBytes, the existing log is renamed by appending
    % "_1", "_2", ... (highest free index wins) before the basename's
    % extension, and a fresh log starts.

    properties
        IncludeTimestamp (1,1) logical = true
        IncludeUser (1,1) logical = true
        IncludeIdentifier (1,1) logical = true
        IncludeValue (1,1) logical = true
        LogFolder (1,1) string
        LogFilename (1,1) string
        Format (1,1) string {mustBeMember(Format, ["text", "json-lines"])} = "text"
        MaxBytes (1,1) double {mustBePositive} = Inf
    end

    methods

        function obj = FileLog(stack, nvp)
            arguments
                stack = statusMgr.Stack
                nvp.IncludeTimestamp (1,1) logical
                nvp.IncludeUser (1,1) logical
                nvp.IncludeIdentifier (1,1) logical
                nvp.IncludeValue (1,1) logical
                nvp.LogFolder (1,1) string {mustBeFolder} = pwd
                % Sentinel-default: the real filename depends on Format
                % (.jsonl for json-lines, .txt otherwise) and Format
                % isn't known yet here. Resolved in the constructor body.
                nvp.LogFilename (1,1) string = string(missing)
                nvp.Format (1,1) string ...
                    {mustBeMember(nvp.Format, ["text", "json-lines"])} = "text"
                nvp.MaxBytes (1,1) double {mustBePositive} = Inf
                nvp.ShowInfo (1,1) logical = true
                nvp.ShowWarnings (1,1) logical = true
                nvp.ShowErrors (1,1) logical = true
                nvp.ShowRunning (1,1) logical = true
                nvp.ShowSuccess (1,1) logical = true
                nvp.ShowIdle (1,1) logical = false
                nvp.HandleInputRequests (1,1) logical = true
                nvp.MinLevel (1,1) statusMgr.Level = statusMgr.Level.Trace
                nvp.IncludeIdentifiers (1,:) string = string.empty(1,0)
                nvp.ExcludeIdentifiers (1,:) string = string.empty(1,0)
            end

            % nvp before setStack: setStack seeds the stack's suppressed
            % identifiers into ExcludeIdentifiers, which set() would
            % otherwise overwrite.
            set(obj, nvp);
            obj.setStack(stack);

            if ismissing(obj.LogFilename)
                ext = ".txt";
                if obj.Format == "json-lines"
                    ext = ".jsonl";
                end
                obj.LogFilename = "Log_" + ...
                    string(datetime("now", Format="yyyyMMdd_HHmmss")) + ext;
            end

            logfile = fullfile(obj.LogFolder, obj.LogFilename);
            if isfile(logfile) && obj.Format == "text"
                writelines("", logfile, WriteMode="append"); % blank-line separator
            end

        end

        function tf = isVisible(~)
            tf = true;
        end

    end

    methods (Access = protected)
        function displayStatus(obj, status, ~)
            arguments
                obj (1,1) statusMgr.view.FileLog
                status (1,1) statusMgr.Status
                ~ % No cancellable option for a file log
            end
            obj.writeToFile(status);
        end

        function handleInputRequest(obj, status)
            % FileLog cannot supply interactive input; log the request and
            % leave it unclaimed so the stack returns the default value.
            obj.writeToFile(status);
        end

        function writeToFile(obj, status)
            switch obj.Format
                case "text"
                    line = obj.formatTextLine(status);
                case "json-lines"
                    line = obj.formatJsonLine(status);
            end
            obj.rotateIfOversize(strlength(line) + 1); % +1 for newline
            writelines(line, fullfile(obj.LogFolder, obj.LogFilename), ...
                WriteMode="append");
        end

        function line = formatTextLine(obj, status)
            line = "";

            if obj.IncludeTimestamp
                ts = string(datetime(status.Timestamp, Format="dd-MMM-yyyy HH:mm:ss"));
                line = line + "[" + ts + "] ";
            end

            if obj.IncludeUser
                line = line + "[" + status.User + "] ";
            end

            line = line + "[" + string(status.Type) + "] ";

            if obj.IncludeIdentifier
                if status.Identifier ~= ""
                    line = line + "[" + status.Identifier + "] ";
                end
            end

            if obj.IncludeValue
                if ~isnan(status.Value)
                    line = line + "[Value=" + status.Value + "] ";
                end
            end

            line = line + status.Message;
        end

        function line = formatJsonLine(~, status)
            % Emit a structured record. Include* flags are not applied
            % in JSON output — downstream tooling can filter columns.
            record = struct( ...
                "timestamp", string(datetime(status.Timestamp, Format="yyyy-MM-dd'T'HH:mm:ss")), ...
                "user", status.User, ...
                "type", string(status.Type), ...
                "identifier", status.Identifier, ...
                "value", status.Value, ...
                "message", status.Message);
            line = string(jsonencode(record));
        end

        function rotateIfOversize(obj, pendingBytes)
            % Rename the current log when the next write would push it
            % past MaxBytes. Appends "_N" before the extension to find
            % a free filename. Default MaxBytes=Inf means never rotate.
            if isinf(obj.MaxBytes)
                return
            end
            logfile = fullfile(obj.LogFolder, obj.LogFilename);
            if ~isfile(logfile)
                return
            end
            info = dir(logfile);
            if info.bytes + pendingBytes <= obj.MaxBytes
                return
            end
            [folder, base, ext] = fileparts(logfile);
            i = 1;
            while true
                rotated = fullfile(folder, base + "_" + i + ext);
                if ~isfile(rotated)
                    break
                end
                i = i + 1;
            end
            movefile(logfile, rotated);
        end

    end % methods

end % classdef
