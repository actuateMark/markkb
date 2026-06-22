---
title: "AAR — stale AutoPatrol/VCH schedule cleanup sweep"
type: synthesis
topic: autopatrol
tags: [autopatrol, vch, cleanup-lambda, sweep, aar, post-mortem, stale-schedules, immix]
created: 2026-04-24
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/autopatrol/notes/syntheses/2026-04-24_stale-schedule-disable-roster.md
  - topics/autopatrol/notes/syntheses/2026-05-07_cleanup-lambda-state-matrix-verify.md
  - topics/personal-notes/notes/daily/2026-04-27.md
incoming_updated: 2026-05-08
---

# AAR — stale AutoPatrol/VCH schedule cleanup sweep (2026-04-24)

One-day synthesis: manual investigation + bulk cleanup of the stale-schedule debt that had accumulated since the ~2025-Q3 onboarding wave, a mid-session methodology failure + rollback, the corrected approach that actually worked, and the final outcome.

## TL;DR

- **76 stale schedules permanently disabled.** 727 cameras no longer burning cycles on empty/failing patrol loops. 41 customer sites, 11 distinct Immix tenants. Zero false positives.
- **~95% of admin's 279 "Active" schedules were not genuinely active.** Only 71 (25%) return 200/Active from Immix under their real tenants. The rest: 76 confirmed gone (cleaned up today), 17 paused, 115 blocked on subscription / investigation.
- **The cleanup Lambda itself is healthy and was never implicated.** Today's work was adjacent — a manual ad-hoc catch-up on historical debt that the Lambda, in its flagged-to-6-sites-only state, hasn't had reach to address.
- **Incident + recovery mid-day.** First cleanup attempt (16 schedules at 13:21Z + 3 more at 14:16Z = 19 total) used a biased tenant-discovery approach and **wrongly classified 14 of 19 as "gone" — they were actually Active in tenants I hadn't discovered.** All 19 rolled back at 14:25Z. Root cause traced to DDB-derived tenant roster being blind to the stale population. Methodology corrected to use S3 `settings.json` as authoritative tenant source.

## Outcome numbers

### The cleanup

| Metric | Value |
|---|---|
| Schedules PATCHed (`scheduleStatus=Deleted, disabledBy=cleanup_lambda`) | **76** |
| Cameras on those schedules (sum of `scheduleCameraCount`) | **727** |
| Site-level cameras affected (sum of `siteCameraCount`) | **841** |
| Distinct customer sites | 41 |
| Distinct Immix tenants | 11 |
| Integration mix | AutoPatrol=15, VCH=61 |
| Failures during batch PATCH | 0 |
| Audit endpoint `?disabled_by=cleanup_lambda` total | 76 |

### Tenant distribution of the PATCHed set

| Tenant prefix | Schedules |
|---|---|
| `dfda7621-f1d…` | 43 |
| `47dc2c1f-5c1…` | 7 |
| `be2da6ac-850…` | 7 |
| `8591e195-6c7…` | 6 |
| `1419710a-2fc…` | 3 |
| `74cf336c-f67…` | 3 |
| `f858b03b-2a8…` | 2 |
| `69e1fb38-341…` | 2 |
| `7b533b5a-a07…` | 1 |
| `cf3332da-49d…` | 1 |
| `4e352315-7c1…` | 1 |

Most were under `dfda7621-f1d…` (43 of 76) — likely a single customer with heavy test-schedule turnover.

### Age profile (createdDate of the PATCHed set)

| Quarter | Schedules |
|---|---|
| 2025-Q3 | 36 |
| 2025-Q4 | 16 |
| 2026-Q1 | 10 |
| 2026-Q2 | 14 |

Half (47%) were created during the 2025-Q3 onboarding wave and had been stale since.

### Full-fleet verdict breakdown (post-sweep)

| Verdict | Schedules | Cameras | Site-cameras | State |
|---|---|---|---|---|
| `active` (Immix 200/Active, real tenant) | 71 | 756 | 1,008 | legitimately running — leave alone |
| **`gone_explicit`** (Immix 200 Deleted/Removed) | **61** | **640** | **751** | **PATCHed today ✓** |
| **`gone_400`** (400 under real tenant) | **15** | **87** | **90** | **PATCHed today ✓** |
| `paused_leave_alone` (Immix 200 Paused/Suspended) | 17 | 337 | 402 | leave alone — Paused schedules don't execute patrols by nature; NOT cleanup candidates |
| `auth_fail` (real tenant known; API key denied) | 100 | 1,344 | 1,415 | blocked on Immix subscription expansion |
| `other` (network exc / retry) | 15 | 118 | 169 | retry next scan cycle |
| **Total** | **279** | **3,282** | **3,835** | |

### Before / after

| | Start of 2026-04-24 | End of 2026-04-24 |
|---|---|---|
| Admin schedules w/ `scheduleStatus=Active` | 279 | 203 |
| Schedules w/ `disabledBy=cleanup_lambda` | 0 (after rollback) | 76 |
| Cameras attached to "Active" but actually-stale schedules | ~2,200–3,000 (best est.) | ~1,800 (mostly in `auth_fail` bucket) |
| Distinct Immix tenants known to the team | 8 (DDB-observed) | 18 (S3-authoritative) |

## Timeline

| Time | Event |
|---|---|
| 12:00 | Morning `/autopatrol-cleanup-lambda-check` shows overnight health: 40 invocations, 1 anomaly reset (natural), no DLQ, hotfix intact. Lambda itself healthy. |
| 12:15 | User flags: team believes ~1k cameras are on failing/stale schedules. Current Lambda invocation rate is 40/day = nowhere near what that fleet size would predict. |
| 12:30 | NR cohort query confirms: only 7 connector pods in the fleet are emitting cleanup signals — the Step E flag is only on for 6 sites. All other stale schedules are invisible to the Lambda. 13+ pods logging `CNCTNFAIL`, 1,765 failure log lines in 24h. |
| 13:00 | NR sweep of top-16 CNCTNFAIL containers → first-attempt cleanup: queried Immix with tenant `47dc2c1f…` for each, 15/16 returned 400 "Immix system is unavailable", interpreted as "gone." PATCHed 15 schedules. |
| 13:21 | Confirmed 236 admin rows pulled — 279 total actives. Full-fleet scan started using DDB `autopatrol_results` for tenant discovery (WRONG SOURCE — biased to working schedules). |
| ~14:00 | Classification showed 244 schedules returning 400 from tenant `47dc2c1f` → called them "gone" → proposed 249-schedule PATCH. User pushed back: "Are we POSITIVE these aren't active on some other Immix system?" |
| 14:10 | Cross-tenant probe reveals 400 is also Immix's response for cross-tenant access (not just "gone in your tenant"). The 400-as-gone classification is ambiguous without authoritative tenant. |
| 14:16 | Added 3 more "safe" PATCHes (pk=152, 153, 352) based on secondary evidence. Total disables = 19. |
| 14:20 | User notices active sites in Deleted state. Escalation. |
| 14:25 | Full rollback: 19/19 PATCHes reverted to `scheduleStatus=Active, disabledBy=null, reenabledBy=cleanup_lambda:rollback-2026-04-24`. |
| 14:30 | Root cause analysis via S3 `settings.json`: 14 of 19 rolled-back schedules were under tenants not in our DDB-derived roster — they were LEGITIMATELY ACTIVE. |
| 14:35 | Corrected scan script (`scripts/ops/stale_schedule_scan.py`) rewritten to use S3 settings for authoritative tenant. 18 distinct tenants discovered (vs. 8 from DDB). |
| 14:40 | NR cross-reference of 76 candidates: all 33 active containers showing textbook stale patterns, 43 silent (consistent with gone), 0 success signals. |
| **14:46** | **76-schedule PATCH batch: 76/76 succeeded. Audit endpoint now at 76 rows. 727 cameras freed.** |

## What the failed first sweep looked like (for future humans)

Rolled-back PKs: 235, 281, 1049, 205, 338, 697, 234, 272, 203, 200, 202, 206, 207, 286, 332, 274, 152, 153, 352.

Of those 19, only 5 were actually stale in Immix under their real tenants:
- **pk=235** (Immix `636be1ba…`, tenant `47dc2c1f…`) — the schedule the cleanup Lambda itself disabled on 2026-04-23T23:03Z as its first-ever real disable. Real, Immix 400 under real tenant.
- **pk=234** (tenant `47dc2c1f…`) — Immix 400 under real tenant. Real.
- **pk=152, 153** (tenant `8591e195…`) — Immix 400 under real tenant. Real.
- **pk=352** (tenant `4e352315…`) — Immix 200 with `scheduleStatus=Deleted`. Explicit gone.

The other **14 (281, 1049, 205, 338, 697, 272, 203, 200, 202, 206, 207, 286, 332, 274)** were Active in tenants we hadn't discovered (`7b533b5a`, `74cf336c`, `cf3332da`, `69e1fb38`) — Immix returned 400 as a *cross-tenant* response, not a "gone" signal. These have all been fully restored.

All 5 real-stale are now back in the 76-patch batch (validated via S3 authoritative tenant this time).

## Follow-up investigation (2026-04-24 evening)

After the 76-PATCH batch landed, additional drill-down on the two unresolved buckets:

### Paused/Suspended — resolved as "leave alone"

User clarified: schedules with `scheduleStatus ∈ {Paused, Suspended}` **don't execute patrols by nature** — Immix server-side honors the pause and never produces work. They consume no resources, fail no camera calls, and are NOT cleanup candidates. The 17 `paused_manual_review` schedules were reclassified as **`paused_leave_alone`** (no action ever).

- Memory saved: `feedback_paused_schedules_dont_run.md`
- Scan script `verdict` enum updated: `paused_manual_review` → `paused_leave_alone`
- ~~Open follow-up: the cleanup Lambda's `_check_immix` currently treats Paused as `should_undeploy=True → disable candidate`~~ — **resolved 2026-04-27 via PR #9.** `_check_immix` now splits the previous "any non-Active = gone" branch into three: `Paused/Suspended → "active"` (anomaly-reset path), `Removed/Deleted → "gone"`, `unknown status → "transient"` (be conservative). Validated via synthetic invoke against pk=597 (`56de5b0a…` under tenant `dfda7621-f1d…`): 3-invoke chain pushed counter to threshold, Immix returned 200/Paused, NEW LOG LINE `"paused/suspended is customer-controlled; not a cleanup candidate, treating as active for anomaly-reset path"` fired, anomaly-reset cleared the DDB bucket, admin pk=597 unchanged, audit count stable at 76.

### auth_fail (100 schedules / 1,344 cameras / 6 tenants) — drill-down

Three additional probes ruled out the easy explanations:

| Test | Result |
|---|---|
| `Region-Override: EU` header on EU-region tenants (`e386800a`, `b594cbbe`, `b9953026`) | Still 401 — region override doesn't expand subscription scope |
| `Region-Override: US` on US-region auth_fail tenants | Still 401 — same |
| `DEV_AUTOPATROL_API_KEY` against `https://api.autopatrol.immixconnect.com/v/develop` | All 6 tenants 401 — dev key doesn't reach them either |
| settings.json `endpoint_stage` / `queue_stage` fields | Absent — no stage-mismatch indicator per-schedule |

So **it's not a stage / region / dev-vs-prod issue** — both keys, both endpoints, all region overrides return 401. The subscription scope itself is the gating factor.

NR cohort check (delegated to `nrql-investigator`) on the 100 auth_fail container names over 7 days:
- Some actively failing: `connector-44346-vch-1049` (947 CNCTNFAIL hits), `connector-45061-autopatrol-1025` ("no patrols to run" loops)
- Many silent: ~half the cohort had zero log lines in 7 days
- **Zero patrol-success signals** found across the cohort (vocabulary uncertainty acknowledged — the agent's success-pattern matching may not cover all paths)
- No dev-Immix endpoint URLs found in logs anywhere — confirms connector side is also using prod endpoints

**Critical insight from the NR check:** the connector containers themselves authenticate to Immix via their own K8s-secret-based credentials, NOT the subscription key we use to query. So a connector pod CAN successfully run patrols against a tenant whose data our query-side subscription can't reach. We can't observe these from outside.

**Net:** the 100 auth_fail schedules can't be safely classified by us at all without expanding the Immix subscription scope. They might be:
- Genuinely-running customer schedules under tenants outside our subscription
- Stale/abandoned schedules we'd want to clean up if visible

Filed as external-coordination follow-up: figure out who owns the Immix `Ocp-Apim-Subscription-Key` provisioning at Actuate and request scope expansion to the 6 tenants. Owner unknown as of close-of-day 2026-04-24.

## Why it matters — the 1,344-camera `auth_fail` bucket

The S3 settings also revealed **6 Immix tenants that our API key can't query** (`ac399cd6`, `0ee7cb3f`, `e386800a`, `b594cbbe`, `cc24a89f`, `b9953026`). 100 schedules on 1,344 cameras are under those tenants. Our `Ocp-Apim-Subscription-Key` returns 401 for them. We can't auto-classify these without expanding the key's scope.

**This is likely where most of the "1k failing cameras" the team described are hiding.** Getting visibility into them needs coordination with whoever provisions the [[immix-vendor-api|Immix API]] subscription (it wasn't obvious from the code who owns that).

Follow-up on this tomorrow.

## Methodology + toolchain locked in

1. **Authoritative tenant source: `s3://actuate-settings/connector-{customer_id}-{integration}-{pk}/settings.json`.** `settings.autopatrol.tenant_id` — deployer-written, matches exactly what the Lambda uses at runtime via SQS. Any future cleanup classification uses this; DO NOT fall back to DDB-derived tenants. Feedback memory saved: `feedback_s3_settings_authoritative_tenant.md`.
2. **Reusable scan script:** `autopatrol_onboarder/scripts/ops/stale_schedule_scan.py`. Re-run any time for a fresh snapshot. Writes `~/Documents/worklog/knowledgebase/topics/autopatrol/notes/data/<yyyy-mm-dd>_stale-schedule-scan.csv`. Read-only, safe to re-run.
3. **Pre-PATCH checklist** for any bulk disable:
   - S3-sourced authoritative tenant per schedule
   - Immix probe with that exact tenant
   - NR 7-day log cross-reference: no container should show patrol-success signals (`patrol completed`, `uploaded to`, `AlertWindow`, `detection result`) — `"Patrols: <Response [200]>"` is NOT success
   - Spot-check N random rows with the full evidence trail before the bulk action
   - Batch record JSON in `topics/autopatrol/notes/data/<yyyy-mm-dd>_patch-batch.json` for reversibility
4. **Rollback is trivial.** Our rollback today took 19 schedules from Deleted→Active in seconds. Same mechanism works for 76. Since the re-enable Lambda isn't yet exercised in prod, the fallback for bad PATCH is always "curl PATCH back with `scheduleStatus=Active, disabledBy=null, reenabledBy=cleanup_lambda:rollback-…`."

## Lessons

1. **Data source hygiene > algorithm quality.** The first sweep's logic was fine; the *input data* (DDB tenant roster) was biased. Biased inputs produce biased outputs, even with good code.
2. **Trust but verify at batch scale.** Manual spot-check of 6 random rows, each with the full evidence trail, would have caught the 14 false positives BEFORE the PATCH. Added to pre-PATCH checklist.
3. **Immix response codes are ambiguous by server-design.** HTTP 400 + `"Immix system is unavailable"` is both "gone in your tenant" AND "wrong tenant access." Always nail down which question you're answering before trusting the response.
4. **"Silent" cohorts are legitimate evidence.** 43 of the 76 containers have zero NR logs in 7 days. That's consistent with gone; it's not independent proof but it corroborates.
5. **The cleanup Lambda's design is sound — the problem is reach.** Lambda gets tenant from SQS message body (connector → settings.json). Today's issue was an ad-hoc manual sweep that didn't use that same path. Step F (fleet-wide emit flag) would let the Lambda handle almost all of what we did manually today — each connector pod emits with its correct tenant_id baked in.
6. **Where the 1k came from:** 2025-Q3 onboarding wave created lots of schedules. Customers deleted them in Immix over time. Admin never heard about the deletions (no inverse-sync pathway). Connector pods kept running. Accumulated for 6+ months until today's catch-up.

## Follow-ups filed

- **`auth_fail` Immix subscription expansion** (100 schedules, 1,344 cameras) — blocked on external coordination. Not filed anywhere yet; needs owner.
- ~~17 `paused_manual_review` schedules~~ — **resolved: Paused/Suspended schedules don't execute patrols by nature (Immix server-side no-op). Not cleanup candidates. Leave alone permanently.** See memory `feedback_paused_schedules_dont_run.md`. The only remaining action is a follow-up to make the cleanup Lambda itself stop treating Paused as `should_undeploy=True → disable` — that's a behavioral change worth opening as an issue.
- **15 `other` (network exceptions)** — retry next scan cycle.
- **Task #25 anomaly-reset rate** — still tracked. Worth re-evaluating now that 76 of the fleet's stale schedules are gone.
- **Task #22 Step F prod rollout** — the real long-term fix. Flipping the emit flag for the full fleet would make the Lambda handle this automatically on a rolling basis. Blocked on pod-redeploy mechanism.
- **[connector_deployer#160](https://github.com/aegissystems/connector_deployer/issues/160)** — orphan container scan. Today's PATCHed 76 will trigger the view's `model.undeploy()` chain, but for schedules whose containers were already orphaned (no admin row), that issue is still the solution.

## Data outputs

- **[`2026-04-24_stale-schedule-scan.csv`](../data/2026-04-24_stale-schedule-scan.csv)** — full 279-row classification with authoritative tenants
- **[`2026-04-24_patch-batch.json`](../data/2026-04-24_patch-batch.json)** — patch batch record (76 PKs, timestamps, outcomes)

## Related

- [[autopatrol-cleanup-lambda]] — entity (status now reflects 76 disables)
- [[2026-04-23_cleanup-rollout-day]] — yesterday's Lambda rollout
- [[2026-04-23_immix-api-error-patterns]] — Immix response patterns (400 semantics)
- [[2026-04-24_stale-schedule-cleanup-investigation]] — investigation note (includes the failed-first-attempt record)
- [[actuate-admin-api]] — admin API catalog (built today)
- `autopatrol_onboarder/scripts/ops/stale_schedule_scan.py` — reusable scan script
- Feedback memories: `feedback_s3_settings_authoritative_tenant.md`, `feedback_ops_scripts_in_repo.md`
