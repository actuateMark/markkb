---
title: MPEG-TS over UDP
type: concept
topic: video-processing
tags: [mpeg-ts, udp, broadcast, multicast, transport]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
---

# MPEG-TS over UDP

**MPEG-2 Transport Stream over UDP** (often abbreviated **MPEG-TS/UDP** or **UDP-TS**) is the broadcast industry's "just blast packets at a multicast group" transport. It carries the same MPEG-TS container that's used in [[hls-and-dash|HLS]] (in its older flavour) and on every digital TV transmitter on Earth. **It is effectively absent from surveillance and cloud video paths today** but appears in any conversation about broadcast contribution, encoder hardware, or LAN-multicast video distribution.

## Background -- what MPEG-TS is

MPEG-TS (ISO/IEC 13818-1) is a container format designed in the early 1990s for **error-prone broadcast channels** (satellite, cable, terrestrial DVB / ATSC). Key constraints in that environment that shaped the design:

- **Fixed-size 188-byte packets** -- you can detect a packet boundary by looking at the sync byte (`0x47`) every 188 bytes; corruption is local.
- **Multiplexed elementary streams** -- a single TS can carry many programs (channels), each with its own video, audio, and data tracks, identified by **PID** (Packet ID, 13-bit, in the TS header).
- **Standalone packet decodability** -- a receiver tuning in mid-stream can lock onto sync bytes, find PMT/PAT tables, and start decoding without needing a "header" delivered first.
- **PCR / PTS / DTS clocks** -- explicit clock-recovery fields so the receiver can resynchronize its 27MHz clock to the broadcaster's.

Compare with MP4/fMP4 ([[containers-overview]]): MP4 has a single master `moov` box that must be present before frames can be parsed. MPEG-TS has no such global header; the metadata tables (PAT/PMT) are *repeated periodically* in the stream so a receiver can join at any point. This is the broadcast property MP4 never had.

## MPEG-TS over UDP in practice

The protocol stack is unceremonious:

```
[Ethernet | IP (uni- or multicast) | UDP | MPEG-TS payload]
```

A typical UDP datagram carries **7 TS packets** (7 x 188 = 1316 bytes), comfortably under standard MTU. There is no application-layer framing; the receiver locks on the `0x47` sync byte. Some deployments wrap TS in **RTP** (RFC 2250 -- RTP payload format for MPEG1/2 streams) for sequence numbering and RTCP reporting; this is "RTP/MP2T" and is still UDP underneath.

### URL conventions in tooling

- [[ffmpeg-entity|FFmpeg]]: `udp://239.0.0.1:5000` (multicast) or `udp://10.0.0.5:5000` (unicast)
- [[gstreamer-entity|GStreamer]]: `udpsrc multicast-group=239.0.0.1 port=5000 ! tsdemux`
- VLC: `udp://@239.0.0.1:5000` (the `@` triggers multicast join)

### Reliability story

There is none. UDP. No ARQ, no FEC by default, no retransmits. Receivers tolerate loss because:

1. MPEG-TS sync recovery is robust (loss of a packet -> minor decode artefact, not a stream death).
2. On controlled networks (broadcast plant LAN, dedicated contribution links) loss is engineered out at L1/L2.
3. Some deployments add **Pro-MPEG FEC** (SMPTE 2022-1) or **RTP-FEC** for public-internet contribution; broadcast equipment exposes this as a tickbox.

For public-internet contribution where loss can't be engineered out, **[[rtmp-and-srt|SRT]]** ([[rtmp-and-srt]]) has largely replaced raw MPEG-TS/UDP because [[rtmp-and-srt|SRT]] bakes in retransmits.

## When you'd use it

### Multicast on a controlled LAN

The original use case: distribute one video source to many receivers on a single broadcast/IGMP-enabled network without paying per-receiver bandwidth at the source. Single multicast group, every interested receiver does an IGMP join, switches forward the multicast traffic only on ports with members. This is how cable and IPTV head-ends still work internally, and how any "video distribution at the venue" build-out (sports stadiums, casinos, broadcasters) does in-building distribution.

### Broadcast contribution

Studio-to-studio or studio-to-transmitter feeds where the path is a private fibre or microwave link with engineered packet loss <0.001%. The encoder outputs MPEG-TS over UDP; the next hop (transmitter, cloud ingester) consumes it. This is being progressively replaced by [[rtmp-and-srt|SRT]] / RIST / 2110-SDI.

### Encoder appliance test rigs

Any hardware encoder (Haivision, AJA, Magewell, Teradek) almost always exposes MPEG-TS/UDP as one output mode. If you're prototyping the receiver side, MPEG-TS/UDP is the "always works" option.

## Why it doesn't show up in surveillance / cloud

- **Not routable across the public internet**. UDP without ARQ on the public internet means visible artefacts; multicast doesn't traverse the internet at all (there's no global multicast).
- **No native cloud ingest path**. AWS doesn't expose MPEG-TS/UDP ingest as a service ([[aws-medialive-entity|AWS Elemental MediaLive]] accepts it, but as an on-prem-to-AWS contribution path, not as a customer-facing endpoint). Compare with [[kvs-components|KVS]], which is purpose-built for cloud ingest.
- **Camera vendors don't speak it**. IP cameras emit [[rtsp-deep-dive|RTSP]]/RTP; surveillance VMSes consume [[rtsp-deep-dive|RTSP]]. The MPEG-TS lineage simply doesn't exist in this product category.
- **Firewall-hostile**. UDP across NAT requires explicit hole-punching; multicast across firewalls is even worse.

## Tooling

For testing MPEG-TS/UDP end-to-end, see [[reading-list]]:

- **[[ffmpeg-entity|FFmpeg]]**: `ffmpeg -i input.mp4 -c copy -f mpegts udp://239.0.0.1:5000?pkt_size=1316`
- **[[gstreamer-entity|GStreamer]]**: `gst-launch-1.0 filesrc location=in.ts ! tsdemux ! ... ! udpsink host=239.0.0.1 port=5000`
- **VLC**: best ad-hoc receiver / sender with a GUI.
- **MediaMTX**: [[rtsp-deep-dive|RTSP]]/[[rtmp-and-srt|RTMP]]/[[hls-and-dash|HLS]]/[[webrtc-deep-dive|WebRTC]] bridge but limited MPEG-TS/UDP coverage; better to use [[ffmpeg-entity|FFmpeg]] directly for raw TS/UDP work.
- **TSDuck** -- a specialist toolkit for analysing and manipulating MPEG-TS streams (PMT/PAT inspection, PID filtering). Worth knowing if MPEG-TS becomes a real part of any project.

## Actuate touchpoints

**Not used in Actuate code.** A grep across `actuate-libraries`, `vms-connector`, and `actuate_admin` for `udp://`, `mpegts`, `tsdemux`, or `mpeg-ts` returns zero functional code paths. No camera integration consumes MPEG-TS/UDP today.

### Realistic future use cases

1. **Stadium / venue partnerships** where the customer already runs a broadcast-style multicast distribution on their LAN and wants Actuate to consume an existing TS/UDP feed rather than re-pulling each camera over [[rtsp-deep-dive|RTSP]]. Adapter would be one [[gstreamer-entity|GStreamer]] pipeline (`udpsrc ! tsdemux ! ...`) bridged into the existing puller framework.

2. **Edge-appliance to cloud contribution** if Actuate ever ships its own on-prem device that aggregates many local cameras and ships a single multiplexed feed to the cloud. [[rtmp-and-srt|SRT]] would be the better choice here -- see [[rtmp-and-srt]] -- but MPEG-TS/UDP would be the lower-tech fallback.

3. **Diagnostic / interop testing** with broadcast-equipment partners; useful to know that any MPEG-TS/UDP source can be transcoded into [[rtsp-deep-dive|RTSP]] via MediaMTX or [[ffmpeg-entity|FFmpeg]] as a one-line test rig.

For comparison against actually-used surveillance protocols: [[rtsp-deep-dive]]. For the modern reliable-UDP successor: [[rtmp-and-srt]]. For the latency comparison: [[protocol-latency-comparison]]. For the codec layer carried inside MPEG-TS: [[h264-deep-dive]], [[h265-hevc-deep-dive]].
