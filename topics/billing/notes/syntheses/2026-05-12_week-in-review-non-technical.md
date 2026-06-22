---
title: "Week in review — autopatrol / VCH / Immix / stream_id / billing (non-technical narrative)"
type: synthesis
topic: billing
tags: [billing, autopatrol, vch, immix, stream_id, week-in-review, communication, non-technical-audience]
created: 2026-05-12
updated: 2026-05-12
author: kb-bot
audience: "non-technical coworker"
covers_window: "2026-05-04 → 2026-05-11"
---

# Week in review — autopatrol / VCH / Immix / stream_id / billing

> **Audience:** non-technical coworker. Written to be shareable as a single narrative covering what may look like several different threads (autopatrol, VCH, Immix, the `stream_id` bug, billing hardening) but is really one coherent project.
>
> **Technical source-of-truth notes** for each section are linked in [[#Cross-references]] at the bottom.

## The short version

A scheduled audit on May 4 found a population of cameras we were monitoring but not properly *charging* for. Some of that was our software's fault; some was a downstream data-pipeline issue owned by the data team. Over the week we shipped six small PRs (bundled into one promotion) that fix the connector-side gaps, handed off a tracker file for the data-team-owned half, and added a daily reconciliation check so the next instance of this kind of drift surfaces quickly. Separately, we fixed a long-standing alert-dispatch bug related to Immix session IDs, and ruled out a suspected stream-failure pattern as a labeling issue on Immix's side.

## The cast of characters (for context)

- **AutoPatrol** — our automated camera-checking system. Runs on a schedule, looks for motion or other detections, and dispatches alerts to monitoring stations.
- **VCH** — Visual Camera Health. A lighter-weight cousin of AutoPatrol that just confirms the camera is alive and producing video. Same plumbing.
- **Immix** — the third-party monitoring-station software our partners use. We don't own it. AutoPatrol and VCH both talk to it.
- **`stream_id`** — a session identifier Immix issues when we open a video stream to one of our partner's cameras. We have to quote it back to Immix when we raise an alert.
- **"Billing emit"** — every time AutoPatrol or VCH does a unit of work, our software is supposed to drop a small message onto an internal queue. Downstream, that queue gets ingested into Snowflake, which is what our finance/sales side uses to actually bill customers.

The whole story is about one or more of those layers not talking to one or more of the others.

## What the audit found

The May 4 audit asked, of every camera, "has this had any billing activity in the past while?" The answer was bigger than expected. We split the silent cameras into cohorts A–F by reason. Cohort F (45 customer accounts, 642 cameras) split into two halves once investigated:

- **~392 cameras (22 customers):** our software was emitting the right billing signals, but those signals weren't making it into Snowflake. A data-pipeline problem. Handed to the data team with a per-customer tracker file.
- **~250 cameras (23 customers):** our software was genuinely failing to emit on certain code paths. The half we fixed.

Within the connector-side half, 9 customers (102 cameras) had schedules the partner had already deleted, and 14 customers (148 cameras) were still being monitored but the emit was missing on idle / failure / empty-config paths.

Detailed breakdown: [[2026-05-06_cohort-f-investigation]].

## What we shipped

Six PRs to the connector, bundled into one promotion (vms-connector PR #1688) that went live this week:

1. **Emit on every exit path, win or lose.** Previously, if the partner's API errored, or the camera had no products configured, or the schedule had been deleted on the partner side, the cronjob would exit without telling billing anything happened. *(PR #1675.)*
2. **Idempotency guard.** Our internal queue retries messages on failure. Without a guard, retries risked double-billing. Each message now keys on `(event_type, camera_id)`. *(PR #1680.)*
3. **Fallback billing for misconfigured cameras.** Sites with no products configured now emit under a placeholder so the work is at least visible. *(PRs #1682, #1683.)*
4. **Removed an unused event.** We had been emitting both `_started` and `_ended` signals; downstream only consumed `_ended`. We pulled the unused half. *(PR #1685.)*
5. **Daily reconciliation signal.** A new job compares (cameras the admin DB says are active) vs (cameras emitting billing signals) vs (cameras in Snowflake). The dashboard goes yellow if those numbers diverge past a threshold. Its first run flagged 2,024 production cameras missing from Ordway's subscription system — material work for the sales side.

Founding post-mortem and full PR timeline: [[2026-05-11_billing-pain-post-mortem]]. Catalog of every billing event in the system: [[billing-events-catalog]].

## The separate `stream_id` bug

Alongside the billing work, we fixed a long-standing alert-dispatch bug.

When AutoPatrol opens a video stream to a partner camera, Immix issues a `stream_id` for that session. If the WebSocket connection drops mid-stream and we reconnect, Immix issues a *new* `stream_id`. Our code was still quoting the *old* one when raising an alert at the end of the patrol, and Immix was rejecting those alerts. The failures didn't surface in the patrol logs because they happened after the patrol itself reported success.

The fix keeps a short history of every `stream_id` we've been issued during a single patrol, and on alert dispatch tries the newest first and falls back to older ones if Immix rejects them. We log on the fall-back path so we can see in production that the recovery is actually catching live cases.

Technical writeup: [[2026-05-06_bugfix-stream-id-history-iteration]] (PR #1677 + `actuate-pullers` 1.17.17).

## "Immix shows my patrols as `streamfailed`"

We initially suspected our software was breaking the video stream because Immix's UI was labeling every no-detection patrol as `streamfailed`. After tracing one run end-to-end (logs from both sides), the actual cause turned out to be Immix's own DeviceWorker hitting its 10-second lifespan limit — which is the duration *we asked it for via the API*. The Worker terminates correctly; Immix's labeling layer just calls that termination a failure. We've flagged this to Immix; for now the label is cosmetic.

Full analysis: [[2026-05-06_immix-streamfailed-worker-lifespan]].

## "Zombie tenants"

Three accounts in our European Immix region have vanished from Immix's listings but are still active in our admin database. Our onboarding Lambda polls them every five minutes and gets errors back. One has 10 orphaned customer records under it (Danish test/demo accounts). Immix's API doesn't expose a clean "this tenant is gone" signal today — we get a mix of empty responses, 400s, and 401s for them. We have an outreach to Immix engineering for either a 404-on-removed endpoint or a `tenantStatus=Removed` value in their contracts listing.

API-contract details: [[2026-04-29_immix-zombie-tenants]].

## Deliberate non-action: the Cohort B decision

A sibling cohort (Cohort B, 31 customers) has cameras the partner has confirmed retired but our admin DB still has active. We decided **not** to do a mass deactivation this week.

The reasoning is asymmetric reversibility: backfilling 31 deactivations is a one-line change, but reversing it (if even one customer turns out to be in a soft-pause state we don't know about) is a careful per-customer cleanup. The customer-facing impact of doing nothing is essentially zero — these cameras consume admin-DB rows but no inference compute. The deactivation code is shipped behind a feature flag; we can flip it on later when the broader propagation-hooks design lands. The same posture applies to Cohort F's deactivation candidates.

Decision record with re-open conditions: [[2026-05-07_cohort-b-no-backfill-decision]].

## What made this take a week

The structural problem was that we had **four independent layers** — admin DB, connector code, AWS SQS queue, and Snowflake — each working as designed in isolation, but with no continuous check that what one layer believed matched what the next layer was actually receiving. The new daily reconciliation signal is the first version of closing that gap. The longer-term fix is a series of "propagation hooks" that cascade state changes across the layers; that work sits on the admin team's plate.

## Cross-references

### Primary source notes (one per section)

- [[2026-05-11_billing-pain-post-mortem]] — the founding technical post-mortem; full PR timeline and structural-lesson breakdown
- [[2026-05-06_cohort-f-investigation]] — the audit that surfaced the gap; cohort-F subdivision math
- [[2026-05-01_silent-cameras-diagnosis]] — original cohort-A-through-F decomposition
- [[2026-05-06_bugfix-stream-id-history-iteration]] — `stream_id` history list + fallback iteration (PR #1677)
- [[2026-05-06_immix-streamfailed-worker-lifespan]] — Immix UI mislabel investigation
- [[2026-04-29_immix-zombie-tenants]] — EU zombie-tenant API-contract violations
- [[2026-05-07_cohort-b-no-backfill-decision]] — deferred-deactivation decision record
- [[billing-events-catalog]] — every billing event in the system

### Topic anchors

- [[_summary]] — billing topic overview
- [[_todos]] — outstanding follow-ups
- [[autopatrol/_summary]] — sibling topic (AutoPatrol entity + cohort history)
- [[vms-connector/_summary]] — code surface where the fixes landed
- [[aws-cost/_summary]] — sibling topic (infra cost vs customer revenue; intentionally separate)

### Adjacent reading

- [[2026-05-11_billing-and-followups-handoff]] — session handoff that catalogued what landed this week
- [[autopatrol-cleanup-lambda]] — the self-righting prototype the reconciliation signal is modeled after
- [[2026-04-30_data-model-cascade-semantics]] — admin-side state-wiring gaps that drive the propagation-hooks design
