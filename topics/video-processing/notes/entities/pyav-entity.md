---
title: "PyAV"
type: entity
topic: video-processing
tags: [pyav, libav, ffmpeg, python, decode, frame-extraction, library]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/actuate-libraries/notes/entities/actuate-pullers.md
  - topics/actuate-platform/notes/syntheses/camera-onboarding-end-to-end.md
  - topics/fleet-architecture/notes/concepts/frame-storage-current-state.md
  - topics/fleet-architecture/notes/syntheses/2026-04-22_fleet-proposal-rescore-with-delta.md
  - topics/fleet-architecture/notes/syntheses/2026-04-22_frame-storage-design-deltas.md
  - topics/fleet-architecture/notes/syntheses/2026-04-22_proposal-b-prime-stateless-with-coordinator.md
  - topics/integrations/autopatrol-integration/_summary.md
  - topics/integrations/autopatrol-integration/notes/entities/autopatrol-integration-components.md
  - topics/integrations/rtsp/_summary.md
  - topics/integrations/rtsp/notes/entities/rtsp-components.md
incoming_updated: 2026-05-01
---

# PyAV

PyAV is a **Cython binding to the libav\* family** (`libavformat`, `libavcodec`, `libavutil`, `libswscale`, `libswresample`) -- the same C libraries that power [[ffmpeg-entity|the ffmpeg CLI]]. Unlike [[reading-list#frame--stream-io-python|`ffmpeg-python`]] (which builds shell command strings) or [[opencv-entity|OpenCV's `cv2.VideoCapture`]] (which wraps libav* but hides almost everything), PyAV exposes libav\*'s primitives **directly** as Python objects: `Container`, `Stream`, `Packet`, `Frame`, `CodecContext`, `BitStreamFilter`. If you can do it with the C API, you can do it with PyAV.

This makes PyAV the only viable option in Python when you actually need to **control the decoder** -- presentation timestamps, packet-level filtering, hardware accel context, skip-frame modes, side-data extraction. See [[ffmpeg-libav-libraries]] for the C-side primitives PyAV mirrors.

## The model

PyAV's API maps directly onto libav\*'s logical hierarchy:

| PyAV object | libav\* equivalent | What it represents |
|---|---|---|
| `av.Container` | `AVFormatContext` | An open input or output (file, [[rtsp-deep-dive|RTSP]] URL, HTTP URL, BytesIO) |
| `av.Stream` | `AVStream` | One stream within a container (video, audio, subtitle) |
| `av.Packet` | `AVPacket` | One compressed unit -- a NALU group, an audio frame |
| `av.VideoFrame` | `AVFrame` (video) | One decoded frame, with PTS / DTS / pict_type / side_data |
| `av.CodecContext` | `AVCodecContext` | Decoder/encoder state -- where you set `skip_frame`, `thread_count`, hwaccel |
| `av.BitStreamFilterContext` | `AVBSFContext` | Bitstream-level transformations (e.g. `h264_mp4toannexb`) |

Once this maps in your head, PyAV becomes the obvious thing: it's just libav\* with a `__del__` method.

## Why PyAV is strictly more powerful than `cv2.VideoCapture`

[[opencv-entity|OpenCV]]'s video API is designed around `cap.read() -> (ok, frame)`. That's the entire surface area. PyAV opens up:

- **Presentation timestamps.** `frame.pts`, `frame.dts`, `frame.time` (PTS converted to seconds via the stream's timebase). The basis of all clip alignment, multi-stream sync, drift correction. Critical for any pipeline doing temporal reasoning.
- **Side-data.** Display matrix (rotation), color metadata (BT.709 vs BT.601 vs BT.2020), HDR mastering metadata, A53-CC captions. `cv2.VideoCapture` swallows all of this.
- **Packet-level access.** `container.demux(stream)` yields `AVPacket` objects you can inspect, filter, route, or selectively decode. Lets you do "extract keyframes only" in O(1) per non-keyframe instead of decoding everything and dropping frames.
- **Skip-frame modes.** `codec_context.skip_frame = AVDISCARD_NONKEY` (or `BIDIR`, `NONINTRA`) tells the decoder to skip non-reference frames at the codec level -- huge CPU savings on long-[[gop-keyframe-fundamentals|GOP]] streams when you don't need every frame. See [[frame-extraction-strategies]] and [[gop-keyframe-fundamentals]].
- **Hardware acceleration.** `av.CodecContext.create(...)` lets you attach a hwaccel context (CUDA, [[hardware-accelerated-codecs|VAAPI]], [[hardware-accelerated-codecs|QuickSync]]). `av.codec.hwaccel.HWAccel` exposes the libav\* hwdevice API. See [[hardware-accelerated-codecs]].
- **Bitstream filters.** `h264_mp4toannexb`, `hevc_mp4toannexb` -- the canonical "rebox raw [[h264-deep-dive|H.264]] from MP4 boxes into Annex-B" filter, which you need anytime you're shoveling MP4-fragment streams into a downstream Annex-B consumer.
- **Custom I/O.** `av.open(io.BytesIO(...))` works. So does `av.open(custom_pyio_obj)`. You're not constrained to URLs and file paths.
- **Re-mux without re-encode.** Open input container → demux packets → mux to output container. Zero CPU. `cv2.VideoCapture`/`cv2.VideoWriter` cannot do this.

## Tradeoffs

- **Steeper API.** "Demux a packet, decode it, get a frame" is three concepts where `cv2.cap.read()` is one. The win is control; the cost is cognitive load.
- **Heavier installs.** `pip install av` ships a wheel with libav\* statically linked, but those wheels are big (~50 MB) and version-pinned to a specific [[ffmpeg-entity|FFmpeg]] release. Conflicts with system [[ffmpeg-entity|FFmpeg]] are possible.
- **Error surface is large.** libav\* has dozens of error codes; many of them surface through PyAV as `av.error.FFmpegError` subclasses (`av.error.InvalidDataError`, `av.error.EOFError`, etc.). Handling them properly matters -- see the discontinuity / recycle logic in `av_url_puller.py`.
- **Documentation is thin.** PyAV's docs cover the API surface but don't explain libav\* semantics. You end up reading `ffmpeg.c` and `libavformat/avformat.h` to understand what PyAV is doing under the hood.

## Actuate usage: the canonical streaming decode path

PyAV is **the** strategic decode library for [[actuate-pullers]]. The migration from [[opencv-entity|OpenCV's `VideoCapture`]] is in progress; new integrations land on PyAV.

**Primary location:**
- `actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py:320-1438` -- the PyAV-based [[rtsp-deep-dive|RTSP]]/HTTP puller. The replacement for [[opencv-entity#actuate-usage-ubiquitous-trending-toward-preprocess-only|`url_puller.py`]] for new integrations and many migrated old ones.

**Key features inside `av_url_puller.py`:**

- **Demux + decode loop** (`:1276-1404`): `container.demux(video_stream)` → `_decode_packet(packet)` (line 755-775) → `frame.to_ndarray(format="bgr24")` (line 1351). The classic libav\* read loop, with explicit packet handling so we can do per-packet decisions before paying the decode cost.
- **PTS extraction with DTS fallback** (`:174-317`, `TimestampTracker`): some camera bridges emit packets without PTS; we fall back to DTS, detect discontinuities, and apply burst-drift correction (specifically observed on Milestone XProtect bridges).
- **Adaptive `AVDiscard` switching** (`:617-753`): the puller measures the keyframe rate over a 5-min window. If keyframes arrive frequently enough, it sets `skip_frame=NONKEY` to skip non-reference frames at the codec level. If the keyframe rate drops below a starvation threshold, it falls back to `AVDISCARD_NONE` to avoid model-pipeline starvation. See [[frame-extraction-strategies]] for the decision logic.
- **fMP4 detection + recycle** (`:496-503, 1158-1185`): the libav\* `mov` demuxer leaks `frag_index` memory on long-running fMP4 streams. The puller detects fMP4 inputs and proactively recycles the container every ~300s+jitter to flush this leak.
- **Hardware decoder context** (`:83-131`, `create_hw_decoder_context`): wires up CUDA/[[hardware-accelerated-codecs|VAAPI]] hwaccel via `av.CodecContext` when available on the node.
- **Keyframe-wait guard** (`:1318-1335`): on stream open or post-recycle, drop frames until the first keyframe to avoid emitting macroblock garbage.

**AutoPatrol fragmented MP4 decode:**
- `actuate-libraries/actuate-pullers/src/actuate_pullers/socket/autopatrol_websocket_stream_puller.py:194-275` -- per-fragment `av.open(io.BytesIO(combined), format="mp4", mode="r")` then `container.decode(video=0)`. AutoPatrol's [[autopatrol/_summary|immix Connect]] WebSocket pushes fMP4 init+media segments; we accumulate `init+moof+mdat`, hand the bytes to PyAV, and let it demux+decode. This is the **only** practical way to do this in Python -- `cv2.VideoCapture` cannot read from a `BytesIO` fMP4 fragment.

**[[connector-factory|Connector factory]] routing** decides which puller class an integration gets. Some integration types are still on `url_puller.py` ([[opencv-entity|OpenCV]]); others have been migrated to `av_url_puller.py` (PyAV). The migration is incomplete, partly because `url_puller.py` is the parent class for several motion-gated variants that haven't been ported yet.

## Actuate touchpoints

- `actuate-pullers/url/av_url_puller.py` -- the canonical PyAV puller. ~1400 lines of demux/decode/timestamp/recycle/hwaccel logic. Read this file to understand how Actuate decodes [[rtsp-deep-dive|RTSP]] and HTTP-MP4 in 2026.
- `actuate-pullers/socket/autopatrol_websocket_stream_puller.py` -- fMP4 fragment decode via PyAV's BytesIO `av.open`. Only path that handles WebSocket-delivered MP4 fragments.
- `actuate-pullers/url/av_url_puller.py:139-171` -- `parse_displaymatrix` extracting MP4 rotation side-data and routing to `cv2.rotate`. Hybrid PyAV (extract metadata) + [[opencv-entity|OpenCV]] (apply rotation). See [[opencv-entity]].
- See [[frame-extraction-strategies]] for the strategic decision tree (when to use which decoder, which skip-frame mode, when to recycle).
- See [[ffmpeg-libav-libraries]] for the underlying C primitives.
- See [[hardware-accelerated-codecs]] for hwaccel context setup.
- See [[gop-keyframe-fundamentals]] for why `skip_frame=NONKEY` and keyframe-wait matter.
