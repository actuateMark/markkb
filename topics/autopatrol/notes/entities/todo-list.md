---
title: "AutoPatrol Team Todo List"
type: entity
topic: autopatrol
tags: [autopatrol, todos, tracker, team]
created: 2026-04-13
updated: 2026-04-17
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-01
---

# AutoPatrol Team Todo List

Team-level tracker for AutoPatrol workstreams. Personal tracking lives in [[mark-todos]]; this one reflects what the whole AutoPatrol team is working against.

## Active workstreams

### Stale-schedule cleanup Lambda (Mark)
Immix-side schedule deletions never flow back to our admin DB — stale cronjobs keep firing indefinitely. Building an event-driven cleanup: VMS-connector emits SQS on "no patrols to run", a new Lambda (sibling to the onboarder) verifies via Immix and soft-deletes on admin with full provenance + reversible re-enable.
- Design: [[2026-04-17_stale-schedule-cleanup-design]]
- Entity: [[autopatrol-cleanup-lambda]]
- Connector emit map: [[2026-04-17_no-patrols-emit-points]]
- Admin sync correction: [[2026-04-17_autopatrol-sync-endpoint-behavior]]
- Plan: `/home/mork/.claude/plans/sequential-questing-creek.md`

### Flex ignore zones
Multiple IZ presets per camera, selectable per schedule, with full API + frontend + settings generation.
- [[brad-murphy|Brad Murphy]] — frontend (AUTO-446, 427, 424, 425, 493)
- Tatiana — API (AUTO-500)
- Victoria Peccia — QA (AUTO-408, 444, 426)

### VLM integration
- [[alena-prashkovich|Alena Prashkovich]] — Prompt Engineering Phase III (AUTO-474)
- [[jessica-bae|Jessica Bae]] — VLM-based alerting frontend planning (AUTO-420)
- Models in evaluation: Qwen3-VL-8B-Instruct, Qwen2.5-VL-32B-Instruct-AWQ, Gemma-3-12B-IT-FP8

### Immix integration
- [[mark-barbera|Mark Barbera]] — Bounding boxes on AP clips to Immix (AUTO-351, ready to deploy)

### Deployment integration
- [[clarissa-herman|Clarissa Herman]] — AP Server/MS integration (AUTO-449)

### Alert lifecycle race (identified 2026-04-16)
Deferred alerts via `flush_deferred_alerts()` can be lost at patrol exit — executor tasks killed by process exit before Immix API call completes. See [[2026-04-16_deferred-alert-race-condition]] and [[autopatrol-alert-lifecycle]]. Fix in progress: drain executor after flush before allowing process exit.

## Recently shipped

- **[[generic-patrol-mode|Generic Patrol Mode]]** (April 2026) — Mark, PR #1639 to stage. `PatrolCamera`, `PatrolSiteManager`, `PatrolFactory`, `PatrolCameraMixin`, async [[inference-pool|inference pool]] with AIMD, [[s3-frame-fallback|S3 frame fallback]], queue/endpoint-stage config routing. See [[generic-patrol-mode]].

## Related

- [[knowledgebase/topics/autopatrol/_summary|AutoPatrol topic summary]]
- [[mark-todos]] — Mark's personal tracker (§2 AutoPatrol outstanding, §3 stale-schedule cleanup)
- [[autopatrol-onboarder]] / [[autopatrol-cleanup-lambda]] — sibling Lambdas
- [[knowledgebase/topics/autopatrol/notes/entities/autopatrol-server]]
