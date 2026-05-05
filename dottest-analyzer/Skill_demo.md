# dottest-analyzer Skill Demo (Windows)

This tutorial shows how to integrate the `dottest-analyzer` skill into a coding agent, then analyze and fix static analysis violations in a .NET solution.

- Skill source: `[DOTTEST_HOME]\integration\ai\skills\dottest-analyzer`

For the purpose of this tutorial we demonstrate integration with Codex CLI and GitHub Copilot, but the skill can be used with any coding agent that supports `SKILL.md` skills and has access to dotTEST MCP tools.

## Step 1: Confirm prerequisites

1. Parasoft dotTEST is installed and licensed on Windows.
2. A .NET solution file (`.sln`) is available and builds successfully.
3. Optionally place the solution under local git source control for easier results validation — see Step 7.
4. Powershell is installed (some agents require specific version of the tool). Moreover Set-ExecutionPolicy for user running the tool to `AllSigned` or `RemoteSigned`

## Step 2: Install the skill into your coding agent

Copy the whole `dottest-analyzer` directory (not only `SKILL.md`).

### 2A. Codex CLI

Copy the `dottest-analyzer` directory from `[DOTTEST_HOME]\integration\ai\skills\dottest-analyzer` into your Codex CLI skills directory:

- **Windows:** `%USERPROFILE%\.codex\skills\`

### 2B. GitHub Copilot coding agent

Copy the `dottest-analyzer` directory from `[DOTTEST_HOME]\integration\ai\skills\dottest-analyzer` into your Copilot skills directory:

- **Windows:** `%USERPROFILE%\.copilot\skills\`

Copilot also supports project-local skills — you can place the directory under `.github\skills\` in your project repository instead.

## Step 3: Configure dotTEST MCP tools in your coding agent

The automatic fix workflow requires the agent to have dotTEST MCP tools available
(`get_violations_from_report_file`, `get_rule_documentation`).

See **[DOTTEST_HOME]\integration\mcp\MCP_SETUP.md** for per-agent setup instructions (Codex CLI, GitHub Copilot, Claude Code) on Windows.

## Step 4: Set environment variables

The skill is non-interactive and expects environment variables. Set them before starting the agent.

### Required variables

PowerShell:
```powershell
$env:DOTTEST_HOME  = "<YOUR_DOTTEST_INSTALLATION_DIRECTORY>"   # e.g. C:\Program Files\Parasoft\dotTEST\2026.1
$env:SOLUTION_PATH = "C:\path\to\YourSolution.sln"
```

Command Prompt (`cmd`):
```bat
set "DOTTEST_HOME=<YOUR_DOTTEST_INSTALLATION_DIRECTORY>"
set "SOLUTION_PATH=C:\path\to\YourSolution.sln"
```

### Common optional variables

PowerShell:
```powershell
$env:DOTTEST_TEST_CONFIGURATION  = "builtin://Recommended Rules"   # default
$env:DOTTEST_COMMIT_FIXES        = "false"                         # set to "true" to auto-commit each fix
$env:DISABLE_UNIT_TEST_VERIFICATION = "false"                      # set to "true" to skip unit tests
$env:OUTPUT_DIR                  = "C:\dottest_output"             # defaults to current directory
# $env:DOTTEST_SETTINGS          = "C:\path\to\dottest.settings"
# $env:DOTTEST_FILTER_RULE       = "BD.PB.CC,SEC.VPPD"            # limit to specific rules
# $env:DOTTEST_STATIC_NO_OF_MAX_FIXES = "5"                       # max violations to fix per run
```

Command Prompt (`cmd`):
```bat
set "DOTTEST_TEST_CONFIGURATION=builtin://Recommended Rules"
set "DOTTEST_COMMIT_FIXES=false"
set "DISABLE_UNIT_TEST_VERIFICATION=false"
set "OUTPUT_DIR=C:\dottest_output"
rem set "DOTTEST_SETTINGS=C:\path\to\dottest.settings"
rem set "DOTTEST_FILTER_RULE=BD.PB.CC,SEC.VPPD"
rem set "DOTTEST_STATIC_NO_OF_MAX_FIXES=5"
```

### Alternative: use a config file

Instead of setting individual variables you can point to a pre-filled `dottest-analyzer.config` file:

PowerShell:
```powershell
$env:DOTTEST_ANALYZER_CONFIG = "C:\path\to\dottest-analyzer.config"
```

Command Prompt (`cmd`):
```bat
set "DOTTEST_ANALYZER_CONFIG=C:\path\to\dottest-analyzer.config"
```

A fully annotated template is provided at `[DOTTEST_HOME]\integration\ai\skills\dottest-analyzer\dottest-analyzer.config`.  
Environment variables always take precedence over values in the config file.

## Step 5: Setup dotTEST MCP Server

https://developers.openai.com/codex/mcp

## Step 5: Open the solution directory in your agent

Open or navigate to the directory containing your `.sln` file in the coding agent.

## Step 6: Prepare your agent's command line

Each agent has own specific set of command line settings. To run in the non-interactive mode corretcly you need to set some of those settings depending on agent.
Suggested command line settings:

### Copilot CLI agent

`--add-dir DIR` - if `OUTPUT_DIR` analyzer setting is pointing to other directory than executing directory then you need to specify this command line setting
`--allow-tool='TOOLS'` - two `dottest=analyzer` tools has to be set this way: `get_rule_documentation` and `get_violations_from_report_file`
NOTE: You need to setup dotTEST MCP server separately as it cannot be done in copilot CLI (See: https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-mcp-servers)


Example:
```bat
copilot --allow-tool='dottestmcp(get_rule_documentation),dottestmcp(get_violations_from_report_file)'
```

### Codex CLI agent

`--sandbox danger-full-access` - this is required to run builder and dotTEST CLI for unit tests and/or static analysis validation
`--add-dir DIR` - if `OUTPUT_DIR` analyzer setting is pointing to other directory than executing directory then you need to specify this command line setting

Example:
```bat
echo %CODEX_API_KEY% | codex login --with-api-key
codex exec --sandbox danger-full-access --add-dir "C:\Users\MyUser\CodexOutput" --add-dir "C:\MyGitRepo\" --model "gpt-5.3-codex" "Use dottest-analyzer to fix violations in priority order, fix at most 1 violations."

```

## Step 6: Ask the agent to fix violations

Start the coding agent (for example: GitHub Copilot or Codex CLI).

Tips for first run:
- Keep `DOTTEST_COMMIT_FIXES=false` until you have verified the results.
- Limit fix count to a small number so you can inspect changes before proceeding.

Send this prompt:

```text
Use dottest-analyzer to fix violations in priority order, but fix at most 5 violations in this run.
Do not suppress violations. After each fix, run tests and re-run dotTEST verification against the
baseline report as required by the skill.
```

To target a specific project or file, add scope language to the prompt, for example:

```text
Use dottest-analyzer to fix up to 3 violations in project MyProject.
```

```text
Use dottest-analyzer to fix violations in file BankAccount.cs, exclude test projects.
```

## Step 7: Validate the results

Manually inspect the changes (the solution must be under git source control):

```powershell
git status --short
git diff
```

The skill outputs reports to `OUTPUT_DIR\parasoft-dottest-reports\`. The baseline static analysis
report is at `baseline\sa\report.xml`; fix-verification reports are at `fix-N\sa\report.xml`.

## Step 8: Optional automatic commit mode

If you want the skill to commit each successful fix automatically:

PowerShell:
```powershell
$env:DOTTEST_COMMIT_FIXES = "true"
# Optionally name the fixes branch:
# $env:FIXES_BRANCH_NAME = "my-ai-fixes"
```

Command Prompt (`cmd`):
```bat
set "DOTTEST_COMMIT_FIXES=true"
```

Then rerun Step 6. Each fix is committed individually with a message in the format:

```
Fix [RULE_ID] violation in [FileName.cs]:[line]

[One-sentence description of the fix applied]

Co-authored-by: [AI agent name]
```

## Step 9: Skipping unit tests (optional)

If your solution has no unit tests, or tests are slow, set:

PowerShell:
```powershell
$env:DISABLE_UNIT_TEST_VERIFICATION = "true"
```

Command Prompt (`cmd`):
```bat
set "DISABLE_UNIT_TEST_VERIFICATION=true"
```

The skill will then only verify that the solution builds successfully after each fix (using `devenv`, `dotnet build`, or `msbuild` — whichever is found on `PATH`).

## Step 10: Common failures and quick fixes

| Symptom | Quick fix |
|---|---|
| `DOTTEST_HOME` not set or invalid | Set `DOTTEST_HOME` and verify `dottestcli.exe` exists inside it. |
| `SOLUTION_PATH` not set or file not found | Point `SOLUTION_PATH` to a valid `.sln` file. |
| Build or tests fail at Step 2 | Fix compilation errors or failing tests before running the skill. |
| `DOTTEST_SETTINGS` file not found | Correct the path or unset `DOTTEST_SETTINGS`. |
| `DOTTEST_BASE_UNIT_TEST_REPORT` / `DOTTEST_BASE_UNIT_TEST_COVERAGE` not found | Correct the paths or unset both variables so the skill creates the baseline automatically. |
| No violations found | This is a valid success state — the skill stops with "No violations were found for the given scope". |
| Analysis exits with non-zero code | Check `dottestcli.exe` output above the error line for compilation or license issues. |

## References

- dotTEST Analyzer skill:
    - `[DOTTEST_HOME]\integration\ai\skills\dottest-analyzer\SKILL.md`
- Config file template:
    - `[DOTTEST_HOME]\integration\ai\skills\dottest-analyzer\dottest-analyzer.config`
- dotTEST MCP tools setup:
    - `[DOTTEST_HOME]\integration\mcp\MCP_SETUP.md`
- Copilot skills docs:
    - https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/create-skills
- Claude Code skills docs:
    - https://code.claude.com/docs/en/skills
