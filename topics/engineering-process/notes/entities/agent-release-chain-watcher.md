---
title: "Agent: release-chain-watcher"
type: entity
topic: engineering-process
tags: [agent, release, deployment, ci, argocd, background, context-protection]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
outgoing:
  - topics/engineering-process/notes/concepts/2026-04-17_local-testing-strategies-per-repo.md
  - topics/engineering-process/notes/entities/agent-nrql-investigator.md
  - topics/engineering-process/notes/entities/agents-catalog.md
  - topics/engineering-process/notes/entities/automation-overnight-check.md
  - topics/personal-notes/notes/daily/2026-05-04.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming:
  - topics/engineering-process/notes/concepts/2026-04-17_local-testing-strategies-per-repo.md
  - topics/engineering-process/notes/entities/agent-nrql-investigator.md
  - topics/engineering-process/notes/entities/agents-catalog.md
  - topics/engineering-process/notes/entities/automation-overnight-check.md
  - topics/personal-notes/notes/daily/2026-05-04.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
incoming_updated: 2026-05-08
---

# release-chain-watcher

Tracks a change through the Actuate deployment chain — PR CI → merge → publish/build → [[argocd|ArgoCD]]/ECS/Lambda → post-deploy NR health. Ideal for background execution during long deploys.

**File:** `/home/mork/.claude/agents/release-chain-watcher.md`
**Model:** sonnet
**Background-friendly:** yes

## When to Use

- Monitoring a PR through CI with many checks
- Watching a merge land and verifying deploy propagation
- Post-deploy NR health window (first 15 min)
- Verifying `actuate-libraries` main publish (high-risk path)

## When NOT to Use

- Triggering merges / deploys / force-pushes — agent is watch-only
- One-shot `gh pr checks` from the parent — don't over-engineer
- Root-cause diagnosis of a failed deploy — use `nrql-investigator` for that

## Branch / Environment Semantics Baked In

| Branch | Env | Next gate |
|--------|-----|-----------|
| feature | PR CI | merge |
| `develop` | dev | verify before promoting |
| `stage` | staging | post-deploy NR |
| `rearchitecture` | connector prod | post-deploy + overnight |
| `main` on `actuate-libraries` | CodeArtifact auto-publish | **verify GITHUB_TOKEN workflow triggered** |
| `main` (other repos) | prod | NR watch |

## Gates Watched (in order)

1. PR CI checks green
2. Merge commit landed
3. Publish / build (ECR matrix for connector: ARM64 + x86; Publish Stable workflow for libraries)
4. Deploy ([[argocd|ArgoCD]] sync / ECS rollout / Lambda version bump)
5. Post-deploy NR health (15 min window, error delta vs baseline)

## NRQL Hygiene

Same rules as [[agent-nrql-investigator]] — scoped, aggregated, short-window. Uses `analyze_deployment_impact` when a deploy marker exists.

## Background Usage

- Check cadence: 60-120s during active phases, 5m during NR window
- Streams one-line status updates
- Hard-stop at 30 min total runtime unless extended

## Reporting Format

Compact gate-status blocks (✓ / → / ✗) with timestamps. Final summary < 200 words. On failure, tight diagnosis with action for parent.

## Skill Callers

| Skill | Where in skill | Notes |
|-------|----------------|-------|
| `/stage-release` | Steps 3 (watch CI), 6 (watch deploy), 7 (verify dev) | Primary host skill — use with `run_in_background: true` |

Primary caller is `/stage-release`. Also invoked ad-hoc by the parent when merging PRs outside the skill flow.

## Related

- [[agents-catalog]]
- [[agent-nrql-investigator]] — shares NRQL rules
- [[connector-library-deployment-lifecycle]] — the lifecycle this agent traverses
