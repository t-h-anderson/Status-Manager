function plan = buildfile()
%BUILDFILE Chart Examples build file.

% Copyright 2024-2025 The MathWorks, Inc.

% Define the build plan.
plan = buildplan( localfunctions() );

% Set the package task to run by default.
plan.DefaultTasks = "package";

% Add the clean task.
plan("clean") = matlab.buildtool.tasks.CleanTask();

% Add a test task to run the unit tests for the project. Generate and save
% a coverage report.
projectRoot = plan.RootFolder;
testFolder = fullfile( projectRoot, "tbx", "charts", "tests" );
codeFolder = fullfile( projectRoot, "tbx", "charts", "charts"  );
plan("test") = matlab.buildtool.tasks.TestTask( testFolder, ...
    "Strict", true, ...
    "RunOnlyImpactedTests", true, ...
    "Description", "Assert that all impacted tests " + ...
    "across the project pass.", ...
    "SourceFiles", codeFolder, ...
    "TestResults", "reports/Results.html", ...
    "LoggingLevel", "Verbose", ...
    "OutputDetail", "Verbose" );
plan("test").addCodeCoverage( "reports/Coverage.html", ...
    "MetricLevel", "mcdc" );

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

function activateLinks( file )
%ACTIVATELINKS Convert the Live Script hyperlinks to JavaScript-enabled
%links within the specified HTML file.

arguments ( Input )
    file(1, 1) string {mustBeFile}
end % arguments ( Input )

% Read the file contents.
htmlFileContents = string( fileread( file ) );

% Replace the commands within the anchors.

% Extract the anchors.
anchors = extractBetween( htmlFileContents, "<a href = ""matlab:", ">", ...
    "Boundaries", "inclusive" );

% Extract the commands.
commands = extractBetween( anchors, """", """" );

% Format the JavaScript-enabled anchors.
replacementAnchors = "<a href = ""#"" onclick=""handleClick(" + ...
    "'" + commands + "'" + "); return false;"">";

% Replace the original anchors with the new anchors.
for k = 1 : numel( anchors )
    htmlFileContents = replace( htmlFileContents, ...
        anchors(k), replacementAnchors(k) );
end % for

% Insert the JavaScript block.
jsFile = fullfile( chartsRoot(), "app", "html", "activateLinks.js" );
jsCode = fileread( jsFile );
htmlFileContents = insertBefore( htmlFileContents, "</body>", ...
    "<script type = ""text/javascript"">" + jsCode + "</script>" );

% Replace the file contents.
fileID = fopen( file, "w" );
fprintf( fileID, "%s", htmlFileContents );
fclose( fileID );

end % activateLinks