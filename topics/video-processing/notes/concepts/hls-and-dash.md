---
title: HLS and DASH
type: concept
topic: video-processing
tags: [hls, dash, cmaf, playback, http-streaming]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/video-processing/_summary.md
  - topics/video-processing/notes/concepts/2026-05-18_mediamtx.md
  - topics/video-processing/notes/concepts/connector-decoder-routing-map.md
  - topics/video-processing/notes/concepts/containers-overview.md
  - topics/video-processing/notes/concepts/mpeg-ts-over-udp.md
  - topics/video-processing/notes/concepts/protocol-latency-comparison.md
  - topics/video-processing/notes/concepts/rtmp-and-srt.md
  - topics/video-processing/notes/concepts/webrtc-deep-dive.md
  - topics/video-processing/notes/entities/aws-ivs-entity.md
  - topics/video-processing/notes/entities/aws-kvs-entity.md
incoming_updated: 2026-05-27
---

# HLS and DASH

**HTTP Live Streaming** (Apple, RFC 8216) and **MPEG-DASH** (ISO/IEC 23009) are the two dominant **adaptive bitrate streaming** protocols. They look very different on paper and almost identical in practice: both segment a stream into HTTP-served chunks, both use a manifest to describe variants, both run on any CDN. **Neither is used in Actuate today**, but at least one of them is the right answer for a clip-replay / archive-playback UI we don't have yet.

## What problem they solve

The trick HLS / DASH solve is **adaptive bitrate over HTTP** through CDNs, no special server, no firewall holes. The downside is that segmentation introduces latency: you cannot play a segment that hasn't been written yet, and segments are 2-10s long. **HLS and DASH are wrong for live analytics** (the whole point of live analytics is to not be 6 seconds late) **but right for VOD, archive, and clip replay** where the analytics has already happened upstream.

## HLS -- HTTP Live Streaming

### Mechanics (RFC 8216)

A **master playlist** (`master.m3u8`, text, UTF-8) lists **variant playlists**, one per bitrate/resolution rendition:

```
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1280000,RESOLUTION=720x480
720p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=480000,RESOLUTION=480x320
480p.m3u8
```

Each variant playlist lists segments:

```
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:6
#EXT-X-MEDIA-SEQUENCE:0
#EXTINF:6.0,
seg-0.ts
#EXTINF:6.0,
seg-1.ts
```

Each `seg-*.ts` is a **[[mpeg-ts-over-udp|MPEG-TS]] segment** containing a few seconds of [[h264-deep-dive|H.264]] + AAC. (Modern HLS uses **fMP4** -- fragmented MP4 -- segments instead, which is the same container DASH uses; this is the CMAF convergence below.)

### Live vs VOD

- **VOD playlist**: ends with `#EXT-X-ENDLIST`. Player downloads the full list, can seek freely.
- **Live (sliding window) playlist**: no endlist; player polls the playlist every `target-duration` seconds for new segments.

### Latency floor

For standard HLS with 6-second segments and a 3-segment buffer (Apple's recommended minimum):
- 18s buffer + 1s segmentation = **18-30s glass-to-glass**.

With **Low-Latency HLS (LL-HLS)**, introduced 2019, segments are split into **partial segments** delivered via HTTP/2 push or chunked transfer:
- **2-5s glass-to-glass**.

Still nowhere near [[webrtc-deep-dive|WebRTC]]; see [[webrtc-deep-dive]] and [[protocol-latency-comparison]].

### Strengths

- **Native browser support on Safari + iOS**. Chrome/Firefox need a JavaScript player (hls.js).
- **Runs on any HTTP CDN** -- no streaming server required.
- **Adaptive bitrate** is built into the player; no server-side rate adaptation logic.
- **Mature DRM** via FairPlay (Apple) / Widevine (Google) / PlayReady (Microsoft) on CMAF/fMP4 segments.

## MPEG-DASH

### Mechanics (ISO/IEC 23009-1)

DASH is the standards-body answer to HLS: same architectural shape, more rigorous spec, broader codec/container support. Manifest is **MPD** (Media Presentation Description), an XML document describing **Periods -> AdaptationSets -> Representations -> SegmentTimelines**.

```xml
<MPD type="static" mediaPresentationDuration="PT3M">
  <Period>
    <AdaptationSet mimeType="video/mp4" codecs="avc1.4D401E">
      <Representation bandwidth="1280000" width="1280" height="720">
        <SegmentTemplate media="$RepresentationID$/seg-$Number$.m4s" .../>
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>
```

Segments are **fMP4** (`.m4s`). Codec-agnostic (works for [[h264-deep-dive|H.264]], [[h265-hevc-deep-dive|H.265]], [[av1-vp9-future|AV1]], [[av1-vp9-future|VP9]] -- HLS was historically H.264-pinned by container, but that constraint dissolved with CMAF).

### Latency floor

- **Standard DASH with 6s segments**: ~12-30s.
- **Low-Latency DASH (LL-DASH)** uses chunked CMAF and chunked transfer-encoding to start playing partial segments: **3-5s**.

### Differences from HLS

| Aspect | HLS | DASH |
|--------|-----|------|
| Manifest format | `.m3u8` (text) | `.mpd` (XML) |
| Original segment container | [[mpeg-ts-over-udp|MPEG-TS]] | fMP4 |
| Modern segment container | fMP4 (CMAF) | fMP4 (CMAF) |
| Native browser support | Safari/iOS | None (needs dash.js / Shaka Player) |
| Apple ecosystem | First-class | Second-class (works, not preferred) |
| Spec body | Apple / IETF | MPEG (ISO) |

In 2026 the industry mostly produces **CMAF segments served under both an HLS and a DASH manifest** so players on any platform can consume the same byte content.

## CMAF -- Common Media Application Format

CMAF (ISO/IEC 23000-19) is the unified container that lets HLS and DASH share segment files. Practical effect:

- One encode, one S3 object set.
- Two manifests (`master.m3u8` for Apple, `master.mpd` for everyone else).
- Same DRM (CENC) via Widevine/PlayReady on the same files.

If we ever ship adaptive playback, CMAF is the segment format to start with.

## Reading-list pointers

For producing HLS / DASH segments from a stream we already have, the realistic options (see [[reading-list]]):

- **[[ffmpeg-entity|FFmpeg]]** with `-f hls` / `-f dash` -- one shell command from any [[rtsp-deep-dive|RTSP]] source.
- **[[aws-mediaconvert-entity|AWS MediaConvert]]** -- batch transcoder, produces CMAF + manifests as a job output. Good for clip-replay UI on archived clips. See [[aws-mediaconvert-entity]].
- **[[aws-mediapackage-entity|AWS MediaPackage]]** -- live packaging service: ingest an MP4 / fMP4 source, output HLS/DASH on the fly.
- **MediaMTX** -- open-source bridge that can re-package an [[rtsp-deep-dive|RTSP]] source into HLS in real time.

## Actuate touchpoints

**Not used in Actuate today.** A grep for `.m3u8`, `.mpd`, `hls`, `dash` across the libraries returns zero functional code -- only test fixtures and unrelated tokens.

### Realistic future use cases

1. **Clip-replay UI for monitoring center / customer dashboards.** When an alert clip is generated and stored in S3 ([[actuate-clip-generation-flow]]), today it's served as a single MP4. For long clips or for adaptive-bitrate replay on bad mobile networks, transcoding the clip to HLS/DASH segments via [[aws-mediaconvert-entity|MediaConvert]] and serving via CloudFront would be the textbook approach. Cost is the offline encode + a few extra S3 PUTs.

2. **Archive playback for AutoPatrol / patrol-mode review.** Historic patrol footage stored as MP4 today could be packaged as HLS for scrubbing. Similar pattern.

3. **Customer-facing live preview at >10s latency**. If a customer just wants "see what the camera saw 30 seconds ago" without sub-second latency, HLS is cheaper to operate than [[webrtc-deep-dive|WebRTC]]. But for sub-second live preview, [[webrtc-deep-dive|WebRTC]] is the lever -- see [[webrtc-deep-dive]].

For protocols actually used today: [[rtsp-deep-dive]]. For latency comparison across all options: [[protocol-latency-comparison]]. For the codec layer underneath HLS/DASH segments: [[h264-deep-dive]], [[h265-hevc-deep-dive]].
