---
title: Codecs Overview
type: concept
topic: video-processing
tags: [codec, h264, h265, mjpeg, av1, compression]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/video-processing/_summary.md
  - topics/video-processing/notes/concepts/av1-vp9-future.md
  - topics/video-processing/notes/concepts/containers-overview.md
  - topics/video-processing/notes/concepts/ffmpeg-command-anatomy.md
  - topics/video-processing/notes/concepts/ffmpeg-hardware-acceleration.md
  - topics/video-processing/notes/concepts/ffmpeg-python-bindings.md
  - topics/video-processing/notes/concepts/frame-extraction-strategies.md
  - topics/video-processing/notes/concepts/gop-keyframe-fundamentals.md
  - topics/video-processing/notes/concepts/gst-rtsp-h264-only-audit.md
  - topics/video-processing/notes/concepts/gstreamer-vs-ffmpeg.md
incoming_updated: 2026-05-01
---

# Codecs Overview

A **codec** (coder/decoder) is a compression scheme for video. It defines how a sequence of pixel-frames is turned into a byte stream and back. Codecs are independent of the file format that wraps them — see [[containers-overview]] for that distinction. Every other note in this section ([[h264-deep-dive]], [[h265-hevc-deep-dive]], [[mjpeg-and-still-image-formats]], [[av1-vp9-future]]) is a deeper look at a specific codec; this note is the orientation.

## What a codec actually does

A raw 1080p30 stream in 4:2:0 YUV is roughly **750 Mbps**. No camera, NVR, or upload link tolerates that. Codecs trade CPU/GPU cycles for bit-rate reduction in two complementary ways:

1. **Intra-frame compression** — within a single frame, exploit spatial redundancy. Block transform (DCT or DCT-like), quantize the coefficients, entropy-code the result. This is essentially what JPEG does, and is the entire compression strategy of [[mjpeg-and-still-image-formats|MJPEG]].
2. **Inter-frame compression** — between frames, exploit temporal redundancy. Predict a block from a previously decoded frame using motion vectors, code only the residual. This is the dominant savings for any video where the scene doesn't change much frame-to-frame — the typical surveillance camera looking at an empty parking lot.

Pure intra-coded codecs ([[mjpeg-and-still-image-formats|MJPEG]], ProRes, DNxHD) have the property that **every frame is independent**. Inter-frame codecs ([[h264-deep-dive|H.264]], [[h265-hevc-deep-dive|H.265]], [[av1-vp9-future|VP9]], [[av1-vp9-future|AV1]]) achieve 10–50× more compression but make individual frames mutually dependent — the decoder can't start mid-stream without a keyframe. This dependency is the source of most surveillance-video pain (see [[gop-keyframe-fundamentals]]).

## Encoder vs decoder

Codecs are defined as a **bitstream syntax** plus a **normative decoder** — the decoder is fully specified by the standard, the encoder is not. Different encoders for the same codec (x264 vs [[hardware-accelerated-codecs|NVENC]] vs Apple's encoder) produce wildly different bitstreams from the same source, all decodable by any compliant decoder. This asymmetry is why "is your camera using [[h264-deep-dive|H.264]]?" is a much less specific question than it sounds.

In Actuate we are almost exclusively a **decoder consumer** — cameras, VMSes, and partner clouds produce the bitstream, our pipeline decodes it. The one exception is encode-to-JPEG for storage and downstream consumption (see [[mjpeg-and-still-image-formats]]).

## The bitrate↔quality knob

Every encoder ultimately exposes one core tradeoff: **rate vs. distortion**. Lower bitrate = smaller files / lower bandwidth, but more visible coding artifacts (blocking, ringing, mosquito noise). The same target bitrate gives wildly different quality across:

- **Codec generation** — [[h265-hevc-deep-dive|H.265]] typically achieves the same perceptual quality as [[h264-deep-dive|H.264]] at ~50% the bitrate. [[av1-vp9-future|AV1]] trims another 30% off [[h265-hevc-deep-dive|H.265]] in theory.
- **Encoder effort** — `x264 -preset placebo` vs `-preset ultrafast` can be a 2× quality difference at the same bitrate.
- **Content type** — static scenes compress much better than high-motion. A surveillance camera on a quiet alley will hit absurd compression ratios; a body-cam in a foot chase will not.

Surveillance cameras typically use [[h264-deep-dive|H.264]] or [[h265-hevc-deep-dive|H.265]] with **CBR (constant bitrate)** mode tuned to a target like 2–4 Mbps for 1080p. This produces predictable network load at the cost of leaving quality on the table during quiet scenes — a tradeoff cameras almost universally make.

## The codec family tree

Three rough lineages dominate:

```
MPEG family (ITU + MPEG, patent-pooled)
  MPEG-2 (1995, broadcast/DVD)
    └─ H.264 / AVC / MPEG-4 Part 10 (2003) — current default
        └─ H.265 / HEVC / MPEG-H Part 2 (2013) — 2× efficiency, patent thicket
            └─ H.266 / VVC (2020) — basically no production deployment

Google / On2 / AOMedia lineage (royalty-free)
  VP8 (2010, ex-On2)
    └─ VP9 (2013) — used in YouTube, almost nowhere else
        └─ AV1 (2018, AOMedia consortium) — finally getting hardware support

JPEG / still-image sibling
  JPEG (1992) — DCT, intra-only
    └─ MJPEG — JPEG frames in a video container
```

[[h264-deep-dive|H.264]] is the de-facto baseline for surveillance: every IP camera shipped in the last 15 years can produce it, every VMS can handle it, decode is hardware-accelerated everywhere, and the patent pool stabilized in the early 2010s. [[h265-hevc-deep-dive|H.265]] is gaining share in newer cameras (typically as an _option_ alongside [[h264-deep-dive|H.264]]) for bandwidth reasons, but the [[h265-hevc-deep-dive|licensing situation]] keeps adoption uneven. [[av1-vp9-future|AV1]] is a near-zero share of camera output today (see [[av1-vp9-future]]).

## What this means for Actuate

Our world is overwhelmingly [[h264-deep-dive|H.264]], with a long tail of [[h265-hevc-deep-dive|H.265]] (newer cameras, some Avigilon flows), [[mjpeg-and-still-image-formats|MJPEG]] (legacy or low-end cameras and snapshot endpoints), and a near-zero presence of [[av1-vp9-future|VP9]]/[[av1-vp9-future|AV1]]. Encode is exclusively to JPEG for frame storage and downstream consumption. Decode happens in three primary places: [[pyav-entity|PyAV]] inside `actuate-pullers` for the URL/[[rtsp-deep-dive|RTSP]] path, [[gstreamer-entity|GStreamer]] for the [[kvs-components|KVS]] path, and AutoPatrol's bespoke ISO-BMFF parser for the WebSocket path.

Reading-list pointers: see [[reading-list]] for the underlying encoder/decoder libraries (x264, x265, SVT-AV1, dav1d, aom-av1) that [[ffmpeg-entity|ffmpeg]]/[[pyav-entity|PyAV]]/[[gstreamer-entity|GStreamer]] ultimately wrap.

## Actuate touchpoints

| Codec / container | Where it appears in Actuate | File |
|---|---|---|
| [[h264-deep-dive|H.264]] | Primary [[rtsp-deep-dive|RTSP]]/HTTP decode path | `actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py` |
| [[h264-deep-dive|H.264]] (URL hint hack) | Forced via `videocodec=h264&` URL rewrite | `actuate-libraries/actuate-pullers/src/actuate_pullers/url/url_puller.py:150-151` |
| [[h265-hevc-deep-dive|H.265]] / [[h265-hevc-deep-dive|HEVC]] | Newer IP cameras; explicit warning logged | `av_url_puller.py:910-913` |
| [[h265-hevc-deep-dive|H.265]] keyframe-wait guard | Skips packets until first IDR | `av_url_puller.py:1318-1335` |
| [[mjpeg-and-still-image-formats|MJPEG]] / JPEG | Detection-frame encode; S3 storage | `actuate-libraries/actuate-pipeline/src/actuate_pipeline/steps/pre_processors/turbojpegencode_step.py`, `cv2encode_step.py`; `actuate-libraries/actuate-image-cache/src/actuate_image_cache/_decode.py` |
| MP4 / fMP4 | [[pyav-entity|PyAV]] demuxer; rotation via displaymatrix; recycle-on-frag-leak | `av_url_puller.py:139-171, 496-503, 1158-1185` |
| MKV (Matroska) | [[kvs-components|KVS]] payload via [[gstreamer-entity|GStreamer]] `matroskademux` | `actuate-libraries/actuate-pullers/src/actuate_pullers/kvs/kvs_ingestor.py:148-167` |
| ISO-BMFF (raw boxes) | AutoPatrol WebSocket stream parser | `actuate-libraries/actuate-pullers/src/actuate_pullers/socket/autopatrol_websocket_stream_puller.py:111-135` |

See [[actuate-frame-ingest-decode-paths]] for the full per-VMS decode-strategy matrix.
