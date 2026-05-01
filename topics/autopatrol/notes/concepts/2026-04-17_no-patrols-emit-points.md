---
title: "Connector: Six 'No Patrols to Run' Exit Points"
type: concept
topic: autopatrol
tags: [autopatrol, vms-connector, connector-exit, sqs, emit-signal, monitoring]
created: 2026-04-17
updated: 2026-04-17
author: kb-bot
incoming:
  - topics/autopatrol/notes/concepts/2026-04-22_cleanup-lambda-bake-state.md
  - topics/autopatrol/notes/entities/autopatrol-cleanup-lambda.md
  - topics/autopatrol/notes/entities/todo-list.md
  - topics/autopatrol/notes/syntheses/2026-04-17_stale-schedule-cleanup-design.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-01
---

# Connector: Six "No Patrols to Run" Exit Points

The vms-connector has six code paths where it logs "no patrols to run, exiting" and exits a patrol. These are the sites where a cleanup-signal SQS emit will be wired.

## Exit sites

**File:** `connector_factories/autopatrol/autopatrol_factory.py`
- `:60` — "no patrols to run due to error, exiting" (exception path after retries)
- `:72` — same message, non-OK response after retries
- `:116` — "No patrols to run after all attempts, exiting" (empty patrols list)

**File:** `connector_factories/shared/vch_factory.py`
- `:52`, `:64`, `:103` — mirror of the three cases above for VCH

All six call `exit(0)` — cronjob records success even though nothing ran.

## What's in scope at each emit site

The `autopatrol_config` object is fully populated before the loop runs. Fields available at exit:
- `self.config.autopatrol.tenant_id`
- `self.config.autopatrol.site_id`
- `self.config.autopatrol.schedule_id`
- `self.config.autopatrol.subscription_id`
- `self.config.customer.id` — Actuate-side customer ID (int)
- Pod's **cron cadence** — loaded in `connector.py:95` from `{deployment_id}/settings.json`. Exact field path to confirm at wire-time.

## Retry context

The connector already retries Immix API calls **3 times in-process** with a 10s sleep (`max_attempts = 3`, `retry_sleep_seconds = 10`, `autopatrol_factory.py:40-41`) before any of these terminal exits fire. Each SQS emit therefore represents **3 consecutive failed Immix calls within one invocation**, not a single failure.

## Baseline traffic (NR 7-day snapshot)

- **186 active schedules** emit "no patrols to run" events
- **~24,590 total events** across the 7 days (~3,500/day fleet-wide)
- **96% hourly cadence** (178/186 schedules) — 12 emits/day per schedule under normal operation
- **2 staging schedules** emit ~every 10 minutes (higher test cadence)
- **Zero observable "schedule deleted" events** in logs — deletion status cannot be inferred from logs; must confirm via Immix API

## Related

- [[2026-04-17_stale-schedule-cleanup-design]] — cleanup Lambda that consumes these emits
- [[autopatrol-cleanup-lambda]] — target Lambda entity
- [[vms-connector/_summary]] — connector architecture
