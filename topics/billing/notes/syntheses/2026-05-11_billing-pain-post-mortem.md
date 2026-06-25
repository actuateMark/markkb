---
title: "Billing-pipeline pain — post-mortem on the April-May 2026 emit-gap firefight"
type: synthesis
topic: billing
tags: [billing, post-mortem, customer-events, site_product_ended, cohort-f, cohort-b, vms-connector, snowflake, reconciliation, vms-connector]
created: 2026-05-11
updated: 2026-05-11
author: kb-bot
[]
incoming:
  - topics/billing/_summary.md
  - topics/billing/_todos.md
  - topics/billing/notes/concepts/2026-05-11_billing-reconciliation-dashboard-design.md
  - topics/billing/notes/concepts/2026-05-11_eng-242-substantially-answered.md
  - topics/billing/notes/concepts/2026-05-14_inference-api-e2m-rules.md
  - topics/billing/notes/entities/actuate-bi-repo.md
  - topics/billing/notes/entities/billing-deferred-backlog.md
  - topics/billing/notes/entities/billing-events-catalog.md
  - topics/billing/notes/entities/snowflake-billing-tables.md
  - topics/billing/notes/syntheses/2026-05-12_week-in-review-non-technical.md
incoming_updated: 2026-05-27
---

# Billing-pipeline pain — post-mortem on the April-May 2026 emit-gap firefight

This is the founding document of the [[knowledgebase/topics/billing/_summary|billing topic]]. It synthesizes the ~four weeks of incremental connector PRs, cohort audits, and admin-side cascade work driven by the discovery that we had been silently leaking customer billing events for an unknown period. The point of this post-mortem is **not** to relitigate each PR — those are documented in their own concept notes — but to extract the **structural lesson** so the next time this surface drifts we catch it in days, not weeks, and ideally automatically.

## What happened (compressed timeline)

| Date | Event | Bytes of pain |
|------|-------|---------------|
| (pre-history) | Alibi billing-profile redesign: Sales Order number becomes the unique identifier; SO must live on the lowest-level site that contains cameras (see [[worklog-alibi-billing-redesign]]). | Foundation that everything else assumes |
| 2026-05-04 | Silent-camera audit ([[2026-05-04_silent-camera-diagnosis]]) decomposes into Cohorts A-F — **642 cameras across 45 customers in Cohort F** flagged as "showing no billing activity over the window." | Drift discovered |
| 2026-05-05 | Cohort B backfill runbook ([[2026-05-05_cohort-b-backfill-runbook]]) — admin cascade pattern operationalized for one class | DRY-RUN + APPLY pattern proven |
| 2026-05-06 | Cohort F deep investigation ([[2026-05-06_cohort-f-investigation]]) — **NR + Immix probes split the 642**: 392 cams are emitted-but-Snowflake-didn't-ingest; 250 are connector-side emission gaps (no `_ended` fires on failure / empty-products / idle paths). Cluster-wide `_started` count: **zero**. | The structural problem is visible end-to-end for the first time |
| 2026-05-06 | PR #1675 lands on stage — adds `_emit_site_product_event("site_product_started")` and `_ended` walk on every cronjob exit path. Designed against the (incorrect) premise that downstream consumed both. | The first patch |
| 2026-05-06 | PR #1680 — per-stream idempotency guard `(event_name, admin_camera_id)` keying. SQS retries no longer double-count. | Foundation patch — keep |
| 2026-05-07 | PR #1682 — healthcheck fallback for empty-`products`-list case (`_HEALTHCHECK_FALLBACK_PRODUCT`). | Patch #2 |
| 2026-05-07 | PR #1683 — rename fallback → `_MISCONFIGURED_FALLBACK_PRODUCT`; site-level fallback for empty `camera_streams`. | Patch #3 |
| 2026-05-07 | PR #1685 — **removes** all `_started` emit sites. Downstream confirmed it consumes only `_ended`; `_started` was net SQS waste. | The retraction of patch #1's started-half. The helper stays event-name-agnostic. |
| 2026-05-07 | Fleet-wide silent-billing scan: **79% AP cronjobs / 67% VCH cronjobs** silent over 24h (zero `_ended` emits per container). PR #1682 closes the "ran clean, products empty" subset; **crash-path remains uncovered**. Filed as deferred backlog item [[autopatrol-deferred-backlog|"Billing emit on crash / early-endrun paths"]]. | New gap class discovered while patching the old one |
| 2026-05-07 | PR #1681 stage→rearchitecture promotion drafted. **Closed 2026-05-08 due to overlay-branch rule violation** ([[2026-05-07_handoff-pr-1681-promotion]] §"Update 2026-05-08"). | Process drift — separate failure mode but ate hours |
| 2026-05-08 | PR #1686, #1687 — also closed (overlay branch). PR **#1688** — finally rule-compliant: `head=stage, base=rearchitecture` direct, full bundle. Soak verdict GREEN. | Recovery |
| 2026-05-11 | Merge deferred to Monday (today). | (where we are) |

## The structural problem (in plain language)

We had **four** independent layers, each owned by different code paths, none of which observed the others:

```
  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
  │   ADMIN     │    │  CONNECTOR  │    │     SQS     │    │  SNOWFLAKE  │
  │  (truth-1)  │    │   (emitter) │    │ (transport) │    │ (ledger)    │
  │             │    │             │    │             │    │             │
  │ Customer    │───►│ site_product│───►│ event_queue │───►│ billing     │
  │  .active    │    │   _ended    │    │  _analytics │    │   tables    │
  │ Camera      │    │   on exit   │    │   .fifo     │    │             │
  │  .is_deleted│    │   path      │    │             │    │             │
  │ Schedule    │    │             │    │             │    │             │
  │  .is_deleted│    │             │    │             │    │             │
  └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
        │                  │                                       │
        │                  └── per-stream idempotency              │
        │                                                          │
        │  ┌──────── IMMIX (truth-2, partner) ──────┐              │
        └──┤ scheduleStatus / contractStatus drift  │              │
           └────────────────────────────────────────┘              │
                                                                   │
        ╳ NO RECONCILIATION LOOP ╳                                 │
        Nothing checks (admin says active) == (we emit) ==         │
        (Snowflake ingested) at fleet scale until a cohort audit ──┘
        runs manually.
```

Each individual layer was working as designed. The drift lived **between** layers and was invisible to all of them.

Specifically, **five separate emission-gap classes** existed simultaneously in the connector code path:

1. **Patrol-error path** (F4) — cronjob fired, [[immix-vendor-api|Immix API]] errored, no `_ended` emit. Pre-PR-#1675.
2. **Empty-`products`-list path** (a subset of "ran clean but no products configured") — no `_ended` emit because the per-product loop had nothing to iterate. Pre-PR-#1682.
3. **Empty-`camera_streams` site-level path** — same as above but at the site fallback level. Pre-PR-#1683.
4. **Schedule-Deleted-or-Paused-in-Immix path** (F3a/b/c) — admin still says Active; cronjob fires; no patrols; old code path didn't emit on no-patrol returns. The cleanup-Lambda catches this *eventually* (Step F deferred at the moment) but billing leaked in the meantime.
5. **Crash / SIGKILL / early-exit path** — process dies before reaching `endrun()`. **Still open** (deferred backlog).

And **one ingestion-gap class** existed in Snowflake:
- **F6/F5** — connector emits `_ended` to the SQS queue correctly; the data-team-owned consumer downstream doesn't ingest. Likely an `event_type` filter or `act_a` filter or table-mapping mismatch. Out-of-team-scope today; tracker handoff in [[2026-05-06_cohort-f-investigation]] §3.

And **one process gap** existed in the connector deployment chain:
- The dev→stable squash-merge `[no ci]` issue ([[handoff-pr-1681-promotion]] §"Squash subject") and the overlay-branch rule violation that produced three closed-PR-iterations to do one merge. Adjacent — not strictly billing — but the slow deploy chain made the firefight take days longer than it should have.

## What we got right

- **Cohort audits as discovery harness.** The cohort decomposition (A-F) turned a vague "billing seems off" into specific numbers per failure class. Cohort B and F's runbooks are reusable assets — keep them current.
- **Per-stream idempotency guard (PR #1680).** Keyed on `(event_name, admin_camera_id)`. Survives the `_started` retraction unchanged because it's event-name-agnostic. Foundation pattern; reuse for any new emit site.
- **The helper stayed event-name-agnostic during the `_started` retraction (PR #1685).** Specifically: `emit_site_product_event_for_streams` accepts an arbitrary event name. If downstream changes its mind in 6 months, the call site change is one line — not a re-design.
- **Cleanup-Lambda as the self-righting prototype.** [[autopatrol-cleanup-lambda]] is the *only* fully-automated drift-detect-and-correct pipeline in this domain. Confirm-via-second-source + threshold + audit-trail (Slack + NR custom event) is the pattern to replicate up the stack.
- **Defensive deprecation note ([[2026-05-07_site-product-started-deprecated]]).** The `_started` retraction kept a clean re-enable path with explicit guidance. Whoever revives `_started` doesn't have to reverse-engineer why we removed it.

## What we got wrong (and how to not get it wrong again)

### 1. We didn't have a billing-events catalog. ⟶ [[billing-events-catalog]] now exists.

Until 2026-05-06 we were not sure whether `_started` was a real downstream event or vestigial. We patched in both, then removed one. **Cost: one entire PR cycle plus the deprecation note.** A catalog of "every billing-relevant event, where it's emitted, where it's consumed, what it discriminates on" should have been the first artifact, not the last.

### 2. The emission code path had no "emit on every exit" invariant. ⟶ Now (mostly) invariant; crash-path still owed.

`startrun()` was added in PR #1675, paired with `endrun()` semantics, with the explicit intent that **every cronjob run ends with at least one billing event regardless of outcome**. The retraction of `_started` (PR #1685) means the invariant downgraded to `_ended` only — which is fine if `_ended` actually fires on every path. The crash path is the surviving counterexample. **Action: design crash-emit. Tracked in topic todos.**

### 3. We had no continuous drift-detection between admin / emit / Snowflake. ⟶ Topic todos item: "Continuous reconciliation dashboard."

The 642-camera cohort F was discovered manually. By the time it surfaced, customers had been mis-billed for an unknown duration. **The fact that cohort F's window-length is unknown is the post-mortem's most uncomfortable finding.** Action: build a continuous reconciliation signal that compares `count(active admin sites × products)` vs `count(distinct site/product emitting `_ended` in trailing window)` vs `count(Snowflake billing rows in trailing window)`. Surface to dashboard. Alert on >X% gap.

**Design landed 2026-05-11:** [[2026-05-11_billing-reconciliation-dashboard-design]] specs the admin↔emit half (R1). Snowflake half (R2) is data-team-owned post-cohort-F-tracker handoff.

### 4. We confused customer billing pipeline with infra cost pipeline. ⟶ Now two separate topics.

For weeks, "billing" and "AWS cost" were the same Confluence query in some heads and not in others. They're connected (every SQS PUT costs both a fraction-of-a-cent in AWS and triggers a customer-revenue line in Snowflake) but the **failure modes, audiences, and remediation paths are unrelated**. Action: this topic ([[knowledgebase/topics/billing/_summary]]) is parallel to [[aws-cost/_summary]]; cross-link, don't conflate.

### 5. The admin source-of-truth state has signal-wiring gaps. ⟶ [[2026-04-30_data-model-cascade-semantics]] inventoried them; topic todos owns the closures.

`Customer.active=False` doesn't propagate to cameras. `AutoPatrolSchedule.delete()` doesn't propagate up. `Customer.restore()` doesn't reactivate cascade-deleted cameras. `Contract.status='Cancelled'` doesn't touch Group/Customer. **Each of these is a future-billing-drift class waiting to happen.** Action: close them (or document and accept) per the propagation-hooks design ADR in topic todos.

### 6. The deploy-chain friction was a force multiplier. ⟶ Out of scope here, owned by [[engineering-process/_summary]].

PR #1681/#1686/#1687 closed for overlay-branch violations; the squash-merge `[no ci]` problem cost two PRs. These aren't billing problems but they extended the billing firefight by days each. Cross-ref `feedback_no_overlay_branches_for_stage_to_rearch.md`.

## What's still owed (post-mortem → topic todos)

This post-mortem feeds [[_todos]] directly. Categories that emerge from the lessons above:

| Lesson → | Topic-todo category |
|---|---|
| Lesson 2 (emit on every exit) | **Tightening** — close crash / SIGKILL gap |
| Lesson 3 (continuous reconciliation) | **Reconciliation** — admin↔emit↔Snowflake signal |
| Lesson 5 (admin signal wiring) | **Self-righting** — propagation hooks per [[2026-04-30_data-model-cascade-semantics]] |
| Lesson 1 (no catalog) | **Codification** — keep [[billing-events-catalog]] current; PR template entry for new emit sites |
| Lesson 4 (separation of concerns) | **Codification** — this topic exists |
| Implicit lesson — Snowflake side opaque | **Reconciliation** — engagement with data-team on F6/F5 ingest gap |
| Implicit lesson — cohort audits manual | **Observability** — cohort dashboard signals; automate the runbook |

Each of those rolls up into a concrete todo in [[_todos]] with acceptance criteria.

## Status of the recent PR chain (snapshot for handoff)

| PR | Status (2026-05-11) | What it did |
|---|---|---|
| vms-connector#1675 | Merged to stage (in #1688 bundle) | startrun + per-product emit walk |
| vms-connector#1680 | Merged to stage (in #1688 bundle) | per-stream idempotency guard |
| vms-connector#1682 | Merged to stage (in #1688 bundle) | healthcheck fallback for empty-products |
| vms-connector#1683 | Merged to stage (in #1688 bundle) | rename → "misconfigured"; site-level fallback for empty `camera_streams` |
| vms-connector#1685 | Merged to stage (in #1688 bundle) | **removed** `_started` emit sites; helper kept event-name-agnostic |
| vms-connector#1684 | Merged to stage (in #1688 bundle) | line-crossing libs bump (unrelated to billing thread; bundled) |
| vms-connector#1681 | Closed 2026-05-08 | Replaced (user wanted #1684 split) |
| vms-connector#1686, #1687 | Closed 2026-05-08 | Overlay-branch rule violations |
| **vms-connector#1688** | **OPEN, BLOCKED on REVIEW_REQUIRED — Monday merge** | Full bundle: rule-compliant stage→rearchitecture promotion |
| autopatrol_onboarder#14 | Drafted; **`cohort_f_tracker.json` handoff to data team complete on our side (2026-05-11)** | Cohort-F deep classifier + tracker. PR merge when team-reviewed. The tracker (45 cids, status=`fixed`/`diagnosed`) is the artifact data team needs for the Snowflake-side F6/F5 ingestion-gap root-cause. We have no further action here unless data team escalates back ([[_todos]] R2). |

Post-merge monitor: Tier-1 systemd one-shots on Firebat mirroring PR #1660 pattern. [[watch-entity|Watch]] for zero `_started` events, steady `_ended` volume, no new error classes vs the 12h pre-merge baseline.

## Cross-references

- [[knowledgebase/topics/billing/_summary]] — topic overview
- [[billing-events-catalog]] — what events exist (the catalog this firefight finally produced)
- [[_todos]] — work owed
- [[knowledgebase/topics/billing/reading-list]] — external + internal sources
- [[2026-05-06_cohort-f-investigation]] — the audit that surfaced the gap
- [[2026-05-04_silent-camera-diagnosis]] — the original cohort decomposition
- [[2026-05-05_cohort-b-backfill-runbook]] — sibling cohort that informed the runbook pattern
- [[2026-05-07_site-product-started-deprecated]] — the dormancy warning
- [[2026-05-07_handoff-pr-1681-promotion]] — promotion-chain handoff
- [[2026-04-30_data-model-cascade-semantics]] — admin signal wiring inventory
- [[autopatrol-cleanup-lambda]] — the self-righting prototype to copy
- [[worklog-alibi-billing-redesign]] — sales-order profile foundation
- [[autopatrol-deferred-backlog]] §"Billing emit on crash / early-endrun paths" — the still-open gap
- [[mark-todos]] — workstream tracker (loose-link from topic-todos)
