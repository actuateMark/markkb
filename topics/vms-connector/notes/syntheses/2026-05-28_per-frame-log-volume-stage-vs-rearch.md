---
title: "Per-frame INFO logs in the connector hot path — stage→rearch scaling trap"
type: synthesis
topic: vms-connector
tags: [logging, observability, rearch-promotion, blacklist, scaling, code-review-finding]
created: 2026-05-28
updated: 2026-05-28
author: kb-bot
sources:
  - vms-connector PR #1713 (https://github.com/aegissystems/vms-connector/pull/1713)
  - actuate-libraries#360 — feat(blacklist): default decay on + suppression reason logging
  - vms-connector#1715 — stage bump for default-on decay
incoming:
  - topics/personal-notes/notes/daily/2026-05-28.md
incoming_updated: 2026-05-30
---

# Per-frame INFO logs in the connector hot path — stage→rearch scaling trap

Surfaced during the [[2026-05-28_session-handoff|2026-05-28 PR #1713 review]] of the BlacklistFilter decay-default-on rollout. The finding is general — not specific to the blacklist filter.

## The trap

Stage runs **~62 active connector pods**. Rearch (production) runs **~5,700 pods** (per the `rearchitecture` namespace in `Connector-EKS`). That's a **~92× pod-count scale factor** between stage and the prod fleet that stage→rearch promotions ship to.

When a code change introduces a per-frame or per-suppression log line in the hot path at INFO level — even one that looks reasonable on a single test stream — its real cost is invisible until it lands on rearch. Stage volume can look bounded; the rearch projection blows past the "should this be DEBUG?" threshold by an order of magnitude.

## Concrete numbers from PR #1713

Library [[actuate-libraries-pr-360]] flips `use_decay_scoring` from opt-in → default-on AND adds per-suppression `BLACKLIST_SUPPRESSED` INFO logs in `blacklist_step.py`. No rate limiting, no per-group dedup, no sampling.

NR cluster-wide (`cluster_name='Connector-EKS'`, `message LIKE '%BLACKLIST_SUPPRESSED%'`, last 6 h since #1715 landed on stage 2026-05-27 18:03 UTC):

| Window | Stage volume | Top emitter | Distribution |
|---|---|---|---|
| 6 h | 54,545 lines | `connector-34880` = 8,606 (~1.4 k/h) | top 2 pods = 27 % of cluster total |

- Stage rate: **~9.1 k/h cluster-wide** (heavy-tailed; per-pod average ~147/h).
- Rearch projection (per-pod-average × pod-count): **~836 k/h cluster-wide**, or **~20 M lines/day**.

Stage alone sits just under "concerning"; rearch sits ~80× above. The cost difference between "fine on stage" and "spike NR ingest by 20 M/day on rearch" is one rebase against `stage`.

## How to catch this before clicking merge

Pre-merge checklist for any rearch-bound PR that touches a connector hot-path code path (filter step, observer, puller `on_frame`, alarm send):

1. **Grep the diff for new `logging.info` / `logger.info` calls inside per-frame loops** (e.g. inside `Step.process`, `Observer.on_data`, `Filter.__update_data`, `Puller.handle_frame`). New INFO inside an existing `for` over detections / boxes / frames is the signature.
2. **If found, query stage for the line cadence** with NRQL: `SELECT count(*) FROM Log WHERE cluster_name = 'Connector-EKS' AND message LIKE '%<UNIQUE_TOKEN>%' SINCE 6 hours ago` (use a wider window if the change landed recently). Also FACET by `container_name` to see distribution.
3. **Multiply per-pod-average by ~92×** for the rearch projection. Sanity check: top-emitter × ~92 if the heavy tail is structural (e.g. high-FP cameras exist in similar proportion on rearch).
4. **Threshold:** projected ≥ 10 k/h cluster-wide → DEBUG or sample. ≥ 100 k/h → block on a gating mechanism (per-group emit-once-then-every-N, or downgrade to DEBUG with a switch to enable per-PR investigations).

The threshold is a heuristic, not a hard rule — but **don't merge without writing down the projection**, even if the answer is "fine."

## Why INFO is the temptation

The signal *is* useful — `BLACKLIST_SUPPRESSED` with the matched-group reason is exactly the FP attribution data the decay feature was built to expose. DEBUG hides it from default ingest; INFO surfaces it. The good fix isn't "always DEBUG" — it's "INFO but gated":

- Emit per state-transition (HOT, COLD, REASON_CHANGED) at INFO — naturally bounded.
- Emit per-suppression at DEBUG OR with a per-group emit-once-then-every-N gate.
- Or: aggregate counts into a periodic INFO summary (e.g. once per minute per filter: `BLACKLIST_SUPPRESSED_SUMMARY count=X by_reason={...}`).

## Cross-refs

- [[2026-05-28_session-handoff]] — the morning's PR #1713 path; this finding surfaced in the agent verdict.
- [[branch-conventions]] — stage/rearch fleet definitions; rearch is a PROD fleet.
- [[code-review-checklist]] — add per-frame INFO log audit as a connector hot-path review item.
- vms-connector PR [#1713](https://github.com/aegissystems/vms-connector/pull/1713) — review verdict comment at [#issuecomment-4565762013](https://github.com/aegissystems/vms-connector/pull/1713#issuecomment-4565762013).
- actuate-libraries PR [#360](https://github.com/aegissystems/actuate-libraries/pull/360) — the source of the new logs.
