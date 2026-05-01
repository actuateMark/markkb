---
title: GStreamer Pipeline Model
type: concept
topic: video-processing
tags: [gstreamer, pipeline, elements, pads, caps, bus, states, appsrc, appsink]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/video-processing/_summary.md
  - topics/video-processing/notes/concepts/ffmpeg-filtergraphs.md
  - topics/video-processing/notes/concepts/gst-rtsp-h264-only-audit.md
  - topics/video-processing/notes/concepts/gstreamer-vs-ffmpeg.md
  - topics/video-processing/notes/concepts/nvidia-deepstream.md
  - topics/video-processing/notes/entities/gstreamer-entity.md
  - topics/video-processing/notes/syntheses/actuate-build-vs-buy-tradeoffs.md
  - topics/video-processing/notes/syntheses/actuate-frame-ingest-decode-paths.md
incoming_updated: 2026-05-01
---

# [[gstreamer-entity|GStreamer]] Pipeline Model

[[gstreamer-entity|GStreamer]] pipelines are **directed acyclic graphs of small typed processing nodes** with strict capability negotiation between them. The mental model is closer to a Unix shell pipe than to an [[ffmpeg-entity|FFmpeg]] command line: data flows from sources through filters to sinks, each link carries a typed contract, and the whole graph runs under a shared clock and a shared async message bus.

This note is the structural reference for [[gstreamer-entity]] and the prerequisite for understanding [[nvidia-deepstream]], [[gstreamer-vs-ffmpeg]], and the Actuate [[kvs-components|KVS]] / [[rtsp-deep-dive|RTSP]] pipelines.

## The five primitives

### 1. Elements

An **element** is a single processing unit with a well-defined role:

- **Sources** -- produce data (`filesrc`, `rtspsrc`, `souphttpsrc`, `appsrc`, `v4l2src`, `kvssink`-counterpart, ...).
- **Sinks** -- consume data (`filesink`, `appsink`, `autovideosink`, `kvssink`, `srtsink`, ...).
- **Filters / transforms** -- 1-in / 1-out (`videoconvert`, `videorate`, `videoscale`, `queue`, `capsfilter`).
- **Demuxers / muxers** -- 1-in / N-out and N-in / 1-out (`matroskademux`, `mp4mux`, `tsdemux`).
- **Encoders / decoders / parsers** -- `avdec_h264`, `x264enc`, `h264parse`, `jpegenc`, `nvh265dec`.

Elements come from plugins; `gst-inspect-1.0 <element>` prints the full schema (pads, caps, properties, signals).

### 2. Pads

A **pad** is a typed port -- the only place data crosses element boundaries. Two attributes matter:

- **Direction**: `src` (output) or `sink` (input). Confusingly, "src" is *output* -- think "source of data", not "source code".
- **Availability**:
  - **Always** -- the pad exists for the lifetime of the element.
  - **Sometimes** -- appears only after the element learns enough about the stream (canonical example: `decodebin` doesn't know it has a video pad until it has parsed the container).
  - **Request** -- created on demand by the application (`tee`'s output pads, `nvstreammux`'s sink pads).

Sometimes-pads are why pipeline construction in code is async: you instantiate `decodebin`, set state to `PAUSED`, and then connect a `pad-added` signal handler that links the new pad once it appears. This is the single most common stumbling block for new [[gstreamer-entity|GStreamer]] users.

### 3. Caps (capabilities)

**Caps** are typed media descriptors -- effectively MIME types with structured fields. Examples:

- `video/x-h264, stream-format=byte-stream, alignment=au, profile=high`
- `video/x-raw, format=I420, width=1920, height=1080, framerate=30/1`
- `image/jpeg, width=1280, height=720, framerate=10/1`

Every pad declares the caps it can produce or accept. When two pads link, [[gstreamer-entity|GStreamer]] runs **caps negotiation**: it computes the intersection of the producer's possible output caps and the consumer's accepted input caps, picks one, and locks it. If the intersection is empty, the link fails -- often with a "could not link" error that you have to debug with `GST_DEBUG=3 gst-launch-1.0 ...`.

You can pin caps explicitly with a `capsfilter` element or with the `! caps !` shorthand in pipeline syntax: `videoconvert ! video/x-raw,format=BGR ! appsink`.

### 4. Bus and messages

The **bus** is an async one-way channel from elements to the application. Element-to-element communication is via buffers on pads; element-to-app communication is via bus messages. Common message types:

- `ERROR` -- an element failed (caps negotiation, file not found, network error). Carries an element reference and a `GError`.
- `EOS` -- end of stream; once seen, the pipeline should be torn down.
- `STATE_CHANGED` -- async confirmation that a state transition completed.
- `TAG` -- metadata (artist, codec, bitrate, ...).
- `WARNING` / `INFO` -- non-fatal.
- `LATENCY` -- an element renegotiated its latency contribution.
- `QOS` -- a sink dropped a buffer; useful for diagnosing real-time failure.

In Python: `pipeline.get_bus().connect("message", handler)` or `bus.poll(...)` in a loop.

### 5. States

A pipeline (and every element) has four states:

- **NULL** -- not initialized. Resources released.
- **READY** -- resources allocated, but no data flow.
- **PAUSED** -- data flowing through pre-roll, but the clock is paused. Demuxers have parsed enough to expose pads.
- **PLAYING** -- the clock is running; data is flowing in real time.

State changes propagate up- or downstream depending on element role and **return one of `SUCCESS`, `ASYNC`, `NO_PREROLL`, `FAILURE`**. Most live sources return `NO_PREROLL` -- the source has no buffered data to pre-roll, so PAUSED isn't a meaningful "buffered" state. This matters for pipeline construction: dynamic linking of `decodebin`'s sometimes-pads requires the pipeline to first reach PAUSED.

## Pipeline syntax (`gst-launch-1.0`)

`gst-launch-1.0` is the CLI runner for ad-hoc pipelines. Its grammar is the same one `Gst.parse_launch(...)` accepts in code:

```
element1 [property=value ...] ! element2 [property=value ...] ! element3
```

- `!` is the link operator (mnemonic: "shove").
- `name=foo` gives an element a name for later reference.
- Branches: `element1 ! tee name=t   t. ! queue ! sink1   t. ! queue ! sink2`.
- Caps as inline filters: `! video/x-raw,format=I420,width=1280 !`.
- Bins: `( element1 ! element2 )` groups into an inline bin.

This grammar is the same on the CLI and in code -- you almost never build pipelines node-by-node in Python because `parse_launch` is faster to write, easier to copy from a working `gst-launch-1.0` invocation, and identical in capability for 95% of cases.

## Bins

A **bin** is a composite element -- it contains other elements but presents itself with its own pads. Two practical uses:

- **Encapsulation.** Build a "demux + decode + colour convert" sub-pipeline once, expose it as a bin with one sink pad and one src pad.
- **Pre-built bins.** `decodebin` is a bin that auto-discovers the right demuxer + parser + decoder for any input. `playbin` is a higher-level bin that does the same plus output. `uridecodebin` adds URI handling. These are the "I just want frames out, figure out the codec" path.

`Gst.Pipeline` itself is a bin (the top-level one).

## Common building blocks (the "20 elements that solve 80% of cases")

| Element | Role |
|---------|------|
| `rtspsrc` | [[rtsp-deep-dive|RTSP]] client. Negotiates session, opens RTP. |
| `rtph264depay`, `rtph265depay` | Strip RTP framing to leave NAL units. |
| `h264parse`, `h265parse` | Repackage / fix up NALs to a sane stream-format. |
| `avdec_h264`, `avdec_h265` | Software decode via `gst-libav` ([[ffmpeg-entity|FFmpeg]]). |
| `nvh264dec`, `nvh265dec` | NVIDIA hardware decode. See [[hardware-accelerated-codecs]]. |
| `vaapih264dec` | Intel/AMD hardware decode on Linux. |
| `videoconvert` | Format conversion (e.g. NV12 → BGR). |
| `videorate` | Frame-rate conversion (drop / duplicate). |
| `videoscale` | Resolution conversion. |
| `queue` | Buffer + thread boundary; almost mandatory between async paths. |
| `tee` | Fan out (request pads). |
| `jpegenc` / `jpegdec` | [[mjpeg-and-still-image-formats|MJPEG]]. See [[mjpeg-and-still-image-formats]]. |
| `matroskademux` / `qtdemux` / `tsdemux` | Container parsers. |
| `appsrc` / `appsink` | Application bridges -- push bytes in / pull buffers out. |
| `souphttpsrc` | HTTP source. |
| `kvssink` | [[aws-kvs-entity|AWS KVS]] producer. See [[aws-kvs-entity]]. |
| `srtsink` / `srtsrc` | [[rtmp-and-srt|SRT]] transport. |

## `appsrc` / `appsink`: the application bridge

The two elements that make [[gstreamer-entity|GStreamer]] pipelines composable with arbitrary application code:

- **`appsrc`** -- accepts buffers from the application via `push-buffer` (or a "need-data" callback). The pipeline thinks it's reading from a normal source. *This is exactly how Actuate's [[kvs-components|KVS]] path works*: `boto3.client("kinesisvideo").get_media()` returns a streaming MKV body; bytes are read in Python and pushed into `appsrc`, which feeds `matroskademux ! decodebin ! ...` downstream. Without `appsrc`, you'd need a GStreamer-native [[kvs-components|KVS]] source plugin (which exists for the *producer* side as `kvssink`, but not for the consumer side).
- **`appsink`** -- delivers buffers out to the application via a `new-sample` callback or pull API. Used at the end of every Actuate [[gstreamer-entity|GStreamer]] pipeline because we ultimately want bytes/numpy arrays inside Python, not on a screen.

The `appsrc → process Python bytes → matroskademux` shape is [[gstreamer-entity|GStreamer]]'s primary integration mode for non-trivial applications.

## Common gotchas

- **`queue` placement.** Without `queue`, the entire pipeline runs on one thread. With `queue`, each `queue` introduces a thread boundary. Live pipelines ([[rtsp-deep-dive|RTSP]], [[kvs-components|KVS]]) almost always need at least one `queue` after the source to avoid blocking.
- **Caps re-negotiation mid-stream.** Some cameras change resolution. Elements downstream may not handle this gracefully; `videoconvert ! videoscale` is sometimes needed defensively.
- **`avdec_*` requires `gst-libav`.** Without that package installed, the only decoders available are whatever the platform-specific plugin sets provide.
- **`appsink` blocking.** Default behaviour is to block when no consumer pulls. Set `drop=true max-buffers=1` for "give me the latest, drop the rest" semantics -- this is what you want for live preview, *not* for ML ingest where dropped frames matter.

## Related notes

- [[gstreamer-entity]] -- the framework overview
- [[gstreamer-vs-ffmpeg]] -- decision matrix
- [[nvidia-deepstream]] -- pipelines extended with `nvstreammux` / `nvinfer`
- [[ffmpeg-libav-libraries]] -- what powers `avdec_*` / `avenc_*`
- [[rtsp-deep-dive]], [[hardware-accelerated-codecs]], [[mjpeg-and-still-image-formats]]
- [[actuate-frame-ingest-decode-paths]], [[actuate-video-pipeline-walkthrough]]

## Cross-topic

- [[vms-connector/_summary]], [[actuate-libraries/_summary]]

## Actuate touchpoints

- **[[kvs-components|KVS]] ingestion** -- `actuate-libraries/actuate-pullers/src/actuate_pullers/kvs/kvs_ingestor.py:148-156` builds `appsrc ! matroskademux ! decodebin ! videoconvert ! jpegenc ! appsink`. Bytes from `boto3` GetMedia are pushed into `appsrc` (lines 270-273); `appsink`'s `new-sample` callback delivers JPEG buffers, which are then `cv2.imdecode`d (line 119). The decode→jpegenc→imdecode round-trip is wasteful: a `videoconvert ! video/x-raw,format=BGR ! appsink` tail would skip both extra codec ops.
- **Legacy [[rtsp-deep-dive|RTSP]]** -- `actuate-libraries/actuate-pullers/src/actuate_pullers/gstreamer/gstreamer_input_pipeline.py:86-101` hardcodes `rtspsrc ! rtph264depay ! h264parse ! avdec_h264 ! videorate ! videoconvert ! jpegenc ! appsink`. The `rtph264depay` + `avdec_h264` pinning means [[h265-hevc-deep-dive|H.265]] [[rtsp-deep-dive|RTSP]] feeds silently fail through this path. Replacing with `rtspsrc ! rtpjitterbuffer ! parsebin ! decodebin ! videoconvert ! ...` would auto-handle codec.
- **No `queue` between `appsrc` and `matroskademux`** in the [[kvs-components|KVS]] path -- worth checking whether HTTP read latency stalls demux.
- **`drop=true max-buffers=1` semantics** -- not currently used; the `appsink` defaults mean buffer accumulation under back-pressure. Worth profiling under load.
