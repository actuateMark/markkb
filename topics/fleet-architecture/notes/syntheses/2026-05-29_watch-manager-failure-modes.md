---
title: Watch Manager Failure Modes — Partition Behavior and Invariants
author: kb-bot
created: 2026-05-29
updated: 2026-05-29
topic: fleet-architecture
type: synthesis
tags: [watchman, fleet-architecture, manager-service, failure-modes, partition, sla]
related:
  - "[[2026-05-28_watch-management-service-design]]"
  - "[[2026-05-29_watch-manager-observability]]"
  - "[[2026-05-29_watch-manager-migration-plan]]"
incoming:
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/concepts/cardinality-decision.md
  - topics/fleet-architecture/notes/concepts/manager-touchpoint-catalog.md
  - topics/fleet-architecture/notes/syntheses/2026-05-28_fleet-rearch-briefing-overview.md
  - topics/fleet-architecture/notes/syntheses/2026-05-29_watch-manager-migration-plan.md
  - topics/fleet-architecture/notes/syntheses/2026-05-29_watch-manager-observability.md
  - topics/watchman/notes/syntheses/2026-05-28_watch-management-service-index.md
  - topics/watchman/notes/syntheses/2026-05-29_site-supervisor-vs-watch-manager.md
incoming_updated: 2026-05-30
---

# Watch Manager Failure Modes — Partition Behavior and Invariants

## Why this note exists

The May 28 master design names cross-cutting constraints but doesn't enumerate what happens when the manager **fails**. [[watchman-repo|Watchman]] SLAs are tight (sub-10s detection-to-notification) and revenue runs through the billing invariant; "what does a failed manager actually break?" needs a clear answer per failure class.

## Design principles

1. **Default to "safe" — armed-state stays as-is during manager failure.** Disarming on uncertainty is unsafe (customer loses surveillance). Arming on uncertainty is also unsafe (false billing). When in doubt, **do not transition.**
2. **Partition recovery is automatic.** No human-in-loop for the common case.
3. **Audit log is the recovery source-of-truth.** When manager rejoins after partition, replay missed transitions from the audit topic.
4. **The connector pod is more resilient than the manager.** A running pod keeps running even if the manager dies; it doesn't depend on per-frame manager calls.

## Failure classes

### F-A. Manager process crash

**Symptoms:** manager pod restarts (K8s restarts it). Reconcile loop pauses for ~30s (init + state hydration).

**Impact:**
- Scheduled transitions in the crash window: **delayed**, not lost. Manager catches up on next tick.
- Manual override "arm now": **delayed** until manager rejoins. Customer-facing UX impact for ≤30s.
- K8s state: **unchanged**. Connector pods keep running.
- Billing: **unaffected**. SQS observation resumes on manager rejoin.

**Recovery:**
- Manager hydrates state from state store on startup.
- Replays missed transitions from audit topic (Kafka consumer offset advances after each transition is applied).
- Drift converges in ≤1–2 reconcile ticks.

**Invariant guarantees:**
- No double-arm (idempotency keys block duplicate K8s mutations during catch-up).
- No skipped billing events (SQS retains messages until ACKed).

### F-B. Manager partition from state store

**Symptoms:** Postgres / Raft / Redis unreachable. Manager logs `state_read_duration_seconds` timeouts.

**Impact:**
- Reconcile loop cannot read desired state — it pauses (does not issue mutations).
- Already-running pods keep running.
- New transitions cannot be issued.

**Recovery:**
- Manager retries on backoff (1s → 5s → 30s, capped at 60s).
- When state store rejoins, reconcile loop resumes from current state.
- Missed scheduled transitions during partition fire on next tick (delayed).

**Invariant guarantees:**
- No state-mutating mutations issued during partition (manager refuses to act on stale reads beyond 5s).

### F-C. Manager partition from K8s API

**Symptoms:** `kubectl` calls fail. Manager logs `k8s_call_duration_seconds` timeouts on mutations.

**Impact:**
- Manager can read desired state but cannot mutate observed state.
- Already-running pods keep running (K8s API down doesn't kill pods).
- Newly-scheduled arms are queued in manager state; mutations retry with backoff.
- Disarms cannot land — pods keep running past intended disarm time.

**Recovery:**
- Mutation queue drains on K8s API rejoin.
- Idempotency keys ensure no double-action during catch-up.

**Invariant guarantees:**
- Eventual consistency — arms and disarms always land, may be late.
- **Billing risk if disarm is delayed:** a [[watch-entity|Watch]] that should have disarmed continues to incur compute. Mitigation: alert on `watch_manager_k8s_call_duration_seconds` p99 > 30s sustained.

### F-D. Manager partition from billing event stream (SQS / Kafka)

**Symptoms:** Manager can mutate K8s, can read state, but cannot observe `site_product_started`/`site_product_ended`.

**Impact:**
- Manager loses ability to confirm "did this [[watch-entity|Watch]] actually run?" T17 oracle silent.
- Audit log shows manager-issued arms but no completion proof.
- Reconcile loop continues to issue mutations (it doesn't depend on billing observation).

**Recovery:**
- Billing event consumer reconnects; replay from last ACKed offset.
- Missed billing observations are re-emitted by SQS / replayed from Kafka retention.
- Manager catches up on completion proofs.

**Invariant guarantees:**
- Constraint #1 (exactly-once billing emit) is **still enforced by the connector** — the manager's role is observation, not enforcement. Partition here delays observability, not correctness.

### F-E. Manager partition from Kafka inter-agent bus (under Watchman)

**Symptoms:** Manager can't publish transition events; Site Supervisor Agent can't receive them.

**Impact:**
- Site Supervisor Agent cannot see armed-state changes — Mode state machine inputs go stale.
- New manual overrides applied through admin → manager → K8s but Site Supervisor doesn't see them; mode-aware FPS bumps don't fire.
- Other agents (Patrol, Threat, Assessment) similarly stale.

**Recovery:**
- Kafka rejoin → consumer catches up from retained offset.
- Site Supervisor backfills armed-state from manager's `GET /debug/state` endpoint (instrumentation hook 5) once Kafka comes back.

**Invariant guarantees:**
- [[watchman-repo|Watchman]] SLA (sub-10s detection-to-notification) is **breached** during a sustained Kafka partition — alert immediately.
- Manager's correctness invariants (exactly-once arm/disarm, billing) are independent of Kafka and remain intact.

### F-F. Split-brain (manager runs in two clusters / two replicas simultaneously)

Most relevant under Proposal B′ (Raft StatefulSet — split-brain prevented by quorum), Proposal C (Assignment Controller + standby — split-brain possible if standby promotes erroneously), and any "fleet-singleton on a regular Deployment" pattern (lease-based, split-brain possible during lease handoff).

**Symptoms:** Two managers issue concurrent K8s mutations for the same [[watch-entity|Watch]].

**Impact:**
- Without idempotency keys: duplicate Deployments created / deletes race / billing skew.
- With idempotency keys: second mutation deduped; no production impact.

**Recovery:**
- Lease holder identified (Redis lease or Raft leader); loser self-terminates.
- Audit log shows two writers; alert if both wrote concurrent mutations.

**Invariant guarantees:**
- **Hard dependency on idempotency keys (instrumentation hook 2).** Without these, split-brain corrupts state. With them, split-brain is degraded performance only.

### F-G. State store corruption / data loss

**Symptoms:** [[watch-entity|Watch]] records missing or mangled. Manager logs `state_consistency_check_total{outcome="fail"}`.

**Impact:**
- Severe. Without state, manager doesn't know which Watches exist.
- Running pods continue (they don't depend on manager state).
- New transitions cannot be evaluated.

**Recovery:**
- Restore state store from backup (Postgres PITR, Raft snapshot, Redis AOF).
- Replay transition audit log from last clean snapshot.
- Reconcile loop resumes; convergence may take longer due to large drift.

**Invariant guarantees:**
- Audit log retention (13 months per [[2026-05-29_watch-manager-observability]]) is the last-resort recovery source.
- **Document Postgres PITR procedure** as part of manager operations runbook.

### F-H. Connector_deployer down

**Symptoms:** Manager's K8s actuator path returns 5xx from `connector_deployer` HTTP API.

**Impact:**
- Same as F-C (K8s partition) — mutations queue, retry with backoff.
- During phase M2 of the migration plan, Django-Q chain has its own deployer client and can cover for the manager.

**Recovery:**
- Manager retries via existing 5-attempt exp backoff.
- If `connector_deployer` is down for > 5 min, alert. Manager doesn't have a fallback path until it talks K8s API directly (later migration phase).

## Per-proposal failure-mode characteristics

| Proposal | F-A crash recovery | F-F split-brain prevention | F-G recovery latency | Notable |
|---|---|---|---|---|
| A — Per-site | Fast (single pod restart) | Per-site, low coordination | Per-site recovery (parallelizable) | Smallest blast radius per failure |
| B — Stage Fleets | Standard K8s restart | Lease-based (split-brain possible) | Slower if Camera Registry is single | Fleet-singleton bottleneck |
| C — Camera-Worker | Assignment Controller restart | Lease + standby promotion (split-brain possible) | Worker reassignment storm risk on long F-G | Camera leases expire during outage |
| D — Event-Driven | Manager restart; JetStream retains state | JetStream consumer group prevents split-brain | JetStream KV restore (StatefulSet-bound) | Cleanest recovery story |
| E — Hybrid Sidecar | StatefulSet restart | Site Context Service singleton (Deployment, lease-based) | Per-camera-group recovery | StatefulSet ordinal preserves identity |
| B′ — Coordinator+Raft | Raft quorum heals fast (typically <5s) | **Raft prevents split-brain by design** | Raft snapshot restore | Strongest failure-mode story by design |

## Invariants that must survive every failure

1. **No double-emit of `site_product_ended`** for the same `(camera, product, run_id)` regardless of manager state. Enforced by the connector (`VCHCamera._product_events_fired` set + SQS), not the manager.
2. **No double-arm**: same `(watch_id, intended_armed_state)` mutation issued twice in a 60s window must be deduped by the actuator path.
3. **No silent disarm beyond intended time**: alert if `armed_duration > expected_window_duration + 60s`.
4. **Audit log writes are best-effort but non-blocking**: a Kafka audit publish failure must not block the K8s mutation it audits. Use local disk buffer + retry.

## Cross-references

- [[2026-05-28_watch-management-service-design]] — master design (the 18 touchpoints all degrade under one or more failure modes above)
- [[2026-05-29_watch-manager-observability]] — alert definitions for the failure modes
- [[2026-05-29_watch-manager-migration-plan]] — failure-mode behavior during dual-write phase M2
- [[2026-05-28_watch-management-proposal-b-prime]] — Raft-backed B′ has the strongest story by design
