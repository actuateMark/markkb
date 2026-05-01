---
title: "Actuate Claude Agents"
type: entity
topic: actuate-platform
tags: [claude-code, agents, ai-tooling, devops, slash-commands, skills, new-relic]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-platform/notes/entities/architecture-decision-records.md
incoming_updated: 2026-05-01
---

# Actuate Claude Agents

Reusable agents, commands, and skills for Claude Code across Actuate repositories. This is the agent-first counterpart to [[actuate-cursor-rules]], adding autonomous multi-step workflows that have no equivalent in Cursor.

Repository: `actuate-claude-agents` (GitHub: `aegissystems/actuate-claude-agents`)

## Architecture

The repo follows an **agent-first workflow architecture**:

| Directory | Purpose |
|-----------|---------|
| `.claude/commands/` | Deterministic slash commands invoked via `/command-name` in Claude Code. |
| `agents/` | Autonomous multi-step workflows -- Claude delegates based on task description. |
| `skills/` | Domain knowledge injected into context when relevant. |
| `CLAUDE.md` | Guardrails and stack policies, auto-loaded in any project that symlinks it. |
| `scripts/` | `install.sh` (global install) and `check-tools.sh` (verify tool availability). |

## Commands

Ten slash commands available via `.claude/commands/`: `/commit`, `/commit-msg`, `/debug`, `/explain`, `/lint`, `/review`, `/reword`, `/sweep`, `/test-this`, `/update-docs`. These are deterministic -- invoked explicitly by name.

## Agents

Seven autonomous agents that Claude matches to tasks by description:

| Agent | Purpose | Dependencies |
|-------|---------|-------------|
| `library-bump` | Bump actuate-* library versions in `pyproject.toml` + `uv.lock` | -- |
| `overnight-check` | Morning [[health-report|health report]] across test sites | [[new-relic|New Relic]] MCP |
| `incident-triage` | Investigate crashes, OOMKills, missing videos for a site | [[new-relic|New Relic]] MCP, kubectl |
| `stage-deploy-check` | Verify a deploy landed (image tag, pod health, errors) | [[new-relic|New Relic]] MCP, kubectl |
| `pr-prep` | Prepare stage-to-rearchitecture PRs | -- |
| `metric-compare` | Compare NR metrics between sites or time windows | [[new-relic|New Relic]] MCP |
| `fork-safety-check` | Scan for thread creation in `__init__` (fork-unsafe patterns) | -- |

Several agents require MCP servers ([[new-relic|New Relic]]) and/or kubectl access.

## Skills

Two domain-knowledge skills:

- **`nr-connector-metrics`** -- [[new-relic|New Relic]] metric names, query patterns, account ID, test site mappings.
- **`connector-log-review`** -- Error patterns, startup/runtime/shutdown health checks for VMS connectors.

## Installation

Global install (all projects): clone the repo, run `./scripts/install.sh`. This hard-links commands and agents into `~/.claude/`, making them available everywhere. For per-project guardrails, symlink `CLAUDE.md` into the target project root.

## Guardrails

`CLAUDE.md` enforces: research-first investigation, minimal diffs, conventional commits, verification with evidence, and per-stack policies (Rust, Python/uv, Shell, Docker, Kubernetes, Terraform, YAML, JSON, Markdown, [[new-relic|New Relic]]/NRQL).

## Connector-Specific Tooling (vms-connector repo)

The `vms-connector` repo maintains its own skill library at `.claude/skills/` that extends the global agent set with connector-specific procedures. These live in the connector repo, not in `actuate-claude-agents`.

| Skill | Purpose |
|-------|---------|
| `/pre-merge-workflow` | Mandatory ordering before merging a connector feature branch: merge library PRs to main → wait for stable CodeArtifact publish → bump stable pins → run local tests → merge. Non-negotiable sequence. |
| `/stage-release` | End-to-end release: merge PR to stage, monitor ECR build (ARM64 + x86), verify deployment rollout, post-merge cleanup. |

The connector repo also carries 16+ other skills covering log review, [[new-relic|New Relic]] queries, operational triage, rolling restarts, and changelog generation. See `CLAUDE.md` in `vms-connector` for the full table.

## Relationship to actuate-cursor-rules

This repo is the Claude Code equivalent. The key addition is **agents** -- autonomous subprocesses that Cursor cannot run. Cursor rules (`.mdc` with globs) map to `CLAUDE.md` sections; Cursor skills map to Claude skills + agents; commands are identical across both tools.
