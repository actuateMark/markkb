---
title: "GStreamer RTSP H.264-only Silent Failure Audit"
type: concept
topic: video-processing
tags: [gstreamer, rtsp, h265, silent-failure, audit, follow-up]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
---

# [[gstreamer-entity|GStreamer]] [[rtsp-deep-dive|RTSP]] [[h264-deep-dive|H.264]]-only Silent Failure Audit

## Summary

The `GStreamerInputPipeline` at `/home/mork/work/actuate-libraries/actuate-pullers/src/actuate_pullers/gstreamer/gstreamer_input_pipeline.py:86-101` builds the [[rtsp-deep-dive|RTSP]] path with a **hard-coded [[h264-deep-dive|H.264]] element chain** (`rtspsrc ! rtph264depay ! h264parse ! avdec_h264`). An [[h265-hevc-deep-dive|H.265]] / [[h265-hevc-deep-dive|HEVC]] [[rtsp-deep-dive|RTSP]] stream fed through this pipeline would fail to negotiate caps and produce zero frames, with no exception bubbling up to the puller — the [[gstreamer-entity|GStreamer]] bus would log a pipeline error inside the library's logger and the puller's frame queue would simply stay empty.

**Headline finding: zero production exposure today.** No connector code path instantiates `GstUrlFramePuller`. The class is exported from the puller library (`actuate_pullers/__init__.py:18-20`, behind a `try/except ImportError`) but no `camera/*/*_camera.py` module imports it; every RTSP-bearing integration uses `AvUrlFramePuller` ([[pyav-entity|PyAV]]) or `OnOffMotionBasedUrlFramePuller` ([[opencv-entity|OpenCV]]). The risk surface is therefore **latent / future-deploy**, not currently bleeding. See [[actuate-frame-ingest-decode-paths]] for the parallel decode paths in the connector.

## Affected integration_types

The factory dispatch in `/home/mork/work/vms-connector/connector_factories/shared/factory.py:60-107` routes 20+ `integration_type` values to per-VMS factory classes; each ultimately constructs a camera from `camera/<vms>/<vms>_camera.py`. Audited every camera module's puller imports:

- **[[pyav-entity|PyAV]] (`AvUrlFramePuller` / `MotionBasedAvUrlFramePuller`):** `rtsp`, `milestone_rtsp`, `adpro`, `digital_watchdog`, `salient`, `avigilon`, `video_insight`, `luxriot`, `genetec`, `exacq`, `openeye`, `eagle_eye`, `eagle_eye_v3`, `hikcentral` (+ `GenesisUrlFramePuller` and `WebcamFramePuller` for special cases on the `rtsp` path).
- **[[opencv-entity|OpenCV]] via `OnOffMotionBasedUrlFramePuller`:** `hikcentral` (motion-gated branch).
- **Proprietary / non-[[rtsp-deep-dive|RTSP]]:** `milestone` (`MilestoneJpgFramePuller`), `orchid` (`OrchidJpgFrameQueuePuller`), `star4live` (`SocketPuller`), `video` (`S3FramePuller`), `vch`/`autopatrol` (`AutopatrolWebSocketStreamPuller` over fMP4/WSS), `SMTP_per_camera`/`ajax` (`VideoQueueFramePuller`), `kvs` (`KVSFramePuller`), patrol mode (`WebcamFramePuller` or delayed `AvUrlFramePuller` at `camera/patrol/patrol_camera.py:82`).

`grep -rn "GstUrlFramePuller" /home/mork/work/vms-connector --include='*.py'` returns **only** matches under `.venv/`. Same for `gst_url_puller`. No factory, no camera, no site manager imports it.

The only [[gstreamer-entity|GStreamer]]-using puller in production is `KVSFramePuller`, with its own codec-agnostic pipeline (`appsrc ! matroskademux ! decodebin ! videoconvert ! jpegenc ! appsink`) — `decodebin` autoplugs codec, so [[kvs-components|KVS]] does *not* share this [[h264-deep-dive|H.264]] trap.

## Camera headcount estimate

Since no production cameras route to `GstUrlFramePuller`, the affected camera count is **zero today**. For completeness, if someone *did* wire it into an integration, the order-of-magnitude exposure varies sharply:

- Wiring it into `rtsp` / `milestone_rtsp` / `adpro` would expose **the largest fleet** (generic [[rtsp-deep-dive|RTSP]] is the catch-all integration; thousands of cameras across small/mid customers).
- Wiring into `hikcentral`, `genetec`, or modern `avigilon` would expose **hundreds to low thousands** with a meaningfully high [[h265-hevc-deep-dive|H.265]] prevalence.
- Wiring into `eagle_eye_v3`, `dw`, `salient`, `luxriot`, `video_insight`, `exacq`, `openeye` — typically dozens to low hundreds per integration.

Real counts come from `admin-api` Postgres: `SELECT integration_type, COUNT(*) FROM camera JOIN site ON ... WHERE active = true GROUP BY 1`. NRQL alternative: `SELECT uniqueCount(camera_name) FROM Metric WHERE cluster_name = 'Connector-EKS' FACET integration_type SINCE 1 day ago`.

## [[h265-hevc-deep-dive|H.265]] exposure on [[rtsp-deep-dive|RTSP]] integrations

Industry baseline as of 2026: [[h265-hevc-deep-dive|H.265]] / [[h265-hevc-deep-dive|HEVC]] is the **default codec on most cameras shipped after ~2020**. Specifically on integrations the connector commonly speaks to:

- **Hikvision / [[hikcentral-components|HikCentral]]** — HEVC ("[[h265-hevc-deep-dive|H.265]]+") is the default for all current Hikvision IP cameras, and the Hikvision-derived rebrand fleet (LTS, Honeywell mid-tier, many ODM brands) ships the same default.
- **Avigilon** — HEVC standard on H5A-era and newer; [[h264-deep-dive|H.264]] still configurable but not the default.
- **Genetec / Omnicast** — codec is camera-driven, not VMS-driven; the fleet skews HEVC for newer deployments.
- **Eagle Eye Networks** — bridge transcodes; outbound stream is typically [[h264-deep-dive|H.264]] but newer V3 paths can pass through HEVC.
- **Digital Watchdog / Salient / Luxriot / Exacq / OpenEye / [[video-insight-components|Video Insight]]** — same camera-driven story; on premise [[h265-hevc-deep-dive|H.265]] share is high and growing.

So if `GstUrlFramePuller` *were* wired into any of the modern-VMS integrations, the [[h265-hevc-deep-dive|H.265]] silent-failure share would be substantial (50%+ for [[hikcentral-components|HikCentral]]/Avigilon, lower elsewhere). See [[h265-hevc-deep-dive]] and [[rtsp-deep-dive]] for codec details.

## Detection signature

If a deploy started routing some integration through `GstUrlFramePuller` against an [[h265-hevc-deep-dive|H.265]] stream, the failure mode would be:

1. `GStreamerInputPipeline.create_pipeline()` calls `Gst.parse_launch()` with the [[h264-deep-dive|H.264]] chain. Pipeline parses successfully (caps mismatch isn't checked at parse time).
2. State transitions to PLAYING. `rtspsrc` connects, [[rtsp-deep-dive|RTSP]] DESCRIBE returns SDP advertising `H265`, but `rtph264depay` rejects the buffer — caps negotiation fails.
3. The bus dispatches a `Gst.MessageType.ERROR` to `on_bus_message()` (line 109-117), which logs `"Pipeline error: ..."` at ERROR and quits the mainloop. The outer `start_streaming()` loop sleeps 5s and retries — same failure repeats.
4. **No frames ever reach `frame_callback`.** `submit_frame` and `tally_frame` never fire. Frame queue stays empty.
5. **Bandwidth would still tick** — `BandwidthTracker` lives in `BasePuller`, but `GstUrlFramePuller.__init__` (`actuate-libraries/actuate-pullers/src/actuate_pullers/url/gst_url_puller.py:11-62`) doesn't actually push bandwidth metrics through [[gstreamer-entity|GStreamer]]'s [[rtsp-deep-dive|RTSP]] bytecount, so even bandwidth would likely read zero. (Verify in `BasePuller`.) Either way, the visible NR signal is **frame-rate near zero and `actuate_metrics_dao.put_bandwidth` flatlining or near-zero**, not an exception count.
6. CloudWatch / NR `Errors` metric: zero — the [[gstreamer-entity|GStreamer]] error is absorbed by `logging.error` inside the library, not raised.

This is the **same class of failure as the AutoPatrol healthcheck early-return incident** (see [[2026-04-23_release-acceptance-criteria]]): "no errors, no frames, silent." Detection therefore must be a positive-presence check: NR `SELECT count(*) FROM Metric WHERE metricName LIKE 'frames_per_second%' AND integration_type = '<x>' SINCE 1 hour ago` per integration; alert when an integration's frame count drops to zero while invocation count is steady.

## Recommended fix

Two options:

**A — codec-agnostic pipeline (minimal patch).** Replace `rtph264depay ! h264parse ! avdec_h264` with `decodebin3`. ~5 lines in `gstreamer_input_pipeline.py:90` plus a parse-test against a synthetic [[h265-hevc-deep-dive|H.265]] [[rtsp-deep-dive|RTSP]] source. `decodebin3` autoplugs the right depay/parse/decode for [[h264-deep-dive|H.264]], [[h265-hevc-deep-dive|H.265]], [[av1-vp9-future|VP8]]/9, [[mjpeg-and-still-image-formats|MJPEG]]. See [[gstreamer-pipeline-model]].

**B — delete `GstUrlFramePuller` and `GStreamerInputPipeline`.** No production code instantiates them; any future [[rtsp-deep-dive|RTSP]] integration should reach for `AvUrlFramePuller` ([[pyav-entity]]) which already covers [[h264-deep-dive|H.264]]/[[h265-hevc-deep-dive|H.265]]/[[mjpeg-and-still-image-formats|MJPEG]] + hardware accel. Deprecation PR + library minor bump.

**Recommendation: B**, gated on confirming nothing outside `vms-connector` imports the class (e.g. `rtsp_camera_simulator`, internal R&D scripts).

## Open questions

- Does the `rtsp_camera_simulator` at `/home/mork/work/vms-connector/rtsp_camera_simulator/camera_simulator.py` use this puller? Cursory grep returned no hit, but worth a closer look before deletion.
- Is there an unmerged PR or feature branch wiring `GstUrlFramePuller` into a new integration as a "perf experiment"? Branch sweep needed.
- Is `KVSFramePuller`'s pipeline implicitly [[h264-deep-dive|H.264]]-biased anywhere downstream (jpegenc handles all [[codecs-overview|codecs]], but `decodebin` autoplugging may have its own issues — distinct audit).
- On the unrelated [[opencv-entity|OpenCV]] (`UrlFramePuller`) path used by `openeye` and `milestone_rtsp` motion-gating, is [[h265-hevc-deep-dive|H.265]] actually supported? `cv2.VideoCapture`'s codec coverage depends on the [[ffmpeg-entity|FFmpeg]] build packed into [[opencv-entity|OpenCV]] — could be a parallel silent-failure path. Track separately. See [[cv2-videocapture-internals]].

## Cross-links

[[gstreamer-entity]] · [[rtsp-deep-dive]] · [[h265-hevc-deep-dive]] · [[gstreamer-pipeline-model]] · [[pyav-entity]] · [[actuate-frame-ingest-decode-paths]] · [[vms-connector/_summary]]
