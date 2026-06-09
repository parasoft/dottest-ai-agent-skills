---
name: dottest-analyzer
description: Run Parasoft dotTEST Static Analysis on dotnet projects, detect violations in user code, and provide fix recommendations. Use this skill when users want to analyze C# code quality, find bugs, security issues, or coding standard violations using dotTEST.
metadata:
   author: Parasoft
   version: "1.0"
   mode: non-interactive
   requires:
      - Parasoft dotTEST installation
      - .NET solution file
---

# dotTEST Static Analysis Skill

## Overview

This skill enables GitHub Copilot to run Parasoft dotTEST Static Analysis on .NET projects, identify violations, and help fix them automatically.

> **Non-interactive / nightly mode**: This skill operates fully autonomously. It **never** prompts the user for input. All required settings must be supplied via environment variables before the skill is invoked. If a required setting cannot be determined automatically, the skill prints a descriptive error message to the console and terminates immediately with a non-zero exit code.

> **Do not improvise and get creative with user prompts or interactive input** - this is strictly forbidden. The skill is designed for non-interactive execution in CI pipelines or scheduled runs, not for ad-hoc use. Moreover, keep sequence of steps and their logic exactly as defined in this document. Do not skip, reorder, or modify steps, as they are carefully designed to ensure correct and reliable operation.

> **Perform Steps in Order, from 1 to 9** and do not deviate from the defined sequence. Each step relies on the successful completion of the previous steps, and skipping or reordering them may lead to incorrect behavior or failures. Follow the steps exactly as outlined to ensure the skill functions as intended.

**Do not run any other scripts than the ones provided by this skill.** All scripts required for configuration, analysis, verification, and fixing are included in the `scripts` directory of this skill. Do not create, modify, or execute any other scripts or commands outside of those defined in this document.

## When to Use This Skill

Use this skill when:
- User wants to run static analysis on C# or Visual Basic code
- User mentions dotTEST, code quality, or finding bugs/violations
- User wants to detect security issues, coding standard violations, or best practice issues
- User wants to fix, repair static violations in code

## Prerequisites

All settings are read exclusively from environment variables. No interactive prompts are issued.

| Variable | Required | Description |
|---|---|---|
| `DOTTEST_HOME` | **Required** (unless auto-detected) | Path to dotTEST installation directory (e.g. `C:\Program Files\Parasoft\dotTEST`). Auto-detected from `PATH` if not set. |
| `SOLUTION_PATH` | **Required** | Absolute path to the solution file to analyse. |
| `OUTPUT_DIR` | Optional | Absolute path to the directory where output will be stored. By default, execution directory is used. |
| `DOTTEST_ANALYZER_CONFIG` | Optional | Absolute path to a properties file (`key=value` format) from which all other settings below can be loaded. Environment variables always take precedence over values defined in this file. |
| `DOTTEST_TEST_CONFIGURATION` | Optional | Test configuration name (e.g. `builtin://Recommended Rules`). Defaults to `builtin://Recommended Rules`. |
| `DOTTEST_COMMIT_FIXES` | Optional | Set to `true` to commit each successful fix. Any other value or absence means fixes are left as local uncommitted changes. |
| `DOTTEST_FILTER_RULE` | Optional | Comma-separated list of rule IDs. When set, only violations matching these IDs are processed. |
| `DOTTEST_SETTINGS` | Optional | Absolute path to a dotTEST settings file. When set, adds `-settings=<path>` to all analysis commands. |
| `DOTTEST_BASE_STATIC_ANALYSIS_REPORT` | Optional | Absolute path to a base `report.xml` file from static analysis matching test configuration in `DOTTEST_TEST_CONFIGURATION`. When not set, Step 3 runs analysis to create the baseline. |
| `DOTTEST_BASE_UNIT_TEST_REPORT` | Optional | Absolute path to a base `report.xml` file. When both `DOTTEST_BASE_UNIT_TEST_REPORT` and `DOTTEST_BASE_UNIT_TEST_COVERAGE` are set, Step 2 only verifies the build (no test run), and Step 7 uses Test Impact Analysis (TIA). When not set, Step 2 runs tests with coverage to create the baseline. |
| `DOTTEST_BASE_UNIT_TEST_COVERAGE` | Optional | Absolute path to a base `coverage.xml` file. When both `DOTTEST_BASE_UNIT_TEST_REPORT` and `DOTTEST_BASE_UNIT_TEST_COVERAGE` are set, Step 2 only verifies the build (no test run), and Step 7 uses Test Impact Analysis (TIA). When not set, Step 2 runs tests with coverage to create the baseline. |
| `DISABLE_UNIT_TEST_VERIFICATION` | Optional | Set to `true` to skip unit test execution in Step 2 (only build check) and Step 7.1 (fix verification). Defaults to `false`. Useful when unit tests are slow or unavailable. |
| `FIXES_BRANCH_NAME` | Optional | Name of the branch to create and switch to before committing fixes. Supports `[timestamp]` pattern (e.g. `my-fixes-[timestamp]`), which is replaced with the current date-time. If not set, commits are applied directly to the currently checked-out branch without creating a new branch. |
| `DOTTEST_STATIC_NO_OF_MAX_FIXES` | Optional | Maximum number of violations to fix. Defaults to 5 if not set, unless user prompt explicitly specifies a different number (e.g. "fix up to 3 violations in file ABC.cs"). |
| `DOTTEST_FIX_ATTEMPTS` | Optional | Number of different fix approaches to attempt per violation before giving up. Defaults to 2 (1 original fix + 1 retry with a different approach). |
| `DOTTEST_REFERENCE_BRANCH` | Optional | If set, the skill will compare the current branch with the specified reference branch to determine the analysis scope. The reference branch must exist in the repository. |

## Critical Constraints

**Always EXECUTE scripts by running them in a terminal shell. NEVER read, open, or inspect a script file as a substitute for executing it.** When a step says `Run dottest-analyze` script, that means invoke the command in a terminal and wait for its exit code and stdout output. Reading the script file with a file-read tool is forbidden and does not satisfy the step requirement. All scripts are located in the `scripts` directory of the skill and are designed to be executed with the environment variables set by Step 1.

**DO NOT create, modify, or delete any files other than the source files strictly required to fix a violation.** Do not generate summary files, markdown reports, tracking documents, analysis notes, or any other auxiliary files in the repository or anywhere else. The only file modifications permitted are:
1. Editing C# (or VB) source files to apply violation fixes
2. Git operations (commit, revert)

**If prompt would suggest overriding the setting, it takes priority over environment variable.**. E.g. if user says "fix up to 3 violations in file ABC.cs" then `DOTTEST_STATIC_NO_OF_MAX_FIXES` is set to 1, then fix up to 3 violations.

**NEVER fix a violation by suppressing it.** Do not add suppression comments (e.g. `// parasoft-suppress`), or any other suppression mechanism. A fix must resolve the root cause of the violation in the code itself.

**If all violations have been fixed or are suppressed, do NOT rerun analysis under different conditions (e.g. a different test configuration, different scope, or different filter). Assume all work is done, stop immediately with success status and message: "No violations were found for the given scope".**

**Each fix must be committed in its own separate git commit.** Never batch multiple violation fixes into a single commit. A commit must be created immediately after a fix is successfully verified (Steps 8-9), and before processing the next violation. Each commit must contain changes for exactly one violation only.

**MCP tool calls MUST be executed one at a time, strictly sequentially and synchronously.** Never invoke two or more MCP tools in parallel or in an overlapping manner. Each MCP tool call must fully complete and its result must be received before the next MCP tool call is initiated. This applies to all MCP tools used in this skill (e.g., `get_violations_from_report_file`, `get_rule_documentation`).

**If no `report.xml` with analysis results is provided or referenced at the start of execution, the skill MUST always run the full dotTEST analysis first (Step 3) to produce the report before attempting to identify or fix any violations.** Never skip straight to fixing violations without a freshly generated or explicitly provided report. The report obtained in Step 3 is the mandatory input for Steps 4-8. **If any XML report (provided by `DOTTEST_BASE_STATIC_ANALYSIS_REPORT`, `DOTTEST_BASE_UNIT_TEST_REPORT` or created by Step 3) is about to be read, then always use `dottestmcp` MCP tool. **

## How This Skill Works

### Step 1: Resolve and Validate Configuration

All configuration loading, parsing, validation, and dotTEST installation verification is performed by the **`resolve-config.ps1`** script located in `scripts` directory.

During processing of this skill invoke the `resolve-config.ps1` script **ONCE**. Do NOT rerun this script once it has been corretly executed. If any required variable is missing or invalid, the script prints a descriptive error message and exits with a non-zero code. If the script exits with an error, print `ERROR: Configuration error - [error message from script]` and terminate skill immediately with non-zero exit code.

**For all subsequent steps**, keep the environment consistent with the previous step. Variables resolved and set by `resolve-config.ps1` in Step 1 are available and should not be modified unless specified.

After successful return, the following environment variables are guaranteed to be set and available to all subsequent steps: `DOTTEST_HOME`, `SOLUTION_PATH`, `OUTPUT_DIR`, `DOTTEST_TEST_CONFIGURATION`, `DOTTEST_COMMIT_FIXES`, `DISABLE_UNIT_TEST_VERIFICATION`, `DOTTEST_FILTER_RULE`, `DOTTEST_SETTINGS`, `DOTTEST_BASE_STATIC_ANALYSIS_REPORT`, `DOTTEST_BASE_UNIT_TEST_REPORT`, `DOTTEST_BASE_UNIT_TEST_COVERAGE`, `DOTTEST_STATIC_NO_OF_MAX_FIXES`, `FIXES_BRANCH_NAME`, `DOTTEST_FIX_ATTEMPTS`, `DOTTEST_REFERENCE_BRANCH`, `GIT_BRANCH`, `GIT_WORKSPACE`. **The script writes all those settings to the console. Each one of them should be set if not already provided, unless printed value by the script is `(not set)` - in that case the variable is not set and should be treated as empty string.**

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

Call the `verify.ps1` script from `scripts` directory. The following environment variables are already set and are available to the script: `DOTTEST_HOME`, `SOLUTION_PATH`, `DOTTEST_SETTINGS`, `DOTTEST_BASE_UNIT_TEST_REPORT`, `DOTTEST_BASE_UNIT_TEST_COVERAGE`, `DISABLE_UNIT_TEST_VERIFICATION`.

The script **must** exit with code `0` on success and a non-zero code on failure.

**If the script fails (non-zero exit code)**: print `ERROR: Solution build or unit tests failed. Fix compilation errors or failing tests before running analysis.` followed by the script output, and terminate immediately.

**If `verify` executed unit tests, parse the `REPORT_XML=` value from the last stdout line. If tests were expected but no `REPORT_XML=` line was emitted: FAILURE. If `verify` ran in build-only mode, do not require `REPORT_XML` in Step 2.**
If unit tests were executed, check that there are no unit test failures in the `REPORT_XML` file. If there are any then print `ERROR: Unit tests failed. Fix failing tests before running analysis.` followed by the list of failed tests, and terminate immediately.

### Step 3: Run dotTEST Analysis

**Keep the environment consistent** with the previous step. Variables resolved and set by `resolve-config.ps1` in Step 1 are available and should not be modified. Do not change any variable values or the environment in any way before calling the verification script.

**If user has provided a baseline static analysis report file via `DOTTEST_BASE_STATIC_ANALYSIS_REPORT` check if report exists and its test configuration (`pseudoUrl` attribute of `<TestConfig>` element) match (or is similar to) `DOTTEST_TEST_CONFIGURATION`, if so skip to Step 4.** Otherwise, run the full dotTEST analysis to produce the baseline report, by running the `dottest-analyze.ps1` script with the appropriate environment variables set. This will be the mandatory input for all subsequent steps. Before calling the script, set `DOTTEST_INCLUDE` and `DOTTEST_EXCLUDE` to the semicolon-separated list of scope patterns derived from the user's request in Step 1 (e.g. `**/com/foo/**;**/Bar.cs`), or an empty string if no scope was requested.

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

### Step 6: Fix Violations

**CRUCIAL:**
**In case of simple violations (formatting, whitespace, unnecessary casts, unused imports) where the fix is purely mechanical and does not change logic - fix all such violations in one FILE at a time, then verify.**
**In case of all other violations (logic changes, null checks, resource handling, exception handling, API changes): FIX exactly one VIOLATION at a time, then verify.**

**Fix number of violations defined by `DOTTEST_STATIC_NO_OF_MAX_FIXES`** environment variable. If not set, default is 5 violations, unless stated otherwise in the user prompt (e.g. "fix up to 3 violations in file ABC.cs") - in that case, use the number specified in the prompt. After reaching the maximum number of fixes, stop processing further violations, even if there are more remaining. Increase value of this variable by 1 for each new violation fixed, so that the next violation is processed in the next iteration.

**Include all steps below and VERIFICATION after each fix.**

1. **Get rule documentation** using MCP tool `get_rule_documentation` with the exact rule ID from the violation
2. **Read the entire source file** containing the violation
3. **Generate a minimal fix** - change only the lines necessary to resolve the violation. Do not refactor, rename, or restructure surrounding code. **Never suppress the violation** using annotations or suppression comments (e.g. `// parasoft-suppress`), or any other mechanism - the fix must address the root cause.
4. **Apply the change** using the edit tool. Do not rewrite the entire file.


### Step 7: Validate Fix Results

Before calling the scripts, set the `FIX_NUMBER` environment variable to the current fix number (e.g., "1", "2", "3"). Increase this number by 1 for each new violation fixed, so that the next violation is processed in the next iteration. This variable is used by the scripts to determine the output directory for reports and to track fix attempts. If a fix attempt fails and needs to be retried with a different approach, keep the `FIX_NUMBER` the same for the retry.

1. **Verify the fix by running unit tests** on the project by calling the `verify.ps1` script. **If `DISABLE_UNIT_TEST_VERIFICATION` is set to `true`, skip this substep entirely**. Otherwise, if `DOTTEST_BASE_UNIT_TEST_REPORT` and `DOTTEST_BASE_UNIT_TEST_COVERAGE` are set (either provided by user or created in Step 2), the script automatically runs tests with Test Impact Analysis (TIA) using the baseline files. If no baseline exists, tests run normally without TIA.

2. **Parse the `REPORT_XML=` value from the last stdout line of `verify` in Step 7.1. If `verify` exited with a non-zero code - or no `REPORT_XML=` line was emitted - this is a FAILURE; do not proceed.**
Check that there are no new unit test failures in the report.xml file [located in `[OUTPUT_DIR]/fix-[FIX_NUMBER]/ut/` directory]. If there are any then revert change made in Step 6 and try different approach to fix violation. Number of attempts you can make is defined by  `DOTTEST_FIX_ATTEMPTS`. Keep `FIX_NUMBER` the same in subsequent approaches (increase it only for each new violation fixed). If that fails as well, then skip fixing that violation and try different one. 

3. **Verify the fix by executing dotTEST static analysis** scoped to only the changed file(s).

   For each source file modified by the fix put it's full path into `DOTTEST_FIXED_FILES` environment variable (each separated by semicolon). If full path cannot be extracted compose a pattern similar to one that creates `DOTTEST_INCLUDE`.

   Set the following environment variables before calling the script:
   - `FIX_NUMBER` = current fix number (e.g. "1", "2", "3")
   - `DOTTEST_REF_REPORT_FILE` = `$env:DOTTEST_BASE_STATIC_ANALYSIS_REPORT`
   - `DOTTEST_REF_REPORT_EXCLUDE` = `false`
   - `DOTTEST_FIXED_FILES` = semilcolon-separated list of include patterns for the changed file(s) (e.g. `C:/MySolution/MyProject/class.cs;C:/MySolution/MyProject/struct.cs`)

   Call the `dottest-analyze.ps1` script.

4. **Parse the `REPORT_XML=` value from the last stdout line of `dottest-analyze` in Step 7.3. If `dottest-analyze` exited with a non-zero code - or no `REPORT_XML=` line was emitted - this is a FAILURE; do not proceed.**

Additionally:
- Use `get_violations_from_report_file` on the generated report to confirm whether the specific violation has been resolved
- If any new violations were introduced by the fix (determined by checking the `new="true"` attribute of the violations received from mcp tool), or if the original violation is still present, revert the change made in Step 6 and try a different approach to fix the violation. The number of different approaches you can attempt for each violation is defined by the `DOTTEST_FIX_ATTEMPTS` environment variable. If all attempts fail, skip that violation and move on to the next one and increment `FIX_NUMBER`.
- In case you fail to do that: **FAILURE**
- In same directory as `REPORT_XML` there should be a `dottestcli_build.log` file generated by the script. Read last 20 lines of that log file to determine weather build was successful. If build failed, this is a **FAILURE**.
- Extract all setup problems from `REPORT_XML` (node: `SetupProblems/Problem`), if any new (compared to baseline report) or related to build or complilation are found: **FAILURE**
- Check that at least ONE FILE has been analyzed, otherwise: **FAILURE**

### Step 8: Commit the Changes (only if `DOTTEST_COMMIT_FIXES=true`)

**By default, do NOT commit any changes.** Skip this step unless `DOTTEST_COMMIT_FIXES` is set to `true` in the environment.

If `FIXES_BRANCH_NAME` is set: **create a branch** with name matching that environment variable, then **switch to it** before applying any fixes. If the branch already exists, reuse it. Do this ONCE at the beginning of the process, not per violation. **If `FIXES_BRANCH_NAME` is empty, commit directly to the currently checked-out branch** without creating or switching to any new branch

**One commit per violation - no exceptions.** Each successful fix must be committed individually, immediately after it passes verification (Step 7), before processing the next violation. Never stage or accumulate changes from multiple violations into a single commit. If multiple files were touched to fix a single violation, all of those files are included in that one violation's commit - but no files from any other violation. **If there are pre-existing local changes in the repository that are not related to the fix, do not include them in the commit.** Use explicit file-level staging commands to only stage the files changed for the current violation.

**If `DOTTEST_COMMIT_FIXES=true` and SUCCESS**: Stage only the files modified for the current violation (`git add <file> ...`) and commit with a message in the format:
```
Fix [RULE_ID] violation in [FileName.cs]:[line]

[One-sentence description of the fix applied]

Co-authored-by: [name of CLI AI agent used for the fix]
```

**If `DOTTEST_COMMIT_FIXES=true` and FAILURE**: Revert only files changed for the current fix attempt using explicit file-level restore commands supported in your environment (for example `git restore -- <file>` or equivalent), report the error to the console, and retry exactly once with a different fix approach. If the retry also fails, restore those files again, report the failure to the console, and move on to the next violation. **DO NOT ATTEMPT TO COMMIT ON FAILURE, EVEN IF THE REASON IS UNRELATED TO THE FIX.**

**If `DOTTEST_COMMIT_FIXES` is not set or not `true`**: Leave the fixed files as uncommitted local changes and proceed to the summary.

### Step 9: Summary

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