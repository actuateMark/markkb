---
title: "Open Question — Vini's API Gateway: Extend or Parallel?"
type: concept
topic: data-access-control
tags: [open-question, team-discussion, api-gateway, vini, authorizer, ENG-122]
created: 2026-05-11
updated: 2026-05-11
author: kb-bot
outgoing:
  - topics/data-access-control/notes/syntheses/2026-05-11_admin-db-access-hardening.md
status: needs-team-discussion
incoming:
  - topics/data-access-control/_summary.md
  - topics/data-access-control/notes/concepts/2026-05-11_open-question-developer-tokens.md
  - topics/data-access-control/notes/syntheses/2026-05-13_dig-followups.md
  - topics/data-access-control/team-brief.md
  - topics/personal-notes/notes/concepts/2026-05-11_next-session-handoff.md
  - topics/personal-notes/notes/daily/2026-05-11.md
incoming_updated: 2026-05-27
---

# Open Question — Vini's API Gateway: Extend or Parallel?

> **Status:** Needs team discussion. Decision required before Phase 2 of [[2026-05-11_admin-db-access-hardening|admin DB access hardening]] commits to its target architecture. This note exists to make the decision conversation tractable rather than open-ended.

## TL;DR

Vini's [[external-api/_summary|external-API initiative]] (ENG-122 family) is building a partner-facing API on top of AWS API Gateway → [[rust-lambda-authorizer|Rust Lambda Authorizer]] → K8s/ALB. We need to decide whether to **extend that chain to handle internal admin-API traffic too**, or **run a parallel-but-compatible internal stack** that shares the auth model and scope vocabulary but is separately deployed.

**Mark's current lean: parallel-but-compatible**, primarily for east-west latency reasons. Wants team input — Vini and Tati especially.

## Why this matters

Phase 2 of the hardening plan makes every non-admin service (vms-connector, queue-consumer, autopatrol-server) call admin via HTTP rather than direct DB. That HTTP call is on a hot path — vms-connector pulls camera/customer/option metadata frequently, and `get_product_by_metrics()` runs ~6 times per site session in the billing flow.

The auth-and-routing infrastructure underneath those calls is exactly what Vini's external-API work has already solved for partner traffic. The question is whether we reuse one stack or two.

## The two options

### Option A — Extend Vini's gateway + authorizer chain to internal traffic

```
Internal Service → AWS API Gateway → Rust Lambda Authorizer → Admin K8s/ALB
```

Internal callers use the same API Gateway endpoint that partners do, just with internal-issued tokens that the Rust authorizer recognizes.

**Buys:**
- One auth implementation. Adding a scope or fixing an auth bug applies to internal + external simultaneously.
- Free rate-limiting + request logging + IAM-based auth from API Gateway.
- The Rust authorizer already exists and is well-tested for the external use case.
- Consistent observability surface across all admin callers.

**Costs / risks:**
- **Coupling to ENG-122's pace.** Vini's workstream timeline becomes our gating dependency. Their team's priorities aren't necessarily ours.
- **Gateway hop adds latency** — for east-west calls inside the same VPC, that's ~10–30ms of extra round-trip we don't need.
- The Rust authorizer would need to validate internal token types; that's a new code path with its own test surface.
- One stack becomes a single point of failure for both external and internal admin auth. A bug taking down the authorizer takes down everything.

### Option B — Parallel-but-compatible internal stack

```
Internal Service → Admin K8s/ALB (DRF authentication classes validate tokens directly)
```

Internal callers hit admin directly. Admin's DRF auth layer validates the same scope vocabulary Vini uses externally, but the validation logic lives in admin (not in a Rust Lambda).

**Buys:**
- No extra hop. Internal latency stays as low as it is today.
- Decoupled delivery — internal hardening ships even if ENG-122 stalls.
- Simpler operationally (one less moving part for internal traffic).
- Failure isolation — an internal auth bug doesn't touch partner traffic and vice versa.

**Costs / risks:**
- Two implementations of "validate a token + check scope" — even if they share a vocabulary, they're different code paths that can drift.
- We rebuild some of what API Gateway gives for free (rate limiting, structured request logs).
- Two auth observability surfaces.

## Questions to land in the discussion

1. **What's ENG-122's realistic delivery timeline?** If Vini's gateway is shipping in the next ~6 weeks anyway, Option A's coupling cost is small. If it's a multi-quarter effort, the coupling becomes material.
2. **How much east-west traffic volume is at stake?** vms-connector makes admin calls per camera per cycle. For 1000 cameras × 10 calls/minute × 20ms latency penalty per call = 200 sec/min of cumulative wall time the connector is waiting on gateway hops it didn't need.
3. **Could we adopt API Gateway later if Option B turns out to be the wrong call?** Yes — `actuate-admin-api` is the abstraction layer, and consumers don't care whether the URL hits a gateway or admin directly. Migration from B → A is cheap. Less clear that A → B is cheap (we'd be tearing out shared infra).
4. **Are there partner-facing endpoints that overlap with internal needs?** If yes, Option A's "one auth path" advantage gets bigger.
5. **Does Vini's authorizer support per-token scopes today, or is it currently coarse (key-valid vs. not)?** Determines how much new work Option A requires anyway.

## Mark's lean

**Parallel-but-compatible (Option B)** as a starting position, for three reasons:

- East-west latency on the vms-connector hot path matters. Gateway hops add up.
- Decoupled delivery — we can ship internal hardening on our own timeline.
- The migration path from B → A is cheap if we later decide we want the gateway. The reverse isn't true.

But I'm willing to be wrong on this — if Vini's gateway is close to shipping and the latency cost is smaller than I think, Option A's "one auth implementation" advantage is real.

## Decision needed by

Before Phase 2 endpoint design begins. The two options imply different request/response shapes (gateway-validated tokens come in differently than DRF-validated ones) and influence the contract every new admin endpoint will follow.

## Cross-references

- [[2026-05-11_admin-db-access-hardening]] — parent synthesis
- [[external-api/_summary]] — Vini's ENG-122 family of workstreams
- [[2026-05-11_admindao-call-site-inventory]] — the migration scope this decision affects
