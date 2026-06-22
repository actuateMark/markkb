---
title: "FFmpeg"
type: entity
topic: video-processing
tags: [ffmpeg, libav, codec, transcode, hwaccel]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/actuate-libraries/notes/concepts/2026-05-19_pyav17-ffmpeg8-migration.md
  - topics/admin-api/notes/entities/actuate-monitoring-api.md
  - topics/data-science/notes/entities/ds-analysis-microservice.md
  - topics/engineering-process/notes/syntheses/2026-04-21_rd-agent-pilot-learnings.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-9-site-dump-crash-hook.md
  - topics/fleet-architecture/notes/concepts/frame-storage-current-state.md
  - topics/infrastructure/notes/entities/create-detection-window.md
  - topics/infrastructure/notes/entities/reusable-github-actions.md
  - topics/llm-shop/notes/syntheses/2026-05-07_overnight-batch-pattern.md
  - topics/personal-notes/notes/concepts/2026-05-28_session-handoff.md
incoming_updated: 2026-05-29
---

# FFmpeg

FFmpeg is the de-facto open-source media toolchain. It's both a **collection of command-line binaries** (`ffmpeg`, `ffprobe`, `ffplay`) and a **set of C libraries** (the `libav*` family) that essentially every other open-source video tool builds on top of. If you've ever decoded, encoded, muxed, demuxed, filtered, or inspected a video frame on Linux/macOS in the last 15 years, FFmpeg or one of its forks (libav, jellyfin-ffmpeg, BtbN's static builds) was almost certainly involved.

## What "FFmpeg" actually refers to

Three distinct things share the name:

1. **The project** — `ffmpeg.org`, the source tree. Maintained by a small core team plus a wide developer base. Releases roughly twice a year on a major version cadence (4.x, 5.x, 6.x, 7.x).
2. **The binaries** — `ffmpeg` (the swiss-army CLI), `ffprobe` (inspector), `ffplay` (SDL-based debug player). The `ffmpeg` binary is what most users mean when they say "FFmpeg."
3. **The libraries** — see [[ffmpeg-libav-libraries]]. These are what `ffmpeg` uses internally and what bindings like [[pyav-entity]], [[opencv-entity]], MoviePy, and [[gstreamer-entity|GStreamer]]'s `gst-libav` plugin call directly.

Conflating these causes confusion. "We use FFmpeg" can mean shelling out to `ffmpeg`, calling `libavcodec` from C/Python, or just having `ffmpeg` on the container image because [[opencv-entity|OpenCV]] bundles it. At Actuate, all three exist; see Actuate touchpoints below.

## Licensing — LGPL vs GPL split

FFmpeg compiles with two licensing modes that gate which features are available:

- **LGPL build** — base FFmpeg without GPL-licensed components. Sufficient for most decode/encode/mux workloads. This is what gets bundled by libraries that need to be freely redistributable ([[pyav-entity|PyAV]]'s wheels, [[opencv-entity|OpenCV]]'s PyPI wheels).
- **GPL build** (`--enable-gpl`) — pulls in `x264`, `x265`, `libxvid`, `libpostproc`, and a handful of filters. Distributing a binary that statically links GPL FFmpeg requires releasing source under GPL.
- **Non-free build** (`--enable-nonfree`) — adds Fraunhofer FDK-AAC and a few others. Cannot be redistributed at all.

Most distro packages (`apt install ffmpeg`) are GPL builds because that's the most useful out of the box. NVIDIA-aware builds (jellyfin-ffmpeg, BtbN nightly) are also GPL. The licensing only really bites if you're shipping FFmpeg statically linked into a closed-source product. For a Lambda or Docker container that just runs `ffmpeg` as a tool, this isn't an issue.

## Industry incumbency

FFmpeg's competitive position is unusual: it has won. Bitmovin, Mux, Cloudflare Stream, [[aws-mediaconvert-entity|AWS MediaConvert]], Netflix, YouTube — all use FFmpeg or its libraries somewhere in their pipeline (often heavily forked and patched, but FFmpeg-derived). The exceptions are:

- Hardware-vendor SDKs (NVIDIA Video Codec SDK, Intel oneVPL) which FFmpeg then wraps.
- Pure broadcast-industry encoders (Elemental, Harmonic) that have parallel codepaths but still expose FFmpeg-compatible CLIs.
- Niche academic/research [[codecs-overview|codecs]].

This means **the FFmpeg invocation skills you learn carry across nearly every video job you'll ever do.** Learning the right 20 flags ([[ffmpeg-command-anatomy]]) pays back forever.

## When to reach for FFmpeg vs alternatives

| Want to... | Tool of choice | Why |
|------------|----------------|-----|
| One-shot transcode / mux on a server | `ffmpeg` CLI | Fastest path; no library setup |
| Programmatic frame access in Python | [[pyav-entity]] (libav* bindings) | Avoids subprocess + parsing |
| Build a long-running streaming pipeline | [[gstreamer-entity]] | Better element lifecycle / dataflow model; see [[gstreamer-vs-ffmpeg]] |
| Inspect what's in a file | `ffprobe -show_streams -of json` | Always shipped with FFmpeg |
| GPU-accelerated decode at scale | FFmpeg `-hwaccel cuda` or [[nvidia-deepstream|DeepStream]] ([[gstreamer-entity|GStreamer]]) | Both work; [[nvidia-deepstream|DeepStream]] wins for multi-stream batched inference |
| Random-access frame reads for ML | `decord` or [[pyav-entity|PyAV]] with seek | FFmpeg-CLI seeking is awkward |
| Live [[rtsp-deep-dive|RTSP]] → frames | [[pyav-entity|PyAV]] (Actuate's choice), [[opencv-entity|OpenCV]], or [[gstreamer-entity|GStreamer]] | All viable; [[pyav-entity|PyAV]] is most predictable |
| [[webrtc-deep-dive|WebRTC]] | Not FFmpeg — use aiortc, Pion, or [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] | FFmpeg's [[webrtc-deep-dive|WebRTC]] support is minimal |

## Performance characteristics

- **Decode throughput**: a single CPU core decodes ~150-300 fps of 1080p [[h264-deep-dive|H.264]] (depends on profile/CPU). With [[hardware-accelerated-codecs|NVDEC]] on a T4/L4, you can push 1000+ fps per stream slot. See [[hardware-accelerated-codecs]].
- **Encode throughput**: x264 medium preset is ~real-time at 1080p on one modern core. [[hardware-accelerated-codecs|NVENC]] is several multiples faster but lower per-bit quality. SVT-[[av1-vp9-future|AV1]] is the fast [[av1-vp9-future|AV1]] path.
- **Startup cost**: spawning `ffmpeg` is ~50-150ms. For high-frequency invocations (frame extraction loops), prefer the libraries directly.
- **Memory**: minimal for transient transcodes; can balloon if filtergraphs buffer (e.g. `tile`, `concat` with mismatched timebases).

## Common gotchas

- **`-ss` placement matters**: before `-i` it does fast seek (keyframe-aligned); after `-i` it decodes-and-discards (frame-accurate but slow). See [[ffmpeg-command-anatomy]].
- **Stream copy isn't free**: `-c copy` skips re-encoding but timestamp / [[gop-keyframe-fundamentals|GOP]] / fragment alignment can still produce broken outputs. Always `ffprobe` the result.
- **Hardware accel is finicky**: hwaccel-output-format is the killer detail. Setting it wrong leaves frames in GPU memory and breaks `to_ndarray()`. See [[ffmpeg-hardware-acceleration]].
- **[[rtsp-deep-dive|RTSP]] transport defaults to UDP**: lossy on the public internet. Force TCP with `-rtsp_transport tcp`.
- **Logging**: `-loglevel verbose` for diagnostics; FFmpeg's default output dumps to stderr, which subprocess wrappers often discard.
- **Pixel format mismatches**: `swscale` will silently insert conversions that cost CPU. `-vf format=yuv420p` is often necessary for compatibility with downstream tools/players.

## Versions worth knowing

- **4.x** — long-time stable. Many distro packages still on this.
- **5.x** — added subtitle filters, improved [[av1-vp9-future|AV1]].
- **6.x** — VVC decoding, much-improved hwaccel support.
- **7.x** — current as of 2026; multi-threaded muxing, more refined Vulkan video.
- **n7-master / nightly** — what BtbN ships static binaries of; usually safe and necessary for newest hardware support.

## Actuate touchpoints

Actuate's relationship with FFmpeg is **almost entirely indirect**:

- **Primary decode path** uses [[pyav-entity]], which links libav* directly. No subprocess. See `actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py:320-1438`. The decode happens inside the Python process via libavformat → libavcodec → libswscale.
- **Legacy / fallback decode** uses [[opencv-entity]]'s `cv2.VideoCapture`, which has FFmpeg bundled as its backend. See `url_puller.py:17-395` and the SQS clip-frame-extraction path in `sqs_puller.py:53`. [[rtsp-deep-dive|RTSP]] transport forced via `OPENCV_FFMPEG_CAPTURE_OPTIONS=rtsp_transport;tcp`.
- **[[gstreamer-entity|GStreamer]] paths** (where present in [[vms-connector/_summary]]) use `gst-libav`, which also wraps libav* — same family, different orchestration.
- **Direct `ffmpeg` subprocess calls** are limited to **hardware-accel auto-detection** in `av_url_puller.py:546, 567, 587, 597`: `ffmpeg -hide_banner -hwaccels` to enumerate available accelerators, plus `nvidia-smi -L` and `lspci` probes. **No transcoding/muxing shells out to ffmpeg.** This is a deliberate constraint.
- **Container images** must include the `ffmpeg` binary (for the hwaccel probe), `libavcodec-extra`, and the NVIDIA Container Toolkit when running on G5/G6/L4 nodes. See [[ffmpeg-hardware-acceleration]] for the build matrix.
- See [[actuate-frame-ingest-decode-paths]] for which integration uses which decoder.

Cross-refs: [[ffmpeg-command-anatomy]] | [[ffmpeg-libav-libraries]] | [[ffmpeg-python-bindings]] | [[ffmpeg-hardware-acceleration]] | [[ffmpeg-filtergraphs]] | [[gstreamer-vs-ffmpeg]] | [[reading-list]]
