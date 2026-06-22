---
title: Watch Manager — Touchpoint Catalog (T1–T18)
author: kb-bot
created: 2026-05-29
updated: 2026-05-29
topic: fleet-architecture
type: concept
tags: [watchman, fleet-architecture, manager-service, touchpoint-catalog]
related:
  - "[[2026-05-28_watch-management-service-design]]"
  - "[[2026-05-29_watch-manager-observability]]"
  - "[[2026-05-29_ait-watch-manager-integration]]"
incoming:
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/concepts/cardinality-decision.md
incoming_updated: 2026-05-30
---

# Watch Manager — Touchpoint Catalog (T1–T18)

Eighteen touchpoints the [[watch-entity|Watch]] Management Service must own or invoke. Promoted from [[2026-05-28_watch-management-service-design]] to a concept note so per-proposal addenda and downstream notes can reference by ID (e.g. "covered by T4 + T16").

## Schedule / state surface

- **T1.** [[watch-entity|Watch]] directive intake — calendar_set evaluation result → desired armed state.
- **T2.** Manual override entity with explicit `expires_at NOT NULL`, replacing Redis `MotionStatus.manual_start/_stop` (which is ephemeral; flushing Redis loses every active override).
- **T3.** Schedule re-derivation on DST + day-boundary, replacing `schedules_redeploy` + `was_redeployed_today` Redis flag.
- **T4.** `image_tag_override_expires_at` per [[watch-entity|Watch]] — read every reconcile, replacing `expire_custom_branches.py` cron.
- **T5.** Single source of truth for "is (site, camera, product) armed right now?" without join-at-read.

## K8s lifecycle

- **T6.** Per-Watch Deployment + VPA create/delete, replacing `ConnectorController.start_connector / stop_connector`.
- **T7.** Per-Watch CronJob set for VCH + AP, replacing `AutoPatrolSchedule.deploy/undeploy` and `Healthcheck.handle_healthcheck_cronjob`. **Sunset under [[watchman-repo|Watchman]]** — Patrol Agent absorbs AP scheduling.
- **T8.** Centralized schedule derivation — pull `__make_chm_schedule`, `__make_vch_schedule`, `__adjust_cron_expression` into manager so admin doesn't author cron strings.
- **T9.** Wire arm/disarm to `replicas: 0/1` or CronJob `suspend: true` instead of full delete/create — preserves history, avoids cold-start image pulls. (Today the deployer has no `/scale` endpoint; this would require either deployer extension or manager-direct K8s API access.)
- **T10.** Reconcile loop — observed K8s state is source of truth; eliminate `is_arming` flags that drift.
- **T11.** Decide gateway vs. direct K8s API — keep `connector_deployer` as the K8s gateway (and become its only client) OR talk K8s directly.

## Pod lifecycle

- **T12.** Wait-for-ready — poll `connector_ready.txt` or first `connector ready` log line (`connector.py:313`).
- **T13.** Coordinate graceful teardown — issue SIGTERM, [[watch-entity|watch]] for `site_product_ended` SQS confirm per `(camera, product)` before tearing down next [[watch-entity|Watch]] resource.
- **T14.** Honor `DEPLOYMENT_ID` env (`connector.py:220`) as the only manager→pod identity handle; `settings.json` on S3 keyed by it.
- **T15.** Don't double-fire `start_patrol/end_patrol` — connector owns the Immix patrol state machine. **Sunset under [[watchman-repo|Watchman]]** alongside T7.

## Reconciliation / observability

- **T16.** Periodic K8s-API resync — manager state vs. actual `kubectl get`; fix orphans, missed creates, partial deletes.
- **T17.** Billing-event subscription — SQS (today) / Kafka (under [[watchman-repo|Watchman]]) `site_product_started`/`site_product_ended` is the manager's "did the workload actually run" oracle.
- **T18.** Audit log — every [[watch-entity|Watch]] state transition + every K8s mutation to ClickHouse with who/what/when/why. Expanded in [[2026-05-29_watch-manager-observability]].

## Coverage matrix (which proposals natively cover which touchpoints)

| TP | A | B | C | D | E | B′ | Notes |
|---|---|---|---|---|---|---|---|
| T1 | + | + | + | + | + | + | All proposals need armed-state intake |
| T2 | + | + | + | + | + | + | Universal — replaces Redis ephemeral |
| T3 | + | + | ++ | + | ++ | ++ | C/E/B′ have centralized schedule eval |
| T4 | + | + | + | + | + | + | All proposals — image tag is per-Watch |
| T5 | + | + | ++ | ++ | ++ | ++ | C/E/B′ controller is the source-of-truth; D's JetStream KV serves the same |
| T6 | + | + | + | + | + | + | Universal K8s primitive ownership |
| T7 | + | + | + | + | + | + | All proposals own VCH/AP lifecycle (or sunset it) |
| T8 | + | + | ++ | + | ++ | ++ | Coordinator-bearing proposals natively centralize cron derivation |
| T9 | – | + | + | + | + | + | A's K8s shape doesn't change; T9 is harder there |
| T10 | + | + | ++ | + | ++ | ++ | C/E/B′ already reconciler-shape |
| T11 | + | + | + | + | + | + | All proposals decide independently |
| T12 | + | + | + | + | + | + | Universal readiness probe |
| T13 | + | + | + | + | + | + | Universal SIGTERM coordination |
| T14 | + | + | + | + | + | + | Universal |
| T15 | + | + | + | + | + | + | Universal (sunsetting under [[watchman-repo|Watchman]]) |
| T16 | + | ++ | ++ | ++ | ++ | ++ | A's smaller K8s surface = smaller reconcile job |
| T17 | + | + | + | ++ | + | + | D's JetStream pipe = native fit |
| T18 | + | + | + | ++ | + | ++ | D's JetStream + B′'s Raft give audit a native home |

Legend: `+` = covered by the proposal's standard machinery; `++` = the proposal's design is *especially well-suited* to this touchpoint; `–` = the proposal is awkward for this touchpoint.

## Hooks (instrumentation, from [[2026-05-29_ait-watch-manager-integration]])

The catalog above is what the manager *does*. The 12 instrumentation hooks at [[2026-05-29_ait-watch-manager-integration]] are what the manager *exposes* to make T17 + T18 observable and AIT-testable. Hooks 1–4 (transition events, idempotency keys, reconcile telemetry, pure-function eval seam) cover the highest-leverage observability + testing overlap.

## Cross-references

- [[2026-05-28_watch-management-service-design]] — origin of the catalog
- [[2026-05-29_watch-manager-observability]] — T18 expanded; metrics + traces + audit
- [[2026-05-29_watch-manager-failure-modes]] — what happens when each touchpoint fails
- [[2026-05-29_ait-watch-manager-integration]] — test fixtures keyed against these touchpoints
