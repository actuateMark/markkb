---
title: "Rubric extension — Monitoring & Alarms + Billing & Reconciliation dimensions, 5-proposal rescore (2026-05-11)"
type: synthesis
topic: fleet-architecture
tags: [evaluation, rubric, scoring, monitoring, billing, reconciliation, fleet, rescore, handoff-4]
created: 2026-05-11
updated: 2026-05-11
author: kb-bot
---

# Rubric extension — Monitoring & Alarms + Billing & Reconciliation

Closes [[2026-05-11_billing-and-followups-handoff]] item **#4**. Adds two dimensions to [[2026-04-16_evaluation-rubric]] that were promised in the 2026-04-23 `_summary` update but never landed, and rescores the 5 in-play proposals (A, B, C, D, E) against them.

The two dimensions are now relevant because:

1. **Monitoring & Alarms** — the [[2026-04-30_three-tier-routine-check-pattern|three-tier routine-check pattern]] and the operational-dashboard expansion (§9 in [[mark-todos]]) have raised the cost of architectures that defer behavioral observability. Any fleet redesign needs to articulate **what behavioral signals prove it works in prod** before PoC results gate selection.
2. **Billing & Reconciliation** — the [[2026-05-11_billing-pain-post-mortem|April-May 2026 billing firefight]] revealed that emit-site multiplicity is a structural failure mode. A fleet redesign that moves billing emission across pod-class boundaries creates new emit-gap risk. The [[2026-05-11_billing-reconciliation-dashboard-design|R1 reconciliation design]] (now deployed as Tier-1 via [[2026-05-11_nf2-deployment-state|NF2]]) operationalizes detection — but the structural choice of *where to emit* sits with the fleet shape.

This synthesis is the source-of-truth for "did the rubric extension land." [[2026-04-22_fleet-proposal-rescore-with-delta]] remains valid for the original 6 dimensions; this note replaces its **headline ranking** with the new 8-dimension version.

## Weight reallocation

Per the handoff's proposal — free 10pp by trimming the three highest-weighted dimensions proportionally, add 5pp each for the two new dimensions:

| Dimension | 2026-04-22 weight | **2026-05-11 weight** | Δ | Why |
|-----------|------------------:|----------------------:|---:|-----|
| Independent scalability | 35% | **30%** | −5 | Still primary, but billing pipeline is the other "doesn't-work-quietly" risk class. |
| Cost reduction | 20% | **17.5%** | −2.5 | Real-dollar CE data anchors this; less projection-driven than at the rubric's birth. |
| Failure isolation | 15% | **12.5%** | −2.5 | Still material; the new monitoring axis partially overlaps (a well-monitored failure is half-isolated). |
| Operational simplicity | 15% | **15%** | 0 | Hot-button axis; deliberately untouched. |
| Migration risk | 10% | **10%** | 0 | Time-bounded; unchanged. |
| Failover quality | 5% | **5%** | 0 | Already minor. |
| **Monitoring & Alarms (NEW)** | — | **5%** | +5 | Required: what signals prove this works in prod, what's on the dashboard, what gates rollout. |
| **Billing & Reconciliation (NEW)** | — | **5%** | +5 | Required: how emit invariants survive the restructure, what new emit sites land, how reconciliation maps in the new shape. |
| **Total** | **100%** | **100%** | 0 | |

The 10pp comes proportionally from the three heaviest dimensions. None of the unchanged dimensions stay at higher weight than they "earned" via load-bearing evidence in [[2026-04-22_fleet-proposal-rescore-with-delta]].

**Alternative considered, not adopted:** weighting both new dimensions at 7.5% (15pp combined). Rejected — would have required cutting `Operational simplicity` or `Migration risk`, both of which carry team-blood-and-tears weight beyond their raw rubric percentage. 5% each is the floor at which the dimensions are *consulted* without becoming margin-determining.

## Dimension 7 — Monitoring & Alarms (5%)

**What it scores:** for each proposal, *what behavioral signals prove the redesigned pipeline is working in production*, what those signals look like in [[/dashboard-check|the operational dashboard]] or analogous surface, and what acceptance criteria gate rollout. This is **observability of intent**, not infra metrics (CPU, memory, queue depth) which are already implicit in `Operational simplicity`.

| Score | Criterion |
|-------|-----------|
| 10 | Per-stage behavioral signals exist as named NRQL or dashboard entries; rollout is gated on specific signal SLOs; failure modes are linked to known signals 1:1 |
| 7-9 | 80%+ of failure modes mapped to behavioral signals; some signals require new instrumentation but the design names them |
| 4-6 | Most failure modes have *infrastructure* signals (queue depth, error rate) but few *behavioral* signals (right thing happening to the right cameras) |
| 1-3 | Monitoring story is "add NR alerts in flight"; failure modes detected reactively |
| 0 | No monitoring story; relies on customer complaints |

Today's baseline scores ~4: we have infra signals but the cohort-F class (silent-but-running cronjobs) showed that behavioral observability was nearly absent. [[2026-04-30_three-tier-routine-check-pattern]] has been raising this; the rubric should now reflect it.

## Dimension 8 — Billing & Reconciliation (5%)

**What it scores:** how the proposal preserves the **`site_product_ended` emission invariant** (every camera-product run leaves a billing trace) across the restructure. Where does emission live? Does the proposal increase or decrease emit-site multiplicity? Is the [[2026-05-11_billing-reconciliation-dashboard-design|R1 reconciliation]] signal still meaningful in the new shape, or does it need rework?

| Score | Criterion |
|-------|-----------|
| 10 | Emission stays in one shared module; reconciliation maps 1:1 to current Postgres↔SPRD anti-join; zero new emit sites; idempotency guard reachable on every exit path |
| 7-9 | Emission lives in 1-2 places; reconciliation needs at most a join-key tweak; new emit sites identified and updated in [[billing-events-catalog]] |
| 4-6 | Emission scatters across 3+ services or pod classes; reconciliation requires non-trivial new queries; crash-path emit needs new design |
| 1-3 | Emission boundary unclear; reconciliation contract not in design; high risk of new silent-leak class |
| 0 | Billing not addressed in proposal; structural emission gaps likely |

Today's baseline scores ~6: emission is in one module (`connector_factories/shared/billing_emit.py`) but the crash-path gap is open ([[autopatrol-deferred-backlog]] "Billing emit on crash"). [[billing-events-catalog]] is the authority any redesign must update.

## Per-proposal scores on the two new dimensions

### Proposal A — Minimal Split

| Dim | Score | Rationale |
|---|---:|---|
| Monitoring & Alarms | **7** | The pipeline is still site-pod with one internal split. Behavioral signals are mostly today's — minor new ones for the puller/processor seam. The split surfaces one new signal class (puller-vs-processor health divergence) and exposes existing failure modes more cleanly. Easy to map. |
| Billing & Reconciliation | **9** | Pipeline still site-pod. Billing emit stays exactly where it is today (`billing_emit.py`). The split is *internal* to the pod, doesn't cross pod-class boundaries. Reconciliation R1/NF2 works unchanged. The only reason this isn't 10 is the open crash-path gap is unchanged — A doesn't make it worse, but doesn't fix it. |

### Proposal B — Stage Fleets

| Dim | Score | Rationale |
|---|---:|---|
| Monitoring & Alarms | **6** | Four separate stage pools = four separate KEDA targets, four separate failure modes, four separate "is this stage healthy" signal sets. **Comprehensive observability surface** but high signal load — each cross-stage failure manifests as a queue backup, requiring new "is the consumer the bottleneck or the producer" disambiguation signals. Rich, but operationally heavy to monitor cleanly. |
| Billing & Reconciliation | **4** | **Largest emit-site risk class of any in-play proposal.** Frame events traverse 4 Redis Streams hops; billing emission has to live somewhere specific. If emission moves to the last hop (alert stage), what happens if hops 1-3 succeed but hop 4 dies before emit? New crash-class. Reconciliation against `usage_monthly` needs new join logic if billing emit is keyed by `alert_pod_id` rather than `camera_id`. Significant design work. |

### Proposal C — Camera-Worker Fleet

| Dim | Score | Rationale |
|---|---:|---|
| Monitoring & Alarms | **7** | Worker pool + Assignment Controller. Three pod classes (worker, controller, scheduler-ish). Worker death = camera reassignment — observable as "camera bin re-balance event." Controller health is a single named signal. Bin-packing health (overcommit, hot workers) is a new behavioral signal class. Moderate surface. |
| Billing & Reconciliation | **8** | Each worker owns a camera bin and is the natural per-camera-per-run emission site. Emission stays in one place per worker (still `billing_emit.py`). Reconciliation maps cleanly: PG cameras → assigned-worker → worker emits → SPRD aggregates. The Assignment Controller is the natural place to validate the "every active camera has exactly one owning worker" invariant — adds defense-in-depth. -2 from 10 because worker churn means in-flight emits could race the reassignment; needs idempotency-by-`(camera, run_id)` not `(camera, worker_id)`. Tractable. |

### Proposal D — Event-Driven Pipeline

| Dim | Score | Rationale |
|---|---:|---|
| Monitoring & Alarms | **4** | JetStream consumer-group health, S3 Express PUT rates, MinIO health, filter-chain split = many distinct surfaces. Each new component is a new monitoring lift. JetStream has its own observability story (separate from K8s). MinIO is single-point-of-failure-class. Heaviest monitoring load of any proposal — that's why D's operational-simplicity score is 2. |
| Billing & Reconciliation | **4** | Frame events flow through JetStream + S3 Express. Where does billing emission live? Likely at the filter-chain output stage, but the filter chain is split across pods. New design work to pin: which pod is the canonical emitter? What's the crash semantics if a filter pod dies mid-window? D's event-driven nature inherently fragments the emit responsibility. Reconciliation requires new queries against JetStream consumer-lag metrics, not against the Postgres-SPRD anti-join NF2 implements. Significant rework. |

### Proposal E — Hybrid Sidecar

| Dim | Score | Rationale |
|---|---:|---|
| Monitoring & Alarms | **7** | Sidecar + core-pod = 2 distinct services per site. FDMD drop rate is **already an explicit dashboard signal in E's design** — load-bearing for the cost case (must be measurable to gate rollout). Site Context Service health is a named signal. Sidecar↔core-pod split surfaces "filtered frames making it through" as a behavioral check. Cohort-F-class detection (silent-but-running) maps to "site claims active, sidecar emits no frames" — a clean signal. Slightly less rich than C's bin-packing signal class, but covers all the named failure modes. |
| Billing & Reconciliation | **8** | Emission per-camera-per-run lives in the core-pod (which is roughly per-site or per-camera-group). Stays in `billing_emit.py`. Reconciliation R1/NF2 works structurally unchanged — the PG→SPRD anti-join doesn't care whether the events came from site-pod-monoliths or core-pods. Site Context Service is the natural place to enforce the "every active camera has a core-pod emitting" invariant. -2 from 10 because the sidecar adds a new pre-emission stage (FDMD-filtered frames never reach core-pod for non-eventful windows) — need to decide whether the sidecar can emit a "ran clean, no events" billing beacon for billing purposes (touches the [[autopatrol-deferred-backlog|crash-path gap]] / `_started` resurrection question). Tractable. |

## Recomputed composite scores

Using addendum scores from [[2026-04-22_fleet-proposal-rescore-with-delta]] for the original 6 dimensions, the new scores above for the 2 new dimensions, and the new weights.

| Proposal | IS (30%) | Cost (17.5%) | FI (12.5%) | OS (15%) | MR (10%) | FQ (5%) | **M&A (5%)** | **B&R (5%)** | **Composite** |
|----------|---------:|-------------:|-----------:|---------:|---------:|--------:|-------------:|-------------:|--------------:|
| A | 3 | 4 | 4 | 6 | 9 | 4 | 7 | 9 | **4.90** |
| B | 10 | 6 | 9 | 3 | 3 | 9 | 6 | 4 | **6.875** |
| C | 6 | 10 | 8 | 7 | 6 | 9 | 7 | 8 | **7.40** |
| D | 10 | 6 | 8 | 2 | 2 | 9 | 4 | 4 | **6.40** |
| E | 8 | 9 | 8 | 6 | 7 | 9 | 7 | 8 | **7.775** |

Sample calculation for E: `(8×0.30)+(9×0.175)+(8×0.125)+(6×0.15)+(7×0.10)+(9×0.05)+(7×0.05)+(8×0.05) = 2.40+1.575+1.00+0.90+0.70+0.45+0.35+0.40 = 7.775`.

## Headline ranking

| Rank | Proposal | 2026-04-22 addendum | **2026-05-11 (8 dims)** | Δ | Status |
|-----:|----------|--------------------:|------------------------:|--:|--------|
| 1 | **E — Hybrid Sidecar** | 7.85 | **7.775** | −0.075 | **Top contender, lead narrows further** |
| 2 | **C — Camera-Worker Fleet** | 7.40 | **7.40** | 0 | **Runner-up, position unchanged** |
| 3 | B — Stage Fleets | 7.25 | **6.875** | **−0.375** | Contender, biggest drop on rescore |
| 4 | D — Event-Driven | 6.85 | **6.40** | −0.45 | Contender, ops-burden compounds |
| 5 | A — Minimal Split | 4.45 | **4.90** | **+0.45** | Fallback, but biggest gainer |
| — | B-prime | 6.25 | — | — | CLOSED, not rescored |
| — | Today's baseline | 3.20 | (recompute below) | — | Floor |

**Recomputed baseline** (today's site-pod monolith, scored against the 8 dimensions):
- IS 0, Cost 4, FI 0, OS 8, MR 10, FQ 4, M&A 4, B&R 6
- `(0×0.30)+(4×0.175)+(0×0.125)+(8×0.15)+(10×0.10)+(4×0.05)+(4×0.05)+(6×0.05) = 0+0.70+0+1.20+1.00+0.20+0.20+0.30 = 3.60`
- Baseline moves from 3.20 → 3.60 because the 8-dim view credits the existing pipeline modestly on the two new axes (we *do* have some monitoring and our billing surface *is* in roughly one place, even if the crash-path gap is real).

## What changed in the ranking

- **E still leads. Lead over C narrows further** — was 0.65 at original rubric, 0.45 at the 2026-04-22 addendum, **0.375 now**. E and C are within 1 PoC measurement of each other.
- **C is the most rubric-robust proposal in the set.** Its score didn't move at any rescoring step (10 → 10 → 10 on cost ceiling-bound; 7 → 7 on ops-simplicity unchanged; 8 on B&R) because C's design happens to score well on the new dimensions too. Camera-worker bin-packing is a clean monitoring story; per-worker emission is a clean billing story.
- **B drops 0.375 from rescore.** Two compounding factors: (1) the 4-hop topology hurts B&R (4 → score), (2) reducing the IS weight from 35% to 30% partially erases B's 10/10 there. B's structural complexity in monitoring (4 stage fleets to observe individually) wasn't credited as a positive in 2026-04-22's score; the M&A dim flags it now.
- **D drops 0.45.** Same IS-weight effect as B (D also scored 10 on IS), plus D scores poorly on both new dimensions (4/4) — heaviest monitoring lift, most fragmented emission.
- **A gains 0.45.** A's "minimal split" structure preserves billing emit cleanly (9 — the highest B&R score) and offers an easy monitoring story (7). A's primary weakness remains IS (3) — the weight cut from 35% to 30% reduces the penalty marginally.

**B-prime (CLOSED) not rescored** — wasn't a candidate after 2026-04-22 closeout.

## Implications for PoC selection

The 2026-04-22 recommendation **stands unchanged: PoC-1 is E, PoC-2 is C.** Two refinements from this rescore:

1. **E's lead is now thin enough that a single PoC failure flips the ordering.** Specifically, if E's FDMD drop rate measures <40%, E's Cost score falls below 9, and C overtakes on composite. The conservative-motion-gate addendum already flagged this; the rubric extension makes it a 0.1-pt margin instead of a 0.4-pt margin.
2. **C's relative robustness on the new dimensions is a tiebreaker if PoC results are close.** C scores 7/8 on monitoring/billing; E scores 7/8. They tie on the new dimensions — but C's existing-dimension scores are anchored in different mechanisms (no frame transport vs motion-gating) that don't share PoC risk. If both PoCs land successfully, C is the lower-risk pick under the new rubric.

**Invalidation criteria updated:**

- E PoC measures FDMD drop <40% → E composite drops below 7.4; **flip to C as primary** (already in 2026-04-22 invalidation list, threshold sharpened).
- E PoC reveals new emit-site fragmentation we hadn't designed for (e.g., sidecar billing emission is structurally awkward) → E's B&R score drops from 8 to ~5; **E composite drops to ~7.6 (still leads C marginally)**. Re-examine billing fitness function for E specifically before PoC if this risk is open.
- C PoC reveals worker-reassignment-during-emit race condition that can't be cleanly idempotency-guarded → C's B&R drops from 8 to ~5; C composite drops to ~7.25 (below B!). Unlikely but worth checking in PoC.

## Outstanding open questions

1. **Should `Operational simplicity` weight have been cut instead of `Independent scalability`?** The rubric's primary criterion is scalability, but in 2026-05 we've spent a lot of capital on ops-burden incidents. Counter: A's ops baseline today (where we are) is the comfortable case; the rubric is meant to evaluate departures from that. Cutting OS would penalize departures that improve ops, which is the wrong direction. Decision: leave OS at 15%. Document the consideration.
2. **Should `Migration risk` weight have been cut?** Could free 2.5pp without disturbing rubric tradition. Counter: the 2026-04-22 addendum specifically credits A and E with low migration risk; cutting MR would erase that signal. Decision: leave at 10%.
3. **Should `Monitoring & Alarms` and `Billing & Reconciliation` be 7.5% each instead of 5%?** Would require cutting OS or MR — see (1) and (2). Decision: 5% each is the floor that surfaces the dimension without making it the margin-determining axis. Revisit at PoC-results-time if either axis turns out to be PoC-discriminating.
4. **Do we re-baseline today's monolith on the new dimensions?** Done above. Baseline moves 3.20 → 3.60. Still well below every in-play proposal.

## Related

- [[2026-04-16_evaluation-rubric]] — original 6-dim rubric (still valid for dimension definitions 1-6)
- [[2026-04-22_fleet-proposal-rescore-with-delta]] — addendum scores used here as input
- [[2026-04-16_proposal-a-minimal-split]]
- [[2026-04-16_proposal-b-stage-fleets]]
- [[2026-04-16_proposal-c-camera-worker]]
- [[2026-04-16_proposal-d-event-driven]]
- [[2026-04-16_proposal-e-hybrid-sidecar]]
- [[2026-05-11_billing-pain-post-mortem]] — why Billing & Reconciliation is now a dimension
- [[2026-05-11_billing-reconciliation-dashboard-design]] / [[2026-05-11_nf2-deployment-state]] — operationalized reconciliation that the dimension scores compatibility with
- [[2026-04-30_three-tier-routine-check-pattern]] — why Monitoring & Alarms is now a dimension
- [[billing-events-catalog]] — emit-site authority any redesign must update
- [[2026-05-11_billing-and-followups-handoff]] §4 — handoff item this note closes
- [[mark-todos]] §5 — fleet workstream tracker
