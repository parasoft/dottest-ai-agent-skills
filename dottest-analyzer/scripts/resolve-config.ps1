# =============================================================================
# resolve-config.ps1  —  Load, parse, and validate all dotTEST Analyzer settings
#
# This script is dot-sourced by the skill runner or other scripts.
# After sourcing, all resolved variables are set as environment variables
# in the calling session.
#
# On validation failure the script writes an ERROR message to stderr and
# exits with code 1.
#
# Environment variables set on success:
#   DOTTEST_HOME, SOLUTION_PATH, DOTTEST_TEST_CONFIGURATION, OUTPUT_DIR,
#   DOTTEST_COMMIT_FIXES, DISABLE_UNIT_TEST_VERIFICATION, DOTTEST_FILTER_RULE, DOTTEST_SETTINGS, 
#   DOTTEST_BASE_STATIC_ANALYSIS_REPORT, FIXES_BRANCH_NAME,
#   DOTTEST_BASE_UNIT_TEST_REPORT, DOTTEST_BASE_UNIT_TEST_COVERAGE,
#   DOTTEST_STATIC_NO_OF_MAX_FIXES, DOTTEST_FIX_ATTEMPTS, DOTTEST_REFERENCE_BRANCH,
#   GIT_BRANCH, GIT_WORKSPACE
# =============================================================================

$ErrorActionPreference = "Stop"

function Die($msg) {
    Write-Error "ERROR: $msg"
    exit 1
}

function SetIfUnset([string]$Name, [string]$Value) {
    $current = [Environment]::GetEnvironmentVariable($Name, "Process")
    if (-not $current -or $current -eq "") {
        [Environment]::SetEnvironmentVariable($Name, $Value, "Process")
    }
}

# =============================================================================
# Step 0: Load optional config file
# =============================================================================
$recognizedKeys = @(
    "DOTTEST_HOME", "SOLUTION_PATH", "DOTTEST_TEST_CONFIGURATION", "OUTPUT_DIR",
    "DOTTEST_COMMIT_FIXES", "DOTTEST_FILTER_RULE", "DOTTEST_SETTINGS",
    "DOTTEST_BASE_STATIC_ANALYSIS_REPORT", "FIXES_BRANCH_NAME",
    "DOTTEST_BASE_UNIT_TEST_REPORT", "DOTTEST_BASE_UNIT_TEST_COVERAGE",
    "DISABLE_UNIT_TEST_VERIFICATION", "DOTTEST_STATIC_NO_OF_MAX_FIXES",
    "DOTTEST_FIX_ATTEMPTS", "DOTTEST_REFERENCE_BRANCH"
)

$configPath = $env:DOTTEST_ANALYZER_CONFIG
if ($configPath -and $configPath -ne "") {
    if (-not (Test-Path $configPath -PathType Leaf)) {
        Die "DOTTEST_ANALYZER_CONFIG points to a file that does not exist: $configPath. Verify the path and retry."
    }
    foreach ($line in Get-Content $configPath) {
        $trimmed = $line.Trim()
        if ($trimmed -eq "" -or $trimmed.StartsWith("#")) { continue }
        $eqIdx = $trimmed.IndexOf("=")
        if ($eqIdx -lt 1) { continue }
        $key = $trimmed.Substring(0, $eqIdx).Trim()
        $val = $trimmed.Substring($eqIdx + 1).Trim()
        if ($recognizedKeys -contains $key) {
            SetIfUnset $key $val
        }
    }
}

# =============================================================================
# Step 1: Resolve required & optional settings
# =============================================================================

# ---- DOTTEST_HOME -------------------------------------------------------------
if (-not $env:DOTTEST_HOME -or $env:DOTTEST_HOME -eq "") {
    $dottestCmd = Get-Command "dottestcli.exe" -ErrorAction SilentlyContinue
    if (-not $dottestCmd) {
        $dottestCmd = Get-Command "dottestcli" -ErrorAction SilentlyContinue
    }
    if ($dottestCmd) {
        $env:DOTTEST_HOME = Split-Path $dottestCmd.Source -Parent
    } else {
        Die "DOTTEST_HOME is not set and dottestcli was not found on PATH. Set the DOTTEST_HOME environment variable and retry."
    }
}

# ---- SOLUTION_PATH -----------------------------------------------------------
if (-not $env:SOLUTION_PATH -or $env:SOLUTION_PATH -eq "" -or -not (Test-Path $env:SOLUTION_PATH -PathType Leaf)) {
    Die "SOLUTION_PATH is not set or does not point to an existing file. Set the SOLUTION_PATH environment variable and retry."
}

# ---- OUTPUT_DIR -----------------------------------------------------------
if (-not $env:OUTPUT_DIR -or $env:OUTPUT_DIR -eq "") {
    $env:OUTPUT_DIR = (Get-Location).Path
}
# Ensure OUTPUT_DIR exists
if (-not (Test-Path -Path $env:OUTPUT_DIR)) {
    New-Item -ItemType Directory -Path $env:OUTPUT_DIR -Force | Out-Null
    Write-Output "[resolve-config] Created output directory: $env:OUTPUT_DIR"
}

# ---- DOTTEST_TEST_CONFIGURATION -----------------------------------------------
if (-not $env:DOTTEST_TEST_CONFIGURATION -or $env:DOTTEST_TEST_CONFIGURATION -eq "") {
    $env:DOTTEST_TEST_CONFIGURATION = "builtin://Recommended Rules"
}

# ---- DOTTEST_COMMIT_FIXES -----------------------------------------------------
if (-not $env:DOTTEST_COMMIT_FIXES -or $env:DOTTEST_COMMIT_FIXES -eq "") {
    $env:DOTTEST_COMMIT_FIXES = "false"
}

# ---- DISABLE_UNIT_TEST_VERIFICATION -------------------------------------------
if (-not $env:DISABLE_UNIT_TEST_VERIFICATION -or $env:DISABLE_UNIT_TEST_VERIFICATION -eq "") {
    $env:DISABLE_UNIT_TEST_VERIFICATION = "false"
}

# ---- DOTTEST_FILTER_RULE -------------------------------------------
if (-not $env:DOTTEST_FILTER_RULE) { $env:DOTTEST_FILTER_RULE = "" }

# ---- DOTTEST_SETTINGS ---------------------------------------------------------
if ($env:DOTTEST_SETTINGS -and $env:DOTTEST_SETTINGS -ne "") {
    if (-not (Test-Path $env:DOTTEST_SETTINGS -PathType Leaf)) {
        Die "DOTTEST_SETTINGS points to a file that does not exist: $($env:DOTTEST_SETTINGS). Verify the path and retry."
    }
} else {
    $env:DOTTEST_SETTINGS = ""
}

# ---- DOTTEST_BASE_STATIC_ANALYSIS_REPORT ------------------------------------------------------
if ($env:DOTTEST_BASE_STATIC_ANALYSIS_REPORT -and $env:DOTTEST_BASE_STATIC_ANALYSIS_REPORT -ne "") {
    if (-not (Test-Path $env:DOTTEST_BASE_STATIC_ANALYSIS_REPORT -PathType Leaf)) {
        Die "DOTTEST_BASE_STATIC_ANALYSIS_REPORT points to a file that does not exist: $($env:DOTTEST_BASE_STATIC_ANALYSIS_REPORT). Verify the path and retry."
    }
} else {
    $env:DOTTEST_BASE_STATIC_ANALYSIS_REPORT = ""
}

# ---- DOTTEST_BASE_UNIT_TEST_REPORT ------------------------------------------------------
if ($env:DOTTEST_BASE_UNIT_TEST_REPORT -and $env:DOTTEST_BASE_UNIT_TEST_REPORT -ne "") {
    if (-not (Test-Path $env:DOTTEST_BASE_UNIT_TEST_REPORT -PathType Leaf)) {
        Die "DOTTEST_BASE_UNIT_TEST_REPORT points to a file that does not exist: $($env:DOTTEST_BASE_UNIT_TEST_REPORT). Verify the path and retry."
    }
} else {
    $env:DOTTEST_BASE_UNIT_TEST_REPORT = ""
}

# ---- DOTTEST_BASE_UNIT_TEST_COVERAGE ----------------------------------------------------
if ($env:DOTTEST_BASE_UNIT_TEST_COVERAGE -and $env:DOTTEST_BASE_UNIT_TEST_COVERAGE -ne "") {
    if (-not (Test-Path $env:DOTTEST_BASE_UNIT_TEST_COVERAGE -PathType Leaf)) {
        Die "DOTTEST_BASE_UNIT_TEST_COVERAGE points to a file that does not exist: $($env:DOTTEST_BASE_UNIT_TEST_COVERAGE). Verify the path and retry."
    }
} else {
    $env:DOTTEST_BASE_UNIT_TEST_COVERAGE = ""
}

# ---- FIXES_BRANCH_NAME -------------------------------------------
# If not set, leave empty — commits go directly to the currently checked-out branch.
# If set, substitute [timestamp] with the current timestamp before use.
if (-not $env:FIXES_BRANCH_NAME) {
    $env:FIXES_BRANCH_NAME = ""
} else {
    $env:FIXES_BRANCH_NAME = $env:FIXES_BRANCH_NAME -replace '\[timestamp\]', (Get-Date -Format 'yyyyMMddHHmmss')
}

# ---- DOTTEST_STATIC_NO_OF_MAX_FIXES ------------------------------------------
if (-not $env:DOTTEST_STATIC_NO_OF_MAX_FIXES -or $env:DOTTEST_STATIC_NO_OF_MAX_FIXES -eq "") {
    $env:DOTTEST_STATIC_NO_OF_MAX_FIXES = "5"
}
if (-not ($env:DOTTEST_STATIC_NO_OF_MAX_FIXES -as [int]) -or [int]$env:DOTTEST_STATIC_NO_OF_MAX_FIXES -lt 1) {
    Die "DOTTEST_STATIC_NO_OF_MAX_FIXES must be a positive integer. Current value: $($env:DOTTEST_STATIC_NO_OF_MAX_FIXES)."
}


# ---- DOTTEST_FIX_ATTEMPTS -----------------------------------------------------
if (-not $env:DOTTEST_FIX_ATTEMPTS -or $env:DOTTEST_FIX_ATTEMPTS -eq "") {
    $env:DOTTEST_FIX_ATTEMPTS = "2"
}
if (-not ($env:DOTTEST_FIX_ATTEMPTS -as [int]) -or [int]$env:DOTTEST_FIX_ATTEMPTS -lt 1) {
    Die "DOTTEST_FIX_ATTEMPTS must be a positive integer. Current value: $($env:DOTTEST_FIX_ATTEMPTS)."
}

# ---- DOTTEST_REFERENCE_BRANCH ----------------------------------------------------
if (-not $env:DOTTEST_REFERENCE_BRANCH) { $env:DOTTEST_REFERENCE_BRANCH = "" }

# Ensure git context variables do not carry stale values between runs
$env:GIT_BRANCH = ""
$env:GIT_WORKSPACE = ""

# Resolve git context and validate target branch when DOTTEST_REFERENCE_BRANCH is set
if ($env:DOTTEST_REFERENCE_BRANCH -and $env:DOTTEST_REFERENCE_BRANCH -ne "") {
    $solutionDir = Split-Path -Path $env:SOLUTION_PATH -Parent
    $gitCmd = Get-Command "git" -ErrorAction SilentlyContinue
    if (-not $gitCmd) {
        Die "DOTTEST_REFERENCE_BRANCH is set, but git is not available on PATH. Install git or unset DOTTEST_REFERENCE_BRANCH."
    }

    & git -C $solutionDir rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -ne 0) {
        Die "DOTTEST_REFERENCE_BRANCH is set, but the solution directory is not inside a git repository: $solutionDir"
    }

    $gitWorkspace = (& git -C $solutionDir rev-parse --show-toplevel).Trim()
    if (-not $gitWorkspace -or $LASTEXITCODE -ne 0) {
        Die "Failed to determine git workspace for solution directory: $solutionDir"
    }

    $gitBranch = (& git -C $solutionDir rev-parse --abbrev-ref HEAD).Trim()
    if (-not $gitBranch -or $LASTEXITCODE -ne 0) {
        Die "Failed to determine current git branch for solution directory: $solutionDir"
    }

    $target = $env:DOTTEST_REFERENCE_BRANCH
    & git -C $solutionDir show-ref --verify --quiet "refs/heads/$target"
    $hasLocalTarget = ($LASTEXITCODE -eq 0)
    $remoteTargetRefs = & git -C $solutionDir for-each-ref --format="%(refname)" "refs/remotes/*/$target"
    $hasRemoteTarget = ($LASTEXITCODE -eq 0) -and $remoteTargetRefs -and $remoteTargetRefs.Count -gt 0

    if (-not $hasLocalTarget -and -not $hasRemoteTarget) {
        Die "DOTTEST_REFERENCE_BRANCH '$target' does not exist in the repository."
    }

    $env:GIT_WORKSPACE = $gitWorkspace
    $env:GIT_BRANCH = $gitBranch
}

# =============================================================================
# Step 2: Verify dotTEST installation
# =============================================================================
$dottestExe = Join-Path $env:DOTTEST_HOME "dottestcli.exe"
if (-not (Test-Path $dottestExe)) {
    Die "dottestcli.exe not found in DOTTEST_HOME=$($env:DOTTEST_HOME). Verify the dotTEST installation path."
}

# =============================================================================
# Print resolved configuration
# =============================================================================
$configDisplay = if ($env:DOTTEST_ANALYZER_CONFIG -and $env:DOTTEST_ANALYZER_CONFIG -ne "") { $env:DOTTEST_ANALYZER_CONFIG } else { "(not set)" }
$filterDisplay = if ($env:DOTTEST_FILTER_RULE -and $env:DOTTEST_FILTER_RULE -ne "") { $env:DOTTEST_FILTER_RULE } else { "(not set)" }
$settingsDisplay = if ($env:DOTTEST_SETTINGS -and $env:DOTTEST_SETTINGS -ne "") { $env:DOTTEST_SETTINGS } else { "(not set)" }
$outputDisplay = if ($env:OUTPUT_DIR -and $env:OUTPUT_DIR -ne "") { $env:OUTPUT_DIR } else { "(not set)" }
$baseStaticAnalysisDisplay = if ($env:DOTTEST_BASE_STATIC_ANALYSIS_REPORT -and $env:DOTTEST_BASE_STATIC_ANALYSIS_REPORT -ne "") { $env:DOTTEST_BASE_STATIC_ANALYSIS_REPORT } else { "(not set)" }
$baseUnitTestDisplay = if ($env:DOTTEST_BASE_UNIT_TEST_REPORT -and $env:DOTTEST_BASE_UNIT_TEST_REPORT -ne "") { $env:DOTTEST_BASE_UNIT_TEST_REPORT } else { "(not set)" }
$baseCoverageDisplay = if ($env:DOTTEST_BASE_UNIT_TEST_COVERAGE -and $env:DOTTEST_BASE_UNIT_TEST_COVERAGE -ne "") { $env:DOTTEST_BASE_UNIT_TEST_COVERAGE } else { "(not set)" }
$maxFixesDisplay = if ($env:DOTTEST_STATIC_NO_OF_MAX_FIXES -and $env:DOTTEST_STATIC_NO_OF_MAX_FIXES -ne "") { $env:DOTTEST_STATIC_NO_OF_MAX_FIXES } else { "(not set)" }
$targetBranchDisplay = if ($env:DOTTEST_REFERENCE_BRANCH -and $env:DOTTEST_REFERENCE_BRANCH -ne "") { $env:DOTTEST_REFERENCE_BRANCH } else { "(not set)" }
$gitBranchDisplay = if ($env:GIT_BRANCH -and $env:GIT_BRANCH -ne "") { $env:GIT_BRANCH } else { "(not set)" }
$gitWorkspaceDisplay = if ($env:GIT_WORKSPACE -and $env:GIT_WORKSPACE -ne "") { $env:GIT_WORKSPACE } else { "(not set)" }

Write-Output @"
Resolved configuration:
  DOTTEST_ANALYZER_CONFIG             = $configDisplay
  DOTTEST_HOME                        = $($env:DOTTEST_HOME)
  SOLUTION_PATH                       = $($env:SOLUTION_PATH)
  OUTPUT_DIR                          = $outputDisplay
  DOTTEST_TEST_CONFIGURATION          = $($env:DOTTEST_TEST_CONFIGURATION)
  DOTTEST_COMMIT_FIXES                = $($env:DOTTEST_COMMIT_FIXES)
  DISABLE_UNIT_TEST_VERIFICATION      = $($env:DISABLE_UNIT_TEST_VERIFICATION)
  DOTTEST_FILTER_RULE                 = $filterDisplay
  DOTTEST_SETTINGS                    = $settingsDisplay
  DOTTEST_BASE_STATIC_ANALYSIS_REPORT = $baseStaticAnalysisDisplay
  DOTTEST_BASE_UNIT_TEST_REPORT       = $baseUnitTestDisplay
  DOTTEST_BASE_UNIT_TEST_COVERAGE     = $baseCoverageDisplay
  DOTTEST_STATIC_NO_OF_MAX_FIXES      = $maxFixesDisplay
  FIXES_BRANCH_NAME                   = $(if ($env:FIXES_BRANCH_NAME -and $env:FIXES_BRANCH_NAME -ne '') { $env:FIXES_BRANCH_NAME } else { '(current branch)' })
  DOTTEST_FIX_ATTEMPTS                = $($env:DOTTEST_FIX_ATTEMPTS)
  DOTTEST_REFERENCE_BRANCH            = $targetBranchDisplay
  GIT_BRANCH                          = $gitBranchDisplay
  GIT_WORKSPACE                       = $gitWorkspaceDisplay
"@