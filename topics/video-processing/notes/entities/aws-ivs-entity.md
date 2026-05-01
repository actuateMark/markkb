---
title: AWS Interactive Video Service (IVS)
type: entity
topic: video-processing
tags: [aws, ivs, live-streaming, low-latency, webrtc, rtmps, hls, real-time]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/2026-04-27.md
  - topics/video-processing/_summary.md
  - topics/video-processing/notes/concepts/av1-vp9-future.md
  - topics/video-processing/notes/concepts/protocol-latency-comparison.md
  - topics/video-processing/notes/concepts/rtmp-and-srt.md
  - topics/video-processing/notes/entities/aws-medialive-entity.md
  - topics/video-processing/notes/entities/aws-mediapackage-entity.md
  - topics/video-processing/notes/syntheses/actuate-build-vs-buy-tradeoffs.md
  - topics/video-processing/notes/syntheses/actuate-clip-generation-flow.md
  - topics/video-processing/notes/syntheses/aws-video-services-decision-matrix.md
incoming_updated: 2026-05-01
---

# AWS Interactive Video Service (IVS)

## What it is

Low-latency live streaming as a managed service, aimed at "broadcaster → many viewers" use cases (live shopping, gaming streamers, fitness, auctions). It is the simplest end-to-end path AWS sells: you push a stream in, your viewers pull it out, AWS handles encoding + packaging + edge delivery.

There are **two distinct flavors** under the IVS brand, sharing only branding:

- **IVS (standard / "Low-Latency")** — RTMPS in, [[hls-and-dash|HLS]] out. End-to-end glass-to-glass latency ~3-5 seconds in "low-latency" mode (down from ~8-10 s in normal mode). Browser-native via the IVS Player JS SDK or any [[hls-and-dash|HLS]] player. Designed for unidirectional broadcast to many viewers.
- **IVS Real-Time** — [[webrtc-deep-dive|WebRTC]]-based, "stages" model. Sub-second latency. Designed for interactive multi-participant scenarios (host + co-hosts + audience) with low-latency two-way exchange. Uses a stages/tokens API rather than channels/keys.

Standard IVS is essentially "[[rtmp-and-srt|RTMP]]-to-HLS as a service with CDN bundled". Real-Time is "managed [[webrtc-deep-dive|WebRTC]] SFU as a service".

## API surface

`boto3.client("ivs")` (standard) and `boto3.client("ivs-realtime")` (Real-Time) are independent.

**Standard IVS (RTMPS → [[hls-and-dash|HLS]]):**

- `create_channel(Type='STANDARD'|'BASIC', LatencyMode='LOW'|'NORMAL', Authorized=False)` returns:
  - `IngestEndpoint` — the RTMPS URL the broadcaster pushes to.
  - `PlaybackUrl` — the [[hls-and-dash|HLS]] URL viewers pull from.
  - A `StreamKey` for ingest auth.
- `put_metadata(ChannelArn, Metadata)` — inject timed metadata into the stream (interaction trigger).
- Recording → S3 via `RecordingConfiguration`.
- `Authorized=True` channels require signed JWTs for playback (DRM-lite).

**IVS Real-Time ([[webrtc-deep-dive|WebRTC]] stages):**

- `create_stage()` → `Stage` ARN.
- `create_participant_token(StageArn, UserId, Capabilities=['PUBLISH'|'SUBSCRIBE'])` — short-lived JWT the client SDK uses to join.
- Client SDKs (Web / iOS / Android / Unity) handle the [[webrtc-deep-dive|WebRTC]] handshake against AWS-hosted SFU.
- Optional **composition** API — server-side mixes a stages session into a single broadcasted feed (for re-broadcast to standard IVS / [[rtmp-and-srt|RTMP]] destinations).

## Pricing model

- **Standard IVS**:
  - Per-minute of input video (resolution-tier-based).
  - Per-minute of output to viewers ([[hls-and-dash|HLS]]), tiered.
  - Recording to S3 per GB.
  - In normal mode, output is dramatically cheaper than low-latency mode for the same-quality CDN delivery — there's a real cost gradient.
- **IVS Real-Time**:
  - Per-minute per-participant (publishers + subscribers).
  - Composition is a separate per-minute add-on.

Both are designed to be priced for "broadcast to many viewers cheaply". For very low concurrency (1-2 viewers) it's not much cheaper than rolling your own with [[aws-medialive-entity]] + [[aws-mediapackage-entity]] + CloudFront — but it is dramatically simpler.

## When to reach for it

- ✅ **Customer-facing live preview at scale** — many concurrent viewers watching one feed (think live-event broadcast, public webcams).
- ✅ **Interactive multi-participant** sub-second use cases (Real-Time) — virtual conferences, co-host shows, live auctions, video-call-style monitoring rooms.
- ✅ Want to ship something live in days, not weeks — IVS is the fastest path from "we have an [[rtmp-and-srt|RTMP]] source" to "viewers can watch in browser".
- ✅ Want recording-to-S3 baked in.

## When not to reach for it

- ❌ Camera ingest from [[rtsp-deep-dive|RTSP]] / ONVIF cameras — IVS expects RTMPS or [[webrtc-deep-dive|WebRTC]] publishers; [[rtsp-deep-dive|RTSP]] isn't a first-class input. (You'd need a relay like [[aws-medialive-entity]] or self-hosted MediaMTX in front of it.)
- ❌ True sub-100ms deterministic latency — even Real-Time's "sub-second" is variable. For real real-time, you're looking at a private SFU or an SDI signal path.
- ❌ Anything that needs DRM (PlayReady / Widevine / FairPlay) — IVS does not support full DRM. Use [[aws-mediapackage-entity]].
- ❌ Heavy long-tail file VOD — IVS is live-shaped; use [[aws-mediaconvert-entity]] + [[aws-mediapackage-entity]].

## Actuate touchpoints

**Not used.** No `ivs` or `ivs-realtime` boto3 client invocations in scouted libraries.

The honest "could it replace homegrown live-preview if/when we build that?" discussion:

**The hypothetical:** Actuate eventually wants a "click on a camera in the dispatcher console → see live video" feature. Today operators see only the alert-clip JPEG sequence, not a live feed. Building this in-house means: an [[rtsp-deep-dive|RTSP]]-to-[[webrtc-deep-dive|WebRTC]] bridge (likely MediaMTX or `gst-rtsp-server`-based), a signaling-channel layer (likely Pion or aiortc), and either fleet-pod-to-browser direct [[webrtc-deep-dive|WebRTC]] or a self-hosted SFU.

**Where IVS Real-Time fits:** publish each camera's decoded [[h264-deep-dive|H.264]] into an IVS Real-Time stage as a publisher participant; dispatchers join as subscribers. AWS handles the SFU, ICE, TURN, and browser SDK. Latency target (~sub-second) matches dispatcher needs. Recording / replay piggybacks on the standard IVS composition API.

**Why it's plausible:**

- Removes the entire SFU operations problem.
- Gets the latency budget right without reinventing [[webrtc-deep-dive|WebRTC]].
- Per-participant pricing aligns reasonably with our user model — small numbers of dispatchers per event.

**Why it's risky:**

- Per-camera publisher cost. We have **a lot** of cameras. Even if only "active" cameras (currently in alert state) publish to IVS, the math gets expensive with many concurrent alerts.
- IVS Real-Time only takes [[webrtc-deep-dive|WebRTC]] publishers — we'd still need an in-pod RTSP-to-WebRTC step (so we don't escape from `gst-webrtcbin` / aiortc anyway, and if we already have that piece, the SFU side could just as easily be self-hosted Pion / LiveKit).
- The "click to view" interaction is at most a few simultaneous viewers per camera in practice (one or two dispatchers per alert). The "many viewers per stream" pricing logic that makes IVS cheap doesn't apply.

**Verdict (subjective):** **plausible to evaluate, not obviously the right answer.** [[aws-kvs-entity]] [[webrtc-deep-dive|WebRTC]] actually fits Actuate's shape better — it's already AWS-native, we're already in [[kvs-components|KVS]], and [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] is priced per-channel-minute rather than per-participant. IVS makes more sense for a customer-public live-preview product than for an internal dispatcher live-preview tool.

The real comparison to do at evaluate-time is **[[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] vs IVS Real-Time vs self-hosted Pion/LiveKit** — see [[aws-video-services-decision-matrix]] and [[fleet-architecture/_summary]] for the substrate question.
