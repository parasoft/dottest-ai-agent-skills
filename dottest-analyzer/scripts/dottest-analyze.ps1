# =============================================================================
# dottest-analyze.ps1 - Runs Parasoft dotTEST static analysis
#
# PURPOSE:
#   Executes dotTEST static analysis on a .NET solution and generates a report.
#   Used for both initial baseline analysis and fix verification runs.
#
# REQUIRED ENVIRONMENT VARIABLES (must be set before invoking):
#   DOTTEST_HOME               - Path to dotTEST installation (e.g., "C:\Program Files\Parasoft\dotTEST\2026.1")
#   SOLUTION_PATH              - Full path to .sln file to analyze
#
# OPTIONAL ENVIRONMENT VARIABLES:
#   DOTTEST_TEST_CONFIGURATION             - Test configuration name (default: "builtin://Recommended Rules")
#   DOTTEST_SETTINGS                       - Path to dotTEST settings file (empty = not used)
#   DOTTEST_INCLUDE                        - Specific file path to analyze (empty = analyze all)
#   DOTTEST_EXCLUDE                        - Specific file path to exclude from analysis (empty = analyze all)
#   DOTTEST_BASE_STATIC_ANALYSIS_REPORT    - Path to baseline report.xml for fix verification (empty = initial analysis)
#   DOTTEST_BASELINE_MODE                  - Must be true for baseline or false for fix verification
#
# OUTPUT:
#   Creates report.xml in one of two locations:
#   - Initial analysis: [solution_dir]\parasoft-dottest-reports\baseline\report.xml
#   - Fix verification: [solution_dir]\parasoft-dottest-reports\static-analysis\report.xml
#   
#   Prints the absolute path on the LAST line as: REPORT_XML=<path>
#
# EXIT CODES:
#   0 - Analysis completed successfully, report.xml created
#   1 - Analysis failed (compilation error, dotTEST error, or file system error)
# =============================================================================

# Stop execution on any error
$ErrorActionPreference = "Stop"

# Log the configuration being used
Write-Output "[dottest-analyze] SOLUTION_PATH = $env:SOLUTION_PATH"
Write-Output "[dottest-analyze] DOTTEST_HOME  = $env:DOTTEST_HOME"

# Change working directory to solution directory
Set-Location -Path $env:OUTPUT_DIR

if ($env:DOTTEST_BASELINE_MODE -notin @("true", "false")) {
    Write-Error "ERROR: DOTTEST_BASELINE_MODE must be explicitly set to 'true' or 'false'."
    exit 1
}

# =============================================================================
# STEP 1: Determine report output directory
# =============================================================================
# Two scenarios:
# 1. Fix verification run: DOTTEST_BASELINE_MODE is false
#    -> Save to: [solution_dir]\parasoft-dottest-reports\static-analysis\
#    -> This report will be compared against the baseline

# 2. Initial baseline analysis: DOTTEST_BASELINE_MODE is true or unset
#    -> Save to: [solution_dir]\parasoft-dottest-reports\baseline\
#    -> This report will be used as baseline for future fix verifications

$isBaselineRun = ($env:DOTTEST_BASELINE_MODE -eq "true")
$isFixRun = -not $isBaselineRun
$hasFixedFiles = ($env:DOTTEST_FIXED_FILES -and $env:DOTTEST_FIXED_FILES -ne "")
$baselineReportDir = Join-Path $env:OUTPUT_DIR "parasoft-dottest-reports\baseline\static-analysis"
$baselineReportPath = Join-Path $baselineReportDir "report.xml"

if ($isFixRun -and -not $hasFixedFiles) {
    Write-Error "ERROR: Fix verification run requested, but DOTTEST_FIXED_FILES is not set."
    exit 1
}

if ($isBaselineRun -and $env:DOTTEST_BASE_STATIC_ANALYSIS_REPORT) {
    Write-Output "[dottest-analyze] Baseline report already provided at: $($env:DOTTEST_BASE_STATIC_ANALYSIS_REPORT)"
    Write-Output "[dottest-analyze] Skipping initial analysis - reusing existing baseline."

    Write-Output "REPORT_XML=$($env:DOTTEST_BASE_STATIC_ANALYSIS_REPORT)"
    exit 0
}

if ($isFixRun) {
    # Fix verification: use the shared static-analysis report directory
    $reportDir = Join-Path $env:OUTPUT_DIR "parasoft-dottest-reports\static-analysis"
    Write-Output "[dottest-analyze] Mode: Fix verification (comparing against baseline)"

    if (-not $env:DOTTEST_BASE_STATIC_ANALYSIS_REPORT -or
        -not (Test-Path -LiteralPath $env:DOTTEST_BASE_STATIC_ANALYSIS_REPORT -PathType Leaf)) {
        Write-Error "ERROR: DOTTEST_BASE_STATIC_ANALYSIS_REPORT does not point to an existing baseline report."
        exit 1
    }
} else {
    # Initial analysis: Create baseline report directory
    $reportDir = $baselineReportDir
    Write-Output "[dottest-analyze] Mode: Initial baseline analysis"
}

# Create report directory if it doesn't exist (including all parent directories)
if (-not (Test-Path -Path $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    Write-Output "[dottest-analyze] Created report directory: $reportDir"
} else {
    Write-Output "[dottest-analyze] Using existing report directory: $reportDir"
}

# =============================================================================
# STEP 2: Build dotTEST command-line arguments
# =============================================================================
# Construct the argument list dynamically based on environment variables
# Path to dotTEST CLI executable
$dottestExe = Join-Path $env:DOTTEST_HOME "dottestcli.exe"

# Start with mandatory arguments
$argList = @(
    "-solution", $env:SOLUTION_PATH,               # Solution file to analyze
    "-config",   $env:DOTTEST_TEST_CONFIGURATION,  # Test configuration (rules to apply)
    "-report",   $reportDir                        # Output directory for report.xml
)

# Add optional arguments if environment variables are set

# Scope selection: first run uses DOTTEST_INCLUDE; fix verification runs use DOTTEST_FIXED_FILES
if ($isFixRun -or $hasFixedFiles) {
    # Fix verification: scope to the exact files that were changed
    $includes = $env:DOTTEST_FIXED_FILES -split ';'
    foreach ($include in $includes) {
        $includeValue = $include.Trim()
        if ($includeValue -ne "") {
            $argList += @("-include", $includeValue)
        }
    }
    Write-Output "[dottest-analyze] Analyzing fixed files: $($env:DOTTEST_FIXED_FILES)"
} else {
    # First run: use DOTTEST_INCLUDE scope from user request
    if ($env:DOTTEST_INCLUDE -and $env:DOTTEST_INCLUDE -ne "") {
        $includes = $env:DOTTEST_INCLUDE -split ';'
        foreach ($include in $includes) {
            $includeValue = $include.Trim()
            if ($includeValue -ne "") {
                $argList += @("-include", $includeValue)
            }
        }
        Write-Output "[dottest-analyze] Analyzing specific files: $($env:DOTTEST_INCLUDE)"
    }
    # DOTTEST_EXCLUDE: Limit analysis to specific file(s)
    # Used during fix verification to exclude files based on user input
    # Supports semicolon-separated list of files and/or patterns
    if ($env:DOTTEST_EXCLUDE -and $env:DOTTEST_EXCLUDE -ne "") {
        $excludes = $env:DOTTEST_EXCLUDE -split ';'
        foreach ($exclude in $excludes) {
            $excludeValue = $exclude.Trim()
            if ($excludeValue -ne "") {
                $argList += @("-exclude", $excludeValue)
            }
        }
        Write-Output "[dottest-analyze] Analyzing specific resources: $($env:DOTTEST_EXCLUDE)"
    }
}

# DOTTEST_SETTINGS: Custom settings file
# Can specify custom configurations, exclusions, or analysis parameters
if ($env:DOTTEST_SETTINGS -and $env:DOTTEST_SETTINGS -ne "") {
    $argList += @("-settings", $env:DOTTEST_SETTINGS)
    Write-Output "[dottest-analyze] Using settings file: $($env:DOTTEST_SETTINGS)"
}

# DOTTEST_BASE_STATIC_ANALYSIS_REPORT: Baseline report for comparison
# Used during fix verification to compare results against the initial baseline
if ($env:DOTTEST_BASE_STATIC_ANALYSIS_REPORT -and $env:DOTTEST_BASE_STATIC_ANALYSIS_REPORT -ne "") {
    $argList += @("-property", "goal.ref.report.file=$($env:DOTTEST_BASE_STATIC_ANALYSIS_REPORT)")
    Write-Output "[dottest-analyze] Using baseline report: $($env:DOTTEST_BASE_STATIC_ANALYSIS_REPORT)"
}

# DOTTEST_BUILDER: Builder to use for compilation
# Maps DEVENV -> visualstudio, DOTNET -> dotnet, MSBUILD -> msbuild
if ($env:DOTTEST_BUILDER -and $env:DOTTEST_BUILDER -ne "") {
    $builderMap = @{ "DEVENV" = "visualstudio"; "DOTNET" = "dotnet"; "MSBUILD" = "msbuild" }
    $builderValue = $builderMap[$env:DOTTEST_BUILDER.ToUpper()]
    $argList += @("-property", "dottest.build.builder_id=$builderValue")
    Write-Output "[dottest-analyze] Using builder: $builderValue"
}

if ($env:DOTTEST_REFERENCE_BRANCH -and $env:DOTTEST_REFERENCE_BRANCH -ne "") {
    $argList += @("-property", "scope.scontrol=true")
    $argList += @("-property", "scope.scontrol.files.filter.mode=branch")
    $argList += @("-property", "scontrol.rep1.type=git")
    $argList += @("-property", "scontrol.rep1.git.workspace=$($env:GIT_WORKSPACE)")
    $argList += @("-property", "scontrol.rep1.git.branch=$($env:GIT_BRANCH)")
    $argList += @("-property", "scope.scontrol.ref.branch=$($env:DOTTEST_REFERENCE_BRANCH)")
}

# verify.ps1 may already have built the solution, either through a configured
# builder or through dottestcli while running tests. Avoid performing the same
# build again. If verification was skipped, leave this unset/false so analysis
# performs the required build itself.
$argList += @("-nobuild")


Write-Output "[dottest-analyze] Executing: $dottestExe $($argList -join ' ')"

# =============================================================================
# STEP 3: Execute dotTEST analysis
# =============================================================================
# Use a unique capture file for every invocation. A previous dotTEST process
# may still have its capture file open, so archiving it with Rename-Item (or
# overwriting it with redirection) is not safe.
$captureId = "{0:yyyyMMdd-HHmmssfff}" -f (Get-Date)
$dottestCliOutputPath = Join-Path $reportDir "dottestcli_output-$captureId.txt"

# Run the dotTEST CLI with the constructed arguments
$env:PARASOFT_DOTTEST_AUTOFIX_MODE = "true"
& $dottestExe @argList > $dottestCliOutputPath

# Capture the exit code from dotTEST
$exitCode = $LASTEXITCODE

# =============================================================================
# STEP 4: Handle analysis result
# =============================================================================

if ($exitCode -ne 0) {
    # Analysis failed - could be due to:
    # - Compilation errors in the solution
    # - dotTEST configuration errors
    # - License issues
    # - File system errors
    Write-Error "ERROR: dotTEST analysis exited with code $exitCode."
    exit $exitCode
}

# Analysis succeeded
Write-Output "[dottest-analyze] Analysis completed successfully."

# Construct and output the path to the generated report.xml
# The skill will parse this line to locate the report for downstream processing
$reportXml = Join-Path $reportDir "report.xml"
Write-Output "REPORT_XML=$reportXml"

exit 0
