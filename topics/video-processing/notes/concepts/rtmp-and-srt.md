---
title: RTMP and SRT
type: concept
topic: video-processing
tags: [rtmp, srt, transport, broadcast, contribution]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/infrastructure/notes/entities/remote-access-proxy.md
  - topics/video-processing/_summary.md
  - topics/video-processing/notes/concepts/2026-05-18_mediamtx.md
  - topics/video-processing/notes/concepts/gstreamer-vs-ffmpeg.md
  - topics/video-processing/notes/concepts/mpeg-ts-over-udp.md
  - topics/video-processing/notes/concepts/protocol-latency-comparison.md
  - topics/video-processing/notes/concepts/webrtc-deep-dive.md
  - topics/video-processing/notes/entities/aws-elemental-live-entity.md
  - topics/video-processing/notes/entities/aws-ivs-entity.md
  - topics/video-processing/notes/entities/aws-kvs-entity.md
incoming_updated: 2026-05-27
---

# RTMP and SRT

Two transport protocols with broadcast / contribution lineage. **Neither is used in Actuate's surveillance integrations today** and there's no near-term plan to change that. This note exists so that when a partner says "we publish over RTMP" or "the feed is SRT", we can place it in context and decide whether to bridge or refuse.

## RTMP -- Real-Time Messaging Protocol

### Origin and current state

RTMP started life as Adobe's Flash Player ingest protocol (originally over TCP/1935). When Flash died, RTMP didn't -- it stuck around because every encoder vendor had RTMP code lying around and every "go live" button on every CDN spoke RTMP. **As of 2026 it remains the dominant ingest protocol for live streaming** even though playback over RTMP is dead.

The lifecycle now looks like: encoder (OBS, Wirecast, broadcast hardware) **publishes RTMP -> ingest server** (NGINX-RTMP, MediaMTX, [[aws-ivs-entity|AWS IVS]], Twitch, YouTube Live) **transcodes / repackages -> [[hls-and-dash|HLS]] or [[hls-and-dash|DASH]]** for playback. RTMP is the contribution leg only.

### Protocol mechanics

- **Transport**: TCP, port 1935 by default (no real UDP equivalent; RTMFP exists but is essentially abandoned).
- **Container**: FLV-style **RTMP Messages** -- chunks of audio (AAC), video ([[h264-deep-dive|H.264]] NAL units wrapped in AVCC), and metadata (AMF0/AMF3-encoded `onMetaData`). The wire format is FLV-adjacent; pull `librtmp` source for the gory details.
- **[[codecs-overview|Codecs]]**: Practically [[h264-deep-dive|H.264]] + AAC. [[h265-hevc-deep-dive|H.265]] over RTMP exists as an "Enhanced RTMP" extension (proposed by YouTube et al., 2023) but adoption is uneven; partners often need explicit handshake compatibility flags.
- **Authentication**: weak / nonexistent. Token-in-stream-key is the typical pattern (`rtmp://server/app/streamkey`).
- **TLS**: RTMPS is the TLS variant -- mandatory for any production workflow. Plain RTMP is plaintext including the stream key.

### Latency

Glass-to-glass over RTMP-ingest -> RTMP-playback (rare today): **2-5s**. Over the more realistic RTMP-ingest -> [[hls-and-dash|HLS]]-playback path: dominated by [[hls-and-dash|HLS]] chunking (6-30s). See [[protocol-latency-comparison]].

### Why RTMP doesn't show up in surveillance

- **Direction is wrong**: RTMP is a *push* protocol (encoder publishes to server). IP cameras are *servers* ([[rtsp-deep-dive|RTSP]] listening); they don't push.
- **Codec mismatch**: Surveillance is heavily [[h265-hevc-deep-dive|H.265]] these days; RTMP's [[h265-hevc-deep-dive|H.265]] story is messy.
- **No sub-stream concept**: RTMP carries one A/V program; surveillance often wants main+sub-stream from one device.

## SRT -- Secure Reliable Transport

### Origin

Developed by **Haivision** (broadcast equipment vendor), open-sourced in 2017 (BSD), now standardized as an IETF Internet-Draft. SRT was built to solve the "expensive satellite link replacement" problem for broadcast contribution: how do you ship a 50Mbps live feed across a public internet link with packet loss and not have it look terrible?

### Protocol mechanics

- **Transport**: UDP, default port 9710 -- **but** with reliability features bolted on.
- **ARQ (Automatic Repeat Request)**: receiver requests retransmits of missed packets. Tunable retransmit window.
- **FEC (Forward Error Correction)**: optional Reed-Solomon-style row/column FEC, trades bandwidth for less round-trip dependency.
- **Encryption**: AES-128/192/256 built into the protocol with a passphrase or pre-shared key.
- **Latency window**: receiver sets a fixed buffer (typical 120-1500ms). Below this, packets are reordered and missing frames retransmitted; above it, packets are dropped. **The latency floor is configurable**, which is rare and useful.
- **Congestion control**: explicit; the sender adapts to the receiver's reported buffer fill.
- **Modes**: "caller" (initiates), "listener" (receives), "rendezvous" (both punch NAT simultaneously) -- this last one makes SRT *NAT-friendlier than UDP RTP*.

### Latency

SRT can achieve **120ms-1s glass-to-glass** over a noisy public internet path, which is materially better than RTMP for the same loss conditions and not much worse than [[rtsp-deep-dive|RTSP]]/UDP on a clean LAN. The trade is: SRT *guarantees* the latency by dropping rather than queuing, while TCP-based protocols *guarantee* delivery by queuing -- with unbounded latency on a bad link.

### Why SRT doesn't show up in surveillance (yet)

- **Camera vendor support is rare**. Hikvision, Dahua, Axis: none expose SRT as a default output. A few "transmitter" boxes (Haivision Makito, Teradek) do, but those are broadcast equipment, not surveillance.
- **Cloud VMS support is rare**. [[aws-ivs-entity|AWS IVS]] supports SRT ingest (recent). [[kvs-components|KVS]] does not. Most VMS vendors haven't implemented it.
- **The use case is contribution, not surveillance**. A broadcaster shipping a single high-bitrate game feed cares about SRT. A surveillance integrator pulling 200 camera streams cares about scale and per-stream cost; SRT's per-stream tuning overhead is a wash.

## Reading-list pointers

For experimenting with either protocol locally, see [[reading-list]]:

- **MediaMTX** (formerly [[rtsp-deep-dive|rtsp]]-simple-server) -- bridges RTMP <-> [[rtsp-deep-dive|RTSP]] <-> [[hls-and-dash|HLS]] <-> [[webrtc-deep-dive|WebRTC]] <-> SRT in one binary. Single best test rig.
- **OBS Studio** -- canonical RTMP/SRT publisher; useful as the encoder side of a test setup.
- **NGINX-RTMP** -- legacy reference RTMP relay; mostly replaced by MediaMTX now.
- **[[gstreamer-entity|GStreamer]] `srtsrc` / `srtsink`** -- if a partner ever asks for SRT bridging, [[gstreamer-entity|GStreamer]] is the path of least resistance.
- **[[ffmpeg-entity|FFmpeg]]** has full SRT support via `srt://` URLs (build with `--enable-libsrt`); RTMP support is built-in.

## Actuate touchpoints

**Neither protocol is currently consumed or produced anywhere in Actuate code.** A grep for `rtmp://`, `srt://`, `librtmp`, or `libsrt` across `actuate-libraries`, `vms-connector`, and `actuate_admin` returns zero hits beyond reading-list / docs.

### Plausible future use cases

- **RTMP**: only relevant if a partner standardizes on broadcast-style ingest (very unlikely for the surveillance vertical). One realistic scenario: a customer wants an "Actuate -> live YouTube" public-feed feature, in which case we'd publish *outbound* RTMP to YouTube Live. Cheap to add via [[ffmpeg-entity|FFmpeg]].
- **SRT**: only relevant for broadcast / contribution partnerships, or if we ever ship our own outdoor-camera "transmitter" hardware needing low-latency public-internet contribution. Not on the roadmap.

If either ever lands, the integration point is [[ffmpeg-entity]] or [[gstreamer-entity]] -- both already speak both protocols natively.

For comparison against actually-used protocols, see [[protocol-latency-comparison]] and [[rtsp-deep-dive]]. For the modern low-latency alternative used in production today, see [[webrtc-deep-dive]].
