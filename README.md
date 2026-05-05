# dottest-ai-agent-skills

This project contains scripts and skills for LLMs to provide automated static analysis violations fixes in CI/CD pipelines with integration with command line tools like Copilot or Codex.

## Overview

**dottest-ai-agent-skills** enables AI coding agents to understand and automatically fix static analysis violations reported by [Parasoft dotTEST](https://www.parasoft.com/products/parasoft-dottest/). By providing purpose-built skills (prompt instructions and tool definitions), the project bridges the gap between static analysis results and AI-powered remediation in your existing CI/CD workflow.

The skills are designed to work alongside a **Parasoft dedicated MCP (Model Context Protocol) server**, which exposes dotTEST analysis results to the AI agent in a structured, queryable format.

## How It Works

1. **Static analysis** – Parasoft dotTEST analyzes your .NET codebase and produces a set of violations (rule violations, security findings, code quality issues, etc.).
2. **MCP server** – The Parasoft MCP server reads the analysis results and makes them available to compatible AI agents via the Model Context Protocol.
3. **AI agent skills** – The scripts and skill definitions in this repository instruct the LLM agent (e.g. GitHub Copilot, OpenAI Codex) on how to query the MCP server, interpret the findings, and apply code fixes autonomously.
4. **CI/CD integration** – The entire flow runs inside a CI/CD pipeline (GitHub Actions, Azure DevOps, Jenkins, etc.) so that violations are fixed, or at least triaged, on every build without manual developer intervention.

## Features

- Ready-to-use skill definitions for popular AI coding agents (Copilot, Codex, and others compatible with the Model Context Protocol).
- Automated remediation of static analysis violations directly in pull requests or feature branches.
- Seamless integration with Parasoft dotTEST and the Parasoft MCP server.
- Designed for CI/CD pipeline execution – no interactive developer involvement required.

## Prerequisites

| Requirement | Notes |
|---|---|
| [Parasoft dotTEST](https://www.parasoft.com/products/parasoft-dottest/) | Performs static analysis on your .NET project. |
| Parasoft MCP server | Exposes dotTEST results to AI agents via MCP. |
| An AI agent CLI | GitHub Copilot CLI, OpenAI Codex CLI, or any MCP-compatible agent. |

## Getting Started

1. **Set up Parasoft dotTEST** in your CI/CD pipeline and configure it to produce analysis results.
2. **Start the Parasoft MCP server** and point it at the dotTEST results.
3. **Add the skills** from this repository to your AI agent configuration so that the agent knows how to interact with the MCP server and apply fixes.
4. **Run your pipeline** – the agent will automatically query the violations and open fix commits or pull request suggestions.

## Repository Structure

```
dottest-ai-agent-skills/
├── README.md          # This file
└── ...                # Skill definitions and helper scripts
```

## License

See [LICENSE](LICENSE) for details.
