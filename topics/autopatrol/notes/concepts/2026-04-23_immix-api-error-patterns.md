---
title: "Immix API — error patterns for missing schedules"
type: concept
topic: autopatrol
tags: [immix, integration, api-quirks, cleanup-lambda, error-handling]
created: 2026-04-23
updated: 2026-04-29
author: kb-bot
- Error: File "2026-04-23_immix-api-error-patterns" not found.
incoming:
  - Error: File "2026-04-23_immix-api-error-patterns" not found.
incoming_updated: 2026-05-01
---

# Immix API — error patterns for missing schedules

Immix does not adhere reliably to REST conventions. Its response to `GET /api/.../schedule/{schedule_id}` for a schedule that no longer exists on their side is **not a consistent 404**. This note catalogs the patterns we've observed and serves as a watch list for ones we expect to discover.

## The problem this matters for

The cleanup Lambda (`immix-autopatrol-schedule-cleanup`, see [[autopatrol-cleanup-lambda]]) calls `autopatrol_api.get_schedule(tenant_id, schedule_id)` after a schedule crosses its no-patrols threshold. The return value decides one of three actions:

| Verdict | Action |
|---|---|
| `active` | anomaly-reset the DDB counter (safety net — Immix says it's alive) |
| `gone` | PATCH admin `is_deleted=True`, delete DDB row, Slack audit |
| `transient` | raise, SQS retries until redrive policy sends to DLQ |

**Misclassifying a "gone" response as "transient" means the Lambda retries forever** and the schedule never gets cleaned up. That's the exact bug we hit with schedule `636be1ba` — 24h+ of retries with no progress.

## Observed response patterns

### ✅ Handled as `gone`

#### HTTP 404 (expected)
Clean not-found. Standard REST.

#### HTTP 400 + body `"Immix system is unavailable. If this problem persists please contact Immix support team"`
Added 2026-04-23 (PR #7, fix/cleanup-immix-400-as-gone).

**Why this is "gone," not transient:**
- Persists per-schedule (same ID gets the 400 consistently over days)
- Never clears on retry
- Correlates with schedules whose parent site/device was removed in Immix
- The misleading body text is a generic error message, not a real system outage

**Bug trap:** the body text screams "transient" but the behavior is the opposite. The status code + persistence are the real signal, not the body string.

#### HTTP 200 with `scheduleStatus in {Suspended, Paused, Removed, Deleted}`
Admin side has no visibility into these states, and the connector's cronjob keeps firing forever against them with empty patrols lists. We treat them as gone; the re-enable Lambda is the escape hatch if a user un-pauses in Immix later.

### ⚠️ Still handled as `transient` — may be misclassified

#### HTTP 401 / 403
Auth failure. Could be a genuine transient credential issue, OR Immix rejecting access to a schedule that's been moved to a tenant we no longer have access to. **We don't know which.** Current code assumes transient. Watch: if we see 401/403 persistently for the same schedule_id across multiple cadence periods, this should probably also become "gone."

#### HTTP 5xx
Generic server error. Treated as transient. Generally a safe assumption but could mask specific per-schedule failures.

#### `response is None` (network / DNS failure)
Truly transient; no reason to revisit.

### 🔍 Unknown / not yet observed

We don't have a comprehensive catalog because we've only been live in prod for hours (as of 2026-04-23). Future patterns we may discover:

- HTTP 200 with `scheduleStatus` we've never seen (new enum value from Immix side)
- HTTP 200 with `scheduleStatus: null` or missing key
- HTTP 200 with an error-shaped JSON body (e.g. `{"error": "..."}`)
- HTTP 409 / 410 / 422 — Immix using semi-standard codes non-standardly
- Empty response body on non-success status

Any of these currently falls through the `logging.warning(...unexpected status...)` path and returns `transient`. Persistent retries on a specific schedule for any of these = a candidate pattern to add to the `gone` path.

### 🔴 New finding: tenant-level contract violations (2026-04-29)

[[2026-04-29_immix-zombie-tenants]] documents a critical issue: three tenant_ids in EU prod return persistent errors when queried, but don't appear in the contracts listing. The violations include 200-with-empty-body, 400-as-not-found, 401-as-tenant-gone, and inconsistent status codes. This blocks the tenant-cascade-disable design because we have no way to detect "tenant is removed" — only "tenant is paused/suspended". See the full note for API contract details and required Immix fixes.

## Recommended instrumentation (follow-up)

To catch new patterns before they become another 24h-silent-retry bug, add observability to `_check_immix`:

1. **Structured log line on every non-200 path** — include `immix_status_code`, `immix_body_first_100_chars`, `schedule_id`, `tenant_id`, `verdict`. Makes NRQL aggregations trivial:
   ```nrql
   SELECT count(*) FROM Log
   WHERE container_name = 'immix-autopatrol-schedule-cleanup'
   AND immix_status_code IS NOT NULL
   FACET immix_status_code, verdict
   SINCE 7 days ago
   ```
2. **NR custom event `AutoPatrolImmixResponse`** on every `_check_immix` call (sampled or full) — a single query can surface unusual patterns without log-grepping.
3. **Same-schedule-same-status-persistence alert** — any `schedule_id` × `(immix_status_code, verdict=transient)` combination firing 3+ times in 24h ⇒ candidate for reclassification. Paged investigation, not auto-action.

Until then, manual review: after any multi-day "transient error for msg X" cluster in the log, pull the upstream response bodies and classify.

## Code locations

- `cleanup_lambda.py:_check_immix` — the classifier
- `cleanup_lambda.py:REASON_ROUTING` — decides bucket
- `cleanup_dao.py:CleanupCounterDAO` — DDB counter behavior
- The re-enable Lambda (`immix-autopatrol-schedule-reenable`) — reversal mechanism

## Related

- [[autopatrol-cleanup-lambda]] — entity
- [[2026-04-23_cleanup-rollout-day]] — the day we caught the 400 pattern
- [[2026-04-17_stale-schedule-cleanup-design]] — original design
- [[autopatrol-cleanup-lambda#_check_immix decision table]] — if that anchor exists; otherwise update it to reference this note
