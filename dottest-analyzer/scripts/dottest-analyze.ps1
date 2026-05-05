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
#   DOTTEST_TEST_CONFIGURATION - Test configuration name (default: "builtin://Recommended Rules")
#   DOTTEST_SETTINGS           - Path to dotTEST settings file (empty = not used)
#   DOTTEST_INCLUDE            - Specific file path to analyze (empty = analyze all)
#   DOTTEST_EXCLUDE            - Specific file path to exclude from analysis (empty = analyze all)
#   DOTTEST_REF_REPORT_FILE    - Path to baseline report.xml for fix verification (empty = initial analysis)
#   DOTTEST_REF_REPORT_EXCLUDE - Set to "false" for fix verification (empty = initial analysis)
#   FIX_NUMBER                 - Sequential fix number (e.g., "1", "2", "3") for fix verification runs
#
# OUTPUT:
#   Creates report.xml in one of two locations:
#   - Initial analysis: [solution_dir]\parasoft-dottest-reports\baseline\report.xml
#   - Fix verification: [solution_dir]\parasoft-dottest-reports\fix[FIX_NUMBER]\report.xml
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
Write-Host "[dottest-analyze] SOLUTION_PATH = $env:SOLUTION_PATH"
Write-Host "[dottest-analyze] DOTTEST_HOME  = $env:DOTTEST_HOME"

# Change working directory to solution directory
Set-Location -Path $env:OUTPUT_DIR

# =============================================================================
# STEP 1: Determine report output directory
# =============================================================================
# Two scenarios:
# 1. Fix verification run: Reference report file is provided
#    -> Save to: [solution_dir]\parasoft-dottest-reports\fix[N]\
#    -> This report will be compared against the baseline

# 2. Initial baseline analysis: No reference report file provided
#    -> Save to: [solution_dir]\parasoft-dottest-reports\baseline\
#    -> This report will be used as baseline for future fix verifications

if ($env:DOTTEST_REF_REPORT_FILE -and $env:DOTTEST_REF_REPORT_FILE -ne "") {
    # Fix verification: Create numbered fix report directory
    $reportDir = Join-Path $env:OUTPUT_DIR "parasoft-dottest-reports\fix-$($env:FIX_NUMBER)\static-analysis"
    Write-Host "[dottest-analyze] Mode: Fix verification (comparing against baseline)"
} else {
    # Initial analysis: Create baseline report directory
    $reportDir = Join-Path $env:OUTPUT_DIR "parasoft-dottest-reports\baseline\static-analysis"
    Write-Host "[dottest-analyze] Mode: Initial baseline analysis"
}

# Create report directory if it doesn't exist (including all parent directories)
if (-not (Test-Path -Path $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    Write-Host "[dottest-analyze] Created report directory: $reportDir"
} else {
    Write-Host "[dottest-analyze] Using existing report directory: $reportDir"
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
$isFixRun = ($env:FIX_NUMBER -and $env:FIX_NUMBER -ne "")
$hasFixedFiles = ($env:DOTTEST_FIXED_FILES -and $env:DOTTEST_FIXED_FILES -ne "")
if ($isFixRun -or $hasFixedFiles) {
    # Fix verification: scope to the exact files that were changed
    $includes = $env:DOTTEST_FIXED_FILES -split ';'
    foreach ($include in $includes) {
        $includeValue = $include.Trim()
        if ($includeValue -ne "") {
            $argList += @("-include", $includeValue)
        }
    }
    Write-Host "[dottest-analyze] Analyzing fixed files: $($env:DOTTEST_FIXED_FILES)"
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
        Write-Host "[dottest-analyze] Analyzing specific files: $($env:DOTTEST_INCLUDE)"
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
        Write-Host "[dottest-analyze] Analyzing specific resources: $($env:DOTTEST_EXCLUDE)"
    }
}

# DOTTEST_SETTINGS: Custom settings file
# Can specify custom configurations, exclusions, or analysis parameters
if ($env:DOTTEST_SETTINGS -and $env:DOTTEST_SETTINGS -ne "") {
    $argList += @("-settings", $env:DOTTEST_SETTINGS)
    Write-Host "[dottest-analyze] Using settings file: $($env:DOTTEST_SETTINGS)"
}

# DOTTEST_REF_REPORT_FILE: Baseline report for comparison
# Used during fix verification to compare results against the initial baseline
if ($env:DOTTEST_REF_REPORT_FILE -and $env:DOTTEST_REF_REPORT_FILE -ne "") {
    $argList += @("-property", "goal.ref.report.file=$($env:DOTTEST_REF_REPORT_FILE)")
    Write-Host "[dottest-analyze] Using baseline report: $($env:DOTTEST_REF_REPORT_FILE)"
}

# DOTTEST_REF_REPORT_EXCLUDE: Control which findings to include in comparison
# Set to "false" during fix verification to include all findings relative to baseline
if ($env:DOTTEST_REF_REPORT_EXCLUDE -and $env:DOTTEST_REF_REPORT_EXCLUDE -ne "") {
    $argList += @("-property", "goal.ref.report.findings.exclude=$($env:DOTTEST_REF_REPORT_EXCLUDE)")
}


if ($env:DOTTEST_REFERENCE_BRANCH -and $env:DOTTEST_REFERENCE_BRANCH -ne "") {
    $argList += @("-property", "scope.scontrol=true")
    $argList += @("-property", "scope.scontrol.files.filter.mode=branch")
    $argList += @("-property", "scontrol.rep1.type=git")
    $argList += @("-property", "scontrol.rep1.git.workspace=$($env:GIT_WORKSPACE)")
    $argList += @("-property", "scontrol.rep1.git.branch=$($env:GIT_BRANCH)")
    $argList += @("-property", "scope.scontrol.ref.branch=$($env:DOTTEST_REFERENCE_BRANCH)")
}

Write-Host "[dottest-analyze] Executing: $dottestExe $($argList -join ' ')"

# =============================================================================
# STEP 3: Execute dotTEST analysis
# =============================================================================
# Run the dotTEST CLI with the constructed arguments
& $dottestExe @argList > "$reportDir\dottestcli_output.txt"

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
Write-Host "[dottest-analyze] Analysis completed successfully."

# Construct and output the path to the generated report.xml
# The skill will parse this line to locate the report for downstream processing
$reportXml = Join-Path $reportDir "report.xml"
Write-Host "REPORT_XML=$reportXml"

exit 0