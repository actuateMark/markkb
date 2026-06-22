---
title: Watch Management Service — Cross-Architecture Design and Constellation Baseline
author: kb-bot
created: 2026-05-28
updated: 2026-05-28
topic: fleet-architecture
type: synthesis
tags: [watchman, scheduling, fleet-architecture, manager-service, override, calendar, arming, lifecycle, autopatrol]
related:
  - "[[topics/fleet-architecture/_summary]]"
  - "[[topics/watchman/_summary]]"
  - "[[2026-05-28_watchman-scheduling-brainstorm-correlation]]"
  - "[[2026-04-22_proposal-b-prime-stateless-with-coordinator]]"
  - "[[2026-04-22_fleet-coordinator-api-sketch]]"
confluence: "https://actuate-team.atlassian.net/wiki/spaces/PM/pages/601686018"
incoming:
  - topics/engineering-process/notes/syntheses/2026-05-29_ait-watch-manager-integration.md
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/concepts/2026-06-01_terminology-conflict-watchman-ambiguity.md
  - topics/fleet-architecture/notes/concepts/cardinality-decision.md
  - topics/fleet-architecture/notes/concepts/manager-touchpoint-catalog.md
  - topics/fleet-architecture/notes/syntheses/2026-05-28_fleet-rearch-briefing-overview.md
  - topics/fleet-architecture/notes/syntheses/2026-05-28_watch-management-proposal-a.md
  - topics/fleet-architecture/notes/syntheses/2026-05-28_watch-management-proposal-b-prime.md
  - topics/fleet-architecture/notes/syntheses/2026-05-28_watch-management-proposal-b.md
  - topics/fleet-architecture/notes/syntheses/2026-05-28_watch-management-proposal-c.md
incoming_updated: 2026-06-02
---

# Watch Management Service — Cross-Architecture Design and Constellation Baseline

## Why this note exists

The [[watchman-repo|Watchman]] scheduling brainstorm (Confluence PM/601686018) defines a `Watch = (site, cameras[], product)` runtime entity. The next design question that affects every fleet-arch proposal: **what stands a [[watch-entity|Watch]] up and tears it down?** Today this is a constellation — admin Django-Q tasks, `connector_deployer` REST calls, in-pod `endrun()` hooks, separate VCH/AutoPatrol CronJobs — not a service. The [[watchman-repo|Watchman]] vision implies a single management service so the *scheduler only ever stands up one thing per [[watch-entity|Watch]]* and that one thing handles everything else.

This note is the **shared baseline + design constraints** for every fleet-arch proposal. Per-proposal addenda evaluate fit and recommend cardinality:

- [[2026-05-28_watch-management-proposal-a]]
- [[2026-05-28_watch-management-proposal-b]]
- [[2026-05-28_watch-management-proposal-c]]
- [[2026-05-28_watch-management-proposal-d]]
- [[2026-05-28_watch-management-proposal-e]]
- [[2026-05-28_watch-management-proposal-b-prime]]

## Decisions established (2026-05-28)

1. **Lifecycle:** continuous daemon (reconciler shape, not ephemeral). Same shape as the brainstorm's Option B runner.
2. **Scope:** unified — owns realtime arming + VCH (healthcheck) + AutoPatrol scheduling. The scheduler hands the manager a [[watch-entity|Watch]] directive; the manager owns every K8s primitive and signal beyond that.
3. **Cardinality:** per-proposal decision. Three options to evaluate — per-Watch supervisor (1:1), per-site supervisor, fleet-singleton controller.
4. **Output shape:** this master + per-proposal addenda.

## Constellation baseline — what exists today

### A. Admin source-of-truth surface (`actuate_admin`)

- **`ScheduleV2`** (`inframap/scheduler/scheduleV2_model.py:19-92`) — per-customer, per-weekday time-range. Holds overrides via `is_override`/`override_start_date`/`override_end_date`. Granularity is *site × weekday × time-range* — no per-camera, no per-product.
- **`FlexSchedule`** (`inframap/scheduler/flex_schedule/flex_schedule_model.py:7-50`) — M2M with `Option` (analytics product), enabling per-product schedules; spawns its own `connector_id`.
- **`Calendar` / `CalendarEvent`** (`inframap/scheduler/calendar/`) — reusable holiday sets that *inflate into* `ScheduleV2(is_override=True)` rows via `Calendar.apply_to_sites`. Calendars don't run anything.
- **`Customer.timezone`** + arming methods (`customer_model.py:1180-1701`): `get_current_schedule`, `timing`, `find_next_start_datetime`, `has_override_today`, `can_arm/can_disarm` (Redis `MotionStatus` debounce, 24h), `set_arming_disarming_status` (Redis write).
- **`Customer.current_schedule_override_start/_end`** is a **denormalized display snapshot**, not the runtime oracle — written only by `SSMStateManagerScheduleDeployer.deploy_schedule_changes:399-406`.
- **`Customer.image_tag_override_expires_at`** (`customer_model.py:168`) — custom-branch TTL, expires via `expire_custom_branches.py` cron.

### B. The Django-Q chain (cron-tick to K8s)

```
django_q.Schedule(name="<connector_id>-start-Mon", func="shortcuts.container_command")
  → shortcuts.container_command (shortcuts.py:200-)
  → ConnectorController.from_customer (connector_controller.py:67-80)
  → start_connector / stop_connector / reboot_connector
  → call_deployer("start"|"stop"|"reboot")  [HTTP, 5 retries, exp backoff]
  → connector_deployer POST /start | /stop | /reboot
```

Three logical layers:

- **`schedule_processor.py`** — synchronous from API save paths; `save_schedules` → `process_schedule_changes` → `deploy_schedule_changes` → `schedule_arm_disarm` (in `finally`).
- **`override_timer.py`** — creates one-shot `django_q.Schedule(schedule_type=ONCE)` rows for override start (`-5 min`) / stop (`-10 min`). Idempotent by name (`get_override_association_name`).
- **`schedule_deployer.py`** — `SSMStateManagerScheduleDeployer.deploy_schedule_changes:357-409`. Converts local time + DST to UTC crons per weekday; persists into `django_q.Schedule` named `<connector_id>[-fs-<flex_id>]-<action>-<weekday>`. Writes `admin:schedule_redeployed:<id>` Redis flag (24h TTL) as the "did we redeploy today" interlock.

### C. K8s actuator surface (`connector_deployer`)

`POST /start`: creates `VPA` + `Deployment` per customer (`methods.py:62-69`). `POST /stop`: deletes them. `POST /delete`: also deletes CHM CronJob. **No `/scale` endpoint** — arm/disarm = full create/delete. CronJobs (`POST /chm` discriminated by `patrol_type=VisualCameraHealth|AutoPatrol`) are independently managed: `__make_vch_schedule` randomises within 4/6/12/24h cadence (`methods.py:387-401`); `__adjust_cron_expression` takes AP's literal cron string and shifts -2 min (`methods.py:348-385`). `concurrencyPolicy: Replace`, `successfulJobsHistoryLimit=1`. Object name disjointness with [[argocd|ArgoCD]] is the only thing preventing collisions ([[argocd|ArgoCD]]: `connector-config`, `aws-minimal-access`, VPA CRD + webhook; deployer: per-customer `{hostname-id}`, `{hostname-id}-vpa`, `{hostname-id}-chm-cronjob`).

### D. Pod lifecycle (`vms-connector`)

- **Cold start:** `connector.py:184` → S3 settings → factory → `SiteManager.__init__` (pre-fork build cost, 30–120s for 24-cam site).
- **Steady state:** `AnalyticsSiteManager.run()` post-fork starts [[inference-pool|inference pool]], gc loop, monitor threads, camera threads. No settings-reload path exists.
- **Shutdown:** SIGTERM → `_shutdown_requested` event → `endrun()`: `site_product_ended` per `(stream, product)` (3-retry admin DAO lookup) → [[inference-pool|inference pool]] shutdown → parallel `camera.endrun()` threads (5s shared deadline) → `sys.exit(0)`. `ChunkedSiteManager` parent runs the same parallel to child shards (30s join deadline).
- **VCH / AP specifics:** `VCHCamera._send_product_ended_events_once` — lock + `_product_events_fired` set keyed on `admin_camera_id`, set-after-success. AutoPatrol calls `start_patrol` / `end_patrol` to Immix's patrol state machine — **owned by the connector**, manager must NOT also call.

## Constraints any manager design must honor

Drawn from the four audit streams (admin, connector, K8s, fleet-arch). These are the non-negotiables that survive across cardinality and proposal choice.

| # | Constraint | Origin |
|---|---|---|
| 1 | `site_product_ended` emits exactly once per `(camera, product)` per run on every exit path | `vms-connector` CLAUDE.md billing invariant; #1663, #1667 regressions |
| 2 | Listener threads must start post-fork (`run()`, not `__init__`) — `ChunkedSiteManager` forks pre-camera-thread | `vms-connector` CLAUDE.md fork-safety |
| 3 | No settings-reload path; any config mutation = teardown + new pod | `connector.py:95` `get_settings()` is one-shot. **Must be relaxed under [[watchman-repo|Watchman]]** — Site Supervisor's mode-change resource allocation (e.g. FPS bump during Active mode) requires hot-reconfigure. See [[2026-05-29_watchman-prds-summary]]. |
| 4 | No transactional boundary across DB-write + cron-row write + K8s call; failures leak | `schedule_deployer.py` admit `delete_duplicate_schedules` is non-deterministic |
| 5 | `current_schedule_override_start/_end` is denormalized display only — Redis `MotionStatus.manual_start/_stop` is the actual runtime oracle | `customer_model.py:1601-1609` debounce |
| 6 | K8s arm/disarm is full create/delete, no scale operation | `connector_deployer` lacks `/scale`/`/replicas` |
| 7 | `terminationGracePeriodSeconds=90` for Deployments, `=10` for CronJobs — design grace into the manager, don't shorten | `deployment.py:38`, `cronjob.py:58` |
| 8 | Connector owns its `start_patrol/end_patrol` HTTP calls to Immix; manager must not also call | `autopatrol_site_manager.py:108,247`. **Sunset under [[watchman-repo|Watchman]]** — Patrol Agent (PROD-152) replaces the connector's per-pod AutoPatrol per [[2026-05-29_watchman-prds-summary]]. Manager must coordinate the deprecation. |
| 9 | Image-tag with `/` must be slash-encoded — deployer doesn't validate | memory `feedback_check_image_tag_after_deployer_push.md` |
| 10 | Manual disarm at 23:59 blocks next-day cron tick at 00:01 (24h debounce) | `customer_model.py:1601-1609` — must redesign manual-override entity |

## Cardinality options — universal tradeoffs

| Dimension | Per-Watch supervisor | Per-site supervisor | Fleet-singleton controller |
|---|---|---|---|
| K8s objects per [[watch-entity|Watch]] | 1 supervisor + N workloads | shared supervisor + N workloads | 0 supervisors + N workloads |
| Blast radius of bug | 1 [[watch-entity|Watch]] | 1 site (many Watches) | whole fleet |
| Memory floor | high (N × baseline) | medium | low |
| Reconciler complexity | low (single resource) | medium | high ([[sharding]], ordering) |
| Maps to today's model | not at all | yes (1 customer ≈ 1 site) | no |
| Fits K8s operator pattern | possible | possible | yes — natural |
| HA story | each pod is its own SPOF | per-site SPOF | leader election / Raft (cf. B′ Blob Coordinator) |
| Fanout to forked shards | trivial (one per pod) | needs pod-internal fanout | needs pod-internal fanout |
| Migration from Django-Q | rewrites scheduler entirely | gradual (one site at a time) | rewrites scheduler entirely |
| Cold-start parallelism | parallel (one per [[watch-entity|Watch]]) | serial within site | parallel across sites, work-queue within |

**Cardinality preference is proposal-dependent**, not universal. See per-proposal addenda.

## Manager touchpoint catalog

Eighteen touchpoints the manager must own or invoke — grouped by surface. Drawn from the four audit streams; each citation in the addenda or source files.

### Schedule / state surface (5)
- T1. [[watch-entity|Watch]] directive intake (calendar_set evaluation result → desired armed state)
- T2. Manual override entity with explicit `expires_at NOT NULL` (replacing Redis `MotionStatus.manual_start/_stop`)
- T3. Schedule re-derivation on DST + day-boundary (replacing `schedules_redeploy` + `was_redeployed_today` Redis flag)
- T4. `image_tag_override_expires_at` per [[watch-entity|Watch]] — read every reconcile (replacing `expire_custom_branches.py` cron)
- T5. Single source of truth for "is (site, camera, product) armed right now?" without join-at-read

### K8s lifecycle (6)
- T6. Per-Watch Deployment + VPA create/delete (replacing `ConnectorController.start_connector / stop_connector`)
- T7. Per-Watch CronJob set for VCH + AP (replacing `AutoPatrolSchedule.deploy/undeploy`, `Healthcheck.handle_healthcheck_cronjob`)
- T8. Centralized schedule derivation — pull `__make_chm_schedule`, `__make_vch_schedule`, `__adjust_cron_expression` into manager so admin doesn't author cron strings
- T9. Wire arm/disarm to `replicas: 0/1` or CronJob `suspend: true` instead of full delete/create — preserves history, avoids cold-start image pulls
- T10. Reconcile loop — observed K8s state is source of truth; eliminate `is_arming` flags that drift
- T11. Decide gateway vs. direct K8s API — keep `connector_deployer` as the K8s gateway (and become its only client) OR talk K8s directly

### Pod lifecycle (4)
- T12. Wait-for-ready: poll `connector_ready.txt` or first `connector ready` log line (`connector.py:313`)
- T13. Coordinate graceful teardown: issue SIGTERM, [[watch-entity|watch]] for `site_product_ended` SQS confirm per `(camera, product)` before tearing down next [[watch-entity|Watch]] resource
- T14. Honor `DEPLOYMENT_ID` env (`connector.py:220`) as the only manager→pod identity handle; settings.json on S3 keyed by it
- T15. Don't double-fire `start_patrol/end_patrol` — connector owns Immix patrol state machine

### Reconciliation / observability (3)
- T16. Periodic K8s-API resync (manager state vs. actual `kubectl get`); fix orphans, missed creates, partial deletes
- T17. Billing-event subscription: SQS `site_product_started`/`site_product_ended` is the manager's "did the workload actually run" oracle
- T18. Audit log: every [[watch-entity|Watch]] state transition + every K8s mutation to ClickHouse with who/what/when/why (brainstorm Open Q8)

## Cross-proposal fit summary

| Proposal | Has built-in coordinator? | Manager fits as | Net-new? |
|---|---|---|---|
| A — Minimal Split | No | Per-site supervisor (1 per site pod) | Yes, but small scope |
| B — Stage Fleets | No (placeholder "Camera Registry") | Fleet-singleton | Yes, large net-new |
| C — Camera-Worker | Yes — Assignment Controller | Manager **is** the controller (already half-built) | No — extend existing |
| D — Event-Driven | No (only JetStream broker) | Fleet-singleton or per-Watch via JetStream subject | Yes, large net-new |
| E — Hybrid Sidecar | Yes — Site Context Service | Manager **is** Site Context Service | No — extend existing |
| B′ — Blob Coordinator | Yes — Blob Coordinator (Raft) | Manager **absorbs** coordinator (Open Q6 in B′) | No — extend existing |

The [[2026-04-22_fleet-coordinator-api-sketch]] 15-RPC unified FleetCoordinator covers C+E+B′ with zero gaps — that API surface is effectively the manager-service contract for those three.

## Open questions

1. **State store.** Postgres (current admin), Redis (current MotionStatus), Coordinator Raft (B′ style), or a new manager-private store? Affects HA + migration cost.
2. **Schema lift-and-shift.** Move `ScheduleV2` / `FlexSchedule` / `Calendar` into the manager's domain, or keep admin as system-of-record and have manager subscribe? Brainstorm proposes a new `watch` / `calendar_set` / `watch_subscription` schema — does the manager own that? See [[2026-05-29_watch-manager-migration-plan]] phases M4–M5.
3. **Cron tick frequency vs. arm-now latency.** Option-B runner has 30–60s tick; manual-override "arm now" UX wants sub-second. Push-vs-poll for transitions. SLO targets in [[2026-05-29_watch-manager-observability]].
4. ~~**Migration plan from Django-Q.**~~ **Resolved** — see [[2026-05-29_watch-manager-migration-plan]] (5-phase shadow-read → dual-write → manager-primary → decommission → schema migration).
5. **`connector_deployer` future.** Keep as K8s gateway (manager talks to it), absorb its responsibilities into the manager, or retire it entirely? Migration phase M1–M3 keeps it; phase M4+ may absorb.
6. **Per-Watch granularity vs. per-site reality.** Today one connector pod serves all of a customer's products; the brainstorm's [[watch-entity|Watch]] model would split products into separate Watches with potentially different schedules. Does that mean N pods per site, or one pod handling N internal Watches with per-product enable gates?
7. **[[sharding|Sharding]] interplay.** `ChunkedSiteManager` shard children must subscribe to arm/disarm signals post-fork. Manager pushes to pod (e.g. SNS topic per pod); pod fans out to shards via shared memory or inotify on a state file.
8. ~~**Operating Modes vs. [[watch-entity|Watch]].**~~ **Resolved by [[2026-05-29_watchman-prds-summary|PRD v2]]** — Modes are site-level Site-Supervisor state, orthogonal to [[watch-entity|Watch]] arming. See [[2026-05-29_site-supervisor-vs-watch-manager]] for the manager↔Site Supervisor relationship.
9. **Site Supervisor ↔ Manager relationship.** Recommended: Option II (two daemons, manager upstream as armed-state source of truth, Site Supervisor as tenant for mode-aware hot-reconfigure). See [[2026-05-29_site-supervisor-vs-watch-manager]].
10. **Hot-reconfigure mechanism for the connector.** Constraint #3 must be relaxed under [[watchman-repo|Watchman]]. Net-new workstream; not part of this manager-service design directly.
11. **Kafka vs. SQS for inter-agent transport.** Under [[watchman-repo|Watchman]], the agent layer uses Kafka. Manager's billing-event subscription (touchpoint T17) needs a bridging migration. See [[2026-05-29_watch-manager-migration-plan]].

## Recommended path

For *this* fleet, the highest-payoff manager design is **a fleet-singleton controller that absorbs C/E/B′'s coordinators** (Assignment Controller + Site Context Service + Blob Coordinator → one FleetCoordinator). Proposals A/B/D each need a net-new manager that does roughly the same job; consolidating on the C+E+B′ pattern is cheaper than designing the manager three more times. The brainstorm's Option B runner is the scheduling-layer instantiation of this same controller.

Two follow-ups before further design:
1. Resolve the brainstorm's "v9-v10 architecture summary" and "existing override-service" references with the doc author (premise pointers, not concepts).
2. Ingest the unread [[watchman-repo|Watchman]] PRD v2 (PM/478019585) and Agent Specs (PM/482344961) — likely contain the user-facing model this builds on.
