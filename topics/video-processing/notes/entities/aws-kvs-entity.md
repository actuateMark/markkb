---
title: AWS Kinesis Video Streams (KVS)
type: entity
topic: video-processing
tags: [aws, kvs, kinesis-video-streams, ingest, webrtc, gstreamer, boto3]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
---

# AWS Kinesis Video Streams (KVS)

## What it is

Managed video ingest, retention, and replay. [[kvs-components|KVS]] is "S3 for live video" with two distinct flavors that share a name and almost nothing else:

- **[[kvs-components|KVS]] Producer (a.k.a. classic / video streams)** — continuous video ingest. A producer publishes timestamped, fragmented MKV chunks into a named "stream"; consumers later read those chunks back via `GetMedia` (live tail) or `GetMediaForFragmentList` (random access). Retention is configurable up to ~10 years. This is the path Actuate uses today.
- **[[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]]** — fully separate API surface that gives you managed signaling channels for peer-to-peer [[webrtc-deep-dive|WebRTC]]. No bytes flow through AWS once the signaling handshake is complete; AWS hosts only the signaling channel + STUN/TURN. End-to-end latency is ~sub-second. Used for "click on a camera in a UI, see live video".

These are not interchangeable — they have different SDKs, different IAM resources, and different pricing axes.

## API surface (the parts engineers actually touch)

[[kvs-components|KVS]] Producer is unusual in that the **boto3 Python client is not a producer client**. boto3 only exposes:

- `kinesisvideo` — control plane. The most-used call is `get_data_endpoint(StreamName, APIName="GET_MEDIA" | "PUT_MEDIA" | "GET_HLS_STREAMING_SESSION_URL" | ...)`. [[kvs-components|KVS]] uses regional data-plane endpoints that you must resolve before calling the data plane.
- `kinesis-video-media` — read-side. `get_media(StreamName, StartSelector={"StartSelectorType": "NOW" | "EARLIEST" | "FRAGMENT_NUMBER" | "PRODUCER_TIMESTAMP" | "SERVER_TIMESTAMP"})`. Returns a streaming response whose `Payload` is a chunked MKV byte stream. You demux it yourself.
- `kinesis-video-archived-media` — random-access read for retained content; [[hls-and-dash|HLS]] / [[hls-and-dash|DASH]] session URL generation; clip extraction to MP4.
- `kinesis-video-signaling` ([[webrtc-deep-dive|WebRTC]]) — `get_signaling_channel_endpoint`, `connect_as_master`/`connect_as_viewer` over WSS.

For **producer-side ingest** (publishing video into a stream), AWS ships:

- the **C++ Producer SDK** (the canonical one);
- a **[[gstreamer-entity|GStreamer]] plugin** (`kvssink`) built on the C++ SDK — by far the easiest publish path;
- a **Java Producer SDK**;
- an **Android Producer SDK**.

There is no first-party Python publisher. You either link the C++ SDK, run a [[gstreamer-entity|GStreamer]] pipeline ending in `kvssink`, or implement the chunked HTTP `PutMedia` protocol yourself (rarely worth it). This gap is a recurring footgun for teams who assume "boto3 must support both directions".

## Pricing model

- **Ingest** — per-GB ingested.
- **Storage** — per-GB-month for retention duration.
- **Consumed** — per-GB read out via `GetMedia` / [[hls-and-dash|HLS]] session.
- **[[webrtc-deep-dive|WebRTC]]** — per signaling channel-minute (open) plus TURN relay GB if you use the AWS-hosted TURN.

Continuous high-resolution feeds get expensive fast — a single 1080p [[h264-deep-dive|H.264]] stream at 4 Mbit/s is roughly 1.3 TB / month ingested + stored, before consumption. [[kvs-components|KVS]] is cost-effective only when you actually need its retention or replay properties; for "decode now and forget" use cases it's strictly more expensive than pulling [[rtsp-deep-dive|RTSP]] directly.

## When to reach for it

- ✅ Camera ingest where the partner publishes to [[kvs-components|KVS]] for you (so the protocol problem is theirs, not yours).
- ✅ You need persisted retention with random access by timestamp / fragment number (clip-replay UIs, evidence archival).
- ✅ Sub-second live preview to a browser → use **[[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]]** specifically.
- ⚠️ "Just decode [[rtsp-deep-dive|RTSP]]" — [[kvs-components|KVS]] is overkill.
- ❌ Long-term cold archive — S3 + a thumbnail index is cheaper.

## When not to reach for it

- The partner already exposes [[rtsp-deep-dive|RTSP]]/[[rtmp-and-srt|RTMP]]/[[hls-and-dash|HLS]] in a workable form.
- You don't need retention.
- You're optimizing for $/frame at high stream counts ([[rtsp-deep-dive|RTSP]] pull beats it on cost per decoded frame).

## Actuate touchpoints

[[kvs-components|KVS]] Producer is **actively used** as a frame source for VMS partners that publish into [[kvs-components|KVS]] on our behalf. The implementation lives in `actuate-libraries/actuate-pullers/src/actuate_pullers/kvs/`:

- `kvs_puller.py:9-47` defines `KVSFramePuller`, the puller-shape adapter the connector instantiates per camera.
- `kvs_ingestor.py:50-335` is the actual ingest:
  - `:82-98` — `boto3.client("kinesisvideo")` resolves the GetMedia data endpoint per region.
  - `:270-273` — `boto3.client("kinesis-video-media")` calls `get_media(StreamName, StartSelector={"StartSelectorType": "NOW"})` and reads `response["Payload"]` in 64 KB chunks.
  - `:148-156, 104-128` — the chunks are pushed into a [[gstreamer-entity|GStreamer]] `appsrc` with caps `video/x-matroska`, then `matroskademux ! decodebin ! videoconvert ! jpegenc ! appsink`. The frame is JPEG-encoded inside [[gstreamer-entity|GStreamer]] and **re-decoded** via `cv2.imdecode` (line 119) into a numpy array.

The **JPEG re-encode round-trip** is a known inefficiency: we go MKV([[h264-deep-dive|H.264]]) → decoded raw → JPEG → decoded raw to land at a numpy frame. Every step that isn't `videoconvert ! appsink` with a raw-frame cap is wasted CPU. It exists historically because the appsink consumer was generic across all puller flavors and JPEG bytes were the lowest-common-denominator handoff. Worth fixing in a future pass — see [[actuate-frame-ingest-decode-paths]] (planned) and [[hardware-accelerated-codecs]].

The [[kvs-components|KVS]] puller is **conditionally imported** (`__init__.py:1-56` does a `try/except ImportError` on PyGObject) so connector pods without GStreamer-Python bindings still build. This means a missing system library silently disables [[kvs-components|KVS]] ingest at startup — see [[vms-connector/_summary]] for the broader puller-registry pattern.

KVS [[webrtc-deep-dive|WebRTC]] is **not** used in Actuate today. It is the plausible substrate for fleet-pod-to-fleet-pod live-frame transport ([[fleet-architecture/_summary]]) and for any future "live preview from monitoring center" UI; flagged in [[aws-video-services-decision-matrix]] as an evaluate-next candidate.

Reading-list pointers: KVS Producer SDK (C++/Java/[[gstreamer-entity|GStreamer]] plugin), KVS [[webrtc-deep-dive|WebRTC]] signaling channels, KVS architecture & pricing docs — all in [[reading-list]] under "AWS-specific reading".
