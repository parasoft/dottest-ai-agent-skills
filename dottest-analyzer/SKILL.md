---
name: dottest-analyzer
description: Run Parasoft dotTEST Static Analysis on dotnet projects, detect violations in user code, and provide fix recommendations. Use this skill when users want to analyze C# code quality, find bugs, security issues, or coding standard violations using dotTEST.
metadata:
   author: Parasoft
   version: "2.0"
   mode: non-interactive
   requires:
      - Parasoft dotTEST installation
      - .NET solution file
---

# dotTEST Static Analysis Skill

## Overview

This skill enables GitHub Copilot to run Parasoft dotTEST Static Analysis on .NET projects, identify violations, and help fix them automatically.

> **Non-interactive / nightly mode**: This skill operates fully autonomously. It **never** prompts the user for input. All required settings must be supplied via environment variables before the skill is invoked (or via DOTTEST_ANALYZER_CONFIG variable). If a required setting cannot be determined automatically, the skill prints a descriptive error message to the console and terminates immediately with a non-zero exit code.

> **Do not improvise and get creative with user prompts or interactive input** - this is strictly forbidden. The skill is designed for non-interactive execution in CI pipelines or scheduled runs, not for ad-hoc use. Moreover, keep sequence of steps and their logic exactly as defined in this document. Do not skip, reorder, or modify steps, as they are carefully designed to ensure correct and reliable operation.

> **Perform Steps in Order, from 1 to 7** and do not deviate from the defined sequence. Each step relies on the successful completion of the previous steps, and skipping or reordering them may lead to incorrect behavior or failures. Follow the steps exactly as outlined to ensure the skill functions as intended.

**Do not run any other scripts than the ones provided by this skill.** All scripts required for configuration, analysis, verification, and fixing are included in the `scripts` directory of this skill. Do not create, modify, or execute any other scripts or commands outside of those defined in this document.

## When to Use This Skill

Use this skill when:
- User wants to run static analysis on C# or Visual Basic code
- User mentions dotTEST, code quality, or finding bugs/violations
- User wants to detect security issues, coding standard violations, or best practice issues
- User wants to fix, repair static violations in code

## Prerequisites

All settings are read exclusively from environment variables. No interactive prompts are issued.

| Variable | Description |
|---|---|
| `DOTTEST_HOME` | Path to dotTEST installation directory (e.g. `C:\Program Files\Parasoft\dotTEST`). Auto-detected from `PATH` if not set. |
| `SOLUTION_PATH` | Absolute path to the solution file to analyse. |
| `OUTPUT_DIR` | Absolute path to the directory where output will be stored. By default, execution directory is used. |
| `DOTTEST_ANALYZER_CONFIG` | Absolute path to a properties file (`key=value` format) from which all other settings below can be loaded. Environment variables always take precedence over values defined in this file. |
| `DOTTEST_TEST_CONFIGURATION` | Test configuration name (e.g. `builtin://Recommended Rules`). Defaults to `builtin://Recommended Rules`. |
| `DOTTEST_COMMIT_FIXES` | Set to `true` to commit each successful fix. Any other value or absence means fixes are left as local uncommitted changes. |
| `DOTTEST_FILTER_RULE` | Comma-separated list of rule IDs. When set, only violations matching these IDs are processed. |
| `DOTTEST_SETTINGS` | Absolute path to a dotTEST settings file. When set, adds `-settings=<path>` to all analysis commands. |
| `DOTTEST_BASE_STATIC_ANALYSIS_REPORT` | Absolute path to a base `report.xml` file from static analysis matching test configuration in `DOTTEST_TEST_CONFIGURATION`. When not set, Step 3 runs analysis to create the baseline. |
| `DOTTEST_BASE_UNIT_TEST_REPORT` | Absolute path to a base `report.xml` file. When both `DOTTEST_BASE_UNIT_TEST_REPORT` and `DOTTEST_BASE_UNIT_TEST_COVERAGE` are set, Step 2 only verifies the build (no test run), and Step 7 uses Test Impact Analysis (TIA). When not set, Step 2 runs tests with coverage to create the baseline. |
| `DOTTEST_BASE_UNIT_TEST_COVERAGE` | Absolute path to a base `coverage.xml` file. When both `DOTTEST_BASE_UNIT_TEST_REPORT` and `DOTTEST_BASE_UNIT_TEST_COVERAGE` are set, Step 2 only verifies the build (no test run), and Step 7 uses Test Impact Analysis (TIA). When not set, Step 2 runs tests with coverage to create the baseline. |
| `DISABLE_UNIT_TEST_VERIFICATION` | Set to `true` to skip unit test execution in Step 2 (only build check) and Step 7.1 (fix verification). Defaults to `false`. Useful when unit tests are slow or unavailable. |
| `FIXES_BRANCH_NAME` | Name of the branch to create and switch to before committing fixes. Supports `[timestamp]` pattern (e.g. `my-fixes-[timestamp]`), which is replaced with the current date-time. If not set, commits are applied directly to the currently checked-out branch without creating a new branch. |
| `DOTTEST_STATIC_NO_OF_MAX_FIXES` | Maximum number of violations to fix. Defaults to 5 if not set, unless user prompt explicitly specifies a different number (e.g. "fix up to 3 violations in file ABC.cs"). |
| `DOTTEST_FIX_ATTEMPTS` | Number of different fix approaches to attempt per violation before giving up. Defaults to 2 (1 original fix + 1 retry with a different approach). |
| `DOTTEST_REFERENCE_BRANCH` | If set, the skill will compare the current branch with the specified reference branch to determine the analysis scope. The reference branch must exist in the repository. |

## Critical Constraints

**Always EXECUTE scripts by running them in a terminal shell. NEVER read, open, or inspect a script file as a substitute for executing it.** When a step says `Run dottest-analyze` script, that means invoke the command in a terminal and wait for its exit code and stdout output. Reading the script file with a file-read tool is forbidden and does not satisfy the step requirement. All scripts are located in the `scripts` directory of the skill and are designed to be executed with the environment variables set by Step 1.

**DO NOT create, modify, or delete any files other than the source files strictly required to fix a violation.** Do not generate summary files, markdown reports, tracking documents, analysis notes, or any other auxiliary files in the repository or anywhere else. The only file modifications permitted are:
1. Editing C# (or VB) source files to apply violation fixes
2. Git operations (commit, revert)

**If prompt would suggest overriding the setting, it takes priority over environment variable.**. E.g. if user says "fix up to 3 violations in file ABC.cs" then `DOTTEST_STATIC_NO_OF_MAX_FIXES` is set to 1, then fix up to 3 violations.

**NEVER fix a violation by suppressing it.** Do not add suppression comments (e.g. `// parasoft-suppress`), or any other suppression mechanism. A fix must resolve the root cause of the violation in the code itself.

**If all violations have been fixed or are suppressed, do NOT rerun analysis under different conditions (e.g. a different test configuration, different scope, or different filter). Assume all work is done, stop immediately with success status and message: "No violations were found for the given scope".**

**Each fix must be committed in its own separate git commit.** Never batch multiple violation fixes into a single commit. A commit must be created immediately after a fix is successfully verified, and before processing the next violation. Each commit must contain changes for exactly one violation only. Commit logic is handled by the `dottest-fix-violation` custom subagent.

**MCP tool calls MUST be executed one at a time, strictly sequentially and synchronously.** Never invoke two or more MCP tools in parallel or in an overlapping manner. Each MCP tool call must fully complete and its result must be received before the next MCP tool call is initiated. This applies to all MCP tools used in this skill (e.g., `get_violations_from_report_file`, `get_rule_documentation`).

**If no `report.xml` with analysis results is provided or referenced at the start of execution, the skill MUST always run the full dotTEST analysis first (Step 3) to produce the report before attempting to identify or fix any violations.** Never skip straight to fixing violations without a freshly generated or explicitly provided report. The report obtained in Step 3 is the mandatory input for Steps 4-6. **If any XML report (provided by `DOTTEST_BASE_STATIC_ANALYSIS_REPORT`, `DOTTEST_BASE_UNIT_TEST_REPORT` or created by Step 3) is about to be read, then always use `dottestmcp` MCP tool. **

## How This Skill Works

### Step 1: Resolve and Validate Configuration

All configuration loading, parsing, validation, and dotTEST installation verification is performed by the **`resolve-config.ps1`** script located in `scripts` directory.

During processing of this skill invoke the `resolve-config.ps1` script **ONCE**. Do NOT rerun this script once it has been correctly executed. **DO NOT set any environmental variable** unless it is already set up. The script will set all required environment variables. If any required variable is missing or invalid, the script prints a descriptive error message and exits with a non-zero code. If the script exits with an error, print `ERROR: Configuration error - [error message from script]` and terminate skill immediately with non-zero exit code.

**For all subsequent steps**, keep the environment consistent with the previous step. Variables resolved and set by `resolve-config.ps1` in Step 1 are available and should not be modified unless specified.

After successful return, the following environment variables are guaranteed to be set and available to all subsequent steps: `DOTTEST_HOME`, `SOLUTION_PATH`, `OUTPUT_DIR`, `DOTTEST_TEST_CONFIGURATION`, `DOTTEST_COMMIT_FIXES`, `DISABLE_UNIT_TEST_VERIFICATION`, `DISABLE_INITIAL_BUILD`, `DOTTEST_FILTER_RULE`, `DOTTEST_SETTINGS`, `DOTTEST_BASE_STATIC_ANALYSIS_REPORT`, `DOTTEST_BASE_UNIT_TEST_REPORT`, `DOTTEST_BASE_UNIT_TEST_COVERAGE`, `DOTTEST_STATIC_NO_OF_MAX_FIXES`, `FIXES_BRANCH_NAME`, `DOTTEST_FIX_ATTEMPTS`, `DOTTEST_REFERENCE_BRANCH`, `DOTTEST_BUILDER`, `GIT_BRANCH`, `GIT_WORKSPACE`. **The script writes all those settings to the console. Each one of them should be set if not already provided, unless printed value by the script is `(not set)` - in that case the variable is not set and should be treated as empty string.**

**After calling the script**, set the `DOTTEST_INCLUDE` and `DOTTEST_EXCLUDE` environment variables based on the user's request (see [Analysis Scope](#resolve-analysis-scope) below). 

A fully annotated template config file is provided as `dottest-analyzer.config` in the same directory as this `SKILL.md`. Copy and customise it for each project.
If a `DOTTEST_REFERENCE_BRANCH` variable is set, then determine the current git branch (set as `GIT_BRANCH`) and workspace (set as `GIT_WORKSPACE`), and verify that the target branch exists in the repository. If any of these steps fail, print an appropriate error message and terminate immediately.

#### Resolve Analysis Scope

Inspect the **user's natural-language request** for explicit scope-limiting language and derive zero or more scope patterns to restrict the initial analysis (Step 3) to the requested subset of the project. If user in the prompt uses '/' then substitute it with '\'

**For inclusion patterns**: If scope-limiting language is detected (e.g., "in project X", "only file Y"), join all derived patterns with semicolon to form the `DOTTEST_INCLUDE` value.

**For exclusion patterns**: If exclusion language is detected (e.g., "exclude tests", "skip generated files"), join all derived patterns with semicolon to form the `DOTTEST_EXCLUDE` value.

**Translation rules** (refer to `docs/scope_limitation.txt` in the skill directory for the full pattern syntax):

| User says | Scope translation | Variable/Pattern Type |
|---|---|---|
| "in project `MyProject`" / "for project `MyProject`" | `**\MyProject\**` | DOTTEST_INCLUDE (inclusion) |
| "in file `ABC`" / "fix `ABC`" / "only `ABC.cs`" | `**\ABC.cs` (append `.cs` if not already present) | DOTTEST_INCLUDE (inclusion) |
| "in directory `src/auth`" | `**\src\auth\**` | DOTTEST_INCLUDE (inclusion) |
| "exclude tests" / "skip test projects" | `**\*.Tests\**` | DOTTEST_EXCLUDE (exclusion) |
| "exclude generated files" / "skip auto-generated" | `**\Generated\**;**\obj\**;**\bin\**` | DOTTEST_EXCLUDE (exclusion) |
| "ignore `TemporaryFiles` directory" | `**\TemporaryFiles\**` | DOTTEST_EXCLUDE (exclusion) |


**Examples:**
- _"Fix all violations in project `MyProject`"_ → `DOTTEST_INCLUDE=**\MyProject\**`
- _"Fix all violations in file `ABC`"_ → `DOTTEST_INCLUDE=**\ABC.cs`
- _"Fix up to five violations in file `ABC` in MyProject project"_ → `DOTTEST_INCLUDE=**\MyProject\**\ABC.cs`
- _"Analyze only `BankService` and `AccountService`"_ → `DOTTEST_INCLUDE=**\BankService.cs;**\AccountService.cs`
- _"Fix violations except in test projects"_ → `DOTTEST_EXCLUDE=**\*.Tests\**`
- _"Fix violations in MyProject but exclude generated files"_ → `DOTTEST_INCLUDE=**\MyProject\**` and `DOTTEST_EXCLUDE=**\Generated\**;**\obj\**;**\bin\**`

If **no scope-limiting language** is present, set `DOTTEST_INCLUDE` and `DOTTEST_EXCLUDE` to empty strings - the `dottest-analyze` script will run a full-project analysis.

**Multiple patterns**: When the user mentions multiple targets or exclusions, combine them with semicolons within the respective variable (e.g., `DOTTEST_INCLUDE=**/Project1/**;**/Project2/**`).

### Step 2: Verify Build and Tests

**Keep the environment consistent** with the previous step. Variables resolved and set by `resolve-config.ps1` in Step 1 are available and should not be modified. Do not change any variable values or the environment in any way before calling the verification script.

**Verify the solution builds and unit tests pass.** The verification behavior depends on whether baseline files are provided and the `DISABLE_UNIT_TEST_VERIFICATION` setting:

**If `DISABLE_UNIT_TEST_VERIFICATION` is set to `true`:**
- The script only verifies that the solution builds successfully. Do not call `dotnet`, `devenv`, or `msbuild` directly from the skill; always run `scripts/verify.ps1` and let the script choose the builder.
- No unit tests are run (useful when tests are slow or unavailable)

**Otherwise, if baseline files are not provided** (both `DOTTEST_BASE_UNIT_TEST_REPORT` and `DOTTEST_BASE_UNIT_TEST_COVERAGE` are not set):
- The script runs unit tests with coverage using configuration `"builtin://Run VSTest Tests with coverage"`
- Results are saved to `parasoft-dottest-reports\baseline\unit-tests`
- The script sets `DOTTEST_BASE_UNIT_TEST_REPORT` and `DOTTEST_BASE_UNIT_TEST_COVERAGE` environment variables to the generated baseline files for use in subsequent steps

**Otherwise, if baseline files are provided** (both `DOTTEST_BASE_UNIT_TEST_REPORT` and `DOTTEST_BASE_UNIT_TEST_COVERAGE` are set):
- The script only verifies that the solution builds successfully. Do not call `dotnet`, `devenv`, or `msbuild` directly from the skill; always run `scripts/verify.ps1` and let the script choose the builder.
- No tests are run during initial verification (tests will run with TIA during fix verification in Step 6.5)

Call the `verify.ps1` script from `scripts` directory. The following environment variables are already set and are available to the script: `DOTTEST_HOME`, `SOLUTION_PATH`, `OUTPUT_DIR`, `DOTTEST_SETTINGS`, `DOTTEST_BASE_UNIT_TEST_REPORT`, `DOTTEST_BASE_UNIT_TEST_COVERAGE`, `DISABLE_UNIT_TEST_VERIFICATION`, `DISABLE_INITIAL_BUILD`, `DOTTEST_BUILDER`.

The script **must** exit with code `0` on success and a non-zero code on failure.

**If the script fails (non-zero exit code)**: print `ERROR: Solution build or unit tests failed. Fix compilation errors or failing tests before running analysis.` followed by the script output, and terminate immediately.

**If `verify` executed unit tests, parse the `REPORT_XML=` value from the last stdout line. If tests were expected but no `REPORT_XML=` line was emitted: FAILURE. If `verify` ran in build-only mode, do not require `REPORT_XML` in Step 2.**
If unit tests were executed, check that there are no unit test failures in the `REPORT_XML` file. If there are any then print `ERROR: Unit tests failed. Fix failing tests before running analysis.` followed by the list of failed tests, and terminate immediately.

### Step 3: Run dotTEST Analysis

**Keep the environment consistent** with the previous step. Variables resolved and set by `resolve-config.ps1` in Step 1 are available and should not be modified. Do not change any variable values or the environment in any way before calling the verification script.

**If user has provided a baseline static analysis report file via `DOTTEST_BASE_STATIC_ANALYSIS_REPORT`, then skip this Step and proceed to Step 4**. Otherwise, run the full dotTEST analysis to produce the baseline report, by running the `dottest-analyze.ps1` script with the appropriate environment variables set. This will be the mandatory input for all subsequent steps. Before calling the script, set `DOTTEST_INCLUDE` and `DOTTEST_EXCLUDE` to the semicolon-separated list of scope patterns derived from the user's request in Step 1 (e.g. `**/com/foo/**;**/Bar.cs`), or an empty string if no scope was requested.

Call the `dottest-analyze.ps1` script from `scripts` directory. The following environment variables are already set and are available to the script: `DOTTEST_HOME`, `SOLUTION_PATH`, `DOTTEST_TEST_CONFIGURATION`, `DOTTEST_SETTINGS`, `DOTTEST_INCLUDE`, `DOTTEST_EXCLUDE`.

The script **must** exit with code `0` on success and a non-zero code on failure, and always prints `REPORT_XML=<absolute_path>` as its **last stdout line** on success.
**If the script fails (non-zero exit code)**: print `ERROR: dotTEST analysis exited with code [N]. See output above for details.` and terminate immediately.

### Step 4: Collect Violations

**If analysis was run in Step 3 parse the `REPORT_XML=` value from the last stdout line of `dottest-analyze.ps1`. Store this absolute path in the `DOTTEST_BASE_STATIC_ANALYSIS_REPORT` environment variable. Do not search for `report.xml` in any other location.**

Call the MCP tool `get_violations_from_report_file` with `DOTTEST_BASE_STATIC_ANALYSIS_REPORT` to obtain a structured list of findings, then report a summary (total count, breakdown by severity).

**Important Notes:**
- Track violation line shifts across fixes in memory during the current run; do not create tracking files.
- Paths to code files between `DOTTEST_BASE_STATIC_ANALYSIS_REPORT` and the local repository may differ; find the best match yourself.
- **Immediately discard any violation whose `suppressed` field is `true`. Suppressed violations must never be fixed or committed.**
- **If there are no violations, stop immediately with success: "No violations were found for the given scope".**

### Step 5: Filter and Prioritize

Process violations in the following deterministic order:
1. **Exclude suppressed violations**: before any other filtering, remove all violations where the `suppressed` field is `true`. These are intentionally silenced by the project team and must not be touched.
2. If any optional filter environment variables were set (`DOTTEST_FILTER_RULE`), apply them exactly as specified.
3. Otherwise, sort all remaining violations by severity (highest first: severity 1 > 2 > 3 > 4 > 5), then by file path alphabetically, then by line number ascending.
4. Process violations in this sorted order, one at a time.

### Step 6: Fix, Verify, and Commit — Delegate to `dottest-fix-violation` Agent

Each fix-verify-commit cycle runs in a **separate agent context** to keep the parent conversation lean.

#### Branch Setup (once, before the fix loop)

If `DOTTEST_COMMIT_FIXES=true` and `FIXES_BRANCH_NAME` is set, create and switch to the named branch **once** before processing the first violation. Replace `[timestamp]` with the current date-time if present:

```powershell
$branch = $env:FIXES_BRANCH_NAME -replace '\[timestamp\]', (Get-Date -Format 'yyyyMMdd-HHmmss')
git checkout -b $branch 2>$null; if ($LASTEXITCODE -ne 0) { git checkout $branch }
```

If `FIXES_BRANCH_NAME` is empty or `DOTTEST_COMMIT_FIXES` is not `true`, commit directly to the currently checked-out branch without creating or switching to any new branch.

#### Classifying Violations

- **Simple violations** (formatting, whitespace, unnecessary casts, unused imports) where the fix is purely mechanical and does not change logic — group all such violations for the **same file** into a single batch, pre-sorted by line number descending.
- **All other violations** (logic changes, null checks, resource handling, exception handling, API changes) — process exactly one at a time.

#### Effective Fix Limit

- Inspect the user's natural-language request for an explicit numeric fix limit (e.g. "fix 3 violations", "apply at most 5 fixes"). If found, use that number as the effective limit.
- Otherwise, use `DOTTEST_STATIC_NO_OF_MAX_FIXES` (default `5`) as the effective limit.
- Initialize a `successful_fixes` counter to `0` and a `FIX_NUMBER` counter to `1`.

#### Invoking the Agent

Before spawning each agent, create the log directory and compute the log file path in the terminal session:

```powershell
$agentLogFile = Join-Path $env:OUTPUT_DIR "parasoft-dottest-reports\fix-$env:FIX_NUMBER\agent.log"
New-Item -ItemType Directory -Path (Split-Path $agentLogFile) -Force | Out-Null
```

The parent shell's `FIX_NUMBER` is not inherited by the isolated subagent.
`FIX_NUMBER` in the JSON payload is the authoritative value; the subagent must
set `$env:FIX_NUMBER` from that payload before running any verification or
analysis script.

`agentLogFile` is the operational conversation log for the
`dottest-fix-violation` agent. The agent must append its decisions, MCP results,
commands, verification output, retries, and final result to this file. Do not
use it as a `Tee-Object` target when running `verify.ps1` or
`dottest-analyze.ps1`; those scripts manage their own output files. Hidden model
reasoning is not available to the skill and is not included.

For each violation or batch, spawn agent "dottest-fix-violation" and pass a task prompt containing a JSON block. The JSON must include all context the agent needs (it runs in its own isolated context and has no access to the parent's conversation history):

**Single (complex) violation:**
```json
{
  "mode": "single",
  "scriptDir": "<absolute path to the scripts directory of this skill>",
  "agentLogFile": "<agentLogFile>",
  "environment": {
    "DOTTEST_HOME": "<DOTTEST_HOME>",
    "SOLUTION_PATH": "<SOLUTION_PATH>",
    "OUTPUT_DIR": "<OUTPUT_DIR>",
    "FIX_NUMBER": "<FIX_NUMBER>",
    "DOTTEST_ANALYZER_CONFIG": "<DOTTEST_ANALYZER_CONFIG or empty>",
    "DOTTEST_TEST_CONFIGURATION": "<DOTTEST_TEST_CONFIGURATION>",
    "DOTTEST_COMMIT_FIXES": "<DOTTEST_COMMIT_FIXES>",
    "DOTTEST_FILTER_RULE": "<DOTTEST_FILTER_RULE or empty>",
    "DOTTEST_SETTINGS": "<DOTTEST_SETTINGS or empty>",
    "DOTTEST_BASE_STATIC_ANALYSIS_REPORT": "<DOTTEST_BASE_STATIC_ANALYSIS_REPORT>",
    "DOTTEST_BASE_UNIT_TEST_REPORT": "<DOTTEST_BASE_UNIT_TEST_REPORT or empty>",
    "DOTTEST_BASE_UNIT_TEST_COVERAGE": "<DOTTEST_BASE_UNIT_TEST_COVERAGE or empty>",
    "DISABLE_UNIT_TEST_VERIFICATION": "<DISABLE_UNIT_TEST_VERIFICATION>",
    "DOTTEST_STATIC_NO_OF_MAX_FIXES": "<DOTTEST_STATIC_NO_OF_MAX_FIXES>",
    "DOTTEST_FIX_ATTEMPTS": "<DOTTEST_FIX_ATTEMPTS>",
    "FIXES_BRANCH_NAME": "<FIXES_BRANCH_NAME or empty>",
    "DOTTEST_REFERENCE_BRANCH": "<DOTTEST_REFERENCE_BRANCH or empty>",
    "DOTTEST_BUILDER": "<DOTTEST_BUILDER or empty>",
    "DISABLE_INITIAL_BUILD": "<DISABLE_INITIAL_BUILD>",
    "GIT_BRANCH": "<GIT_BRANCH or empty>",
    "GIT_WORKSPACE": "<GIT_WORKSPACE or empty>"
  },
  "violation": {
    "ruleId": "<rule_id>",
    "sourceFile": "<absolute_path>",
    "lineNumber": <line>,
    "message": "<message>",
    "severity": <severity>
  }
}
```

**Batch (simple) violations — same file, pre-sorted line-descending:**
```json
{
  "mode": "batch",
  "scriptDir": "<absolute path to the scripts directory of this skill>",
  "agentLogFile": "<agentLogFile>",
  "environment": {
    "DOTTEST_HOME": "<DOTTEST_HOME>",
    "SOLUTION_PATH": "<SOLUTION_PATH>",
    "OUTPUT_DIR": "<OUTPUT_DIR>",
    "FIX_NUMBER": "<fix_number>",
    "DOTTEST_ANALYZER_CONFIG": "<DOTTEST_ANALYZER_CONFIG or empty>",
    "DOTTEST_TEST_CONFIGURATION": "<DOTTEST_TEST_CONFIGURATION>",
    "DOTTEST_COMMIT_FIXES": "<DOTTEST_COMMIT_FIXES>",
    "DOTTEST_FILTER_RULE": "<DOTTEST_FILTER_RULE or empty>",
    "DOTTEST_SETTINGS": "<DOTTEST_SETTINGS or empty>",
    "DOTTEST_BASE_STATIC_ANALYSIS_REPORT": "<DOTTEST_BASE_STATIC_ANALYSIS_REPORT>",
    "DOTTEST_BASE_UNIT_TEST_REPORT": "<DOTTEST_BASE_UNIT_TEST_REPORT or empty>",
    "DOTTEST_BASE_UNIT_TEST_COVERAGE": "<DOTTEST_BASE_UNIT_TEST_COVERAGE or empty>",
    "DISABLE_UNIT_TEST_VERIFICATION": "<DISABLE_UNIT_TEST_VERIFICATION>",
    "DOTTEST_STATIC_NO_OF_MAX_FIXES": "<DOTTEST_STATIC_NO_OF_MAX_FIXES>",
    "DOTTEST_FIX_ATTEMPTS": "<DOTTEST_FIX_ATTEMPTS>",
    "FIXES_BRANCH_NAME": "<FIXES_BRANCH_NAME or empty>",
    "DOTTEST_REFERENCE_BRANCH": "<DOTTEST_REFERENCE_BRANCH or empty>",
    "DOTTEST_BUILDER": "<DOTTEST_BUILDER or empty>",
    "DISABLE_INITIAL_BUILD": "<DISABLE_INITIAL_BUILD>",
    "GIT_BRANCH": "<GIT_BRANCH or empty>",
    "GIT_WORKSPACE": "<GIT_WORKSPACE or empty>"
  },
  "violations": [ ... ]
}
```

The agent performs all fix, verification, retry, and optional commit logic autonomously. The agent copies every variable from the JSON `environment` object into its terminal process environment before running scripts.

#### Collecting Results

Parse the `FIX_RESULT=` JSON line from the agent's output. Update counters:

- If `status` is `"SUCCESS"`: increment `successful_fixes` by `violationsFixed` and increment `FIX_NUMBER` by `1`. If `successful_fixes` ≥ `$env:DOTTEST_STATIC_NO_OF_MAX_FIXES`, print `Fix limit of [N] reached. Proceeding to summary.` and proceed immediately to Step 7.
- If `status` is `"FAILURE"`: record the failure, increment `FIX_NUMBER` by `1`, and move on to the next violation.

#### Processing Order

Process violations in the sorted order from Step 5, one agent invocation at a time. **Do not invoke multiple `dottest-fix-violation` agents in parallel** — each must complete before the next begins (to avoid git conflicts and ensure line-number stability).

### Step 7: Summary

Report:
- Total fixes attempted
- Successful fixes
- Failures
- Files with uncommitted local changes (if committing was not requested)
- Successful commits (if committing was requested)

## Error Handling

All errors are printed to the console (stderr) and cause immediate termination with a non-zero exit code. No user interaction is performed.

Configuration and validation errors (first group below) are raised by the `resolve-config` script in Step 1. Runtime errors (second group) are raised by the skill directly.

If this skill enounters any condition that breaks the expected flow or prevents it from performing its tasks correctly, it must print a clear and descriptive error message to the console and terminate immediately with a **non-zero exit code**. The following table outlines potential error conditions, corresponding console messages, and the resulting actions:

| Condition | Console message | Action |
|---|---|---|
| `DOTTEST_ANALYZER_CONFIG` file not found | `ERROR: DOTTEST_ANALYZER_CONFIG points to a file that does not exist: [path]. Verify the path and retry.` | Terminate immediately |
| `DOTTEST_HOME` not set and dottestcli not on PATH | `ERROR: DOTTEST_HOME is not set and dottestcli was not found on PATH. Set the DOTTEST_HOME environment variable and retry.` | Terminate immediately |
| `SOLUTION_PATH` not set or path does not exist | `ERROR: SOLUTION_PATH is not set or does not point to an existing directory. Set the SOLUTION_PATH environment variable and retry.` | Terminate immediately |
| dottestcli not found in `DOTTEST_HOME` | `ERROR: dottestcli not found in DOTTEST_HOME=[DOTTEST_HOME]. Verify the dottest installation path.` | Terminate immediately |
| `DOTTEST_SETTINGS` file not found | `ERROR: DOTTEST_SETTINGS points to a file that does not exist: [path]. Verify the path and retry.` | Terminate immediately |
| `DOTTEST_BASE_UNIT_TEST_REPORT` file not found | `ERROR: DOTTEST_BASE_UNIT_TEST_REPORT points to a file that does not exist: [path]. Verify the path and retry.` | Terminate immediately |
| `DOTTEST_BASE_UNIT_TEST_COVERAGE` file not found | `ERROR: DOTTEST_BASE_UNIT_TEST_COVERAGE points to a file that does not exist: [path]. Verify the path and retry.` | Terminate immediately |
| Build or unit tests fail | `ERROR: Solution build or unit tests failed. Fix compilation errors or failing tests before running analysis.` + script output | Terminate immediately |
| Analysis script returns non-zero | `ERROR: dotTEST analysis exited with code [N]. See output above for details.` | Terminate immediately |