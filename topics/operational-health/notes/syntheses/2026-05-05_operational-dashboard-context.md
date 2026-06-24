---
title: "Operational Dashboard — workstream context (factored from mark-todos §9)"
type: synthesis
topic: operational-health
tags: [operational-dashboard, mark-todos-factored]
created: 2026-05-05
updated: 2026-05-05
author: kb-bot
incoming:
  - topics/engineering-process/notes/syntheses/2026-06-22_actuate-footprint-handoff.md
  - topics/offboarding/notes/concepts/2026-06-23_firebat-dashboard-ownership-handoff.md
  - topics/personal-laptop/notes/syntheses/2026-05-05_claude-context-optimization.md
  - topics/personal-notes/notes/concepts/2026-06-22_dashboard-signals-catalog.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-06-24
---

Factored out of mark-todos §9 on 2026-05-05 to keep the live workstream tracker lean. See [[mark-todos]] §9 for active checkboxes.

## Scope (cross-repo, not just AutoPatrol)

In-scope components:

| Component | Silent-regression risk | Candidate signal(s) |
|---|---|---|
| `vms-connector` (fleet) | high | `patrol-exit emits/day`, OOMKills (new per-container chronic pattern), `streamId Guid` rejection count, CNCTNFAIL rate per site |
| `actuate-libraries` (pullers / pipeline / daos / etc.) | medium | version drift alerts; consumer-side import check |
| `actuate-inference-api` | high | per-model detection throughput, 4xx/5xx rates, per-partner-API-key activity |
| `actuate_admin` (Django + RBAC) | medium | schedule-activation rate, tenant-create success, RBAC denial patterns |
| `autopatrol_onboarder` (3 Lambdas) | HIGH | per the [[2026-04-23_alarm-dashboard-sketch]] (onboarder liveness + cleanup + reenable) |
| `autopatrol-server` | medium | patrol-completion rate, CNCTNFAIL per site |
| `camera-ui` + `alert-ui` | low-medium | error rate from browser telemetry |
| Alert-delivery pipeline (`queue-*`, `smtp-frame-receiver`, `clips-smtp-worker`) | HIGH | queue depth, per-integration delivery rate |

## Principles (design-for-monitoring — echoed in fleet-arch + software-arch + engineering-process)

1. **Behavioral signals, not surface metrics.** `Errors=0`, `Invocations>0`, `200 OK` are not health signals. Activity-marker log lines + downstream side effects are.
2. **1–2 signals per component, reviewable in <60 seconds total.** Dashboard is for quick scan; drill-down is on-demand.
3. **Monitoring-friendliness is a first-class design dimension.** Every fleet-architecture proposal and every software-architecture sketch must answer "how do I know this is working?" before it's signed off.
4. **Every repo owns its signals.** Per-repo `CLAUDE.md` carries the acceptance-criteria + signal-set definition. When a new feature ships, its signals must be added before merge.
5. **Cross-repo aggregator is the daily-check surface.** `/dashboard-check` queries each per-repo signal set and renders one consolidated view.

## Cross-topic integration

- **`engineering-process`** — release-acceptance-criteria rule ([[2026-04-23_release-acceptance-criteria]]) filed here. Release-related notes treat "post-deploy verification against acceptance criteria" as mandatory.
- **`fleet-architecture`** — every proposal (A, B, C, D, E) must include a "monitoring & alarms" subsection.
- **`software-architecture`** — sketches must demonstrate monitoring hooks from the start. Code-health vs operational-health dashboards are kept distinct with cross-link.

## Phasing (proposed)

- ~~**Phase 0:** signal inventory~~ — complete
- ~~**Phase 1a:** build `/dashboard-check` skill, end-to-end smoke~~ — shipped 2026-04-23
- **Phase 1b (in progress):** signal-set expansion + replay tests + advanced regression rules — 15/19 signals enabled
- **Phase 2:** extend CLAUDE.md rules to every in-scope repo; add acceptance-criteria enforcement to `/stage-release` + `/post-deploy-monitor`.
- **Phase 3:** build the dashboard UI (CW or NR) for non-skill-based review; instrument missing NR wiring.
- **Phase 4 (ongoing):** negative feedback loop — any incident that surfaces a missing signal triggers a signal-set update.

## Related

- [[2026-04-23_postmortem-onboarder-healthcheck]] — the trigger
- [[2026-04-23_alarm-dashboard-sketch]] — AutoPatrol-scoped precursor (generalized here; old §9 archived [[2026-04-23]])
- [[2026-04-23_release-acceptance-criteria]] — the global rule this workstream operationalizes
- [[2026-04-24_dashboard-1b-continuation]] — pickup doc
- [[feedback_fail_fast_guards]] — hard rule surfaced by the incident
- [[feedback_acceptance_criteria_every_merge]] — hard rule surfaced by the incident
- [[skill-autopatrol-cleanup-lambda-check]] / [[skill-autopatrol-overnight-check]] — per-repo check-skill pattern
- [[2026-04-14_connector-fleet-monitoring]] — existing fleet-monitoring synthesis (partial overlap)
- [[2026-04-16_code-health-dashboard]] — adjacent dashboard concept (code-health, not ops-health)
- Skill chain (target): `/daily-scope` → `/dashboard-check`; `/stage-release` → `/post-deploy-monitor` → `/dashboard-check`
