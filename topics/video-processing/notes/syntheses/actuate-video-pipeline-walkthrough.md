---
title: "Actuate Video Pipeline Walkthrough (camera glass to monitoring center)"
type: synthesis
topic: video-processing
tags: [actuate, pipeline, walkthrough, decode, frame-flow, alert, immix]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/2026-04-27.md
  - topics/video-processing/_summary.md
  - topics/video-processing/notes/concepts/gstreamer-pipeline-model.md
  - topics/video-processing/notes/concepts/gstreamer-vs-ffmpeg.md
  - topics/video-processing/notes/concepts/nvidia-deepstream.md
  - topics/video-processing/notes/concepts/protocol-latency-comparison.md
  - topics/video-processing/notes/syntheses/actuate-build-vs-buy-tradeoffs.md
  - topics/video-processing/notes/syntheses/actuate-clip-generation-flow.md
  - topics/video-processing/notes/syntheses/actuate-frame-ingest-decode-paths.md
incoming_updated: 2026-06-25
---

# Actuate Video Pipeline Walkthrough

End-to-end map of every place a single video frame flows through Actuate -- from a photon hitting a CMOS sensor to an alert ringing on a monitoring-center workstation. This is **the** walkthrough; sibling notes ([[actuate-frame-ingest-decode-paths]], [[actuate-clip-generation-flow]], [[actuate-build-vs-buy-tradeoffs]]) zoom in on individual stages. Every claim about Actuate cites a file path. When the pipeline forks (and it forks a lot), we follow each branch.

## The diagram

```
                     ┌─────────────────────────────────────────────────┐
                     │              CAMERA / VMS LAYER                  │
                     │  (RTSP, KVS, WebSocket fMP4, JPEG poll, SQS S3) │
                     └───────────────────────┬─────────────────────────┘
                                             │
                       per-integration_type → factory.generate_site()
                                             │
                     ┌───────────────────────▼─────────────────────────┐
                     │   PULLER  (BasePuller subclass per integration) │
                     │   produces BGR uint8 numpy frames into          │
                     │   thread-shared frame_queue                     │
                     └───────────────────────┬─────────────────────────┘
                                             │
                     ┌───────────────────────▼─────────────────────────┐
                     │   PIPELINE  pre_processors → inference → post   │
                     │   (encode JPEG, crop, run YOLO, filter dets)    │
                     └───────────────────────┬─────────────────────────┘
                                             │  hit (detection windowed)
                     ┌───────────────────────▼─────────────────────────┐
                     │   FRAME PERSIST  S3 JPEG put + DDB EnrichedFrame│
                     └───────────────────────┬─────────────────────────┘
                                             │
                     ┌───────────────────────▼─────────────────────────┐
                     │   ALERT SENDER  per-integration alert flavour    │
                     │   (Immix, AILink, Frontel, generic, ...)        │
                     └───────────────────────┬─────────────────────────┘
                                             │
                     ┌───────────────────────▼─────────────────────────┐
                     │ MONITORING CENTER  (Immix MP4 muxed downstream  │
                     │ from event_queue_immix_alarm.fifo)              │
                     └─────────────────────────────────────────────────┘
```

The strong containment line is between the connector (which produces frame events + S3 keys) and the downstream consumers that actually format an MP4 -- see [[actuate-clip-generation-flow]] for that boundary in detail.

## Stage 1 -- Camera / VMS

A camera ([[rtsp-deep-dive|RTSP]], ONVIF) or VMS bridge (Avigilon Cloud Service, Milestone XProtect, Eagle Eye Networks, Immix VCH AutoPatrol, [[aws-kvs-entity|KVS]]) emits the actual encoded byte stream. [[codecs-overview|Codecs]] in the wild for our fleet: [[h264-deep-dive|H.264]] dominates, [[h265-hevc-deep-dive|H.265/HEVC]] growing, [[mjpeg-and-still-image-formats|MJPEG]] for cheap cameras and Orchid endpoints, plus proprietary muxes (Milestone's TCP frame protocol, Genetec stream tunnels).

We have **no control over codec choice at this layer** -- whatever the customer's camera emits is what we get. That's why the decoder layer has to be plural. See [[h264-deep-dive]], [[h265-hevc-deep-dive]], [[mjpeg-and-still-image-formats]].

## Stage 2 -- [[connector-factory|Connector factory]] dispatch

`vms-connector/connector_factories/shared/factory.py:60-107` -- `generate_site()` switches on `integration_type` to pick a puller class. This is the **single most important fan-out point in the entire system**: from here on, the decode/transport strategy diverges per integration. The factory is the only place a developer sees every supported VMS at once.

For the full per-integration decoder mapping, see [[actuate-frame-ingest-decode-paths]].

## Stage 3 -- The puller (frame ingestion)

The canonical puller catalog is exported from `actuate-libraries/actuate-pullers/src/actuate_pullers/__init__.py:1-56`. Each concrete puller inherits `BasePuller` (`actuate-libraries/actuate-pullers/src/actuate_pullers/shared/base_puller.py`) and produces decoded BGR uint8 numpy frames into a thread-shared `frame_queue`.

The four most-used pullers and what they do internally:

- **`AvUrlFramePuller`** (`actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py:320-1438`) -- canonical [[pyav-entity|PyAV]]-based [[rtsp-deep-dive|RTSP]]/HTTP/fMP4 puller. The "good" decoder. Demuxes via `container.demux(video_stream)` and decodes with `_decode_packet()` (line 755-775), yielding `frame.to_ndarray(format="bgr24")` (line 1351). Includes adaptive frame skipping via `AVDiscard` (line 617-753), full PTS / DTS tracking with discontinuity correction (`TimestampTracker`, line 174-317), hardware-acceleration detection (line 527-607) covering CUDA, [[hardware-accelerated-codecs|VAAPI]], AMF, [[hardware-accelerated-codecs|VideoToolbox]]. The [[ffmpeg-entity|FFmpeg]]/libav substrate makes this our most capable decoder; see [[ffmpeg-libav-libraries]] and [[pyav-entity]].

- **`UrlFramePuller`** (`actuate-libraries/actuate-pullers/src/actuate_pullers/url/url_puller.py:17-395`) -- legacy [[opencv-entity|OpenCV]]-based [[rtsp-deep-dive|RTSP]]/HTTP path. Uses `[[opencv-entity|cv2]].VideoCapture` + [[ffmpeg-entity|ffmpeg]] under the hood; sets `OPENCV_FFMPEG_CAPTURE_OPTIONS=rtsp_transport;tcp` for `omniaweb` / `eagleeyenetworks` URLs (line 314, 318). See [[opencv-entity]], [[cv2-videocapture-internals]]. The motion-gated variant `actuate-libraries/actuate-pullers/src/actuate_pullers/url/url_puller_motion.py:20-100+` uses `actuate_movement.delta_noise.get_delta_noise` to throttle decode-cost on motionless feeds. The migration to `AvUrlFramePuller` is **incomplete**: many integration_types still resolve to this [[opencv-entity|OpenCV]] path. This is migration debt.

- **`KVSFramePuller`** (`actuate-libraries/actuate-pullers/src/actuate_pullers/kvs/kvs_puller.py:9-47` + `kvs_ingestor.py:50-335`) -- pulls [[aws-kvs-entity|Kinesis Video Streams]] via `boto3.client("kinesis-video-media").get_media()` (line 270-273), feeds the MKV byte chunks into a [[gstreamer-entity|GStreamer]] `appsrc` pipeline (`appsrc → matroskademux → decodebin → videoconvert → jpegenc → appsink`, line 148-156). The pipeline **re-encodes JPEG inside [[gstreamer-entity|GStreamer]] then re-decodes via `[[opencv-entity|cv2]].imdecode`** at line 119 -- two unnecessary codec ops per frame. See [[aws-kvs-entity]], [[gstreamer-entity]].

- **`AutopatrolWebsocketStreamPuller`** (`actuate-libraries/actuate-pullers/src/actuate_pullers/socket/autopatrol_websocket_stream_puller.py:43-300+`) -- WebSocket binary fMP4 path for Immix AutoPatrol. Does **its own ISO-BMFF box parsing** byte-by-byte (`extract_next_fragment`, line 111-135) walking `ftyp`/`moov`/`moof`/`mdat` boxes, then opens each assembled fragment via `av.open(buffer, format="mp4")` and decodes with [[pyav-entity|PyAV]] (line 194-275). One of the two places we manually parse a container format.

For the full per-puller catalog including Milestone TCP, Orchid HTTP, JPEG-poll, SQS-Video, S3 batch, Unix-socket, named-pipe, and webcam variants, see [[actuate-frame-ingest-decode-paths]].

## Stage 4 -- Codec / container handling inside the decoder

[[pyav-entity|PyAV]] gives us the codec details that [[opencv-entity|OpenCV]] hides:

- **HW decoder table** at `av_url_puller.py:24-77` enumerates [[h264-deep-dive|h264]], [[h265-hevc-deep-dive|hevc]], [[mjpeg-and-still-image-formats|mjpeg]], mpeg2/4, vp8/9, av1, vc1, prores × cuda / videotoolbox / vaapi / amf / mediacodec / v4l2m2m. See [[hardware-accelerated-codecs]].
- **fMP4 detection** (`av_url_puller.py:496-503, 1158-1185`) flags Avigilon-style fragmented MP4 and schedules a 300s+jitter recycle to flush the libavformat `mov` demuxer's growing `frag_index` (~5-10 MB/hr leak). Without this, long-lived Avigilon streams OOM.
- **Display matrix rotation** (line 139-171) reads MP4 sidedata 9-int rotation matrices and applies `[[opencv-entity|cv2]].rotate` for 90/180/270 cases -- portrait-mode security cameras still happen.
- **Keyframe wait** (line 1318-1335) skips packets until the first keyframe, avoiding bogus partial-decode artefacts. See [[gop-keyframe-fundamentals]].

[[h265-hevc-deep-dive|H.265/HEVC]] is decoded correctly by the [[pyav-entity|PyAV]] path with an explicit warning at line 910-913 (`"H265 in use, potential performance issues"`). The [[gstreamer-entity|GStreamer]] [[rtsp-deep-dive|RTSP]] fallback path is **[[h264-deep-dive|H.264]]-only** (`actuate-libraries/actuate-pullers/src/actuate_pullers/gstreamer/gstreamer_input_pipeline.py:86-101`) -- [[h265-hevc-deep-dive|H.265]] [[rtsp-deep-dive|RTSP]] via that path silently fails. Flagged in [[actuate-frame-ingest-decode-paths]].

## Stage 5 -- Pipeline pre-processors

Once a frame is in the `frame_queue` it enters the inference pipeline. `actuate-libraries/actuate-pipeline/src/actuate_pipeline/core/pipeline_factory.py:102-126` selects the encoder step based on `customer.use_turbojpeg` (default True):

- `actuate-libraries/actuate-pipeline/src/actuate_pipeline/steps/pre_processors/turbojpegencode_step.py:1-31` -- `TurboJpegEncodeStep`, JPEG quality 95, BGR, 4:2:0.
- `actuate-libraries/actuate-pipeline/src/actuate_pipeline/steps/pre_processors/cv2encode_step.py:9-24` -- `Cv2EncodeStep` fallback `cv2.imencode(".jpg", frame)`.

Other pre-processors crop ROIs and stamp metadata. The `UploadFrameStep` (`actuate-libraries/actuate-pipeline/src/actuate_pipeline/steps/pre_processors/upload_frame_step.py:13-40`) writes a one-shot background frame per camera to `s3://<analytics-ui-bucket>/<customer>/background/<camera>.jpg`. See [[frame-extraction-strategies]].

## Stage 6 -- Inference

Encoded JPEG bytes are sent to the [[nvidia-deepstream|DeepStream]] / Triton inference server (model server is its own topic; see [[ai-models/_summary]]). The pipeline gets back per-frame detections + scores. Inference is out of scope for this synthesis but is the consumer of all the upstream decode work.

## Stage 7 -- Post-processors and frame persist

On a "hit" (a windowed cluster of detections), the post-processors fire. Per-detection frames land in two places:

- **S3 (JPEG)**: `actuate-libraries/actuate-frames/src/actuate_frames/save_frame_meta.py:12-79`. Key shape `<custcam_id><label>/<window_timestamp>/<frame_id>` in the detection bucket. Uploaded async via `executor.submit`. Note: **this is a JPEG, not an MP4**.
- **DynamoDB EnrichedFrame**: same file, line 54-73. Writes `s3_bucket`, `s3_key`, `frame_id`, `model_labels`. The DDB row is the only thing downstream services hold; the JPEG is referenced indirectly.

Gauntlet/robomladen (research/labelling pipeline) writes a parallel set: `actuate-libraries/actuate-pipeline/src/actuate_pipeline/steps/post_processors/save_analysis_frame_step.py:8-40` to `actuate-robomladen` bucket.

**All frame storage in S3 is JPEG-only.** No MP4, no MKV, no fMP4 written by these libraries. Implications for clip generation discussed in [[actuate-clip-generation-flow]].

## Stage 8 -- Alert sender

`actuate-libraries/actuate-alarm-senders/` has one sender per VMS / monitoring-centre flavour. The shared annotation step (`actuate-libraries/actuate-alarm-senders/src/actuate_alarm_senders/shared_alert/attachment_alert_sender.py:14-77`) decodes the alert JPEG via TurboJPEG, draws bounding boxes via `actuate_viz.draw_boxes`, and re-encodes JPEG (quality 95). **No video assembly happens here** -- it's strictly per-frame JPEG manipulation.

For Immix (the major monitoring-centre integration): `actuate-libraries/actuate-alarm-senders/src/actuate_alarm_senders/immix/immix_alert_sender.py:88-100` computes `attachment_frames = alert_data.attachment_frame_count * alert_data.product_fps` when `use_mp4=True` and **hands off to `event_queue_immix_alarm.fifo`** with `event_type`, `s3_folder`, frame count. The actual MP4 muxing for Immix MP4-mode happens in a downstream consumer that lives outside `actuate-libraries`, `vms-connector`, and `actuate-alarm-senders`. This is a hard architectural seam (see [[actuate-clip-generation-flow]]).

For AILink / Frontel / SQS-clip integrations: `actuate-libraries/actuate-alarm-senders/src/actuate_alarm_senders/shared_alert/clips_alert_bridge.py:34-128` maps `ClipsAlertData` → `AlertData` with `clip_alert_s3_bucket` / `clip_alert_s3_key` carried through. **Clips arrive PRE-muxed from upstream** -- the connector neither demuxes nor remuxes them.

The Immix annotated-image variant (`autopatrol_sender.py:102-133`) uploads a single annotated frame to `annotated/<window_id>/<frame_id>.jpg` and returns a presigned URL.

## Stage 9 -- Monitoring centre delivery

This is OUT of the libraries we own. For Immix MP4 mode, a downstream FIFO consumer assembles the MP4 from the frames in S3 and pushes it to Immix VCH. For AILink / Frontel, the alert payload + presigned clip URL is delivered via the partner's API. See [[integrations/immix/_summary|integrations/immix]].

## What this synthesis does not cover (and where to find it)

- **Per-integration decoder choice and gotchas** -- [[actuate-frame-ingest-decode-paths]]
- **Why we don't mux MP4s and what we'd do if we did** -- [[actuate-clip-generation-flow]]
- **Where AWS managed services would replace homegrown code** -- [[actuate-build-vs-buy-tradeoffs]]
- **AsyncInferencePool internals and batching** -- [[vms-connector/_summary]]

## Open questions

1. **Connector Dockerfile audit** -- is `libnvidia-decode`, `libturbojpeg`, the right [[gstreamer-entity|gstreamer]]-plugins set actually installed on production EKS nodes? Scout pass did not locate the connector Dockerfile.
2. **Two parallel decoder paths (`url_puller` vs `av_url_puller`) co-exist** -- is there a tracked epic to finish the migration?
3. **No NR instrumentation on per-frame timings** -- can we add light-touch per-stage histograms without blowing up cardinality?

## See also

[[actuate-frame-ingest-decode-paths]] | [[actuate-clip-generation-flow]] | [[actuate-build-vs-buy-tradeoffs]] | [[ffmpeg-entity]] | [[gstreamer-entity]] | [[opencv-entity]] | [[pyav-entity]] | [[knowledgebase/topics/billing/reading-list]] | [[vms-connector/_summary]] | [[actuate-libraries/_summary]]
