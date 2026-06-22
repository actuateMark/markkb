---
title: "OpenCV"
type: entity
topic: video-processing
tags: [opencv, cv2, video, image-processing, frame-decode, library]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/actuate-libraries/notes/concepts/2026-05-19_pyav17-ffmpeg8-migration.md
  - topics/actuate-libraries/notes/concepts/dependency-graph.md
  - topics/actuate-libraries/notes/concepts/image-cache-strategies.md
  - topics/actuate-libraries/notes/entities/actuate-classic-inference-client.md
  - topics/actuate-libraries/notes/entities/actuate-imutils.md
  - topics/actuate-libraries/notes/entities/actuate-movement.md
  - topics/actuate-libraries/notes/entities/actuate-pullers.md
  - topics/actuate-libraries/notes/entities/actuate-viz.md
  - topics/actuate-platform/notes/syntheses/camera-onboarding-end-to-end.md
  - topics/actuate-platform/notes/syntheses/how-a-frame-becomes-an-alert.md
incoming_updated: 2026-05-27
---

# OpenCV (`cv2`)

OpenCV is a **computer vision library** -- not a video library. It happens to ship a video I/O module (`cv2.VideoCapture` / `cv2.VideoWriter`) because almost every CV pipeline needs frames from somewhere, but the library's center of gravity is image processing, geometric ops, classical CV, drawing, and now a sprawling set of `dnn`, `tracking`, `ximgproc`, and `aruco` modules. The video I/O code is an afterthought wrapping a vendored [[ffmpeg-entity|FFmpeg]] (or [[gstreamer-entity|GStreamer]], or V4L2, or MSMF, depending on platform/build).

This distinction matters. OpenCV is **excellent** at the things its core was designed for and **mediocre-to-bad** at the things its video module was bolted on for. See [[cv2-videocapture-internals]] for the gory details on the latter.

## What OpenCV is good at

- **ndarray-first model.** Frames are `numpy.ndarray` of shape `(H, W, 3)` in BGR (yes, BGR -- a 1990s historical accident from Intel SSE alignment). This makes interop with the rest of the Python scientific stack trivial.
- **Image preprocessing.** `cv2.resize`, `cv2.warpAffine`, `cv2.warpPerspective`, `cv2.remap`, `cv2.cvtColor`. Fast SIMD-vectorized implementations.
- **Geometric operations.** Homography estimation, perspective rectification, panorama stitching, fisheye/equirectangular unwarp.
- **Color-space conversions.** YUV ↔ RGB, BGR ↔ HSV ↔ LAB. Codec output is YUV; OpenCV makes it ergonomic to work in whichever space you need.
- **Drawing primitives.** `cv2.rectangle`, `cv2.putText`, `cv2.polylines` -- the canonical "annotate detections on a frame" toolkit.
- **JPEG encode/decode.** `cv2.imencode(".jpg", frame)` and `cv2.imdecode(buf)`. Reliable, fast enough, and (importantly) format-tolerant. The decode path is more lenient than libjpeg-turbo and absorbs many real-world malformed JPEGs that we get from wonky cameras.
- **Build/install ergonomics.** `pip install opencv-python` ships a self-contained wheel with a vendored [[ffmpeg-entity|FFmpeg]]. No system codec dependencies. This is the #1 reason it's the default in so many ML pipelines.

## What OpenCV is bad at

- **PTS / DTS access.** `cap.read()` returns `(ok, frame)`. There is no presentation timestamp. `cap.get(cv2.CAP_PROP_POS_MSEC)` is heuristic and frequently wrong on [[rtsp-deep-dive|RTSP]]. For any timing-sensitive work (clip alignment, multi-stream sync, drift correction) you need [[pyav-entity|PyAV]].
- **Low-latency [[rtsp-deep-dive|RTSP]].** `cv2.VideoCapture` reads from [[ffmpeg-entity|FFmpeg]]'s internal buffer with no exposed control over `max_delay`, `buffer_size`, `fflags`, `flags`, `probesize`, `analyzeduration`, etc. The only escape hatch is `OPENCV_FFMPEG_CAPTURE_OPTIONS` env-var (whole-process, not per-call). See [[cv2-videocapture-internals]].
- **Codec edge cases.** Stream-restart on [[rtsp-deep-dive|RTSP]] keepalive failure, fMP4 fragment handling, B-frame reordering, side-data (rotation matrices, color metadata) -- all swallowed silently. [[pyav-entity|PyAV]] exposes them.
- **Hardware decode.** Possible via `cv2.cudacodec.VideoReader` if you build with CUDA, but the default `pip install opencv-python` wheel has no CUDA. Most production deployments ignore this entirely.
- **Live-preview / encode pipelines.** `cv2.VideoWriter` works for writing local MP4s in DRY_RUN-style scripts; for anything resembling a streaming encode pipeline use [[ffmpeg-entity|ffmpeg]] or [[gstreamer-entity|GStreamer]] directly.

## When to use OpenCV in 2026

Use it for: per-frame image work after the decode is done. Use it for: tactical script-level decode where PTS doesn't matter and you want one wheel and zero ops headaches. Use it for: still-image (JPEG/PNG) decode where its tolerance for garbage input is a feature.

Don't use it for: anything where decoder behavior, timing, or codec details matter. That's [[pyav-entity|PyAV]]'s job.

## Actuate usage (ubiquitous, trending toward "preprocess only")

OpenCV is everywhere in actuate-libraries -- the historical default decoder, encoder, and image-manipulation library. Recent work has been migrating the **decode path** to [[pyav-entity|PyAV]] while keeping OpenCV for everything that comes after.

**Decode paths (legacy, being phased out for streaming):**
- `actuate-libraries/actuate-pullers/src/actuate_pullers/url/url_puller.py:17-395` -- `UrlFramePuller`, the legacy OpenCV [[rtsp-deep-dive|RTSP]]/HTTP puller. `cv2.VideoCapture` + bundled [[ffmpeg-entity|FFmpeg]]. The motion-gated puller variants still inherit from this. See [[cv2-videocapture-internals]] for the open issues.
- `actuate-libraries/actuate-pullers/src/actuate_pullers/sqs/sqs_puller.py:13-99` -- `cv2.imread` for stills, `cv2.VideoCapture(local_filename)` for video clips.
- `actuate-libraries/actuate-pullers/src/actuate_pullers/s3/s3_puller.py:13-80+` -- `cv2.VideoCapture(clip)` for batch S3 clips.
- `actuate-libraries/actuate-pullers/src/actuate_pullers/socket/socket_puller.py:22-120+` -- `cv2.VideoCapture` against a named pipe for `software_type==streaming`.
- `actuate-libraries/actuate-pullers/src/actuate_pullers/buffer/buffer_puller.py:10-60` -- `cv2.VideoCapture("pipes/...")`.
- `actuate-libraries/actuate-pullers/src/actuate_pullers/webcam/webcam_puller.py:13-60+` -- `cv2.VideoCapture(0)` dev path.

**Encode and image work (sticking with OpenCV):**
- `actuate-libraries/actuate-pipeline/src/actuate_pipeline/steps/pre_processors/cv2encode_step.py:9-24` -- `cv2.imencode(".jpg", frame)` JPEG encode fallback when [[reading-list#niche|TurboJPEG]] isn't available.
- `actuate-libraries/actuate-pullers/src/actuate_pullers/shared/base_puller.py:267-286, 301-307` -- `cv2.imencode(".jpg")` for camera-status preview frames.
- `actuate-libraries/actuate-image-cache/src/actuate_image_cache/_decode.py:15-29` -- JPEG-bytes → numpy: TurboJPEG-then-`cv2.imdecode` fallback chain. The `cv2.imdecode` fallback exists *because* OpenCV is more tolerant of malformed JPEGs than TurboJPEG.
- `actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py:139-171` -- inside the [[pyav-entity|PyAV]] puller, `cv2.rotate` is used for 90/180/270 frame rotation derived from MP4 `displaymatrix` side-data. Hybrid: [[pyav-entity|PyAV]] for decode + side-data extraction, OpenCV for the geometric op.

**Annotation / drawing:** `cv2.rectangle` and `cv2.putText` are used in the alarm-senders attachment-rendering paths to draw bounding boxes on alert images.

**Panorama unwarp:** OpenCV's `cv2.remap` is the workhorse for fisheye / panorama camera unwarp in the panorama preprocessing steps.

The **direction of travel**: keep OpenCV for everything post-decode (image ops, JPEG encode, drawing, geometric warps), move all streaming decode to [[pyav-entity|PyAV]]. The migration is incomplete -- see [[frame-extraction-strategies]] for which puller types still use which path.

## Actuate touchpoints

- `actuate-pullers/url/url_puller.py` -- legacy OpenCV `VideoCapture` puller (parent class of motion-gated variants). See [[cv2-videocapture-internals]].
- `actuate-pullers/{sqs,s3,socket,buffer,webcam}/*.py` -- non-streaming pullers all still on `cv2.VideoCapture`. Lower decode-quality bar -- file/clip/local sources don't suffer the [[rtsp-deep-dive|RTSP]] timing issues the URL puller did.
- `actuate-pullers/url/av_url_puller.py:139-171` -- `cv2.rotate` for displaymatrix-derived rotation; hybrid [[pyav-entity|PyAV]]+OpenCV usage.
- `actuate-pipeline/steps/pre_processors/cv2encode_step.py` -- JPEG encode fallback.
- `actuate-image-cache/_decode.py` -- JPEG decode fallback chain (after TurboJPEG).
- `actuate-pullers/shared/base_puller.py` -- camera-status preview JPEG encode.
- Drawing/annotation in alarm-senders attachment renderers.
- See [[pyav-entity]] for the canonical streaming decode path; see [[frame-extraction-strategies]] for the migration map.
