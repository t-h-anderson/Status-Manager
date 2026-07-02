function installStatusManager(nvp)
% Install method to make sure Status Manager is installed and up-to-date
% Include in other projects' startup to automatically install this
% dependency
% Note: Add default toolbox path is "dependencies" folder

arguments
    nvp.RequiredVersion = ""
    nvp.ToolboxPath = "./dependencies";
end

toolboxName = "Status Manager";
toolboxNamesToMatch = [toolboxName, "StatusManager"];
requiredVersion = nvp.RequiredVersion;

% Get installed toolbox version
toolboxes = matlab.addons.toolbox.installedToolboxes;
toolboxNames = string({toolboxes.Name});
installedIdx = ismember(toolboxNames, toolboxNamesToMatch);

if any(installedIdx)
    installedVersion = string({toolboxes(installedIdx).Version});
else
    installedVersion = "";
end

% Return if toolbox is installed and it matches the required version
if any(installedIdx) && any(installedVersion == requiredVersion)
    fprintf("%s (Ver. %s) matches requirement.\n", toolboxName, requiredVersion);
    return
end

% Get available versions
tbxPath = fullfile(nvp.ToolboxPath, "*.mltbx");
tbxs = dir(tbxPath);

if isempty(tbxs)
    error("statusMgr:installStatusManager:noToolboxes", ...
        "No %s toolboxes available in %s.", toolboxName, nvp.ToolboxPath);
end

% Get list of available versions
vers = arrayfun(@(x) string(matlab.addons.toolbox.toolboxVersion(fullfile(x.folder, x.name))), tbxs);

if requiredVersion == ""
    % If specific version isn't required get latest
    [~, idx] = maxVer(vers);
    idx = find(idx, 1, "first");
    maxVersion = vers(idx);

    if any(maxVersion == installedVersion)
        fprintf("%s up-to-date (Ver. %s).\n", toolboxName, maxVersion);
        return
    end
else
    idx = find(vers == requiredVersion, 1, "first");

    if isempty(idx)
        error("statusMgr:installStatusManager:versionNotFound", ...
            "%s (Ver. %s) not found in %s.", toolboxName, nvp.RequiredVersion, nvp.ToolboxPath);
    end
end

tbxName = tbxs(idx).name;
latestTbxPath = fullfile(tbxs(idx).folder, tbxName);

matlab.addons.toolbox.installToolbox(latestTbxPath);
fprintf("%s (Ver. %s) installed.\n", toolboxName, vers(idx));

end


function [value, idx] = maxVer(vers)
arguments
    vers(1, :) string
end

% Split at points
splitUp = arrayfun(@(x) strsplit(x, "."), vers, "UniformOutput", false);

% Get number of version levels
levels = cellfun(@(x) numel(x), splitUp);
maxLevel = max(levels);

% Pad version levels with 0 if there is variation
for i = 1:numel(levels)
    levelsToAdd = maxLevel - levels(i);
    zeroPadding = repmat("0", 1, levelsToAdd);
    splitUp{i} = [splitUp{i}, zeroPadding];
end

% Get list of separated and padded version numbers
splitUp = vertcat(splitUp{:});

% Iteratively 'clear' rows that are not maximal
for i = 1:size(splitUp, 2)
    iMax = string(max(str2double(splitUp(:, i))));
    splitUp(splitUp(:, i) ~= iMax, :) = "";
end

% Get indices of noncleared rows
idx = any(strlength(splitUp) ~= 0, 2);

% Get max version
value = vers(idx);

end
