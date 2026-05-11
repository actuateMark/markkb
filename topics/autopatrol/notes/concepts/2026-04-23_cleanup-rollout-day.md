---
title: "Cleanup Lambda Rollout Day — 2026-04-23"
type: concept
topic: autopatrol
tags: [autopatrol, cleanup-lambda, rollout, hotfix, threshold-tuning, incident-day, immix, immix, immix, immix, immix]
created: 2026-04-23
updated: 2026-04-23
author: kb-bot
outgoing:
  - topics/actuate-platform/notes/entities/actuate-admin-api.md
  - topics/personal-notes/notes/daily/2026-04-23.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
incoming:
  - topics/actuate-platform/notes/entities/actuate-admin-api.md
  - topics/autopatrol/notes/concepts/2026-04-23_immix-api-error-patterns.md
  - topics/autopatrol/notes/concepts/2026-04-24_stale-schedule-cleanup-investigation.md
  - topics/autopatrol/notes/concepts/2026-04-28_chronic-flapper-investigation.md
  - topics/autopatrol/notes/concepts/2026-04-28_tenant-status-sync-gap.md
  - topics/autopatrol/notes/concepts/2026-05-07_handoff-cleanup-lambda-interpretive-checks.md
  - topics/autopatrol/notes/syntheses/2026-04-24_stale-schedule-cleanup-aar.md
  - topics/personal-notes/notes/daily/2026-04-23.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
incoming_updated: 2026-05-08
---

# Cleanup Lambda Rollout Day — 2026-04-23

Day-in-the-life reference for the cleanup Lambda's rollout from "dark-mode baked" to "live with tight threshold." Preserved as a condensed narrative because several decisions compressed into a few hours have longer-horizon implications that future sessions may want to trace.

## Timeline (UTC)

| Time | Event |
|---|---|
| 08:54 | First post-2026-04-21-deploy ERROR lines logged for the onboarder: `Failed to connect to AutoPatrol API: <Response [404]>`. Nobody notices. |
| ~14:35 | Customer reports: "can't create new schedules and set them to Active." |
| 14:45 | Triage: both US + EU onboarder Lambdas 404-bailing since the 2026-04-21T16:20 deploy. |
| 14:55 | Root cause: `if res.status_code not in [200, 201]: return` added silently in the cleanup-Lambda merge (PR #3). Upstream `/healthcheck` endpoint has been 404'ing for a long time; old code ignored it; new code returns early. |
| 15:00 | Hotfix PR #4 opened (downgrade `logging.error + return` → `logging.warning`, no abort). |
| 15:04 | PR #4 merged + deployed. First post-hotfix invocation at 15:04:52 runs 3+ minutes processing contracts (vs previous 400ms early-exit). |
| ~15:30 | Post-mortem written ([[2026-04-23_postmortem-onboarder-healthcheck]]). Derived rules: [[2026-04-23_release-acceptance-criteria]], hard rule against HTTP-abort-without-ask. |
| 16:00 | Post-mortem review surfaces pre-existing retry-idempotency bug in the cleanup Lambda (DDB counter double-counts on SQS retries). PR #5 opened + unit-tested. |
| 16:14 | PR #5 merged. Deploy workflow reports "success" — but only the onboarder Lambda actually gets updated. Cleanup + reenable Lambdas silently fail with `AccessDeniedException` (and were failing on every merge since 2026-04-20). |
| ~16:25 | Discovery: IAM policy `GitHubActionDeployAutoPatrolLambda` was missing `lambda:UpdateFunctionCode` for cleanup + reenable ARNs. Workflow's `\|\| echo "skipped"` was swallowing every error, not just ResourceNotFound. |
| 16:28 | IAM policy v2 applied (adds 4 missing ARNs). |
| 16:30 | PR #6 opened: workflow hardening (fail on real errors, mask CodeArtifact token). |
| 16:33 | PR #6 merged + deployed. This time all 6 Lambdas actually get the new code. |
| 17:XX | Verification pass. 0 disables all-time confirmed via CloudWatch log scan + admin API audit. Manager informed. |
| **17:59:26** | **`CLEANUP_ENABLED=true` flipped** on `immix-autopatrol-schedule-cleanup`. Stage goes live. |
| 18:04 | First post-ENABLED invocation: schedule 138 emits, count 3→4, below old threshold=8, no threshold hit. Runs cleanly. |
| **18:12:57** | **`CLEANUP_TARGET_HOURS` lowered 48→18.** For 6h-cadence schedules (our entire stage population) the threshold drops to the floor=3. For hourly: 48→18. |
| 18:16 | `threshold` field cleared on 3 existing DDB rows (c3808175, fbdfdba6, ee1822f1) so the next emit each picks up the new computed value instead of the locked-in old threshold=8. |
| 18:27 | No post-18h invocation yet (next emit expected ~19:56Z for schedule 223). |
| 19:09 | First fully-post-fix DDB row created: `636be1ba` (admin_pk=235) — has both `threshold=3` stored AND `last_message_id`. Confirms the post-PR-#5 code path is actually running. |
| 19:30 | `/autopatrol-cleanup-lambda-check` run: pipeline healthy; 34 invocations / 24h; 0 errors; 0 actual disables; 2 anomaly resets; DLQs all empty. See §Post-18h health check findings below. |

## What changed + why

### 1. Stage → "stage-that's-really-prod" reframing

Realized mid-day that the "stage queue" (`autopatrol_stale_schedule_cleanup_dev.fifo`) has been carrying real Immix customer tenant traffic the entire bake period. The Lambda's `AUTOPATROL_STAGE=prod` env var routes all admin + [[immix-vendor-api|Immix API]] calls to prod endpoints. Every PATCH would hit the real admin DB against real customer schedules.

**Consequence:** the originally-planned "1 week stage bake before prod rollout" gate was excessive. The risk per message has been prod-risk the whole time. Shortened to 24-48h of monitoring, not a week.

**Consequence²:** "Step F — prod US rollout" isn't a risk-class escalation — it's a volume scale-up (more connector pods emitting to the prod queue). Same Lambda, same admin DB, same blast radius per message.

### 2. Threshold lowered from 48h → 18h

Rationale:
- Anomaly-reset safety net has been validated 3× over 7 days (different schedules, 0 false positives)
- Immix's `scheduleStatus` is authoritative — when it says Active, we reset, regardless of connector's signal
- Re-enable Lambda available if we're ever wrong
- Faster cleanup cycle is customer-visible benefit

Tradeoff: expected anomaly-reset rate will climb 3-10× because thresholds fire sooner. That's fine as long as it stays under ~20/day sustained. Tracked as follow-up task #25.

### 3. Retry-idempotency fix

DDB counter was incrementing on every SQS redelivery (observed during a transient Immix outage: counter went 8→9→10 across 3 retries). Pre-flip this was harmless. Post-flip it would make a brief Immix flap lap the threshold and fire a bad disable.

Fix: `UpdateItem` now has `ConditionExpression: attribute_not_exists(last_message_id) OR last_message_id <> :msg_id`. Same `MessageId` twice → `ConditionalCheckFailedException` → fallback path refreshes ttl + last_at only, no count increment.

### 4. Deploy workflow hardening

Old deploy.yml used `\|\| echo "skipped: function not yet provisioned"` on cleanup + reenable steps. Intent was to tolerate not-yet-existent Lambdas. Reality was it swallowed every error class including IAM denials. New `.github/scripts/deploy_lambda.sh` tolerates ONLY `ResourceNotFoundException`; everything else fails the job.

Also: `CODEARTIFACT_AUTH_TOKEN` was being written to `$GITHUB_ENV` without `::add-mask::`, so every step's env dump logged the full JWT. Fixed.

## Acceptance / manager audit

- `GET /api/auto_patrol_schedule/?disabled_by=cleanup_lambda` → **0 rows** (2026-04-23 end-of-day)
- CloudWatch 14-day log scan: `"disabled admin schedule"` → 0 matches
- No sites deleted (Lambda doesn't touch sites; only schedules via `is_deleted=True`)

## Post-18h health check findings (19:30Z)

First `/autopatrol-cleanup-lambda-check` after the flip + threshold lower. Pipeline is healthy but the expected first-disables haven't fired yet.

**DDB state (5 rows):**

| schedule_id | bucket | count | threshold attr | last_message_id | last_failure_at | Interpretation |
|---|---|---|---|---|---|---|
| `c3808175` | patrol_exit | 3 | *(cleared 18:16)* | N | 13:56Z | Waiting for next emit (~19:56Z) to recompute threshold=3 and trigger Immix check |
| `fbdfdba6` | patrol_exit | 3 | *(cleared 18:16)* | N | 15:40Z | Same — next emit ~21:40Z |
| `ee1822f1` | patrol_exit | 4 | *(cleared 18:16)* | N | 18:04Z | Same — next emit ~00:04Z; already above threshold |
| `636be1ba` | patrol_exit | 1 | 3 (stored) | Y | 19:09Z | Post-18:12 row, correctly-shaped. Below threshold. |
| `1e2ee05f` | site_disabled | 12/56 | stored | Y | 18:38Z | Normal; site_disabled bucket far from threshold. |

**What to watch next 24h:** each of `c3808175`, `fbdfdba6`, `ee1822f1` should either disappear (disabled) or get an anomaly-reset on their next 6h-cadence emit. If a row is still at count=3/4 by 2026-04-24T12:00Z, something's wrong with the threshold-clear or next-emit logic.

**Transient errors — all concentrated on one schedule:**
- 9 transient errors in 24h, ALL for schedule `636be1ba` (admin_pk=235)
- Three bursts of 3 retries each, 6h apart (01:09Z, 07:09Z, 13:09Z) — matches this schedule's emission cadence
- Raised from `_check_immix` returning `"transient"` — likely an Immix-side 401/403/5xx specific to this tenant/schedule
- The 19:09Z emission incremented count=1, so at least one transient message eventually ACKed OR expired via redrive (DLQ stayed at 0 so SQS eventually succeeded)
- **Action:** track this schedule specifically. If transient persists, Immix auth or per-tenant API issue; may need to escalate to the immix team.

**Retry-idempotency fix exercise state:** 0 `retry-dedup` hits in 24h despite 9 transient errors. Possible because those transients happened pre-fix (before 16:33Z) or because each transient's retries all happen while the Lambda invocation is still running (same message, same invocation, not a re-delivery from SQS). Not proof the fix is broken; more evidence needed. Task #19 still open.

## Follow-ups filed today

- Task #19 — verify retry-idempotency fix exercises organically (not a gate, evidence-gathering)
- Task #21 — 24-48h post-flip monitoring window
- Task #22 — Step F (prod US scale-up) deferred until pod-redeploy mechanism exists
- Task #23 — Step G (prod EU) deferred until EU infra is provisioned
- Task #24 — Phase 1b dashboard signal activation (new signals added today: `cleanup_lambda_actual_disable_rate`, `cleanup_lambda_anomaly_reset_rate`, `cleanup_lambda_anomaly_repeat_offenders_7d`)
- Task #25 — watch anomaly-reset rate under 18h threshold
- Task #26 — investigate schedule `636be1ba-57c9-4da1-c534-08de1b193ea0` (admin_pk=235) for persistent Immix transient errors (9 in 24h, 3 bursts of 3 retries at 6h cadence)
- [[2026-04-23_feature-request-ad-hoc-connector-redeploy-api]] — KB feature-request for an API to redeploy connector pods on demand

## Related

- [[2026-04-23_postmortem-onboarder-healthcheck]] — the post-mortem that started the day
- [[2026-04-23_release-acceptance-criteria]] — rule derived from the post-mortem
- [[2026-04-24_morning-watch-list]] — tomorrow's specific watch items
- [[autopatrol-cleanup-lambda]] — entity (current state)
- [[2026-04-22_cleanup-lambda-bake-state]] — the pre-flip snapshot (superseded)
