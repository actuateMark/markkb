---
title: Watchman Platform — Fleet Architecture & Management Service Briefing
author: kb-bot
created: 2026-05-28
updated: 2026-05-28
topic: fleet-architecture
type: synthesis
tags: [fleet-architecture, watchman, manager-service, briefing, overview, autopatrol]
related:
  - "[[topics/fleet-architecture/_summary]]"
  - "[[topics/watchman/_summary]]"
  - "[[2026-05-28_watch-management-service-design]]"
  - "[[2026-05-28_watchman-scheduling-brainstorm-correlation]]"
  - "[[2026-05-05_fleet-architecture-workstream-context]]"
incoming:
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/syntheses/2026-06-01_adr-watchman-mvp-slim-connector.md
  - topics/personal-notes/notes/daily/2026-05-28.md
  - topics/watchman/notes/syntheses/2026-05-29_watchman-prds-summary.md
incoming_updated: 2026-06-02
---

# Watchman Platform — Fleet Architecture & Management Service Briefing

**Audience:** team meetings (2026-05-29 & 2026-06-01). 5-minute read; bring this open in Q&A.

## TL;DR

The fleet rearchitecture is now part of the **[[watchman-repo|Watchman]]** project umbrella. [[watchman-repo|Watchman]] introduces the `Watch = (site, cameras[], product)` runtime entity — the customer-facing unit of "armed surveillance" — and that data model needs (a) a **platform** to run on and (b) a **runtime service** to manage [[watch-entity|Watch]] lifecycle. We have **six fleet-architecture proposals (A, B, C, D, E, B′)** for (a), and a converging design for (b) — a **[[watch-entity|Watch]] Management Service** that the scheduler hands a [[watch-entity|Watch]] to and that owns everything downstream (setup, teardown, [[healthchecks]], arm/disarm, billing-event capture). Three proposals (C, E, B′) already half-build the management service; two (B, D) need it as net-new; one (A) gets a small contained version. The [[2026-04-22_fleet-coordinator-api-sketch|FleetCoordinator 15-RPC API]] is effectively the management service's contract for C+E+B′.

## Watchman is the umbrella

This isn't a fleet-only rework — it's the platform layer of **[[watchman-repo|Watchman]]**, the product effort that defines:

- The **[[watch-entity|Watch]]** entity (`site × cameras[] × product`) as the unit users arm and disarm.
- Shared **calendar sets** (`base` recurring + `suppress` for holidays/closures) that many Watches subscribe to.
- **Manual overrides** with explicit `expires_at` (no permanent flips).
- **Operating modes** (Patrol / Active Monitoring) — **site-level state managed by the Site Supervisor Agent (PROD-147), orthogonal to [[watch-entity|Watch]] arming.** A [[watch-entity|Watch]] is armed or disarmed; a site is in Patrol or Active. They compose. (Confirmed by [[2026-05-29_watchman-prds-summary|PRD v2 / Agent Specs]].)
- A **multi-agent layer** above the data plane: Site Supervisor (mode state machine + resource allocator), Site Context (rhythm model + schedule-aware context), Patrol Agent (PROD-152 — cloud-side adaptive patrol; absorbs today's AutoPatrol), Connectivity Agent (stream health + NVR-playback fallback), Escalation Agent (**direct-to-operator push/SMS/phone/email — not Immix**), and others.

Everything in this briefing — the six proposals, the manager service, the cross-cutting constraints — is **how we make [[watchman-repo|Watchman]] run reliably on our infrastructure**. The [[watchman-repo|Watchman]] PRD v2 (PM/478019585) and Agent Specs (PM/482344961) define what users see; this document defines what's underneath. See [[2026-05-29_watchman-prds-summary]] for a fact-sheet of what those PRDs actually say.

See [[2026-05-28_watchman-scheduling-brainstorm-correlation]] for the gap between [[watchman-repo|Watchman]]'s vision and the connector's current `(site, camera, product)` model. Key gap: **the connector has no arm/disarm concept today** — Watches project onto current code as a *predicate* over `(camera, stream, feature_deployment)` tuples that has to be added.

## Why we're rearchitecting (in service of Watchman)

Today's connector fleet has three structural pain points that block delivering [[watchman-repo|Watchman]] cleanly:

1. **Scheduling sprawl.** Arm/disarm flows through a constellation, not a service: `ScheduleV2` + `FlexSchedule` + `Calendar` + Django-Q tasks + `schedule_processor.py` + `override_timer.py` + `schedule_deployer.py` + `ConnectorController` + `connector_deployer` REST + in-pod `endrun()` hooks + separate VCH/AutoPatrol CronJobs. No transactional boundary across DB write → cron-row write → K8s call; failures leak silently. [[watchman-repo|Watchman]]'s clean [[watch-entity|Watch]]/CalendarSet/ManualOverride model can't bolt onto this — it needs a real service.
2. **Tight pod-coupling.** State lives in per-pod memory; one pod handles all of a customer's cameras + products. No granularity below "the whole site." `ChunkedSiteManager` shards across processes but doesn't change the model. [[watchman-repo|Watchman]]'s per-Watch granularity has no natural home here.
3. **No arm/disarm gate in the data plane.** The connector has zero time-of-day gating, zero per-camera enable bit, zero alert suppression by schedule. Pod-running-or-not is the only knob. [[watchman-repo|Watchman]] requires finer.

(There's also an edge case — the midnight-cutover schedule-evaluation race, **ENG-96** — band-aided today with `scalerReplicasArmDown: 20`. Worth fixing as part of the rework, but not a primary driver. Most proposals fix it incidentally.)

## Two implementation paths for Watchman's scheduler

The [[watchman-repo|Watchman]] scheduling brainstorm (Confluence PM/601686018) sketches two ways to drive [[watch-entity|Watch]] transitions:

- **(A) EventBridge-per-event** — one AWS schedule per `(watch, event)` pair, transition Lambdas flip `is_in_window` bits in DB. Near-instant transitions; large AWS-resource surface; reconciliation/cold-start care needed.
- **(B) Runner tick** — one process wakes every 30–60s, evaluates armed state as a pure function of `(calendar_events, manual_overrides, now)`. No per-Watch AWS resources; up to one tick of latency on transitions; naturally stateless.

Either way, **the Management Service is what runs**: Option B *is* the manager's reconcile loop; Option A makes the manager a transition consumer. Picking A or B is a question for *inside* the manager, not a separate decision.

## The six proposals — one-paragraph each

### A — Minimal Split
Per-family puller pods, per-site pipeline worker (unchanged), pod-fleet alert dispatch. State in pipeline worker pod memory; ephemeral frames in Redis Streams; windows in DDB. **No coordinator.** Smallest delta from today — and the smallest step toward the [[watchman-repo|Watchman]] runtime.

### B — Stage Fleets
Five pipeline stage fleets (Puller, Motion, Inference-Coord, Observer+Filter, Alert) as Deployments. Tracker state in Observer pod memory + Redis snapshots. **No coordinator** (a "Camera Registry" placeholder is named but undeveloped — the manager service slots into this gap).

### C — Camera-Worker Fleet
Generic worker pods bin-packed with cameras across sites by an **Assignment Controller (singleton + HA standby)**. TTL-leased camera→worker mapping. State in worker pod memory + Redis snapshots. Controller already owns schedule context — armed-state rides along with the assignment, which is exactly the [[watchman-repo|Watchman]] manager-service surface.

### D — Event-Driven Pipeline
Pod per stage (Puller+FDMD, Detector, Observer+stateful, Alert), Deployments autoscaled on NATS JetStream consumer-lag. Frames in S3/MinIO (1h TTL), envelopes in NATS JetStream durable streams. **No coordinator beyond the broker** — the manager rides JetStream as a publisher on per-Watch subjects.

### E — Hybrid Sidecar
Smart Puller pods (per VMS family) + **Detection Core StatefulSet pod per camera-group (10–50 cameras)** + Alert Dispatch pods. State in StatefulSet pod memory + Redis snapshots. Has a coordinator — **Site Context Service** — owning config, camera registry, and centralized schedule eval. Site Context IS the manager-service surface in this proposal.

### B′ — Stateless with Blob Coordinator
B's five stage fleets + a **3-replica Blob Coordinator StatefulSet (etcd-Raft)**. Per-window JPEG blobs on node-local tmpfs of the owning motion pod; lease metadata in Raft state. Originally scoped to blob lifecycle but its own open question asks "should it absorb C's assignment and E's schedule eval?" The [[2026-04-22_fleet-coordinator-api-sketch]] answers yes — a unified **FleetCoordinator (15 RPCs across Assignments, Schedules, Config, Outcomes)**.

## The Watch Management Service — what it is

A **continuous daemon** that the scheduler hands a [[watch-entity|Watch]] directive to; the daemon owns every K8s primitive + signal beyond that point. Decisions established:

- **Lifecycle:** continuous (not summoned per arm-window).
- **Scope:** unified — owns realtime arming + VCH (healthcheck) + AutoPatrol scheduling. One control plane for every runtype.
- **Cardinality:** proposal-dependent — per-Watch (1:1), per-site, or fleet-singleton. Most proposals favor fleet-singleton.

What it replaces (today's constellation):

| Replaces | With |
|---|---|
| Django-Q `schedule_processor / override_timer / schedule_deployer` chain | Manager's reconcile loop |
| `ConnectorController.start/stop/reboot_connector` + `connector_deployer` REST | Manager-driven K8s actions (or manager uses deployer as its only client) |
| Separate VCH + AP CronJob owners (`Healthcheck.handle_healthcheck_cronjob`, `AutoPatrolSchedule.deploy/undeploy`) | Single manager publishes Watches of all types |
| Redis `MotionStatus.manual_start/_stop` epoch fields + 24h debounce | First-class `ManualOverride` entity with `expires_at NOT NULL` in durable storage |
| `Customer.current_schedule_override_start/_end` denormalized display fields | Manager state as source of truth |
| Per-pod schedule evaluation (today's midnight race lives here) | Single evaluator at manager tick |

## Per-proposal fit matrix

| Proposal | Has built-in coordinator? | Manager fits as | Effort | Fit |
|---|---|---|---|---|
| A — Minimal Split | No | Per-site supervisor (sidecar to pipeline worker) | Small, net-new | Workable |
| B — Stage Fleets | No (only the "Camera Registry" placeholder) | Fleet-singleton; manager IS the unfilled gap | Large, net-new | Required |
| C — Camera-Worker | **Yes — Assignment Controller** | Manager IS the Controller + small extensions | Small, extend | **Strong** |
| D — Event-Driven | No (just JetStream) | Fleet-singleton + per-Watch JetStream subjects | Large, net-new but elegant | Strong (different) |
| E — Hybrid Sidecar | **Yes — Site Context Service** | Manager IS Site Context + small extensions | Small, extend | **Strong** |
| B′ — Blob Coordinator | **Yes — Blob Coordinator (Raft)** | Manager absorbs Coordinator → unified FleetCoordinator | Medium, extend | **Strong + linearizable** |

**The high-leverage observation:** C, E, and B′ converge on the same manager surface — the [[2026-04-22_fleet-coordinator-api-sketch|FleetCoordinator 15-RPC API]] covers all three with zero gaps. Picking any of C/E/B′ buys the manager work in the same motion as the data-plane rearchitecture.

## Judge Contract — alert path from connector to operator

A separate but related design landed 2026-05-29: **[[watchman-repo|Watchman]] Judge ⇔ Backend I/O Contract** ([[2026-05-29_watchman-judge-backend-io-contract]]). It defines the wire protocol for the **judge agent** — the AI loop that takes a confirmed alert and returns a disposition (`escalate_immediate / escalate_review / auto_clear_normal / auto_clear_fp / suppress_low_value`).

```
Connector pod ──[SQS]──▶ Watchman Judge ──[SNS]──▶ Django ──[WS]──▶ Operator
                                                       └──▶ Audit log
```

Key points for the meeting:
- **This is one agent of ten** in the [[watchman-repo|Watchman]] platform — not the whole platform. The "[[watchman-repo|Watchman]]" naming in the source doc is ambiguous; we recommend renaming to "[[watchman-repo|Watchman]] Judge."
- **The contract is orthogonal to the manager service.** Manager controls arm/disarm; judge processes alerts from armed Watches. They don't talk directly.
- **Hook point in the connector:** post-observer/window confirmed alerts (today's alert path) — implies a new `WatchmanJudgeAlertSender` in `actuate-alarm-senders` peered with existing senders.
- **`watch_id` + `run_id` should be added** to both input and output schemas — lets dispositions join cleanly to manager audit log + billing.
- **Immix is separate.** Captured in [[2026-05-29_watchman-judge-immix-integration]]; not a peer of Django in the judge fan-out.
- **Latency conflict to resolve.** PRD says sub-10s detection-to-notification; contract estimates 6–12s for escalate. Need per-hop budget.
- **Transport conflict to resolve.** Contract picks SQS/SNS; PRD assumes Kafka inter-agent bus. Platform-level decision.

Full 12-item conflict register in the judge-contract synthesis.

## Cross-cutting constraints any manager must honor

10 non-negotiables, regardless of proposal:

1. `site_product_ended` emits exactly once per `(camera, product)` per run — billing invariant; bitten by it twice (#1663, #1667).
2. Listener threads must start **post-fork** (`run()`, not `__init__`) — `ChunkedSiteManager` forks pre-camera-thread.
3. No settings-reload path — any config mutation = teardown + new pod. **Must be relaxed under [[watchman-repo|Watchman]]** — Site Supervisor's "bump FPS in Active mode" requires hot-reconfigure. Net-new workstream.
4. No transactional boundary across DB write + cron-row write + K8s call.
5. Redis `MotionStatus.manual_start/_stop` is the actual runtime oracle today, not the Customer fields. **This is a problem, not a constraint to preserve** — Redis is ephemeral; a flush loses every active manual override. The manager design replaces this with a durable `ManualOverride` entity (Postgres / Raft / whichever state store we pick). Redis stays only as an optional read-through cache.
6. K8s arm/disarm is full create/delete — `connector_deployer` has no `/scale` endpoint.
7. `terminationGracePeriodSeconds=90` for Deployments, `=10` for CronJobs — design grace in, don't shorten. **[[watch-entity|Watch]] this interact with constraint #3:** because there's no settings reload, any config mutation (e.g. ignore-zone edit) = teardown + new pod. Today that means the whole customer's pod cycles for any change. With per-Watch (or smaller-than-site) granularity, the impact is bounded — change an ignore zone on one camera, only that [[watch-entity|Watch]]'s workload cycles, not the entire site. This is one of the strongest arguments for narrower-than-site cardinality in proposals C/D/E/B′.
8. Connector owns its own `start_patrol/end_patrol` HTTP calls to Immix — manager must NOT also call. **Sunset under [[watchman-repo|Watchman]]** — Patrol Agent (PROD-152) replaces this; manager coordinates the deprecation.
9. Image tags with `/` must be slash-encoded — deployer doesn't validate.
10. Manual disarm at 23:59 blocks next-day cron tick (24h debounce on the Redis fields) — the new `ManualOverride` entity with explicit `expires_at` eliminates this class of bug.

Full audit + 18-touchpoint catalog in [[2026-05-28_watch-management-service-design]].

## Decisions the team needs

In rough priority order — these gate further design:

1. **Pick the rearchitecture proposal** (or short-list to 2 for PoC). Manager-service fit *is* a fleet-arch evaluation dimension now.
2. **Manager state store** — Postgres (current admin), Redis (current MotionStatus), Raft (B′ style), or a new private store? Affects HA + failure modes per [[2026-05-29_watch-manager-failure-modes]].
3. **`connector_deployer` future** — keep as K8s gateway, absorb into manager, or retire? Migration plan ([[2026-05-29_watch-manager-migration-plan]]) keeps it through phase M3.
4. **VCH/AP runtime model** — partly answered by [[2026-05-29_watchman-prds-summary|PRD]]. Patrol Agent absorbs AP scheduling; VCH overlaps Connectivity Agent + CHM. Both lose "separate CronJob" identity in the target state. Open question: what's the bridge state?
5. **Manager schema ownership** — does the manager own the new [[watch-entity|Watch]]/CalendarSet/ManualOverride schema, or does admin own it and manager subscribe?
6. **Per-Watch K8s granularity** — one pod per site handling N internal Watches, or one Deployment per [[watch-entity|Watch]]? (See constraint #7 — this directly determines blast radius of any config change.)
7. **Site Supervisor ↔ Manager relationship.** Recommended: Option II (manager upstream as armed-state source of truth, Site Supervisor is a tenant for mode-aware hot-reconfigure). See [[2026-05-29_site-supervisor-vs-watch-manager]].
8. **Hot-reconfigure mechanism for the connector.** Net-new workstream — constraint #3 must be relaxed under [[watchman-repo|Watchman]].
9. **Kafka adoption timeline.** PRD assumes Kafka inter-agent bus; today's billing pipe is SQS. Bridging migration per [[2026-05-29_watch-manager-migration-plan]].

## Where to read more

**[[watchman-repo|Watchman]] (product layer)**
- **[[watchman-repo|Watchman]] summary:** [[topics/watchman/_summary]]
- **PRD + Agent Specs digest:** [[2026-05-29_watchman-prds-summary]] *(read this first — fact-sheet of PM/478019585 + PM/482344961)*
- **Confluence — [[watchman-repo|Watchman]] PRD v2:** [PM/478019585](https://actuate-team.atlassian.net/wiki/spaces/PM/pages/478019585)
- **Confluence — Agent Specs:** [PM/482344961](https://actuate-team.atlassian.net/wiki/spaces/PM/pages/482344961)
- **Confluence — [[watchman-repo|Watchman]] Scheduling Brainstorm:** [PM/601686018](https://actuate-team.atlassian.net/wiki/spaces/PM/pages/601686018)
- **Brainstorm gap analysis ([[watchman-repo|Watchman]] vs. current connector):** [[2026-05-28_watchman-scheduling-brainstorm-correlation]]
- **Site Supervisor ↔ Manager relationship:** [[2026-05-29_site-supervisor-vs-watch-manager]]
- **[[watchman-repo|Watchman]] cross-ref index for this work:** [[2026-05-28_watch-management-service-index]]

**Platform / fleet-arch — Round 1 (May 28)**
- **Master design + constellation baseline:** [[2026-05-28_watch-management-service-design]]
- **Per-proposal addenda** (one each for A/B/C/D/E/B′): `2026-05-28_watch-management-proposal-{x}.md` in `fleet-architecture/notes/syntheses/`.

**Platform / fleet-arch — Round 2 (May 29)**
- **Observability primitives:** [[2026-05-29_watch-manager-observability]]
- **Migration plan (5-phase cutover):** [[2026-05-29_watch-manager-migration-plan]]
- **Failure modes / partition behavior:** [[2026-05-29_watch-manager-failure-modes]]
- **AIT/brain-in-jar integration plan:** [[2026-05-29_ait-watch-manager-integration]]
- **[[watchman-repo|Watchman]] Judge ⇔ Backend I/O Contract:** [[2026-05-29_watchman-judge-backend-io-contract]] (analysis + decisions + conflict register)
- **Immix integration (separate):** [[2026-05-29_watchman-judge-immix-integration]]

**Existing context**
- **Existing fleet-arch proposals** (April 16 + 22): `2026-04-16_proposal-{a,b,c,d,e}-*.md`, `2026-04-22_proposal-b-prime-stateless-with-coordinator.md`, `2026-04-22_fleet-coordinator-api-sketch.md`
- **Evaluation rubric:** [[2026-04-16_evaluation-rubric]] + [[2026-05-11_rubric-monitoring-billing-dimensions]]
- **Run Service workstream context** (parallel control plane for ephemeral + persistent modes): [[2026-05-05_fleet-architecture-workstream-context]]
