---
title: "Decode Locality per Fleet Proposal (where decode happens in A-E)"
type: synthesis
topic: video-processing
tags: [bridge, fleet-architecture, decode, locality, hwaccel, gop, preliminary, rtsp]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
---

# Decode Locality per Fleet Proposal

Where does the video codec→numpy decode happen in each fleet-architecture proposal? The five candidates (A–E) don't make this explicit, but each implicitly assumes a different boundary between frame transport and decoding. This synthesis articulates the decode-locality trade-off per proposal and surfaces implications for codec coverage, GPU placement, [[gop-keyframe-fundamentals|GOP]] latency, and the incomplete [[pyav-entity|PyAV]]/[[opencv-entity|OpenCV]] migration.

## Why decode locality matters

**Decode is not free.** It costs CPU (or GPU memory bandwidth if hardware-accelerated), and it happens *somewhere* in the pipeline. The earlier in the topology you decode, the less network traffic you send (JPEG or [[h264-deep-dive|H.264]] packets are smaller than numpy arrays). The later you decode, the more the decoding fleet can specialize — dedicate GPUs to hardware-decode, batch across streams, etc. The choice couples to:

1. **What crosses the wire** — codec packets (small, CPU decode cost distributed), JPEG snapshots (medium), or numpy frames (large). See [[2026-04-16_frame-transport-comparison]] for the full cost model.
2. **Hardware accelerator placement** — if decode happens in the puller fleet, GPU nodes must be everywhere pullers are. If decode is centralized, one GPU fleet can serve many pullers.
3. **[[gop-keyframe-fundamentals|GOP]] / keyframe latency** — waiting for an IDR before decode can produce a frame. Stateless transport (codec packets) preserves this latency to the decode site. Stateful transport (frame buffers) hides it upstream.
4. **Failover state** — if a decode worker dies mid-stream, does the decoder context (PTS tracking, reference frames, hwaccel surfaces) need to be snapshotted and resumed? Or can the next pod just restart fresh?
5. **Codec coverage** — the [[actuate-frame-ingest-decode-paths|current puller suite]] has two parallel decode substrates ([[pyav-entity|PyAV]] and [[opencv-entity|OpenCV]]). Some proposals (especially C) only work cleanly with [[pyav-entity|PyAV]]'s hardware-accel support and explicit codec context control. C forces a completion of the [[pyav-entity|PyAV]] migration before PoC.

## Proposal A — Minimal Split

**Decode location:** **Puller fleet** (extract pullers, keep decode in them).

**What crosses the wire:** JPEG bytes (per-camera Redis Stream, one stream per camera).

**Rationale:** The puller must connect to the VMS anyway, pulling [[rtsp-deep-dive|RTSP]]/fMP4/WebSocket or JPEG. Decode inside the puller is the path of least resistance — the puller is already responsible for codec selection, hardware detection, VMS-specific tuning. A encodes JPEG before sending, paying a second-encode cost ([[rtsp-deep-dive|RTSP]] [[h264-deep-dive|H.264]] → numpy → JPEG → pipeline).

**Hardware-accelerator implications:** Puller pods must sit on EC2 nodes with GPU (G5/G6/L4) if the VMS streams [[h264-deep-dive|H.264]]/[[h265-hevc-deep-dive|H.265]]. But today's puller pods are tiny (2–4 vCPU) — packing 10–20 cameras per pod means the GPU is underutilized. **Cost pressure:** A's JPEG-encode cost + pod-density overhead negates some of the extraction win.

**[[gop-keyframe-fundamentals|GOP]] / keyframe latency:** Hides inside the puller. JPEG encode waits for a valid frame from the decoder, so the first-frame latency includes the IDR-wait (0–[[gop-keyframe-fundamentals|GOP]]/2 seconds) plus JPEG-encode cost (~1–5 ms). Pipeline workers see only JPEG frames, timing-decoupled from the camera's [[gop-keyframe-fundamentals|GOP]] structure.

**Failover:** Decoder context (PTS tracker, reference frames, AVDiscard state) is volatile — if the puller pod dies, loss is at most 10–30 seconds of frames (the Redis MAXLEN window). Pipeline workers are unaffected. No tracker-snapshot needed for the puller itself, but [[2026-04-16_graceful-failover-design|graceful failover]] doesn't apply to A; pipeline-worker failover is still baseline (immediate loss of the camera's site).

**[[pyav-entity|PyAV]]/[[opencv-entity|OpenCV]] migration debt:** Minimal. Pullers continue using today's factory routing (AvUrlFramePuller for [[rtsp-deep-dive|RTSP]], [[opencv-entity|OpenCV]] fallback for motion-gated, [[gstreamer-entity|GStreamer]] for edge cases). No forced codec-path consolidation.

**Open question:** Is the JPEG-encode cost inside the puller (hardware or software) a real bottleneck? At 32k cameras × 3 fps, that's 96k JPEGs/s. Measurement in PoC is essential.

---

## Proposal B — Stage Fleets

**Decode location:** **Pipeline fleet** (inference/observer stage, after motion detection).

**What crosses the wire:** JPEG bytes (Redis Stream, 4 hops: raw JPEG → motion-filtered JPEG → inference → observed events).

**Rationale:** Extract puller to a dedicated fleet for network-scale isolation. Puller still encodes JPEG (same cost as A). Motion workers and inference coordinators read JPEG and re-decode for processing. Observers run detection and filtering. This is "every stage is its own fleet" — decode happens implicitly in multiple places (puller first, then motion/inference).

**Hardware-accelerator implications:** GPUs for inference are already deployed (inference-coord fleet). Decode happens in the inference-coord on GPU (or on CPU if inference is CPU-bound). Motion and observer workers are stateless and Spot-eligible; they don't need GPU. **Architecture implication:** GPU placement is dictated by inference, not decode. Decode inherits the GPU from inference.

**[[gop-keyframe-fundamentals|GOP]] / keyframe latency:** Puller warp JPEG, hides IDR latency from downstream. But now we're doing JPEG → motion → JPEG→ decode → inference → JPEG→ decode → observer. Each stage introduces ~1–5 ms per-hop encode/decode cost on the critical path. At 4 hops that's 4–20 ms of pure codec machinery. **Uncompressed frames would save this.** But uncompressed frames (raw BGR24 or YUV420) blow up Redis message size 10–100×, which is the entire cost lever of the proposal. B trades per-frame codec latency for network-codec efficiency.

**Failover:** Tracker state lives in observer fleet. Uses [[2026-04-16_graceful-failover-design|full graceful failover]] with Redis tracker snapshots. Codec-context state (PTS tracker, reference frames) is not preserved between observer pods — each pod starts fresh and may miss a few frames until the tracker stabilizes. **Cost:** expected 1–10 frame gap per reassignment (acceptable; tracker resumes from snapshot).

**[[pyav-entity|PyAV]]/[[opencv-entity|OpenCV]] migration debt:** **High.** Motion workers, inference coordinators, and observers all call into the puller's decode path (importing av_url_puller or url_puller). If you have two parallel paths, every downstream stage has to choose or support both. B's benefit is maximized if there's one canonical decode substrate. The synthesis should recommend **completing the [[pyav-entity|PyAV]] migration before B's PoC**.

**Open question:** Can motion and inference stages decode JPEG efficiently without GPUs? At high frame rates, software JPEG decode (libjpeg-turbo) becomes CPU-bound. If motion FPS is high on every camera, CPU saturates and B's per-stage scaling breaks down.

---

## [[2026-04-16_proposal-c-camera-worker|Proposal C — Camera-Worker Fleet]]

**Decode location:** **Worker pod** (full pipeline in-process, per-camera, inside the worker).

**What crosses the wire:** Nothing (frames stay in-process). Redis carries tracker snapshots and camera-assignment leases only.

**Rationale:** Generic worker pods run the entire pipeline — fetch, decode, inference, filtering, tracking — for 10–50 cameras per pod. No frame-network cost. Cameras are bin-packed across workers dynamically; a worker can hold any camera (or any camera in a VMS family, depending on image choice). This is the "camera-locality" bet: the pipeline is cheap enough to run N copies of it (one per worker per camera) rather than trying to demultiplex N cameras through shared stages.

**Hardware-accelerator implications:** Each worker pod must be GPU-capable if the cameras stream [[h264-deep-dive|H.264]]/[[h265-hevc-deep-dive|H.265]]. Workers are 4–8 vCPU + GPU (e.g., an A10 or L4 shared across 10–20 cameras via bin-packing). This is **more GPU-dense than A or B** — the GPU is packed tighter because there's no separate puller layer and inference is co-resident. But it also means **every worker needs a GPU**, which ties the worker fleet to GPU-capable nodes. Cost trade-off is complex.

**[[gop-keyframe-fundamentals|GOP]] / keyframe latency:** No difference from today — the worker decodes [[rtsp-deep-dive|RTSP]]/fMP4/WebSocket in-process, pays the IDR-wait latency, feeds numpy frames through the pipeline. **Key win:** C eliminates the puller/pipeline network boundary, so the pipeline sees deterministic latency (no Redis-hop jitter). **Key risk:** if a camera reassigns from worker A to worker B, the new worker starts fresh with a new [[rtsp-deep-dive|RTSP]] connection, new decoder context, and potentially a new IDR-wait. Tracker state is snapshotted in Redis (per [[2026-04-16_graceful-failover-design]]), so windows are preserved, but frame timing may glitch.

**Failover:** Tracker state snapshotted to Redis every 1 s. Worker death → assignment controller detects missing lease → reassigns camera to another worker → new worker resumes from Redis snapshot. **Cost:** 1–2 frames lost during the lease-expiry window. **Complexity:** the camera-reassignment itself is a "decoder death" — the [[rtsp-deep-dive|RTSP]] connection closes and a new one opens. If VMS auth or tunnel setup is slow, RTO can balloon.

**[[pyav-entity|PyAV]]/[[opencv-entity|OpenCV]] migration debt:** **Critical.** The "universal worker image" (single image that can run any camera) requires one decode path. Today's factory splits across AvUrlFramePuller, UrlFramePuller, [[gstreamer-entity|GStreamer]], and JPEG pullers. C's bin-packing only makes sense if you can assign any camera to any worker without image rebuild. **Forcing factor:** C either demands PyAV-only (migration complete) or requires per-VMS-family worker pools (which defeats the "universal worker" simplicity). The synthesis should flag this as **a hard blockers until [[pyav-entity|PyAV]] migration finishes**.

**Open question:** The [[customer-site-connectivity|connectivity topology]] threat is largest for C. If a camera's VMS lives behind a per-site WireGuard tunnel, can a universal worker route to it? Not without tunnel termination in the worker pod (infeasible at scale) or an assignment constraint (workers labeled by tunnel class, bin-packing loses freedom). **Blocker: pending `kubernetes-deployments` deep dive.**

---

## [[2026-04-16_proposal-d-event-driven|Proposal D — Event-Driven Pipeline]]

**Decode location:** **Detector fleet** (dedicated inference stage, pulling frames from S3/MinIO by reference).

**What crosses the wire:** Frame *references* (NATS JetStream envelopes with S3 key + metadata). Frame bytes live in S3 Express One Zone (per-AZ, low-latency).

**Rationale:** Puller captures frames, runs FDMD motion detection locally, drops non-motion frames (60–80% reduction), writes motion-detected JPEG bytes to S3 Express, publishes NATS envelope with the S3 key + motion result. Detector fleet pulls frames from S3 by key, decodes JPEG (or re-encodes if S3 stored raw bytes), runs inference. Observer pulls inferred detections from NATS.

**Hardware-accelerator implications:** Decode happens in the detector fleet, which also runs inference. GPU is placed there (A10, L4, L40S). Puller fleet is CPU-only (FDMD is CPU, no [[rtsp-deep-dive|RTSP]] hardware decode needed). **Efficiency win:** GPU is packed denser with both FDMD filtering and inference in the same pod. **Cost risk:** S3 Express per-AZ buckets add infrastructure; VPC gateway endpoints avoid cross-AZ transfer but require careful DNS/routing setup.

**[[gop-keyframe-fundamentals|GOP]] / keyframe latency:** Puller waits for decode (IDR-wait), encodes JPEG, uploads to S3. Detector downloads from S3, decodes JPEG, infers. The IDR-wait latency is paid in the puller (before S3 upload), so S3 reference has no live-RTSP timing coupling. **Advantage:** if the S3 object is already on disk (replayed, reprocessed), the detector can decode it without waiting for a live camera. **Disadvantage:** Puller → S3 → Detector adds two full codec ops (upload time + download latency). D's cost case depends on S3 Express latency being <100 ms.

**Failover:** Tracker state in observer fleet, snapshotted to Redis. Frame durability is in S3 (1-hour lifecycle), not ephemeral Redis Streams like A/B. **Advantage:** detector can restart and re-fetch frames from S3. **Disadvantage:** S3 is a new SPOF — if MinIO or S3 Express cluster fails, no frames can be decoded until it recovers. [[2026-04-16_frame-transport-comparison]] models this as a cost lever — S3 replication is expensive.

**[[pyav-entity|PyAV]]/[[opencv-entity|OpenCV]] migration debt:** **High.** The detector fleet imports the decode path (AvUrlFramePuller or similar) to handle JPEG. If [[opencv-entity|OpenCV]] is still in play, detector has to choose. D recommends **canonical [[pyav-entity|PyAV]] decoder** for the detector (JPEG via `av.open(io.BytesIO(jpeg_bytes))`). Puller's FDMD uses CPU, but detector's decode must be efficient — [[pyav-entity|PyAV]]'s hardware JPEG decoding (if available) is worth having.

**Open question:** FDMD cost in the puller at camera-per-pod scale. At 32k cameras × 3 fps, CPU for motion detection alone (no decode) may dominate. PoC must measure to confirm motion-gate reduction (60–80% claimed) translates to real savings.

---

## [[2026-04-16_proposal-e-hybrid-sidecar|Proposal E — Hybrid Sidecar]]

**Decode location:** **Smart puller fleet** (for initial frame decode from VMS, locally, without transport).

**What crosses the wire:** Motion-filtered JPEG (Redis Stream per camera-group, motion-detected frames only; 20–40% of raw volume).

**Rationale:** Smart puller pulls from VMS, decodes [[rtsp-deep-dive|RTSP]]/fMP4/WebSocket in-process, runs FDMD motion detection locally, sends only motion-detected frames via Redis Streams to a detection-core StatefulSet. Detection core runs inference and full filter chain in-process per camera-group. Tracker state is snapshotted to Redis. Site-context service (centralized) handles config and schedule (fixes ENG-96).

**Hardware-accelerator implications:** Smart puller pods sit on GPU nodes (need [[rtsp-deep-dive|RTSP]] hardware decode). Detection-core pods (StatefulSet per camera-group) also have GPUs (inference). **Packing efficiency:** two tiers but both GPU-heavy. Unlike D, no separate motion-only CPU fleet — motion and inference share the detection-core GPU. **Cost model:** E's savings come from motion-gating (fewer frames on the wire), not GPU consolidation.

**[[gop-keyframe-fundamentals|GOP]] / keyframe latency:** Puller decodes [[rtsp-deep-dive|RTSP]], pays IDR-wait, runs FDMD, sends only motion frames via Redis. Detection core receives motion-filtered stream. **Key difference from A:** E applies FDMD before Redis, so the stream is pre-filtered. **Latency impact:** pipeline waiting for inference sees motion-detected-only frames, potentially smoother (fewer false motion, more stable tracker) but potentially delayed (wait for motion to trigger, then decode, then infer). For true real-time static-scene detection, E is higher-latency than a raw decode path.

**Failover:** Tracker state in detection-core StatefulSet, snapshotted to Redis. Smart puller is stateless (motion state is cheap to restart). **Design:** detection-core is StatefulSet with camera-affinity — a given camera-group pod owns a set of cameras; on pod death, the assignment controller reassigns to another pod, which resumes from Redis snapshot. **Cost:** tracker snapshot on pod death, camera reassignment, motion-model cold-start (~3–5 seconds per puller restart).

**[[pyav-entity|PyAV]]/[[opencv-entity|OpenCV]] migration debt:** **Moderate.** Smart pullers must decode [[rtsp-deep-dive|RTSP]] with hardware support (to feed FDMD), but FDMD output is JPEG-only (no live codec stream to detection-core). If FDMD is extracted into a library, it can stay codec-agnostic (consume numpy frames, emit binary motion-region mask). Existing [[pyav-entity|PyAV]] path suffices for the puller. **Forcing factor:** E's motion-gating is the cost lever, so FDMD quality is critical. If FDMD is currently only implemented for [[opencv-entity|OpenCV]], extracting it to a standalone library is prerequisite work.

**Open question:** FDMD model state and camera reassignment. If a camera is assigned to puller A (which has FDMD models trained on past motion), then reassigned to puller B, does the model transfer or cold-start? Cold-start is simpler (each puller has independent models) but costs 3–5 seconds of warm-up before motion-detection is reliable. This is acceptable if rare, but if bin-packing causes frequent reassignments, cost accumulates.

---

## Cross-Proposal Themes

### GPU Placement and Cost Trade-Offs

| Proposal | GPU placement | GPU utilization | Cost delta |
|----------|---------------|-----------------|-----------|
| A | Puller pods (many, small) | Low (1–2 cameras per GPU) | +10–15% |
| B | Inference-coord pods | Medium (shared by inference + decode) | +15–25% |
| C | Worker pods (GPU per worker) | Medium–high (bin-packed, 10–50 cam/pod) | -15–30% |
| D | Detector pods (dedicated) | High (GPU runs detector + inference) | ~neutral |
| E | Smart puller + detection-core (two fleets) | Medium (motion pre-filtering reduces downstream) | -20–40% |

**Insight:** C and E win on GPU efficiency because they either bin-pack wildly (C) or pre-filter before GPU (E). A is GPU-sparse; B GPU-inherits from inference. D is a middle ground — dedicated detector pods can be right-sized but add complexity.

### [[pyav-entity|PyAV]] vs [[opencv-entity|OpenCV]] Migration Status

| Proposal | Requires | Current Status | Pre-PoC Work |
|----------|----------|----------------|-------------|
| A | Either; status quo | Ongoing | None; ready |
| B | Canonical path ([[pyav-entity|PyAV]] recommended) | Ongoing | Recommend [[pyav-entity|PyAV]] completion |
| C | **PyAV-only (universal image)** | Incomplete | **Blocker; must finish migration** |
| D | [[pyav-entity|PyAV]] recommended (detector) | Ongoing | Recommend [[pyav-entity|PyAV]] for detector |
| E | [[pyav-entity|PyAV]] (puller) for [[rtsp-deep-dive|RTSP]] hardware decode | Ongoing | None; ready |

**Insight:** C is the only one that forces a blockers. The universal-worker assumption requires one decode path; two parallel paths defeat the bin-packing promise.

### Failover State and Codec Context

| Proposal | Failover type | Codec context snapshot? | RTO | Notes |
|----------|---------------|------------------------|-----|-------|
| A | None (pipeline pod crash = site dark) | N/A | Baseline (seconds) | [[graceful-failover-design]] does not apply |
| B | Full (observer pod + tracker snapshot) | No; context restarts | 1–10 frames per pod death | Tracker resumes; codec context cold-starts |
| C | Full (worker pod + tracker snapshot) | No; context restarts | 1–10 frames + reassignment | Camera reassignment + codec cold-start |
| D | Full (observer pod + tracker snapshot) | No; re-fetch from S3 | 1–10 frames; S3 availability critical | Frame durability > ephemeral Redis |
| E | Full (detection-core pod + tracker snapshot) | No; context cold-starts | 1–10 frames + motion cold-start | Motion model restarts on puller reassignment |

**Insight:** None of the proposals snapshot codec context (PTS tracker, reference frames, AVDiscard state). All accept "cold start" on failover. This is acceptable (codec context recovers in <1 frame), but it's worth noting for customers running on tight RTO budgets.

---

## What This Means for Pre-PoC Scoring

**Decode locality differentially impacts two rubric dimensions:**

1. **Cost reduction:** E and D win by motion-gating (fewer frames on wire) or bin-packing (C). A and B don't reduce frame volume pre-transport.
2. **Operational simplicity:** A is simplest (status quo topology). C adds assignment complexity. E adds site-context service + FDMD extraction. B adds 4 stages + distributed tracing.

**Pre-PoC data that would shift scores:**

- **FDMD motion-gate reduction rate:** if E's claimed 60–80% is overestimated (actual is 30–40%), the cost case weakens significantly. Measure in PoC.
- **Per-camera hardware-decode cost at scale:** if A's JPEG encoding in 32k puller pods (96k JPEG/s total) is a real bottleneck, A's cost advantage erodes and B/C/E look better.
- **S3 Express latency per-AZ:** if D's assumption of <100 ms S3 PUT/GET round-trip doesn't hold at scale, detector→S3→detector becomes a latency tax and D's cost case weakens.
- **Customer-site WireGuard adoption:** if >20% of sites use per-site tunnels, C's "universal worker" assumption breaks and the proposal needs a tunnel fleet or assignment constraints (both add cost/ops). See [[customer-site-connectivity]].
- **[[pyav-entity|PyAV]] migration timeline:** C is blocked until [[pyav-entity|PyAV]] can decode all 19+ integration types. If that's 4+ weeks, C's timeline estimate (13–20 wks) is optimistic.

---

## Open Questions for Expansion

1. **Codec coverage completeness:** does [[pyav-entity|PyAV]]'s HW_DECODERS table ([[h264-deep-dive|h264]], hevc, mjpeg, mpeg2, mpeg4, vp8, vp9, av1, vc1, prores) cover 100% of Actuate customer cameras? Or do edge cases still require [[gstreamer-entity|GStreamer]] or [[opencv-entity|OpenCV]] fallback?
2. **fMP4 recycle impact on long-running pullers:** the 300-second demuxer recycle in [[pyav-entity|PyAV]] (workaround for mov frag_index leak) introduces periodic IDR-waits every 5 minutes. At scale, does this cause visible latency spikes? Measure per-proposal.
3. **[[inference-pool|Inference pool]] sizing with AIMD:** proposals B, D, E all have multiple inference locations. Does AIMD congestion control converge better with one large centralized pool (B, D) or multiple per-pod pools (E)? Pool placement is an open design question in [[inference-api-interaction]].
4. **Motion-gating false-negative rate:** if E's FDMD drops motion (60–80% frames), can real attacks/events be missed? Security/UX trade-off not yet characterized.

---

> **Status: preliminary draft (2026-04-27).** Each proposal-subsection should be expanded with hard numbers (decode CPU/sec/camera, GPU [[hardware-accelerated-codecs|NVDEC]] throughput, IDR-wait latency) before the PoC selection. The PyAV-migration-blocker for C should be resolved before PoC scope is locked.

Cross-links: [[fleet-architecture/_summary]], [[2026-04-16_proposal-a-minimal-split]], [[2026-04-16_proposal-b-stage-fleets]], [[2026-04-16_proposal-c-camera-worker]], [[2026-04-16_proposal-d-event-driven]], [[2026-04-16_proposal-e-hybrid-sidecar]], [[2026-04-16_frame-transport-comparison]], [[2026-04-16_graceful-failover-design]], [[frame-transport-payload-formats]], [[gpu-substrate-and-fleet-placement]], [[actuate-frame-ingest-decode-paths]], [[hardware-accelerated-codecs]], [[gop-keyframe-fundamentals]], [[pyav-entity]], [[opencv-entity]], [[ffmpeg-hardware-acceleration]], [[reading-list]].
