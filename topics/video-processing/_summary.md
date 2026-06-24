---
title: Video Processing
type: summary
topic: video-processing
tags: [video, codec, streaming, ffmpeg, gstreamer, opencv, kvs, mediaconvert, rtsp, hls, webrtc]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
---

# Video Processing

Open-ended research topic covering the **video processing landscape** -- the tools, codecs, containers, transport protocols, and managed services that move pixels around -- mapped onto **how Actuate uses them today**. Engineering reference + strategic decision-making in equal weight.

Coverage scope (see [[knowledgebase/topics/video-processing/reading-list]] for alternatives + peripheral tools):

- **Tools / libraries:** [[ffmpeg-entity|FFmpeg]], [[gstreamer-entity|GStreamer]], [[opencv-entity|OpenCV]], [[pyav-entity|PyAV]], [[imageio-entity|imageio]]
- **AWS managed services:** [[aws-kvs-entity|Kinesis Video Streams]], Elemental [[aws-mediaconvert-entity|MediaConvert]] / [[aws-medialive-entity|MediaLive]] / [[aws-mediapackage-entity|MediaPackage]], [[aws-elemental-live-entity|Elemental Live]] (on-prem), [[aws-rekognition-video-entity|Rekognition Video]], IVS
- **Codecs:** [[h264-deep-dive|H.264]], [[h265-hevc-deep-dive|H.265]] / [[h265-hevc-deep-dive|HEVC]], [[av1-vp9-future|AV1]], [[av1-vp9-future|VP9]], [[mjpeg-and-still-image-formats|MJPEG]]
- **Containers:** MP4, MKV, [[mpeg-ts-over-udp|MPEG-TS]], fMP4, WebM
- **Transport protocols:** [[rtsp-deep-dive|RTSP]], [[rtmp-and-srt|RTMP]], [[hls-and-dash|HLS]], [[hls-and-dash|DASH]], [[webrtc-deep-dive|WebRTC]], [[rtmp-and-srt|SRT]], [[mpeg-ts-over-udp|MPEG-TS over UDP]]
- **Hardware acceleration:** [[hardware-accelerated-codecs|NVENC]] / [[hardware-accelerated-codecs|NVDEC]], [[nvidia-deepstream|NVIDIA DeepStream]], [[hardware-accelerated-codecs|QuickSync]], [[hardware-accelerated-codecs|VAAPI]], AMF, [[hardware-accelerated-codecs|VideoToolbox]]
- **Out of scope:** non-AWS clouds (Azure Media Services, GCP Video Intelligence) -- listed in reading list only for awareness

## Why this topic exists

Video processing is the substrate of the Actuate platform but it's been treated as an implementation detail. Decisions like "do we re-encode this clip?", "should we move to [[kvs-components|KVS]]?", "is [[webrtc-deep-dive|WebRTC]] viable for live preview?", "what's the latency budget of our [[rtsp-deep-dive|RTSP]] pull path?" -- all repeatedly come up in connector work, alert clip generation, settings/UI features, and partner integrations. Each time we either rediscover the answer or pick a default without knowing the alternatives.

This topic is the persistent answer.

## Topic taxonomy

```
video-processing/
  notes/
    concepts/             # technical primitives (codecs, GOPs, latency budgets, transport tradeoffs)
    entities/             # specific tools and services (FFmpeg, GStreamer, KVS, MediaConvert, ...)
    syntheses/            # cross-cutting decisions and mapping to Actuate use cases
  reading-list.md         # catalog of alternatives + peripheral tools
  sources/                # ingested source material (later)
```

## Major sub-areas (with deep-dive notes)

### 1. Codecs and containers
[[codecs-overview]] | [[containers-overview]] | [[h264-deep-dive]] | [[h265-hevc-deep-dive]] | [[mjpeg-and-still-image-formats]] | [[av1-vp9-future]] | [[gop-keyframe-fundamentals]] | [[hardware-accelerated-codecs]]

### 2. Transport / streaming protocols
[[rtsp-deep-dive]] | [[rtmp-and-srt]] | [[hls-and-dash]] | [[webrtc-deep-dive]] | [[mpeg-ts-over-udp]] | [[protocol-latency-comparison]]

### 3. FFmpeg
[[ffmpeg-entity]] | [[ffmpeg-command-anatomy]] | [[ffmpeg-libav-libraries]] | [[ffmpeg-python-bindings]] | [[ffmpeg-hardware-acceleration]] | [[ffmpeg-filtergraphs]]

### 4. GStreamer
[[gstreamer-entity]] | [[gstreamer-pipeline-model]] | [[gstreamer-vs-ffmpeg]] | [[nvidia-deepstream]]

### 5. OpenCV and frame-level libraries
[[opencv-entity]] | [[cv2-videocapture-internals]] | [[pyav-entity]] | [[imageio-entity]] | [[frame-extraction-strategies]]

### 6. AWS video services
[[aws-kvs-entity]] | [[aws-mediaconvert-entity]] | [[aws-medialive-entity]] | [[aws-mediapackage-entity]] | [[aws-elemental-live-entity]] | [[aws-rekognition-video-entity]] | [[aws-ivs-entity]] | [[aws-video-services-decision-matrix]]

### 7. Cross-cutting Actuate mapping (synthesis)
[[actuate-video-pipeline-walkthrough]] -- end-to-end map of every place video flows through Actuate
[[actuate-clip-generation-flow]] -- alert clip assembly, S3 storage, monitoring-center delivery
[[actuate-frame-ingest-decode-paths]] -- per-VMS decode [[strategies]], what library handles what
[[actuate-build-vs-buy-tradeoffs]] -- where AWS managed services could replace homegrown code

## Cross-references to other topics

| KB topic | Relationship |
|----------|--------------|
| [[vms-connector/_summary]] | Primary consumer of decode/transport primitives; AsyncInferencePool feeds on decoded frames |
| [[actuate-libraries/_summary]] | `actuate-pullers` and `actuate-alarm-senders` host most of the codec/transport logic |
| [[fleet-architecture/_summary]] | Frame-transport design (between fleet pods) is a video-processing problem |
| [[integrations/kvs/_summary]] | One specific consumer of [[aws-kvs-entity|AWS KVS]] |
| [[integrations/rtsp/_summary]] | Generic [[rtsp-deep-dive|RTSP]] integration, primary protocol surface |
| [[ai-models/_summary]] | YOLO / VLM consumers of decoded frame batches |
| [[watchman/_summary]] | VLM analysis of video clips (clip generation upstream) |
| [[autopatrol/_summary]] | Patrol mode pulls discrete frame snapshots, different latency profile than real-time |
| [[infrastructure/_summary]] | Hardware accel availability on EKS nodes; ARM vs x86 decode tradeoffs |

## Key questions this topic should be able to answer

1. **Decode**: where in the codebase do we turn a stream/file into a numpy frame, and what library is doing it? What are we paying for in CPU?
2. **Encode**: when we save a clip to S3 for an alert, what codec/container/quality settings do we use? Are we re-encoding when we shouldn't be?
3. **Transport**: the latency floor for each protocol we support, and which integration uses which.
4. **AWS managed**: which managed service would replace which piece of homegrown code, and what's the cost/lock-in tradeoff?
5. **Hardware accel**: do our EKS nodes have GPU encode/decode? Are we using it? Should we?
6. **Strategic**: can we get to <500ms end-to-end live preview? Is [[webrtc-deep-dive|WebRTC]] the lever? Is [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] the lever?

## Status

- **2026-04-27 (seed wave)**: Topic seeded. 41 notes across 7 parallel deep-dive workstreams (24 concepts, 12 entities, 5 syntheses). Connector cross-references anchored to specific file paths in `actuate-libraries` / `vms-connector` via a scout pass. Reading list catalogues alternatives + RFCs/specs.
- **2026-04-27 (follow-up wave)**: 4 follow-up audits + 4 fleet-architecture bridge syntheses + 1 supplementary EKS-substrate concept landed. Total: **50 notes**. Findings promoted to [[mark-todos]] §15 as actionable workstreams. `/kb-relink` skill drafted to handle wikilink enrichment on cadence.
- **2026-04-27 (relink pass)**: Thorough wikilink enrichment across 3 syntheses + 2 concepts. Key anchors: [[pyav-entity]], [[ffmpeg-entity]], [[gstreamer-entity]], [[opencv-entity]], [[aws-kvs-entity]], [[h264-deep-dive]], [[h265-hevc-deep-dive]], [[aws-mediaconvert-entity]], [[aws-mediapackage-entity]], [[aws-ivs-entity]]. Coverage increased from ~4 files to 5+ files with dense cross-referencing.

## Follow-ups (resolved during the seed pass — see notes for full detail)

| Original concern | Outcome | Note |
|---|---|---|
| [[gstreamer-entity|GStreamer]] [[rtsp-deep-dive|RTSP]] path silently H.264-only | **Latent trap, zero callers** -- recommend deletion of `GstUrlFramePuller` | [[gst-rtsp-h264-only-audit]] |
| Downstream MP4 muxer location | **Located** -- ECS Fargate `prod-queue-immix-consumer`; produces AVI/Xvid despite `.mp4` filename | [[immix-mp4-mux-downstream]] |
| [[connector-decoder-routing-map|Connector decoder routing map]] | **22 integration_types mapped**; hikcentral splits [[pyav-entity|PyAV]] / legacy-OpenCV by motion flag | [[connector-decoder-routing-map]] |
| Connector Dockerfile system-deps | **Audited** -- GPU [[ffmpeg-entity|FFmpeg]] builds missing `--enable-gnutls` (silent HTTPS/RTSPS failure) | [[connector-docker-system-deps]] |
| EKS GPU substrate availability | **Substrate exists** (G4dn/G5/G6/G6e via Karpenter) -- but connector pods don't tolerate GPU nodes | [[eks-prod-node-pool-gpu-availability]] |
| [[kvs-components|KVS]] pipeline JPEG round-trip | Documented; tracked as a [[mark-todos]] §15c migration item | [[gstreamer-vs-ffmpeg]] + [[aws-kvs-entity]] |
| Two parallel decoder paths | Documented; migration completion is a pre-req for [[2026-04-16_proposal-c-camera-worker|fleet proposal C]] | [[connector-decoder-routing-map]] |
| fish2pano subprocess no timeout | Tracked as [[mark-todos]] §15a quick fix | -- |

## Fleet-architecture bridges (preliminary syntheses)

These syntheses bridge video-processing knowledge into the fleet-architecture proposal evaluation. All marked preliminary; need hard data before binding to a PoC selection.

- [[frame-transport-payload-formats]] -- codec × transport tradeoff matrix (raw / JPEG / encoded packet / fMP4 vs Redis / NATS / S3-ref)
- [[decode-locality-per-proposal]] -- where decode happens in proposals A-E, what crosses the wire, hwaccel implications
- [[gpu-substrate-and-fleet-placement]] -- NVIDIA/Karpenter scheduling primitives; today's substrate vs proposal needs
- [[kvs-webrtc-as-fleet-frame-plane]] -- [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] verdict: weak fit for inter-pod; strong candidate for outbound live-preview / [[watchman-repo|Watchman]]

## See also

- Reading list: [[knowledgebase/topics/video-processing/reading-list]]
