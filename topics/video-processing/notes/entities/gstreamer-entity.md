---
title: GStreamer
type: entity
topic: video-processing
tags: [gstreamer, pipeline, multimedia, rtsp, plugins, deepstream, video, ffmpeg]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/actuate-libraries/notes/entities/actuate-config.md
  - topics/actuate-libraries/notes/entities/actuate-pullers.md
  - topics/infrastructure/notes/entities/remote-access-proxy.md
  - topics/integrations/adpro/_summary.md
  - topics/integrations/kvs/_summary.md
  - topics/integrations/kvs/notes/entities/kvs-components.md
  - topics/integrations/rtsp/_summary.md
  - topics/integrations/rtsp/notes/entities/rtsp-components.md
  - topics/personal-notes/notes/daily/2026-04-27.md
  - topics/profiling-and-performance/notes/syntheses/2026-05-12_profiling-toolkit-and-roadmap.md
incoming_updated: 2026-05-27
---

# GStreamer

GStreamer is an open-source, plugin-based **multimedia framework** -- a runtime for building media pipelines as graphs of small, hot-swappable processing elements. Where [[ffmpeg-entity|FFmpeg]] is a monolithic binary plus a set of `libav*` libraries that you typically use in a "transcode this file" or "remux that stream" mode, GStreamer is a *streaming* framework first: pipelines are long-lived, composable, observable, and capable of dynamic reconfiguration while running.

It is the dominant framework in surveillance, automotive, broadcast, and embedded video industries, largely because it solves a different problem than [[ffmpeg-entity|FFmpeg]]: it makes media pipelines **a system you build inside your application**, not a subprocess you shell out to.

## Core model

GStreamer's vocabulary is small but precise. See [[gstreamer-pipeline-model]] for the full deep dive; the short version:

- **Element** -- a single processing node (a source, sink, demuxer, decoder, filter, encoder, muxer). Examples: `rtspsrc`, `h264parse`, `avdec_h264`, `videoconvert`, `appsink`, `kvssink`.
- **Pad** -- a typed input or output port on an element. Pads carry **caps** (capabilities -- a content-type description like `video/x-h264, stream-format=byte-stream, alignment=au`).
- **Pipeline** -- the top-level container; a directed graph of linked elements with one shared clock and bus.
- **Bin** -- a composite element that contains other elements and presents itself as one.
- **Bus** -- the asynchronous message channel from elements to the application (errors, EOS, state changes, tags, latency renegotiation).
- **States** -- `NULL`, `READY`, `PAUSED`, `PLAYING`. Transitions are negotiated; failures show up as bus messages.

The result: an application doesn't say "[[ffmpeg-entity|ffmpeg]], transcode this file" -- it instantiates a graph, sets state to `PLAYING`, and listens to the bus. The graph keeps producing data until you tear it down or it errors.

## Plugin landscape

GStreamer's runtime is small; almost all functionality lives in plugins, organized into well-known buckets:

- **gst-plugins-base** -- the foundational set (`videoconvert`, `audioconvert`, `playbin`, etc.).
- **gst-plugins-good** -- LGPL plugins with no licence/quality concerns (`rtspsrc`, `matroskademux`, `jpegenc`, `souphttpsrc`).
- **gst-plugins-bad** -- newer or less-mature plugins (`srtsink`, `webrtcbin`, `nvcodec` family). The "bad" label is about API stability, not code quality.
- **gst-plugins-ugly** -- plugins with potential patent/licence concerns (`x264enc` historically lived here).
- **gst-libav** -- the [[ffmpeg-entity|FFmpeg]]-codec bridge. Exposes nearly every libav* decoder/encoder as a GStreamer element (`avdec_h264`, `avdec_h265`, `avenc_mpeg4`, ...). Critically, this is how GStreamer gets its codec breadth -- it doesn't reimplement [[codecs-overview|codecs]]; it borrows [[ffmpeg-entity|FFmpeg]]'s. See [[ffmpeg-libav-libraries]].
- **NVIDIA's plugin set (nvcodec / [[nvidia-deepstream|DeepStream]])** -- `nvh264dec`, `nvh264enc`, `nvstreammux`, `nvinfer`. See [[nvidia-deepstream]] and [[hardware-accelerated-codecs]].
- **Vendor plugins** -- Intel (`vaapi`/`qsv`), AMD (`amf`), Apple (`vtdec`/`vtenc`), Rockchip, NXP, etc.

The plugin system is what makes GStreamer practical: hardware acceleration is "swap an element name", protocol coverage extends without source changes, and the same pipeline grammar covers [[rtsp-deep-dive|RTSP]] cameras, MP4 files, and [[rtmp-and-srt|SRT]] contribution feeds.

## Bindings

GStreamer is C at its core, with first-class bindings:

- **PyGObject (`gi.repository.Gst`)** -- the Python binding. Idiomatic but verbose; pipelines are usually built as `Gst.parse_launch("...")` strings rather than node-by-node. Mainstream Python use of GStreamer is via this binding (it's what Actuate uses).
- **gstreamer-rs** -- Rust bindings. Mature, idiomatic, and increasingly the preferred binding for new tooling (`gst-plugin-rs` even lets you write plugins in Rust).
- **gst-cs (gstreamer-sharp)** -- C# bindings.
- **JavaScript / Vala / Lua / Perl** -- second-tier but exist.
- **C/C++** -- the canonical path; almost every plugin is written in C.

PyGObject is what we use; `gstreamer-rs` is worth knowing about for high-throughput services where Python's GIL becomes a problem.

## When to reach for GStreamer

GStreamer earns its complexity in three situations:

1. **Protocol coverage breadth.** Need to bridge [[rtsp-deep-dive|RTSP]] in, [[rtmp-and-srt|SRT]] out, with [[webrtc-deep-dive|WebRTC]] fallback? GStreamer is the only mainstream framework that has all three first-class. AWS's [[kvs-components|KVS]] Producer SDK is shipped as a GStreamer plugin (`kvssink`) for the same reason.
2. **Pipeline composability.** When the same code needs to ingest from a file, an [[rtsp-deep-dive|RTSP]] camera, an HTTP [[mjpeg-and-still-image-formats|MJPEG]] feed, and an `appsrc` of bytes from elsewhere in your process -- with the rest of the graph identical -- GStreamer's element/pad model makes this trivial. With [[ffmpeg-entity|FFmpeg]] you'd shell out four different ways.
3. **Hardware acceleration as just another element.** Swapping `avdec_h264` for `nvh264dec` is a one-token change. The pipeline keeps running. With [[ffmpeg-entity|FFmpeg]] you'd be re-tuning command-line flags and likely changing your entire invocation strategy.

You should *not* reach for GStreamer when:

- You're transcoding a single file in batch -- [[ffmpeg-entity|FFmpeg]]'s CLI is shorter and faster to write.
- Your team has zero GStreamer literacy and the use case is one-off -- the learning curve is real (see [[gstreamer-vs-ffmpeg]]).
- You need fine-grained control over codec parameters -- libav* directly (via [[pyav-entity|PyAV]]) gives you that without the pipeline overhead.

Why surveillance / automotive lean on it: long-lived multi-stream pipelines with hot-swap requirements. Verkada-class systems and automotive ADAS stacks both run GStreamer-based pipelines in production.

## Gotchas / hard-earned lessons

- **State changes are async.** Setting state to `PLAYING` returns immediately; the actual transition happens on the bus. New users routinely write code that races the state change.
- **Caps negotiation is opaque until it fails.** When two elements can't agree on caps, you get a bus error with a frustratingly generic message. `GST_DEBUG=3` is mandatory for diagnosis.
- **`gst-libav` is a soft dep on [[ffmpeg-entity|FFmpeg]].** Without it you have very few decoders -- pipelines that "should work" silently fail until you `apt-get install gstreamer1.0-libav`.
- **Plugin discovery is filesystem-driven.** A pipeline can fail because a plugin package isn't installed, with an error that just says "no element 'rtspsrc'". Always confirm the plugin set baked into your container.
- **PyGObject's GIL interaction.** Long-running pipelines in Python release the GIL inside C code (good), but `appsink` callbacks reacquire it (potentially bad under high frame rate).

## Actuate uses

Two paths in `actuate-pullers`, both PyGObject-based:

1. **[[kvs-components|KVS]] ingestion path** -- `actuate-libraries/actuate-pullers/src/actuate_pullers/kvs/kvs_ingestor.py` (lines 50-335) builds the pipeline `appsrc ! matroskademux ! decodebin ! videoconvert ! jpegenc ! appsink` (line 148-156). Bytes from `boto3.client("kinesisvideo").get_media()` are pushed into `appsrc`; JPEGs come out of `appsink` and are then `cv2.imdecode`d in Python (line 119). This is currently the only way we ingest [[kvs-components|KVS]] streams. Note the **decode→encode→decode round-trip** -- GStreamer decodes the stream, re-encodes to JPEG, then Python decodes the JPEG to numpy. Two unnecessary codec ops per frame; an optimization candidate that should target raw `appsink` with `videoconvert` to BGR.

2. **Legacy GStreamer-based [[rtsp-deep-dive|RTSP]] path** -- `actuate-libraries/actuate-pullers/src/actuate_pullers/url/gst_url_puller.py` and `gstreamer/gstreamer_input_pipeline.py:86-101` define the [[rtsp-deep-dive|RTSP]] pipeline as `rtspsrc ! rtph264depay ! h264parse ! avdec_h264 ! videorate ! videoconvert ! jpegenc ! appsink`. **Hardcoded [[h264-deep-dive|H.264]]** -- [[h265-hevc-deep-dive|H.265]] [[rtsp-deep-dive|RTSP]] cameras silently fail through this puller. The [[pyav-entity|PyAV]]-based path (`AvUrlFramePuller`) is the default; this GStreamer puller is opt-in.

Both pullers are wrapped in `try/except ImportError` blocks in `actuate_pullers/__init__.py` (lines 1-56) so the library still loads on machines without PyGObject + GStreamer plugins. `actuate-pullers/pyproject.toml:16` pins `pygobject==3.50.0`. The runtime container must include `gstreamer1.0-libav`, `gstreamer1.0-plugins-base`, `-good`, and `-bad` (matroska, [[rtsp-deep-dive|rtsp]], souphttpsrc plugins specifically). The exact Dockerfile location should be verified -- TODO.

## Related notes

- [[gstreamer-pipeline-model]] -- the model and grammar in detail
- [[gstreamer-vs-ffmpeg]] -- decision matrix
- [[nvidia-deepstream]] -- the GPU-accelerated GStreamer reference architecture
- [[ffmpeg-entity]], [[ffmpeg-libav-libraries]] -- the codec foundation GStreamer borrows
- [[hardware-accelerated-codecs]] -- where the `nvcodec` / `vaapi` / `vtdec` plugins fit
- [[rtsp-deep-dive]] -- the protocol `rtspsrc` implements
- [[aws-kvs-entity]] -- consumer of the GStreamer [[kvs-components|KVS]] path
- Reading list: [[reading-list]] -- MediaMTX, GO2RTC, Live555, Janus, gst-[[rtsp-deep-dive|rtsp]]-server are the GStreamer-adjacent tools worth knowing

## Cross-topic

- [[vms-connector/_summary]] -- primary consumer of `actuate-pullers`
- [[actuate-libraries/_summary]] -- where the GStreamer-using code lives
- [[fleet-architecture/_summary]] -- frame-transport context

## Actuate touchpoints

- **`actuate-pullers/kvs/kvs_ingestor.py`** -- the only currently-active GStreamer pipeline in production.
- **`actuate-pullers/url/gst_url_puller.py`** -- legacy GStreamer [[rtsp-deep-dive|RTSP]] path. [[h264-deep-dive|H.264]]-only; flagged for either deprecation or codec generalization.
- **`actuate-pullers/__init__.py`** -- `ImportError` guards make GStreamer optional; runtime image gating is the real availability switch.
- **Container build** -- the connector runtime image must ship the GStreamer plugin set or `kvssink`/`rtspsrc`/`matroskademux` will silently be missing. Worth a Dockerfile audit pass.
- **No NR instrumentation** -- GStreamer pipeline errors surface only via PyGObject bus messages; we don't currently turn those into structured logs. Connector logging captures the error string but not the element / state / caps detail that diagnosis needs.
