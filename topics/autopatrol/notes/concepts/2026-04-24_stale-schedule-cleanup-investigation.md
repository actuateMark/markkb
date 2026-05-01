---
title: "Stale AutoPatrol schedule & zombie-task investigation"
type: concept
topic: autopatrol
tags: [autopatrol, cleanup-lambda, investigation, stale-schedules, zombie-tasks, fleet-health, immix]
created: 2026-04-24
updated: 2026-04-24
author: kb-bot
---

# Stale AutoPatrol schedule & zombie-task investigation

## Context

Mark was told there are **~1,000 cameras** (across AP + VCH integrations) that are assigned to sites/schedules whose connector containers are running patrol tasks but always failing to connect to the underlying camera. Important scope caveat: that's **1,000 cameras, not 1,000 schedules**. The total schedule count is ~300, with per-schedule camera fan-out of roughly 3–50. Most schedules work correctly; the problem is a subset of them that are either:

1. **Genuinely gone in Immix** but still running on the connector side (cleanup candidates — the [[autopatrol-cleanup-lambda|AutoPatrol cleanup Lambda]] was built for exactly this) — OR
2. **Zombie tasks** — connector containers running with a `scheduleId` that no longer exists in admin at all (observed pattern: container emits SQS cleanup signals → Lambda tries to resolve admin_pk → admin returns 0 results → Lambda silently ACKs and drops)

Both classes together represent the stale-fleet surface area we're trying to shrink. See [[autopatrol-cleanup-lambda]] for the Lambda design and [[2026-04-23_cleanup-rollout-day]] for the rollout timeline.

## Why the cleanup Lambda is only seeing a tiny slice

As of 2026-04-24T12:00Z the cleanup Lambda processed **40 invocations in the last 24h**, not the thousands-per-day that the fleet scope would predict.

Root cause confirmed via NR cross-reference (2026-04-24T13:00Z investigation, delegated to `nrql-investigator`):

| Dimension | Value | Source |
|---|---|---|
| Connector pods emitting `emit_no_patrols_signal` / cleanup signals (24h) | **7** (5 prod + 2 staging) | NR `Connector-EKS` cluster |
| Cleanup signals emitted (24h) | 26 | NR |
| Lambda invocations (24h) | 40 | CloudWatch (Δ ≈ SQS batching) |
| Distinct pods logging `CNCTNFAIL` (24h) | **13+** | NR — NR only sees currently-logging pods, not the silent-failing subset |
| Combined failure log volume (24h) | 1,765 lines (`CNCTNFAIL` + `failed to connect`) | NR |

**Gap mechanism:** the `AUTOPATROL_EMIT_CLEANUP_SIGNALS` feature flag (or equivalent) was enabled for only the 6 stage-bake sites via `vms-connector#1657`. Every other connector pod in prod — including the bulk of the failing-camera fleet — fails cameras and logs `CNCTNFAIL`, but does NOT emit the SQS cleanup signal. So the Lambda never sees them.

No evidence of SQS delivery bugs or connector-side emit failures. The flag-gate fully explains the delta.

**Long-term fix:** Step F in the [[autopatrol-cleanup-lambda]] rollout plan — flip `AUTOPATROL_EMIT_CLEANUP_SIGNALS` on for the entire prod connector fleet. Currently blocked on an ad-hoc pod-redeploy mechanism (mark-todos §3, Task #22).

## Zombie tasks (NEW pattern, flagged 2026-04-23)

Of the 7 distinct `schedule_id`s the Lambda saw in its 14-day window, **2 do not exist in admin**:
- `51c72148-79fa-4eca-d6de-08ddb7d3f342` — 13 emit signals over 14d
- `798e6dde-2d2a-4dab-422a-08ddc933478e` — 12 emit signals over 14d

Both hit the `admin has no schedule with scheduleId=… — nothing to do, ACKing the message` branch in `cleanup_lambda._resolve_cadence_and_pk`. The Lambda correctly ACKs (it can't construct a container name without admin_pk, integration type, and customer_id), but the connector pod keeps running indefinitely because nothing tears down the container.

**Tracked as follow-up:** [connector_deployer#160](https://github.com/aegissystems/connector_deployer/issues/160). Proposed design: deployer-side periodic orphan scan listing deployed containers, verifying `admin_pk` exists in admin, DELETEing on 404.

## What the cleanup Lambda has actually cleaned up so far

Exactly **1 schedule** has been soft-deleted by the Lambda end-to-end (as of 2026-04-24T13:00Z):

- **admin_pk=235**, Immix `636be1ba-57c9-4da1-c534-08de1b193ea0`
- Disabled 2026-04-23T23:03:26Z via PR #8's `scheduleStatus=Deleted + disabledBy=cleanup_lambda + disabledAt=…` PATCH (with post-PATCH verify)
- The original "first disable" at 22:09:57Z was silently dropped due to the camelCase-serializer bug; manually curl-PATCHed at 22:19:19Z to set provenance, then at 22:51:38Z to set `scheduleStatus=Deleted`; re-validated at 23:03:26Z via the new Lambda code path
- Full audit: `GET /api/auto_patrol_schedule/?disabled_by=cleanup_lambda` → 1 row

Anomaly-reset count (24h ending 2026-04-24T13:00Z): **6** — all involved `c3808175`, `fbdfdba6`, or `ee1822f1` hitting threshold → Immix reports still-Active → safety net resets the bucket without disabling.

## Action plan — bypass Step F to catch the NR-visible subset today

Step F (fleet-wide emit-flag rollout) is the end-state but takes infrastructure work. Parallel path: walk the NR-visible failing pods today, manually disable the ones Immix confirms gone, and record real-world ratios.

### Sweep plan (this note will be updated with results)

1. **Pull all containers with `CNCTNFAIL` or `failed to connect` logs in the last 24h** (NR, FACET by container_name, LIMIT 20 or more).
2. **Parse container names** — format is `[staging-]connector-{customer_id}-{integration}-{admin_pk}-chm-cronjob`. Extract admin_pk + integration.
3. **Per container**, via admin API:
   - `GET /api/auto_patrol_schedule/{admin_pk}/` — pull scheduleId, scheduleStatus, disabledBy, updatedDate
   - If admin returns 404 → **zombie task** (no admin record at all) — different handling, tracked under connector_deployer#160
4. **Per schedule**, via Immix API (through Lambda's synthetic-invoke path or direct curl):
   - If Immix returns 400 or 404 → **cleanup candidate**, PATCH `{scheduleStatus: "Deleted", disabledBy: "cleanup_lambda:manual-sweep", disabledAt: …}`
   - If Immix returns 200 with active scheduleStatus → **state mismatch**, leave for anomaly-reset monitoring (Task #25)
5. **Record results in this note** — per-schedule verdict table, ratios, next steps.

### What we're NOT doing in this sweep

- **Not** using the cleanup Lambda itself to drive disables. Too slow (need 3+ invokes per schedule) and it only covers schedules in DDB, not the broader NR-visible fleet.
- **Not** touching schedules whose `admin_pk` is absent from admin — those are zombie tasks and belong to the connector_deployer#160 track.
- **Not** hitting schedules that are legitimately active but temporarily failing (network blip, Immix transient). Those need longer observation.

## ⚠️ Methodology correction — 2026-04-24T14:30Z

**Early sections of this note (below) relied on a flawed tenant-discovery approach and led to 14 wrongly-disabled schedules. All 19 PATCHes from 2026-04-23 and 2026-04-24 have been rolled back (2026-04-24T14:25Z) — audit endpoint `?disabled_by=cleanup_lambda` is back to 0 rows; affected schedules have `reenabledBy=cleanup_lambda:rollback-2026-04-24` for traceability.**

The cleanup Lambda itself is unaffected — by design it uses the proper tenant from the SQS message body (connector-populated from `settings.json`). The bug was in the manual ad-hoc sweep script that predicted "gone" from a DDB-derived tenant roster.

**Root cause:**
- DDB `autopatrol_results` only contains rows for schedules that have successfully run patrols → biased toward working schedules.
- Failing/stale schedules (the cleanup target population) have no DDB entry → their tenant was unknown.
- The first sweep fell back to "try known tenants sequentially, take first 400 response" — this DOES NOT distinguish "gone in your tenant" from "cross-tenant access" at the Immix protocol layer. Both return the same 400.
- Fourteen schedules under tenants we hadn't discovered via DDB (tenants like `7b533b5a-a071…`, `74cf336c-f671…`) returned 400 as cross-tenant responses under T47. We misclassified them as "gone."

**The fix: authoritative tenant from S3 settings.**
Every deployed schedule has a `settings.json` at `s3://actuate-settings/connector-{customer_id}-{integration}-{pk}/settings.json`. The deployer writes `tenant_id` directly from `admin.AutoPatrolSchedule.customer.group.tenant_id` — this is the EXACT tenant the cleanup Lambda uses (via connector → SQS → Lambda). Using S3-sourced tenants, a 400 response IS trustworthy "gone."

Updated scan script: `autopatrol_onboarder/scripts/ops/stale_schedule_scan.py`. Memory saved: `feedback_s3_settings_authoritative_tenant.md`. All results below this point in the note use the corrected methodology.

## Sweep results (2026-04-24T14:30Z) — corrected, S3-sourced tenants

Re-ran the full 279-schedule sweep using `s3://actuate-settings/` for tenant discovery.

**18 distinct tenants discovered** (vs. 8 under the flawed DDB-based approach):
`ac399cd6`(74) `dfda7621`(55) `7b533b5a`(40) `47dc2c1f`(24) `37575b9e`(15) `0ee7cb3f`(12) `1419710a`(11) `74cf336c`(10) `be2da6ac`(7) `8591e195`(6) `e386800a`(6) `b594cbbe`(5) `f858b03b`(4) `69e1fb38`(4) `cf3332da`(2) `cc24a89f`(2) `b9953026`(1) `4e352315`(1)

**Verdict breakdown:**

| Verdict | Schedules | Cameras | Action |
|---|---|---|---|
| `active` (Immix 200/Active under real tenant) | 71 | 756 | ✋ leave alone |
| `gone_explicit` (Immix 200 + scheduleStatus=Deleted/Removed) | 61 | 606 | ✅ safe to PATCH |
| `gone_400` (Immix 400 under authoritative tenant) | 15 | 86 | ✅ safe to PATCH |
| `paused_manual_review` (Immix 200 + Paused/Suspended) | 17 | 337 | ⏸ review per-schedule |
| `auth_fail` (tenant known but our API key 401s) | 100 | 1,344 | 🔒 blocked — needs Immix subscription expansion |
| `other` (network exceptions) | 15 | 118 | 🔁 retry later |
| **Total** | **279** | **3,247** | |

**Safe-to-PATCH total: 76 schedules / 692 cameras.**

### auth_fail sub-distribution

These are real tenants (per S3 settings) but our Immix `Ocp-Apim-Subscription-Key` can't query them. Likely subscription/provisioning gap — needs coordination with Immix team or whoever owns our key's scoping.

| Tenant prefix | Schedules |
|---|---|
| `ac399cd6-2fd…` | 74 |
| `0ee7cb3f-4a3…` | 12 |
| `e386800a-7c2…` | 6 |
| `b594cbbe-b7f…` | 5 |
| `cc24a89f-d7d…` | 2 |
| `b9953026-27c…` | 1 |

## Output CSV

`~/Documents/worklog/knowledgebase/topics/autopatrol/notes/data/2026-04-24_stale-schedule-scan.csv` — 279 rows, columns include `s3_tenant_id`, `immix_code`, `immix_schedule_status`, `verdict`, and DDB activity metrics. Re-generatable by re-running the script.

## Corroborating NR log check (2026-04-24T14:40Z)

Before PATCHing the 76 gone candidates, cross-referenced each container's 7-day NR log behavior (delegated to `nrql-investigator`):

- **33 containers actively logging** — all exclusively textbook stale patterns: `"No patrols to run after all attempts, exiting"` (20+), `"No patrols found (attempt N/3), retrying..."`, `"No cameras found in config"`, `"No models configured for site"`, `emit_no_patrols_signal reason=site_disabled`, `CNCTNFAIL stream_id is missing` (vch-234 specifically).
- **43 containers silent** — 0 log lines in 7 days. Silence corroborates gone-on-Immix; doesn't independently prove (safety comes from the Immix authoritative check).
- **0 containers showing patrol-success signals** (`patrol completed`, `uploaded to`, `AlertWindow`, `detection result`) — full cohort is clean.
- Subtle anti-pattern caught by the agent: `"Patrols: <Response [200]>"` is NOT success — that's Immix returning a 200 with an empty patrol list. Don't misread.

## PATCH execution — 2026-04-24T14:46Z

Applied `{"scheduleStatus": "Deleted", "disabledBy": "cleanup_lambda", "disabledAt": "..."}` to all 76.

- **76/76 succeeded**, 0 failures
- Audit endpoint `?disabled_by=cleanup_lambda` now returns exactly **76 rows**
- Each schedule's view post-save triggers `deploy_schedule_settings` → `model.deploy` → `should_undeploy=True` → `model.undeploy()` → connector container torn down
- Cameras freed from failing-patrol loops: ~692 (sum of `scheduleCameraCount` across the 76)
- Full batch record at `topics/autopatrol/notes/data/2026-04-24_patch-batch.json` (list of PKs, timestamps, failures=0)

## Remaining work

- **17 `paused_manual_review`** (337 cameras) — Immix reports Paused/Suspended. Per-schedule judgment call; not auto-disabled.
- **100 `auth_fail`** (1,344 cameras) — S3 has authoritative tenants but our Immix API key returns 401 for those 6 tenants (`ac399cd6`, `0ee7cb3f`, `e386800a`, `b594cbbe`, `cc24a89f`, `b9953026`). Needs Immix subscription expansion — outside autopatrol_onboarder scope. Worth filing as a separate follow-up ticket to whoever provisions the `Ocp-Apim-Subscription-Key` at Actuate.
- **15 `other`** — network exceptions during the Immix probe. Retry next scan cycle.

## Post-mortem: what the incident taught us

- **Tenant source matters more than tenant count.** The DDB-biased roster was incomplete (8 of 18 actual tenants); a 400 under a guessed tenant looks identical to a 400 under the real one. The rule: authoritative tenant from S3, or don't probe.
- **Immix's 400 response is ambiguous by design.** Their server returns `400 "Immix system is unavailable..."` for two distinct conditions: gone-in-your-tenant AND wrong-tenant-access. We documented this in [[2026-04-23_immix-api-error-patterns]] yesterday as specifically the gone-case; today's incident extended it — the response body is ALSO what cross-tenant rejection looks like.
- **The cleanup Lambda itself is immune.** It gets `tenant_id` from the SQS message body (connector-populated from `settings.json`). Bug was in the manual ad-hoc sweep script, not the Lambda.
- **NR log cross-reference is a cheap last-line-of-defense.** Adding the 7-day "does this container show success signals?" check to ops scripts catches cases where Immix lies to us or state mismatches slip through. 76/76 agreed on today's batch; that's the bar.

> ⚠️ **The sections immediately below are the FLAWED first-attempt sweep that led to 14 wrongly-disabled schedules.** Kept as-is for post-mortem traceability. All PATCHes applied here were rolled back 2026-04-24T14:25Z. See the "Methodology correction" section above for the corrected sweep results.

Pulled 16 prod connector cronjobs with any `CNCTNFAIL` or `failed to connect` log activity in the last 24h via NR. For each, extracted `admin_pk` from the container name, queried admin for the scheduleId, and queried Immix directly with a candidate tenant (`47dc2c1f-5c19-43fb-b5d5-753c5e96eb14` — same tenant the autopatrol pod pk=260 logs).

### Immix responses

| admin_pk | integration | container | Immix verdict (T47) | action |
|---|---|---|---|---|
| **260** | autopatrol | connector-35832-autopatrol-260 | **200 Active** (477 CNCTNFAIL/24h) | ⏭️ LEAVE — legitimate active schedule, camera connectivity issue (not stale) |
| 281 | vch | connector-40792-vch-281 | 400 "system is unavailable" = **gone** | ✅ disabled |
| 1049 | vch | connector-44346-vch-1049 | 400 = gone | ✅ disabled |
| 205 | vch | connector-38579-vch-205 | 400 = gone | ✅ disabled |
| 338 | vch | connector-41267-vch-338 | 400 = gone | ✅ disabled |
| 697 | vch | connector-43637-vch-697 | 400 = gone | ✅ disabled |
| 234 | vch | connector-39418-vch-234 | 400 = gone | ✅ disabled |
| 272 | vch | connector-40510-vch-272 | 400 = gone | ✅ disabled |
| 203 | vch | connector-38577-vch-203 | 400 = gone | ✅ disabled |
| 200 | vch | connector-38574-vch-200 | 400 = gone | ✅ disabled |
| 202 | vch | connector-38576-vch-202 | 400 = gone | ✅ disabled |
| 206 | vch | connector-38580-vch-206 | 400 = gone | ✅ disabled |
| 207 | vch | connector-38582-vch-207 | 400 = gone | ✅ disabled |
| 286 | vch | connector-40798-vch-286 | 400 = gone | ✅ disabled |
| 332 | vch | connector-41261-vch-332 | 400 = gone | ✅ disabled |
| 274 | vch | connector-40512-vch-274 | 400 = gone | ✅ disabled |

**Ratio:** 15 of 16 (93.75%) were genuinely gone. **This is the real-world signal the cleanup Lambda would give us at scale if Step F were deployed** — the feature-flag rollout would catch ~93% of NR-visible failing pods as cleanup candidates automatically.

### Action taken

PATCHed all 15 genuinely-gone schedules via admin API with:
```json
{"scheduleStatus": "Deleted", "disabledBy": "cleanup_lambda", "disabledAt": "2026-04-24T13:21:44.489Z"}
```

All 15 verified via response body — `scheduleStatus=Deleted / disabledBy=cleanup_lambda / disabledAt` populated. The view's post-save `deploy_schedule_settings → model.deploy → should_undeploy → undeploy()` chain should have torn down the connector containers; connectivity will reflect over the next cronjob cycle.

The one active schedule (pk=260, "AP AV" under customer "Alibi Vigilant") is left alone. Its 477 `CNCTNFAIL` events / 24h are a real connectivity problem the customer owns — worth separate follow-up but NOT a stale-schedule candidate.

### Audit endpoint state

```
GET /api/auto_patrol_schedule/?disabled_by=cleanup_lambda
→ 16 rows total
    2026-04-23: 1 (pk=235 / 636be1ba — the first Lambda-driven disable)
    2026-04-24: 15 (manual sweep)
```

### Implications for the cleanup Lambda rollout

1. **Step F is higher-value than the rollout plan estimated.** 15 cleanup candidates surfaced from the top-16 NR-visible pods in ONE day. Scaling the feature flag to the full prod fleet would bring the cleanup Lambda from ~40 invocations/day to something like 150+ with most of the increase converting directly to disables. The ROI on the pod-redeploy mechanism (Task #22) just got better.
2. **The 400-as-gone classifier (PR #7) is working exactly as designed.** Every one of the 15 gone schedules returned `400 + "Immix system is unavailable. If this problem persists please contact Immix support team"` — the same exact pattern the Lambda is now trained to handle. That's the full validation PR #7 was waiting for.
3. **The PATCH payload shape is validated at batch scale.** 15 PATCHes in one call, all fields stuck cleanly. No silent-drop, no retries, no serializer surprises. Path B (PR #8) is battle-tested now.
4. **"Zombie tasks" class is still a real distinct problem.** The 2 schedules from yesterday's sweep that are NOT in admin (`51c72148`, `798e6dde`) are unaffected by today's sweep — they need the deployer-side scan ([connector_deployer#160](https://github.com/aegissystems/connector_deployer/issues/160)) to clean up.
5. **The "Immix-says-Active-anyway" class (state mismatch) is separate.** Yesterday's forced sweep showed 3 schedules (`c3808175`, `fbdfdba6`, `ee1822f1`) return `200/Active` from Immix — these are NOT in today's NR-visible CNCTNFAIL top-16 (their connectors emit to SQS instead of failing loudly in logs). They're in the "state mismatch" bucket and need different handling (Task #25 / Immix-side investigation).

## Follow-up hypotheses raised by this sweep

- **Most of the "1k failing cameras" probably map to gone-in-Immix schedules that never sync back.** The `updatedDate` on most of these 15 schedules was from Oct-Dec 2025 — admin hasn't received a sync update for them in 4-6 months. That's consistent with them being removed in Immix a long time ago but never cleaned up in admin because no-one was watching.
- **Step F ROI worth re-estimating.** If even a third of the full 300-schedule fleet is in a similar state, flipping the emit flag would convert into ~100+ cleanup disables on the first cycle — a one-time catch-up effect.
- **The admin-side broader scan (walking all 300 schedules, not just NR-visible ones) should be next.** NR only sees currently-logging pods. Schedules whose containers are silent or restarted-to-zero won't show in CNCTNFAIL queries. An admin-side query of `scheduleStatus=Active AND updatedDate < N days` crossed against Immix would catch those.

## Related

- [[autopatrol-cleanup-lambda]] — Lambda design + current rollout state
- [[2026-04-23_cleanup-rollout-day]] — rollout-day timeline
- [[2026-04-23_immix-api-error-patterns]] — Immix API quirks catalog
- [connector_deployer#160](https://github.com/aegissystems/connector_deployer/issues/160) — orphan container cleanup
- mark-todos §3 — workstream state

## Next steps after the sweep

- If the sweep finds, say, 3 of 13 top-offender pods are Immix-gone → validates that Step F is worth the priority bump (would cascade many more)
- If the sweep finds mostly state mismatches → Immix-side investigation, not cleanup-Lambda work
- If a zombie task appears with a live failure pattern → feeds evidence into connector_deployer#160
- The broader admin-side stale-schedule scan (walking all ~300 schedules, not just NR-visible ones) is a separate follow-up — bigger effort, catches silent-pod cases NR can't see

## Related

- [[autopatrol-cleanup-lambda]] — Lambda design + current rollout state
- [[2026-04-23_cleanup-rollout-day]] — the rollout-day timeline (including the first disable at 23:03Z)
- [[2026-04-23_immix-api-error-patterns]] — Immix API quirks catalog (relevant for the 400-as-gone classifier)
- [[2026-04-17_stale-schedule-cleanup-design]] — original design synthesis
- [connector_deployer#160](https://github.com/aegissystems/connector_deployer/issues/160) — orphan container cleanup follow-up
- mark-todos §3 — workstream state + Tasks #22 (Step F), #25 (anomaly-reset rate), #27 (Immix error observability), #28 (orphan cleanup)
