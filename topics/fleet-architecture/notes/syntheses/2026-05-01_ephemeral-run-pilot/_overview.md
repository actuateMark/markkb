---
title: "Run Service — Overview"
type: synthesis
topic: fleet-architecture
tags: [fleet-architecture, run-service, control-plane, api-gateway, vms-connector, k8s-jobs, schema-drift]
created: 2026-05-01
updated: 2026-05-01
author: kb-bot
status: drafting
incoming:
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/api-contract.md
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/paradigm-c.md
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/paradigm-d.md
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/paradigm-e.md
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/translation-layer.md
  - topics/fleet-architecture/notes/syntheses/2026-05-05_fleet-architecture-workstream-context.md
incoming_updated: 2026-05-27
---

# Run Service — Overview

> **Naming note:** "Run Service" (or `run-service`) is provisional. The folder name `2026-05-01_ephemeral-run-pilot/` and a few legacy references in cross-linked docs still use the older "ephemeral run pilot" framing — they will be reconciled in a single rename pass once the project name is final.

A new **permanent control plane** for [[vms-connector|VMS connector]] workloads, exposed as an API-Gateway-fronted service that accepts a `RunSpec.v1` payload describing a site's cameras, detection products, alert routing, and run mode (ephemeral, persistent, or scheduled). The service translates the spec into the standard connector `settings.json`, schedules the connector pipeline image on the chosen fleet paradigm (C, D, or E — see paradigm notes), and surfaces detection events back to the caller in real time.

## Project framing — permanent control plane, not pilot scaffolding

This service is designed from day one as a **long-lived production surface**, parallel to admin-api site provisioning. Three run modes coexist over time:

- `mode: ephemeral` — bounded duration (≤24h), one-off or daily-recurring API-driven run. The first delivery vehicle.
- `mode: persistent` — open-ended; the canonical onboarding path for new customers brought in through this control plane.
- `mode: scheduled` (future) — recurring runs on a calendar; the API exposes the schedule, the control plane fires runs on cadence.

**Run-service and admin-api are parallel paths, not a migration.** Existing admin-api sites stay in admin-api. New sites onboarded through run-service are first-class residents of the new control plane and don't get backported. The chosen fleet paradigm has to recognize "site" inputs from both origins; that's the only required alignment between the two systems.

This framing has consequences:

1. **Schema discipline is permanent.** Every field shipped in `RunSpec.v1` carries a deprecation cycle. The Pydantic model becomes a published partner-facing contract.
2. **DX is not optional.** OpenAPI spec, partner-facing docs, at least one SDK (Python first), copy-pasteable curl examples on day 1. This is the experience customers and partners see — it sells the platform.
3. **Operational ownership is real.** On-call rotation, SLA, NR + CloudWatch logs, run-service-specific dashboards. Day-1 commitments, not v1.5 retrofits.
4. **The "ephemeral" lens scoring is informative but not deciding.** The chosen paradigm has to win on combined ephemeral + persistent rubric scoring. See the rubric section below.

## Run modes — first-class citizens of the same API

`mode: ephemeral` and `mode: persistent` are first-class citizens on the same `RunSpec.v1` surface. The chosen fleet paradigm must serve both well — through the **same primitives, not parallel implementations.**

| Dimension | `mode: persistent` (canonical onboarding) | `mode: ephemeral` (first delivery vehicle) |
|---|---|---|
| Lifetime | Open-ended; explicit `DELETE` to stop | ≤24h, defined per-call by `duration_seconds` |
| Cadence | Continuous; cameras stream all day, daily | On-demand bursts; may be daily-recurring or one-off |
| Provisioning | `POST /v1/runs` with `mode: persistent` (parallel to admin-api site provisioning) | `POST /v1/runs` with `mode: ephemeral` and a duration |
| Configuration source | API POST → translator → settings.json (same as ephemeral) | API POST → translator → settings.json |
| Data ownership | **Full** — frames, events, alerts persisted in our infra | **Partial** — caller may host their own; shorter retention defaults |
| Failure recovery | Full graceful failover (snapshot + resume) | Best-effort within 24h; restart-and-handoff acceptable |
| Cost model | Customer subscription | Per-run, possibly billed differently |
| Detection event delivery | All channels (SSE / webhook / GET); replay enabled by default | All channels; replay is a per-tenant feature flag |

The "less claim over their data" point matters for paradigm D specifically — D's S3 frame storage is a strong fit for persistent mode (we want long retention) but is **operational overhead** for ephemeral runs. The right paradigm handles both retention shapes without two parallel data planes.

## Why ephemeral mode ships first

Ephemeral is the first delivery vehicle even though persistent will eventually carry more volume:

- **Bounded blast radius** — 24h max, single tenant, no overlap with admin-api sites. If something breaks, one trial is affected.
- **Forces the hard questions early** — cold-start latency, cost-per-run, alert routing under finite TTL, status delivery, observability, schema drift. These are all things persistent mode has to solve too; the ephemeral case just makes them sharper.
- **Real customer value path on day 1** — sales demos, partner trials, autopatrol-style spot evaluations. Ships utility immediately rather than waiting for the full persistent-mode story.
- **Comparison harness** — running the same workload across 3 paradigms gives a head-to-head signal the abstract evaluation rubric can't.
- **What ephemeral doesn't tell us** — long-haul reliability, multi-day cost amortization, persistent-data retention behavior, complex schedule evaluation (`flex_schedule_id` and friends). These come back on the table once persistent mode lights up; they feed the persistent-lens scoring.

## Goals

1. **Ship a permanent control plane** for [[vms-connector|VMS connector]] workloads. API surface is API-Gateway → Lambda → K8s, running the standard connector pipeline image. Both ephemeral and persistent modes served from the same surface.
2. **Realize the service under 3 of the 5 fleet-architecture proposals** ([[2026-04-16_proposal-c-camera-worker|C — Camera-Worker]], [[2026-04-16_proposal-d-event-driven|D — Event-Driven]], [[2026-04-16_proposal-e-hybrid-sidecar|E — Hybrid Sidecar]]) and compare them under identical conditions across both modes.
3. **Surface the full configuration surface** — site/integration creds, camera creds, models, products (with us-defined sensitivity presets), and full alert plumbing (email/SMS/webhook/SNS/integration alarms) — through `RunSpec.v1`. Healthcheck/monitoring stays platform-side; recipients are caller-controlled.
4. **Solve schema drift** between the public API contract and the connector's settings.json without making admin-api a runtime dependency.
5. **Deliver detection events** to callers via SSE, webhook, and polling — with replay capability — using presigned URLs for frame access.
6. **Drive the fleet paradigm selection** — ephemeral-lens scoring combines with persistent-mode lens (the existing [[2026-04-16_evaluation-rubric|topic-level rubric]]) for the final paradigm pick. Single-mode wins don't qualify.

## Non-goals

- Migrating existing admin-api sites to run-service. Admin-api and run-service are parallel paths; existing sites stay where they are.
- Replacing admin-api site provisioning. New customers come in through run-service; existing customers continue with admin-api.
- Per-customer custom numeric tuning (`first_layer_confidence`, `iou_thresh`, etc.). Sensitivity is exposed as us-defined presets (`low / medium / high`); numeric tuning stays internal.
- Customer self-serve UI in v1 — the API is the surface; UI is downstream and built by partner teams or a future Actuate portal.
- Non-RTSP integration types in v1 (Avigilon, Milestone, etc. extend the schema later; RunSpec is designed to accept the discriminator).

## Locked-in scope decisions (from 2026-05-01 interviews)

| Question | Answer |
|---|---|
| Project name | **`run-service`** (provisional). Final name TBD; folder/file names will be reconciled in a single rename pass. |
| Project framing | **Permanent control plane**, parallel to admin-api site provisioning. Not pilot scaffolding. No migration of existing admin-api sites. |
| Run modes | `ephemeral` (≤24h) and `persistent` (open-ended) on the same `RunSpec.v1` surface. `scheduled` mode reserved for future. |
| Run duration ceiling (ephemeral) | **24 hours.** Longer requires a follow-up call; restart-and-handoff semantics already handle in-day failures. |
| Auth | Cognito **or** API key + tenant in payload (both supported behind one authorizer). |
| Alert routing | Inline recipients in POST OR pre-registered via `POST /v1/alert-configs` (returns short id). No admin-side config. **Full plumbing in scope:** email, SMS, webhook, SNS topic ARNs, integration alarms (crisis_go / envera / genetec / etc.), per-camera SMS lists, healthcheck-specific recipient lists. |
| Sensitivity | **Us-defined presets** (`low / medium / high`), not free numeric tuning. Internal threshold values stay platform-side. |
| Healthcheck / monitoring config | **Platform defaults** — caller does not configure healthcheck logic or monitoring alarm shapes. **Routing** of healthcheck alerts is caller-controlled (which recipients hear about a stream-quality failure). |
| Detection event delivery | All three channels: SSE (`GET /v1/runs/{id}/events`), per-event webhook (`events_webhook_url` on RunSpec), and polling summary (`GET /v1/runs/{id}`). |
| Frame access | **Presigned URLs** to S3, default 1h expiry, tunable per tenant. No inline JPEGs. |
| Tracker IDs | **Exposed in v1** as a stable identifier — lets callers correlate detections across frames into "encounters" without re-implementing tracking. |
| Event replay | **Per-tenant feature flag**, default off. Enabled tenants pay for storage; events queryable post-run for the run's retention window (default 90d). |
| Admin-API role | **None at runtime.** Admin holds zero state about run-service runs. Parallel system, not a dependency. |
| Integration types | **[[rtsp-deep-dive|RTSP]] only at v1 launch**; schema designed with `integration_type` discriminator so Avigilon, Milestone, Genetec etc. extend cleanly without a v2. |
| Underlying connector | The standard [[vms-connector|VMS connector]] pipeline image (same alert-sender, same detection logic, same image registry); deployed via the chosen fleet paradigm. |

## Architecture sketch (paradigm-independent layer)

```
Caller (sales / partner / customer / autopatrol / future portal)
  │
  │  POST /v1/runs  { mode, cameras, products, alerts, events, ... }
  ▼
API Gateway ──► Lambda authorizer (Cognito OR API key + tenant)
  │
  ▼
Lambda (orchestrator)
  │  1. validate RunSpec.v1
  │  2. translate → settings.json (per [[translation-layer]])
  │  3. run init container `connector validate /config/settings.json`
  │  4. apply K8s manifest in run-service namespace
  │     - paradigm-specific (see paradigm-c / -d / -e)
  │     - activeDeadlineSeconds = duration_seconds   (ephemeral only)
  │  5. write run record + alert configs + event prefs to DynamoDB
  ▼
EKS (Connector-EKS cluster)
  │
  │  Pipeline runs the standard image. Two output streams:
  │
  │  (1) Alerts → existing alert-sender → recipients (out-of-band of API)
  │      email / SMS / webhook / SNS / integration alarms
  │
  │  (2) Detection events → run-service event bus → caller
  │      ├─ SSE (GET /v1/runs/{id}/events) — live tail
  │      ├─ Webhook (events_webhook_url on RunSpec) — async per-event
  │      └─ Summary (GET /v1/runs/{id}) — counts and latest
  │
  ▼
  ephemeral: TTL elapses, K8s reclaims, callback fires
  persistent: runs until DELETE; failure recovery via paradigm's snapshot/restore
```

## Schema drift — design

Admin-API is **not** the validator of run-service's translated settings.json — admin holds zero state about run-service runs. So validation responsibility lives entirely within run-service + the connector image. Three layers:

| Layer | Owns | Source-of-truth question it answers |
|---|---|---|
| **Public API schema** (`RunSpec.v1`) | run-service, versioned independently | "Is the caller's request well-formed?" |
| **Translator** (lambda code) | run-service | "Does the request expand to a complete settings.json?" |
| **Connector validator** (`connector validate` mode) | The connector image itself | "Will today's connector image actually accept this settings.json?" |

The connector validator is the **definitive** check — the connector's parser is the only thing that authoritatively knows what a valid settings.json looks like, because it's what consumes one in production. Lambda runs a tiny init-container with the same image, `args: ["validate", "/config/settings.json"]`, and only proceeds to schedule the real workload if it exits 0.

To prevent silent drift between the translator's assumptions and the connector's parser, a **canary** runs as a periodic test (firebat cron or GH Actions, hourly):

1. Take a known-good `RunSpec` fixture.
2. Run it through the production translator.
3. Run the output through the latest connector image's `validate` mode.
4. Alert if it fails.

This catches "the connector renamed a settings field and our translator is now wrong" within an hour, before a real customer call hits it.

The regression corpus for the translator lives at `~/work/settings-files/` (real customer settings dumps) — translator unit tests assert that for each fixture, a `RunSpec` derived from it round-trips back to a settings.json that the connector accepts.

## Detection event delivery — design

Run-service exposes a **second output stream** alongside the existing alert-sender path. Alerts go to recipients directly (email, SMS, webhook, SNS, integration alarms) — that's the existing connector pipeline behavior, unchanged. Detection events flow back to the **caller** through three channels, picked at run creation:

| Channel | Endpoint / trigger | Use case |
|---|---|---|
| **Polling summary** | `GET /v1/runs/{id}` | Casual lifecycle check; counts and latest event |
| **Server-sent events** | `GET /v1/runs/{id}/events` (SSE) | Live dashboard tailing the run |
| **Per-event webhook** | `events_webhook_url` field on `RunSpec` | Async partner integration, downstream pipeline |

### `DetectionEvent.v1` shape

```json
{
  "event_id": "evt_a3k7qz",
  "schema_version": "v1",
  "run_id": "run_xy7k2m",
  "tenant_id": "acme-corp",
  "occurred_at": "2026-05-01T15:42:18.234Z",
  "camera": { "id": "cam-1", "name": "Loading Bay" },
  "product": "intruder",
  "model": "weapon-mid",
  "confidence": 0.87,
  "bbox": [0.21, 0.34, 0.18, 0.47],
  "classes_detected": ["person", "weapon"],
  "tracker_id": "track_8821",
  "zone": "bay-7",
  "frame_ref": {
    "url": "https://signed-url-to-jpeg",
    "expires_at": "2026-05-01T16:42:18Z"
  },
  "alert_fired": true,
  "alert_triggers": ["main-ops"]
}
```

### What's filtered out as "internal"

- `admin_camera_id`, internal `stream_id`, internal `model_id` — replaced with caller-friendly names from the RunSpec
- S3 bucket names, K8s pod / container ids, NR account info, internal correlation ids
- Internal numeric thresholds (`first_layer_confidence`, `iou_thresh`, etc.) — caller sees `sensitivity: "medium"`, not the underlying numbers

### Storage + replay

- **Default**: events are **transient** — published to SSE / webhook subscribers in real time, summarized in DynamoDB run record, but full event records aren't retained.
- **Replay-enabled tenants**: events written to a separate store (DynamoDB or S3-Parquet — TBD by paradigm) for the run's retention window. `GET /v1/runs/{id}/events?since=...` queries from this store.
- **Frame retention**: presigned URLs default 1h; after expiry, the frame is gone (paradigm D's S3 lifecycle policy is the deletion mechanism). Tenants can extend frame retention but pay for it.

### Tracker IDs

The connector's BoTSORT tracker assigns a stable id to each tracked object across frames. A single person walking through camera `cam-1` appears with `tracker_id: "track_8821"` on every frame they're detected in. Exposing this lets a caller say "5 distinct intruders today" instead of "1,247 intruder frames" without re-implementing tracking. Stability across pod restarts is guaranteed by [[tracker-snapshot-schema]]; that guarantee carries through to v1 of the public surface.

## Evaluation rubric — ephemeral lens

This is the **ephemeral-mode rubric**, not the final paradigm-selection rubric. The final selection combines this with the persistent-mode rubric (the existing [[2026-04-16_evaluation-rubric|topic-level rubric]]) and weights both. A paradigm that scores 9/10 on this rubric but degrades persistent-mode behavior is not a winner.

Each of paradigm-c / -d / -e gets scored on the same axes so the pilot produces an apples-to-apples ephemeral-mode signal.

| Dimension | Weight | Why it matters here |
|---|---|---|
| **Cold-start latency** | 20% | Caller waits on `POST /runs` to return a usable run ID; > 60s and the API feels broken. The whole Job lifecycle is bounded by 24h, so 5min of cold-start is 0.3% of run-time wasted. |
| **Per-run cost** | 20% | Pilot runs need to be cheap enough that we'd offer trials to dozens of prospects without flinching. |
| **Tear-down cleanliness** | 15% | TTL-driven termination must release all resources (pod, PVC, NATS subjects, Redis keys); leaks compound across thousands of runs. |
| **Alert latency under TTL** | 15% | Real-time alerts during the run are the product; if alerts are delayed because of architectural overhead they don't fire before TTL. |
| **Failure recovery** | 10% | If a worker dies mid-run, what do we tell the caller? "Re-call the API" (acceptable) vs "your trial is silently dead" (not acceptable). |
| **Implementation cost** | 10% | What's the delta from "today's connector image" to "today's connector image + this paradigm's plumbing"? |
| **Architectural fit (ephemeral lens)** | 10% | Does this paradigm naturally express the ephemeral-run pattern? Final selection cares about both ephemeral fit AND persistent fit; this dimension is only the ephemeral half. |

### Combining with the persistent-mode rubric

The final paradigm-selection scorecard is a weighted blend:

```
final_score(paradigm) = w_persistent * persistent_score(paradigm)
                      + w_ephemeral  * ephemeral_score(paradigm)
```

`w_persistent` should be **larger** than `w_ephemeral` for now, because:

1. The persistent mode is today's primary load and has years of operational learning behind it.
2. The ephemeral mode is unproven as a customer-value path — it might end up niche.
3. A great persistent architecture that supports ephemeral adequately is worth more than a great ephemeral architecture that strains under persistent loads.

Tentative split: `w_persistent = 0.65`, `w_ephemeral = 0.35`. Tune after PoC results in.

### Bimodal-friendliness as a hidden dimension

Across both rubrics, [[watch-entity|watch]] for paradigms where the *same primitive* serves both modes versus paradigms that need *parallel implementations* per mode:

- **One primitive serves both** — bin-packed worker pool with TTL-or-perpetual leases (paradigm C); JetStream subjects with TTL-or-no-TTL (paradigm D); Site Context with TTL-or-perpetual sites (paradigm E). All three claim this in principle.
- **Parallel implementations** — separate K8s Jobs for ephemeral plus separate Deployments for persistent. Avoid; multiplies operational surface.

The PoC should explicitly stress-test that the same primitives operate cleanly under both modes (e.g., a worker pool serving 10 persistent sites + 5 ephemeral runs simultaneously without per-mode-tuned configuration).

## Sub-project layout

```
topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/
  _overview.md           — this file
  api-contract.md        — RunSpec.v1, lifecycle endpoints, DetectionEvent.v1, events delivery
  translation-layer.md   — RunSpec → settings.json mapping, sensitivity preset → numeric, canary
  paradigm-c.md          — Camera-Worker realization (both modes)
  paradigm-d.md          — Event-Driven realization (both modes)
  paradigm-e.md          — Hybrid Sidecar realization (both modes)
  decision-log.md        — (later) running log of design pivots + rationale
  comparison-matrix.md   — (after PoC) head-to-head scoring across the 3 paradigms × 2 modes
```

The folder name will be reconciled with the project name once it's finalized. Paradigm notes currently score under the ephemeral lens only; persistent-lens scores live in `comparison-matrix.md` after the PoCs run.

## Open design questions

1. **Final project name** — `run-service` is provisional. Locking it triggers a folder/title rename pass.
2. **Sensitivity preset taxonomy** — universal `low / medium / high` for all products, or per-product variants (e.g., intruder might warrant `loose / standard / strict / extreme`)? Default: universal 3-tier; revisit per-product when a customer asks.
3. **Cognito vs API-key-with-tenant** — both behind one authorizer is the current plan; revisit if operational cost is unjustified.
4. **Run history retention** — DynamoDB run records: 30d? 90d? Forever? Default 90d; tunable per tenant.
5. **Per-tenant concurrent-run cap** — default 5, override per tenant.
6. **Cost ceiling per run** — refuse if estimated cost > tenant max (default $50). Coefficient calibration TBD.
7. **Alert-config short id format** — proposed `ac_<6-char base32>`.
8. **Connector image `validate` subcommand** — does it already exist, or is this a new feature on the connector itself? Translator design assumes it exists.
9. **Frame URL TTL** — default 1h, tunable per tenant. Longer = more cost (S3 GET retention) but more flexibility for downstream pipelines.
10. **Event replay retention** — default 90d (matches run record). Replay-enabled tenants can extend at extra storage cost.
11. **Per-product alert filters** — currently `triggers: [product_alert | healthcheck | scene_change | ...]` is per alert config. Should we allow per-product filtering inside a config (e.g., "main-ops gets intruder + weapon, not loitering")? Adds complexity; defer unless requested.
12. **Same-primitive vs parallel-implementation policy** — should we require the chosen paradigm's primitives serve both modes without per-mode-tuned config, or accept some bimodal configuration? Affects PoC design.
13. **Data ownership boundary** — what's the default frame-retention story for ephemeral mode? Per-tenant override threshold?
14. **Ephemeral / persistent rubric weighting** — tentative `w_persistent = 0.65` / `w_ephemeral = 0.35`. Revisit once persistent mode is in production and we have real economics.
15. **Migration of admin-api-side concepts** — even though we don't migrate sites, we might want to share concepts (alert configs, model registry). Worth a follow-up design doc.
16. **OpenAPI spec authoring** — generate from the Pydantic model (recommended) or hand-author? Generation guarantees alignment but adds a build step.
17. **SDK languages for v1** — Python first; Go and TypeScript secondary. JS for browser is third priority.

## Cross-references

- Parent topic: [[fleet-architecture/_summary]]
- Source proposals being realized:
  - [[2026-04-16_proposal-c-camera-worker]]
  - [[2026-04-16_proposal-d-event-driven]]
  - [[2026-04-16_proposal-e-hybrid-sidecar]]
- Cross-cutting designs (apply across paradigms):
  - [[2026-04-16_graceful-failover-design]] — failure recovery for both modes
  - [[2026-04-16_frame-transport-comparison]] — affects paradigm-d the most
  - [[k8s-controller-selection-guide]] — Job vs Deployment vs StatefulSet picks per paradigm
  - [[pod-termination-sequence]] — TTL-driven termination semantics (ephemeral) and graceful shutdown (persistent)
  - [[tracker-snapshot-schema]] — tracker_id stability guarantee that the public surface depends on
- Related topics:
  - [[vms-connector/_summary]] — the pipeline being orchestrated
  - [[admin-api/_summary]] — parallel system, not a runtime dependency
  - [[settings-automation/_summary]] — adjacent work on settings.json shape
