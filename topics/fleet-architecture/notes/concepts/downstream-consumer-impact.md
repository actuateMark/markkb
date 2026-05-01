---
title: "Downstream Consumer Impact — Watchman, AutoPatrol, CHM, Alert Integrations"
type: concept
topic: fleet-architecture
tags: [watchman, autopatrol, chm, downstream, consumers, alerts, events]
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
  - topics/fleet-architecture/notes/syntheses/2026-04-22_frame-storage-design-deltas.md
  - topics/fleet-architecture/notes/syntheses/2026-04-22_proposal-b-prime-stateless-with-coordinator.md
incoming_updated: 2026-05-01
---

# Downstream Consumer Impact

The connector is not an island. Three product platforms ([[watchman/_summary|Watchman]], [[knowledgebase/topics/autopatrol/_summary|AutoPatrol]], [[camera-health-monitoring/_summary|CHM]]) and 20+ monitoring-center integrations consume its output. Any fleet architecture must preserve those contracts — or explicitly renegotiate them. This note catalogs what each consumer depends on, and what each proposal changes from their perspective.

## The contracts today

| Consumer | Input contract | Source |
|----------|----------------|--------|
| [[watchman-repo|Watchman]] | Event stream (confirmed detections with metadata + frame clips in S3) | [[watchman/_summary]] |
| AutoPatrol | Frame pulls via `AutoPatrolConnectorFactory`; alerts via `AutoPatrolAlertSender` | [[knowledgebase/topics/autopatrol/_summary]] |
| CHM | Healthcheck frames, camera connectivity status, scene-change detection | [[camera-health-monitoring/_summary]] |
| Immix and 20+ integrations | SQS FIFO per integration with alert envelopes, SMTP+clip attachments | [[actuate-libraries/notes/entities/actuate-alarm-senders]], [[actuate-platform/notes/concepts/sns-sqs-fanout-pattern]] |

## Per-proposal impact on downstream consumers

### A — Minimal Split
- **[[watchman-repo|Watchman]]:** no change — events still emitted by pipeline worker, SNS→SQS path unchanged.
- **AutoPatrol:** `AutoPatrolConnectorFactory` moves into extracted puller fleet; same API surface for AutoPatrol side.
- **CHM:** healthcheck pipeline runs today inside the connector as a separate pipeline type. Does it stay with the pipeline worker or move to the puller? **Open question.** Default assumption: stays with pipeline worker.
- **Alert integrations:** unchanged — same SQS FIFO queues.
- **Migration signal:** zero customer-visible change if done right.

### B — Stage Fleets
- **[[watchman-repo|Watchman]]:** events emitted by Observer fleet. Contract itself unchanged but timing may shift (observer is 4 hops deep).
- **AutoPatrol:** frame pulls still happen in puller fleet; alerts via dedicated alert-dispatch fleet.
- **CHM:** healthcheck pipeline type's mapping to stages is non-obvious. Healthcheck frames may skip some stages (no motion, no inference for static-connectivity check). **Needs design work** — likely a shorter pipeline path.
- **Alert integrations:** unchanged — same SQS FIFO queues from alert-dispatch fleet.
- **Migration signal:** potentially measurable latency shift (4 hops) — CHM scene-change detection may need to re-tune thresholds.

### C — Camera-Worker
- **[[watchman-repo|Watchman]]:** events emitted from worker pods — contract unchanged.
- **AutoPatrol:** this is the trickiest consumer. `AutoPatrolConnectorFactory` today assumes site-scoped lifecycle. Cameras reassigning across workers means patrol sessions migrate. **May break AutoPatrol's session state** — need to audit.
- **CHM:** healthcheck frames pulled per-camera fine; scene-change state is per-camera already (matches [[blacklist-filter-locality|per-camera state finding]]).
- **Alert integrations:** unchanged.
- **Migration signal:** AutoPatrol is the biggest integration concern.

### D — Event-Driven
- **[[watchman-repo|Watchman]]:** events from observer fleet. S3 ref pattern means frame clips might land in a different bucket (or S3 Express bucket) — [[watchman-repo|Watchman]] may need to know about it. **Audit frame-URL construction** in Watchman and the connector's clip-generation path.
- **AutoPatrol:** frame pulls via puller fleet.
- **CHM:** healthcheck has an NATS-subject of its own, or bypasses the bus.
- **Alert integrations:** unchanged.
- **Migration signal:** clip storage location change needs Watchman coordination.

### E — Hybrid Sidecar
- **Watchman:** events from detection core fleet. Unchanged contract.
- **AutoPatrol:** smart puller handles patrol; AutoPatrolConnectorFactory moves into smart puller — same pattern as A.
- **CHM:** healthcheck runs in smart puller alongside FDMD. Potential synergy — motion detection primitives already useful to CHM for scene-change.
- **Alert integrations:** alert-dispatch fleet change is transparent to integrations (same SQS FIFO queues).
- **Migration signal:** minimal for downstream; E plays nicely with existing consumers.

## AutoPatrol — shared concern across B, C, D

[[knowledgebase/topics/autopatrol/_summary]] — AutoPatrol runs as **CronJobs** in today's setup, sharing deployment with vms-connector. The cron-job pattern is orthogonal to the always-on pipeline. Questions for any proposal:

- Does AutoPatrol become its own fleet (parallel to the regular puller fleet)?
- Can AutoPatrol reuse the new puller fleets (B/D/E) or does it stay separate?
- If a puller restart loses AutoPatrol session state mid-patrol, is that acceptable? (Today: restart at site level kills patrol.)

**Recommendation for every proposal's PoC:** explicitly validate that one autopatrol job completes end-to-end in the new architecture before declaring the PoC successful. Easy to overlook; [[watchman-repo|Watchman]] is coming and AutoPatrol feeds it.

## CHM — cross-cutting dependency on frame pulls

[[camera-health-monitoring/_summary]] consumes healthcheck frames and runs a scene-change detector. Today these frames flow through the same pipeline path as production frames but with a `healthcheck` pipeline type. In any fleet redesign:

- Smart pullers (E) or extracted pullers (A/B/D) must still emit healthcheck frames
- Observer state for scene-change detection is per-camera (safe to co-locate with detection core in E, or spread in C)
- Scene-change alerts use a distinct sender class (`SysAidAlertSender`) — alert-dispatch fleet must route correctly

## Immix and other integrations — the alert SPOF

20+ integrations receive alerts via per-integration SQS FIFO queues ([[actuate-platform/notes/concepts/sns-sqs-fanout-pattern]]). Alert senders include SMTP (Immix), HTTP webhooks, Milestone event injection, [[bold-components|Bold]] API, Patriot API, and more. Every proposal preserves this contract — the SNS→SQS fan-out stays as-is. What changes is **who** publishes the SNS event:

- A: pipeline worker → SNS
- B, D: observer fleet → SNS
- C: worker pod → SNS
- E: detection core → SNS → alert dispatch fleet (adds one hop for routing)

**ENG-66** (alert-sender thundering herd) is addressed by proposals B/D/E because alert dispatch becomes its own autoscaled fleet rather than shared with the pipeline. C partially addresses it via worker count autoscaling. A extracts alert-sender independently — direct ENG-66 fix.

## Enhancement opportunities

- **Formalize the event-envelope schema.** Today it's ad-hoc between SNS publishers and SQS consumers. Each proposal must ensure [[watchman-repo|Watchman]] and AutoPatrol get the same envelope they expect — a formalized schema + versioning would prevent silent drift. Worth doing before any proposal lands.
- **Provide a frame-lifecycle API.** Today clip URLs are constructed by the connector and read by [[watchman-repo|Watchman]]. Proposal D might change where they live. Abstract behind a frame-lifecycle service to decouple frame location from consumer code.
- **Extend CHM's scene-change detector to reuse FDMD.** Proposal E extracts FDMD as a standalone library — CHM's scene-change detector could consume the same primitive, reducing duplication.

## References

- [[watchman/_summary]]
- [[knowledgebase/topics/autopatrol/_summary]]
- [[camera-health-monitoring/_summary]]
- [[actuate-libraries/notes/entities/actuate-alarm-senders]]
- [[actuate-platform/notes/concepts/sns-sqs-fanout-pattern]]
- [[actuate-platform/notes/syntheses/how-a-frame-becomes-an-alert]]
