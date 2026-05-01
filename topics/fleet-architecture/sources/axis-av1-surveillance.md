---
title: "Source: AV1 Codec for Video Surveillance — Axis Communications"
type: source
topic: fleet-architecture
tags: [source, codec, av1, h264, h265, compression, video-encoding, surveillance]
url: https://newsroom.axis.com/blog/av1-codec-video-surveillance
ingested: 2026-04-21
author: kb-bot
---

# AV1 Codec for Video Surveillance — Axis Communications

Senior Expert Engineer perspective on AV1 adoption across Axis ARTPEC silicon, covering codec-to-codec compression ratios on real surveillance footage.

## Compression Ratios (Measured on ARTPEC Hardware)

Two validated baselines for detection-window clip sizing:

- **AV1 vs H.264 (ARTPEC-8 baseline):** ~40% bitrate reduction at equivalent perceptual quality. Most common fleet migration path given H.264's installed-base dominance.
- **AV1 vs H.265 (ARTPEC-9 upgrade path):** ~25% bitrate reduction over the H.265 encoder on ARTPEC-8.

These figures apply to continuous-stream surveillance (static camera angle, mixed motion). Detection-window clips — short clips of 10–30 frames around a motion/detection event — would likely compress more favourably than continuous streams because frame-to-frame change is concentrated rather than ambient.

## Hardware Gating

AV1 encoding requires ARTPEC-9 SoC at the camera edge. Our connector does NOT encode at the camera — it receives decoded frames over RTSP — so the relevant question is **software encoder availability on the EKS node**, not camera hardware. Axis's AV1 numbers are for camera-side hardware encoding; software AV1 (libsvtav1, libaom) carries substantially higher CPU cost than libx264/libx265. **No CPU overhead figures for software encoding are provided in the article** — this is a critical gap.

## Decoder Compatibility

AV1 is supported by all major browsers, operating systems, and mobile devices per the article. Downstream consumers (Immix, alert-UI) viewing clips via presigned URL would be unaffected by a connector-side AV1 encode.

## Forensic Quality Note

At equivalent bitrate, AV1 better preserves fine detail (license plates, text) than H.264, which degrades those regions first under DCT block compression. For detection windows, frames that triggered the detection are the high-value targets; AV1's better preservation at low bitrate is forensically relevant.

## Production Gaps

The article does not address: short-clip (GOP-of-1 or short-GOP) encoding latency, in-process encoding CPU cost on server hardware, fragmented MP4 container compatibility with AV1, or keyframe interval tuning for random-access in short clips.

## Relevance to Fleet Proposals

- **A — Minimal Split**: In-process AV1 encode compatible with A's monolithic pipeline. CPU cost lands in the existing pipeline pod; no architectural change.
- **B — Stage Fleets**: Dedicated "encode stage" fleet owns AV1; B's stage decomposition makes right-sizing encode CPU independently natural. AV1's higher CPU cost per frame makes this isolation more valuable.
- **C — Camera-Worker**: Each worker encodes for its bin-packed cameras. AV1 CPU overhead folds into VPA sizing per worker.
- **D — Event-Driven**: Encode worker consumes window-close events from NATS JetStream; codec choice orthogonal to D's transport layer.
- **E — Hybrid Sidecar**: Detection core pod encodes before S3 promotion. AV1 may push the detection pod into bursty-CPU profile, reinforcing the [[vpa-bimodal-workload-limitation]] concern.

## Relevance to Frame-Storage Design Directions

- **In-process encoding (§11)**: Directly relevant. 40% vs H.264 / 25% vs H.265 bitrate reductions quantify the data-volume benefit. However, §11's primary lever is API-call reduction (22 → 2 calls/window); AV1's compression advantage is a secondary S3 storage-cost benefit, not the headline win.
- **In-cluster blob + conditional promotion (§12)**: Orthogonal to codec choice. In-cluster blob holds raw JPEGs; AV1 compression happens at promotion time. Relevant only at the final encode step.
- **API-call cost structure**: Not applicable. AV1 reduces byte size of the single promoted clip but doesn't change call count.

## Source
https://newsroom.axis.com/blog/av1-codec-video-surveillance
