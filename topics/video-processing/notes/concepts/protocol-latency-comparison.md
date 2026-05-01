---
title: Protocol Latency Comparison
type: concept
topic: video-processing
tags: [latency, transport, decision-matrix, comparison, autopatrol]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
---

# Protocol Latency Comparison

Decision-oriented synthesis. **If you have to pick a transport for a new use case in Actuate, this table is the starting point.** Per-protocol details live in the dedicated deep-dive notes; this note is the cross-cut.

## Cheat sheet -- glass-to-glass latency floor

"Glass-to-glass" = camera lens captures frame -> viewer screen displays frame. All numbers are realistic floors on a healthy network with a competent implementation. **Real production deployments often run 2-5x slower** due to unprincipled buffer settings, [[gop-keyframe-fundamentals|GOP]]/keyframe choices, network jitter, or transcoding hops.

| Protocol | Latency floor | Realistic typical | Server / CDN cost | Browser-native? | NAT-friendly? | Actuate today | Actuate future fit |
|----------|---------------|-------------------|-------------------|-----------------|----------------|---------------|--------------------|
| **[[webrtc-deep-dive|WebRTC]] (P2P, direct)** | 100-300ms | 200-500ms | ~$0 (signaling only) | Yes (all evergreen browsers) | Yes (ICE) | No | **Live preview, watchman live-view, inter-pod fleet transport** |
| **[[webrtc-deep-dive|WebRTC]] (SFU)** | 150-400ms | 300-800ms | $$ (SFU bandwidth) | Yes | Yes | No | Many-to-many viewing |
| **[[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] (managed SFU/TURN)** | 200-500ms | 400ms-1s | $ (per-channel-hour + GB) | Yes (via SDK) | Yes (managed TURN) | No | **Lowest-friction sub-1s preview** |
| **[[rtsp-deep-dive|RTSP]]/UDP (RTP)** | 100-300ms | 300ms-1s | $ (puller compute) | No (browser can't play [[rtsp-deep-dive|RTSP]]) | **No** (NAT-hostile) | No (NAT) | No -- replaced by [[webrtc-deep-dive|WebRTC]] |
| **[[rtsp-deep-dive|RTSP]]/TCP (interleaved)** | 300ms-1s | **500ms-2s** | $ (puller compute) | No | Yes (TCP only) | **Yes -- primary** | Stays primary for camera ingest |
| **[[mpeg-ts-over-udp|MPEG-TS]]/UDP (multicast)** | 100-400ms | 200-800ms | ~$0 on LAN | No | No (multicast off-LAN) | No | Stadium/venue LAN integrations only |
| **[[rtmp-and-srt|SRT]]** | 120-500ms (configurable) | 200ms-1.5s | $ (relay if any) | No | Yes (rendezvous) | No | Broadcast-contribution partnerships |
| **WebSocket fMP4** | 500ms-1s | 1-2s | $ (server) | Yes (via MSE) | Yes (TCP/443) | **Yes** (AutoPatrol) | Stays for AutoPatrol/VCH |
| **[[rtmp-and-srt|RTMP]]** | 1-3s | 2-5s | $ (ingest server) | No (Flash-era) | Yes (TCP/1935) | No | Outbound-to-YouTube only, niche |
| **LL-[[hls-and-dash|HLS]]** | 2-3s | 3-5s | $ (CDN, cheap) | Yes (Safari native, hls.js elsewhere) | Yes (HTTP/443) | No | Adaptive playback at low latency |
| **LL-DASH** | 2-4s | 3-6s | $ (CDN) | Via dash.js / Shaka Player | Yes (HTTP/443) | No | Same as LL-HLS, non-Apple ecosystem |
| **[[hls-and-dash|HLS]] (standard)** | 6-10s | 15-30s | $ (CDN, cheapest) | Yes (Safari native) | Yes | No | **Clip replay UI, archive playback** |
| **[[hls-and-dash|DASH]] (standard)** | 6-10s | 15-30s | $ (CDN) | Via player | Yes | No | Same as [[hls-and-dash|HLS]], broader codec support |
| **[[kvs-components|KVS]] GetMedia** | 2-5s | 5-15s | $ (per-stream-hour + GB) | No (SDK only) | Yes | **Yes** (`kvs_puller.py`) | Stays for KVS-ingesting cameras |

### Reading the table

- **Latency floor** is what a careful implementation can achieve in lab conditions. It's a lower bound, not a promise.
- **Realistic typical** is what you'll see in production with normal jitter, encoder buffering, and unoptimized clients. This is the number that matters.
- **NAT-friendly** -- "Yes" means it works through standard customer NAT without the customer punching firewall holes. This rules out plain [[rtsp-deep-dive|RTSP]]/UDP and unicast UDP transports for almost any cloud-hosted ingest path.
- **Actuate today** column is fact. **Actuate future fit** is opinion / strategic positioning.

## Decision rules

These are the heuristics the table boils down to:

1. **Camera ingest from customer-side IP cameras**: [[rtsp-deep-dive|RTSP]]-over-TCP. Already the de-facto default. Latency floor 500ms-2s is acceptable for analytics; the alternative (UDP) doesn't survive customer NAT. See [[rtsp-deep-dive]].

2. **Sub-second live preview for operators**: [[webrtc-deep-dive|WebRTC]], ideally KVS-managed. The only protocol with a sub-500ms realistic floor that runs in a browser. **This is where the lever is for the "watchman live-view" experience.** See [[webrtc-deep-dive]].

3. **Long-form playback / clip replay**: [[hls-and-dash|HLS]] (or [[hls-and-dash|HLS]]+[[hls-and-dash|DASH]] via CMAF). Cheapest CDN cost, browser-native, latency irrelevant for archived content. Use [[aws-mediaconvert-entity|AWS MediaConvert]] to produce segments offline. See [[hls-and-dash]].

4. **Cameras already on [[kvs-components|KVS]]** (Verkada-style or partner-managed): consume via [[kvs-components|KVS]] GetMedia. We already have this path; see Actuate touchpoints below.

5. **WebSocket fMP4** is the AutoPatrol / VCH approach -- not a protocol we'd choose for new work, but it's an existing surface and works.

6. **[[mpeg-ts-over-udp|MPEG-TS]]/UDP, [[rtmp-and-srt|SRT]], [[rtmp-and-srt|RTMP]]**: not applicable to surveillance ingest. Useful only for partner integrations where the partner already publishes that way. See [[mpeg-ts-over-udp]], [[rtmp-and-srt]].

## What dominates the latency budget

For each protocol, the dominant cost in the budget is:

| Protocol family | Dominant latency cost |
|-----------------|----------------------|
| [[rtsp-deep-dive|RTSP]]-TCP | Encoder [[gop-keyframe-fundamentals|GOP]] / [[gop-keyframe-fundamentals|keyframe interval]] + libavformat probe time (analyzeduration) + TCP HOL on loss |
| [[webrtc-deep-dive|WebRTC]] | Encoder + jitter buffer (adaptive, can shrink to 30ms) |
| [[hls-and-dash|HLS]] / [[hls-and-dash|DASH]] | **Segment duration** (`#EXT-X-TARGETDURATION` / `SegmentTimeline@d`) + minimum-segments-buffered |
| LL-HLS / LL-DASH | Partial segment duration + chunked-transfer flush cadence |
| [[kvs-components|KVS]] GetMedia | [[kvs-components|KVS]] server-side fragment-completion time (~2-3s for 1s-fragment configs) |
| [[rtmp-and-srt|SRT]] | Configured `latency` parameter (the receiver buffer window) |
| WebSocket fMP4 | Fragment duration + per-fragment [[pyav-entity|PyAV]] `av.open` cost |

Engineering levers cluster differently per family. **For [[rtsp-deep-dive|RTSP]], lower latency means smaller probesize / shorter [[gop-keyframe-fundamentals|GOP]] / fewer B-frames.** For [[hls-and-dash|HLS]], **lower latency means shorter segments and the LL-HLS extension.** For [[webrtc-deep-dive|WebRTC]], lower latency is mostly about the encoder configuration; the protocol itself adds little.

## Cost shape

For sustained streams, the cost shapes are:

- **[[webrtc-deep-dive|WebRTC]]**: server compute + bandwidth. SFU costs scale linearly with viewers per stream. TURN relay costs are a step function (only kicks in for ~10-15% of connections).
- **[[hls-and-dash|HLS]] / [[hls-and-dash|DASH]]**: CDN bandwidth dominated by long-tail viewer count. **Cheapest at scale.**
- **[[rtsp-deep-dive|RTSP]]-TCP**: client-side puller compute is the only cost (we control both ends).
- **[[kvs-components|KVS]]**: per-stream-hour + per-GB stored + per-GB consumed. Predictable and bounded.

## Actuate touchpoints

Concrete file references for protocols already used in Actuate (the rest of the table is forward-looking):

### [[rtsp-deep-dive|RTSP]] -- primary protocol surface

- [`actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py:320-1438`](file:///home/mork/work/actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py) -- [[pyav-entity|PyAV]] path, forces `rtsp_transport=tcp`, probesize 128KB, analyzeduration 300ms.
- [`url_puller.py:17-395`](file:///home/mork/work/actuate-libraries/actuate-pullers/src/actuate_pullers/url/url_puller.py) -- legacy [[opencv-entity|OpenCV]] path; `OPENCV_FFMPEG_CAPTURE_OPTIONS=rtsp_transport;tcp` for `omniaweb`/`eagleeyenetworks`.
- [`url_puller_motion.py:20-100+`](file:///home/mork/work/actuate-libraries/actuate-pullers/src/actuate_pullers/url/url_puller_motion.py) -- motion-gated, used by `openeye`/`milestone_rtsp`.
- [`gst_url_puller.py:11-62`](file:///home/mork/work/actuate-libraries/actuate-pullers/src/actuate_pullers/url/gst_url_puller.py) -> [`gstreamer_input_pipeline.py:86-101`](file:///home/mork/work/actuate-libraries/actuate-pullers/src/actuate_pullers/gstreamer/gstreamer_input_pipeline.py) -- [[gstreamer-entity|GStreamer]] path; **[[h264-deep-dive|H.264]]-only, silently fails on [[h265-hevc-deep-dive|H.265]]**.
- See [[rtsp-deep-dive]].

### KVS GetMedia

- [`kvs/kvs_puller.py:9-47`](file:///home/mork/work/actuate-libraries/actuate-pullers/src/actuate_pullers/kvs/kvs_puller.py) + [`kvs_ingestor.py:50-335`](file:///home/mork/work/actuate-libraries/actuate-pullers/src/actuate_pullers/kvs/kvs_ingestor.py) -- `boto3.client("kinesisvideo")` resolves GetMedia endpoint, `kinesis-video-media` GetMedia(StartSelectorType=NOW); reads streaming MKV in 64KB chunks, pushed into [[gstreamer-entity|GStreamer]] appsrc.
- Pipeline: `appsrc -> matroskademux -> decodebin -> videoconvert -> jpegenc -> appsink` -- **double-encode** (decoded to raw, re-encoded to JPEG, decoded again via `cv2.imdecode`). Optimization candidate.
- See [[aws-kvs-entity]], [[integrations/kvs/_summary]].

### WebSocket fMP4 (AutoPatrol / VCH)

- [`socket/autopatrol_websocket_stream_puller.py:43-300+`](file:///home/mork/work/actuate-libraries/actuate-pullers/src/actuate_pullers/socket/autopatrol_websocket_stream_puller.py) -- binary MP4 over `websockets`; manual ISO-BMFF box parser at `:111-135`; each fragment opened individually via `av.open(buffer, format="mp4")`.

### Other ingest patterns (not transport protocols per se)

- HTTP polling for JPEGs: `orchid/orchid_jpg_queue_puller.py`, `jpg/jpg_frame_queue_puller.py`.
- Milestone proprietary TCP: `milestone/milestone_jpg_frame_puller.py`.
- SQS-Video (S3 keys via SQS): `sqs/sqs_puller.py` -- `cv2.imread` for stills, `cv2.VideoCapture(local_filename)` for clips.
- Unix socket / named pipe: `socket/socket_puller.py`.
- Batch S3 pull (gauntlet/robomladen): `s3/s3_puller.py`.

These aren't really transport "protocols" in the network sense -- they're application-layer ingest patterns -- but they share the table's vocabulary of latency budgets and reliability semantics.

## See also

- Per-protocol deep dives: [[rtsp-deep-dive]], [[rtmp-and-srt]], [[hls-and-dash]], [[webrtc-deep-dive]], [[mpeg-ts-over-udp]]
- Codec layer underneath these transports: [[h264-deep-dive]], [[h265-hevc-deep-dive]], [[mjpeg-and-still-image-formats]]
- Actuate-side mapping: [[actuate-frame-ingest-decode-paths]], [[actuate-video-pipeline-walkthrough]]
- Tooling alternatives: [[reading-list]] (MediaMTX, Pion, LiveKit, Janus, GO2RTC)
- AWS managed offerings: [[aws-kvs-entity]], [[aws-ivs-entity]]
