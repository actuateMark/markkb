---
title: "Cloud Video Analytics Platform — Architecture Summary v10"
type: concept
topic: fleet-architecture
tags: [cloud, video-analytics, saas, architecture, proposal, multi-tenant, scheduling, detector-router]
jira: ""
confluence: ""
created: 2026-06-01
updated: 2026-06-01
author: kb-bot
---

# Cloud Video Analytics Platform — Architecture Summary v10

**Source document:** External architecture proposal for a consolidated cloud-only, multi-tenant video analytics SaaS. Serves ~100,000 cameras across us-west-2 region. Final v10 state captures the most mature iteration.

**Key characteristic:** Adds explicit per-(camera, product) state resolution with two-stage lifecycle model and introduces `detector-router` as a core cost-control gate.

## Product Framing

Commercial-security SaaS (not a DVR/archive service). Customers attach existing IP cameras and NVRs; Actuate delivers:
- **Actionable alarms** with pre/post-roll evidence clips (~15s each, stored in S3 core path)
- **Site-level NL intelligence** — "ask your site what's happening" (premise: event-store is always ours, regardless of customer plan)
- Optional **Cloud DVR** (continuous archive, S3 Std→IA→Glacier IR, 20-30% assumed take rate)
- Optional **Advanced Site Intelligence** (cross-camera Re-ID search, person enrollment — premium tier)

**Pricing:** $5/camera/month intruder, $15/camera/month weapon; per-product-per-camera. DVR add-on + Advanced SI premium.

## Scale Assumptions

- ~100,000 cameras multi-tenant
- ~60% continuous-stream (budget cameras, older NVRs)
- ~40% ONVIF-trigger-capable (motion events; we negotiate ONVIF access)
- Multi-site per customer (each site is a "site," each customer has multiple)
- Region: us-west-2 only (v1)
- Existing PyAV-based RTSP ingest code as foundation

## Architecture — Three-Tier Pipeline with Two Buses

### Two-Bus Pattern

**Frame bus** (Redis Streams, sharded by camera_id, TTL ≤5s):
- Carries low-res JPEG only (60 KB, 640×640, q=85) + motion polygon bbox-of-union
- Post motion-gating: ~8 GB/sec throughput

**Event bus** (Kafka/MSK, multi-AZ, 30d retention, no pixel data):
- Topics: `motion`, `detections`, `tracks`, `embeddings`, `analytics`, `stationary`, `zone_violations`, `vlm.responses`, `alerts`, `site_state_updates`, `control`
- Carries event refs + metadata only; hi-res frames stay on ingest worker, fetched via HTTP ref-fetch
- Every event carries `wall_ts` (RTCP-anchored clock from ingest for cross-camera correlation)

### Processing Flow

```
Cameras → Ingest (PyAV)
            ├─ 4-way packet fanout (ring buffer 15s, S3 archive, RTP live, analytics)
            ├─ Motion gate (pixel-based polygons, 1 FPS idle + burst on motion)
            └─ Frame bus (lo-res JPEG + polygon bbox)
                   ↓
              Detector router (NEW v10) — routes to pools based on per-(camera,product) state
                   ↓
              Detectors (YOLO intruder/weapon/fire, region-restricted via motion polygon)
                   ↓
              Event bus
                   ├─ Tracker (BoT-SORT + Re-ID, still-time tracking)
                   └─ Site state (real-time per-site rollups)
                   ↓
              Alert service (window, cooldown, zones, stationary suppression)
                   ↓
              Dispatch fleet (SNS/Lambda → partner integrations)
                   ↓
              Event store (ClickHouse, forever, partitioned tenant+site+day)
```

## Component Reference

### Ingest Tier

**`ingest-streaming`** — c8gn.4xlarge × ~300 (Graviton4, 200 Gbps NIC)
- PyAV continuous RTSP pull; ~200-250 cameras/node
- Hardware decode via libav hwaccel (when GPU-attached)
- RTCP-anchored wall-clock (critical for DVR + site-intel cross-camera correlation)
- Motion gate: 1 FPS idle, burst on motion
- Stateful, no spot

**`ingest-triggered`** — c8g.2xlarge × ~30
- ONVIF-capable cameras (~40% of fleet)
- Holds subscriptions (~1500 cams/node)
- On trigger: opens RTSP, ingests for motion-duration + cooldown, closes
- Always runs own motion code (camera triggers too noisy to trust)
- ~10× density vs continuous; ~1-2s pre-roll loss

**`trigger-receiver`** — c8g.large × ~6
- ONVIF webhook endpoint, routes to ingest-triggered workers

### Bus Tier

**`frame-bus`** — Redis r8g.2xlarge × 6 (Graviton4 DDR5)

**`event-bus`** — MSK Kafka m8g.xlarge × 6, multi-AZ, 30d retention

### Detection Tier

**`detector-intruder`** — inf2.xlarge × ~40 (Inferentia2, spot)
- YOLO + Neuron SDK
- Region-restricted (motion polygon bbox-of-union)
- 25-40% cheaper than NVIDIA equivalents

**`detector-weapon`** — g6e.xlarge × ~20 (L40S, spot)
- Two-stage detection (model still evolving)
- CUDA flexibility; reconsider Inferentia migration when stable

**`detector-fire`** — inf2.xlarge × ~10
- Lower base FPS; motion gating less critical

**`detector-router`** — c8g.large × 4 **(NEW in v10)**
- Reads per-(camera, product) state from scheduler-service
- Forwards frame-bus messages only to pools whose product is active for that camera
- Primary cost-control gate: "loitering OFF for this camera" means no loitering frames queued

### Tracker Tier

**`tracker-botsort`** — g6.xlarge × ~25 (L4)
- BoT-SORT (motion + appearance) + OSNet Re-ID embeddings
- Per-track still-time (BoT-SORT doesn't do this natively)
- Still-time logic: bbox-stable AND no motion-in-bbox → increment (with 3-of-5 multi-frame debounce)
- Busy-scene fallback (>60% motion coverage): bbox-stability only
- Emits `tracked-detection` + one-time `stationary` events

### Intelligence Tier

**`vlm-service`** — g7e.2xlarge × ~6 (NVIDIA Blackwell RTX PRO 6000, 96GB)
- Qwen-VL or similar multimodal
- Fetches hi-res via ref-fetch endpoint
- 2.3× G6e perf, ~2.6× lower $/output-token at production concurrency

**`llm-service`** — Trn2.48xlarge × 1 + Claude API
- Claude API for agentic orchestration (planning across tools)
- Trainium2 for routine summarization + retrieval
- Tools: `get_site_state`, `query_events`, `vector_search`, `describe_frame`, `compare_to_baseline`, `list_active_alarms`, `get_camera_state`, `get_site_schedule`, `get_armed_state`

**`site-state-service`** — c8g.2xlarge × 6 **(v1 core capability)**
- Stream consumer of event-bus; maintains per-site real-time rollups
- Active alarms, occupancy by zone, activity vs baseline, camera health, business context
- Redis materialization (per-site hash) + periodic ClickHouse snapshots
- Sharded by site_id

### Alert and Dispatch

**`alert-service`** — c8g.xlarge × ~20
- Sliding-window confirmation, cooldown, dedup
- Applies ignore zones, AOIs, stationary suppression
- Consults per-(camera, product) state from scheduler-service before firing
- Alert-type rules: intruder suppressed on stationary, weapon NEVER suppressed, loitering REQUIRES stationary

**`analytics-workers`** — c8g.xlarge × ~15
- Loitering, line-crossing, occupancy, dwell (zone-aware)

**`dispatch-fleet`** — SNS + Lambda
- Reads alerts, fans out per dispatch routing rules
- Schedule-aware routing (different recipients at different times)
- Existing partner integrations (Totem/DMP, Genetec, webhooks)

### Storage

**`event-store`** — ClickHouse r8g.4xlarge × 6
- **Always ours.** Every event forever, partitioned tenant+site+day
- Doubles as high-volume log store (saves $50-100k/mo vs full New Relic)

**`vector-store`** — Milvus r8g.2xlarge × 6 (premium tier only)
- Re-ID + CLIP/SigLIP embeddings
- Cross-camera search, NL search, person enrollment

**`s3-evidence`** — S3 (core path)
- Per-alarm clips (15s pre/post-roll from ingest ring buffer)
- Every alarm actionable without DVR

**`s3-archive`** — S3 Std→IA→Glacier IR (DVR add-on only)
- Continuous .ts segments; only written when DVR enabled
- Lifecycle: 24h Std → 7d IA → 30d Glacier IR (tenant-configurable)

**`playback-service`** — c8g.xlarge × ~6 + CloudFront (DVR add-on only)
- HLS playlist generation, signed URLs

### Scheduling (v9–v10 refined)

**`scheduler-service`** — c8g.xlarge × 6 **(NEW in v9, refined in v10)**
- Stateless Python, sharded by tenant_id
- **Two-stage resolution:** camera lifecycle first, then per-product state (see [[2026-06-01_v10-scheduler-and-state-resolution]])
- Triggered by: EventBridge (time), alarm-panel events, customer overrides
- Emits commands on `control` topic (ingest, detector-router, alert, dispatch subscribe)
- Latency: rule eval <100ms; override propagation <1s end-to-end
- Jitter on cohort starts (60s spread to avoid thundering herd)

**`eventbridge-scheduler`** — AWS managed
- Wake-me primitive only; rule logic in scheduler-service
- Handles cron, timezones, DST, retries

**`override-service`** — c8g.large × 2
- Customer REST API: "arm now," "extend to," "vacation," etc.
- Every override has explicit expiry (no permanents via this path)

**`alarm-panel-integration`** — c8g.large × 3
- Webhook receiver for partner panels (Alarm.com, DMP, Honeywell, Bosch)
- Canonical event translation: `{tenant_id, panel_id, state, ts}`

**`config-service`** — c8g.large × 4 + Postgres
- Per-camera zones (ignore + AOI), per-tenant entitlements, per-site metadata
- **Sparse schedule rules** at tenant/site/camera/product levels
- Override history, alarm-panel-to-tenant mapping

### Live Streaming (core path)

**`live-fanout`** — c8gn.large × ~20
- SRT/RTP relay, per-camera fanout

**`media-server`** — c8g.2xlarge × ~50
- MediaMTX/LiveKit; RTSP/RTP → WebRTC (sub-1s) + LL-HLS (2-4s)
- Auto-scales on concurrent-viewer count

## Twelve Key Decisions

1. **PyAV over GStreamer** — Don't rewrite working code. Empirical camera compatibility knowledge is the asset; PyAV already handles it well. RTCP timestamp handling better for cross-camera correlation. Reconsider only if: GPU-colocated ingest becomes primary, specific camera incompatibility, live-streaming becomes product centerpiece, sustained GIL contention in profiling.

2. **Frame-bus / event-bus split** — Hi-res pixels never traverse event bus. Frame bus carries lo-res JPEG only; downstream services HTTP-fetch hi-res from ingest worker's ring buffer. Keeps Kafka throughput sane, avoids re-encoding, makes event store cheap (no blobs).

3. **Motion as tier-0 detection** — Pixel-based motion runs in ingest, gates analytics decode, publishes first-class motion events with polygon coords. Downstream uses: detector region-restriction, tracker still-time, LLM "show motion at 3am" queries, occupancy estimates.

4. **Two ingest modes** — ~60% continuous, ~40% triggered. Triggered costs much less (no continuous decode) but camera triggers too noisy; always run own motion code on resulting stream.

5. **Stationary suppression at tracker, not detector** — Detector correctly keeps detecting parked cars. Tracker computes per-track still-time (polygon-aware). Alert-service suppresses intruder alerts on stationary tracks; loitering/abandoned REQUIRE stationary.

6. **Zones at alert layer** — Ignore zones + AOIs apply at alert-service, after event-store captures raw detections. Customer can edit zones without losing history; detectors stay zone-agnostic.

7. **Site intelligence as v1 core** — Not premium. Site-state-service maintains real-time per-site rollups; LLM tier (Claude API for orchestration, Trn2 for cheap retrieval) does agentic planning.

8. **Cloud DVR as opt-in add-on** — Most customers have own NVR. 15s ingest ring buffer + per-alarm S3 evidence clip makes every alarm actionable. Continuous archive is separate paid feature.

9. **Per-camera, per-product scheduling with two-stage resolution** — Stage 1: camera lifecycle (streaming?). Stage 2: per-product activation (which products active on this streaming camera?). Sparse rule storage at tenant/site/camera/product levels; evaluation-time precedence resolution with 5-level stack: override > alarm-panel > camera > site > tenant.

10. **Purpose-built scheduler-service + EventBridge** — Not Temporal (overkill — scheduling is rule eval, not durable workflow). Not Step Functions (same mismatch). Not Quartz (JVM-only). EventBridge is cheap wake-me primitive; we own rule logic.

11. **Observability split** — New Relic for APM, alerting, low-volume ops logs. ClickHouse (already deployed for event-store) absorbs high-volume per-event logs. OpenTelemetry throughout for vendor independence. At 100k cameras, full-NR logging would cost $50-100k/mo; ClickHouse cuts ~10×.

12. **2026 silicon choices** — Graviton4 c8g/c8gn for ingest/media (200 Gbps NIC). Graviton4 r8g + DDR5 for memory-bound services (Redis, ClickHouse, Milvus). Inf2.xlarge for YOLO (CNN canonical good-fit). G6e.xlarge for weapon detector (CUDA flexibility pending model stabilization). G6.xlarge for BoT-SORT (L4 sufficient for small Re-ID model). **G7e.2xlarge for VLM (Blackwell, RTX PRO 6000 96GB, GA us-west-2 Feb 2026, 2.3× G6e perf)**. Trn2.48xlarge for LLM self-hosted summarization.

## Deliberately NOT Optimized For

- **Latency <3s end-to-end** — Multi-frame confirmation prevents FP; 3-6s is right tradeoff
- **Edge inference** — Cloud-only by design. On-prem is **separate product (Watchman)** — see [[terminology-conflict-note-watchman-ambiguity]]
- **Real-time video collaboration** — Live view exists for context; not "watch cameras all day" product
- **Video archive as core value prop** — Customers have own NVR; DVR is add-on

## Open Questions / Known Weaknesses

1. **Per-camera dynamic auto-tuning** — Should system learn scene characteristics over first 1-2 days and auto-tune sampling, polygon thresholds, stationary-time thresholds? Not v1, but architecture should anticipate.

2. **Multi-tenant GPU pool isolation** — Detector pools shared across tenants. Acceptable for commercial-security customer base or do we need tenant-dedicated pools for compliance? Probably fine v1; worth flagging.

3. **Single-region DR** — us-west-2 only for v1. Event-store partitioning by tenant makes multi-region eventual extension feasible but not designed in.

4. **Training-data pipeline** — Event store has all raw detections; path from "FP customer flagged" → "retraining set" → "model rollout" not drawn. Should be.

5. **Per-tenant cost attribution** — Per-tenant cost reporting mentioned (custom metrics in observability) but data model not fully fleshed. Affects pricing decisions.

6. **Schedule rule complexity ceiling** — Sparse rules + inheritance + alarm-panel integration + overrides is right, but customers will eventually want holiday calendars, conditional rules ("armed unless raining outdoors"). Line between supported vs "custom integration project" not defined.

7. **Person enrollment PII handling** — Premium feature includes customer-uploaded face/body images for known-person matching. PII handling, retention, deletion guarantees not designed yet.

8. **GIL contention in PyAV ingest** — PyAV releases GIL during C calls, but per-packet Python work + 4-way fanout might bottleneck. Profiling required; one of the GStreamer-reconsider triggers.

---

**Source:** `/home/mork/Downloads/architecture-summary.md` + `/home/mork/Downloads/pipeline-diagram-v10.html` (received 2026-06-01)
