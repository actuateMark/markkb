---
title: "Frame extraction strategies"
type: concept
topic: video-processing
tags: [decode, frame-extraction, pyav, opencv, skip-frame, gop, strategy, decision]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/2026-04-27.md
  - topics/video-processing/_summary.md
  - topics/video-processing/notes/concepts/connector-decoder-routing-map.md
  - topics/video-processing/notes/concepts/cv2-videocapture-internals.md
  - topics/video-processing/notes/entities/opencv-entity.md
  - topics/video-processing/notes/entities/pyav-entity.md
  - topics/video-processing/notes/syntheses/actuate-video-pipeline-walkthrough.md
incoming_updated: 2026-05-01
---

# Frame extraction strategies

How you turn an encoded video stream into ndarrays is a strategy choice with a real CPU and latency cost. This note is the **decision-oriented cheat sheet** for "what decode pattern fits which problem." Opinionated -- the patterns get picked for a reason.

Companion notes: [[pyav-entity]] (the canonical decode library), [[opencv-entity]] / [[cv2-videocapture-internals]] (the legacy library and its limits), [[gop-keyframe-fundamentals]] (why keyframe rate dominates these decisions), [[hardware-accelerated-codecs]] (the hwaccel multiplier).

## The strategies

### 1. Demux + decode every packet (`container.decode(video=0)`)

```python
container = av.open(url)
for frame in container.decode(video=0):
    process(frame)
```

The simplest pattern. [[pyav-entity|PyAV]] demuxes packets and decodes every video frame in arrival order. Equivalent to what `cv2.VideoCapture.read()` does internally, but with PTS access.

**Use when:** you need every frame, the stream is well-behaved, CPU is not the bottleneck. AutoPatrol per-fragment fMP4 decode (`autopatrol_websocket_stream_puller.py:194-275`) uses this -- fragments are short, framecount is small, simplicity wins.

**Don't use when:** you're decoding a long-[[gop-keyframe-fundamentals|GOP]] [[h265-hevc-deep-dive|H.265]] stream at 30fps and only need 1 fps for inference. You're paying full decode cost for 29× more frames than you need.

### 2. Demux + selective decode (`container.demux + packet.decode`)

```python
container = av.open(url)
for packet in container.demux(video_stream):
    if not_interested(packet):
        continue
    for frame in packet.decode():
        process(frame)
```

Splits the cost: demux is cheap; decode is expensive. Lets you make per-packet decisions before paying decode cost. The basis of every interesting downsampling strategy.

**Use when:** you need fine-grained control over which packets are decoded -- e.g. keyframe-only, time-window subsampling, packet inspection before decode.

**Actuate usage:** the canonical pattern in `av_url_puller.py:1276-1404`. `container.demux(video_stream)` → `_decode_packet(packet)` (line 755-775). Every streaming decode in [[actuate-pullers]] takes this shape.

### 3. Codec-level skip-frame (`AVDISCARD_*`)

```python
codec_context.skip_frame = av.video.codeccontext.SkipType.NONKEY
# or via the libav* enum:
# AVDISCARD_NONE     = 0    -- decode everything
# AVDISCARD_DEFAULT  = 0
# AVDISCARD_NONREF   = 8    -- skip frames not used as refs
# AVDISCARD_BIDIR    = 16   -- skip B-frames
# AVDISCARD_NONINTRA = 24   -- skip non-I frames (only intra-coded)
# AVDISCARD_NONKEY   = 32   -- skip non-keyframes
# AVDISCARD_ALL      = 48
```

The decoder is told to **skip work** at the codec level. `NONKEY` is the most useful: only keyframes (I-frames) get decoded; everything in between is discarded by the decoder before any pixel work happens. **Massive CPU savings** on long-[[gop-keyframe-fundamentals|GOP]] streams.

When each is safe:

- **`NONKEY`** -- safe always; you get only I-frames. CPU savings scale with [[gop-keyframe-fundamentals|GOP]] size.
- **`BIDIR`** -- safe; you get I+P frames (no B). Useful when you want most frames but want to avoid B-frame reorder cost.
- **`NONREF`** -- safe; skip frames not referenced by other frames. Smaller savings.
- **`NONINTRA`** -- equivalent to NONKEY for most modern [[codecs-overview|codecs]].
- **`ALL`** -- only useful for "open the codec and validate it without producing frames."

**The trap:** `NONKEY` only works if keyframes arrive often enough to feed your downstream model. If a camera is configured with a 60-second [[gop-keyframe-fundamentals|GOP]] (common for bandwidth-optimized cellular bridges), you get 1 fps when you `skip_frame=NONKEY`. If your ML pipeline expects 5 fps, the model starves.

**Actuate's adaptive switching** (`av_url_puller.py:617-753`) addresses this:

1. Start in `AVDISCARD_NONE` to measure actual keyframe rate over a 5-min window.
2. If keyframe rate ≥ pipeline threshold, switch to `NONKEY` -- saves CPU.
3. If rate drops below starvation threshold, fall back to `NONE` -- starvation > efficiency.
4. Re-evaluate every 5 minutes.

This is the single most-leveraged decode optimization in the codebase. See [[gop-keyframe-fundamentals]] for why [[gop-keyframe-fundamentals|GOP]] size is the dominant variable.

### 4. Random-access via seek

```python
container.seek(target_pts, stream=video_stream, any_frame=False)
for frame in container.decode(video=0):
    if frame.pts >= target_pts:
        return frame
```

`container.seek(pts)` jumps to the nearest keyframe ≤ target and starts decoding forward. Useful for scrub / random access to a long file.

**Cost on long-[[gop-keyframe-fundamentals|GOP]] streams:** very high. Seek lands on the previous keyframe; you decode forward through the entire [[gop-keyframe-fundamentals|GOP]] to reach your target frame. With a 60-frame [[gop-keyframe-fundamentals|GOP]], a seek to frame 59 decodes 60 frames. With **long-GOP [[h265-hevc-deep-dive|H.265]]** (which favors GOPs of 100+ frames) this is even worse.

**Don't use for:** real-time streaming. There's no notion of "seek" on [[rtsp-deep-dive|RTSP]] / live HTTP streams.

**Use for:** offline clip analysis, scrub-to-frame in alert-clip review, training-data assembly.

### 5. Decord-style batch reading (random access for ML)

Libraries like [[knowledgebase/topics/billing/reading-list#frame--stream-io-python|`decord`]] are optimized specifically for "give me frames at indices [i, j, k, ...] from this video file" use cases that ML training loops have. Internally they keep a more aggressive index of keyframe positions and overlap decode work across requests.

**Use for:** ML training pipelines reading clip files, where the access pattern is "random subset of frame indices per epoch."

**Don't use for:** streaming. `decord` is file-oriented. Not applicable for live [[rtsp-deep-dive|RTSP]] / HTTP streams.

**Actuate usage:** none today. Could be relevant for model training pipelines if scope expands. See [[knowledgebase/topics/billing/reading-list]] for the broader landscape.

### 6. Per-stream FPS downsampling vs per-pipeline downsampling

You can throttle the frame rate at two levels:

- **Per-stream (decoder side):** `cap.grab()` repeatedly to drop frames cheaply, or `skip_frame=NONKEY` at the codec level. Saves decode CPU.
- **Per-pipeline (consumer side):** the model pipeline picks frames at its own cadence; the decoder produces at full rate. Wastes decode CPU but isolates the consumer's cadence from the source.

**Strong opinion:** per-stream downsampling. Always. CPU savings compound across hundreds of cameras per pod; per-pipeline downsampling means you decode full-FPS just to throw away most frames. The exception is when codec-level downsampling would starve the model -- that's exactly the failure mode the adaptive `AVDiscard` switching was built to handle.

## The two parallel decode paths in [[actuate-pullers]]

Today, [[actuate-pullers]] has **two coexisting streaming decoders**:

| | [[opencv-entity|OpenCV]] path | [[pyav-entity|PyAV]] path |
|---|---|---|
| File | `actuate-pullers/url/url_puller.py:17-395` | `actuate-pullers/url/av_url_puller.py:320-1438` |
| Library | [[opencv-entity|`cv2.VideoCapture`]] | [[pyav-entity|PyAV]] |
| PTS access | no | yes |
| Adaptive skip-frame | no | yes |
| fMP4 fragment recycle | no | yes |
| Hwaccel | no | yes (CUDA/[[hardware-accelerated-codecs|VAAPI]]) |
| Migration status | parent class for motion-gated variants; held back by inheritance | canonical for all new integrations |

Other puller types are in the same OpenCV-or-PyAV pattern:

- File / batch (S3, SQS, socket, buffer, webcam): all [[opencv-entity|OpenCV]]. Lower bar -- file/clip sources don't suffer the [[rtsp-deep-dive|RTSP]] timing issues. Migration cost > migration benefit.
- AutoPatrol fMP4 fragment WebSocket: [[pyav-entity|PyAV]] (only practical option for `BytesIO` fMP4 fragments -- see `autopatrol_websocket_stream_puller.py:194-275`).

[[connector-factory|Connector factory]] routing decides per `integration_type` which puller class an integration gets. The migration to PyAV-everywhere-streaming is gated on porting the motion-gated variants out from `url_puller.py`'s class hierarchy; until then, the [[opencv-entity|OpenCV]] path stays in production for those integration types.

## Decision tree

```
Streaming source (RTSP, HTTP-MP4, fMP4 fragments)?
    Need PTS / multi-cam sync / hwaccel / adaptive downsampling?
        YES → PyAV (av_url_puller.py pattern)
              ├── adaptive AVDiscard (default)
              └── keyframe-wait guard on open
        NO (legacy or file-only) → cv2.VideoCapture (url_puller.py)

File / clip / S3 / SQS / local pipe?
    cv2.VideoCapture is fine. Tolerance for malformed input is a feature here.
    (Migration to PyAV is low-priority -- bar is much lower.)

ML training pipeline reading large clip files at random indices?
    Decord. Designed for this access pattern. Not used in Actuate today.

Ad-hoc script, batch frame export, notebook EDA?
    imageio. Friendly API, ffmpeg subprocess, lazy-installable binary.
    (Not used in Actuate today -- but a reasonable default for scripts.)
```

## Actuate touchpoints

- `actuate-pullers/url/av_url_puller.py:1276-1404` -- canonical [[pyav-entity|PyAV]] demux+decode loop.
- `actuate-pullers/url/av_url_puller.py:617-753` -- adaptive `AVDiscard` switching with starvation fallback.
- `actuate-pullers/url/av_url_puller.py:1318-1335` -- keyframe-wait guard.
- `actuate-pullers/url/av_url_puller.py:496-503, 1158-1185` -- fMP4 detection + recycle.
- `actuate-pullers/url/av_url_puller.py:174-317` -- `TimestampTracker` (PTS extraction, DTS fallback, discontinuity detection).
- `actuate-pullers/url/url_puller.py:339-363` -- legacy [[opencv-entity|OpenCV]] `cap.read()` + `cap.grab()` downsampling.
- `actuate-pullers/socket/autopatrol_websocket_stream_puller.py:194-275` -- per-fragment `av.open(BytesIO)` + `container.decode(video=0)`.
- See [[pyav-entity]] / [[opencv-entity]] / [[cv2-videocapture-internals]] for library-level details.
- See [[gop-keyframe-fundamentals]] / [[h265-hevc-deep-dive]] for why [[gop-keyframe-fundamentals|GOP]] size dominates skip-frame decisions.
- See [[hardware-accelerated-codecs]] for the GPU-decode multiplier on the [[pyav-entity|PyAV]] path.
- See [[actuate-frame-ingest-decode-paths]] for the per-VMS map of which decoder handles which integration type.
