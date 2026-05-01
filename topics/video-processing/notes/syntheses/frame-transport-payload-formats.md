---
title: "Frame-Transport Payload Formats (codec × transport bridge to fleet-architecture)"
type: synthesis
topic: video-processing
tags: [bridge, fleet-architecture, frame-transport, codec, jpeg, h264, redis, nats, s3, preliminary]
jira: ""
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/2026-04-27.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/video-processing/_summary.md
  - topics/video-processing/notes/syntheses/decode-locality-per-proposal.md
incoming_updated: 2026-05-01
---

# Frame-Transport Payload Formats: Codec × Transport Bridge to Fleet Architecture

The [[fleet-architecture/_summary|fleet-architecture redesign]] evaluates five candidate service architectures (A–E) and cross-cutting designs like [[2026-04-16_frame-transport-comparison|frame-transport comparison]]. That document compares Redis Streams, NATS JetStream, SNS/SQS, and S3-refs as **inter-pod message buses**. It does not specify what goes **inside those messages** — the **payload format**. This is a video-processing question. Different [[codecs-overview|codecs]] and frame representations favor different transports, and the choice of codec will constrain (or enable) the eventual architecture selection.

## The payload-format axis: four candidates

### Raw numpy ndarray (BGR24)

A decoded frame in memory: `uint8[height, width, 3]` in BGR color order.

- **Size:** ~6 MB at 1080p30, ~1.5 MB at 540p
- **CPU cost on send:** zero — pass the buffer directly
- **CPU cost on receive:** zero — use immediately
- **Bandwidth / storage:** maximum; prohibitive for remote fleet boundaries
- **Distribution:** **breaks Redis message-size cap** (Redis single-message limit is configurable but typically 512 MB cluster-wide, often tuned to 1 MB per message on multi-tenant deployments)

**Verdict:** only viable within a single pod (in-memory shared buffers or Unix pipes). Not suitable for inter-pod / inter-fleet boundaries.

### JPEG bytes (libjpeg-turbo or cv2 encode)

Intra-only codec. Each frame stands alone.

- **Size:** 50–300 KB per frame, depending on scene complexity and quality setting
  - Quality 95 (our default for detection frames) on 1080p bland scene: ~100 KB
  - Complex high-motion scene (worst case): ~300 KB
- **CPU cost on send:** 5–15 ms per frame (TurboJPEG at quality 95 on modern x86)
- **CPU cost on receive:** 10–30 ms per frame (JPEG decode via `libjpeg-turbo` or [[opencv-entity|OpenCV]])
- **Compression ratio:** ~10–20× vs raw (5× compression factored into bandwidth budget)
- **Distribution:** **fits Redis (~100 KB << 1 MB cap)**, fits NATS (default 1 MB per message), fits S3 inline as object body, fits SQS (256 KB body size limit — **marginal**)

**Verdict:** sweet spot for intra-fleet, same-datacenter boundaries. Encode cost is acceptable if the encode happens once and the bytes are reused across multiple consumers. See [[mjpeg-and-still-image-formats]] for Actuate's existing heavy use of JPEG (TurboJPEG encode at quality 95, 4:2:0 chroma, in `actuate-pipeline/steps/pre_processors/`).

### Encoded packet ([[h264-deep-dive|H.264]] or [[h265-hevc-deep-dive|H.265]])

Inter-frame codec (I/P/B frames). Each packet is part of a frame; multiple packets may be needed per frame.

- **Size per frame:** 5–50 KB on average (10–20 KB typical for 1080p30 at 2–4 Mbps camera bitrate)
- **CPU cost on send:** zero — pass through from camera/decoder without re-encoding
- **CPU cost on receive:** must be paid by decoder (10–50 ms per frame, depending on HW acceleration)
- **Compression ratio:** 50–200× vs raw
- **[[gop-keyframe-fundamentals|GOP]] / keyframe awareness:** **critical constraint** — cannot drop arbitrary packets. A P-frame or B-frame without its reference (I-frame) orphans the entire subsequent frame chain until the next IDR (Instantaneous Decoder Refresh, a.k.a. keyframe). See [[gop-keyframe-fundamentals]].
- **Distribution:** fits NATS (5–50 KB << 1 MB), fits S3 (unbounded), fits SQS (with care — needs fragmentation per 256 KB), fits Redis (marginal — clusters tuned for smaller messages)

**Verdict:** excellent bandwidth efficiency; moves decode cost to the receiver; **only viable if the receiver can consume [[h264-deep-dive|H.264]] packets in-order and knows the [[gop-keyframe-fundamentals|GOP]] structure.** Works well when the consumer is a specialized fleet (e.g., a decoder fleet that immediately re-encodes to JPEG or passes to inference). Breaks down if the consumer is generic and doesn't understand [[gop-keyframe-fundamentals|GOP]].

### fMP4 fragment (self-contained streaming unit)

Container format with both video codec ([[h264-deep-dive|H.264]]/[[h265-hevc-deep-dive|H.265]]) and framing metadata.

- **Size:** few hundred KB per fragment (fMP4 `moof` box overhead ~2–5 KB, plus the media data)
- **CPU cost on send:** zero (pass-through from decoder or camera)
- **CPU cost on receive:** same as raw packets, but the `moof` box carries codec context so no separate SPS/PPS handling
- **Resumable transport:** fragment boundaries are atomic — can pause/resume a stream without codec state loss (see [[containers-overview]] for fMP4 structure)
- **Distribution:** fits S3 as object body, fits NATS, fits WebSocket (Actuate's [[autopatrol/_summary|AutoPatrol (H1.2)]] already consumes fMP4 over WebSocket), **not typical for Redis** (larger messages, framing overhead)

**Verdict:** strongest choice for resumable / fault-tolerant transport. Used by [[protocol-latency-comparison|AutoPatrol / VCH]] via WebSocket. Best for architectures where the boundary is a streaming interface (WebSocket, gRPC streaming, or S3 multipart) rather than discrete message queues.

## Cross-matrix: payload format × transport

Which combinations work? Which introduce friction?

| Payload | Redis Streams | NATS JetStream | SNS/SQS | S3 refs | WebSocket/gRPC stream |
|---------|---------------|----------------|---------|--------|----------------------|
| **Raw ndarray (BGR)** | ❌ exceeds cap | ❌ exceeds cap | ❌ (SQS 256 KB hard limit) | ✅ but wasteful | ❌ buffer overhead |
| **JPEG bytes** | ✅ standard path | ✅ standard path | ⚠️ (SQS marginal) | ✅ s3 put/get | ✅ natural |
| **[[h264-deep-dive|H.264]] packets** | ⚠️ (need [[gop-keyframe-fundamentals|GOP]] tracking) | ✅ works | ⚠️ needs fragmentation | ✅ unbounded | ✅ works if stateless |
| **fMP4 fragment** | ⚠️ (large for streams) | ✅ works | ❌ (too large + SQS cap) | ✅ natural | ✅ native |

**Key observations:**

1. **JPEG + Redis/NATS** is the proven Actuate pattern. Encode once at the source, store compact bytes everywhere.
2. **[[h264-deep-dive|H.264]] packets** demand **GOP-aware consumers** — only viable if the receiving fleet (or stage boundary) has a decoder that understands codec state.
3. **S3-refs** (storing the frame in S3 and passing a `{bucket}/{key}` reference via the message bus) is attractive for large payloads (fMP4, raw numpy) but introduces latency (S3 PUT/GET roundtrip) and distributed failure modes (what if S3 write succeeds but the message bus PUT fails?).
4. **fMP4** is resumable and framing-clean but oversized for discrete-message buses; best suited to streaming transports.

## Codec choice and decode locality

A critical insight: **where decode happens determines what payload format you can ship.**

Today's connector pulls a camera [[rtsp-deep-dive|RTSP]] stream, decodes it to numpy via [[pyav-entity|PyAV]] (see [[h264-deep-dive]]), runs inference on the decoded frame, and encodes to JPEG for storage. If the fleet boundary sits **before** decode (raw [[h264-deep-dive|H.264]] packets cross the boundary), the receiving fleet must pay the decode cost. If the boundary sits **after** decode (numpy or JPEG crosses), the receiving fleet uses what's already decoded.

This choice cascades across the five proposals:

- **[[2026-04-16_proposal-a-minimal-split|A — Minimal Split]]:** in-pod decode unchanged; payload format only matters between puller-fleet and pipeline-fleet within the same logical site unit. Likely JPEG or numpy.
- **[[2026-04-16_proposal-b-stage-fleets|B — Stage Fleets]]:** every pipeline stage is a boundary. Each boundary is a codec choice. Pre-processing → detection frames are JPEG (already the standard). Detection → alerting might be JPEG or numpy. This proposal forces the most explicit payload format decisions.
- **[[2026-04-16_proposal-c-camera-worker|C — Camera-Worker]]:** workers decode → process; boundaries are mostly alerts and control-plane metadata, not frames. Workers scale per-camera; fleet boundaries are sparse.
- **[[2026-04-16_proposal-d-event-driven|D — Event-Driven NATS+S3]]:** S3-ref is the natural fit. Messages carry `{bucket}/{key, timestamp, resolution}`, not the frame itself. Decouples producer (puller fleet) from consumer (processor fleet) via durability.
- **[[2026-04-16_proposal-e-hybrid-sidecar|E — Hybrid Sidecar]]:** smart pullers decode in-pod and ship JPEG/numpy to a stateful core. Similar locality to A but with explicit puller sizing.

## Preliminary proposal hints

**A — Minimal Split:** 
Payload format is **internal detail**. Puller and pipeline exchange JPEG or numpy in-memory or via Redis within the same site pod. No major codec decision. Risk: doesn't decouple codec evolution from puller/pipeline coupling.

**B — Stage Fleets:** 
Most explicit codec decisions. Pre-processing → detection frames stay JPEG (proven). Detection → alert → clip generation may keep JPEG or shift to [[h264-deep-dive|H.264]] packets if the alert-sender fleet is decoder-capable (needs design). Advantage: forces clarity. Risk: N boundary decisions instead of 1.

**C — Camera-Worker:** 
Workers are the decode authority. Payload formats between workers and alert-sender are likely JPEG or metadata-only. Boundaries are sparse. Good isolation; limits payload format variability.

**D — Event-Driven NATS+S3:** 
S3-ref dominates. Pullers write frames to S3 (or reference pre-stored streams), post `{bucket}/{key, frame_id, timestamp}` to NATS, and event-driven processors consume on demand. Excellent decoupling. Risk: adds S3 dependency and latency (PUT must complete before message is useful).

**E — Hybrid Sidecar:** 
Pullers decode and produce JPEG or numpy; core processes these. Closest to today's shape. Payload format between puller and core is most constrained (probably JPEG or numpy, with encode/decode at boundaries).

## Open questions (data needed for concreteness)

1. **Per-camera JPEG bandwidth at quality 95:** measure 100 representative cameras across integrations (different scene complexity, motion profiles, resolutions). Feed into transport cost model.
2. **[[h264-deep-dive|H.264]] packet distribution shape:** is the ~10 KB average per-frame rule correct for our mix of cameras? What's the 95th percentile?
3. **Redis cluster configuration audit:** what's the actual per-message size cap in prod? Some customers may have tighter limits than others.
4. **Decode-at-scale benchmarks:** how much CPU is paid per frame for [[h264-deep-dive|H.264]] decode (software) vs hardware-accelerated (if available on EKS nodes)?
5. **S3 write latency to each region:** baseline PUT latency for the EU and US clusters. Feeds into D feasibility.
6. **Stateful cache behavior:** if E (or B) shifts to per-stage boundaries, how much state (trackers, windows) must be re-initialized at each boundary vs shared?

---

> **Status: preliminary draft (2026-04-27).** Designed to land in fleet-architecture's context. Numbers are order-of-magnitude; needs benchmarking before binding to a proposal selection. The matrix and codec-choice constraints are solid; the per-proposal implications are forward-looking and should be validated against each proposal's PoC.

**See also:**
- [[fleet-architecture/_summary]] — the five proposals and cross-cutting design list
- [[2026-04-16_frame-transport-comparison]] — Redis/NATS/SNS/S3 transport comparison (payload-agnostic)
- [[decode-locality-per-proposal]] — companion note defining where decode happens in each proposal (cross-reference when drafted)
- [[codecs-overview]], [[h264-deep-dive]], [[h265-hevc-deep-dive]], [[mjpeg-and-still-image-formats]] — codec details
- [[gop-keyframe-fundamentals]] — why [[h264-deep-dive|H.264]] packet transport is stateful
- [[containers-overview]] — fMP4 and MP4 structure
- [[protocol-latency-comparison]] — transport layer details (WebSocket, gRPC, S3 latency)
