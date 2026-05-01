---
title: "Library Decomposition — What Changes in actuate-libraries per Proposal"
type: concept
topic: fleet-architecture
tags: [actuate-libraries, decomposition, pipeline, filters, observers, fdmd, monorepo]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
incoming:
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/concepts/frame-storage-current-state.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-a-minimal-split.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-b-stage-fleets.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-c-camera-worker.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-d-event-driven.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-e-hybrid-sidecar.md
  - topics/fleet-architecture/notes/syntheses/2026-04-22_proposal-b-prime-stateless-with-coordinator.md
  - topics/fleet-architecture/reading-list.md
incoming_updated: 2026-05-01
---

# Library Decomposition Required

The 41-package UV monorepo ([[actuate-libraries/_summary]]) is today organized for a single-process pipeline. Each fleet proposal forces different library surgery. This note catalogs the work per proposal, grounded in the existing dependency topology ([[actuate-libraries/notes/concepts/dependency-graph]]).

## The 7 library groups (from [[actuate-libraries/_summary]])

1. **Core processing** — `actuate-pipeline`, `actuate-pipeline-objects`, `actuate-filters`, `actuate-inference-objects`, `actuate-threadpool`, `actuate-botsort`, `actuate-filterpy`
2. **Camera/stream** — `actuate-pullers`, `actuate-camera-objects`, `actuate-healthcheck-objects`, ...
3. **AI/inference** — `actuate-inference-client`, `actuate-models`, ...
4. **Integration/alerting** — `actuate-alarm-senders`, `actuate-connector-observers`, ...
5. **Config/data** — `actuate-config`, `actuate-daos`
6. **Health/monitoring** — `actuate-healthcheck`, ...
7. **Utilities** — `actuate-log`, ...

## Decomposition required per proposal

### A — Minimal Split
- **Extract:** `actuate-pullers` wired to Redis Streams producer (new client)
- **Extract:** `actuate-alarm-senders` wired to SQS consumer
- **Create:** `actuate-redis-streams` (new thin wrapper — no such lib exists)
- **Unchanged:** `actuate-pipeline`, `actuate-filters`, `actuate-connector-observers`, `actuate-botsort`
- **Risk:** low — leaf libraries only

### B — Stage Fleets
- **Split `actuate-filters`:** stateless filters (`label`, `confidence`, `zone`, `iou`) move to detector fleet; stateful filters (`stationary`, `blacklist`) move to observer fleet
- **Split `actuate-pipeline`:** current chain-of-responsibility must work across service boundaries — extract step-registration into `actuate-pipeline-runtime` (each stage loads only its steps)
- **Extract:** `actuate-connector-observers` into observer fleet
- **Create:** `actuate-redis-streams`, `actuate-otel-instrumentation`, `actuate-inference-coord` (if we take that option)
- **Risk:** high — touches the most-depended-on libraries

### C — Camera-Worker
- **Unchanged libs:** `actuate-pipeline`, `actuate-filters`, `actuate-connector-observers` — all in-process, as today
- **Create:** `actuate-assignment-controller` (new service) + `actuate-assignment-client` (worker-side SDK)
- **Create:** `actuate-redis-streams` (for leases + tracker snapshots)
- **Enhance:** `actuate-pullers` universal-image mode — lazy-load adapters on assignment
- **Risk:** moderate — assignment primitives are greenfield

### D — Event-Driven
- **Split `actuate-filters`:** same as B (stateless→detector, stateful→observer)
- **Create:** `actuate-nats-jetstream` (client wrapper), `actuate-s3-frame-ref` (ref-pattern helper on top of existing `actuate-daos` S3DAO), `actuate-fdmd-puller` (FDMD-in-puller mode)
- **Enhance:** `actuate-daos` S3DAO with S3 Express One Zone support
- **Risk:** high — new infra + filter chain split

### E — Hybrid Sidecar
- **Extract:** FDMD (currently inside `actuate-pipeline` `MotionDetectionStep`) into standalone `actuate-fdmd` that the smart puller can consume
- **Create:** `actuate-redis-streams`, `actuate-site-context` (config/schedule/camera registry service + client)
- **Unchanged:** `actuate-pipeline`, `actuate-filters`, `actuate-connector-observers`, `actuate-botsort` — detection core runs the full chain
- **Split `actuate-alarm-senders`:** remains used by Alert Dispatch fleet; MultiAlertSender orchestrator stays a library
- **Risk:** moderate — FDMD extraction is invasive but mechanical

## Shared new libraries (>1 proposal)

| New lib | A | B | C | D | E |
|---------|:-:|:-:|:-:|:-:|:-:|
| `actuate-redis-streams` | ✅ | ✅ | ✅ | | ✅ |
| `actuate-otel-instrumentation` | | ✅ | | ✅ | |
| `actuate-assignment-controller` | | | ✅ | | |
| `actuate-site-context` | | | | | ✅ |
| `actuate-fdmd` (standalone) | | | | ✅ | ✅ |
| `actuate-nats-jetstream` | | | | ✅ | |

`actuate-redis-streams` is the most-shared — 4 of 5 proposals need it. **Recommended:** build it early as a dependency of whichever PoC starts first.

## Filter chain split — the hard shared problem (B, D)

Proposals B and D both require splitting `actuate-filters` by state dependency. Inventory:

| Filter | State | Proposed home |
|--------|-------|---------------|
| LabelFilter | stateless | Detector |
| ConfidenceFilter | stateless | Detector |
| ZoneFilter | stateless (polygon intersect) | Detector |
| IgnoreZonesFilter | stateless | Detector |
| IOUFilter | stateless (current frame only) | Detector |
| StationaryFilter | stateful (cooldowns, per-camera history) | Observer |
| BlacklistFilter | stateful (R-tree per camera) | Observer |

Blacklist locality is [[blacklist-filter-locality|already verified]] — camera-scoped.

## Enhancement opportunities

- **Formalize filter state-dependency in metadata.** Each filter class could declare `is_stateless: bool` — a fitness function ([[2026-04-16_architecture-enforcement|Architecture Enforcement]]) could enforce it. Would make the B/D split mechanical.
- **Extract connector-factories into a runtime registry.** [[vms-connector/notes/concepts/connector-factory]] — today's `generate_site()` pattern bundles integration dispatch with deployment wiring. For C's universal image and E's smart puller, we want dispatch-only. Factor out.
- **Inventory and deprecate dead libraries.** 41 packages includes some leaves with few callers. Pre-migration cleanup reduces churn surface.

## References

- [[actuate-libraries/_summary]]
- [[actuate-libraries/notes/concepts/dependency-graph]]
- [[actuate-libraries/notes/concepts/filter-architecture]]
- [[actuate-libraries/notes/concepts/observer-pattern]]
- [[actuate-libraries/notes/entities/actuate-alarm-senders]]
- [[vms-connector/notes/concepts/connector-factory]]
