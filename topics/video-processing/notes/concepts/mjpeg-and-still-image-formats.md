---
title: MJPEG and Still-Image Formats
type: concept
topic: video-processing
tags: [codec, mjpeg, jpeg, intra, surveillance, turbojpeg]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/actuate-libraries/notes/entities/actuate-integration-calls.md
  - topics/actuate-libraries/notes/entities/actuate-pullers.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase2-stream-probe.md
  - topics/integrations/eagle-eye/_summary.md
  - topics/video-processing/_summary.md
  - topics/video-processing/notes/concepts/av1-vp9-future.md
  - topics/video-processing/notes/concepts/codecs-overview.md
  - topics/video-processing/notes/concepts/connector-decoder-routing-map.md
  - topics/video-processing/notes/concepts/connector-docker-system-deps.md
  - topics/video-processing/notes/concepts/gop-keyframe-fundamentals.md
incoming_updated: 2026-05-01
---

# MJPEG and Still-Image Formats

**[[mjpeg-and-still-image-formats|Motion JPEG (MJPEG)]]** is the codec that says "video is just a stream of still images." Each frame is an independent JPEG; there is no inter-frame compression, no motion vectors, no [[gop-keyframe-fundamentals|GOP]]. Per-frame compression efficiency is poor (typical 10:1 vs [[h264-deep-dive|H.264]]'s 50–100:1 on the same content), but every frame is randomly accessible and corruption is bounded to a single frame. For Actuate this codec family is **massively over-represented in the codebase** — we encode all detection frames as JPEG, store them as JPEG in S3, and decode JPEG-byte payloads back to numpy on every cache hit.

## JPEG itself, briefly

A JPEG frame is the result of:

1. **Color-space conversion** RGB → YCbCr.
2. **Chroma subsampling** — typically 4:2:0 (chroma planes are half-resolution in both dimensions) for surveillance / consumer. 4:4:4 exists; we don't use it.
3. **8×8 block DCT** on each plane.
4. **Quantization** — divide DCT coefficients by a per-block-position quantization table. This is the lossy step. The "quality" knob is really a quant-table-scaling knob.
5. **Entropy coding** — zigzag scan, run-length encoding, Huffman coding. (Arithmetic coding exists in the spec; never used in practice.)

Because every frame stands alone, the only knobs are: resolution, chroma sub-sampling pattern, quality (= quant scaling), and Huffman table choice. No [[gop-keyframe-fundamentals|GOP]], no profile, no level. The simplicity is the point — JPEG decoders are everywhere, including in browser ImageDecoder APIs, [[opencv-entity|OpenCV]], every language's stdlib, and every JPEG SoC accelerator on the planet.

## MJPEG in surveillance: why it persists

You'd think a 50–100× compression-efficiency gap would have killed MJPEG. It hasn't, because MJPEG has properties that matter for surveillance specifically:

1. **No [[gop-keyframe-fundamentals|GOP]] latency.** First-frame decode = decode one JPEG. No keyframe wait, no IDR-required-to-start. See [[gop-keyframe-fundamentals]] for the contrast with [[h264-deep-dive|H.264]]/[[h265-hevc-deep-dive|H.265]].
2. **Bounded corruption blast radius.** A corrupt JPEG = one bad frame. A corrupt [[h264-deep-dive|H.264]] P-frame can damage every subsequent frame until the next IDR (see [[h264-deep-dive]]).
3. **Random access at any frame.** Useful for snapshot endpoints, evidence playback, and CV analysis that subsamples frames.
4. **Trivial to re-encode / scale.** No reference-frame state; no encoder rate-control to maintain across frames. Per-frame JPEG resize is embarrassingly parallel.
5. **Universal decode availability.** Every camera, every browser, every analytics box. MJPEG over HTTP is a 1990s pattern that still works on every camera made.

The cost is bandwidth — a 1080p30 MJPEG stream at "good" quality is 40–80 Mbps, vs 2–4 Mbps for [[h264-deep-dive|H.264]]. Cheap cameras and short snapshot intervals dodge this; high-fps full-resolution MJPEG streams are rare today.

## MJPEG over HTTP (multipart/x-mixed-replace)

The classic "MJPEG over HTTP" stream is a `multipart/x-mixed-replace` response with each part being a JPEG frame and a Content-Type/Content-Length header. Trivial to scrape with `curl` and a parser — which is part of why every camera supported it. This is also the format ONVIF Profile S calls "MJPEG over HTTP" and the fallback most VMSes can produce when an [[rtsp-deep-dive|RTSP]] path is unavailable.

We've decoded these in Actuate over the years — `cv2.VideoCapture` handles them via libavformat, [[pyav-entity|PyAV]] does too. They're not currently a primary ingestion path, but if a partner supplies a snapshot URL or an HTTP MJPEG fallback, the URL-puller path handles it.

## JPEG everywhere in Actuate

The Actuate pipeline encodes detection frames to JPEG in three places:

**TurboJPEG encode** (`actuate-libraries/actuate-pipeline/src/actuate_pipeline/steps/pre_processors/turbojpegencode_step.py:1-31`) — the fast path. Uses `PyTurboJPEG` (a `libjpeg-turbo` binding) to compress a BGR numpy array to JPEG bytes at quality 95, 4:2:0 chroma subsampling. TurboJPEG is significantly faster than [[opencv-entity|`cv2.imencode`]] (often 2–4×) because it uses SIMD-tuned libjpeg-turbo directly without going through [[opencv-entity|OpenCV]]'s Python bindings.

**[[opencv-entity|OpenCV]] fallback** (`actuate-libraries/actuate-pipeline/src/actuate_pipeline/steps/pre_processors/cv2encode_step.py:9-24`) — the compatibility path. `cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 95])`. Slower but doesn't depend on the libjpeg-turbo native library being present.

**Pipeline factory choice** (`actuate-libraries/actuate-pipeline/src/actuate_pipeline/core/pipeline_factory.py:102-126`) — selects TurboJPEG vs [[opencv-entity|cv2]] encode based on the customer's `use_turbojpeg` flag. The flag is per-customer rather than global because libjpeg-turbo deployment was rolled out cautiously after early stability concerns; the [[opencv-entity|cv2]] path remains the safe default for some long-tail customers.

**Decode side** (`actuate-libraries/actuate-image-cache/src/actuate_image_cache/_decode.py:15-29`) — JPEG bytes → numpy, with the same TurboJPEG-then-cv2 fallback pattern. This is hot — every frame retrieved from S3 or the in-memory image cache goes through this decode.

## Storage: every detection frame is JPEG

S3 storage layout per `actuate-libraries/actuate-frames/src/actuate_frames/save_frame_meta.py:43`: keys are of the form `<custcam_id><label>/<window_timestamp>/<frame_id>` and the object body is JPEG bytes. There is **no MP4 or MKV storage** of detection-time imagery in the libraries. Clip muxing (assembling alert clips from these JPEG frames into MP4 for monitoring-center delivery) happens downstream of the libraries — it's not an `actuate-libraries` concern.

This design has tradeoffs we've lived with:

- **Pro: random access by frame is trivial.** Every frame is one S3 key.
- **Pro: no codec state to manage across frames.** Each frame self-contained.
- **Pro: no re-encode for resize / crop / annotation.** Decode → modify → re-encode is straightforward; no [[gop-keyframe-fundamentals|GOP]] boundary concerns.
- **Con: storage cost is much higher than an inter-frame-coded video.** A 30-second alert clip at 30fps as 900 individual JPEGs is several × the bytes of an [[h264-deep-dive|H.264]] MP4 of the same content. Mitigated in practice by storing only frames around detections, not continuous clips.
- **Con: per-frame S3 write pressure.** 900 PUTs vs 1 PUT for a 30s clip. PUT pricing matters.

These tradeoffs come up in `[[actuate-build-vs-buy-tradeoffs]]` discussions — the JPEG-everywhere posture is a deliberate design decision, but worth re-examining when frame volumes spike.

## Other intra-only / still formats worth knowing

- **PNG** — lossless. Used in CV pipelines that can't tolerate JPEG quantization noise (synthetic test images, ground-truth masks). Not used in Actuate's hot path.
- **WebP** — Google's JPEG successor; lossy mode is ~25–35% smaller at the same perceptual quality. Browser support good; surveillance support nonexistent. Not currently used.
- **AVIF** — [[av1-vp9-future|AV1]]'s still-image profile (see [[av1-vp9-future]]). Better compression than WebP; encoder cost much higher; ecosystem support uneven.
- **HEIF / HEIC** — [[h265-hevc-deep-dive|H.265]]'s still-image profile. Apple-popular; surveillance-irrelevant.
- **JPEG 2000** — wavelet-based; broadcast / cinema niche. Effectively zero surveillance presence.
- **ProRes / DNxHD** — intra-only video [[codecs-overview|codecs]], broadcast / post-production. Not surveillance-relevant.

We may eventually evaluate WebP or AVIF for storage cost reduction, but the decode-path ubiquity of JPEG is hard to give up — every CV consumer, every browser, every field tool already handles JPEG natively.

## Common gotchas

1. **Quality 95 4:2:0 is the right default for AI input.** Quality > 95 is mostly wasted bits (encoder enters "store the noise" territory); quality < 90 risks introducing artifacts that VLM/YOLO models can pick up as features. We've debated this more than once.
2. **TurboJPEG vs [[opencv-entity|cv2]] produces *slightly* different bitstreams.** Same quality setting, different Huffman tables, different rounding. Visually identical, byte-different. Don't write tests that compare encoded bytes.
3. **MJPEG over [[rtsp-deep-dive|RTSP]]** is rare (most cameras default to [[h264-deep-dive|H.264]] over [[rtsp-deep-dive|RTSP]]) but exists; libavformat handles it transparently.
4. **JPEG file size ≠ pixel content.** A scene with grass and trees compresses much worse than a flat wall. Bandwidth budgeting against worst-case content matters.

## Actuate touchpoints

- TurboJPEG encode (quality 95, BGR, 4:2:0) — `actuate-libraries/actuate-pipeline/src/actuate_pipeline/steps/pre_processors/turbojpegencode_step.py:1-31`
- [[opencv-entity|cv2]] encode fallback — `actuate-libraries/actuate-pipeline/src/actuate_pipeline/steps/pre_processors/cv2encode_step.py:9-24`
- Encode-path selection per customer — `actuate-libraries/actuate-pipeline/src/actuate_pipeline/core/pipeline_factory.py:102-126`
- JPEG-bytes → numpy decode — `actuate-libraries/actuate-image-cache/src/actuate_image_cache/_decode.py:15-29`
- S3 key layout for stored JPEG frames — `actuate-libraries/actuate-frames/src/actuate_frames/save_frame_meta.py:43`
- Cross-topic: [[actuate-clip-generation-flow]], [[actuate-frame-ingest-decode-paths]], [[ai-models/_summary]], [[reading-list]] for libjpeg-turbo / mozjpeg alternatives.
- Per-format overviews: [[codecs-overview]], [[containers-overview]]
