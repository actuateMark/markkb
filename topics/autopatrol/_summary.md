---
title: AutoPatrol (H1.2)
type: summary
topic: autopatrol
tags: [autopatrol, h1-2, vlm, flex-ignore-zones, immix, patrol]
jira: "AUTO"
created: 2026-04-13
updated: 2026-04-14
author: kb-bot
---

# AutoPatrol (H1.2)

Automated patrol scheduling product that runs camera patrols, generates clips, and uses VLM (Vision Language Model) analysis for alerting. Partnership with Immix. **Revenue driver: VCH ~$800K/12mo via Immix platform.**

## Current Active Workstreams (April 2026)

### 1. Flex Ignore Zones (Dominant workstream)
Multiple IZ presets per camera, selectable per schedule, with full API + frontend + settings generation.
- **Brad Murphy:** Frontend components (AUTO-446, 427, 424, 425, 493)
- **Tatiana:** API calls (AUTO-500)
- **Victoria Peccia:** QA (AUTO-408, 444, 426)

### 2. VLM Integration
- **Alena Prashkovich:** Prompt Engineering Phase III wrapping up (AUTO-474)
- **Jessica Bae:** VLM-based alerting frontend planning (AUTO-420)
- Models in evaluation: Qwen3-VL-8B-Instruct, Qwen2.5-VL-32B-Instruct-AWQ, Gemma-3-12B-IT-FP8

### 3. Immix Integration
- **Mark Barbera:** Bounding boxes on AP clips to Immix (AUTO-351, ready to deploy)

### 4. Deployment Integration
- **Clarissa Herman:** AP Server/MS integration (AUTO-449)

### 5. Alert Lifecycle Race Condition (Identified April 16, 2026)
- **Deferred alerts fired via `flush_deferred_alerts()` can be lost at patrol exit** — executor tasks killed by process exit before Immix API call completes. See [[2026-04-16_deferred-alert-race-condition]] and [[autopatrol-alert-lifecycle]].
- Fix in progress: drain executor after flush before allowing process exit.

### 6. Generic Patrol Mode (Shipped April 2026)
- **Mark Barbera:** Shipped in PR #1639 to stage (April 13, 2026). See [[generic-patrol-mode]] for architecture.
  - ENG-106 (Done) — `PatrolCamera`, `PatrolSiteManager`, `PatrolFactory`, `PatrolCameraMixin` extraction
  - ENG-107 (Done) — async inference pool with AIMD concurrency, multi-product camera fixes
  - ENG-93 (Done) — S3 frame fallback for deferred alerts
  - ENG-95 (Done) — `queue_stage`/`endpoint_stage` config routing, replaces customer name check

## Key People

| Person | Focus |
|--------|-------|
| Brad Murphy | Frontend (flex IZ, bulk updates, AP schedules) |
| Victoria Peccia | QA (IZ presets, flex IZ) |
| Tatiana | Backend (AP-specific flex IZ API) |
| Alena Prashkovich | DS (VLM prompt engineering) |
| Clarissa Herman | Integration (deployment x AP Server/MS) |
| Jessica Bae | Frontend planning (VLM alerting) |
| Mark Barbera | Immix bounding boxes, generic patrol |
| Otzar Jaffe | ML (YOLOv8 entrance model, datasets) |

## 50+ Open Issues

Most active initiative by issue count. Hot items:
- AUTO-424/493 (Highest, Ready to Deploy) -- Bulk updating FE component
- AUTO-446/500 (High, In Progress) -- Flex IZ on AP schedules
- AUTO-474 (Medium, In Progress) -- Prompt Engineering Phase III

## Relationship to [[watchman/_summary|Actuate Watchman]]

AutoPatrol's patrol scheduling microservice will be adapted for Watchman's Patrol Agent (continuous adaptive scheduling instead of Immix-triggered scheduling). AutoPatrol's context synthesis and recommendation infrastructure feeds into Watchman's Assessment and Recommendation agents.
