---
title: "Session Handoff — Cleanup Lambda Tenant Cascade + VCH Emit Fix + Dashboard Tuning"
type: concept
topic: personal-notes
tags: [handoff, cleanup-lambda, tenant-cascade, vch, dashboard, mark-todos, in-flight, immix]
created: 2026-04-29
updated: 2026-04-29
author: kb-bot
outgoing:
  - topics/personal-notes/notes/concepts/2026-04-30_admin-propagation-handoff.md
  - topics/personal-notes/notes/daily/2026-04-29.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming:
  - topics/autopatrol/notes/concepts/2026-04-29_immix-zombie-tenants.md
  - topics/personal-notes/notes/concepts/2026-04-30_admin-propagation-handoff.md
  - topics/personal-notes/notes/daily/2026-04-29.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-08
---

# Session Handoff — Cleanup Lambda Tenant Cascade + VCH Emit Fix + Dashboard Tuning

**Where you left off:** PR #2376 merged to staging; v2.7.1 release-train (#2377) staging→main is OPEN and CI-green awaiting review; PR #1662 merged to stage; PR #10 still DRAFT; dashboard `connector_no_patrols_to_run_24h` retuned RED→YELLOW; two unrelated RED signals queued for next session.

## The 3 PRs (refreshed 2026-04-29)

| # | Repo | URL | Target | State | Next action |
|---|---|---|---|---|---|
| 1 | [[actuate_admin]] | https://github.com/aegissystems/actuate_admin/pull/2376 | staging | **MERGED 2026-04-28** ✓ deployed to `staging.actuateui.net` | bundled into #2377 — no further action |
| 1.5 | [[actuate_admin]] | https://github.com/aegissystems/actuate_admin/pull/2377 | main | **OPEN** — release-train "v2.7.1" — CI green (5/5), `reviewDecision=REVIEW_REQUIRED` | get review approval + merge to advance §16 sub-step 4b |
| 2 | vms-connector | https://github.com/aegissystems/vms-connector/pull/1662 | stage | **MERGED 2026-04-28** ✓ ECR build green | wait for stage connector pods to recycle through new image (passive) |
| 3 | autopatrol_onboarder | https://github.com/aegissystems/autopatrol_onboarder/pull/10 | master | DRAFT | un-DRAFT + merge ONLY after #2377 deploys to prod admin |

**Note on #2377:** opened by someone else 2026-04-28T17:30Z as the v2.7.1 release-train. Bundles our cascade-disable fix + EMISC-22 (EU CD pipeline), AUTO-345 (AutoPatrol product-metric propagation), EMISC-66 (admin static assets CORS), EMISC-76 (GroupUser scoping), EMISC-79 (Site Hierarchy count distinct), Clips armed check. The cascade-disable endpoint is one of seven changes in this PR; review will be cross-team.

## What's been validated

### Stage admin endpoint (2026-04-28 PM)

- Probe: `autopatrol_onboarder/scripts/probe/stage_disable_tenant_dry_run.py`
- Result: HTTP 200 with cascade scope on both canary tenants (`Remote Security Solutions`, `Legacy`)
- **86 schedules + 85 customers** would be soft-deleted across the 2 canaries when prod cascade fires
- Re-running the probe yields identical counts → dry_run is genuinely non-mutating ✓

### Cleanup Lambda code change (locally + in PR #10)

- 9 unit tests passing; tested:
  - `count >= TENANT_CHECK_THRESHOLD` (default 2) trigger
  - retry semantics on intermediate counts (`>=` not `==`)
  - 3 gates: `DRY_RUN`, `CLEANUP_ENABLED`, `TENANT_CASCADE_ENABLED` (defaults `false`)
  - 10-min suspended-tenants cache TTL
  - fail-soft on Immix outage

### VCH emit fix (vms-connector PR #1662)

- Removed VCH `no_patrols` factory-level emit at `connector_factories/autopatrol/vch_factory.py:115-123`
- Diagnosis: VCH `/Patrols/` is event-driven, not continuously-populated. 100% of VCH `no_patrols` emits over 7d came from one test tenant.
- 6 CI checks green; ECR images built for ARM + x86

## Remaining steps (in order)

| Step | Task | Blocked by |
|---|---|---|
| 1 | [[actuate_admin]] #2377 review + merge to main | review approval (cross-team — release-train) |
| 2 | Verify `/api/auto_patrol/disable_tenant/` live in prod admin via dry_run probe on the 2 canaries | step 1 + CI deploy |
| 3 | autopatrol_onboarder PR #10 un-DRAFT + merge | step 2 |
| 4 | DRY_RUN canary on prod cleanup Lambda (~1h post-Lambda-deploy with `TENANT_CASCADE_ENABLED=false`) | step 3 |
| 5 | Flip `TENANT_CASCADE_ENABLED=true` on prod Lambda env | step 4 canary clean |

## Confidence calibration: is dry_run success sufficient?

**Yes.** Reviewed 2026-04-29:

- The cascade endpoint's **SELECT path is identical** between dry_run and live mode (lines 119–141 of `autopatrol_view.py`). dry_run materializes the exact same row list as live mode and returns the same counts.
- The **MUTATE path** calls `schedule.delete()` and `customer.delete()` per row — these are the same methods the admin UI's "Delete site" button exercises in prod every day. The orchestration is a thin loop over them.
- **Unit test `test_apply_cascades_correctly`** explicitly asserts: `is_deleted=True`, `disabled_by=reason`, `disabled_at`, `deleted_date`, `schedule_status="Deleted"` on every schedule, plus `is_deleted=True` on every customer. Tenant isolation, idempotency, already-deleted-skip all covered.
- **Implementation is careful:** iterate-and-`.delete()` (not bulk `update()`) so soft-delete + undeploy() hooks fire; `schedule_status="Deleted"` belt-and-suspenders so even if `.delete()` is later refactored to drop the undeploy, `should_undeploy=True` keeps the K8s teardown path. All wrapped in `transaction.atomic()`.
- **Stage probe** confirmed dry_run on both canaries returns the expected scope (12 + 74 schedules / 12 + 73 customers) and is non-mutating across re-runs.

**Genuine residual uncertainty:** N=74 schedule.delete() in one `transaction.atomic()` is the only novel load case (each fires an HTTP DELETE to the [[connector-deployer|connector deployer]]). The smaller canary (Remote Security Solutions, 12 schedules) naturally validates this envelope on its next `no_patrols` event before the larger Legacy cascade ever fires — no extra step needed in the rollout. **No Step 4d.5 added.**

## Cleanup Lambda baseline (most recent check 2026-04-29)

- Pipeline state: **GREEN**
- 24h invocations: 19, errors: 0, anomaly resets: 3
- 7d chronic flappers: `fbdfdba6` (9), `c3808175` (9), `ee1822f1` (8), `56de5b0a` (1)
- Lambda `LastModified`: 2026-04-27T14:11Z (still PR #9 — no new deploy since)
- Once §28 merges → Lambda redeploys, `LastModified` will update, `tenant_cascade_enabled` log line should appear with `false`

## Where the canary tenants live

| Tenant | tenantId | Status (Immix) | Cascade scope (stage probe) |
|---|---|---|---|
| Remote Security Solutions | `0ee7cb3f-4a3a-49b0-bcb5-73fce964b427` | Suspended/Suspended | 12 schedules + 12 customers |
| Legacy | `ac399cd6-2fdf-4659-b8e5-baea54075017` | Suspended/Suspended | 74 schedules + 73 customers |

## Dashboard observations + tuning applied 2026-04-29

### `connector_no_patrols_to_run_24h` retuned RED → YELLOW

- Was **RED** at value=29, thresholds `(yellow_above: 0, red_above: 3)` — first-deploy threshold was a guess
- Retuned to thresholds `(yellow_above: 5, red_above: 60)` → now **YELLOW**
- `prior_value=29`, flat across 2 days — not a regression, this is the steady-state baseline
- Backup of prior config: `~/.claude/skills/dashboard-check/config/signals.json.bak.2026-04-29` on firebat
- 3 of 4 chronic flappers contributing to the count are §17 VCH schedules (`c3808175`, `fbdfdba6`, `ee1822f1`) which should drop after vms-connector PR #1662 reaches prod
- **Re-calibrate after #1662 ships** — measure new floor, retighten thresholds. Description field carries this calibration history inline (per `onboarder_activity_us` precedent).
- Re-ran `/dashboard-check` on firebat to confirm new status; status flipped to YELLOW as expected.

### New global rule in CLAUDE.md: dashboard JSON access

- The Caddy server at `http://actuate-dev.local/dashboard/` serves rendered HTML only — `data.json` is **not** exposed (404)
- Canonical source: `ssh mork-firebat 'cat ~/Documents/worklog/dashboard/latest/data.json'` — firebat runs the cron, laptop's local copy is stale
- Top-level keys: `evaluations` (array), `observations`, `overall`, `snapshot_date`, `snapshot_time`
- Each evaluation: `signal_id`, `status` (green/yellow/red), `value`, `baseline`, `thresholds`, `prior_value`, `history`, `description`, `would_have_caught`, `data_source`, `last_observed_at`
- Signal catalog (where to retune thresholds): `~/.claude/skills/dashboard-check/config/signals.json` on firebat

## Other RED dashboard signals — investigation backlog (NOT autopatrol-related)

These surfaced 2026-04-29 alongside the no_patrols retune. Unrelated to cleanup-Lambda or tenant-cascade work — separate threads.

### connector-11202 — 26,838 errors / 24h (top of `fleet_error_top15`)

- Single container generating ~70% of the fleet-wide error volume in the top-15 facet
- Other top contributors: `connector-deploy` (11,049), `connector-10770` (9,126), `connector-26864` (3,930) — substantial cliff to #5+
- No prior context in this session — fresh issue
- **First action for next session:** delegate to `nrql-investigator` agent: 24h error breakdown for `container_name='connector-11202'` FACET by `level` and `error.message` to characterize the error class. Then check `connector-10770` since it's also high.
- Worth checking: do these correlate with the same customer/tenant? Are they all in the same k8s cluster region?

### connector-14170 — chronic OOM offender (top of `fleet_new_oom_offender`)

- 13 OOMKills in 24h — top of fleet, **two days running** (per 2026-04-28 daily-wrap carry-over)
- Already deferred from the §3 cleanup-lambda watch-list discussion 2026-04-28; still pending decision: §3 watch-list vs §9 dashboard signal vs new memory-limit-drift workstream
- Hypothesis from prior investigation: connector pod memory limits drifted below what the workload actually needs — see [[2026-04-23_oom-surge-connector-limit-drift]]
- **Next action for next session:** decide promotion target + update relevant `connector_deployer` / vms-connector GH issues with the memory-limit-drift hypothesis. This was on yesterday's Morning Follow-Up list and got bumped — should not slip another day.

### EU onboarder zombie-tenant finding (2026-04-29)

Found 3 EU tenants in onboarder failure logs that are gone from Immix entirely. One (`c3047b59`, Danish tenant) has 10 orphaned customer rows in EU admin DB. Two others have 0 admin DB rows — origin TBD. Full writeup at [[2026-04-29_immix-zombie-tenants]]. Confirms RSS + Legacy ARE returned Suspended by Immix as expected — the issue is the EU zombie pattern not covered by the design.

### Other context

- `cluster_pending_pods` was RED on the earlier dashboard pull (108) but cleared on the 13:24Z re-run — k8s scheduler caught up. Not actionable; if it returns to RED, that's a separate signal to chase.
- `connector_dummy_model_fallback_24h=4` is YELLOW (threshold yellow_above=0, red_above=5) — known §3-adjacent issue (AUTO-566 config-sync gap). Not regressing.

## KB notes written today (2026-04-28 — 2026-04-29)

- [[2026-04-28_tenant-status-sync-gap]] — full architectural background, probe results, implementation status
- [[2026-04-28_chronic-flapper-investigation]] — flapper class breakdown (VCH vs Paused), reusable probe scripts

## mark-todos workstreams in scope

- **§16** — Tenant-status sync gap (Steps 1–3 done; Step 4 has subtasks 4a–4e laid out with exact commands; 4a verified clean on stage; 4b is "PR #2377 review + merge" not "open the PR")
- **§17** — VCH no_patrols false-emit (investigation done; PR #1662 is the deliverable; 3 subtasks pending stage soak)
- **§3** — cleanup Lambda parent workstream (steady-state monitoring; Step E.3 4-day soak GREEN per 2026-04-27)
- **§3 carry-over (deferred 2026-04-28 → 2026-04-29):** connector-14170 OOM promotion-target decision (see "Other RED" above)
- **§9** — Operational Dashboard (this handoff's tuning falls under Phase 1b — first calibration of a freshly-added signal)

## Probe scripts (all in `autopatrol_onboarder/scripts/probe/`, in PR #10)

| Script | Purpose |
|---|---|
| `tenant_status_probe.py` | Confirms Immix has no `/Tenants` endpoint but exposes `tenantStatus` per contract. Re-run periodically to monitor suspended-tenant population. |
| `flapper_schedule_probe.py` | Given (schedule_id, tenant_id) pairs, fetches `scheduleStatus` + title via Immix `/Schedules/{id}`. Used for chronic-flapper diagnosis. |
| `flapper_patrol_stream_probe.py` | Placeholder — cleanup Lambda's actual classifier calls `get_schedule`, NOT `get_patrol_stream`. Kept for reference. |
| `stage_disable_tenant_dry_run.py` | Hits the new `/api/auto_patrol/disable_tenant/` endpoint with `dry_run=true` for canary tenants. Pulls token from `prod/actuate/postgres` Secrets Manager (key `api-token-{stage}`). |

All require `AUTOPATROL_API_KEY` env var (or `ADMIN_API_TOKEN` for the stage probe). Standard recipe:

```bash
export AUTOPATROL_API_KEY="$(AWS_PROFILE=prod aws lambda get-function-configuration \
  --function-name immix-autopatrol-schedule-cleanup --region us-west-2 \
  --query 'Environment.Variables.AUTOPATROL_API_KEY' --output text)"
.venv/bin/python scripts/probe/<probe>.py
```

## Critical safety notes for the prod rollout

1. **Cleanup Lambda auto-deploys on push to master.** PR #10 must stay DRAFT until admin endpoint is in prod admin. Otherwise the Lambda would deploy with code that calls a non-existent endpoint (although the cascade is also gated by `TENANT_CASCADE_ENABLED=false`, so even an early deploy would no-op).
2. **`Customer.delete()` triggers `delete_immediate_group()`** — when the last active customer in a Group drops to ≤1, the parent Group is also soft-deleted. Expected behavior for suspended tenants but worth eyeballing the first prod cascade.
3. **`schedule.delete()` issues N HTTP DELETEs** to the [[connector-deployer|connector deployer]] (1 per schedule). For Legacy tenant cascade, that's 74 deployer calls — done via `transaction.atomic()` so they're a tight batch.
4. **`TENANT_CASCADE_ENABLED` defaults `false`** on Lambda env — must be explicitly flipped after canary clean via `aws lambda update-function-configuration`.

## Quick-resume checklist for next session

1. Read this doc top-to-bottom (~3 min)
2. `gh pr view 2377 -R aegissystems/actuate_admin --json state,reviewDecision,mergeable,mergeStateStatus` — has the v2.7.1 release-train been merged yet? If yes, jump to step 5.
3. `gh pr view 10 -R aegissystems/autopatrol_onboarder` — still DRAFT? (confirm before any action)
4. `ssh mork-firebat 'cat ~/Documents/worklog/dashboard/latest/data.json' | jq '[.evaluations[] | select(.status == "red") | {signal_id, value, thresholds}]'` — any new RED signals since 2026-04-29?
5. Run `/autopatrol-cleanup-lambda-check` for cleanup Lambda baseline.
6. **If #2377 merged + admin endpoint live in prod:** un-DRAFT PR #10 → CI → merge → Lambda redeploys with `TENANT_CASCADE_ENABLED=false`. Wait ~1h, run §16 sub-step 4d DRY_RUN canary log scrape (commands in mark-todos §16). If clean, flip the flag (4e).
7. **If #2377 not merged yet:** nudge for review, then pivot to investigation backlog (connector-11202 errors / connector-14170 OOM — see "Other RED" above).

## Backlog for when the rollout idle-waits

The PR rollout has long passive windows (review wait, deploy wait, soak wait). Use those for:

- **connector-11202 / connector-10770 error spike** — `nrql-investigator` agent, characterize the error class
- **connector-14170 OOM promotion-target decision** — §3 carry-over from 2026-04-28; decide §3 vs §9 vs new workstream
- **#1662 stage pod recycle verification** — check that the VCH `no_patrols` count drops in stage logs (§17 24h post-merge gate)
- **Re-calibrate `connector_no_patrols_to_run_24h` thresholds** — once #1662 reaches prod, measure new fleet-wide floor and retighten yellow/red bands

## Links

- Topic: [[autopatrol/_summary]]
- Sister investigation: [[2026-04-28_chronic-flapper-investigation]]
- Architectural background: [[2026-04-28_tenant-status-sync-gap]]
- Cleanup Lambda runbook: [[2026-04-20_cleanup-lambda-runbook]]
- Cleanup Lambda entity: [[autopatrol-cleanup-lambda]]
