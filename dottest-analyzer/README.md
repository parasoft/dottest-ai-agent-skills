# Fixing Violations Using AI Coding Agents with dotTEST AI Solutions

## Table of Contents

1. [Overview](#overview)
2. [What You Can Achieve with dottest-analyzer](#what-you-can-achieve-with-dottest-analyzer)
3. [Integrating dotTEST AI Solutions with Your Coding Agent](#integrating-dottest-ai-solutions-with-your-coding-agent)
   - [Prerequisites](#prerequisites)
   - [Installation](#installation)
   - [Supported Coding Agents](#supported-coding-agents)
   - [Integrating with Any Other MCP-Compatible Agent](#integrating-with-any-other-mcp-compatible-agent)
4. [Configuration Reference](#configuration-reference)
   - [Required Settings](#required-settings)
   - [Optional Settings](#optional-settings)
   - [Configuration File](#configuration-file)
5. [Usage Examples](#usage-examples)
   - [Example 1: Basic Full-Project Analysis](#example-1-basic-full-project-analysis)
   - [Example 2: Scoped Analysis — Single Project or File](#example-2-scoped-analysis--single-project-or-file)
   - [Example 3: Using a Config File and Settings File](#example-3-using-a-config-file-and-settings-file)
   - [Example 4: Test Impact Analysis for Large Projects](#example-4-test-impact-analysis-for-large-projects)
6. [Best Practices for Reviewing AI-Applied Fixes](#best-practices-for-reviewing-ai-applied-fixes)
7. [Security Considerations](#security-considerations)
   - [Use Coding Agents Responsibly](#use-coding-agents-responsibly)
   - [Grant Only Necessary Tool Access](#grant-only-necessary-tool-access)
   - [Restrict the Agent to Specific Folders](#restrict-the-agent-to-specific-folders)
   - [Configuring Git Commit Access for Codex CLI](#configuring-git-commit-access-for-codex-cli)
8. [CI/CD Integration Workflow](#cicd-integration-workflow)
   - [CI/CD Pipeline Overview](#cicd-pipeline-overview)
   - [Pipeline Stages](#pipeline-stages)
   - [Adapting to other CI systems](#adapting-to-other-ci-systems)
9. [Hands-On Tutorial](#hands-on-tutorial)

---

## Overview

Parasoft dotTEST AI Solutions extend your AI coding agent with the ability to detect and automatically fix C# and Visual Basic static analysis violations. The integration is built around the **`dottest-analyzer` skill** — a non-interactive, fully autonomous workflow that drives dotTEST analysis, collects violations, applies each fix, verifies the result, and optionally commits the change.

The skill works with any .NET solution and integrates with the following coding agents:

| Coding Agent | Identifier |
|---|---|
| GitHub Copilot CLI | `copilot` |
| OpenAI Codex CLI | `codex` |

---

## What You Can Achieve with dottest-analyzer

The `dottest-analyzer` skill enables end-to-end automated static analysis and repair:

- **Run dotTEST static analysis** against your .NET solution using any built-in or custom test configuration (e.g. `builtin://Recommended Rules`, `builtin://CWE Top 25 + On the Cusp 2025`).
- **Collect violations** from the generated report, filter by severity, rule, or file scope, and rank them in prioritized order.
- **Fix violations automatically** — the skill applies each fix, re-runs the build and unit tests, and retries on failure (up to the configured number of attempts).
- **Verify fixes** by re-running dotTEST analysis incrementally after each change and comparing against the baseline report — the same violation must be gone and no new violations introduced.
- **Commit fixes** individually as separate Git commits when `DOTTEST_COMMIT_FIXES=true` is set, giving you a clean, reviewable history.
- **Limit scope** to a project, file, directory, or branch diff so the agent only touches the code you care about.
- **Operate autonomously in CI/CD** — the skill never prompts for user input; all settings are supplied via config file or environment variables.

### What the skill does NOT do

- It never suppresses a violation using `// parasoft-suppress` or any similar mechanism. Every fix must resolve the root cause.
- It never mixes multiple violation fixes into a single commit.
- It does not create pull requests on its own — it only commits to the currently checked-out branch. Branch management is left to the user or CI pipeline.
- It never modifies build scripts, documentation files or any other files unrelated with the change — only C# (or VB) source files strictly needed to fix a violation.

---

## Integrating dotTEST AI Solutions with Your Coding Agent

### Prerequisites

Before installing the integration:

1. **Parasoft dotTEST 2026.1** (or later) must be installed and licensed on the machine where analysis will run.
2. **.NET solution** must build cleanly and all existing unit tests must pass before the skill is invoked (unless they are disabled using the `DISABLE_UNIT_TEST_VERIFICATION` setting).
3. The machine running the agent must have access to the dotTEST installation directory.
4. **PowerShell** must be installed and the execution policy for the running user set to `AllSigned` or `RemoteSigned`.

### Installation

#### Step 1 — Register the dotTEST MCP server

Add the `dottestmcp` server to your agent's MCP configuration. The exact format depends on the agent; refer to its documentation for the correct config file location and schema.

##### GitHub Copilot CLI
```
copilot mcp add dottestmcp "<DOTTEST_HOME>\\integration\\mcp\\dottestmcp.bat"
```

##### Codex CLI
```
codex mcp add dottestmcp "<DOTTEST_HOME>\\integration\\mcp\\dottestmcp.bat"
```

Alternatively, edit the agent's config file.
**JSON-based agents (most common):**
```json
{
  "mcpServers": {
    "dottestmcp": {
      "command": "<DOTTEST_HOME>\\integration\\mcp\\dottestmcp.bat",
      "args": []
    }
  }
}
```

#### Step 2 — Copy the skill

Copy the entire `dottest-analyzer` directory into your agent's skills directory (not only `SKILL.md`):

```
Source: <cloned-repo-root>\
```

##### GitHub Copilot CLI

```
Destination: %USERPROFILE%\.copilot\skills\dottest-analyzer\
```
Copilot also supports project-local skills — you can place the directory under `.github\skills\` in your project repository instead.

##### Codex CLI

```
Destination: %USERPROFILE%\.codex\skills\dottest-analyzer\
```
Alternatively, you can provide the path to the skill directory directly in the Codex command line using:
```
-c "skill_dirs=[<path-to-dottest-analyzer-skill-dir>]"
```

### Supported Coding Agents

| Agent | MCP config file | Skills directory |
|---|---|---|
| GitHub Copilot CLI | `%USERPROFILE%\.copilot\mcp-config.json` | `%USERPROFILE%\.copilot\skills\` |
| Codex CLI | `%USERPROFILE%\.codex\config.toml` | `%USERPROFILE%\.codex\skills\` |

> **Note:** Skills and MCP server configuration placed in the user home directory become available for **all invocations of that coding agent under the current user account**. Most agents also support project-level configuration to limit the scope to a single project — refer to the respective coding agent documentation for details.

### Integrating with Any Other MCP-Compatible Agent

The `dottest-analyzer` skill can be used with **any coding agent that supports MCP tools and `SKILL.md` skills**. If your agent is not listed above, refer to the agent's documentation.
---
## Configuration Reference

All settings are supplied as environment variables. No interactive prompts are issued at runtime.
Alternatively, values can be placed in an optional config file and loaded via `DOTTEST_ANALYZER_CONFIG`. Template for this config file is provided with the skill.

### Required Settings

| Variable | Description |
|---|---|
| `DOTTEST_HOME` | Path to the dotTEST installation directory (e.g. `C:\Program Files\Parasoft\dotTEST\2026.1`). Auto-detected from `PATH` if not set. |
| `SOLUTION_PATH` | Absolute path to the .NET solution file (`.sln`) to analyse. |

### Optional Settings

| Variable | Default | Description |
|---|---|---|
| `OUTPUT_DIR` | *(current directory)* | Absolute path to the directory where output will be stored. **Note**: Some agents require explicit write access to external directories (e.g. Codex CLI requires `--add-dir <OUTPUT_DIR>` to allow writing outside the default sandbox). |
| `DOTTEST_TEST_CONFIGURATION` | `builtin://Recommended Rules` | Test configuration name. Use any built-in profile or a path to a custom configuration. Common built-ins: `builtin://Recommended Rules`, `builtin://CWE Top 25 + On the Cusp 2025`. |
| `DOTTEST_COMMIT_FIXES` | `false` | Set to `true` to automatically commit each successful fix as a separate Git commit. |
| `DOTTEST_FILTER_RULE` | *(all rules)* | Comma-separated rule IDs to process. When set, only violations matching these IDs are fixed. Example: `BD.PB.CC,SEC.VPPD`. |
| `DOTTEST_SETTINGS` | *(none)* | Absolute path to a dotTEST settings file. Adds `-settings=<path>` to all analysis commands. |
| `DOTTEST_BASE_STATIC_ANALYSIS_REPORT` | *(none)* | Absolute path to an existing `report.xml`. When set and its test configuration matches `DOTTEST_TEST_CONFIGURATION`, the analysis step is skipped and this file is used as the baseline. |
| `DOTTEST_BASE_UNIT_TEST_REPORT` | *(none)* | Absolute path to a base unit test `report.xml`. When both this and `DOTTEST_BASE_UNIT_TEST_COVERAGE` are set, the initial verification only checks the build and TIA is used for fix verification. |
| `DOTTEST_BASE_UNIT_TEST_COVERAGE` | *(none)* | Absolute path to a base `coverage.xml`. Required together with `DOTTEST_BASE_UNIT_TEST_REPORT` to enable Test Impact Analysis (TIA). |
| `DISABLE_UNIT_TEST_VERIFICATION` | `false` | Set to `true` to skip unit test execution during build verification. Useful when tests are slow or unavailable. |
| `FIXES_BRANCH_NAME` | *(current branch)* | Name of a new branch to create and switch to before committing fixes. Supports `[timestamp]` substitution (e.g. `my-fixes-[timestamp]`). When not set, fixes are committed directly to the currently checked-out branch. |
| `DOTTEST_STATIC_NO_OF_MAX_FIXES` | `5` | Maximum number of violations to fix in one session. Overridden by an explicit number in the agent prompt (e.g. "fix 3 violations"). |
| `DOTTEST_FIX_ATTEMPTS` | `2` | Number of fix approaches to attempt per violation before giving up (1 original + retries). |
| `DOTTEST_REFERENCE_BRANCH` | *(none)* | Git branch name used as a reference. When set, only violations introduced relative to this branch are analysed. Example: `main`. |

### Configuration File

For team or project-level configuration, copy the `dottest-analyzer.config` template from this repository and set values in a file. Then point the agent to it:

```powershell
# Windows PowerShell
$env:DOTTEST_ANALYZER_CONFIG = "C:\projects\myapp\dottest-analyzer.config"
```

```bat
:: Windows Command Prompt
set "DOTTEST_ANALYZER_CONFIG=C:\projects\myapp\dottest-analyzer.config"
```

Values defined in the file are overridden by any environment variable with the same name, making per-run overrides easy without editing the file.

---

## Usage Examples

### Example 1: Basic Full-Project Analysis

Analyse the entire .NET solution using the default `Recommended Rules` configuration and apply up to 5 fixes, leaving them as local uncommitted changes.

**Windows (PowerShell):**

```powershell
$env:DOTTEST_HOME   = "C:\Program Files\Parasoft\dotTEST\2026.1"
$env:SOLUTION_PATH  = "C:\projects\myapp\myapp.sln"
$env:DOTTEST_COMMIT_FIXES = "false"
```

**Windows (Command Prompt):**

```bat
set "DOTTEST_HOME=C:\Program Files\Parasoft\dotTEST\2026.1"
set "SOLUTION_PATH=C:\projects\myapp\myapp.sln"
set "DOTTEST_COMMIT_FIXES=false"
```

**Agent prompt:**

```
Use dottest-analyzer to fix violations in priority order.
Fix at most 5 violations in this run. Do not suppress violations.
After each fix, verify the build and re-run dotTEST analysis to confirm the violation is gone.
```

---

### Example 2: Scoped Analysis — Single Project or File

Restrict analysis to a specific project or file to keep the session focused and minimise build times.

**Analyse only a specific C# project:**

```powershell
$env:DOTTEST_HOME   = "C:\Program Files\Parasoft\dotTEST\2026.1"
$env:SOLUTION_PATH  = "C:\projects\myapp\myapp.sln"
$env:DOTTEST_COMMIT_FIXES = "true"
```

**Agent prompt:**

```
Use dottest-analyzer to fix all severity-1 violations
in project MyProject. Commit each fix separately.
Fix at most 3 violations.
```

**Analyse only a single file:**

```
Use dottest-analyzer to analyse and fix violations in file BankAccount.cs only.
```

The skill automatically translates natural-language scope expressions into file include/exclude patterns:

| User says | Derived pattern |
|---|---|
| "in project `MyProject`" | `**\MyProject\**` |
| "in file `BankAccount`" | `**\BankAccount.cs` |
| "in directory `src\auth`" | `**\src\auth\**` |
| "exclude tests" | `DOTTEST_EXCLUDE=**\*.Tests\**` |
| differences from `main` branch | set `DOTTEST_REFERENCE_BRANCH=main` |

---

### Example 3: Using a Config File and Settings File

For projects requiring specific analysis settings, keep all configuration in a project-local config file so only a single environment variable needs to be set in the shell.

**Step 1 — Create the config file**

Copy `dottest-analyzer.config` from this repository to your project and fill in the values:

```properties
# .dottest\dottest-analyzer.config

DOTTEST_HOME=C:\Program Files\Parasoft\dotTEST\2026.1
SOLUTION_PATH=C:\projects\enterprise-app\enterprise-app.sln
DOTTEST_SETTINGS=C:\projects\enterprise-app\dottest.settings
DOTTEST_TEST_CONFIGURATION=builtin://CWE Top 25 + On the Cusp 2025
DOTTEST_COMMIT_FIXES=true
DOTTEST_STATIC_NO_OF_MAX_FIXES=5
OUTPUT_DIR=C:\dottest_output
```

**Step 2 — Point the agent to the config file**

```powershell
# Windows PowerShell
$env:DOTTEST_ANALYZER_CONFIG = "C:\projects\enterprise-app\.dottest\dottest-analyzer.config"
```

```bat
:: Windows Command Prompt
set "DOTTEST_ANALYZER_CONFIG=C:\projects\enterprise-app\.dottest\dottest-analyzer.config"
```

**Agent prompt:**

```
Use dottest-analyzer to find and fix security vulnerabilities
in the enterprise-app project. Apply fixes to SQL injection and
resource-leak rule violations only. Commit each fix.
```

---

### Example 4: Test Impact Analysis for Large Projects

For large projects, running the full test suite before and after every fix can be prohibitively slow. dotTEST supports **Test Impact Analysis (TIA)**, which uses a baseline coverage snapshot to determine which tests are actually affected by a code change and runs only those tests.

> **Recommendation:** Enable TIA for any project where a full test run takes more than a few minutes. The one-time cost of generating the base report is usually recovered after the first two or three fix sessions.

#### Step 1 — Generate the base report and coverage snapshot

Run dotTEST with unit test coverage enabled so that per-test coverage data is collected:

**PowerShell:**

```powershell
$env:DOTTEST_HOME  = "C:\Program Files\Parasoft\dotTEST\2026.1"
$env:SOLUTION_PATH = "C:\projects\large-app\large-app.sln"
# Run unit tests with coverage to produce baseline files
& "$env:DOTTEST_HOME\dottestcli.exe" `
    -solution "$env:SOLUTION_PATH" `
    -config "builtin://Run VSTest Tests with coverage" `
    -report "C:\dottest_output\baseline\unit-tests"
```

Both baseline files will be produced in the output directory:

| File | Purpose |
|---|---|
| `baseline\unit-tests\report.xml` | Baseline unit test report — used as `DOTTEST_BASE_UNIT_TEST_REPORT` |
| `baseline\unit-tests\coverage.xml` | Per-test coverage data — used as `DOTTEST_BASE_UNIT_TEST_COVERAGE` |

Commit these files to your repository (or store them as CI artifacts) so they can be reused across sessions without re-running the full suite.

#### Step 2 — Configure the config file

Update (or create) your project-local `dottest-analyzer.config` to reference the baseline files:

```properties
DOTTEST_HOME=C:\Program Files\Parasoft\dotTEST\2026.1
SOLUTION_PATH=C:\projects\large-app\large-app.sln
DOTTEST_TEST_CONFIGURATION=builtin://Recommended Rules
DOTTEST_BASE_UNIT_TEST_REPORT=C:\dottest_output\baseline\unit-tests\report.xml
DOTTEST_BASE_UNIT_TEST_COVERAGE=C:\dottest_output\baseline\unit-tests\coverage.xml
DOTTEST_COMMIT_FIXES=true
DOTTEST_STATIC_NO_OF_MAX_FIXES=10
```

With both baseline files set:
- **The initial build verification switches to build-only mode** — no full test run is performed upfront.
- **Fix verification uses TIA mode** — only tests whose coverage overlaps the changed lines are executed.

#### Step 3 — Point the agent to the config file

```powershell
$env:DOTTEST_ANALYZER_CONFIG = "C:\projects\large-app\.dottest\dottest-analyzer.config"
```

#### Step 4 — Run the agent

```
Use dottest-analyzer to fix the highest-severity violations.
Fix at most 10 violations. Commit each fix separately.
```

#### Keeping the baseline current

After a batch of fixes is reviewed and merged, regenerate the baseline by repeating Step 1. An outdated baseline may miss new violations introduced since it was created, or trigger unnecessary tests for lines that no longer exist.

---

## Best Practices for Reviewing AI-Applied Fixes

AI-generated fixes are applied one at a time, verified by the build and dotTEST re-analysis, and (when `DOTTEST_COMMIT_FIXES=true`) committed with descriptive messages. Still, human review is essential.

### Read the commit messages

Each commit message describes the rule that was violated, the file and line, and the change applied. Read these before merging to understand what was changed and why. A well-formed commit message looks like:

```
Fix BD.PB.CC violation in BankAccount.cs:47

Close stream in finally block to prevent resource leak.
dotTEST rule: BD.PB.CC (severity 1)
```

### Check the code quality

Verify that each fix follows your team's coding standards — naming conventions, error handling patterns, logging style, and architectural boundaries. An AI fix that technically resolves the violation may still introduce patterns that conflict with your codebase conventions.

### Apply incremental fixes for minor remaining issues

If a fix is mostly correct but needs a small adjustment (e.g. a variable name or an error message), do not revert it. Instead, apply your correction as a separate follow-up commit. This keeps the AI-generated fix attributable and your correction clearly visible in the history.

### Revert when the fix is fundamentally wrong

If an AI-generated fix introduces logic errors, breaks a business invariant, or changes semantics in an unacceptable way — revert the entire commit:

```bash
git revert <commit-sha>
```

Do not attempt to partially fix a fundamentally broken change. A clean revert is easier to understand in the history than a patchwork correction.

### Use a branching strategy

Never run automated fixes directly on `main` or a release branch. Use a dedicated feature or fix branch:

```bash
git checkout -b fix/dottest-violations
# run the agent here
git push origin fix/dottest-violations
# open a pull request for review
```

After review, either merge the branch or cherry-pick individual verified commits from it:

```bash
git cherry-pick <commit-sha>
```

This isolates AI-generated changes and gives the team a natural review gate before they reach the protected branch.

### Do not fix all violations at once

Limit the scope of each agent session. Processing all violations in one run makes review impractical, increases the risk of conflicts, and makes it harder to bisect if something goes wrong. Instead:

- Set `DOTTEST_STATIC_NO_OF_MAX_FIXES` to a small number (5–10) per session.
- Scope the analysis to a single project or directory per run.
- Prioritise severity-1 and severity-2 violations first, then revisit lower-severity items in subsequent sessions.
- Review and merge each batch before starting the next.

### Verify test coverage is maintained

After merging a batch of fixes, check that code coverage has not dropped. Unit test reports for each fix are stored in `OUTPUT_DIR\parasoft-dottest-reports\fix-N\unit-tests\` and include coverage data when TIA is enabled.

### Keep the baseline report up to date

When using `DOTTEST_BASE_STATIC_ANALYSIS_REPORT` for incremental workflows, refresh the baseline after each batch of approved fixes. An outdated baseline can cause the skill to re-report already-fixed violations or mis-classify new ones.

---

## Security Considerations

AI coding agents are powerful tools but they execute code, invoke shell commands, and write files on your behalf. Applying a few basic security principles reduces risk significantly.

### Use Coding Agents Responsibly

Treat a coding agent the same way you treat any automation that has write access to your source code:

- **Review every change before merging.** The agent may produce a technically correct fix that has unintended side effects on business logic or introduces a dependency you do not want. No automated tool replaces human judgement at the merge gate.
- **Run agents in a controlled environment.** Prefer a dedicated CI runner, a container, or a sandboxed development machine. Avoid running agents on machines that have production credentials, database access, or access to secrets beyond what the build requires.
- **Audit agent activity.** Enable commit signing and preserve agent-generated commit messages verbatim. This creates a clear audit trail distinguishing human commits from automated ones.
- **Do not accept AI-generated fixes blindly.** The `dottest-analyzer` skill is designed to fix one violation at a time and verify the result, but it can still make mistakes. Treat each commit as a candidate fix, not a guaranteed correct change.

### Grant Only Necessary Tool Access

Configure your agent to expose only the MCP tools it actually needs for the `dottest-analyzer` workflow. Granting access to all available tools increases the attack surface unnecessarily.

The minimum set of MCP tools required by this skill is:

| Tool | Purpose |
|---|---|
| `get_violations_from_report_file` | Read violations from the dotTEST report |
| `get_rule_documentation` | Look up rule details when reasoning about a fix |

### Restrict the Agent to Specific Folders

Where your agent supports folder or file-system sandboxing, configure it to operate only on the C# source tree, not on build scripts, CI configuration, secrets files, or other sensitive directories.

**General principles:**

- Allow read/write access to your project's source root.
- Allow read-only access to build output directories if the agent needs to inspect compiled artifacts.
- Deny access to `.git/config`, CI pipeline definitions (`.github/`, `.gitlab-ci.yml`, `Jenkinsfile`), environment files (`.env`, `*.secret`), and any directory containing credentials or certificates.
- If your agent supports an allowlist of file extensions, restrict writes to `.cs` and `.vb` files only — the skill must never need to modify any other file type.

### Configuring Git Commit Access for Codex CLI

By default, Codex CLI requires explicit permission rules before allowing shell commands. To let the skill commit its fixes, add a rule to the Codex rules file.

Create or append to `%USERPROFILE%\.codex\rules\default.rules`:

```python
# Allow git commit to save fixes made by Codex
prefix_rule(
    pattern      = ["git", "commit"],
    decision     = "allow",
    justification = "Allow git commit so Codex can commit violation fixes",
    match = [
        "git commit -m \"fix violations\"",
        "git commit --all -m \"autofix\"",
    ],
)
```

This rule uses `prefix_rule` to match any `git commit` invocation whose command line begins with `git commit`, while the `match` list further restricts approval to the specific commit message patterns used by the skill. Commands that do not match the `match` patterns are not covered by this rule and will still require interactive approval.

> **Tip:** Keep the `match` list as specific as possible. Avoid wildcard patterns such as `"git commit *"` that would silently approve any commit message the agent might produce outside the expected fix workflow.

Other git operations that the agent does **not** need — such as `git push`, `git rebase`, or `git config` — should **not** be added to the allow list. Require interactive approval for those.

---

## CI/CD Integration Workflow

### CI/CD Pipeline Overview

Integrating dotTEST AI Solutions into your CI/CD pipeline allows you to automatically detect and fix static analysis violations as part of your normal development workflow. Below is a recommended workflow that balances automation with developer oversight.

### Pipeline Stages

**1. Source Control — Code Repository**

The process is initiated when a developer creates a Pull Request to merge changes into the `main` (or `master`) branch. This event acts as the trigger for all downstream automation.

**2. Build Machine**

The pull request triggers the build machine to automatically start the integration process through three sequential steps:

- **Build Project** — source code is compiled and artifacts are produced.
- **Run Tests** — the full suite of unit and integration tests is executed to ensure functional correctness.
- **dotTEST Security Scan** — static analysis is performed using dotTEST to identify security vulnerabilities and compliance violations (see [Configuration Reference](#configuration-reference) for available test configurations).

**3. Automated AI Remediation (conditional)**

If violations are found during the dotTEST scan, the pipeline branches into an automated remediation flow:

- **Create New Branch** — a dedicated branch is created from the feature branch to contain the AI's fixes, keeping the original branch clean.
- **Trigger AI Coding Agent** — the `dottest-analyzer` skill is activated with the dotTEST report as its baseline (`DOTTEST_BASE_STATIC_ANALYSIS_REPORT`), so no second full analysis is needed.
- **Fix Violations** — the agent processes violations in priority order, applies fixes, and verifies each one with a targeted build and re-analysis.
- **Commit Fixed Code** — each verified fix is committed as a separate, descriptive Git commit to the AI branch.

**4. Developer Review and Re-integration**

The developer reviews the AI agent's commits. If satisfied, specific commits are **cherry-picked** from the AI branch back onto the original feature branch:

```bash
git cherry-pick <fix-commit-sha>
```

Commits that are incorrect can simply be left out of the cherry-pick selection. The AI branch can then be discarded.

**5. Code Review and Merge**

Whether the flow came from the normal path (no violations) or the remediation path (fixes cherry-picked), the process continues through the final quality gate:

- **Code Review** — another developer or an automated agent performs a peer review of all changes.
- **Merge to main** — if all changes are accepted and the pipeline is green, the feature branch is merged into `main`.

---

### Adapting to other CI systems

The same pattern applies to Jenkins, GitLab CI, Azure DevOps, and other systems. The key requirements are:

- dotTEST is available on the runner (via installation, container image, or mounted volume).
- The coding agent CLI is installed on the runner.
- The `DOTTEST_HOME` and `SOLUTION_PATH` environment variables are set.
- The runner has a Git identity configured for commits.
- The `GITHUB_TOKEN` (or equivalent) has write permission to push branches and open pull requests.

For **nightly full-project scans**, schedule the workflow on a cron trigger and drop `DOTTEST_REFERENCE_BRANCH` to analyse the entire codebase.


---

## Hands-On Tutorial

`Skill_demo.md` (located alongside this guide in this repository) provides a step-by-step tutorial that walks you through:

1. Confirming prerequisites and setting up the demo .NET solution.
2. Installing the skill and MCP tools into GitHub Copilot CLI or Codex CLI.
3. Setting the required environment variables for your solution.
4. Sending your first prompt to the agent to fix violations.
5. Validating the results with `git diff`.
6. Enabling automatic commit mode.

Start there for a hands-on introduction before applying the skill to your own project.

