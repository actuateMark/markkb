---
title: "Agent: connector-pipeline-expert"
type: entity
topic: engineering-process
tags: [agent, vms-connector, actuate-libraries, codebase-exploration, read-only]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
---

# connector-pipeline-expert

Read-only domain expert for the VMS connector and the 41-package actuate-libraries monorepo. Answers "where does X happen" without pulling a large codebase into the parent context.

**File:** `/home/mork/.claude/agents/connector-pipeline-expert.md`
**Model:** opus (deep reasoning over a large codebase)
**Mode:** read-only

## When to Use

- "Where in the pipeline does filter X run?"
- "Which library implements Y?"
- "How is config field Z threaded from YAML to the pipeline stage?"
- "Which sender handles integration partner P?"
- "How does AIMD / BoTSORT / sliding-window work in code?"

## When NOT to Use

- Questions about admin-api, inference-api, watchman, or infrastructure — out of scope
- Tasks that require edits — agent is read-only
- Trivial single-file reads the parent can do in one tool call

## Hard Scope

Reads only from:
- `/home/mork/work/vms-connector/`
- `/home/mork/work/actuate-libraries/`
- `/home/mork/Documents/worklog/knowledgebase/topics/{vms-connector,actuate-libraries,integrations}/`

Anything outside → agent declines.

## Architecture It Knows

- Chain-of-responsibility pipeline (default / gauntlet / local / healthcheck)
- Pre → Inference (AsyncInferencePool, AIMD) → Post → Observers
- Post-processors: Stationary, IOU, Ignore Zones, Confidence, Blacklist, Sliding Window, Confirmation, Alerting
- Observers: Intruder, Loiterer (BoTSORT), Line Crossing, Blacklist
- Library clusters: core processing, camera/stream, alert delivery, persistence
- Deployment: `rearchitecture` namespace, ArgoCD from `aegissystems`

## Reporting Format

- **Where it lives:** `path:line` pointers
- **How it works:** 2-5 mechanism bullets
- **Config knobs:** YAML field → code path (when asked)
- **Related:** KB wikilinks

Target < 400 words. No code dumps — pointers only.

## Skill Callers

| Skill | Where in skill | Notes |
|-------|----------------|-------|
| `/generate-project-docs` | Phase 1 (Explore the Codebase) | Only when target repo is vms-connector or actuate-libraries; otherwise use Explore agent |

Lightly used. Primarily invoked ad-hoc from the parent for architecture questions, not inside skill flows.

## Related

- [[agents-catalog]]
- [[vms-connector/_summary|VMS Connector topic]]
- [[actuate-libraries/_summary|Actuate Libraries topic]]
