# =============================================================================
# verify.ps1  —  Verify solution build and unit tests
#
# Called by the dotTEST Analyzer skill to verify that the solution builds
# and unit tests pass. Behavior depends on whether baseline files are provided:
#
# SCENARIO 1: No baseline files (DOTTEST_BASE_UNIT_TEST_REPORT and DOTTEST_BASE_UNIT_TEST_COVERAGE not set)
#   - Runs unit tests with coverage using "builtin://Run VSTest Tests with coverage"
#   - Saves results to parasoft-dottest-reports\baseline\unit-tests
#   - Sets DOTTEST_BASE_UNIT_TEST_REPORT and DOTTEST_BASE_UNIT_TEST_COVERAGE env vars for subsequent steps
#
# SCENARIO 2: Baseline files provided (both DOTTEST_BASE_UNIT_TEST_REPORT and DOTTEST_BASE_UNIT_TEST_COVERAGE set)
#   a) Initial verification (Step 2, no FIX_NUMBER): Only builds the solution with dotnet/devenv
#   b) Fix verification (Step 7, has FIX_NUMBER): Runs tests with TIA using baseline
#
# SCENARIO 3: DISABLE_UNIT_TEST_VERIFICATION is set to "true"
#   - Always only builds the solution with dotnet/devenv/msbuild, never runs tests
#
# Environment variables provided by the skill:
#   DOTTEST_HOME                       – dotTEST installation directory
#   SOLUTION_PATH                      – Absolute path to the solution file
#   DOTTEST_SETTINGS                   – Absolute path to dotTEST settings file (may be empty)
#   DOTTEST_BASE_UNIT_TEST_REPORT      – Baseline report.xml for TIA (may be empty)
#   DOTTEST_BASE_UNIT_TEST_COVERAGE    – Baseline coverage.xml for TIA (may be empty)
#   OUTPUT_DIR                         – Absolute path to the directory where output will be stored (may be empty)
#   FIX_NUMBER                         – Set during fix verification (Step 7), empty during initial verification (Step 2)
#   DISABLE_UNIT_TEST_VERIFICATION     – Set to "true" to skip all unit test execution (defaults to "false")
#
# Exit codes:
#   0  – Verification completed successfully
#   1  – Build or tests failed
# =============================================================================

$ErrorActionPreference = "Stop"

Write-Host "[verify] SOLUTION_PATH = $env:SOLUTION_PATH"
Write-Host "[verify] DOTTEST_HOME  = $env:DOTTEST_HOME"

Set-Location -Path $env:OUTPUT_DIR

# ---------------------------------------------------------------------------
# Determine verification mode
# ---------------------------------------------------------------------------
$disableTests = ($env:DISABLE_UNIT_TEST_VERIFICATION -and $env:DISABLE_UNIT_TEST_VERIFICATION -eq "true")
$hasBaseline = ($env:DOTTEST_BASE_UNIT_TEST_REPORT -and $env:DOTTEST_BASE_UNIT_TEST_REPORT -ne "") -and `
               ($env:DOTTEST_BASE_UNIT_TEST_COVERAGE -and $env:DOTTEST_BASE_UNIT_TEST_COVERAGE -ne "")
$isFixVerification = ($env:FIX_NUMBER -and $env:FIX_NUMBER -ne "")

$buildOnlyMode = $disableTests -or ($hasBaseline -and -not $isFixVerification)

if ($buildOnlyMode) {
    if ($disableTests) {
        # SCENARIO 3: Unit tests disabled - just build
        Write-Host "[verify] DISABLE_UNIT_TEST_VERIFICATION is set. Verifying build only..."
    } else {
        # SCENARIO 2a: Baseline provided + initial verification - just build
        Write-Host "[verify] Baseline files provided. Verifying build only..."
    }
    $buildMethods = @(
        @{ Command = "devenv"; Args = @("$env:SOLUTION_PATH", "/build"); Display = "devenv `"$env:SOLUTION_PATH`" /build" },
        @{ Command = "dotnet"; Args = @("build", "$env:SOLUTION_PATH"); Display = "dotnet build `"$env:SOLUTION_PATH`"" },
        @{ Command = "msbuild"; Args = @("$env:SOLUTION_PATH"); Display = "msbuild `"$env:SOLUTION_PATH`"" }
    )

    $attemptedBuild = $false
    $buildSucceeded = $false
    $exitCode = 1

    foreach ($method in $buildMethods) {
        $cmd = Get-Command $method.Command -ErrorAction SilentlyContinue
        if (-not $cmd) {
            Write-Host "[verify] '$($method.Command)' not found. Trying next build method..."
            continue
        }

        $attemptedBuild = $true
        Write-Host "[verify] Running: $($method.Display)"
        & $method.Command @($method.Args) > "$env:OUTPUT_DIR\build_output.txt"
        $exitCode = $LASTEXITCODE

        if ($exitCode -eq 0) {
            $buildSucceeded = $true
            break
        }

        Write-Warning "[verify] $($method.Command) build failed with code $exitCode. Trying next build method..."
    }

    if (-not $attemptedBuild) {
        Write-Error "ERROR: None of devenv, dotnet, or msbuild were found. Cannot build solution."
        exit 1
    }

    if (-not $buildSucceeded) {
        Write-Error "ERROR: Solution build failed with code $exitCode using all available build methods."
        exit $exitCode
    }
    
    Write-Host "[verify] Build completed successfully."
    exit 0
    
} else {
    # SCENARIO 1 / 2b: Run tests with coverage (baseline creation or TIA fix verification)
    if ($hasBaseline) {
        # SCENARIO 2b: Baseline provided + fix verification - run tests with TIA
        Write-Host "[verify] Running tests with TIA using baseline files..."
        $reportDir = Join-Path $env:OUTPUT_DIR "parasoft-dottest-reports\fix-$($env:FIX_NUMBER)\unit-tests"
    } else {
        # SCENARIO 1: No baseline - create baseline by running tests with coverage
        Write-Host "[verify] No baseline files provided. Running tests with coverage to create baseline..."
        $reportDir = Join-Path $env:OUTPUT_DIR "parasoft-dottest-reports\baseline\unit-tests"
    }

    if (-not (Test-Path -Path $reportDir)) {
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
        Write-Host "[verify] Created report directory: $reportDir"
    }

    $dottestExe = Join-Path $env:DOTTEST_HOME "dottestcli.exe"
    $argList = @(
        "-solution", $env:SOLUTION_PATH,
        "-config",   "builtin://Run VSTest Tests with Coverage",
        "-report",   $reportDir
    )

    # Add TIA baseline files for fix verification
    if ($hasBaseline) {
        $argList += @("-referenceReportFile", $env:DOTTEST_BASE_UNIT_TEST_REPORT)
        $argList += @("-referenceCoverageFile", $env:DOTTEST_BASE_UNIT_TEST_COVERAGE)
    }

    if ($env:DOTTEST_SETTINGS -and $env:DOTTEST_SETTINGS -ne "") {
        $argList += @("-settings", $env:DOTTEST_SETTINGS)
    }

    if ($env:DOTTEST_REFERENCE_BRANCH -and $env:DOTTEST_REFERENCE_BRANCH -ne "") {
        $argList += @("-property", "scope.scontrol=true")
        $argList += @("-property", "scope.scontrol.files.filter.mode=branch")
        $argList += @("-property", "scontrol.rep1.type=git")
        $argList += @("-property", "scontrol.rep1.git.workspace=$($env:GIT_WORKSPACE)")
        $argList += @("-property", "scontrol.rep1.git.branch=$($env:GIT_BRANCH)")
        $argList += @("-property", "scope.scontrol.ref.branch=$($env:DOTTEST_REFERENCE_BRANCH)")
    }

    Write-Host "[verify] Running: $dottestExe $($argList -join ' ')"

    & $dottestExe @argList > "$reportDir\dottestcli_output.txt"
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        Write-Error "ERROR: Unit tests failed with code $exitCode."
        exit $exitCode
    }

    if (-not $hasBaseline) {
        Write-Host "[verify] Baseline created."

        # Set baseline paths for subsequent steps
        $baselineReport = Join-Path $reportDir "report.xml"
        $baselineCoverage = Join-Path $reportDir "coverage.xml"

        $env:DOTTEST_BASE_UNIT_TEST_REPORT = $baselineReport
        $env:DOTTEST_BASE_UNIT_TEST_COVERAGE = $baselineCoverage

        Write-Host "DOTTEST_BASE_UNIT_TEST_REPORT=$baselineReport"
        Write-Host "DOTTEST_BASE_UNIT_TEST_COVERAGE=$baselineCoverage"
    }

    Write-Host "[verify] Tests completed successfully."
        $reportXml = Join-Path $reportDir "report.xml"
        Write-Host "REPORT_XML=$reportXml"

    exit 0
}