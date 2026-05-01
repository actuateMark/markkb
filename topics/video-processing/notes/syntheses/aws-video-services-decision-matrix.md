---
title: "AWS Video Services Decision Matrix (for Actuate)"
type: synthesis
topic: video-processing
tags: [aws, decision-matrix, build-vs-buy, kvs, mediaconvert, medialive, mediapackage, ivs, rekognition, immix]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - _index.md
  - topics/personal-notes/notes/daily/2026-04-27.md
  - topics/video-processing/_summary.md
  - topics/video-processing/notes/entities/aws-ivs-entity.md
  - topics/video-processing/notes/entities/aws-kvs-entity.md
  - topics/video-processing/notes/entities/aws-medialive-entity.md
  - topics/video-processing/notes/entities/aws-rekognition-video-entity.md
  - topics/video-processing/notes/syntheses/actuate-build-vs-buy-tradeoffs.md
  - topics/video-processing/notes/syntheses/actuate-clip-generation-flow.md
  - topics/video-processing/notes/syntheses/kvs-webrtc-as-fleet-frame-plane.md
incoming_updated: 2026-05-01
---

# AWS Video Services Decision Matrix (for Actuate)

The seven AWS video services covered in this topic ([[aws-kvs-entity]], [[aws-mediaconvert-entity]], [[aws-medialive-entity]], [[aws-mediapackage-entity]], [[aws-elemental-live-entity]], [[aws-rekognition-video-entity]], [[aws-ivs-entity]]) overlap, share marketing copy, and are routinely confused. This note is the opinionated answer to **"for use case X, which AWS service is the right reach (or none)?"** — grounded in Actuate's actual workload shape (5-30 fps surveillance feeds, thousands of cameras, low concurrent-viewer count per feed, high frame-throughput on inference, on-prem viability matters).

Verdict legend: **OK** = fits, default-yes / **Maybe** = plausible but not obvious / **No** = wrong tool.

## The matrix

| Use case | [[kvs-components|KVS]] Producer | [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] | [[aws-mediaconvert-entity|MediaConvert]] | [[aws-medialive-entity|MediaLive]] | [[aws-mediapackage-entity|MediaPackage]] | IVS (std) | IVS Real-Time | [[aws-rekognition-video-entity|Rekognition Video]] | S3 + custom |
|---|---|---|---|---|---|---|---|---|---|
| **Live frame ingest from cameras ([[rtsp-deep-dive|RTSP]])** | No (overkill, expensive) | No (publisher SDK gap) | No (file-only) | No (per-channel cost wrong shape) | No (packager, not ingest) | No (RTMPS-only ingest) | No ([[webrtc-deep-dive|WebRTC]] publisher only) | No (analytics, not transport) | **OK** *(today: [[rtsp-deep-dive|RTSP]] pull in connector pods)* |
| **Live frame ingest from KVS-publishing partners** | **OK** *(actively used)* | No | No | No | No | No | No | No | No |
| **Clip-replay UI (low-volume, internal ops)** | Maybe *(if clip already in [[kvs-components|KVS]])* | No | Maybe *(if format conversion needed)* | No | No | No | No | No | **OK** *(pre-rendered MP4 in S3 + signed URL)* |
| **Clip-replay UI (high-volume, customer-facing)** | No | No | **OK** *(transcode pipeline)* | No | **OK** *(packaging + DRM)* | Maybe | No | No | Maybe |
| **Partner clip delivery (per-partner format)** | No | No | **OK** *(job templates per partner profile)* | No | No | No | No | No | Maybe *([[ffmpeg-entity|ffmpeg]]-on-Lambda)* |
| **Live-preview to dispatcher (sub-second, internal)** | No | **OK** *(best-fit if we stay AWS-native)* | No | No | No | No | Maybe *(per-participant cost concern)* | No | Maybe *(self-host Pion / LiveKit / aiortc)* |
| **Archive + search (long-term clip retention)** | Maybe *(retention up to 10 yr; expensive)* | No | No | No | No | No | No | No | **OK** *(S3 lifecycle policies + thumbnail index)* |
| **Custom-model inference per frame** | No | No | No | No | No | No | No | No | **OK** *(in-house YOLO + VLM stack)* |
| **Generic content-moderation on user-uploaded clips** | No | No | No | No | No | No | No | **OK** *(textbook Rekognition fit)* | No |
| **Scheduled patrol-mode frame snapshots** | No | No | No | No | No | No | No | No | **OK** *(today: [[actuate-pullers]] + cron)* |
| **Public live-event broadcast (many viewers)** | No | No | No | Maybe *(if broadcast-grade needed)* | **OK** | **OK** *(simplest path)* | No | No | No |
| **Interactive multi-participant low-latency (e.g. video room)** | No | Maybe | No | No | No | No | **OK** | No | Maybe *(self-host)* |
| **On-prem-required encoding (contractual)** | No | No | No | No | No | No | No | No | **OK** *([[ffmpeg-entity|ffmpeg]] / [[gstreamer-entity|GStreamer]] on customer hardware)* + [[aws-elemental-live-entity|Elemental Live]] (if AWS-branded HW required) |

## What we use today

- **[[aws-kvs-entity]] Producer (read-side only)** — `actuate-pullers/kvs/` consumes partner-published [[kvs-components|KVS]] streams via boto3 `kinesis-video-media:get_media`, MKV chunks demuxed by [[gstreamer-entity|GStreamer]]. **Known inefficiency:** in-pipeline JPEG re-encode round-trip (`appsrc ! matroskademux ! decodebin ! videoconvert ! jpegenc ! appsink` → `cv2.imdecode`) — wastes CPU. See [[aws-kvs-entity]] for line refs.
- **S3 + custom (the homegrown path)** — frame ingest via direct [[rtsp-deep-dive|RTSP]] pulls in connector pods, JPEGs to S3, in-house model stack on EC2 G5/G6, alert clips written to S3 ([[actuate-clip-generation-flow]], [[actuate-frame-ingest-decode-paths]]).
- **Custom alarm senders** — Immix, Sureview, etc. via `actuate-alarm-senders`. Note: Immix `use_mp4=True` mode hands off to a downstream FIFO consumer that does the MP4 muxing; that consumer is **not** in the libraries scouted and may or may not already use [[aws-mediaconvert-entity|MediaConvert]]. Worth confirming.
- **Nothing else.** [[aws-mediaconvert-entity|MediaConvert]], [[aws-medialive-entity|MediaLive]], [[aws-mediapackage-entity|MediaPackage]], [[aws-elemental-live-entity|Elemental Live]], [[aws-rekognition-video-entity|Rekognition Video]], IVS, IVS Real-Time — zero usage.

## What we should plausibly evaluate

In rough priority order of "likely value × likely cost-feasibility":

1. **[[aws-mediaconvert-entity|MediaConvert]] for partner clip delivery + format normalization.** If the Immix MP4 pipeline (and per-partner clip delivery generally) is currently [[ffmpeg-entity|ffmpeg]]-shelled in a Lambda, swapping to [[aws-mediaconvert-entity|MediaConvert]] removes operational toil and gives us deterministic per-job cost. The win is operational, not transport-cost. **First step:** confirm where the Immix MP4 muxing actually lives today (downstream of `event_queue_immix_alarm.fifo`, per `actuate-libraries/actuate-alarm-senders/src/actuate_alarm_senders/immix/immix_alert_sender.py:88-100`). If it's already [[aws-mediaconvert-entity|MediaConvert]], document; if not, do a cost-equivalence sketch.
2. **[[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] for fleet-pod-to-fleet-pod and pod-to-browser frame transport.** If [[fleet-architecture/_summary]] decides we need a managed signaling layer + STUN/TURN for cross-pod live-frame movement, [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] is the AWS-native answer. Cost shape (per-channel-minute) is reasonable. Gives us live-preview-to-dispatcher as a secondary win.
3. **[[aws-mediapackage-entity|MediaPackage]] v2 + [[aws-mediaconvert-entity|MediaConvert]] for a customer-facing clip-replay UI.** Only if/when we ship that product surface. Pre-condition: [[aws-mediaconvert-entity|MediaConvert]] evaluation (#1) succeeded.
4. **Fix the [[kvs-components|KVS]] puller JPEG round-trip** — internal optimization, not a service change, but should land before any [[kvs-components|KVS]] volume increases. See [[aws-kvs-entity]] and [[hardware-accelerated-codecs]].

## What doesn't fit our model and why

- **[[aws-medialive-entity|MediaLive]]** — per-channel-hour pricing assumes one channel = one premium broadcast feed. Our shape is thousands of low-bitrate cameras. Off by ~3 orders of magnitude on cost. Use only if we ever ship a "broadcast-grade situation room" with a small curated set of premium feeds.
- **[[aws-elemental-live-entity|Elemental Live]] (on-prem)** — capex hardware appliances for broadcast facilities. Strategic departure from cloud-first architecture. Only relevant if a future enterprise customer writes "must terminate encoding on-prem in AWS-branded hardware" into a contract. Hypothetical.
- **[[aws-rekognition-video-entity|Rekognition Video]] (and Custom Labels)** — generic models, per-minute pricing, opaque tuning. Wrong on every axis for surveillance-specific high-throughput inference. Our home-rolled stack ([[ai-models/_summary]], [[watchman/_summary]]) is the deliberate, correct call. Custom Labels specifically is also being deprecated by AWS; even if we wanted it, its lifespan is questionable.
- **IVS standard** — RTMPS-in, [[hls-and-dash|HLS]]-out. Wrong input format for our cameras ([[rtsp-deep-dive|RTSP]]), wrong output format for our internal-tooling latency budget (3-5s [[hls-and-dash|HLS]]), and the "many viewers per feed" pricing discount doesn't apply to dispatcher use. Customer-facing live-broadcast product would be its niche; not on the roadmap.
- **IVS Real-Time** — closer fit than standard IVS for live preview, but per-participant pricing × per-camera publisher cost stacks badly at fleet scale, and we'd still need an in-pod RTSP-to-[[webrtc-deep-dive|WebRTC]] bridge regardless. [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] is the better AWS-native bet; self-hosted Pion / LiveKit is the better non-AWS bet.

## Headline takeaway

The **only AWS video service that fits our shape today is [[kvs-components|KVS]] Producer (read-side)**, and that fit is determined by partner-side decisions, not ours. Everything else in the AWS family is shaped for broadcast / publishing / consumer-facing video, which is not the Actuate workload.

**Where we will eventually want to revisit AWS video services:**

- **[[aws-mediaconvert-entity|MediaConvert]]** — clip-format-conversion pipeline; first AWS service likely to enter our stack for a non-KVS reason.
- **[[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]]** — frame-transport substrate, when [[fleet-architecture/_summary]] decides we need one.
- **[[aws-mediapackage-entity|MediaPackage]] v2** — only if we ship a public clip-replay product. Tied to [[aws-mediaconvert-entity|MediaConvert]] preceding it.

Everything else: **document, don't adopt.** This note is the persistent answer for the next time someone asks.

## See also

- [[aws-kvs-entity]] · [[aws-mediaconvert-entity]] · [[aws-medialive-entity]] · [[aws-mediapackage-entity]] · [[aws-elemental-live-entity]] · [[aws-rekognition-video-entity]] · [[aws-ivs-entity]]
- [[actuate-build-vs-buy-tradeoffs]] (broader build-vs-buy framing across the topic)
- [[actuate-clip-generation-flow]] (the clip pipeline these AWS services would plug into)
- [[fleet-architecture/_summary]] (cross-topic: frame-transport question)
- [[ai-models/_summary]] · [[watchman/_summary]] (why we don't use Rekognition)
- [[reading-list]] for adjacent services (MediaTailor, MediaConnect, Elemental Conductor, GroundTruth Video)

## Actuate touchpoints

This entire note is Actuate-specific by design — every row of the matrix is a concrete Actuate use case, every verdict reflects our cost/latency/scale shape. Concrete pointers:

- **Active integration:** [[aws-kvs-entity]] read-side via `actuate-libraries/actuate-pullers/src/actuate_pullers/kvs/` (`kvs_puller.py`, `kvs_ingestor.py`).
- **First likely new adoption:** [[aws-mediaconvert-entity]] for partner-clip transcoding, downstream of `event_queue_immix_alarm.fifo` in the Immix MP4 path.
- **Strategic evaluate-next:** [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] for fleet/dispatcher live preview, gated on [[fleet-architecture/_summary]] decisions.
- **Confirmed-skip:** [[aws-medialive-entity|MediaLive]], [[aws-elemental-live-entity|Elemental Live]], IVS standard, IVS Real-Time, [[aws-rekognition-video-entity|Rekognition Video]], Custom Labels — for the reasons above. Revisit only on contractual / strategic trigger.
