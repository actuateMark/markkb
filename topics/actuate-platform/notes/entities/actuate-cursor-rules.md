---
title: "Actuate Cursor Rules"
type: entity
topic: actuate-platform
tags: [cursor, claude-code, ai-tooling, rules, skills, slash-commands, openspec]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Actuate Cursor Rules

Reusable rules, commands, and skills for AI-assisted development, supporting both Cursor and Claude Code. Uses a **skill-first workflow architecture**: skills are the canonical source for multi-step workflows, commands are thin wrappers for deterministic invocation, and rules provide always-on constraints.

Repository: `actuate-cursor-rules` (GitHub: `aegissystems/actuate-cursor-rules`)

## Directory Structure

| Directory | Purpose |
|-----------|---------|
| `rules/*.mdc` | Cursor rules -- agent rules (guardrails, code-quality, tests, docs, commit, rules) and stack rules that auto-activate on file patterns. |
| `commands/` | Cursor slash commands (`.md` files). |
| `.claude/commands/` | Claude Code slash commands -- mirrors `commands/` with inline skill content. |
| `skills/` | Canonical workflow definitions used by both Cursor and Claude Code. |
| `project-rules/` | Per-project rule overrides (e.g., `ds-slicing-microservice`). |
| `scripts/` | Install scripts: `cursor-upsert-rules.sh`, `claude-code-upsert-rules.sh`, `check-tools.sh`. |

## Rules

17 rules in `.mdc` format covering two categories:

**Agent rules** -- behavioral constraints: `guardrails`, `agent-code-quality`, `agent-tests`, `agent-docs`, `agent-commit`, `agent-rules`.

**Stack rules** -- auto-activate by file glob: `stack-rust`, `stack-python-uv`, `stack-shell`, `stack-docker`, `stack-kubernetes`, `stack-terraform`, `stack-yaml`, `stack-json`, `stack-markdown`, `stack-newrelic`, `stack-actuate-library-versions`.

## Commands

23 slash commands, including core development commands (`/commit`, `/debug`, `/explain`, `/lint`, `/review`, `/reword`, `/sweep`, `/test-this`, `/update-docs`, `/new-rule`) and the full OpenSpec (`opsx`) family (`/opsx:new`, `/opsx:continue`, `/opsx:apply`, `/opsx:verify`, `/opsx:sync`, `/opsx:archive`, `/opsx:bulk-archive`, `/opsx:explore`, `/opsx:ff`, `/opsx:multi-proposal`, `/opsx:multi-apply`, `/opsx:onboard`).

## Skills

25+ skills organized in subdirectories under `skills/`. Categories include:

- **Core workflows**: `commit-staged-changes`, `code-quality-sweep`, `generate-tests`, `update-documentation`, `systematic-debug`, `reword-commits`, `agent-sweep`.
- **OpenSpec workflows**: `openspec-new-change`, `openspec-apply-change`, `openspec-continue-change`, `openspec-verify-change`, `openspec-sync-specs`, `openspec-archive-change`, `openspec-explore`, `openspec-ff-change`, `openspec-multi-*`, `openspec-onboard`.
- **Stack workflows**: Per-stack skills (`stack-rust-workflow`, `stack-python-uv-workflow`, `stack-docker-workflow`, etc.) that complement the stack rules.

## Installation

**Cursor**: Link `commands/` and `skills/` into `~/.cursor/`, then symlink rules into each project's `.cursor/rules/` directory. Cursor's Remote Rules feature is currently broken, so local symlinks are the workaround.

**Claude Code**: Run `./scripts/claude-code-upsert-rules.sh` to hard-link commands into `~/.claude/commands/`. `CLAUDE.md` at repo root is auto-loaded and provides guardrails and stack policies.

## Command vs Skill Design Philosophy

Commands are for explicit, deterministic invocation with arguments. Skills activate when users express intent in natural language. High-value workflows maintain both entry points. The canonical mapping lives in `COMMAND_SKILL_MATRIX.md`.

## Relationship to actuate-claude-agents

This repo is the Cursor-native counterpart. The key difference is that `actuate-claude-agents` adds autonomous **agents** (overnight-check, incident-triage, etc.) that have no Cursor equivalent. Rules, commands, and skills overlap and are kept in sync.
