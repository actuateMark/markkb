---
title: Watchman Scheduling Brainstorm — Correlation with Current Fleet
author: kb-bot
created: 2026-05-28
updated: 2026-05-28
topic: fleet-architecture
type: synthesis
tags: [watchman, scheduling, fleet-architecture, override, calendar, arming]
related:
  - "[[topics/fleet-architecture/_summary]]"
  - "[[topics/watchman/_summary]]"
  - "[[topics/admin-api/notes/syntheses/2026-05-13_customer-model-dissection]]"
  - "[[topics/fleet-architecture/notes/concepts/config-and-schedule-propagation]]"
confluence: "https://actuate-team.atlassian.net/wiki/spaces/PM/pages/601686018"
incoming:
  - topics/fleet-architecture/notes/syntheses/2026-05-28_fleet-rearch-briefing-overview.md
  - topics/fleet-architecture/notes/syntheses/2026-05-28_watch-management-service-design.md
  - topics/fleet-architecture/notes/syntheses/2026-05-29_watch-manager-migration-plan.md
  - topics/personal-notes/notes/daily/2026-05-28.md
  - topics/watchman/notes/concepts/calendar-set.md
  - topics/watchman/notes/concepts/watch-entity.md
  - topics/watchman/notes/syntheses/2026-05-28_watch-management-service-index.md
  - topics/watchman/notes/syntheses/2026-05-29_watchman-judge-immix-integration.md
  - topics/watchman/notes/syntheses/2026-05-29_watchman-prds-summary.md
incoming_updated: 2026-05-30
---

# Watchman Scheduling Brainstorm — Correlation with Current Fleet

Source: Confluence PM/601686018 "[[watchman-repo|Watchman]] Scheduling — Brainstorm" (2026-05-27).

The brainstorm pins down a **customer-facing data model** for scheduling — `Watch = (site, cameras[], product)` runtime entities subscribing to shared `calendar_set` rows (kind=`base` | `suppress`), with manual overrides (NOT NULL `expires_at`) and IANA timezones stored on the [[watch-entity|Watch]]. Two implementation options compared: (A) EventBridge-per-event with `watch_event_runtime.is_in_window` bits, (B) Runner tick (~30–60s) computing armed state as a pure function.

## Premises the doc asserts vs. fleet reality

| Doc premise | Today | Conflict |
|---|---|---|
| "Iteration on v9-v10 architecture summary scheduling" | No `v9` / `v10` doc in KB; fleet-architecture iterations are A/B/C/D/E + B′ | **Premise unresolved.** Need source link from author. |
| "Matches existing `override-service`" | No discrete service. Constellation of `Customer.current_schedule_override_start/_end` + Django-Q `override_timer.py` + `schedule_deployer.py` in [[actuate_admin]] | **Premise misleading.** Anyone reading the brainstorm and looking for `override-service` will find nothing. |
| `Watch = site × cameras[] × product` runtime entity | No analog. Today: `customer.cameras[].streams[].features[]`. Product is bound **per-stream** as a `StreamDeploymentConfig` (`actuate-config/.../stream_deployment_config.py`); one stream can run N feature deployments simultaneously. There is no first-class aggregation across cameras for a single product. | **New abstraction.** A [[watch-entity|Watch]] projects onto a *filter* over `(stream, feature_deployment)` tuples — workable, but the join needs to be built. |
| IANA timezone stored on the [[watch-entity|Watch]] | `Customer.timezone` already exists; one tz per site | **Compatible.** [[watch-entity|Watch]].timezone is just denormalized from site. |
| Manual override has explicit `expires_at` NOT NULL | `Customer.current_schedule_override_start/_end` are nullable | **Compatible upgrade** — schema tightening, matches the brainstorm's "no permanent flip via this path" rule. |
| Armed / disarmed is a real concept | **Does not exist at the connector layer.** No `arm`/`disarm`/`is_active`/time-of-day gate inside vms-connector. The pod-runs-or-doesn't is the only gate. Arming logic lives upstream ([[actuate_admin]] scheduler service) and manifests as cronjob existence / settings reload | **Largest gap.** The brainstorm's whole model assumes a runtime that can flip a [[watch-entity|Watch]]'s armed bit and have the data plane honor it. The connector has no insertion point for this today. |
| Suppress sets stack across Watches without per-Watch duplication | Holidays / closures today require per-customer manual override flips | **Real win** — relieves the manual-override sprawl. |
| External alarm panels consume transitions | Alarmwatch / Crosbies (ENG-125/34) already mutate arm state via API; StarFM/[[ajax-components|Ajax]] integration via Paolo | **Pattern exists, but role shifts under [[watchman-repo|Watchman]].** The brainstorm assumes Immix-shaped partner integrations as primary. Per [[2026-05-29_watchman-prds-summary|PRD v2 / Agent Specs]], [[watchman-repo|Watchman]]'s **Escalation Agent is direct-to-operator** (push/SMS/phone/email). Partner integrations become **secondary delivery channels**, not the primary path. Manager must support both during migration. |

## How "Watch" projects onto current connector internals

A [[watch-entity|Watch]] `(site, cameras[], product)` is not a config object — it is a **predicate** over existing structures:

```
applicable_streams(watch) =
  { (camera, stream, feature_deployment)
    | camera.camera_id ∈ watch.cameras
      ∧ check_for_plus(feature_deployment.model_name) == watch.product }
```

Today the connector iterates `feature_deployments` unconditionally in `base_stream_camera.py:132,263,267,287`. The minimum-viable disarm gate is one `if`:

- **Cheapest:** `base_stream_camera.py:915-935` and `:1045-1106` — alert dispatch loop, already keyed by `product_name`. Suppress alert emission for disarmed `(stream, product)`.
- **CPU-saving:** skip `PipelineFactory.build_post_processing_subpipeline()` for disarmed pairs at startup; requires rebuild on arm flip.
- **Billing invariant:** `site_product_ended` must still fire on every exit path regardless of armed state (see CLAUDE.md "billing-event lifecycle invariant"). Disarmed ≠ unbilled.

The connector has **no mechanism today** to receive an out-of-band arm/disarm signal. Options:
1. Settings reload (current path for almost everything, but slow / coarse).
2. New subscriber inside `SiteManager` to the brainstorm's SNS/EventBridge transitions topic. [[sharding|Sharding]] complication: `ChunkedSiteManager` forks pre-arm-listener; the listener must start post-fork in `AnalyticsSiteManager.run()` (see CLAUDE.md fork-safety rules).
3. Periodic DB poll (Option B fits this naturally — the runner already writes the truth; connectors read it).

## Runtype applicability

| Runtype | Fit | Notes |
|---|---|---|
| `default` (realtime) | Cleanest | Per-`(camera, product)` arm/disarm is the natural [[watch-entity|Watch]] model. Currently the only knob is pod up/down. |
| `healthcheck` (VCH) | Reduced | Cronjob *is* the schedule. [[watch-entity|Watch]] reduces to "include camera in tick's roster." |
| `autopatrol` | Reduced | Same as VCH. The VCH/AP `schedule_id` (`autopatrol_site_manager.py:190`) is already an opaque scheduler-side ID but is not used for gating, just billing. |
| `local`, `gauntlet` | N/A | Dev/batch. |

## Option A vs. B — where each pinches in this fleet

**Option A (EventBridge-per-event):**
- Quota math: `N_watches × M_events_per_set × 2`. Fleet today has ~1000s of cameras × ~3-5 products avg. If product-decomposed Watches reach ~5k and a popular suppress set is shared by all, you stay well under the 1M default. Manageable, but worth a capacity model.
- Cold-start gap (newly created [[watch-entity|Watch]] reads `armed=false` until first cron fires) is the textbook reproduction of [[topics/admin-api/notes/syntheses/2026-05-13_customer-model-dissection]]'s **ENG-96 midnight race**, just framed differently. Backfill self-heal needed.
- DB ↔ AWS reconciliation is new operational surface. We don't currently own per-resource cloud-state reconcilers.

**Option B (Runner tick):**
- Centralizes evaluation in one process — **directly resolves ENG-96** by removing per-pod schedule reads. This is what [[topics/fleet-architecture/notes/syntheses/2026-04-22_proposal-b-prime-stateless-with-coordinator]] proposes at the fleet-arch level. Option B is the scheduling-layer instantiation of B′.
- 30–60s transition latency is acceptable for a security product armed at the minute granularity but is worse than EventBridge for "arm now" UX. Mitigation: manual-override path can short-circuit the tick (write + push notification to a watchers fanout).
- No AWS schedule fan-out, no quota, no reconciliation, no orphan cleanup. Simpler operational surface; takes on uptime cost of "the runner."

## Open gaps the brainstorm doesn't cover but the fleet needs

1. **Product identity normalization.** The doc's `product` field is taken as given. Today the connector derives product identity from `model_name` via `check_for_plus()` (`connector_factories/shared/base_connector_factory.py`). The [[watch-entity|Watch]] needs to either store the canonical product ID or the model_name set it covers — clarify before schema design.
2. **Sharding-aware transition delivery.** The transitions topic (Option B's outward SNS or Option A's Lambda-fan-out) lands at the pod, but cameras are partitioned across shard subprocesses by `ChunkedSiteManager`. The pod-level subscriber needs to fan out to shards (pipe / shared memory / shared DB poll). Naïve `threading.Thread` in `__init__` will die in the fork (see CLAUDE.md fork-safety, `[[fork-safety-check]]`).
3. **Connector-side gate insertion point.** Either alert-dispatch suppression (cheapest, preserves billing) or subpipeline build-time filter (CPU saving, requires rebuild on flip). Decision impacts the SLA on "arm now" UX.
4. **Migration from Django-Q chain.** `actuate_admin/schedule_processor.py + override_timer.py + schedule_deployer.py` (mark-todos §14, race condition) is the de facto current scheduler. Brainstorm assumes a clean-slate model; needs a migration plan that doesn't drop existing customer schedules.
5. **[[watchman-repo|Watchman]] PRD v2 / Agent Specs (PM/478019585, PM/482344961) are unread in KB** and likely contain the user-facing scheduling design the brainstorm builds on. Ingest before further design rounds.

## Recommendation (one-paragraph)

The brainstorm's data model ([[watch-entity|Watch]] + shared calendar_set + manual_override) is well-shaped and orthogonal to the implementation choice. Option B is the better fit for *this* fleet: it directly resolves ENG-96, avoids a new cloud-state reconciliation surface we don't currently own, and aligns with the [[topics/fleet-architecture/notes/syntheses/2026-04-22_proposal-b-prime-stateless-with-coordinator|B′ coordinator pattern]] we're already designing toward. The two follow-ups before any code: (a) get the "v9-v10 summary" and "override-service" pointers from the doc author so premises stop being unresolved, and (b) decide where in the connector data plane the armed gate lands — alert-dispatch is the cheapest, billing-safe insertion point.
