<!-- DEVBOOKS:START -->
# DevBooks Usage Guide

These instructions apply to Claude Code.

## Language Preference

**Chinese by default**: Unless explicitly requested otherwise, all outputs should be in Chinese, including:
- Documentation content
- Code comments
- Commit messages
- Specifications

## Workflow

Always open `@/AGENTS.md` when the request meets any of the following:
- Mentions planning or proposals (e.g., proposal, spec, change, plan)
- Introduces new features, breaking changes, architecture changes, or major performance/security work
- The request is unclear and you need an authoritative specification before coding

Use `@/AGENTS.md` to understand:
- How to create and apply change proposals
- Spec formats and conventions
- Project structure and guidelines

Keep this managed block so `devbooks update` can refresh the instructions.

<!-- DEVBOOKS:END -->
