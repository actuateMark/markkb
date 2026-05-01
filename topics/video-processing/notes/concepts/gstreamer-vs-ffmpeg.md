---
title: GStreamer vs FFmpeg
type: concept
topic: video-processing
tags: [gstreamer, ffmpeg, libav, pyav, decision-matrix, video, architecture]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - _index.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/video-processing/_summary.md
  - topics/video-processing/notes/concepts/ffmpeg-filtergraphs.md
  - topics/video-processing/notes/concepts/ffmpeg-hardware-acceleration.md
  - topics/video-processing/notes/concepts/ffmpeg-libav-libraries.md
  - topics/video-processing/notes/concepts/gstreamer-pipeline-model.md
  - topics/video-processing/notes/concepts/nvidia-deepstream.md
  - topics/video-processing/notes/concepts/rtsp-deep-dive.md
incoming_updated: 2026-05-01
---

# [[gstreamer-entity|GStreamer]] vs [[ffmpeg-entity|FFmpeg]]

This is the highest-leverage decision in any video-processing project: do you reach for [[ffmpeg-entity|**FFmpeg**]] (and its libraries `libav*`, fronted in Python by [[pyav-entity|PyAV]]), or for [[gstreamer-entity|**GStreamer**]]? The two are often described as "competitors" but the truth is more interesting -- they share most of their codec implementation (`gst-libav` is just [[ffmpeg-entity|FFmpeg]]'s libav* exposed as [[gstreamer-entity|GStreamer]] elements), and the choice between them is almost entirely about **pipeline shape and operational model**, not about codec support.

This note is opinionated: it tells you which tool to pick for which job, with the reasoning. It is the decision-oriented partner to [[gstreamer-entity]], [[ffmpeg-entity]], and [[ffmpeg-libav-libraries]].

## The fundamental difference

**[[ffmpeg-entity|FFmpeg]] is a transcoder.** Its native operating mode is "read this input, apply these filters, write this output, exit". The CLI reflects that (`ffmpeg -i in.mp4 -c:v libx265 out.mp4`); so does the C library API (`avformat_open_input`, demux loop, `avcodec_send_packet` / `avcodec_receive_frame`, `avformat_write`). It can do streaming work (`-i [[rtsp-deep-dive|rtsp]]://...`, `-f flv [[rtmp-and-srt|rtmp]]://...`), but the API still feels batch-oriented: you build an invocation, run it, and manage failure by restarting.

**[[gstreamer-entity|GStreamer]] is a pipeline runtime.** Its native operating mode is "set up a graph, set state to PLAYING, listen to the bus, react". Pipelines are long-lived. They renegotiate caps when the source changes resolution. They expose per-element state that you can introspect at runtime. They support dynamic reconfiguration -- adding/removing branches, swapping encoders -- while running. The cost: an entirely different mental model, plus 5-10× more boilerplate for a one-shot transcode.

A useful one-liner: **[[ffmpeg-entity|FFmpeg]] is a Unix tool; [[gstreamer-entity|GStreamer]] is an actor system.**

## Codec support: a non-difference

Both wrap **libavcodec**. [[gstreamer-entity|GStreamer]]'s `gst-libav` plugin set exposes `avdec_h264`, `avdec_h265`, `avdec_aac`, `avenc_*`, etc. -- these are literally [[ffmpeg-entity|FFmpeg]]'s decoders/encoders, behind the [[gstreamer-entity|GStreamer]] plugin interface. Hardware [[codecs-overview|codecs]] are similar: [[ffmpeg-entity|FFmpeg]] has `h264_nvenc` / `h264_qsv` / `h264_vaapi`, [[gstreamer-entity|GStreamer]] has `nvh264enc` / `vaapih264enc`. They wrap the same vendor SDKs.

Implication: **codec coverage is not a tiebreaker.** If you're choosing between [[ffmpeg-entity|FFmpeg]] and [[gstreamer-entity|GStreamer]] because "[[ffmpeg-entity|FFmpeg]] supports more codecs", you're wrong. The decision is about pipeline shape.

## Decision matrix

| Question | Pick [[ffmpeg-entity|FFmpeg]] / [[pyav-entity|PyAV]] | Pick [[gstreamer-entity|GStreamer]] |
|----------|--------------------|----------------|
| One-shot transcode of a file? | YES | overkill |
| Long-lived multi-stream service with hot-swappable elements? | painful | YES |
| Hardware accel as one-token swap? | possible but invasive | YES (just rename element) |
| Need fine-grained codec control (rate-control mode, [[gop-keyframe-fundamentals|GOP]], refs)? | YES | possible but indirect |
| Latency-bounded real-time pipeline (<200 ms end-to-end)? | hard | YES |
| Bridging to [[aws-kvs-entity|AWS KVS]] / [[rtmp-and-srt|SRT]] / [[webrtc-deep-dive|WebRTC]] / NDI in same process? | partial ([[aws-kvs-entity|KVS]] Producer SDK is [[gstreamer-entity|GStreamer]]-only) | YES |
| Team has zero [[gstreamer-entity|GStreamer]] literacy and project is a one-off? | YES | NO |
| Pipeline observability / per-element timing? | weak (parse stderr) | strong (bus + `gst-shark`) |
| Python ergonomics? | YES via [[pyav-entity|PyAV]] | acceptable via PyGObject; verbose |
| Single-frame extraction at random offsets? | YES ([[pyav-entity|PyAV]] / decord) | overkill |
| Need dynamic graph mutation while running? | NO | YES |
| Want to inline-process bytes from arbitrary Python source? | YES ([[pyav-entity|PyAV]] `av.open(io.BytesIO)`) | YES (`appsrc`) |
| Long-term ML-pipeline integration with NVIDIA hardware? | possible | YES ([[nvidia-deepstream|DeepStream]] is [[gstreamer-entity|GStreamer]]; see [[nvidia-deepstream]]) |

## Latency

[[gstreamer-entity|GStreamer]]'s pipeline-with-clock model is built for low latency. Elements expose latency contributions; the pipeline aggregates them; the bus surfaces renegotiations. `rtspsrc latency=0` plus careful queue management gets you sub-200 ms end-to-end on [[h264-deep-dive|H.264]] [[rtsp-deep-dive|RTSP]] feeds.

[[ffmpeg-entity|FFmpeg]] can hit similar latencies in narrow configurations, but tuning is per-flag and surprises are frequent (`-fflags nobuffer`, `-flags low_delay`, `-strict experimental`, ...). For a single fixed pipeline you can dial it in. For a fleet of varying inputs, [[gstreamer-entity|GStreamer]]'s per-element latency negotiation is structurally easier to reason about.

## Observability

[[ffmpeg-entity|FFmpeg]]'s observability surface is **stderr text**. To get per-frame timing you parse log lines or run with `-progress`. There's no per-filter timing breakdown unless you instrument the C API directly.

[[gstreamer-entity|GStreamer]] ships with:

- The bus, which gives you structured async messages.
- `GST_DEBUG=3` (or higher) for per-element trace.
- `gst-shark` for production profiling -- per-element latency, queue depth, buffer drops over time.
- `GST_TRACERS` for runtime-pluggable tracers (latency, queue level, framerate).

For long-lived production pipelines this is a real differentiator.

## Learning curve

[[ffmpeg-entity|FFmpeg]] CLI: 30 minutes for the common case. [[pyav-entity|PyAV]]: a weekend.

[[gstreamer-entity|GStreamer]]: weeks. The element/pad/caps/bus model is conceptually heavier; failures (caps negotiation, missing plugins, async state changes) require knowing the framework to debug. The payoff arrives once you've internalized it -- thereafter, complex pipelines are 5 minutes; without that internalization, every pipeline is half a day.

A team without [[gstreamer-entity|GStreamer]] literacy taking on a [[gstreamer-entity|GStreamer]] project pays this cost up-front. A team with literacy gets compounding returns. This is the single biggest soft factor in the decision.

## Language bindings

- **Python** -- [[pyav-entity|PyAV]] is the gold standard for [[ffmpeg-entity|FFmpeg]]; PyGObject is the only mainstream binding for [[gstreamer-entity|GStreamer]]. [[pyav-entity|PyAV]]'s API is significantly more Pythonic.
- **Rust** -- `ffmpeg-next` for [[ffmpeg-entity|FFmpeg]]; `gstreamer-rs` for [[gstreamer-entity|GStreamer]]. `gstreamer-rs` is genuinely production-grade; `ffmpeg-next` is a usable but somewhat thin wrapper.
- **Go** -- `gst-cgo` and various [[ffmpeg-entity|FFmpeg]] shellouts. Neither is great. Most production Go video stacks (Pion, MediaMTX, GO2RTC) reimplement what they need.
- **C/C++** -- both excellent, with [[ffmpeg-entity|FFmpeg]]'s API being smaller and more stable.

## When to use both (the most common answer)

For most non-trivial systems the right answer is **both, in different roles**:

- [[ffmpeg-entity|FFmpeg]] / [[pyav-entity|PyAV]] for the parts that are batch or fine-grained: pulling [[rtsp-deep-dive|RTSP]] for ML inference, encoding alert clips with specific quality settings, post-processing recordings.
- [[gstreamer-entity|GStreamer]] for the parts that need pipeline shape: [[kvs-components|KVS]] publish/consume, [[rtsp-deep-dive|RTSP]] server hosting, [[webrtc-deep-dive|WebRTC]] bridging, multi-stream batched-inference pipelines ([[nvidia-deepstream|DeepStream]]).

This is exactly Actuate's split.

## Actuate's split (the worked example)

- **Real-time ingest from [[rtsp-deep-dive|RTSP]] / HTTP / file** -- `actuate-pullers` defaults to `AvUrlFramePuller`, which is **[[pyav-entity|PyAV]]-based** (libav* directly, no [[ffmpeg-entity|FFmpeg]] subprocess, no [[gstreamer-entity|GStreamer]] dependency). Lightweight, fast, no plugin runtime to manage. This is the production path.
- **[[kvs-components|KVS]] ingest** -- `actuate-libraries/actuate-pullers/src/actuate_pullers/kvs/kvs_ingestor.py:148-156` uses **[[gstreamer-entity|GStreamer]]**. The reason: [[kvs-components|KVS]] GetMedia returns a streaming MKV body, and `appsrc → matroskademux → decodebin → ...` is a clean expression of "feed me bytes, demux, decode, hand frames out". You could do this in [[pyav-entity|PyAV]] (`av.open(BytesIO)`) and probably should in a future iteration; [[gstreamer-entity|GStreamer]] was chosen historically because the AWS-published reference for [[kvs-components|KVS]] *publishing* is the `kvssink` [[gstreamer-entity|GStreamer]] plugin and it set the team's defaults.
- **Legacy [[gstreamer-entity|GStreamer]] [[rtsp-deep-dive|RTSP]]** -- `actuate-libraries/actuate-pullers/src/actuate_pullers/gstreamer/gstreamer_input_pipeline.py:86-101`. Hardcoded [[h264-deep-dive|H.264]] (`rtph264depay ! h264parse ! avdec_h264`), so [[h265-hevc-deep-dive|H.265]] [[rtsp-deep-dive|RTSP]] cameras silently fail through this path. Kept for fallback / experimentation; not the default.
- **Alert clip generation** -- [[ffmpeg-entity|FFmpeg]] subprocess. Right call: it's a one-shot transcode/mux per clip, not a long-lived pipeline.

The Actuate decision pattern, made explicit:

1. **Default to [[pyav-entity|PyAV]]** for ingest unless something forces otherwise.
2. **Reach for [[gstreamer-entity|GStreamer]]** when you need protocol bridging (`appsrc`/`appsink` integration with non-FFmpeg sources, [[kvs-components|KVS]], future [[rtmp-and-srt|SRT]]/[[webrtc-deep-dive|WebRTC]]/NDI), batched multi-stream pipelines ([[nvidia-deepstream|DeepStream]]), or runtime hardware-accel swapping.
3. **Reach for [[ffmpeg-entity|FFmpeg]] CLI** for batch transcodes (clip generation, archive re-encoding).

The [[kvs-components|KVS]] path's decode→jpegenc→imdecode round-trip (see [[gstreamer-pipeline-model]] Actuate touchpoints) is a sign that the [[gstreamer-entity|GStreamer]] choice there has cost -- a PyAV-based [[kvs-components|KVS]] path could remove the round-trip and the runtime plugin dependency.

## Related notes

- [[gstreamer-entity]] -- what [[gstreamer-entity|GStreamer]] is
- [[gstreamer-pipeline-model]] -- pipeline grammar
- [[ffmpeg-entity]], [[ffmpeg-libav-libraries]] -- the codec foundation
- [[pyav-entity]] -- the Python libav* binding
- [[nvidia-deepstream]] -- [[gstreamer-entity|GStreamer]]'s strongest argument for ML
- [[hardware-accelerated-codecs]]
- [[actuate-frame-ingest-decode-paths]], [[actuate-video-pipeline-walkthrough]]

## Cross-topic

- [[vms-connector/_summary]], [[actuate-libraries/_summary]], [[fleet-architecture/_summary]]

## Actuate touchpoints

- **`actuate-pullers` default = [[pyav-entity|PyAV]]** -- `AvUrlFramePuller` is the production path. Right call.
- **`actuate-pullers` [[kvs-components|KVS]] = [[gstreamer-entity|GStreamer]]** -- the only place [[gstreamer-entity|GStreamer]] is in the active hot path. Worth re-evaluating: a PyAV-based [[kvs-components|KVS]] reader (`av.open(BytesIO)` over the GetMedia stream) would remove the runtime PyGObject + plugin dependency *and* skip the JPEG re-encode round-trip.
- **`actuate-pullers` legacy [[gstreamer-entity|GST]] [[rtsp-deep-dive|RTSP]] = optional / disabled by default** -- `try/except ImportError` in `actuate-pullers/__init__.py`. [[h264-deep-dive|H.264]]-hardcoded, silently breaks [[h265-hevc-deep-dive|H.265]]. Either generalize codec via `decodebin` or deprecate.
- **Alert clip pipeline = [[ffmpeg-entity|FFmpeg]] subprocess** (in `actuate-alarm-senders` clip-builder). Right call.
- **Decision drift risk** -- new contributors reach for whichever one they know. Without a written policy, the codebase ends up with a mix that's hard to maintain. This note is the policy.
