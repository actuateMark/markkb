---
type: entity
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [person, engineering, autopatrol, ebus, chm]
outgoing:
  - topics/actuate-platform/notes/concepts/multi-region-deployment.md
  - topics/admin-api/_summary.md
  - topics/alerts-improvements/notes/concepts/immix-dispatch.md
  - topics/autopatrol/_summary.md
  - topics/autopatrol/notes/entities/todo-list.md
  - topics/camera-health-monitoring/_summary.md
  - topics/inference-api/_summary.md
  - topics/integrations/ebus/notes/concepts/phase1-vs-phase2.md
  - topics/personal-notes/_summary.md
  - topics/product-roadmap/_summary.md
incoming:
  - topics/actuate-platform/notes/concepts/multi-region-deployment.md
  - topics/admin-api/_summary.md
  - topics/alerts-improvements/notes/concepts/immix-dispatch.md
  - topics/autopatrol/_summary.md
  - topics/autopatrol/notes/entities/todo-list.md
  - topics/autopatrol/notes/syntheses/2026-04-28_failed-patrol-investigation-handoff.md
  - topics/camera-health-monitoring/_summary.md
  - topics/data-access-control/_summary.md
  - topics/inference-api/_summary.md
  - topics/integrations/ebus/notes/concepts/phase1-vs-phase2.md
incoming_updated: 2026-05-27
---

# Mark Barbera

Mark Barbera is a software engineer at Actuate who works across multiple product initiatives, making him one of the most cross-functional engineers on the team. His current work spans [[autopatrol/_summary|AutoPatrol (H1.2)]], [[camera-health-monitoring/_summary|Camera Health Monitoring (H1.1)]], and the [[external-api/_summary|External API Initiative]] initiative.

## Current Work (April 2026)

Mark's active tickets reflect three distinct workstreams:

- **ENG-106, ENG-107 -- AutoPatrol prototype and bug fixes (In Review).** AutoPatrol is Actuate's automated patrol product (H1.2 initiative, project key AUTO), currently the most active initiative with 50+ open issues. Mark's prototype work is in the review stage, with [[victoria-peccia]] handling QA on the flex ignore-zone features.
- **ENG-126 -- EBUS v5 API (Upcoming).** EBUS is a European integration partner. The v5 API update is still in "To Do" status, blocked behind Mark's current review queue. This is flagged as a key risk in the [[product-roadmap/_summary|Product Roadmap & Initiatives]] because delays here affect European partner onboarding timelines.
- **ED-32 -- EU Deployment work.** Mark contributes to the EU Deployment project (ED), which covers European-specific integrations and compliance requirements including work with Monitex and action log enhancements.

## Cross-Initiative Spread

Mark is explicitly called out in the team structure as one of several engineers who span multiple initiatives: **AUTO + CS3 + ENG (EBUS)**. This breadth means his review queue and context-switching load are significant concerns for scheduling.

## Camera Health Monitoring (CHM)

CHM (H1.1, project key CS3) is now in maintenance mode -- it has launched and is considered a differentiator ([[scene-change-detection|scene change detection]] via SIFT). Mark's ongoing CHM involvement is primarily maintenance and bug-fix work rather than new feature development. [[victoria-peccia]] also handles QA for CHM, specifically around schedule disabling functionality.

## Key Relationships

- Works with [[tatiana-hanazaki]] on AutoPatrol backend (she handles the Admin API side via PROD-116, BACK-638, AUTO-500).
- Works with [[brad-murphy]] on AutoPatrol frontend features (flex IZ, bulk updates, AP schedules).
- EBUS v5 API work connects to the broader [[external-api/_summary|External API Initiative]] initiative that [[vinicius-flores]] also contributes to.

## See Also

- [[autopatrol/_summary|AutoPatrol (H1.2)]] -- the H1.2 initiative
- [[camera-health-monitoring/_summary|Camera Health Monitoring (H1.1)]] -- the H1.1 initiative
- [[active-risks]] -- EBUS delay risk
