---
title: "Evaluation Rubric — Fleet Architecture PoC Competition"
type: synthesis
topic: fleet-architecture
tags: [evaluation, rubric, scoring, poc, selection, fleet]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
incoming:
  - home/offboarding/2026-06-23_watchman-fleet-handoff-paolo-mike.md
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-a-minimal-split.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-b-stage-fleets.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-c-camera-worker.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-d-event-driven.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-e-hybrid-sidecar.md
  - topics/fleet-architecture/notes/syntheses/2026-04-17_preliminary-pilot-option.md
  - topics/fleet-architecture/notes/syntheses/2026-04-22_frame-storage-design-deltas.md
  - topics/fleet-architecture/notes/syntheses/2026-04-22_proposal-b-prime-stateless-with-coordinator.md
incoming_updated: 2026-06-25
---

# Evaluation Rubric

Scoring criteria for comparing the 5 candidate architectures after their targeted PoCs produce benchmark numbers. Weights reflect the interview priorities: **scalability primary, cost secondary, isolation and simplicity also material**.

## Weights

| Dimension | Weight | Rationale |
|-----------|-------:|-----------|
| Independent scalability | **35%** | Primary criterion — each stage should scale to its own bottleneck |
| Cost reduction | **20%** | Secondary — VPA fix and de-sharding are the big prizes |
| Failure isolation | **15%** | Blast radius on crash |
| Operational simplicity | **15%** | Ops burden, debuggability, new infra, on-call load |
| Migration risk | **10%** | Timeline, code churn, behavioral drift |
| Failover quality | **5%** | Tracker/window resume — partially covered by graceful-failover design |

Weights sum to 100. Scoring is 0-10 per dimension; weighted sum produces a composite score.

## Rubric per dimension

### 1. Independent scalability (35%)

| Score | Criterion |
|-------|-----------|
| 10 | Each of puller/inference/observer/alert scales independently via HPA or KEDA on its own signal |
| 7-9 | 3 of 4 stages scale independently; one stage bundled with another |
| 4-6 | 2 of 4 stages scale independently |
| 1-3 | Only 1 stage scales independently (puller + pipeline bundled) |
| 0 | Everything scales as a site-pod unit (today's model) |

### 2. Cost reduction (20%)

Measured as **projected cost delta vs today at 10× fleet size**:

| Score | Cost delta at 10× |
|-------|------------------|
| 10 | -30% or better |
| 8 | -10% to -30% |
| 6 | 0 to -10% (break-even) |
| 4 | 0 to +10% |
| 2 | +10% to +20% |
| 0 | >+20% |

PoC benchmark numbers feed directly into this.

### 3. Failure isolation (15%)

| Score | Criterion |
|-------|-----------|
| 10 | Any single pod crash affects ≤N cameras where N << site size, alerts keep flowing during pipeline failures |
| 7-9 | Pipeline crash affects a camera-group; alerts isolated |
| 4-6 | Pipeline crash affects a site's cameras; alerts isolated |
| 1-3 | Pipeline crash affects a site; alerts share fate |
| 0 | Single crash = whole site dark (today) |

### 4. Operational simplicity (15%)

| Score | Criterion |
|-------|-----------|
| 10 | No new infra; reuses existing SQS/S3/DynamoDB primitives |
| 7-9 | 1 new infra component (e.g., Redis cluster); debuggable via existing tooling |
| 4-6 | 2-3 new components; distributed tracing desirable but not mandatory |
| 1-3 | 3+ new components; distributed tracing mandatory |
| 0 | Requires a dedicated platform-ops FTE to run |

### 5. Migration risk (10%)

| Score | Criterion |
|-------|-----------|
| 10 | ≤12 weeks; behavior-preserving; incremental rollout via flag |
| 7-9 | 13-20 weeks; mostly behavior-preserving |
| 4-6 | 20-28 weeks; some behavior changes requiring customer comms |
| 1-3 | 28+ weeks; significant code rewrite |
| 0 | Cannot incrementally roll back |

### 6. Failover quality (5%)

| Score | Criterion |
|-------|-----------|
| 10 | RPO ≤1 s, RTO ≤5 s, verified in PoC chaos test |
| 7 | RPO ≤5 s, RTO ≤10 s |
| 4 | Today's behavior (2-30 s gap on pipeline restart) |
| 0 | Worse than today |

## Baseline: score today's architecture

Before PoCs exist, score the current site-per-pod monolith against the rubric. This validates the rubric and establishes a floor.

| Dimension | Score | Notes |
|-----------|------:|-------|
| Independent scalability | 0 | Everything scales as a site-pod unit |
| Cost reduction | 4 | VPA over-provisions; [[sharding]] overhead |
| Failure isolation | 0 | Site-pod crash = whole site dark |
| Operational simplicity | 8 | No new infra; one service type |
| Migration risk | 10 | Baseline — no migration cost at all |
| Failover quality | 4 | Today's behavior |

Weighted sum: `(0×0.35) + (4×0.20) + (0×0.15) + (8×0.15) + (10×0.10) + (4×0.05) = 3.20 / 10`

That's the bar to beat. Anything scoring near this is a regression in net utility despite novelty.

## Scoring process

1. Each proposal's synthesis note has a **"Open questions"** section listing what its PoC must answer to get defensible scores
2. After PoC, the proposal owner updates the synthesis with numbers
3. A separate `2026-04-XX_fleet-architecture-selection.md` synthesis applies the rubric to all 5, computes composite scores, and makes a recommendation
4. Selection is a team discussion — rubric provides the quantitative frame, judgment provides the decision

## Red flags that invalidate scoring

- **Unrealistic load in PoC** — must simulate at least 100 cameras at 3 FPS to have predictive value
- **Missing failover test** — any proposal claiming graceful failover must demonstrate it, not just design it
- **No 10× projection** — cost scoring requires projected numbers at scale
- **Unreviewed cost model** — infra cost assumptions must be cross-checked (e.g., Redis RAM requirement, S3 GET/PUT volume)

## Out of scope for rubric

- Fit with downstream products ([[watchman-repo|Watchman]], AutoPatrol, etc.) — should be considered in selection discussion but is hard to score objectively
- Team preference / developer happiness — important, but not a rubric line
- Customer-visible behavior changes — must be flagged per proposal but not weighted in the composite
