---
title: "Actuate Frame Ingest & Decode Paths (per-VMS)"
type: synthesis
topic: video-processing
tags: [actuate, decode, puller, integration, rtsp, kvs, websocket, mjpeg, autopatrol]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
---

# Actuate Frame Ingest & Decode Paths

A per-VMS map of how Actuate turns "the customer's camera feed" into a numpy frame the inference pipeline can consume. There are far more decode paths than the architecture diagrams in Confluence imply. **Two parallel decoder substrates ([[pyav-entity|PyAV]]-based and [[opencv-entity|OpenCV]]-based) co-exist** and that migration debt shapes everything else in this synthesis.

This is the per-stage zoom-in on Stage 3 of [[actuate-video-pipeline-walkthrough]].

## The fan-out point

`vms-connector/connector_factories/shared/factory.py:60-107` -- `generate_site()` switches on `integration_type` to pick a puller class. From here on the decode strategy diverges per integration. Every claim in the table below resolves through this factory.

The puller registry that the factory reaches for: `actuate-libraries/actuate-pullers/src/actuate_pullers/__init__.py:1-56`. Note the `try/except ImportError` blocks -- `GstUrlFramePuller`, `KVSFramePuller`, and `AvUrlFramePuller` are conditionally available depending on whether [[gstreamer-entity|GStreamer]] or [[pyav-entity|PyAV]] are installed in the runtime image. **The Dockerfile contents are the source of truth for which decoders are actually present in production.** Scout pass did not locate the connector Dockerfile; flag for verification.

## The puller / decode table

| integration_type (rough) | Puller class | Transport | Container | Decode substrate |
|---|---|---|---|---|
| [[rtsp-deep-dive|RTSP]] (modern, default) | `AvUrlFramePuller` | [[rtsp-deep-dive|RTSP]]/TCP forced | [[h264-deep-dive|H.264]], [[h265-hevc-deep-dive|H.265]], [[mjpeg-and-still-image-formats|MJPEG]] raw | **[[pyav-entity|PyAV]] / libav** |
| [[rtsp-deep-dive|RTSP]] (legacy / motion-gated) | `UrlFramePuller`, `UrlFramePullerMotion` | [[rtsp-deep-dive|RTSP]] via [[opencv-entity|cv2]] [[ffmpeg-entity|ffmpeg]] | [[h264-deep-dive|H.264]] mostly | **[[opencv-entity|OpenCV]] `cv2.VideoCapture`** |
| [[rtsp-deep-dive|RTSP]] ([[gstreamer-entity|GStreamer]] fallback) | `GstUrlFramePuller` | [[rtsp-deep-dive|RTSP]] | **[[h264-deep-dive|H.264]] only** | [[gstreamer-entity|GStreamer]] `rtspsrc → rtph264depay → avdec_h264` |
| [[kvs-components|KVS]] | `KVSFramePuller` | [[kvs-components|KVS]] GetMedia (HTTPS) | MKV chunks | [[gstreamer-entity|GStreamer]] `matroskademux → decodebin → jpegenc → appsink` then `cv2.imdecode` |
| AutoPatrol / VCH | `AutopatrolWebsocketStreamPuller` | WebSocket binary | fMP4 (manual ISO-BMFF parse) | [[pyav-entity|PyAV]] per fragment |
| Milestone (proprietary) | `MilestoneJpgFramePuller` | Raw TCP socket (optional TLS) | Per-frame JPEG | TurboJPEG / `cv2.imdecode` |
| Orchid | `OrchidJpgQueuePuller` | HTTP polling | Per-frame JPEG | TurboJPEG / `cv2.imdecode` |
| Generic JPEG poll | `JpgFrameQueuePuller` | HTTP polling | Per-frame JPEG | TurboJPEG / `cv2.imdecode` |
| SQS-Video | `SqsPuller` | SQS message → S3 download | MP4 / image | `cv2.VideoCapture(local_file)` |
| SMTP-per-camera (legacy) | `VideoQueuePuller` | SMTP attachment → S3 | MP4 / image | `cv2.VideoCapture` |
| Gauntlet / robomladen | `S3Puller` | S3 list / fetch | MP4 / clip | `cv2.VideoCapture(clip)` |
| External pipeline (Unix socket) | `SocketPuller` | `AF_UNIX SOCK_STREAM` | Per-frame raw or named-pipe | direct numpy or `cv2.VideoCapture` against named pipe |
| Buffered named-pipe | `BufferPuller` | Named pipe FIFO | Raw frames | direct numpy |
| Pure passthrough | `QueuePuller` | In-process Queue | numpy frames | none (no decode) |
| Local dev | `WebcamFramePuller` | `/dev/video0` | YUYV/[[mjpeg-and-still-image-formats|MJPEG]] | `cv2.VideoCapture(0)` |

(Integration_type → puller mapping is in `vms-connector/connector_factories/shared/factory.py`; this table consolidates the puller behaviour itself, not the routing.)

## The two decoder paths and the migration debt

We have **two parallel [[rtsp-deep-dive|RTSP]] decoder paths** in production:

- `actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py:320-1438` -- [[pyav-entity|PyAV]].
- `actuate-libraries/actuate-pullers/src/actuate_pullers/url/url_puller.py:17-395` -- [[opencv-entity|OpenCV]] `cv2.VideoCapture`.

The migration from [[opencv-entity|OpenCV]] to [[pyav-entity|PyAV]] is **incomplete**. The factory still routes a meaningful share of integration_types to `UrlFramePuller`, including the motion-gated variant (`actuate-libraries/actuate-pullers/src/actuate_pullers/url/url_puller_motion.py:20-100+`) for `openeye` and `milestone_rtsp`. The migration debt isn't just "two libraries" -- the two paths have different behaviour:

- Different [[rtsp-deep-dive|RTSP]] transport handling. [[pyav-entity|PyAV]] path forces TCP at `av_url_puller.py:412-494`. [[opencv-entity|OpenCV]] path sets `OPENCV_FFMPEG_CAPTURE_OPTIONS=rtsp_transport;tcp` only for `omniaweb` / `eagleeyenetworks` URLs (`url_puller.py:314, 318`).
- Different codec coverage. [[pyav-entity|PyAV]] decodes [[h265-hevc-deep-dive|H.265]]/[[h265-hevc-deep-dive|HEVC]] correctly with an explicit performance warning at `av_url_puller.py:910-913`. [[opencv-entity|OpenCV]]'s [[h265-hevc-deep-dive|H.265]] support depends on its [[ffmpeg-entity|FFmpeg]] build and is less predictable.
- Different reconnect / failure semantics. The [[opencv-entity|OpenCV]] path has a hack to rewrite URLs with `videocodec=h264&` on connection failure (`url_puller.py:150-151, 1121-1122`); the [[pyav-entity|PyAV]] path doesn't need it.
- Different rotation / sidedata handling. [[pyav-entity|PyAV]] reads MP4 display matrix and applies `cv2.rotate` (`av_url_puller.py:139-171`); [[opencv-entity|OpenCV]] silently ignores rotation metadata.
- Different memory profile. PyAV detects fMP4 and recycles the demuxer every ~5 minutes (`av_url_puller.py:496-503, 1158-1185`) to flush the libavformat `mov` demuxer's `frag_index` (~5-10 MB/hr leak on Avigilon streams). OpenCV's wrapper of the same libavformat doesn't expose this.

Operationally this means: **the same camera, on two slightly different integration_types, can hit either decoder path, and behave differently.** Worth a tracked epic to finish the migration.

See [[opencv-entity]], [[cv2-videocapture-internals]], [[pyav-entity]] for why the two paths exist at all.

## [[pyav-entity|PyAV]] path -- the canonical decoder, in depth

`av_url_puller.py:1276-1404` is the main demux+decode loop. Key features:

- **`AVDiscard` adaptive frame skipping** (line 617-753). Measures keyframe rate over 10s; if `keyframe_fps >= target * 1.5`, sets `codec_context.skip_frame = "NONKEY"`. Re-evaluates every 5 minutes. Starvation detection (line 668-679) falls back to `DEFAULT`. This is our primary CPU lever for high-bitrate streams. See [[gop-keyframe-fundamentals]] for why this works.
- **`TimestampTracker`** (line 174-317). PTS extraction with DTS fallback, discontinuity detection, [[rtsp-deep-dive|RTSP]] buffer-burst drift correction (Milestone bridge specific at line 286-294 -- the only place we have integration-specific PTS correction), wall-clock anchoring. Necessary because real cameras lie about timestamps constantly.
- **HW decoder table** at line 24-77. [[h264-deep-dive|h264]], hevc, mjpeg, mpeg2/4, vp8/9, av1, vc1, prores × cuda / videotoolbox / vaapi / amf / mediacodec / v4l2m2m. See [[hardware-accelerated-codecs]].
- **Hardware acceleration detection** at line 527-607 -- shells out to `nvidia-smi -L`, `ffmpeg -hide_banner -hwaccels`, `lspci` (each timeout=5s). Priority: macOS [[hardware-accelerated-codecs|VideoToolbox]] → NVIDIA CUDA → Intel [[hardware-accelerated-codecs|VAAPI]] → AMD AMF.
- **Per-hwaccel options dict** at line 412-494. [[rtsp-deep-dive|RTSP]] low-latency tuning (`probesize=128KB`, `analyzeduration=300ms`, `fflags=discardcorrupt`), [[hardware-accelerated-codecs|VAAPI]] device path (`hwaccel_device=/dev/dri/renderD128`), forced TCP transport.
- **`hwaccel_output_format` deliberately not set** (line 454-456, 432-434). Comment says GPU-memory frames break `frame.to_ndarray()`. So even when we hardware-decode, the frame round-trips through CPU memory. This is on the table for optimization in [[actuate-build-vs-buy-tradeoffs]].
- **fMP4 handling** at line 496-503, 1158-1185. Detects "mov"/"mp4" in `container.format.name`, sets `_is_fmp4=True`, schedules 300s+jitter recycle. Without this, Avigilon streams OOM.

Strong substrate. The [[pyav-entity|PyAV]] path is well-engineered.

## [[gstreamer-entity|GStreamer]] [[rtsp-deep-dive|RTSP]] path -- the silent [[h265-hevc-deep-dive|H.265]] trap

`actuate-libraries/actuate-pullers/src/actuate_pullers/gstreamer/gst_url_puller.py:11-62` and the pipeline at `actuate-libraries/actuate-pullers/src/actuate_pullers/gstreamer/gstreamer_input_pipeline.py:86-101`:

```
rtspsrc ! rtph264depay ! h264parse ! avdec_h264 ! videorate ! videoconvert ! jpegenc ! appsink
```

**Hardcoded [[h264-deep-dive|H.264]].** If the camera negotiates [[h265-hevc-deep-dive|H.265]] ([[h265-hevc-deep-dive|HEVC]]) the `rtph264depay` element will refuse to handle the stream and the pipeline will silently fail to produce frames. There's no caps negotiation, no fallback to `rtph265depay`. **Worth flagging in any "why is this customer's camera not producing frames" investigation.**

This path is the GStreamer-only fallback; most integrations now route to `AvUrlFramePuller`. But any integration that still uses `GstUrlFramePuller` gates customers out of [[h265-hevc-deep-dive|H.265]] silently. See [[gstreamer-entity]], [[gstreamer-pipeline-model]].

Fix is one-line: add `! rtph265depay ! h265parse ! avdec_h265 ! ...` as a fallback caps branch, or use `decodebin` instead of the explicit chain. But it's been in place a while and any change needs careful regression testing across cameras that already work.

## KVS path -- the JPEG round-trip

`actuate-libraries/actuate-pullers/src/actuate_pullers/kvs/kvs_puller.py:9-47` + `kvs_ingestor.py:50-335`:

1. `boto3.client("kinesisvideo")` resolves data endpoints, then `boto3.client("kinesis-video-media").get_media()` opens a streaming GET (`kvs_ingestor.py:82-98, 270-273`).
2. The MKV byte chunks are pushed into a [[gstreamer-entity|GStreamer]] `appsrc` pipeline at `kvs_ingestor.py:148-156`:

   ```
   appsrc → matroskademux → decodebin → videoconvert → jpegenc → appsink
   ```

3. The `appsink` pulls JPEG-encoded buffers and the Python side decodes them back to numpy via `cv2.imdecode` at `kvs_ingestor.py:119`.

The pipeline **encodes JPEG inside [[gstreamer-entity|GStreamer]] then immediately decodes it back to numpy in Python**. Two unnecessary codec ops per frame:

- GPU/CPU work for JPEG encode (likely software).
- CPU work for `cv2.imdecode`.

Flagged in [[actuate-build-vs-buy-tradeoffs]] as an optimization candidate. The cleaner pipeline would terminate at `appsink` with `caps="video/x-raw,format=BGR"` and skip the `jpegenc` element entirely; or move [[kvs-components|KVS]] onto the [[pyav-entity|PyAV]] substrate ([[kvs-components|KVS]] streams are MKV with [[h264-deep-dive|H.264]]/[[h265-hevc-deep-dive|H.265]] inside, which [[pyav-entity|PyAV]] can demux directly if we feed it the byte stream).

See [[aws-kvs-entity]], [[gstreamer-entity]].

## AutoPatrol WebSocket path -- handcrafted ISO-BMFF parsing

`actuate-libraries/actuate-pullers/src/actuate_pullers/socket/autopatrol_websocket_stream_puller.py:43-300+` is one of the more interesting pullers. The Immix VCH bridge for AutoPatrol streams **fragmented MP4 (fMP4) over WebSocket binary frames**.

The puller has to walk the byte stream and find fragment boundaries:

- `extract_next_fragment` at line 111-135 -- byte-by-byte ISO-BMFF box-header parsing. Recognises `ftyp`, `moov`, `moof`, `mdat`, `styp`, `sidx` boxes by length-prefixed tag.
- Once a complete `moof + mdat` pair is assembled into a buffer, it's passed to `av.open(io.BytesIO(combined), format="mp4", mode="r")` (line 194-275) and decoded with `container.decode(video=0)`.

This works because each fMP4 fragment is a self-describing standalone unit (fragment-MOOV inheritance from the init-MOOV is what lets [[pyav-entity|PyAV]] decode without seeing the original `moov`).

Why this design? AutoPatrol is patrol-mode: discrete frame snapshots driven by Immix VCH at low cadence. WebSocket is the only transport Immix exposes. fMP4 is what comes out. We could conceivably let [[pyav-entity|PyAV]] demux the WebSocket stream directly with a custom `AvIOContext` ([[pyav-entity|PyAV]] supports this) but the manual byte-walker is simpler to reason about.

See [[autopatrol/_summary]], [[mjpeg-and-still-image-formats]] for the still-image patrol latency model, and the [[ffmpeg-libav-libraries]] note on `AvIOContext`.

## JPEG-snapshot pullers (Milestone, Orchid, generic)

For VMSs that expose a "give me a JPEG" endpoint, decode is trivial: TurboJPEG → numpy or `cv2.imdecode` → numpy. The `actuate-libraries/actuate-image-cache/src/actuate_image_cache/_decode.py:15-29` helper covers the TurboJPEG path with `cv2.imdecode` fallback.

The interesting work in these pullers is *transport*, not decode:

- **Milestone** (`actuate-libraries/actuate-pullers/src/actuate_pullers/milestone/milestone_jpg_frame_puller.py:25-80+`) -- proprietary protocol over raw TCP socket, optionally TLS via `connect_with_optional_tls`. Custom framing.
- **Orchid** (`actuate-libraries/actuate-pullers/src/actuate_pullers/orchid/orchid_jpg_queue_puller.py:11-80+`) -- HTTP polling at `/service/low-bandwidth/streams` with desired FPS/resolution.
- **Generic JPEG poll** (`actuate-libraries/actuate-pullers/src/actuate_pullers/jpg/jpg_frame_queue_puller.py:14-80+`) -- motion-gated HTTP snapshot polling.

See [[mjpeg-and-still-image-formats]] for why JPEG-poll is its own thing distinct from streaming [[mjpeg-and-still-image-formats|MJPEG]].

## SQS-Video and S3 batch -- "decode at rest"

These pullers operate on already-encoded clips on S3, not live streams.

- **SQS-Video** (`actuate-libraries/actuate-pullers/src/actuate_pullers/sqs/sqs_puller.py:13-99`) -- polls a per-camera FIFO queue. Message body is an S3 key. `s3_dao.s3_client.download_file(...)` downloads to local disk (line 53). Branches: still image → `cv2.imread`; video clip → `cv2.VideoCapture(local_filename)` + frame-by-frame `cap.read()`.
- **S3 batch** (`actuate-libraries/actuate-pullers/src/actuate_pullers/s3/s3_puller.py:13-80+`) -- gauntlet/robomladen pipeline. Lists S3 files, opens each with `cv2.VideoCapture(clip)`.

These are the **only places we use `cv2.VideoCapture` on a local file** (vs. an [[rtsp-deep-dive|RTSP]] URL). Quirks of `VideoCapture` on file paths are documented in [[cv2-videocapture-internals]].

## fish2pano -- the unbounded subprocess

`actuate-libraries/actuate-pullers/src/actuate_pullers/shared/base_puller.py:333-339` runs `subprocess.run([self.lib_path] + shlex.split(camera.panorama_parameters) + [input_path], check=True)` for fisheye-to-panorama unwarp via a bundled `fish2pano` C binary. **No `timeout` parameter.** Hang risk. The path is low-volume (fisheye cameras only) but the lack of timeout is worth fixing the next time someone touches that file.

Related: `actuate-libraries/actuate-image-manipulation/src/actuate_image_manipulation/dewarp.py:1-40` uses `ctypes.CDLL` to load `dewarp.*.so` directly.

## Things to flag in any future investigation

1. **[[gstreamer-entity|GStreamer]] [[rtsp-deep-dive|RTSP]] path is [[h264-deep-dive|H.264]]-only** (`gstreamer_input_pipeline.py:90`). [[h265-hevc-deep-dive|H.265]]/[[h265-hevc-deep-dive|HEVC]] [[rtsp-deep-dive|RTSP]] via [[gstreamer-entity|GST]] silently fails. [[pyav-entity|PyAV]] path covers [[h265-hevc-deep-dive|H.265]] properly.
2. **[[kvs-components|KVS]] pipeline re-encodes JPEG in [[gstreamer-entity|GStreamer]] then re-decodes in Python.** Two unnecessary codec ops per frame. Optimization candidate.
3. **fish2pano subprocess has no timeout.** Hang risk (low-volume path).
4. **Two parallel decoder paths ([[pyav-entity|PyAV]] vs [[opencv-entity|OpenCV]]) co-exist.** Migration to [[pyav-entity|PyAV]] is incomplete; behaviours differ subtly across the two paths.
5. **`hwaccel_output_format` deliberately not set** -- even hardware-decoded frames round-trip through CPU memory because GPU-memory frames break `frame.to_ndarray()`. Worth investigating with a zero-copy NVIDIA path.
6. **PTS handling drift correction** at `av_url_puller.py:286-294` is Milestone-bridge-specific. If we hit similar drift on another integration we'd need to factor that out.
7. **Connector Dockerfile location not confirmed in scout pass.** Verify apt deps for [[ffmpeg-entity|ffmpeg]], [[gstreamer-entity|gstreamer]] plugins, libnvidia-decode, libturbojpeg.

## Cross-references

- End-to-end pipeline context -- [[actuate-video-pipeline-walkthrough]]
- What happens *after* the frame leaves the puller -- [[actuate-clip-generation-flow]]
- Where managed services could replace homegrown decode -- [[actuate-build-vs-buy-tradeoffs]]
- Library positioning -- [[ffmpeg-entity]], [[gstreamer-entity]], [[opencv-entity]], [[pyav-entity]], [[aws-kvs-entity]]
- Codec deep-dives -- [[h264-deep-dive]], [[h265-hevc-deep-dive]], [[mjpeg-and-still-image-formats]], [[hardware-accelerated-codecs]], [[gop-keyframe-fundamentals]]
- Transport protocols -- [[rtsp-deep-dive]], [[mpeg-ts-over-udp]], [[protocol-latency-comparison]]
- Topic landing -- [[reading-list]]
- Cross-topic -- [[vms-connector/_summary]], [[actuate-libraries/_summary]], [[integrations/kvs/_summary]], [[integrations/rtsp/_summary]], [[autopatrol/_summary]]
