---
title: "Pre-implementation research priority reorder (2026-05-11)"
type: concept
topic: personal-notes
tags: [research-prioritization, fleet-architecture, billing, pre-implementation, daily-scope-input, handoff-followup]
created: 2026-05-11
updated: 2026-05-11
author: kb-bot
incoming:
  - topics/personal-notes/notes/concepts/2026-05-11_billing-and-followups-handoff.md
  - topics/personal-notes/notes/daily/2026-05-11.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-27
---

# Pre-implementation research priority reorder (2026-05-11)

Closes [[2026-05-11_billing-and-followups-handoff]] item #3 ("Reeval scan"). The session 2026-05-11 produced an ordered list of pre-impl research items for the fleet-architecture workstream. Billing was promoted to top-priority class mid-session via the post-mortem ([[2026-05-11_billing-pain-post-mortem]]). This note reorders against that shift, adds billing-derived research items, and identifies the top 2-3 for promotion to [[mark-todos]].

**Input to next `/daily-scope`** — when picking tomorrow's 2-3 items, read this first.

## Methodology

Re-rank against four criteria:

1. **Bleeding closure** — does this close an ongoing revenue/billing leak or operational risk? Always beats data-gathering for future decisions.
2. **Decision-flipping value** — does the answer change *which* design we pick? Higher than answers that fill in detail on a decision already made.
3. **Cost** — cheap items get a bump; trivial knock-offs slot above slow deep dives at the same value tier.
4. **Availability** — is it actually doable now, or blocked on external response? Blocked items move off the active list to a "[[watch-entity|watch]]" bucket.

## Reordered list

| Rank | Item | Hours | Tier | Why this rank |
|---:|---|---:|---|---|
| 1 | **R1 implementation PR** (build the admin↔emit reconciliation collector + signal per [[2026-05-11_billing-reconciliation-dashboard-design]]) | 8–16 | this-week | Closes the post-mortem's headline risk (unknown drift window). Design is done; impl is concrete. Highest bleeding-closure value of anything on the list. |
| 2 | **T1 spot-check** — classify 5–10 silent containers in NR (completed-no-emit / signal-killed / crashed / stuck-in-healthcheck) per [[billing/_todos]] T1 | 4 | this-week | Pre-impl for the crash-path emit fix. Cheap. Output directly feeds the crash-emit design decision (and may collapse the 79%-silent number to something less alarming). |
| 3 | **Confirm `connector validate` subcommand exists** (per §5 "Run Service — translator + spec") | 0.25 | this-week | Trivial knock-off. Either way the answer reshapes Run Service translator+spec sequencing. No good reason to leave this hanging. |
| 4 | **NR query: actual FDMD drop rate fleet-wide** (was old #1 per session 2026-05-11 list) | 2 | this-week | Could flip the fleet E→C decision. Was the top fleet item before billing surfaced; still high-value but no longer #1 overall. |
| 5 | **Tier3 replication investigation** (S3 Storage Lens / CUR+Athena / CloudTrail) — §5 pre-PoC open question | 1 | this-week | $44k/year cost lever; independent of billing. Cheap. |
| 6 | **[[pyav-entity|PyAV]] GIL budget measurement at frame rate** (was old #3) | 4 | next-week | Partially flips E→C. Same priority as before billing shift — fleet items just get a tier shift, not internal reorder. |
| 7 | **WireGuard/tunnel inventory** (was old #2) | 8 | next-week | Flips C unviable if customers don't have tunnels. Larger lift; gather data later. |
| 8 | **Lease-churn benchmark** (was old #5) | 4 | next-week | Does not flip a decision. |

## Watch bucket (blocked — no active work)

These are tracked but require external response. Don't promote until the blocker clears.

| Item | Blocker | Status |
|---|---|---|
| **ENG-242 response** — Snowflake DDL + filter logic (closes [[billing/_todos]] C2, C5, T2, T3, T4) | Data-team triage and reply | Filed 2026-05-11; no action on our side |
| **S1 — AutoPatrolSchedule post-delete propagation hook design** | Admin-team alignment on cascade-semantics ADR ([[2026-05-07_cohort-b-no-backfill-decision]]) | Pre-decision |
| **S2 — Customer.active → cameras propagation hook design** | Admin-team decision on `active=False` semantics (soft-disable vs soft-delete) | Pre-decision |
| **T1 final design** | PR #1688 merge + baseline stabilization | Merge deferred to Monday 2026-05-11 |

## Removed from active list

- (none) — all six original session-2026-05-11 fleet items remain ranked; none have been sunsetted.

## Top 3 — promote to mark-todos

The three this-session-actionable winners. These should get a `[ ]` line in their respective §N today, so they surface as candidates in `/daily-scope` tomorrow:

1. **R1 implementation PR** → mark-todos §28 (billing) — add as a discrete open work item under R1.
2. **T1 spot-check (5–10 silent containers)** → mark-todos §28 (billing) — add under T1, flagged as the pre-impl research step.
3. **Confirm `connector validate` subcommand exists** → mark-todos §5 (fleet) — already present at line 136 as an open item; nothing to add.

(#4 NR FDMD-drop query is a strong tier-2 candidate; promote if R1 impl ends up blocked on something unexpected.)

## Re-eval triggers

Re-run this reorder when:

- ENG-242 lands (Snowflake DDL — unblocks multiple billing items and may demand re-prioritization).
- PR #1688 merges and the post-merge baseline establishes (unblocks T1 final design — current spot-check #2 becomes design work).
- Admin-team responds on the cascade ADR (unblocks S1 + S2 design work).
- Any fleet-architecture proposal-deep-dive happens that re-weights the rubric (the rubric monitoring + billing dimensions are handoff item #4 — still pending).
- 14 days from now (2026-05-25) regardless — keep the reorder from staling silently.

## Cross-references

- [[2026-05-11_billing-and-followups-handoff]] — item #3 this note closes
- [[2026-05-11_billing-pain-post-mortem]] — the priority-shift driver
- [[2026-05-11_billing-reconciliation-dashboard-design]] — R1 design (this note's #1)
- [[billing/_todos]] T1, R1, C2 — items referenced
- [[mark-todos]] §5 — fleet workstream (items 3-8 belong here)
- [[mark-todos]] §28 — billing workstream (items 1-2 belong here)
- [[2026-05-05_fleet-architecture-workstream-context]] — fleet workstream's prior context (the session-2026-05-11 list was built against this)
- [[2026-04-22_fleet-proposal-rescore-with-delta]] — rubric rescore that the fleet pre-impl items inform
