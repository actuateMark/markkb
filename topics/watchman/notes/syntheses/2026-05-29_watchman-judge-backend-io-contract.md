---
title: Watchman Judge ⇔ Backend I/O Contract — Analysis & Correlation
author: kb-bot
created: 2026-05-29
updated: 2026-05-29
topic: watchman
type: synthesis
tags: [watchman, judge-agent, assessment-agent, io-contract, integration, fleet-architecture, immix]
related:
  - "[[topics/watchman/_summary]]"
  - "[[2026-05-29_watchman-prds-summary]]"
  - "[[2026-05-28_watch-management-service-design]]"
  - "[[2026-05-28_watch-management-service-index]]"
  - "[[2026-05-29_watchman-judge-immix-integration]]"
source: "_research-inbox/2026-05-29_watchman-judge-backend-io-contract-source.md"
incoming:
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/syntheses/2026-05-28_fleet-rearch-briefing-overview.md
  - topics/fleet-architecture/notes/syntheses/2026-06-01_adr-watchman-mvp-slim-connector.md
  - topics/watchman/_summary.md
  - topics/watchman/notes/syntheses/2026-05-28_watch-management-service-index.md
  - topics/watchman/notes/syntheses/2026-05-29_watchman-judge-immix-integration.md
incoming_updated: 2026-06-02
---

# Watchman Judge ⇔ Backend I/O Contract — Analysis & Correlation

## TL;DR

The source doc (`WATCHMAN_BACKEND_IO_CONTRACT.md`) is **sound as a slice but mislabeled and missing context**. It defines wire protocol for **one** [[watchman-repo|Watchman]] agent — the judge/assessment loop — using pipeline → SQS → judge → SNS → fan-out. Architecturally clean (queues between machines, WebSocket to the human) but the doc uses "[[watchman-repo|Watchman]]" ambiguously against the PRD's 10-agent platform, doesn't carry [[watch-entity|Watch]] entity context, and conflicts with the PRD's Kafka inter-agent bus assumption. Eight recommendations below; six are concrete schema/naming asks, two are platform decisions.

Source preserved at `_research-inbox/2026-05-29_watchman-judge-backend-io-contract-source.md`.

## Decisions captured from review (2026-05-29)

| # | Question | Decision | Rationale |
|---|---|---|---|
| 1 | Hook point in connector | **Post-observer/window confirmed alert** (today's alert path) | Lower volume; schema needs product context not raw `yolo_class`; arming enforcement happens connector-side (disarmed pods don't fire) |
| 2 | [[watch-entity|Watch]] entity in schema | **Add `watch_id` to input + output** | Lets judge dispositions join cleanly to manager audit log + billing; one-line schema change |
| 3 | Kafka vs SQS/SNS transport | **Open question — document the conflict** | Platform-level decision beyond the judge contract; bring to inter-agent-bus owner |
| 4 | Contract naming | **Recommend rename to "[[watchman-repo|Watchman]] Judge ⇔ Backend I/O Contract"** | Disambiguates from [[watchman-repo|Watchman]] the platform; matches existing `Watchman/agents/judge_agent.py` code |
| 5 | Latency budget reconciliation | **Flag as conflict needing resolution** | PRD says sub-10s detection-to-notification; doc says ~6–12s. Need per-hop budget breakdown |
| 6 | Immix in the fan-out | **Separate concern — captured in [[2026-05-29_watchman-judge-immix-integration]]** | Not part of judge contract scope |
| 7 | Underspecified fields | **Flag each with a concrete proposal** | `sequence_id`, `descriptor`, `yolo_class` vs `product` |

## What the doc actually defines

A wire-protocol between three layers:

1. **Pipeline → Judge** via SQS standard queue (fire-and-forget, metadata-only message, frames stay in S3)
2. **Judge → fan-out** via SNS publish → SQS-per-consumer (Django operator app, Immix, audit log)
3. **Django → operator** via WebSocket (live UI push)

Disposition vocabulary: `escalate_immediate`, `escalate_review`, `auto_clear_normal`, `auto_clear_fp`, `suppress_low_value`.

This is the **assessment loop** — one of the ten PRD agents. It does NOT cover:
- [[watch-entity|Watch]] lifecycle (arm/disarm, schedule) — that's the [[2026-05-28_watch-management-service-design|Watch Management Service]]
- Operating Modes (Patrol/Active) — that's the Site Supervisor Agent ([[2026-05-29_site-supervisor-vs-watch-manager]])
- Site rhythm / schedule-aware context — that's the Site Context Agent
- Patrol orchestration — that's the Patrol Agent
- Escalation delivery (push/SMS/phone/email) — that's the Escalation Agent (downstream of this contract's Django output)
- Stream-health monitoring + NVR-playback fallback — that's the Connectivity Agent
- Learning, threat, recommendations — separate agents

## Section-by-section validation

### §1 — Input (pipeline → SQS → judge)

**Sound:** SQS standard queue, fire-and-forget, `alert_id` as dedupe key, no image bytes in the message — all correct hygiene.

**Schema gaps with proposals:**

| Field | Status | Proposal |
|---|---|---|
| `alert_id` | OK | Reuse connector's existing alert event ID — it's already stable and unique |
| `site_id`, `camera_id` | OK | Match connector's `customer.connector_id` and `camera_id` |
| `alert_ts` | OK | ISO 8601 UTC; match connector's `capture_ts` semantics |
| `yolo_class` | **Rename** | → `product`. The connector emits alerts keyed by product (intruder/weapon/fire/etc.), not raw YOLO class. Today's `check_for_plus(model_name)` maps to product; pre-hook in `base_stream_camera.py:915-935` already has `product_name` in scope. |
| `yolo_confidence` | OK as-is | Inference confidence makes sense per-detection |
| `bbox: {x,y,w,h}` | **Verify** | Confirm orientation matches IDP/PDP packets in `actuate-pipeline-objects`. Today's IDPs use `xyxy` layout in some places, `xywh` in others — pick one and document. |
| `s3_prefix` | **Verify layout** | Confirm prefix matches `actuate-image-cache` / S3-frame-fallback layout: `s3://{bucket}/{prefix}/{capture_ts}/...` |
| `schema_version` | OK | Add: state explicit behavior on version mismatch (drop? warn-and-process? DLQ?) |
| **`watch_id`** | **ADD** | One-line addition. Lets judge dispositions join to manager audit log + billing without site/camera/time matching. Decision #2. |
| **`run_id`** | **ADD** | The connector emits `site_product_started/_ended` per run; alerts within a run share a `run_id`. Useful for the judge to group consecutive alerts and for billing reconciliation. |

**Hook point** (decision #1): **post-observer/window confirmed alert**. This means the publish call lives near `base_stream_camera.py:915-935` (alert dispatch loop), in a new `WatchmanJudgeAlertSender` in `actuate-alarm-senders` peered with the existing senders. Arming enforcement happens upstream — disarmed Watches emit no alerts, so the judge never sees them.

### §2 — Output (judge → SNS → consumers)

**Sound architecturally:** SNS fan-out for independent consumers is the textbook pattern.

**Schema proposals:**

| Field | Status | Proposal |
|---|---|---|
| `alert_id` | OK | Echoes input |
| `sequence_id` | **Underspecified** | Propose: `sequence_id` = **incident grouping ID minted by the judge** when consecutive alerts on the same `(site_id, camera_id, product)` within a configurable window form one human-perceived event. The judge owns the windowing. Document the windowing rule. |
| `site_id`, `camera_id` | OK | Echo input |
| `disposition` | OK | Five-value enum: `escalate_immediate | escalate_review | auto_clear_normal | auto_clear_fp | suppress_low_value` |
| `confidence` | OK as-is | Judge confidence (separate from inference confidence) |
| `summary` | OK | Human-readable; LLM-generated |
| `descriptor` | **Cross-link** | Doc references "entity descriptor, proposal §4.1.2." Locate that doc and pin a wikilink. **Action: track down §4.1.2 reference.** |
| `s3_prefix` | OK | Echo input |
| `decided_at` | OK | Judge timestamp |
| `schema_version` | OK | Same versioning rules as input |
| **`watch_id`** | **ADD** | Echo input. Decision #2. |
| **`run_id`** | **ADD** | Echo input. |

### §3 — WebSocket scoping

**Sound.** "Queues between machines, WebSocket to the human's screen" is correct. Drop on the WebSocket is recoverable (UI re-syncs); drop in the queue chain is not.

### §4 — Idempotency + DLQ

**Sound and standard.** Notable parallel to our connector's billing-event invariant (`VCHCamera._send_product_ended_events_once`) — the same exactly-once discipline applies on every queue boundary.

### §5 — Open questions

All five are real:
- **Q1 (messaging infra)** — conflicts with PRD's Kafka assumption. Decision #3: document the conflict, bring to inter-agent-bus owner.
- **Q2 (output consumers)** — three consumers (Django, Immix, audit) per the doc, but **Immix should be captured as a separate integration** ([[2026-05-29_watchman-judge-immix-integration]]). Decision #6.
- **Q3 (alert_id source)** — reuse connector's stable event ID. Decision implied by hook-point #1.
- **Q4 (frame URLs)** — Django at display time. Recommended.
- **Q5 (latency SLO)** — flag as conflict; need per-hop budget. Decision #5.

## Correlation with fleet-architecture plans

The Judge Contract is **orthogonal to the [[watch-entity|Watch]] Management Service**. Both are layers of the same [[watchman-repo|Watchman]] platform:

```
                  Manager Service (CONTROL — arm/disarm, schedule)
                              │ "this Watch is armed"
                              ▼
   ┌──────────┐  alerts  ┌──────────────────┐  dispositions  ┌────────────┐
   │ connector│──[SQS]──▶│  Watchman Judge  │──[SNS]────────▶│  Django    │──[WS]──▶ operator
   │   pod    │          │   (this doc)     │   ├──[SNS]────▶│  Audit log │
   └──────────┘          └──────────────────┘   └─── separate path ──────▶│  Immix    │
        ▲                          │                                       └────────────┘
        │ hot-reconfigure          │ transitions/dispositions
        │                          ▼
        └─── Site Supervisor Agent (per-site mode SM, reads judge decisions)
```

| Layer | Owns | KB anchor |
|---|---|---|
| Manager Service | Arm/disarm, schedule, manual override | [[2026-05-28_watch-management-service-design]] |
| Connector pod | Produces alerts when armed | per-proposal addenda, e.g. [[2026-05-28_watch-management-proposal-c]] |
| **Judge Contract** | Disposition per alert | this note |
| Site Supervisor Agent | Per-site mode (Patrol/Active) reading dispositions | [[2026-05-29_site-supervisor-vs-watch-manager]] |
| Operator app | Live UI to humans | (out of scope here) |
| Immix integration | Legacy alarm console | [[2026-05-29_watchman-judge-immix-integration]] |
| Audit log | ClickHouse retention | [[2026-05-29_watch-manager-observability]] §audit |

### Manager Service ↔ Judge interaction

- **Manager arms a [[watch-entity|Watch]]** → connector pod starts → pod produces alerts only for armed Watches.
- **Judge consumes alerts** — has no notion of armed-state because there are no alerts from disarmed Watches by construction (decision #1's consequence).
- **Judge emits dispositions** → audit log captures `(watch_id, alert_id, sequence_id, disposition)` rows.
- **Site Supervisor reads dispositions** → drives mode transitions (Patrol → Active on threat above threshold).
- **Manager Service reads NOT dispositions but billing events** (`site_product_started/_ended`) for its own T17 oracle. Judge dispositions ≠ billing events. Worth stating explicitly in the contract.

### Per-proposal interaction

| Proposal | Judge integration |
|---|---|
| A — Minimal Split | Connector pods publish to SQS via new `WatchmanJudgeAlertSender`. Same as today's alert pattern. |
| B — Stage Fleets | Alert fleet pods publish to SQS at end of pipeline. Same shape. |
| C — Camera-Worker | Generic worker pods publish to SQS. Same shape. |
| D — Event-Driven | **Alerts already flow through JetStream.** SQS becomes redundant — judge should subscribe to a JetStream subject directly. Bridge JetStream → SQS adds a hop. **Recommend judge consume the alert subject** under proposal D. |
| E — Hybrid Sidecar | Alert Dispatch pods publish to SQS at end of pipeline. Same shape. |
| B′ — Coordinator+Raft | Alert fleet pods publish to SQS. Coordinator attests to alert provenance (which armed [[watch-entity|Watch]] produced it) — strongest audit story. |

## Conflict register (things to take back to the doc author)

In priority order:

1. **Naming collision.** "[[watchman-repo|Watchman]]" in the doc = judge agent. "[[watchman-repo|Watchman]]" in PRD = the platform. Rename suggested to `Watchman Judge ⇔ Backend I/O Contract` (or `Assessment Agent I/O Contract` if PRD-canonical naming wins). **Decision #4.**
2. **Kafka vs SQS/SNS.** PRD/Agent Specs assume Kafka inter-agent bus; this contract picks SQS/SNS. **Resolve at platform level**, not in this contract. **Decision #3.**
3. **Latency budget.** PRD §8 sub-10s detection-to-notification SLA; contract estimates 6–12s for escalate path. Need per-hop breakdown (connector → SQS → judge → SNS → Django → WS). **Decision #5.**
4. **`watch_id` and `run_id` missing from schema.** One-line schema additions; let dispositions join cleanly to manager audit + billing. **Decision #2.**
5. **`yolo_class` should be `product`.** The connector emits per-product alerts, not raw YOLO. **Hook point #1.**
6. **`sequence_id` underspecified.** Propose: judge mints it as incident grouping ID; define the windowing rule.
7. **`descriptor` cross-reference unresolved.** §4.1.2 of some other doc — track down and link.
8. **`bbox` orientation.** Confirm `xywh` vs `xyxy` against `actuate-pipeline-objects` IDP/PDP.
9. **`schema_version` mismatch behavior.** Drop / warn / DLQ — explicit policy needed.
10. **Hook point in connector code.** Confirm publish lives near `base_stream_camera.py:915-935` in a new `WatchmanJudgeAlertSender` in `actuate-alarm-senders`.
11. **Connector-side arming enforcement.** The contract implicitly assumes only armed Watches produce alerts. Add a footnote stating that explicitly so future readers understand why there's no `armed` field in the input.
12. **Disposition vs. billing.** State explicitly that judge dispositions do NOT replace `site_product_*` billing events. They're independent.

## Recommendations to land

In rough order:

1. Submit the conflict register back to the doc author with the 12 items above.
2. Add `watch_id` + `run_id` to both schemas (decision #2 + schema for billing reconciliation).
3. Rename per decision #4.
4. Per-hop latency budget breakdown to settle decision #5.
5. Stand up `WatchmanJudgeAlertSender` in `actuate-alarm-senders` (proposed module name) as part of a feature branch when the POC graduates from CSV in / stdout out.
6. Stand up the SNS topic + per-consumer SQS queues in `ds-terraform-eks-v2` infrastructure (separate Terraform module).
7. Update Immix integration plan separately ([[2026-05-29_watchman-judge-immix-integration]]).
8. Track Kafka migration as a platform-level epic alongside other Kafka adoption (Agent Specs).

## Cross-references

- Source contract preserved: `_research-inbox/2026-05-29_watchman-judge-backend-io-contract-source.md`
- [[watchman-repo|Watchman]] PRD digest: [[2026-05-29_watchman-prds-summary]]
- [[watch-entity|Watch]] Management Service master: [[2026-05-28_watch-management-service-design]]
- Manager-Judge boundary: [[2026-05-29_site-supervisor-vs-watch-manager]] (Site Supervisor is the agent that reads judge dispositions)
- Observability + audit log: [[2026-05-29_watch-manager-observability]]
- Immix integration (separate concern): [[2026-05-29_watchman-judge-immix-integration]]
- Existing Judge code reference: `Watchman/agents/judge_agent.py` (per [[2026-05-29_watchman-prds-summary]])
