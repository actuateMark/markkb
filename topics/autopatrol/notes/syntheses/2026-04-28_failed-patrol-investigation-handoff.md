---
title: "AutoPatrol Failed-Patrol Investigation — Handoff (2026-04-28)"
type: synthesis
topic: autopatrol
tags: [investigation, handoff, AUTO-566, AUTO-567, customer-incident, product-sync, settings-deploy, immix, immix, immix, immix, immix]
jira: ["AUTO-566", "AUTO-567", "AUTO-553", "AUTO-525"]
created: 2026-04-28
updated: 2026-04-29
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/2026-04-29.md
incoming_updated: 2026-05-08
---

# AutoPatrol Failed-Patrol Investigation — Handoff

Investigation triggered 2026-04-28 by a customer report on patrol `84833E77-4247-4D4F-538E-08DEA10F17AF` (site 46460 "hanwha 3"). Patrol marked "Failed" in Immix portal despite running cleanly. Surface a fleet-wide silent product-sync gap. Consolidates all findings, tickets, code changes, and remaining work.

## TL;DR for the next person

Two independent issues surfaced:

1. **Customer-visible "Failed" badge on healthy patrols** — caused by Immix's API server-side derivation: zero `raise_patrol_alert` calls before `update_patrol(Finished)` → Immix flips response to `patrolStatus: Failed`. **Patch landed:** [autopatrol-server PR #23](https://github.com/aegissystems/autopatrol-server/pull/23) (always emit per-camera PATROL_SUMMARY at HEALTHCHECK tier). Pending review/merge/deploy.

2. **Upstream config-sync gap** — affected sites silently run with empty/wrong `feature_deployments[]` per camera. Two production sites observed (46460, 40890), with two different bug shapes. **Tracked in [AUTO-566](https://actuate-team.atlassian.net/browse/AUTO-566).** Defensive guard tracked in [AUTO-567](https://actuate-team.atlassian.net/browse/AUTO-567).

## Architecture summary

The propagation chain when [[actuate-config]] (camera-ui's product config UI) updates a product:

```
camera-ui PATCH /api/auto_patrol_product_metric/{id}/  {enabled: true}
        ↓
AutoPatrolProductMetric.save() override (autopatrol_product_metric_model.py:81)
        ↓ super().save()       — row updated, schedule's enabled flag flipped
        ↓ ensure_metric_in_related_cameras()  — should create camera-level Metric
        ↓ self.schedule.deploy_schedule_settings()  — regenerates settings.json + S3 push
```

`models[]` in settings.json derives from schedule-level `AutoPatrolProductMetric.enabled` flags. `feature_deployments[]` per camera derives from camera-level `Metric` rows. **They are decoupled** — one can be populated while the other is empty.

## Finding 1 — The customer-visible symptom (PATCHED)

**Root cause:** Immix's API silently rewrites our `update_patrol(Finished)` to `patrolStatus: Failed` when no `raise_patrol_alert` was made for the patrol. Confirmed by NRQL comparison across 14 days: 0 alerts ⇒ Failed, ≥1 alert ⇒ Finished, no counter-examples.

`PatrolStatusEnum` in `actuate-integration-calls` only has `Pending/Started/Finished` — we **cannot** post `Failed`. The first investigation agent's claim that we posted Failed was a misreading of the response body (Immix echoes the rewritten state in the 200 response).

**Patch ([PR #23](https://github.com/aegissystems/autopatrol-server/pull/23)):** drop the `has_findings = chm_issues or clip_summaries` gate in `autopatrol_queue.py`, iterate cameras, emit one `raise_patrol_alert(detection_code="PATROL_SUMMARY")` per camera at HEALTHCHECK tier (SDK default). Skip cameras without `stream_id` (GH#1656 hardening).

**Verification path** (post-merge/deploy) is documented as a comment on the PR — 4 NRQL queries to confirm `update patrol response` flips from `"Failed"` to `"Finished"`, no per-camera errors, customer alarm panel doesn't ring.

## Finding 2 — Upstream config-sync gap (TWO bugs)

Pulled `s3://actuate-settings/connector-{site}-autopatrol-{n}/settings.json` directly for both observed affected production sites. Different bug shapes.

### Site 46460 ("hanwha 3") — Hypothesis C confirmed

| Field | Value |
|---|---|
| `models[]` | 1 entry (`intruder-384h-512w`, model_id 66) — schedule-level enabled WORKED |
| `schedule_status` | Active |
| `cameras[]` | 3 cameras attached |
| Per-camera `feature_deployments[]` | **`[]` empty for all 3** |

The schedule's `AutoPatrolProductMetric.enabled=True` for intruder, `deploy_schedule_settings` regenerated settings.json with the new model entry — **but `ensure_metric_in_related_cameras` failed silently inside the loop** before creating any camera-level Metric records.

### Site 40890 — Different bug

| Field | Value |
|---|---|
| `models[]` | empty |
| `schedule_status` | Active |
| `cameras[]` | **empty — zero cameras** |

The schedule has no cameras attached. `process_devices_data` (in `autopatrol_schedule_sync.py:125`) either never ran or `item.get("cameras")` was empty. Different sync-layer bug.

## Code-level analysis of Hypothesis C silent-failure modes

`ensure_metric_in_related_cameras` (`autopatrol_product_metric_model.py:46-76`) calls these in sequence per camera:

1. `StreamSplitter.list_compatible_labels()` — returns `[]` if no streams have AI models, but `[]` is not handled specially downstream
2. `StreamSplitter.get_label_properties(label)` — **CAN RAISE `ValueError`** if the label has no corresponding raw metric and isn't CHM (line 298-300)
3. `StreamSplitter.get_stream_for_label(...)` — **never returns None**; always returns an existing stream or creates one via `add_missing_model_stream`. `add_missing_model_stream` calls `get_default_ai_model` which **CAN RAISE `ValueError`** if no MetricLabel matches the raw_metric_label_name (line 326-328)
4. `Sensitivity.get_highest(label)` — **swallows exceptions and returns None silently** (`sensitivity_model.py:141-143`). If sensitivity is nullable on Metric, save() proceeds with sensitivity=None
5. `new_metric.save()` — would raise on NOT-NULL constraint violations
6. `CameraConfigurationService(camera).configure(is_new=False)` — could mutate Metrics via `split_streams`

**Most likely silent-failure mode:** `Sensitivity.get_highest` returning None silently, leading to a downstream issue (Metric saved with null sensitivity but then filtered out somewhere, or splitter rearrangement losing it). Other `ValueError`-raising paths would surface as HTTP 500 to camera-ui, which the customer would have noticed.

Less likely but possible: a previous attempt left orphan Metric rows that the `if not Metric.objects.filter(...).exists()` check picks up, causing the loop to skip the actual creation. Worth checking on the affected cameras' Metric history.

## Manual remediation paths

**Site 46460 (admin shell):**
```python
import logging
from inframap.sites.autopatrol.autopatrol_schedule_model import AutoPatrolSchedule

schedule = AutoPatrolSchedule.objects.get(
    schedule_id="a38dbad2-7d16-4c65-3876-08dea13d817e"
)
for pm in schedule.schedule_product_metrics.filter(enabled=True):
    print(f"Re-running for {pm.metric_label.name}")
    try:
        pm.ensure_metric_in_related_cameras(
            logger=logging.getLogger("manual_repair")
        )
    except Exception as e:
        print(f"  FAILED: {type(e).__name__}: {e}")
schedule.deploy_schedule_settings(call_deployer=True, user=request.user)
```
If the loop raises, the exception names the silent-failure mode in code. If it runs cleanly, settings.json regenerates with proper feature_deployments — pull from S3 to verify.

**Site 40890 (admin shell):**
```python
from inframap.sites.customer.customer_model import Customer

customer = Customer.objects.get(immix_site_id=40890)
print(f"customer.cameras.count(): {customer.cameras.count()}")
schedule = customer.autopatrol_schedules.first()
print(f"schedule.cameras.count(): {schedule.cameras.count()}")
# If customer has cameras but schedule doesn't, manually attach:
# schedule.cameras.add(*customer.cameras.all())
# schedule.deploy_schedule_settings(call_deployer=True, user=...)
```

## Cross-references — AUTO-553 / AUTO-525

The two affected sites are part of a broader product-sync architecture gap:

| Ticket | Direction | Status |
|---|---|---|
| **[AUTO-525](https://actuate-team.atlassian.net/browse/AUTO-525)** | Auto-deploy AP sites on any change (broader gap) | Ready for Testing |
| **[AUTO-553](https://actuate-team.atlassian.net/browse/AUTO-553)** | Camera Metric *remove* → schedule disable | Ready for Testing (stage only — commit `aa02033a`, NOT in `main`/`develop`) |
| **[AUTO-566](https://actuate-team.atlassian.net/browse/AUTO-566)** | [[actuate-config]] update → camera Metric *create* | Open |
| **[AUTO-567](https://actuate-team.atlassian.net/browse/AUTO-567)** | Defensive guard / operational visibility | Open |

Recommend coordinating these so the fix lands as one coherent product-sync architecture rather than four independent hooks.

## Hypotheses ruled in/out

| Hypothesis | Status | Evidence |
|---|---|---|
| (A) [[actuate-config]] calls wrong endpoint | **Ruled out** | `siteAboutStore.tsx:2789` PATCHes the right `auto_patrol_product_metric/{id}/` |
| (B) PATCH 404 — row didn't exist | **Unknown** | Need admin DB query or admin pod CloudWatch (logs not in NR) |
| (C) Save hook silent failure | **Strongly supported for 46460** | `models[]` populated but `feature_deployments[]` empty proves schedule-level deploy succeeded but camera Metric creation failed. Most likely: `Sensitivity.get_highest` swallowing an exception |
| (D) Deploy didn't take effect | **Ruled out for 46460** | settings.json from S3 shows correct schedule-level state, just empty cameras |

## Tickets created during investigation

- **[AUTO-566](https://actuate-team.atlassian.net/browse/AUTO-566)** (High) — config-sync gap (this investigation's primary ticket)
- **[AUTO-567](https://actuate-team.atlassian.net/browse/AUTO-567)** (Medium) — defensive guard / operational visibility

Both have @[[jessica-bae|Jessica Bae]], @Tatiana, @[[brad-murphy|Brad Murphy]], @[[mark-barbera|Mark Barbera]] mentioned in description. **Watchers must be added manually via Jira UI** (no API tool exposed).

## Code/config changes shipped

| Repo | Change | Status |
|---|---|---|
| `autopatrol-server` | [PR #23](https://github.com/aegissystems/autopatrol-server/pull/23) — always emit per-camera PATROL_SUMMARY | Open, awaiting review/merge |
| `~/.claude/skills/dashboard-check/config/signals.json` | Added `connector_dummy_model_fallback_24h` + `connector_no_patrols_to_run_24h` (filtered to `-autopatrol-` containers) | Committed locally, enabled |
| `vms-connector/.claude/skills/investigate-patrol.md` | New skill scaffolding the patrol-failed lifecycle reconstruction | Committed locally |
| KB: `topics/autopatrol/notes/concepts/2026-04-28_integration-types-naming-confusion.md` | Documents AutoPatrol vs VCH vs CHM distinction (the `-chm-cronjob` naming gotcha) | Written |
| KB: `topics/camera-health-monitoring/notes/concepts/2026-04-28_vch-chm-vs-autopatrol-naming.md` | Cross-reference | Written |

## Open questions / next steps

For whoever picks this up:

1. **Run the manual remediation on site 46460** — captures the exception that names the silent-failure mode. ETA 5 minutes in admin shell.
2. **Diagnose site 40890's empty `cameras[]`** — separate issue. Check whether customer has cameras at all, whether schedule was activated pre-camera-sync.
3. **Confirm the customer's account of "[[actuate-config]] update"** — did they really PATCH a product or did they take some other action? camera-ui calls the right endpoint, but if their flow was different we may be solving the wrong problem.
4. **Determine fleet scope** — sweep admin DB for any AP schedule whose cameras have empty Metric rows despite enabled `AutoPatrolProductMetric` rows. If many, this is widespread silent corruption.
5. **Decide ticket structure** — keep AUTO-566 as both bugs or split into AUTO-566a (Hypothesis C silent failure) + AUTO-566b (empty cameras on schedule)?
6. **Lobby for Immix `Completed-NoThreats` patrol status** — long tail, lower priority, but the root behavior (silent rewrite of Finished → Failed in API responses) is unfortunate even with PR #23 deployed.
7. **Verify HEALTHCHECK tier is silent across customer alarm panel configs** before broad rollout of PR #23.
8. **Add watchers to AUTO-566/AUTO-567 in Jira UI.**

## Investigation timeline (for context)

- 16:00 UTC 2026-04-28 — patrol `84833E77...` ran on site 46460, came back as Failed in customer's Immix portal
- ~17:00 UTC — investigation began
- 18:00 UTC — root cause identified (Immix server-side derivation), patch designed
- 19:00 UTC — PR #23 opened, AUTO-566 created
- 20:00 UTC — fleet-wide sweep (corrected to 2 production sites after VCH/CHM noise removed)
- 21:00 UTC — AUTO-567 created, dashboard signals added, KB notes written
- 22:00 UTC — settings.json ground-truth check, two-bug split identified
- ~23:00 UTC — handoff synthesis (this note) written

## Observability gap discovered during investigation (2026-04-29)

**The production camera-admin Django web pod is NOT forwarded to [[new-relic|New Relic]].** Only `camera-admin-staging` is queryable. This is the pod that serves PATCH `/api/auto_patrol_product_metric/{id}/` and runs the `_delayed_deploy_settings` background thread — **the exact pod whose logs would tell us why customer saves on 40890 didn't propagate**.

This gap **blocked direct verification** of Hypothesis A ("save hook fired but deploy thread crashed silently"). Without NR access to the prod web pod, we'd need CloudWatch / kubectl stderr to see what's actually failing inside the thread.

What IS in NR for admin-side debugging (verified 2026-04-29 via direct query):

- `djangoq` (~210k logs/24h) — Django Q background workers, NOT the `_delayed_deploy_settings` thread (raw `Thread`, not django-q task)
- `autopatrol-server` (~9.5k/24h) — patrol completion + Immix calls
- `camera-admin-staging` (~4.7k/24h) — stage admin web pod (mirrors prod but only stage traffic)
- `admin-auto-onboarding-*` — onboarding cronjob pods

`prod_camera_admin` **does not exist** as a container — agents have hallucinated it three times during this investigation. Trust direct query results, not agent claims.

Full container reference: see `[[nr-connector-query-cookbook#actuate_admin Containers in NR]]` for log volumes, query templates, and the observability gap callout.

This gap is itself a followup ticket candidate — forwarding production web pod logs would close it.

## Related KB notes

- [[2026-04-28_integration-types-naming-confusion]] — AutoPatrol vs VCH vs CHM distinction
- [[2026-04-28_vch-chm-vs-autopatrol-naming]] — same, cross-reference
- [[autopatrol/_summary]] — topic-level overview
- [[nr-connector-query-cookbook]] — admin-container reference and observability gap
