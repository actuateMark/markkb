---
title: "Fleet Proposal Re-Score with 2026-04-22 Delta + Real CE Data"
type: synthesis
topic: fleet-architecture
tags: [rescore, evaluation, proposal-comparison, ce-grounded, synthesizer-pilot-3]
created: 2026-04-22
updated: 2026-04-22
author: kb-bot
incoming:
  - home/offboarding/2026-06-23_watchman-fleet-handoff-paolo-mike.md
  - topics/aws-cost/_summary.md
  - topics/aws-cost/notes/concepts/2026-04-23_s3-tier3-breakdown.md
  - topics/aws-cost/notes/syntheses/2026-04-23_s3-tier3-cost-investigation.md
  - topics/aws-cost/notes/syntheses/2026-04-27_aws-cost-topic-spinoff.md
  - topics/aws-cost/notes/syntheses/2026-04-28_s3-cost-reduction-action-plan.md
  - topics/fleet-architecture/notes/syntheses/2026-05-05_fleet-architecture-workstream-context.md
  - topics/fleet-architecture/notes/syntheses/2026-05-11_rubric-monitoring-billing-dimensions.md
  - topics/fleet-architecture/notes/syntheses/2026-06-02_watchman-phase0-fleet-fit.md
  - topics/personal-notes/notes/concepts/2026-05-11_billing-and-followups-handoff.md
incoming_updated: 2026-06-25
---

# Fleet Proposal Re-Score with 2026-04-22 Delta + Real CE Data

## Motivation

The 2026-04-16 proposal scoring was produced before any of the subsequent week's grounding evidence landed. In the intervening days, three things happened that warrant revisiting the weighted composites: (1) the frame-storage design-delta surfaced an in-cluster-blob + conditional-promotion direction that initially read as a >50× S3 API-call collapse but was later corrected by a second NR query showing the true non-eventful-window ratio is ~31%, not >99%; (2) an AWS Cost Explorer pull for the 30-day window ending 2026-04-22 replaced projected S3 cost assumptions with real dollars ($32,820.89 / 30 days; ~$399k/year annualized); and (3) Proposal B-prime was examined and formally closed at 6.25/10 with a closeout banner, leaving five candidate proposals in play. A fourth consideration — the **fleet-coordinator unification question** surfaced during the B-prime analysis — remains open and is structurally relevant to C and E's operational-simplicity scoring.

The load-bearing evidence here is the AMENDMENT banner in `[[2026-04-22_frame-storage-design-deltas]]` which retracts the >50× multiplier, the B-prime closeout at `[[2026-04-22_proposal-b-prime-stateless-with-coordinator]]`, the CE figures captured in both amendments, and the coordinator-unification concept at `[[fleet-coordinator-unification-question]]`. This re-score is not a decision; it is the 2026-04-16 rubric rerun against the 2026-04-22 state of evidence, with the original proposal syntheses held as the primary per-proposal input and the delta synthesis read critically (several of its per-proposal recommendations rested on the retracted >50× premise and must be treated as superseded where that premise was load-bearing).

## Ground-truth cost data (2026-04-22)

AWS Cost Explorer, `AWS_PROFILE=prod` (account 388576304176), 30-day window 2026-03-23 through 2026-04-22, UnblendedCost:

| Line item | 30-day cost | % of S3 | Annual (×12.17) | Notes |
|-----------|------------:|--------:|----------------:|-------|
| **Tier1 PUT / COPY / POST / LIST** | **$15,016.91** | **45.8%** | ~$182,756 | 2.8B requests |
| **Storage (GB-month)** | **$11,548.20** | **35.2%** | ~$140,540 | 1.94M GB-months ≈ 65 TB working set |
| **Tier3 replication / lifecycle** | **$3,646.91** | **11.1%** | ~$44,380 | 72.9M requests |
| **Tier2 GET / SELECT** | **$1,869.52** | **5.7%** | ~$22,750 | 4.66B requests |
| **Data transfer** | **$695.00** | **2.1%** | ~$8,460 | |
| Retrieval + early-delete | <$50 | <0.2% | <$600 | Negligible |
| **Total S3** | **$32,820.89** | **100%** | **~$399,463** | |

The "S3 cost is API-calls-dominated" hypothesis is **confirmed but modestly**: 62.7% of the bill is request-priced (Tier1 + Tier2 + Tier3), and 35.2% is storage. That is materially different from the "storage is dominant, so Intelligent-Tiering will save us" mental model that predated this pull; it is also materially different from the short-lived "requests are 95%+ and conditional-promotion is transformative" claim that the pre-correction design-delta read into the data. The correct framing sits between those two: any meaningful S3 cost reduction has to hit requests, but requests are not infinite leverage — halving request volume saves ~$93k/year, not ~$200k/year, and storage remains material enough that motion-gating (which reduces both storage and PUT count proportionally) has a structural advantage over conditional-promotion (which primarily reduces PUT count).

One line item deserves standalone investigation independent of any proposal: **Tier3 replication/lifecycle at $3,647/mo (~$44k/year) on 72.9M requests**. That is an above-expected value for replication traffic on a 65 TB working set. Possibilities include: cross-region replication on buckets that shouldn't have it; lifecycle transitions firing on objects that immediately delete (wasted transition cost); or replication policies inherited from [[watchman-repo|Watchman]]/AutoPatrol paths that have drifted. This is worth an analyst-hour before PoC work starts — it may yield a pre-PoC win independent of any fleet proposal.

## Rubric axes and weightings

From `[[2026-04-16_evaluation-rubric]]`:

| Axis | Weight | 2026-04-22 scoring-logic impact |
|------|-------:|---------------------------------|
| Independent scalability | **35%** | Unchanged. Primary criterion, no new evidence. |
| Cost reduction | **20%** | **Changed.** Replace projected "10× fleet" modeling with actual $33k/mo S3 baseline. Motion-gating-at-puller is the real cost lever (D/E); conditional-promotion is a ~1.45× second-order win (all proposals adopting the delta). |
| Failure isolation | **15%** | Unchanged. |
| Operational simplicity | **15%** | **Partially changed.** Fleet-coordinator unification question introduces a "could simplify if unified" upside for C/E scoring, but as long as the question is open, neither gets the upside. No change to scores; flagged as a post-PoC lever. |
| Migration risk | **10%** | Unchanged. |
| Failover quality | **5%** | Unchanged. |

Weights sum to 100. The re-score adjusts scores on the two axes where the 2026-04-22 evidence is load-bearing (cost reduction most; operational simplicity latently). Everywhere else, 2026-04-16 scores are preserved because the underlying evidence hasn't shifted.

## Per-axis re-scoring notes

### Cost reduction (20%) — largest change

The 2026-04-16 scoring used a projected "10× fleet" lens with the cost-delta brackets from the rubric (−30% or better → 10; 0 to −10% → 6; +10-20% → 2). Those brackets are preserved. What changes is the **evidence going into the score** for each proposal:

- **Motion-gating-at-puller (D, E)**: if FDMD drops 60-80% of raw frames before they hit Redis/NATS/S3, both PUT volume and storage GB-months drop proportionally. On the $33k/mo baseline with 62.7% request cost and 35.2% storage cost, a 70% frame drop would linearly reduce ~97.9% of the S3 workload's drivers (all the frame paths). In practice the non-frame paths (clip uploads, spray bucket, replication) don't drop — call it a ~50-60% S3 cost reduction if motion-gating works as modeled, i.e. ~$16-20k/mo savings (~$200-240k/year). This is the single largest lever in any proposal.
- **Conditional-promotion-at-window-close (applies to all delta-adopting proposals, most structurally to A, C, E)**: corrected to ~1.45× PUT reduction on the non-eventful-window population, i.e. ~$4.7k/mo of the $15k/mo Tier1 bill (~$56k/year). This is real but modest, and it stacks multiplicatively with motion-gating for D/E.
- **No-frame-transport (C)**: per `[[2026-04-16_proposal-c-camera-worker]]` §"Cost model", C's zero-cross-AZ-frame-transit and absence of a Redis frames-bus delivers −15% to −30% projected at 10× fleet. That projection predates the CE data but is consistent with it — the savings come from avoiding the data-transfer bill plus [[shrinking]] the Redis cluster to a control-plane-only footprint, not from S3 directly. C does not *natively* do motion-gating but can adopt the in-cluster-blob-plus-conditional-promotion pattern trivially (delta synthesis §"Proposal C" explicitly calls this out as "Natural fit"), so C picks up the ~$4.7k/mo conditional-promotion win plus its existing structural savings.
- **B's 4-hop frame transport (B)**: baseline projected +15-25% at current scale, break-even at 3-5× fleet. The CE data confirms that cross-AZ data transfer is only 2.1% of S3 cost today ($695/mo), but B's cost story is about the much larger ~$400k/mo projected inter-AZ bill at scale driven by full JPEG bytes traversing 4 Redis Streams hops — the CE data neither confirms nor refutes that projection (today's bill isn't 4-hop-based; the projection is what B's architecture would incur). No change to B's cost score.
- **A (minimal split)**: A's +10-15% vs today was based on one Redis hop plus added pod count. CE data doesn't change A's story. If A adopts the delta (it can, with moderate code churn in `SlidingWindowStep.close_window`), it picks up the ~$4.7k/mo conditional-promotion win — enough to move A from "+10-15%" to "roughly neutral," but not into cost-win territory.

### Operational simplicity (15%) — latent change

The fleet-coordinator unification question (`[[fleet-coordinator-unification-question]]`) asks whether C's Assignment Controller, E's Site Context Service, and B-prime's (now closed) Blob Coordinator are implementation variants of one primitive. If answered affirmatively during design review, C and E would each see an ops-simplicity upside because their control-plane service becomes a shared platform primitive rather than per-proposal infrastructure. As of 2026-04-22 the question is open; both proposals' 2026-04-16 ops-simplicity scores stand.

For clarity, this re-score does not give C or E credit for hypothetical unification. If the API-sketch design-review answers the question affirmatively, a subsequent re-score would bump both by +1 on ops simplicity (+0.15 weighted each). That is tracked as a future adjustment, not applied now.

### Independent scalability, failure isolation, migration risk, failover quality

No new evidence bearing on any of these since 2026-04-16. Scores carried forward unchanged. (Migration-risk specifically: the delta work adds ~1-2 weeks of `SlidingWindowStep.close_window` + PyAV-encode code to whichever proposal wins — negligible on the 14-32 week scale, doesn't shift any bracket.)

## Per-proposal re-scored tables

Each table carries 2026-04-16 scores in column 2, the 2026-04-22 rescore in column 3, and delta rationale in column 4. Weighted totals are recomputed at the bottom.

### Proposal A — Minimal Split

| Dimension                     | 2026-04-16 | 2026-04-22 | Delta + rationale                                                                                                                                |
| ----------------------------- | ---------: | ---------: | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| Independent scalability (35%) |          3 |          3 | No change. Pipeline still site-pod.                                                                                                              |
| Cost reduction (20%)          |          3 |          4 | +1. Adopting the conditional-promotion delta saves ~$4.7k/mo; moves A from "+10-15%" to "roughly neutral." Still doesn't reach the -10% bracket. |
| Failure isolation (15%)       |          4 |          4 | No change.                                                                                                                                       |
| Operational simplicity (15%)  |          6 |          6 | No change.                                                                                                                                       |
| Migration risk (10%)          |          9 |          9 | No change (delta is ~1-2 weeks additive, within bracket).                                                                                        |
| Failover quality (5%)         |          4 |          4 | No change.                                                                                                                                       |

Weighted 2026-04-22: `(3×0.35)+(4×0.20)+(4×0.15)+(6×0.15)+(9×0.10)+(4×0.05) = 4.45 / 10` (vs 4.25).

### Proposal B — Stage Fleets

| Dimension                     | 2026-04-16 | 2026-04-22 | Delta + rationale                                                                                                                                                                                                                                             |
| ----------------------------- | ---------: | ---------: | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Independent scalability (35%) |         10 |         10 | No change. Strongest on primary criterion.                                                                                                                                                                                                                    |
| Cost reduction (20%)          |          6 |          6 | No change. The delta-synthesis's "awkward fit" analysis for B is retained as architecturally valid, but the ~1.45× corrected multiplier doesn't make the awkwardness materially worse or better — the CE data doesn't meaningfully revise B's 10× projection. |
| Failure isolation (15%)       |          9 |          9 | No change.                                                                                                                                                                                                                                                    |
| Operational simplicity (15%)  |          3 |          3 | No change.                                                                                                                                                                                                                                                    |
| Migration risk (10%)          |          3 |          3 | No change.                                                                                                                                                                                                                                                    |
| Failover quality (5%)         |          9 |          9 | No change.                                                                                                                                                                                                                                                    |

Weighted 2026-04-22: `(10×0.35)+(6×0.20)+(9×0.15)+(3×0.15)+(3×0.10)+(9×0.05) = 7.25 / 10` (unchanged).

B's 2026-04-22 status note at the top of its synthesis is load-bearing here: the delta-synthesis's "invalidated" claim was itself invalidated by the NR reversal, so B's original score is preserved.

### Proposal C — Camera-Worker Fleet

| Dimension | 2026-04-16 | 2026-04-22 | Delta + rationale |
|-----------|-----------:|-----------:|-------------------|
| Independent scalability (35%) | 6 | 6 | No change. |
| Cost reduction (20%) | 10 | 10 | No change. Already at the top bracket; CE data confirms the mechanism (no frame transport = zero cross-AZ data-transfer contribution + minimal Redis footprint). Adopting the conditional-promotion delta is additive (~$4.7k/mo) but already absorbed in the 10/10 ceiling. Do not double-count. |
| Failure isolation (15%) | 8 | 8 | No change. |
| Operational simplicity (15%) | 7 | 7 | No change. Fleet-coordinator unification would push this to 8, but only if the design-review question resolves affirmatively. |
| Migration risk (10%) | 6 | 6 | No change. WireGuard/tunnel blocker persists independently of CE data. |
| Failover quality (5%) | 9 | 9 | No change. |

Weighted 2026-04-22: `(6×0.35)+(10×0.20)+(8×0.15)+(7×0.15)+(6×0.10)+(9×0.05) = 7.40 / 10` (unchanged).

C's position is *reinforced* by the CE data rather than re-scored. The CE pull confirms that the cost structure C was designed against (API calls + data transfer + storage proportions) is real; C's design avoids two of the three at the architectural level. The score doesn't move but the confidence in C's cost story is materially higher than it was on 2026-04-16.

### Proposal D — Event-Driven Pipeline

| Dimension | 2026-04-16 | 2026-04-22 | Delta + rationale |
|-----------|-----------:|-----------:|-------------------|
| Independent scalability (35%) | 10 | 10 | No change. |
| Cost reduction (20%) | 6 | 7 | +1. D's motion-gating-at-puller (FDMD dropping 60-80% of raw frames) is the dominant cost lever. The CE data confirms the mechanism's leverage: 62.7% request-cost + 35.2% storage = 97.9% of S3 cost is frame-driven. Under D's 70%-drop assumption, the $33k/mo baseline contracts to roughly $16-20k/mo — a −40 to −50% reduction, putting D in the 8+ bracket. However, D still pays for its own JetStream + S3 Express + MinIO deployment, and the delta-synthesis's "JetStream-as-blob" alternative wasn't in the 2026-04-16 scoring. Net: +1 bracket move, from −10% projected to −15 to −25% projected. |
| Failure isolation (15%) | 8 | 8 | No change. MinIO SPOF story unchanged. |
| Operational simplicity (15%) | 2 | 2 | No change. NATS + S3 Express + tracing + filter-chain-split stays heavy. |
| Migration risk (10%) | 2 | 2 | No change. |
| Failover quality (5%) | 9 | 9 | No change. |

Weighted 2026-04-22: `(10×0.35)+(7×0.20)+(8×0.15)+(2×0.15)+(2×0.10)+(9×0.05) = 7.05 / 10` (vs 6.85).

### Proposal E — Hybrid Sidecar

| Dimension | 2026-04-16 | 2026-04-22 | Delta + rationale |
|-----------|-----------:|-----------:|-------------------|
| Independent scalability (35%) | 8 | 8 | No change. |
| Cost reduction (20%) | 10 | 10 | No change. Already at top bracket. The CE data confirms E's thesis: motion-gating at the puller is the dominant lever, and conditional-promotion stacks on top. E claimed −20 to −40% pre-CE; CE data supports that range (FDMD 70% drop → ~$16-20k/mo S3 savings + Spot viability on pullers + VPA bimodal fix). Do not double-count the conditional-promotion delta here; it's already in the 10/10. |
| Failure isolation (15%) | 8 | 8 | No change. |
| Operational simplicity (15%) | 6 | 6 | No change. Fleet-coordinator unification would push this to 7. |
| Migration risk (10%) | 7 | 7 | No change. |
| Failover quality (5%) | 9 | 9 | No change. |

Weighted 2026-04-22: `(8×0.35)+(10×0.20)+(8×0.15)+(6×0.15)+(7×0.10)+(9×0.05) = 8.05 / 10` (unchanged).

E's lead is **preserved and better-supported** post-CE. The 2026-04-16 cost-axis 10/10 was on projection; the CE data provides the first real-dollar validation of the mechanism E depends on.

### Proposal B-prime (CLOSED, for reference)

| Dimension | 2026-04-22 | Notes |
|-----------|-----------:|-------|
| Independent scalability (35%) | 9 | From B-prime synthesis |
| Cost reduction (20%) | 7 | Coordinator + On-Demand motion offset gains |
| Failure isolation (15%) | 7 | Tmpfs node-loss gap |
| Operational simplicity (15%) | 2 | Worst in family |
| Migration risk (10%) | 2 | 28-36 weeks |
| Failover quality (5%) | 7 | Node-loss blob-loss unique to B-prime |

Weighted: **6.25 / 10**, formally closed per `[[2026-04-22_proposal-b-prime-stateless-with-coordinator]]` CLOSEOUT banner. Reference only.

## Headline ranking

| Rank | Proposal | 2026-04-16 | 2026-04-22 | Δ | Status |
|-----:|----------|-----------:|-----------:|--:|--------|
| 1 | **E — Hybrid Sidecar** | 8.05 | **8.05** | 0 | **Top contender** |
| 2 | **C — Camera-Worker Fleet** | 7.40 | **7.40** | 0 | **Contender / runner-up** |
| 3 | B — Stage Fleets | 7.25 | **7.25** | 0 | Contender (operationally complex) |
| 4 | D — Event-Driven | 6.85 | **7.05** | +0.20 | Contender (ops-simplicity drag) |
| 5 | A — Minimal Split | 4.25 | **4.45** | +0.20 | Fallback |
| — | B-prime | — | 6.25 | — | **CLOSED** (reference) |
| — | Today's baseline | 3.20 | — | — | Floor |

All five in-play proposals still beat today's 3.20 baseline. The top-to-bottom spread is 4.45 → 8.05 (3.60 points), and the top cluster (E, C, B) is within 0.80 points — PoC selection matters more than re-scoring precision at this stage.

## What changed vs 2026-04-16

- **E's lead: unchanged in magnitude, better supported in provenance.** 2026-04-16 had E at 8.05 based on projections. 2026-04-22 has E at 8.05 with the cost-reduction axis now anchored in real CE data. The lead over #2 (C) is 0.65 weighted — the same gap, but no longer vulnerable to "the cost projection was wishful."
- **C: mildly reinforced by CE data.** Zero-hot-path-frame-transport avoids two of the three cost drivers (requests and data transfer). Storage remains the axis where C's in-process buffering + conditional-promotion matters, and the delta adoption is "Natural fit" per the delta synthesis. Score unchanged, confidence up.
- **D: score up +0.20** because the motion-gating mechanism (which D already had) is now validated by CE data as a dominant lever. D would rank higher in a pure-cost world, but ops-simplicity 2/10 and migration risk 2/10 keep it behind C and B.
- **B: unchanged.** The delta synthesis's "B is invalidated" claim was itself invalidated by the NR correction. B's 7.25 stands. B remains valid-but-operationally-complex; it competes with C on composite but loses on cost-axis.
- **A: score up +0.20** from conditional-promotion adoption. A is still deep in fallback territory — the +0.20 is bracket-level precision, not a change in strategic role.
- **B-prime: closed** at 6.25. Included only as a reference row; re-examination trigger is "E PoC fails on motion-filter drop rate <50% or detection-core StatefulSet ops load."

The **fleet-coordinator unification question** is not reflected in any score, but if resolved affirmatively at design review, it would add +0.15 weighted to both C and E on the ops-simplicity axis — tightening the gap between C and E from 0.65 to the same 0.65 (both move together), but improving each proposal's absolute ops story.

## Recommended PoC selection

**First PoC: [[2026-04-16_proposal-e-hybrid-sidecar|Proposal E — Hybrid Sidecar]].** E leads on composite (8.05), leads on cost reduction (top bracket, now with CE-data support), directly addresses three known ENG pain points (ENG-78 VPA bimodal, ENG-96 schedule-eval, ENG-66 alert thundering herd), keeps the battle-tested pipeline core intact, and its central unknowns (FDMD drop rate, detection-core StatefulSet ops burden) are load-bearing for the cost case and measurable in a 2-3 week PoC.

**Runner-up PoC: [[2026-04-16_proposal-c-camera-worker|Proposal C — Camera-Worker Fleet]].** C runs second on composite (7.40), wins cleanly on cost (tied 10/10 with E but via a structurally different mechanism — no frame transport vs motion-gating), fixes ENG-96 by design via the Assignment Controller, and has the lowest operational-component count of any ambitious proposal. C has an unresolved blocker — WireGuard/tunnel routing across workers — that is independent of the fleet-coordinator question and must be resolved during the `kubernetes-deployments` deep dive before PoC.

**Invalidation criteria that would flip the recommendation:**

- E's FDMD drop rate PoC measures <50% → cost case collapses, E drops to roughly C's level. Flip to C as primary.
- C's tunnel-routing story becomes a hard blocker (>30% of sites incompatible with universal worker assignment) → flip to E as primary unconditionally; consider B as fallback-contender despite its ops complexity.
- [[pyav-entity|PyAV]] in-process encode exceeds GIL budget in either PoC → the conditional-promotion delta becomes unreachable for that proposal; the ~$4.7k/mo conditional-promotion win drops out of that proposal's cost story, which materially affects only D (D's baseline was worst so the delta's absolute reduction is biggest) and A (where the delta is A's primary cost story).

## Open questions before PoC

1. **Motion-gate drop-rate real-world validation (load-bearing for D/E).** Proposals D and E both assume FDMD drops 60-80% of raw frames. The CE data confirms this is where the cost leverage sits, but we don't have a fleet-wide measurement of what FDMD actually drops in production today. An NR query against FDMD emit rates vs puller capture rates would close this; if the real drop is 40-50% rather than 60-80%, the cost case for both D and E softens by 20-40%.
2. **Fleet-coordinator unification resolution.** Could reshape C/E ops-simplicity scoring by +1 each. API-sketch design-review targets `topics/fleet-architecture/notes/syntheses/2026-04-XX_fleet-coordinator-api-sketch.md` per the concept note's tracked next steps. If pursued, do it before PoC — the coordinator is a shared primitive in both candidates' designs and building it twice is the waste the unification question is trying to prevent.
3. **Tier3 replication/lifecycle cost driver ($44k/year).** Independent of any proposal. A 1-hour analyst investigation into *why* 72.9M replication requests fire on a 65 TB working set could yield a pre-PoC cost win that applies regardless of which proposal lands. Candidates: inappropriate cross-region replication, lifecycle transitions on already-deleted objects, drifted replication policies. Worth closing before PoC so the cost baseline the PoC is measured against reflects a cleaned-up steady state.
4. **WireGuard/tunnel story for C.** Pre-existing blocker from the 2026-04-16 C synthesis §"Site connectivity." Gated on `kubernetes-deployments` deep dive. If >20% of sites use WireGuard and universal-worker routing is infeasible, C needs a pre-PoC redesign (likely toward "assignment constrained by tunnel class," which erodes bin-packing).
5. **`/create-video` retirement path (post-PoC).** All delta-adopting proposals retire the Lambda. The cross-team conversation is gated on proposal selection but should be flagged now so [[alert-ui|Alert-UI]] / Immix / [[watchman-repo|Watchman]] owners aren't surprised.
6. **`SlidingWindowStep.close_window` outcome instrumentation (~5 LoC).** Not a blocker but a hygiene item. Adds a structured INFO log `window_outcome=detection_positive|no_detection` that makes the non-eventful ratio a first-class queryable signal and prevents the proxy-hunting that caused the original NR mistake.

## Addendum (2026-04-22 evening) — Cost-axis refinements

Two refinements landed after the main re-score was written and deserve explicit incorporation rather than a follow-up re-score pass. Both tighten the cost-axis scoring; one shifts the ranking modestly, the other reframes where leverage lives. Written directly in the main session after subagent quota was hit (resets 2026-04-22T14:00 America/New_York); kept tight.

### Refinement 1 — Top-services landscape reframes leverage ceilings

From `/cost-check --top-services --days 30` run 2026-04-22:

| Service | 30d | Annual | % of total |
|---------|------:|-------:|-----:|
| **EC2 compute** | **$121,715** | **~$1,461,000** | **55.4%** |
| S3 | $32,821 | ~$394,000 | 14.9% |
| DynamoDB | $18,220 | ~$219,000 | 8.3% |
| EC2-Other (EBS/NAT/etc.) | $16,147 | ~$194,000 | 7.3% |
| ECS | $5,662 | ~$68,000 | 2.6% |
| VPC / RDS / Config / CW / ELB / etc. | $22,499 | ~$270,000 | 10.3% |
| AWS Config (surprise) | $3,719 | ~$45,000 | 1.7% |
| **TOTAL FLEET CLOUD** | **$219,854** | **~$2,674,000** | **100%** |

**Load-bearing reframe:** the main re-score's cost-axis reasoning was S3-centric. **S3 is only 14.9% of total cloud spend — absolute savings ceiling is ~$400k/year.** Compute dominates at 55.4% / ~$1.46M/year. Any proposal whose design reduces compute (pool consolidation, [[sharding]] elimination, right-sizing per stage) has a leverage ceiling **~3.7× larger than any S3-only optimization can reach**.

Per-proposal consequence:

- **C** benefits structurally: "one [[inference-pool|inference pool]] per worker" is a pool-count reduction (from ~1 pool per site-pod to 1 pool per bin-packed worker serving 30–50 cameras). This is a compute-side lever the S3-focused re-score didn't explicitly credit. **C's cost-axis already sits at 10/10 (ceiling), so the effect is *confidence up*, not score up.** Noted for readers.
- **E** benefits structurally: camera-group-scoped pools + FDMD-at-puller compose motion-gating with pool consolidation. Same ceiling effect — E is already at cost-axis 10/10 in the main re-score, the reframe reinforces but can't lift.
- **D** benefits from motion-gating reducing downstream inference compute (fewer frames flow past FDMD → fewer inference calls → smaller inference-coord fleet). Not in the main re-score's 6→7 move. Partial offset below.
- **A, B** — neither touches compute meaningfully. No change from this refinement.

### Refinement 2 — Motion-gate drop-rate at conservative 40–50% (user decision 2026-04-22)

The main re-score baked in FDMD drop rates of 60–80% per the 2026-04-16 proposal syntheses. User decision 2026-04-22: **rescore with the conservative 40–50% range pending empirical validation.** Midpoint 45%.

Math. At 70% drop (original optimistic), motion-gating was projected to eliminate ~98% of S3 frame-driven workload ≈ ~$16–20k/mo S3 savings on the $33k/mo baseline. At 45% drop, savings scale proportionally: ~$10–13k/mo S3 savings. Still material but ~35% smaller than optimistic. Cost-axis bracket impact: D moves from "roughly −15%" back toward "roughly −5 to −10%" (one bracket down); E's 10/10 ceiling becomes threatened (E's −20 to −40% projection rested on 70% drop; at 45% it's closer to −12 to −22% — still good but no longer in the ≤−30% top bracket).

### Per-proposal axis adjustment

| Proposal | 2026-04-16 cost | 2026-04-22 main cost | **Addendum cost** | Rationale |
|----------|---:|---:|---:|-----------|
| A | 3 | 4 | **4** | Unchanged. Conditional-promotion delta doesn't depend on motion-gate. |
| B | 6 | 6 | **6** | Unchanged. B doesn't motion-gate today. |
| C | 10 | 10 | **10** | Ceiling preserved. Compute-side reframe adds confidence, not score. C's cost story is **robust to motion-gate uncertainty** — it doesn't depend on FDMD. |
| D | 6 | 7 | **6** | **Back down to 6.** 45% drop softens the main re-score's +1 bump. D's S3 savings drop from ~$200k/year to ~$130k/year under conservative assumption. |
| E | 10 | 10 | **9** | **Down 1 from ceiling.** 45% drop brings E's total cost reduction from −20 to −40% projected (needs ≤−30% for 10) down to −12 to −22% projected. Compute-side leverage from camera-group pools offsets modestly. Net: 9. |

### Recomputed weighted totals

| Proposal | 2026-04-16 | 2026-04-22 main | **Addendum** | Δ from main |
|----------|------:|------:|------:|------:|
| **E — Hybrid Sidecar** | 8.05 | 8.05 | **7.85** | **−0.20** |
| C — Camera-Worker | 7.40 | 7.40 | **7.40** | 0 |
| B — Stage Fleets | 7.25 | 7.25 | **7.25** | 0 |
| D — Event-Driven | 6.85 | 7.05 | **6.85** | **−0.20** |
| A — Minimal Split | 4.25 | 4.45 | **4.45** | 0 |
| B-prime (CLOSED) | — | 6.25 | 6.25 | — |

Calculation for E: `(8×0.35)+(9×0.20)+(8×0.15)+(6×0.15)+(7×0.10)+(9×0.05) = 2.80+1.80+1.20+0.90+0.70+0.45 = 7.85`. Calculation for D: `(10×0.35)+(6×0.20)+(8×0.15)+(2×0.15)+(2×0.10)+(9×0.05) = 3.50+1.20+1.20+0.30+0.20+0.45 = 6.85`.

### Final ranking after addendum

| Rank | Proposal | 2026-04-16 | 2026-04-22 main | Addendum | Status |
|-----:|----------|------:|------:|------:|--------|
| 1 | **E — Hybrid Sidecar** | 8.05 | 8.05 | **7.85** | **Top contender (narrower lead)** |
| 2 | **C — Camera-Worker** | 7.40 | 7.40 | **7.40** | **Contender (relatively stronger)** |
| 3 | B — Stage Fleets | 7.25 | 7.25 | **7.25** | Contender (ops-complex) |
| 4 | D — Event-Driven | 6.85 | 7.05 | **6.85** | Contender (ops-complex) |
| 5 | A — Minimal Split | 4.25 | 4.45 | **4.45** | Fallback |
| — | B-prime | — | 6.25 | 6.25 | **CLOSED** |

E's lead over C narrows from **0.65 → 0.45**. Ranking order unchanged (E still first), but the gap is now small enough that the fleet-coordinator sketch + PoC measurements will determine the final pick, not the re-scoring precision.

### Conditional scenario — if fleet-coordinator unification resolves affirmative

The API-sketch design-review has been committed to run **before PoC** (user decision 2026-04-22). If that sketch concludes unification is viable, C and E both gain **+1 on operational-simplicity (+0.15 weighted each)**:

| Proposal | Addendum | **+ coord unification** | Δ |
|----------|------:|------:|------:|
| E | 7.85 | **8.00** | +0.15 |
| C | 7.40 | **7.55** | +0.15 |

Both move together; E retains its 0.45 lead. Absolute ops-simplicity story improves for both. The conditional scenario doesn't reshape PoC selection — it tightens the confidence on both candidates.

**Strategic note:** under the conservative motion-gate assumption, **C is the more robust choice if FDMD disappoints in E's PoC.** C's cost story doesn't rest on motion-gating at all — it comes from zero frame transport + pool consolidation. If E's PoC measures FDMD drop <40%, E's cost-axis collapses further (below 9), and C overtakes on composite. Flagged for PoC-go/no-go criteria.

### Net effect on PoC recommendation

**Recommendation preserved: PoC-1 is E, PoC-2 is C.** The conservative refinement doesn't flip the ranking — E still leads. But the lead is thinner (0.45 vs 0.65), and C's relative position is stronger on *robustness*. Two updates to the main re-score's invalidation criteria:

1. **E's FDMD drop-rate PoC result is now more load-bearing.** If measured drop is <40%, E's cost-axis likely falls below C's effective ceiling. Flip trigger: measured FDMD drop <40% in E's PoC → flip primary to C unconditionally.
2. **Fleet-coordinator sketch outcome directly shapes PoC-2 (C).** If unification resolves viable, C's Assignment Controller gets built from the shared primitive rather than as a C-specific service. If unification is rejected, C builds its controller standalone. Either way the sketch runs before PoC, per the user decision.

## Related

- `[[2026-04-16_evaluation-rubric]]` — scoring framework
- `[[2026-04-16_proposal-a-minimal-split]]`
- `[[2026-04-16_proposal-b-stage-fleets]]` (note 2026-04-22 status banner)
- `[[2026-04-16_proposal-c-camera-worker]]`
- `[[2026-04-16_proposal-d-event-driven]]`
- `[[2026-04-16_proposal-e-hybrid-sidecar]]`
- `[[2026-04-22_proposal-b-prime-stateless-with-coordinator]]` — CLOSED
- `[[2026-04-22_frame-storage-design-deltas]]` — AMENDMENT banner is load-bearing
- `[[fleet-coordinator-unification-question]]` — open structural question
- `[[2026-04-16_frame-transport-comparison]]`
- `[[2026-04-16_graceful-failover-design]]`
- `[[frame-storage-current-state]]`
- `topics/personal-notes/notes/entities/mark-todos.md` §5 — fleet-architecture workstream tracking
