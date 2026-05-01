---
title: "Connector Decoder Routing Map (integration_type → puller class → decode library)"
type: concept
topic: video-processing
tags: [connector, factory, routing, decoder, migration, follow-up, rtsp]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/2026-04-27.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/video-processing/_summary.md
incoming_updated: 2026-05-01
---

# Connector Decoder Routing Map

## Summary

`vms-connector` chooses a decoder per camera in two [[layers]]. The first layer is `connector_factories/shared/factory.py:60-107` — a giant `if/elif` on `integration_type` that selects a per-integration **factory module**. The factory instantiates a per-integration **camera class** in `vms-connector/camera/<integration>/<integration>_camera.py`. The camera's `launch_process()` is where the actual **puller class** (from `actuate-libraries/actuate-pullers`) is selected, often with a runtime branch on `motion_queue`, `customer.lead`, `customer.local`, or transport mode.

This concept note enumerates every `integration_type` branch, traces the exact puller class instantiated, and tags it with its underlying decode library: **[[pyav-entity|PyAV]]** ([[ffmpeg-entity|FFmpeg]] via libav, hwaccel-capable), **[[opencv-entity|OpenCV]]** (`cv2.VideoCapture`, no hwaccel from our codepath), **Milestone proprietary** (TLS socket + JPEG XML protocol), **HTTP polling** (Orchid JPEG queue), **WebSocket fMP4** (AutoPatrol/VCH), **[[aws-kvs-entity|AWS KVS]]** ([[hls-and-dash|HLS]]/GetMedia + [[pyav-entity|PyAV]]), **SQS-Video / S3 batch** (clip download → [[opencv-entity|OpenCV]]), or **Unix socket** (Star4Live).

**The big finding:** the [[gstreamer-entity|GStreamer]] puller (`actuate_pullers/url/gst_url_puller.py`, the [[h264-deep-dive|H.264]]-only one) is **not used anywhere** in `vms-connector`. Every "live [[rtsp-deep-dive|RTSP]]-ish" integration is now on [[pyav-entity|PyAV]] `AvUrlFramePuller`. The remaining legacy [[opencv-entity|OpenCV]] `UrlFramePuller` instantiations live only in motion-gated `OnOffMotionBasedUrlFramePuller` (hikcentral) and inside helpers (S3, SQS, VideoQueue, Webcam, Socket, Buffer) where the decoder choice is dictated by container/codec rather than by the live stream.

## Routing table

| `integration_type` | Factory module | Camera class | Puller class | Decode library | Container/Protocol | HW-accel? | Migration status |
|---|---|---|---|---|---|---|---|
| `rtsp` | [`rtsp/rtsp_factory.py`](file:///home/mork/work/vms-connector/connector_factories/rtsp/rtsp_factory.py) | `RTSPCamera` | `AvUrlFramePuller` (default) / `MotionBasedAvUrlFramePuller` (motion) / `GenesisUrlFramePuller` (lead=="genesis") / `WebcamFramePuller` (local) | [[pyav-entity|PyAV]] | [[rtsp-deep-dive|RTSP]]→[[h264-deep-dive|H.264]]/[[h265-hevc-deep-dive|HEVC]] | Yes (CUDA/[[hardware-accelerated-codecs|VAAPI]]/VT/AMF/v4l2m2m) | **Migrated** |
| `milestone_rtsp` | `rtsp/rtsp_factory.py` | `RTSPCamera` | same as `rtsp` | [[pyav-entity|PyAV]] | [[rtsp-deep-dive|RTSP]] | Yes | **Migrated** |
| `adpro` | `rtsp/rtsp_factory.py` | `RTSPCamera` | same as `rtsp` | [[pyav-entity|PyAV]] | [[rtsp-deep-dive|RTSP]] | Yes | **Migrated** |
| `digital_watchdog` | `dw/dw_factory.py` | `DWCamera` | `AvUrlFramePuller` / `MotionBasedAvUrlFramePuller` | [[pyav-entity|PyAV]] | [[rtsp-deep-dive|RTSP]] | Yes | **Migrated** |
| `salient` | `salient/salient_factory.py` | `SalientCamera` | `AvUrlFramePuller` / `MotionBasedAvUrlFramePuller` | [[pyav-entity|PyAV]] | [[rtsp-deep-dive|RTSP]] | Yes | **Migrated** |
| `milestone` | `milestone/milestone_factory.py` | `MilestoneCamera` | `MilestoneJpgFramePuller` | [[opencv-entity|OpenCV]] (`cv2.imdecode`) over Milestone proprietary TLS/XML+JPEG | TCP socket + Milestone XML framing | No | Permanent — proprietary protocol |
| `avigilon` | `avigilon/avigilon_factory.py` | `AvigilonCamera` | `AvUrlFramePuller` / `MotionBasedAvUrlFramePuller` | [[pyav-entity|PyAV]] | [[rtsp-deep-dive|RTSP]] | Yes | **Migrated** |
| `video_insight` | `video_insight/video_insight_factory.py` | `VideoInsightCamera` | `AvUrlFramePuller` | PyAV | RTSP | Yes | **Migrated** |
| `luxriot` | `luxriot/luxriot_factory.py` | `LuxriotCamera` | `AvUrlFramePuller` / `MotionBasedAvUrlFramePuller` | PyAV | RTSP | Yes | **Migrated** |
| `genetec` | `genetec/genetec_factory.py` | `GenetecCamera` | `AvUrlFramePuller` / `MotionBasedAvUrlFramePuller` | PyAV | RTSP | Yes | **Migrated** |
| `exacq` | `exacq/exacq_factory.py` | `ExacqCamera` | `AvUrlFramePuller` (video stream) **or** `JpgFrameQueuePuller` (JPEG stream) | PyAV **or** [[opencv-entity|OpenCV]] `cv2.imdecode` | RTSP **or** HTTP [[mjpeg-and-still-image-formats|MJPEG]] | Yes (PyAV path only) | Mixed; JPEG path unavoidable |
| `openeye` | `openeye/openeye_factory.py` | `OpeneyeCamera` | `AvUrlFramePuller` / `MotionBasedAvUrlFramePuller` | PyAV | RTSP | Yes | **Migrated** |
| `orchid` | `orchid/orchid_factory.py` | `OrchidCamera` | `OrchidJpgFrameQueuePuller` | `requests` HTTP + [[opencv-entity|OpenCV]] `cv2.imdecode` | HTTP JPEG polling | No | Permanent — Orchid offers no RTSP route from us |
| `star4live` | `star4live/star4live_factory.py` | `Star4LiveCamera` | `SocketPuller` | [[opencv-entity|OpenCV]] `cv2.VideoCapture` on Unix-pipe | Unix domain socket from Star4Live SDK sidecar | No (cv2 software) | Bespoke — sidecar feeds raw |
| `video` | `video/videoclip_factory.py` | `VideoClipCamera` (or `VerifierCamera` in robo) | `S3FramePuller` (default) / `UrlFramePuller`+`MotionBasedUrlFramePuller` / `GenesisUrlFramePuller` (verifier branch) | [[opencv-entity|OpenCV]] (`cv2.VideoCapture` on downloaded clip) | S3-backed MP4 clips | No | Batch verifier — [[opencv-entity|OpenCV]] is acceptable for clips |
| `eagle_eye` / `eagle_eye_v3` | `eagle_eye/eagle_eye_factory.py` | `EagleEyeCamera` | `AvUrlFramePuller` / `MotionBasedAvUrlFramePuller` | PyAV | HTTPS preview MP4 (Eagle Eye HTTP) | Yes | **Migrated** |
| `hikcentral` | `hikcentral/hikcentral_factory.py` | `HikcentralCamera` | `AvUrlFramePuller` (default) **or** `OnOffMotionBasedUrlFramePuller` (motion) | PyAV **or** **legacy OpenCV `UrlFramePuller`** | RTSP | Partial (motion path is OpenCV) | **Half-migrated — motion path still legacy** |
| `kvs` | `kvs/kvs_factory.py` | `KvsCamera` | `KVSFramePuller` (`KVSFramePuller`+`KvsIngestor`) | PyAV (over [[kvs-components|KVS]] [[hls-and-dash|HLS]]/GetMedia output) | [[aws-kvs-entity|AWS KVS]] | Yes (PyAV) | **Migrated** |
| `vch` | `autopatrol/vch_factory.py` | `VCHCamera` | `AutopatrolWebSocketStreamPuller` (subclass of `AvUrlFramePuller`) | PyAV (fMP4 over WebSocket) | Immix WebSocket fMP4 (~2 s burst) | Yes | **Migrated** (PyAV under WS) |
| `autopatrol` | `autopatrol/autopatrol_factory.py` | `AutoPatrolCamera` | `AutopatrolWebSocketStreamPuller` (subclass of `AvUrlFramePuller`); `WebcamFramePuller` only when `customer.local && use_webcam` | PyAV | Immix WebSocket fMP4 (~10 s patrol) | Yes | **Migrated** |
| `SMTP_per_camera` / `ajax` | `smtp/smtp_factory.py` | `SMTPCamera` | `VideoQueueFramePuller` | OpenCV (`cv2.VideoCapture` on staged MP4) | SMTP-attached MP4 → local file → cv2 | No | Batch — OpenCV is acceptable for MP4 files |

Patrol (non-Immix) integration uses `connector_factories/patrol/patrol_factory.py` → `PatrolCamera` → currently only `AvUrlFramePuller` (`inner_integration_type == "rtsp"`); other inner types raise.

The `sqs_video` factory (`connector_factories/sqs_video/sqs_factory.py`) is **dead** — it has no live `integration_type` branch in the switch, and its `default()` body is fully commented out. The underlying `SqsPuller` (`actuate_pullers/sqs/sqs_puller.py`, OpenCV-based MP4 decoder) is not reachable from production today.

## Migration debt commentary

**Live-stream integrations on [[pyav-entity|PyAV]] (the new path):** [[rtsp-deep-dive|rtsp]], milestone_rtsp, adpro, digital_watchdog, salient, avigilon, video_insight, luxriot, genetec, openeye, eagle_eye, eagle_eye_v3, kvs, vch, autopatrol, hikcentral (default branch), exacq (video-stream branch). That's **16 of the 22 active integration_types** decoded primarily by [[ffmpeg-entity|FFmpeg]] through [[pyav-entity|PyAV]] with hardware-acceleration available via `HW_DECODERS` (CUDA/[[hardware-accelerated-codecs|VAAPI]]/[[hardware-accelerated-codecs|VideoToolbox]]/AMF/v4l2m2m/MediaCodec) — see `actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py:24-77`.

**Live-stream integrations still on legacy [[opencv-entity|OpenCV]] `UrlFramePuller`:** **only one remains** — `hikcentral` when `motion_queue` is wired, via `OnOffMotionBasedUrlFramePuller(UrlFramePuller)`. **This is worth a ticket.** The non-motion hikcentral path was migrated to `AvUrlFramePuller` but the motion-gated path was not. [[hikcentral-components|Hikcentral]] is a real-traffic VMS ([[hikcentral-components|HikCentral]] Pro) and the on/off motion behaviour is the load-saver on dense sites. This split means a single integration runs two different decoders depending on a config flag, which complicates hwaccel rollout, frame-timestamp semantics, and debugging.

**Non-live decoders that are intentional:**
- `MilestoneJpgFramePuller` — Milestone's JPEG-over-XML proprietary stream is not [[rtsp-deep-dive|RTSP]]. [[opencv-entity|OpenCV]] `cv2.imdecode` on JPEG bytes is the right tool; [[pyav-entity|PyAV]] would not help.
- `OrchidJpgFrameQueuePuller` — Orchid does not expose [[rtsp-deep-dive|RTSP]] from our customer base; HTTP JPEG polling is the contract.
- `JpgFrameQueuePuller` (exacq JPEG stream) — exacq's HTTP [[mjpeg-and-still-image-formats|MJPEG]] stream path is JPEG-per-frame; [[opencv-entity|OpenCV]] decode is correct. The exacq [[rtsp-deep-dive|RTSP]] video-stream path uses [[pyav-entity|PyAV]].
- `VideoQueueFramePuller` (SMTP/ajax) — local MP4 staged from SMTP attachment; [[opencv-entity|cv2.VideoCapture]] on a finite file is fine.
- `S3FramePuller` (video/robo) — S3-staged clip; same reasoning as VideoQueue.
- `KVSFramePuller` — wraps [[kvs-components|KVS]] GetMedia/[[hls-and-dash|HLS]] into a [[pyav-entity|PyAV]] decode; KVS-specific transport but [[pyav-entity|PyAV]] under the hood.
- `SocketPuller` (star4live) — Star4Live SDK is a vendor sidecar that pipes raw frames to a Unix socket. [[opencv-entity|cv2]] decoding from the pipe is the contract.
- `AutopatrolWebSocketStreamPuller` — subclasses `AvUrlFramePuller` and feeds fMP4 chunks from the websocket into PyAV. Already on the new path.

**The [[gstreamer-entity|GStreamer]] `GstUrlFramePuller` is unused.** It exists in `actuate-pullers` (`actuate_pullers/url/gst_url_puller.py`) and is gated behind a `try/except` import (`actuate_pullers/__init__.py:18`) so missing [[gstreamer-entity|GStreamer]] doesn't break the package, but **no integration in vms-connector calls it**. The [[h264-deep-dive|H.264]]-only limitation noted in scout context never materialised as production debt because the migration target was PyAV, not [[gstreamer-entity|GStreamer]]. Deleting it from `actuate-pullers` is a tidy follow-up — but low priority while it's quietly behind a feature gate.

## Recommendations

1. **Migrate hikcentral's motion path off `OnOffMotionBasedUrlFramePuller`** — port the on/off motion gating to a [[pyav-entity|PyAV]]-based motion puller (`MotionBasedAvUrlFramePuller` already exists for the always-on motion case). Worth a ticket. Owner: connector. Risk: motion-gating semantics need behavioural parity testing on a [[hikcentral-components|HikCentral]] test site.
2. **Decide the fate of `GstUrlFramePuller`** — either delete it from `actuate-pullers` (it adds dependency surface for a code path no caller uses) or commit to using it for a hwaccel scenario [[pyav-entity|PyAV]] can't cover (e.g. embedded ARM where v4l2m2m via [[pyav-entity|PyAV]] proves unstable). No current production driver.
3. **Decide the fate of `connector_factories/sqs_video/`** — the factory is body-commented and has no `integration_type` branch. Either delete it, or wire a real "sqs_video" branch and resurrect `SqsPuller`. Today it is dead-code clutter that confuses code search.
4. **Document the JPEG-vs-[[rtsp-deep-dive|RTSP]] runtime branch in `exacq_camera.py:90-103`** — exacq's puller switches on `customer.use_video_stream` between [[pyav-entity|PyAV]] ([[rtsp-deep-dive|RTSP]]) and `JpgFrameQueuePuller`. Add a note to [[integrations/exacq/_summary]] so future debugging knows which decode path a given site is on without re-reading source.
5. **Consider hwaccel rollout per integration** — now that 16/22 integrations are on [[pyav-entity|PyAV]], [[hardware-accelerated-codecs|NVDEC]]/[[hardware-accelerated-codecs|VAAPI]] rollout via `customer.hw_accel` config can be staged per integration. [[rtsp-deep-dive|RTSP]] / digital_watchdog / avigilon / hikcentral (default branch) are highest-value first targets given camera count.

## Cross-references

- [[actuate-frame-ingest-decode-paths]] — the broader frame-ingest synthesis this note operationalises
- [[2026-04-27_frame-transport-payload-formats]] — sibling note on transport/container per integration
- [[pyav-entity]] — [[pyav-entity|PyAV]] decoder entity
- [[opencv-entity]] — [[opencv-entity|OpenCV]] decoder entity
- [[gstreamer-entity]] — [[gstreamer-entity|GStreamer]] (unused in connector; documented for completeness)
- [[aws-kvs-entity]] — KVS-specific transport
- [[cv2-videocapture-internals]] — [[opencv-entity|cv2.VideoCapture]] internals (relevant for legacy `UrlFramePuller`, SocketPuller, S3, VideoQueue)
- [[frame-extraction-strategies]] — overarching frame-extraction concept note
- [[vms-connector/_summary]] — connector topic summary
- [[actuate-libraries/_summary]] — libraries (and `actuate-pullers`) topic summary
- [[integrations/milestone/_summary]] — Milestone proprietary protocol note
- [[integrations/orchid/_summary]] — Orchid HTTP JPEG polling
- [[integrations/exacq/_summary]] — Exacq [[rtsp-deep-dive|RTSP]]-vs-JPEG branch
- [[integrations/hikcentral/_summary]] — [[hikcentral-components|HikCentral]] integration
- [[integrations/autopatrol-integration/_summary]] / [[integrations/vch/_summary]] — Immix WebSocket fMP4 transport
- [[integrations/kvs/_summary]] — [[aws-kvs-entity|AWS KVS]] integration
- [[integrations/eagle-eye/_summary]] — Eagle Eye HTTP preview
- [[integrations/digital-watchdog/_summary]], [[integrations/avigilon/_summary]], [[integrations/genetec/_summary]], [[integrations/luxriot/_summary]], [[integrations/openeye/_summary]], [[integrations/salient/_summary]], [[integrations/video-insight/_summary]], [[integrations/rtsp/_summary]], [[integrations/adpro/_summary]] — RTSP-family integrations now on [[pyav-entity|PyAV]]
