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

**Do not run any other scripts than the ones provided by this skill.** The skill package must include `scripts/resolve-config.ps1`, `scripts/verify-environment.ps1`, `scripts/verify.ps1`, and `scripts/dottest-analyze.ps1`, and the coding agent must have the `dottest-fix-violation` agent available. Before Step 1, confirm that these dependencies are available. If a required script or agent is missing, stop with a clear error; do not continue with an incomplete workflow. Do not create, modify, or execute any other scripts or commands outside of those defined in this document.

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
| `DISABLE_UNIT_TEST_VERIFICATION` | Set to `true` to skip unit-test execution during Step 2. The current fix agent cannot safely complete fix verification in this mode, so Step 6 stops before starting fixes. Defaults to `false`. |
| `DISABLE_INITIAL_BUILD` | Set to `true` to skip the initial build only when Step 2 is already in build-only mode (`DISABLE_UNIT_TEST_VERIFICATION=true` or both unit-test baseline files are provided). It does not skip the build/test work performed after a fix. Defaults to `false`. |
| `FIXES_BRANCH_NAME` | Name of the branch to create and switch to before committing fixes. Supports `[timestamp]` pattern (e.g. `my-fixes-[timestamp]`), which is replaced with the current date-time. If not set, commits are applied directly to the currently checked-out branch without creating a new branch. |
| `DOTTEST_STATIC_NO_OF_MAX_FIXES` | Maximum number of violations to fix. Defaults to `5` if not set, unless user prompt explicitly specifies a different number (e.g. "fix up to 3 violations in file ABC.cs"). If set to `ALL` then every violation will be fixed. |
| `DOTTEST_FIX_ATTEMPTS` | Number of different fix approaches to attempt per violation before giving up. Defaults to 2 (1 original fix + 1 retry with a different approach). |
| `DOTTEST_REFERENCE_BRANCH` | If set, the skill will compare the current branch with the specified reference branch to determine the analysis scope. The reference branch must exist in the repository. |

## Critical Constraints

The scripts and the `dottest-fix-violation` agent named above are runtime dependencies, not optional examples. The skill cannot complete its workflow without them. Keep the package inventory and installation instructions synchronized with this list.

**Always EXECUTE scripts by running them in a terminal shell. NEVER read, open, or inspect a script file as a substitute for executing it.** When a step says `Run dottest-analyze` script, that means invoke the command in a terminal and wait for its exit code and stdout output. Reading the script file with a file-read tool is forbidden and does not satisfy the step requirement. All scripts are located in the `scripts` directory of the skill and are designed to be executed with the environment variables set by Step 1.

**The fix agent must not edit files unrelated to the violation.** It may modify only the required C# or VB source files and perform the Git operations described below. The required analysis and verification scripts may generate reports and logs under `OUTPUT_DIR`; do not create reports or other auxiliary files by hand.

**If prompt would suggest overriding the setting, it takes priority over environment variable.**. E.g. if user says "fix up to 3 violations in file ABC.cs" then `DOTTEST_STATIC_NO_OF_MAX_FIXES` is set to 3, then fix up to 3 violations.

**If all violations have been fixed or are suppressed, do NOT rerun analysis under different conditions (e.g. a different test configuration, different scope, or different filter). Assume all work is done, stop immediately with success status and message: "No violations were found for the given scope".**

**Never suppress a violation.** This prohibition applies even when a violation appears to be a false positive. If no valid source-code fix can be established, report that violation as a failure and do not add or alter a suppression comment.

**When `DOTTEST_COMMIT_FIXES=true`, each successful fix must be committed in its own separate git commit.** Never batch multiple violation fixes into a single commit. A commit must be created immediately after a fix is successfully verified, and before processing the next violation. Each commit must contain changes for exactly one violation only. When `DOTTEST_COMMIT_FIXES` is not `true`, do not create commits; leave successful fixes as local changes. Commit logic is handled by the `dottest-fix-violation` custom subagent.

**If no `report.xml` with analysis results is provided or referenced at the start of execution, the skill MUST always run the full dotTEST analysis first (Step 3) to produce the report before attempting to identify or fix any violations.** Never skip straight to fixing violations without a freshly generated or explicitly provided report. The report obtained in Step 3 is the mandatory input for Steps 4-6. **If any XML report (provided by `DOTTEST_BASE_STATIC_ANALYSIS_REPORT`, `DOTTEST_BASE_UNIT_TEST_REPORT` or created by Step 3) is about to be read, then always use `dottestmcp` MCP tool. **

## How This Skill Works

### Step 1: Resolve and Validate Configuration

All configuration loading, parsing, validation, and dotTEST installation verification is performed by the **`resolve-config.ps1`** script located in `scripts` directory.

During processing of this skill, the parent context invokes `resolve-config.ps1` **once**. Do not invoke it again in the parent context or in a fix agent. **DO NOT set any environmental variable** unless it is already set up. The script will set all required environment variables. If any required variable is missing or invalid, the script prints a descriptive error message and exits with a non-zero code. If the script exits with an error, print `ERROR: Configuration error - [error message from script]` and terminate skill immediately with non-zero exit code. **After the script returns, verify that the current environment actually matches what it printed: for every `Resolved configuration` line whose value is not `(not set)`, confirm `$env:<VARIABLE>` equals the exact printed value; skip verification for any variable printed as `(not set)`. If a mismatch is found, do not terminate — set `$env:<VARIABLE>` to the printed value so the environment matches the script's resolved configuration before proceeding.**

**For all subsequent steps**, keep the environment consistent with the previous step. Variables resolved and set by `resolve-config.ps1` in Step 1 are available and should not be modified unless specified.

After successful return, the following environment variables are guaranteed to be set and available to all subsequent steps: `DOTTEST_HOME`, `SOLUTION_PATH`, `OUTPUT_DIR`, `DOTTEST_TEST_CONFIGURATION`, `DOTTEST_COMMIT_FIXES`, `DISABLE_UNIT_TEST_VERIFICATION`, `DISABLE_INITIAL_BUILD`, `DOTTEST_FILTER_RULE`, `DOTTEST_SETTINGS`, `DOTTEST_BASE_STATIC_ANALYSIS_REPORT`, `DOTTEST_BASE_UNIT_TEST_REPORT`, `DOTTEST_BASE_UNIT_TEST_COVERAGE`, `DOTTEST_STATIC_NO_OF_MAX_FIXES`, `FIXES_BRANCH_NAME`, `DOTTEST_FIX_ATTEMPTS`, `DOTTEST_REFERENCE_BRANCH`, `DOTTEST_BUILDER`, `GIT_BRANCH`, `GIT_WORKSPACE`. **The script writes all those settings to the console. Each one of them should be set if not already provided, unless printed value by the script is `(not set)` - in that case the variable is not set and should be treated as empty string.** The scripts do not copy configured baseline reports or coverage files. They use the configured paths directly; only baselines generated by the scripts update the corresponding environment variables. Existing output files alone do not select a baseline.

For unit-test baselines, either both `DOTTEST_BASE_UNIT_TEST_REPORT` and `DOTTEST_BASE_UNIT_TEST_COVERAGE` must be set, or neither may be set. If exactly one is set, stop before Step 2 with a configuration error; do not run verification with an incomplete TIA baseline.

**After calling the script**, set the `DOTTEST_INCLUDE` and `DOTTEST_EXCLUDE` environment variables based on the user's request (see [Analysis Scope](#resolve-analysis-scope) below). 

After scope resolution, set `DOTTEST_BASELINE_MODE=true` and create the complete `$environment` JSON object used later in subagent payloads. It must contain every variable listed in the Step 6 environment schema, including the three baseline variables, `DOTTEST_INCLUDE`, `DOTTEST_EXCLUDE` (do NOT include `DOTTEST_BASELINE_MODE`). Represent `(not set)` as an empty string and `(current branch)` as the actual process value. Also record whether the static baseline was provided and whether both unit-test baseline files were provided at this point. Serialize the object with `ConvertTo-Json -Compress`; this is the single mutable environment object for Steps 2–6. Do not recreate it by calling `resolve-config.ps1` again.

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

`verify.ps1` requires `DOTTEST_BASELINE_MODE` to be explicitly set. First invoke `scripts/verify-environment.ps1 -ExpectedJson ($environment | ConvertTo-Json -Compress)` to restore and verify the exact current environment object, including its current baseline values. If verification fails, terminate immediately; do not rerun `resolve-config.ps1`. After it succeeds, set `DOTTEST_BASELINE_MODE=true` and invoke `verify.ps1`; this selects initial verification behavior. Keep the mode `true` through Step 2. Set it to `true` again immediately before invoking `dottest-analyze.ps1` in Step 3. The scripts fail if the variable is missing or is not `true` or `false`.

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

**If `verify` executed unit tests, parse the `UT_REPORT_XML=` value from the last stdout line. If tests were expected but no `UT_REPORT_XML=` line was emitted: FAILURE. If `verify` ran in build-only mode, do not require `UT_REPORT_XML` in Step 2.**
If unit tests were executed, check that there are no unit test failures in the `UT_REPORT_XML` file. If there are any then print `ERROR: Unit tests failed. Fix failing tests before running analysis.` followed by the list of failed tests, and terminate immediately.

After `verify.ps1` completes successfully, update the `$environment` object and its JSON representation from the current process values. If both unit-test baseline variables were empty when the object was first created and `verify.ps1` generated baselines, update `DOTTEST_BASE_UNIT_TEST_REPORT` and `DOTTEST_BASE_UNIT_TEST_COVERAGE` to the paths emitted by `verify.ps1`. If unit-test baselines were present in the initial object, leave them unchanged and do not treat the existing canonical files as newly generated. The updated JSON is passed to Step 3 and later to subagents.

### Step 3: Run dotTEST Analysis

First invoke `scripts/verify-environment.ps1 -ExpectedJson ($environment | ConvertTo-Json -Compress)`. This must succeed before analysis starts; do not rerun `resolve-config.ps1`. Then set `DOTTEST_INCLUDE` and `DOTTEST_EXCLUDE` to the semicolon-separated scope patterns derived from the user's request in Step 1, or to empty strings if no scope was requested. Set `DOTTEST_BASELINE_MODE=true` immediately before invoking `dottest-analyze.ps1`. The script requires this value explicitly and fails if the mode is missing or invalid.

Always invoke `dottest-analyze.ps1` in this step. If `DOTTEST_BASE_STATIC_ANALYSIS_REPORT` was provided in the initial configuration, the script returns that same path in `SA_REPORT_XML=` and skips static analysis; it does not copy the report to the canonical output directory. The configured report must match `DOTTEST_TEST_CONFIGURATION`. `DOTTEST_INCLUDE` and `DOTTEST_EXCLUDE` do not alter a reused report; apply them to the violation source-file paths returned by MCP in Step 5. If `DOTTEST_REFERENCE_BRANCH` is set, the reused report must already represent analysis against that reference branch; otherwise stop with a configuration error. If no static-analysis baseline was provided, the script runs analysis to create one under `OUTPUT_DIR`. In either case, it must exit with code `0` on success and a non-zero code on failure, and print `SA_REPORT_XML=<absolute_path>` as its **last stdout line** on success. The emitted path identifies the report to use in subsequent steps.

The selected baseline report must be available before any `dottest-fix-violation` agent is spawned. A fix agent never creates a baseline; it receives the selected report path in its JSON payload and uses it as its reference report.
**If the script fails (non-zero exit code)**: print `ERROR: dotTEST analysis exited with code [N]. See output above for details.` and terminate immediately.

**After successful completion of this step, the baseline report file path must be stored in `DOTTEST_BASE_STATIC_ANALYSIS_REPORT` for use in Step 4.**

After `dottest-analyze.ps1` completes successfully, update `DOTTEST_BASE_STATIC_ANALYSIS_REPORT` in the `$environment` object and its JSON representation from the final `SA_REPORT_XML=` path. If a static baseline was provided, this remains the original configured path; the script does not copy it or create a new baseline. Pass this updated object to Step 6.

### Step 4: Collect Violations

Parse the `SA_REPORT_XML=` value from the last stdout line of `dottest-analyze.ps1`, whether it identifies a newly generated report or the configured report reused in Step 3. Store this path in `DOTTEST_BASE_STATIC_ANALYSIS_REPORT`. Do not search for `report.xml` in any other location.

Call the MCP tool `get_violations_from_report_file` with `DOTTEST_BASE_STATIC_ANALYSIS_REPORT` to obtain a structured list of findings, then report a summary (total count, breakdown by severity).

**Important Notes:**
- Track violation line shifts across fixes in memory during the current run; do not create tracking files.
- Paths to code files between `DOTTEST_BASE_STATIC_ANALYSIS_REPORT` and the local repository may differ; find the best match yourself.
- **Immediately discard any violation whose `suppressed` field is `true`. Suppressed violations must never be fixed or committed.**
- **If there are no violations, stop immediately with success: "No violations were found for the given scope".**

### Step 5: Filter and Prioritize

Process violations in this deterministic order:
1. Exclude all violations where `suppressed` is `true`.
2. Apply the requested severity selection, if any. For example, "severity-1 violations" means severity exactly `1`.
3. If the user explicitly names rule IDs in the prompt, use those IDs as the effective rule filter; otherwise use `DOTTEST_FILTER_RULE` when set. The explicit user request takes precedence over the configured value.
4. Apply the requested file, project, or directory scope to the reported source-file paths using the Ant-style patterns described in [Resolve Analysis Scope](#resolve-analysis-scope). When a configured static-analysis report is reused, this filters the returned violations; it does not rerun analysis or change the report.
5. Sort all remaining violations by severity (1 first, then 2 through 5), file path alphabetically, and line number ascending. Always sort after filtering, including when `DOTTEST_FILTER_RULE` is set.
6. Process violations in this sorted order, respecting the effective fix limit.

If no violations remain after suppression, severity, rule, and scope filtering, stop successfully with the message `No violations were found for the given scope`. Do not start a fix agent or rerun analysis with different filters.

### Step 6: Fix, Verify, and Commit — Delegate to `dottest-fix-violation` Agent

Set `DOTTEST_BASELINE_MODE=false` in the environment snapshot before spawning the `dottest-fix-violation` agent. The fix agent must run in fix mode, not baseline mode; the scripts reject a missing or invalid mode value.

Each fix-verify-commit cycle runs in a **separate agent context** to keep the parent conversation lean. **DO NOT attempt to fix, verify, or commit violations directly in the parent context**. Instead, spawn a new agent for each violation (or batch of simple violations) and pass all required context in a JSON payload. The agent runs autonomously and returns a JSON result to the parent.

Before the first fix-agent invocation, confirm that the solution is inside a Git worktree, that `git diff --quiet` and `git diff --cached --quiet` both succeed, and that every target source file is tracked by Git. If any check fails, stop without invoking the agent. Do not require a completely empty `git status`: reports and logs under `OUTPUT_DIR` may be untracked, and `git checkout -- .` does not remove untracked files. The current fix agent reverts with `git checkout -- .` after verification failure, so it must not run while user changes or earlier uncommitted fixes to tracked files are present. When `DOTTEST_COMMIT_FIXES` is not `true`, process at most one agent invocation (one complex violation or one same-file simple batch) per skill run, then proceed to the summary. This prevents a later failed invocation from discarding an earlier successful uncommitted fix.

The current fix agent always expects `UT_REPORT_XML` after `verify.ps1`, but `verify.ps1` does not emit that marker when `DISABLE_UNIT_TEST_VERIFICATION=true`. Until the agent is updated to support build-only verification, if this setting is `true`, stop before spawning it and report that fix verification cannot safely complete in this mode. Do not claim the fix was verified.

#### Branch Setup (once, before the fix loop)

If `DOTTEST_COMMIT_FIXES=true` and `FIXES_BRANCH_NAME` is set, create and switch to the named branch **once** before processing the first violation. Replace `[timestamp]` with the current date-time if present:

```powershell
$branch = $env:FIXES_BRANCH_NAME -replace '\[timestamp\]', (Get-Date -Format 'yyyyMMdd-HHmmss')
git checkout -b $branch 2>$null; if ($LASTEXITCODE -ne 0) { git checkout $branch }
```

If `DOTTEST_COMMIT_FIXES` is not `true`, do not create or switch branches and do not commit. If commits are enabled but `FIXES_BRANCH_NAME` is empty, commit each verified fix directly to the currently checked-out branch.

#### Classifying Violations

- **Simple violations** (formatting, whitespace, unnecessary casts, unused imports) where the fix is purely mechanical and does not change logic — when `DOTTEST_COMMIT_FIXES` is not `true`, group eligible violations for the **same file** into a single batch, pre-sorted by line number descending and never exceeding the remaining fix limit.
- When `DOTTEST_COMMIT_FIXES=true`, process each violation in its own agent invocation. Do not use batch mode, because the agent creates one commit per invocation.
- **All other violations** (logic changes, null checks, resource handling, exception handling, API changes) — process exactly one at a time.

#### Effective Fix Limit

- Inspect the user's request for an explicit fix limit. An explicit number overrides `DOTTEST_STATIC_NO_OF_MAX_FIXES`; an explicit request to fix all eligible violations means no numeric limit.
- If the request has no explicit limit and `DOTTEST_STATIC_NO_OF_MAX_FIXES` is `ALL`, process all remaining eligible violations without a numeric limit.
- Otherwise, use `DOTTEST_STATIC_NO_OF_MAX_FIXES` (default `5`) as the numeric effective limit.
- Initialize a `successful_fixes` counter to `0`.

#### Invoking the Agent

For each violation or batch, populate one of the JSON payloads below and embed it directly in the subagent's prompt text. Do not write the payload to disk.

The payload **must include all context** the agent needs (it runs in its own isolated context and has no access to the parent's conversation history):

Immediately before spawning the agent, build an `environment` JSON object from the current parent process. It must contain every variable printed by `resolve-config.ps1` plus the post-resolution scope and mode values below.
Represent `(not set)` as an empty string. Do not pass the literal display text `(current branch)`; pass the actual `FIXES_BRANCH_NAME` process value, which is empty when commits stay on the current branch. Capture this object after Step 3 has selected the baseline paths.

```json
{
  "DOTTEST_ANALYZER_CONFIG": "<value>",
  "DOTTEST_HOME": "<value>",
  "SOLUTION_PATH": "<value>",
  "OUTPUT_DIR": "<value>",
  "DOTTEST_TEST_CONFIGURATION": "<value>",
  "DOTTEST_COMMIT_FIXES": "<value>",
  "DISABLE_UNIT_TEST_VERIFICATION": "<value>",
  "DISABLE_INITIAL_BUILD": "<value>",
  "DOTTEST_FILTER_RULE": "<value>",
  "DOTTEST_SETTINGS": "<value>",
  "DOTTEST_BASE_STATIC_ANALYSIS_REPORT": "<value>",
  "DOTTEST_BASE_UNIT_TEST_REPORT": "<value>",
  "DOTTEST_BASE_UNIT_TEST_COVERAGE": "<value>",
  "DOTTEST_STATIC_NO_OF_MAX_FIXES": "<value>",
  "FIXES_BRANCH_NAME": "<value>",
  "DOTTEST_FIX_ATTEMPTS": "<value>",
  "DOTTEST_BUILDER": "<value>",
  "DOTTEST_REFERENCE_BRANCH": "<value>",
  "GIT_BRANCH": "<value>",
  "GIT_WORKSPACE": "<value>",
  "DOTTEST_INCLUDE": "<value>",
  "DOTTEST_EXCLUDE": "<value>",
  "DOTTEST_BASELINE_MODE": "false"
}
```

The `environment` object must be identical in the single and batch payloads. Do not add a second copy of these values as top-level payload properties. The `{ "...": ... }` notation in the payload examples is documentation shorthand; the actual emitted JSON must contain every property from the complete object above.

**Single (complex) violation:**
```json
{
  "mode": "single",
  "scriptDir": "<absolute path to the scripts directory of this skill>",
  "environment": { "...": "the complete environment object above" },
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
  "environment": { "...": "the complete environment object above" },
  "violations": [ ... ]
}
```

The agent performs all fix, verification, retry, and optional commit logic autonomously. It receives the complete `environment` object from the parent context and restores it using `verify-environment.ps1`; it does **not** run `resolve-config.ps1`. It must stop on an environment verification failure before running `verify.ps1` or `dottest-analyze.ps1`.

#### Collecting Results

Parse the `FIX_RESULT=` JSON line from the agent's output. Update counters:

- If `status` is `"SUCCESS"`: increment `successful_fixes` by `violationsFixed`. When the effective limit is numeric and `successful_fixes` is greater than or equal to it, print `Fix limit of [N] reached. Proceeding to summary.` and proceed immediately to Step 7. For `ALL`, do not perform a numeric limit comparison.
- If `status` is `"FAILURE"`: record the failure. When `DOTTEST_COMMIT_FIXES=true`, move on to the next violation. Otherwise, proceed immediately to the summary; do not invoke another agent in this run.

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
