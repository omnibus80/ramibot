---
description: Local G9v3 agent environment
applyTo: "**"
---

# Local G9v3 Environment

A local G9v3-3B model is available through an OpenAI-compatible Chat Completions endpoint.

When working in this repository:

- Treat the entire open workspace as in scope. Read and edit any workspace file needed for the user's task.
- Use VS Code Agent mode and its available workspace tools for repository work; honor VS Code tool approval prompts.
- Use the existing MCP configuration and tools when appropriate. Do not reinstall, replace, or modify MCP Kali.
- Keep model-serving configuration separate from MCP service configuration.
- Inspect logs before retrying a failed service.
