---
title: "FFmpeg Python bindings — decision matrix"
type: concept
topic: video-processing
tags: [ffmpeg, python, pyav, opencv, imageio, moviepy, bindings]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
---

# [[ffmpeg-entity|FFmpeg]] Python bindings — decision matrix

There is no single "Python [[ffmpeg-entity|FFmpeg]] library" — there are at least five mainstream options and they all compose differently. Picking the wrong one for a job results in either fighting the library forever (subprocess builders for tight inner loops) or reinventing convenience wrappers ([[pyav-entity|PyAV]] when you wanted a one-liner). This note maps each option to its sweet spot and gives the call signal for choosing among them.

## The options

### 1. [[pyav-entity|PyAV]] (`pip install av`)

**What it is:** Cython bindings to the libav* C API. You get Python objects (`av.Container`, `av.Stream`, `av.Packet`, `av.Frame`, `av.CodecContext`, `av.filter.Graph`) that are 1:1 with the C structs.

**Strengths:**
- No subprocess overhead — runs in-process.
- Direct access to packets and frames, including timestamps, side data, and codec parameters.
- Hardware-decoder selection via `av.CodecContext.create("h264_cuvid", "r")` — full control.
- Filtergraph access via `av.filter.Graph` — same expressive power as `ffmpeg -filter_complex`.
- Battle-tested in ML training pipelines and production streaming.

**Weaknesses:**
- API surfaces a lot of [[ffmpeg-entity|FFmpeg]]'s complexity — you have to know what an AVPacket is.
- Wheel availability sometimes lags [[ffmpeg-entity|FFmpeg]] releases.
- Multi-threading awkward; the GIL holds during `frame.to_ndarray()`.

**Use when:** You're decoding/encoding in a Python service and need fine-grained control over packets, frames, codec contexts, or hwaccel. **This is the right default for any production decode loop.**

### 2. [[ffmpeg-entity|ffmpeg]]-python (`pip install ffmpeg-python`)

**What it is:** Pure-Python builder that constructs `ffmpeg` CLI invocations from a chained API and `subprocess.run`s them. Does not link any [[ffmpeg-entity|FFmpeg]] libraries.

```python
import ffmpeg
(
    ffmpeg
    .input('rtsp://cam/stream', rtsp_transport='tcp')
    .filter('scale', 1280, 720)
    .filter('fps', 10)
    .output('out.mp4', vcodec='h264_nvenc')
    .overwrite_output()
    .run()
)
```

**Strengths:**
- Cleaner ergonomics than building shell strings by hand.
- Filtergraph composition is genuinely easier than typing comma-separated chains.
- Output is just an `ffmpeg` invocation — easy to debug (call `.get_args()` and copy-paste).

**Weaknesses:**
- Subprocess only — no in-process frame access.
- Maintainership has been sporadic (last meaningful release older than its competitors).
- Errors come from the subprocess as stderr text, not Python exceptions.

**Use when:** You're orchestrating one-shot transcodes / muxes from Python and want CLI ergonomics without manual string-building. **Not appropriate for a tight frame loop.**

### 3. [[imageio-entity|imageio]] + imageio-[[ffmpeg-entity|ffmpeg]] (`pip install imageio imageio-ffmpeg`)

**What it is:** Friendly read/write API in `imageio`; `imageio-ffmpeg` is a subprocess-based plugin that supplies the [[ffmpeg-entity|FFmpeg]] binary (statically built) so users don't need a system [[ffmpeg-entity|FFmpeg]].

```python
import imageio
reader = imageio.get_reader('input.mp4')
for i, frame in enumerate(reader):
    pass  # frame is a numpy array (H, W, 3) RGB
```

**Strengths:**
- Trivial API; `imread` / `imwrite` model adapted for video.
- Bundles its own static [[ffmpeg-entity|FFmpeg]] — works in any container without `apt-get install ffmpeg`.
- Sane fallbacks; less footgun-prone than [[pyav-entity|PyAV]] for casual users.

**Weaknesses:**
- Subprocess pipe — frames flow through stdin/stdout. Adds memcpy and latency.
- Limited control over codec/hwaccel selection.
- Not the right tool for live [[rtsp-deep-dive|RTSP]] — pipe buffering causes latency.

**Use when:** You're prototyping or doing batch frame I/O in research code. Don't use it for production live decode.

### 4. [[opencv-entity|OpenCV]]'s `cv2.VideoCapture` (`pip install opencv-python`)

**What it is:** [[opencv-entity|OpenCV]] ships with [[ffmpeg-entity|FFmpeg]] statically bundled into the wheel. `cv2.VideoCapture` is [[opencv-entity|OpenCV]]'s video reader; on Linux the default backend is the bundled FFmpeg (libavformat + libavcodec).

```python
import cv2
cap = cv2.VideoCapture('rtsp://cam/stream')
while True:
    ok, frame = cap.read()  # frame is BGR numpy array
    if not ok:
        break
```

**Strengths:**
- Most familiar API in CV land — every tutorial uses it.
- Frames come out as BGR numpy arrays directly, ready for [[opencv-entity|OpenCV]] / inference.
- Bundled FFmpeg means no system dependency wrestling.
- Backend selection via `cv2.CAP_FFMPEG`, `cv2.CAP_GSTREAMER`, etc. — flexible.

**Weaknesses:**
- Almost no control over codec parameters or hwaccel beyond the env-var sledgehammer (`OPENCV_FFMPEG_CAPTURE_OPTIONS=rtsp_transport;tcp`).
- Silent stream failures — `cap.read()` returns `(False, None)` with no diagnostic info.
- Bundled FFmpeg may lack hardware [[codecs-overview|codecs]]; system FFmpeg may have [[hardware-accelerated-codecs|NVENC]]/[[hardware-accelerated-codecs|NVDEC]] but you're not using it.
- Dropped frames often invisible. Latency creep on [[rtsp-deep-dive|RTSP]] is hard to debug.

**Use when:** You're doing CV inference on ad-hoc clips and want zero setup; or you're maintaining legacy code that already uses it. **Avoid for new live-stream production paths** unless you've benchmarked and accepted the limits.

### 5. MoviePy (`pip install moviepy`)

**What it is:** High-level video editing library — clip composition, concat, overlay, transitions. Uses `imageio-ffmpeg` under the hood, plus PIL for stills.

**Strengths:**
- Genuinely the easiest API for "stitch these clips and overlay text on this one."
- Good for generating training/demo videos.

**Weaknesses:**
- Slow (subprocess + repeated decode passes).
- Wrong tool for any production streaming or inference path.

**Use when:** Tooling, demos, marketing-clip assembly. Never in a hot path.

## Decision matrix

| Need | Pick | Why |
|------|------|-----|
| Live [[rtsp-deep-dive|RTSP]] → numpy frames in production | **[[pyav-entity|PyAV]]** | In-process, low latency, hwaccel-controllable |
| Live [[rtsp-deep-dive|RTSP]] → numpy in legacy code | **[[opencv-entity|OpenCV]] `VideoCapture`** | Already there; just be aware of limits |
| One-shot transcode from Python | **[[ffmpeg-entity|ffmpeg]]-python** or just `subprocess.run([...])` | Easy CLI composition |
| Batch frame extraction for ML training | **decord** (not FFmpeg-family) or **[[pyav-entity|PyAV]]** with seek | Random access > sequential |
| Casual read/write in a research notebook | **[[imageio-entity|imageio]]** | Simplest API |
| Edit clips for a marketing reel | **MoviePy** | Right ergonomic level |
| Multi-input filtergraph with overlays | **[[pyav-entity|PyAV]]** (`av.filter.Graph`) or **`ffmpeg-python`** | Both expose filtergraph composition |
| Streaming [[webrtc-deep-dive|WebRTC]] | None of these — use **aiortc** | FFmpeg-family [[webrtc-deep-dive|WebRTC]] support is weak |

See [[reading-list]] for the full catalog (decord, vidgear, scikit-video, aiortc).

## Subprocess-builders (a meta-category)

Anything that calls `subprocess.run(["ffmpeg", ...])` falls into the same trade-off bucket: you get every [[ffmpeg-entity|FFmpeg]] feature for free, you pay process-spawn overhead per invocation, and you parse stderr to detect errors. `ffmpeg-python`, `imageio-ffmpeg`, and `MoviePy` are all variants of this pattern; rolling your own with `subprocess.run` directly is often clearer for one-off jobs:

```python
import subprocess
result = subprocess.run(
    ["ffmpeg", "-hide_banner", "-loglevel", "error",
     "-rtsp_transport", "tcp", "-i", url,
     "-t", "10", "-c", "copy", out_path],
    capture_output=True, text=True, check=True,
)
```

A bare `subprocess.run` is honest about what it is. Wrappers can hide that you're really just composing CLI strings.

## The libav* vs subprocess trade

The fundamental fork is whether your library **links libav* in-process** ([[pyav-entity|PyAV]], [[opencv-entity|OpenCV]]'s bundled [[ffmpeg-entity|FFmpeg]]) or **shells out to a separate `ffmpeg` process** (ffmpeg-python, [[imageio-entity|imageio]]-ffmpeg, MoviePy).

| Concern | In-process (libav*) | Subprocess |
|---------|--------------------|-----------|
| Frame access | Direct | Pipe / temp file |
| Latency | Low (function calls) | High (process spawn + IPC) |
| Memory | Shared with Python | Separate; copies cost |
| Error handling | Python exceptions | stderr parsing |
| Crash blast radius | Process crash takes down service | Subprocess crash isolated |
| Hwaccel control | Fine-grained | Whatever flags you compose |
| Setup complexity | Wheel must match | Just need `ffmpeg` on PATH |

**Rule of thumb:** if a frame is going to be consumed in Python (inference, manipulation), use in-process. If you're producing an output file/stream and don't need to touch frames, subprocess is fine.

## Actuate touchpoints

Actuate uses three of the five options, with deliberate role separation:

- **Primary path: [[pyav-entity|PyAV]]** — `actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py:320-1438`. Live [[rtsp-deep-dive|RTSP]] decode, hwaccel-controllable. Hardware decoder context creation at `lines 83-131` uses `av.CodecContext.create(...)` with names like `h264_cuvid` from the `HW_DECODERS` table at lines 24-77. Frame egress via `frame.to_ndarray(format="bgr24")` at line 1351.
- **Legacy / SMTP-per-camera path: [[opencv-entity|OpenCV]]'s bundled [[ffmpeg-entity|FFmpeg]]** — `url_puller.py:17-395` and `sqs_puller.py:53`. [[rtsp-deep-dive|RTSP]] transport pinned via `OPENCV_FFMPEG_CAPTURE_OPTIONS=rtsp_transport;tcp` (lines 314, 318). Frame egress via `cap.read()` returning BGR numpy directly. The choice here predates [[pyav-entity|PyAV]] in the codebase; the path is being slowly migrated where latency-sensitive.
- **No `ffmpeg-python`, no `imageio`, no MoviePy** in the connector code path. They're acceptable for ad-hoc developer tooling but explicitly **not** in the production decode tree.
- **Direct `subprocess.run(["ffmpeg", ...])`** appears once for **hwaccel detection only**: `av_url_puller.py:546, 567, 587, 597`. The team's standard is "[[pyav-entity|PyAV]] for media work, subprocess for environment probes only."

If you're adding a new puller or transcode path: default to [[pyav-entity|PyAV]]. Use [[opencv-entity|OpenCV]]'s `VideoCapture` only when matching an existing pattern in the same file. Justify any subprocess-builder choice in the PR description — the team has hit subprocess-pipe latency bugs before and the bias is against re-introducing them.

Cross-refs: [[ffmpeg-entity]] | [[ffmpeg-libav-libraries]] | [[ffmpeg-hardware-acceleration]] | [[pyav-entity]] | [[opencv-entity]] | [[actuate-frame-ingest-decode-paths]] | [[reading-list]]
