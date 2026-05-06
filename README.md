# dottest-ai-agent-skills

This project contains skills and scripts that enable AI coding agents to automatically detect and fix static analysis violations reported by [Parasoft dotTEST](https://www.parasoft.com/products/parasoft-dottest/).

## Overview

**dottest-ai-agent-skills** bridges the gap between dotTEST static analysis results and AI-powered remediation in your CI/CD workflow. Each skill packages prompt instructions and helper scripts so that a supported coding agent can run analysis, apply fixes, verify them, and optionally commit the changes — all without human intervention.

Skills interact with a **Parasoft MCP (Model Context Protocol) server** that exposes dotTEST analysis results to the agent in a structured, queryable format.

## How It Works

1. **Static analysis** – Parasoft dotTEST analyses your .NET codebase and produces a violation report.
2. **MCP server** – The Parasoft MCP server reads the report and makes violations available to the AI agent via the Model Context Protocol.
3. **AI agent skill** – The skill instructions and scripts in this repository tell the agent how to query violations, apply code fixes, verify them with a build/test run and an incremental re-analysis, and commit the result.
4. **CI/CD integration** – The entire flow runs inside a CI/CD pipeline (GitHub Actions, Azure DevOps, Jenkins, etc.) with no interactive developer involvement.

## Available Skills

| Skill | Description |
|---|---|
| [`dottest-analyzer`](dottest-analyzer/README.md) | Runs dotTEST static analysis on a .NET solution, collects violations, applies fixes, verifies each fix, and optionally commits changes. Supports scope limiting, Test Impact Analysis, branch-diff mode, and full CI/CD automation. |

## Prerequisites

| Requirement | Notes |
|---|---|
| [Parasoft dotTEST](https://www.parasoft.com/products/parasoft-dottest/) 2026.1+ | Performs static analysis and unit-test verification on your .NET project. |
| Parasoft MCP server | Exposes dotTEST results to AI agents via MCP. Bundled with dotTEST under `<DOTTEST_HOME>\integration\mcp\`. |
| AI agent CLI | GitHub Copilot CLI or OpenAI Codex CLI (any MCP-compatible agent with `SKILL.md` support). |
| PowerShell | Execution policy set to `AllSigned` or `RemoteSigned`. |

## Getting Started

1. **Register the MCP server** with your agent (see the skill README for exact commands).
2. **Copy the skill directory** (e.g. `dottest-analyzer/`) into your agent's skills directory.
3. **Configure required settings** — at minimum `DOTTEST_HOME` and `SOLUTION_PATH` — via environment variables or a config file.
4. **Run your pipeline** – the agent will run analysis, apply fixes, and commit them as individual commits on the current branch.

See [dottest-analyzer/README.md](dottest-analyzer/README.md) for full installation, configuration, and usage instructions.

## Repository Structure

```
dottest-ai-agent-skills/
├── README.md                        # This file
└── dottest-analyzer/                # dottest-analyzer skill
    ├── SKILL.md                     # Skill instructions consumed by the AI agent
    ├── README.md                    # Full installation and usage guide
    ├── SKILL_DEMO.md                # Hands-on walkthrough / demo script
    ├── dottest-analyzer.config      # Annotated configuration file template
    ├── docs/
    │   └── scope_limitation.txt     # Pattern syntax for analysis scope limiting
    └── scripts/
        ├── dottest-analyze.ps1      # Runs dotTEST analysis
        ├── resolve-config.ps1       # Loads and validates configuration
        └── verify.ps1               # Verifies build and unit tests after a fix
```
