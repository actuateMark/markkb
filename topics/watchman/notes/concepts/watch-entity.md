---
title: Watch (entity)
author: kb-bot
created: 2026-05-29
updated: 2026-05-29
topic: watchman
type: concept
tags: [watchman, watch-entity, scheduling]
related:
  - "[[topics/watchman/_summary]]"
  - "[[calendar-set]]"
  - "[[2026-05-28_watch-management-service-design]]"
  - "[[2026-05-28_watchman-scheduling-brainstorm-correlation]]"
  - "[[2026-05-29_watchman-prds-summary]]"
incoming:
  - home/offboarding/2026-06-23_firebat-dashboard-ownership-handoff.md
  - home/offboarding/2026-06-23_watchman-fleet-handoff-paolo-mike.md
  - topics/autopatrol/notes/concepts/2026-04-20_cleanup-lambda-runbook.md
  - topics/autopatrol/notes/concepts/2026-04-23_cleanup-rollout-day.md
  - topics/autopatrol/notes/concepts/2026-04-23_immix-api-error-patterns.md
  - topics/autopatrol/notes/concepts/2026-05-04_autopatrol-server-release-process.md
  - topics/autopatrol/notes/entities/autopatrol-aws-objects.md
  - topics/billing/notes/concepts/2026-05-11_billing-reconciliation-dashboard-design.md
  - topics/billing/notes/concepts/2026-05-11_eng-242-substantially-answered.md
  - topics/billing/notes/entities/billing-deferred-backlog.md
incoming_updated: 2026-06-25
---

# Watch (entity)

## Definition

A **Watch** is the customer-facing runtime entity of armed surveillance. It is the combination of:

- one **site**
- one or more **cameras** at that site
- one **product** (intruder, weapon, fire, gun, smoke, etc.)

Schema (per [[watchman-repo|Watchman]] scheduling brainstorm, PM/601686018):

```
Watch(
  id,
  site_id,
  camera_ids: [uuid, ...],
  product: enum,
  timezone: str,   # IANA, denormalized from site for scheduling stability
  active: bool,
  name: str,
)
```

A site can have arbitrarily many Watches. Each Watch has its own armed/disarmed state at any moment.

## Examples

- "Front-lot intruder" = `site:ACME-Reno × cameras:[cam-1, cam-2, cam-3] × product:intruder`
- "Drive-thru weapon" = `site:ACME-Reno × cameras:[cam-4] × product:weapon`

## Properties

- **Armed-state is computed**, not stored as a Watch field. Derived from subscribed calendar sets + active manual overrides; see [[calendar-set]] and the brainstorm's evaluation rules.
- **Timezone lives on the Watch**, not on the calendar event. This lets the same [[calendar-set|CalendarSet]] evaluate against `America/Los_Angeles` for an ACME-Reno site and `America/Chicago` for an ACME-Chicago site without duplicating calendar events.
- **A Watch carries no schedule columns of its own.** It subscribes to one or more `calendar_set` rows via the `watch_subscription` join table.

## Relationship to current connector model

A Watch does not exist as a config object in today's connector code. It projects onto a **predicate** over existing `(camera, stream, feature_deployment)` tuples:

```
applicable_streams(watch) =
  { (camera, stream, feature_deployment)
    | camera.camera_id ∈ watch.cameras
      ∧ check_for_plus(feature_deployment.model_name) == watch.product }
```

Today's connector iterates `feature_deployments` unconditionally; introducing Watches requires either a runtime gate (alert dispatch suppression — cheapest) or a pre-pipeline filter (CPU saving, requires rebuild on arm flip). See [[2026-05-28_watchman-scheduling-brainstorm-correlation]].

## Relationship to Operating Modes

A Watch's armed/disarmed state is **orthogonal to a site's Operating Mode** (Patrol vs. Active Monitoring). Both can be true simultaneously: a site can be in Active Monitoring Mode while only some of its Watches are armed. Mode is site-level Site-Supervisor state; arming is per-Watch manager state. See [[2026-05-29_watchman-prds-summary]] and [[2026-05-29_site-supervisor-vs-watch-manager]].

## Status

**Not yet implemented in code.** As of 2026-05-29, no `class Watch`, `CalendarSet`, or `ManualOverride` exists in any Actuate repo (`actuate-libraries`, `actuate_admin`, `vms-connector`, `Watchman`, `actuate-watchman-internal`). The closest live primitive is `Watchman/db/schema.sql`'s `zones` table with `operating_hours JSONB` — a time-of-day window per zone, not a Watch.

The Watch entity will be net-new code. Manager-service design assumes it as the canonical domain object — see [[2026-05-28_watch-management-service-design]].

## Cross-references

- [[calendar-set]] — the schedule-source-of-truth a Watch subscribes to
- [[2026-05-28_watchman-scheduling-brainstorm-correlation]] — projection onto current connector model
- [[2026-05-28_watch-management-service-design]] — manager-service design built around Watch lifecycle
- [[2026-05-29_site-supervisor-vs-watch-manager]] — relationship to agent-layer
