---
title: "Cleanup Lambda Rollout Day — 2026-04-23"
type: concept
topic: autopatrol
tags: [autopatrol, cleanup-lambda, rollout, hotfix, threshold-tuning, incident-day, immix]
created: 2026-04-23
updated: 2026-04-23
author: kb-bot
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
| 19:56 | **First post-ENABLED threshold action fires** — `c3808175` emits, count→3, Immix returns **Active** → anomaly-reset (not a disable). Safety net validated live. |
| 21:40 | **Second anomaly-reset of the day** — `fbdfdba6` emits naturally on its 6h cadence, Immix reports **Active**, reset. Two 6h-cadence schedules in the stage-prod tenant both report Active despite connector saying no patrols → state-mismatch candidates, not cleanup candidates. |
| ~20:15 | Mark notices the 9 transient errors for `636be1ba` are all responding with 400 + "Immix system is unavailable..." body text. Pattern is persistent (24h+, same schedule) ⇒ not transient ⇒ Immix's way of saying "this schedule doesn't exist." Decision: treat 400 as `gone` in `_check_immix`. |
| 22:06 | PR #7 merged — `fix(cleanup-lambda): treat Immix 400 as "gone" not transient`. Deploy workflow 24861281359 starts. |
| 22:07:26 | Deploy completes (all 6 Lambda targets). New CodeSha256 on `immix-autopatrol-schedule-cleanup`. |
| **22:09:57** | **First successful cleanup disable, ever.** Synthetic SQS invoke against `636be1ba` pushes count→3; Immix 400; new code path treats as gone; `disabled admin schedule_pk=235`; DDB row deleted. End-to-end chain proven. |
| 22:15 | User spot-checks 235 in admin — `scheduleStatus=Active`, `isDeleted` flag still indicates not-deleted. The "disable" didn't actually land. Investigation begins. |
| 22:20 | Root cause found: the admin `AutoPatrolScheduleSerializer` is strict camelCase and silently drops unknown fields. Prior PATCH sent `{is_deleted, disabled_by, disabled_at}` (snake_case + a non-serializer field `is_deleted`). All three fields silently dropped. PATCH returned 200 via `updated_date` auto-bump, zero business effect. Manual curl PATCH with correct camelCase `{disabledBy, disabledAt}` landed on 235 at 22:19:19Z — but `scheduleStatus=Active` stayed and container wasn't undeployed. |
| ~22:30 | Second root cause: `is_deleted` isn't exposed in the serializer at all, and adding it would require an admin-side PR. User flagged a simpler path — `scheduleStatus ∈ {Deleted,Removed,Paused,Suspended}` triggers `model.deploy().should_undeploy→undeploy()` via the view's existing post-save hook. Going with **Path B**: PATCH `{scheduleStatus="Deleted", disabledBy, disabledAt}`, skip any admin PR. |
| 22:51 | Manual curl PATCH against 235 with all three fields — scheduleStatus flips to Deleted, disabledBy/disabledAt land, updatedDate bump shows view's `deploy_schedule_settings` thread ran (which would call `undeploy()`). Schedule 235 now fully + correctly disabled on admin. |
| 23:01:05 | PR #8 merged (`fix(cleanup-lambda): PATCH scheduleStatus=Deleted + camelCase + verify`). Deploy workflow 24863147377 starts. |
| 23:01:37 | Deploy complete. New CodeSha256 on `immix-autopatrol-schedule-cleanup`. |
| **23:03:26** | **Path B verified end-to-end via 3-invoke synthetic chain against 235.** Final log line: `disabled admin schedule_pk=235 ... (verified: scheduleStatus=Deleted disabledBy=cleanup_lambda disabledAt=2026-04-23T23:03:26.349976Z)`. Admin state matches exactly; DDB row deleted by `dao.delete()`. Full chain proven for the first time with an actually-landing disable. |
| 23:21 | **Sweep across the 14-day roster** to find any other schedules that should have been cleaned up but weren't. Roster = 7 distinct schedule_ids the Lambda processed in 14d. Of those: 2 not in admin (silently dropped), 1 already disabled (235), 1 too far from threshold to force (site_disabled bucket for pk=234). The remaining 3 (ee1822f1/pk=138, c3808175/pk=223, fbdfdba6/pk=159) got forced to threshold via synthetic invokes — **all three returned `Active` from Immix and anomaly-reset.** Safety net working. **Only 1 genuinely-gone schedule existed in our 14-day window; it's cleaned up.** Side-signal: 4/5 admin-tracked schedules in the stage pool are in a "connector-sees-no-patrols / Immix-says-active" state mismatch — worth revisiting via Task #25 anomaly-reset-rate monitoring. |

## What changed + why

### 1. Stage → "stage-that's-really-prod" reframing

Realized mid-day that the "stage queue" (`autopatrol_stale_schedule_cleanup_dev.fifo`) has been carrying real Immix customer tenant traffic the entire bake period. The Lambda's `AUTOPATROL_STAGE=prod` env var routes all admin + Immix API calls to prod endpoints. Every PATCH would hit the real admin DB against real customer schedules.

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
- ~~Task #26 — investigate schedule `636be1ba` for persistent Immix transient errors~~ — **root-caused + resolved same day.** Immix returns 400 + "system is unavailable" body for not-found schedules; previously treated as transient (retry forever), now treated as gone (disable). PR #7, verified via ad-hoc invoke at 22:09:57Z. Schedule 235 is the first admin row soft-deleted by the cleanup Lambda.
- **Follow-up**: other schedules with similar "transient" patterns in the past 7d may also resolve now. Watch next 24-48h for an uptick in cleanup disables as the 400-path backlog clears. Currently-known candidate: none of the other 4 rows have 400 patterns in the log; they're more likely to anomaly-reset (like `c3808175` did at 19:56Z, `fbdfdba6` at 21:40Z).
- **Task #27 — catalog Immix error patterns + add observability.** Immix doesn't adhere to REST best practices; we just caught one pattern (400 + "system unavailable" body = actually gone) and should expect more. Written up as [[2026-04-23_immix-api-error-patterns]]. Next step: instrument `_check_immix` with structured log fields (`immix_status_code`, `immix_body_first_100_chars`, `verdict`) or an `AutoPatrolImmixResponse` NR custom event, so new patterns surface in aggregation queries instead of requiring manual log archaeology after a schedule has failed silently for 24h.
- **Task #28 — orphan container cleanup in the deployer** ([connector_deployer#160](https://github.com/aegissystems/connector_deployer/issues/160), assigned to self). Cleanup Lambda silently ACKs no-patrols signals for schedules that aren't in admin — but the connector pod for that schedule keeps running forever. 2 observed orphans in today's 14d sweep (`51c72148`, `798e6dde`). Best fix is deployer-side: periodic orphan scan listing deployed containers, verifying admin_pk still exists, DELETE on mismatch. Cost + noise, not a correctness blocker.
- [[2026-04-23_feature-request-ad-hoc-connector-redeploy-api]] — KB feature-request for an API to redeploy connector pods on demand

## Related

- [[2026-04-23_postmortem-onboarder-healthcheck]] — the post-mortem that started the day
- [[2026-04-23_release-acceptance-criteria]] — rule derived from the post-mortem
- [[2026-04-24_morning-watch-list]] — tomorrow's specific watch items
- [[autopatrol-cleanup-lambda]] — entity (current state)
- [[2026-04-22_cleanup-lambda-bake-state]] — the pre-flip snapshot (superseded)
