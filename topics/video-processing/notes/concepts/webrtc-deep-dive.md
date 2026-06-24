---
title: WebRTC Deep Dive
type: concept
topic: video-processing
tags: [webrtc, sfu, ice, dtls, srtp, low-latency, live-preview]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/fleet-architecture/notes/syntheses/2026-05-29_watch-manager-observability.md
  - topics/infrastructure/notes/concepts/2026-05-19_mediamtx-chart-design.md
  - topics/video-processing/_summary.md
  - topics/video-processing/notes/concepts/2026-05-18_go2rtc.md
  - topics/video-processing/notes/concepts/2026-05-18_mediamtx.md
  - topics/video-processing/notes/concepts/av1-vp9-future.md
  - topics/video-processing/notes/concepts/gstreamer-vs-ffmpeg.md
  - topics/video-processing/notes/concepts/hls-and-dash.md
  - topics/video-processing/notes/concepts/mpeg-ts-over-udp.md
  - topics/video-processing/notes/concepts/protocol-latency-comparison.md
incoming_updated: 2026-05-30
---

# WebRTC Deep Dive

**WebRTC** (Web Real-Time Communication, RFC 8825 family) is the protocol stack the browser-side world settled on for sub-second media transport. It's the right answer to "how do we show a customer their camera with <500ms glass-to-glass latency from a cloud-hosted backend?" -- a question Actuate doesn't currently have a good answer to. WebRTC is the most plausible lever for live-preview, watchman live-view, and inter-pod frame transport in fleet architecture.

## Stack overview

WebRTC is not a single protocol; it's a **stack of protocols** with associated APIs:

| Layer | Protocol | Purpose |
|-------|----------|---------|
| Application | JavaScript `RTCPeerConnection` API | Browser-side handle |
| Signaling | (out of band -- WebSocket / HTTP / [[kvs-components|KVS]] signaling channel) | SDP offer/answer exchange |
| Connection establishment | **ICE** (RFC 8445) | NAT traversal candidate negotiation |
| | STUN (RFC 8489) | Public-IP discovery |
| | TURN (RFC 8656) | Relay when ICE direct fails |
| Security | **DTLS** (RFC 6347) | Key exchange |
| Media transport | **SRTP** (RFC 3711) | Encrypted RTP |
| Data transport | **SCTP over DTLS** | DataChannel |
| Media | RTP / RTCP | Same as the rest of the RTP world |
| [[codecs-overview|Codecs]] | [[h264-deep-dive|H.264]] / [[av1-vp9-future|VP8]] / [[av1-vp9-future|VP9]] / [[av1-vp9-future|AV1]] + Opus | Mandatory codec set varies; [[h264-deep-dive|H.264]] + Opus universally available |

The key insight: **WebRTC is RTP done right.** It's RTP packets carrying [[h264-deep-dive|H.264]] or [[av1-vp9-future|VP8]] video, but with a NAT-traversal layer (ICE), encryption (DTLS-SRTP), and a feedback channel (RTCP with NACK / PLI / FIR / RPSI / TWCC) that lets the sender adapt to network conditions in real time. That feedback loop is what makes WebRTC work over the public internet at sub-second latency where [[rtsp-deep-dive|RTSP]]-over-UDP fails.

## Connection establishment dance

1. **Out-of-band signaling**: the two peers exchange **SDP** offer / answer through some channel the WebRTC spec doesn't dictate. Real-world choices: WebSocket to a signaling server, HTTP+SSE, [[kvs-components|KVS]] Signaling Channel, Pusher, Firebase, etc.
2. **ICE gathering**: each peer enumerates candidate transports (host / server-reflexive / relay) by querying configured STUN and TURN servers. Candidates are exchanged via the signaling channel.
3. **ICE connectivity checks**: peers send STUN bind requests across all candidate pairs in priority order. The first pair that succeeds becomes the chosen path.
4. **DTLS handshake**: the chosen transport carries a DTLS handshake; SRTP keys are derived via DTLS-SRTP (RFC 5764).
5. **Media flows**: SRTP packets carry encrypted RTP; RTCP packets (also encrypted, SRTCP) carry feedback.

NAT traversal succeeds for ~85-90% of host pairs via direct ICE, with the rest needing a TURN relay. **TURN is operationally expensive** (relay bandwidth costs, capacity planning) and is the main reason "self-host WebRTC" projects fail.

## SFU vs MCU vs P2P

For one-to-one calls, peers connect directly (P2P). For one-to-many or many-to-many you need a server:

- **P2P (mesh)**: each viewer establishes its own peer connection to the publisher. Doesn't scale past ~3-4 viewers (publisher uplink saturates).
- **MCU (Multipoint Control Unit)**: server decodes all inputs and re-encodes a single composite output. Heavy CPU, single bitrate output, mostly obsolete.
- **SFU (Selective Forwarding Unit)**: server receives one stream from each publisher and forwards encrypted RTP to subscribers without decoding. Each subscriber gets its own SRTP session but shares the source RTP. Linear scale on bandwidth, no CPU cost. **This is the architecture every modern WebRTC product uses.**

Reference SFUs in [[knowledgebase/topics/billing/reading-list]]:
- **Janus Gateway** -- C, plugin-based, the OG.
- **Pion** (Go) -- the lower-level toolkit; building blocks rather than a product.
- **LiveKit** -- room-model SDK on top of Pion. Open core, well-documented.
- **MediaSoup** (Node.js + C++) -- another popular SFU.
- **aiortc** -- pure Python; useful for server-side RTP injection from Python pipelines, less so as an SFU.

## KVS Signaling Channels -- the AWS managed alternative

AWS [[aws-kvs-entity|Kinesis Video Streams]] provides **WebRTC Signaling Channels** which sidestep most of the operational pain:

- AWS hosts the signaling endpoint, STUN, and a managed TURN service.
- Authentication flows through IAM / KVS-issued credentials; no token server to operate.
- Pricing is per-channel-hour + per-GB on the relay path; competitive with self-hosting TURN at our scale.
- **Limitation**: [[kvs-components|KVS]] WebRTC is a 1:N broadcast model (one master, many viewers), not a generalized SFU. For Actuate's live-preview use case (one camera -> one operator) this is fine; for many-to-many it isn't.

See [[aws-kvs-entity]] for the full picture; [[integrations/kvs/_summary]] for current consumers.

## Latency profile

WebRTC's design target is **sub-second glass-to-glass**:

- Encoder: 16-50ms (low-latency configs, no B-frames, short [[gop-keyframe-fundamentals|GOP]]).
- Network (RTP-over-UDP, ICE direct): 10-100ms.
- Jitter buffer (adaptive, can shrink to ~30ms): 30-150ms.
- Decoder: 16-50ms.
- Compositor / display: 16-33ms.

Realistic floor: **150-400ms** on a clean LAN, **300-800ms** over public internet, **500ms-1.5s** when forced through TURN relay. See [[protocol-latency-comparison]] for the full comparison.

## Actuate touchpoints

**WebRTC is not currently used anywhere in Actuate code.** No `webrtc`, `aiortc`, `pion`, `livekit`, or KVS-WebRTC API calls exist in `actuate-libraries`, `vms-connector`, or `actuate_admin` as of the scout.

### Realistic future use cases (where WebRTC is the right lever)

1. **Sub-500ms live preview** for monitoring center operators. Currently when an operator clicks "show me this camera live", the path goes through whatever the VMS exposes (often [[rtsp-deep-dive|RTSP]]-pulled-on-demand, often >2s latency, frequently fails to connect). Wrapping this with [[kvs-components|KVS]] WebRTC -- camera-side ingest into [[kvs-components|KVS]] via the [[kvs-components|KVS]] Producer SDK or a [[gstreamer-entity|GStreamer]] plugin, viewer-side WebRTC playback -- is the architecturally sound path to <500ms preview. The operator-experience improvement is the kind of thing that wins renewals.

2. **[[watchman-repo|Watchman]] live-view**. [[watchman-repo|Watchman]] performs VLM analysis on alert clips ([[watchman/_summary]]) but for live triage of an unfolding incident, an operator wants to see the camera *now*, not a 30-second-old clip. Same WebRTC plumbing as live preview.

3. **Inter-pod frame transport in fleet architecture**. The fleet rearchitecture distributes inference and analytics across multiple pods; today's frame-transport between them goes via SQS/S3 on the slow path or via direct gRPC/HTTP on the fast path ([[fleet-architecture/_summary]]). For sustained sub-second video streams between pods, WebRTC SFU semantics (encrypted, congestion-controlled, NAT-friendly) would be a step up. The cost is operating the SFU; LiveKit on EKS is the path of least resistance.

4. **Customer-facing direct-to-camera preview**. Eliminates a round-trip through our backend entirely; cameras with native WebRTC support (some Axis, some newer cloud-VMS endpoints) can negotiate directly with the customer's browser. Operationally complex (signaling, TURN); strategically interesting.

For comparison against today's RTSP-based approach: [[rtsp-deep-dive]] (latency floor 500ms-1.5s on best case). For the codec inside WebRTC streams, see [[h264-deep-dive]]. For alternative low-latency-but-not-WebRTC approaches: [[hls-and-dash]] (LL-[[hls-and-dash|HLS]], 2-3s), [[rtmp-and-srt]]. For the full latency comparison: [[protocol-latency-comparison]].
