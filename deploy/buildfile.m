function plan = buildfile()
%BUILDFILE Status Manager build file.

% Copyright 2024-2025 The MathWorks, Inc.

% Define the build plan.
plan = buildplan( localfunctions() );

% Set the package task to run by default.
plan.DefaultTasks = "package";

% Add the clean task.
plan("clean") = matlab.buildtool.tasks.CleanTask();

% Add a test task to run the unit and integration tests, as CI does.
% Results and coverage go to the (ignored) test artifacts folder.
projectRoot = fileparts( plan.RootFolder );
testFolder = fullfile( projectRoot, "test" );
artifactsFolder = fullfile( testFolder, "artifacts" );
plan("test") = matlab.buildtool.tasks.TestTask( testFolder, ...
    "Strict", true, ...
    "Description", "Assert that all tests across the project pass.", ...
    "SourceFiles", fullfile( projectRoot, "src" ), ...
    "TestResults", fullfile( artifactsFolder, "Results.html" ), ...
    "OutputDetail", "Concise" );
plan("test").addCodeCoverage( fullfile( artifactsFolder, "Coverage.html" ) );

% The test task depends on the check task.
plan("test").Dependencies = "check";

end % buildfile

function checkTask( context )
% Check the source code and project for any issues.

% Set the project root as the folder in which to check for any static code
% issues.
projectRoot = context.Plan.RootFolder;
codeIssuesTask = matlab.buildtool.tasks.CodeIssuesTask( projectRoot, ...
    "IncludeSubfolders", true, ...
    "Configuration", "factory", ...
    "Description", ...
    "Assert that there are no code issues in the project.", ...
    "WarningThreshold", 0 );
codeIssuesTask.analyze( context )

% Update the project dependencies.
prj = currentProject();
prj.updateDependencies()

% Run the checks.
checkResults = table( prj.runChecks() );

% Log any failed checks.
passed = checkResults.Passed;
notPassed = ~passed;
if any( notPassed )
    disp( checkResults(notPassed, :) )
else
    fprintf( "** All project checks passed.\n\n" )
end % if

% Check that all checks have passed.
assert( all( passed ), "buildfile:ProjectIssue", ...
    "At least one project check has failed. " + ...
    "Resolve the failures shown above to continue." )

end % checkTask

function packageTask( context )
% Package the Toolbox.

% Project root directory.
prj = currentProject();
projectRoot = fileparts(context.Plan.RootFolder);

% Import and tweak the toolbox metadata.
toolboxJSON = fullfile( projectRoot, "deploy", "tbxdescription.json" );
meta = jsondecode( fileread( toolboxJSON ) );
meta.ToolboxMatlabPath = fullfile( projectRoot, meta.ToolboxMatlabPath );
meta.ToolboxFolder = fullfile( projectRoot, meta.ToolboxFolder );
meta.ToolboxImageFile = fullfile( projectRoot, "deploy", meta.ToolboxImageFile );
meta.ToolboxGettingStartedGuide = fullfile( projectRoot, "doc",...
    meta.ToolboxGettingStartedGuide );
mltbx = fullfile( projectRoot, "releases", ...
    meta.ToolboxShortName + " " + meta.ToolboxVersion + ".mltbx" );
meta.OutputFile = mltbx;

% Define the toolbox packaging options.
toolboxFolder = meta.ToolboxFolder;
toolboxID = meta.Identifier;
meta = rmfield( meta, ["Identifier", "ToolboxFolder", "ToolboxShortName"] );

opts = matlab.addons.toolbox.ToolboxOptions( ...
    toolboxFolder, toolboxID, meta );

% Remove unnecessary files.
tf = startsWith( opts.ToolboxFiles, fullfile(projectRoot, "src") ) | ...
    startsWith( opts.ToolboxFiles, fullfile(projectRoot, "doc") ) ;
opts.ToolboxFiles(~tf) = [];

% Remove files not in the project
opts.ToolboxFiles(~ismember(opts.ToolboxFiles, [prj.Files.Path])) = [];

% Package the toolbox.
matlab.addons.toolbox.packageToolbox( opts )
fprintf( 1, "[+] %s\n", opts.OutputFile )

% Add the license.
licenseText = fileread( fullfile( projectRoot, "license.txt" ) );
mlAddonSetLicense( char( opts.OutputFile ), ...
    struct( "type", 'BSD', "text", licenseText ) );

end % packageTask
