---
title: AWS Elemental MediaLive
type: entity
topic: video-processing
tags: [aws, medialive, live, encoding, channels, broadcast, statmux]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/2026-04-27.md
  - topics/video-processing/_summary.md
  - topics/video-processing/notes/concepts/mpeg-ts-over-udp.md
  - topics/video-processing/notes/entities/aws-elemental-live-entity.md
  - topics/video-processing/notes/entities/aws-ivs-entity.md
  - topics/video-processing/notes/entities/aws-mediaconvert-entity.md
  - topics/video-processing/notes/syntheses/actuate-build-vs-buy-tradeoffs.md
  - topics/video-processing/notes/syntheses/aws-video-services-decision-matrix.md
incoming_updated: 2026-05-01
---

# AWS Elemental MediaLive

## What it is

Live linear video encoding as a managed service — i.e. broadcast-grade 24/7 channel encoding. You configure a "channel" with one or more **inputs** and one or more **output groups**, and MediaLive runs a pair of redundant encoder pipelines that take live source video and emit live output streams. It is the cloud descendant of the on-prem [[aws-elemental-live-entity|AWS Elemental Live]] ([[aws-elemental-live-entity]]) appliance — same encoder family, exposed as an API with cloud auto-scaling.

Where [[aws-mediaconvert-entity]] is for files, MediaLive is for **continuous live streams**. Channels are billed by the hour they are running.

## API surface

The mental model: Inputs → Channel → Output Groups.

**Inputs** (the live source feeds): MediaLive accepts a wide range of contribution formats, more than any other AWS service.

- `RTP_PUSH` — RTP/UDP push; partner pushes to a MediaLive endpoint.
- `RTMP_PUSH`, `RTMP_PULL` — [[rtmp-and-srt|RTMP]] in either direction.
- `URL_PULL` — pull from an HTTP/HTTPS URL ([[hls-and-dash|HLS]], MP4, etc).
- `MP4_FILE` — loop a static file (useful for filler / standby).
- `MEDIACONNECT` — pull from an [[aws-mediaconnect-entity]] flow (the supported way to do contribution-grade transport into AWS).
- `INPUT_DEVICE` — physical Elemental Link hardware device deployed at the source site.
- `AWS_CDI` — Cloud Digital Interface (uncompressed-grade contribution within a placement group).
- `MULTICAST` — UDP multicast inside a VPC.
- `SMPTE_2110_RECEIVER_GROUP` — broadcast-IP standard.
- `SRT_CALLER` — Secure Reliable Transport (caller mode), the modern open replacement for [[rtmp-and-srt|RTMP]].

**Channel** — the encoding job itself. Two redundant pipelines (for failover), input switching, audio selectors, caption selectors, frame-capture intervals, motion-compensated frame-rate conversion, ad markers (SCTE-35), graphics overlays.

**Output groups**:

- `HLS` — directly to S3 / [[aws-mediapackage-entity|MediaPackage]] / MediaStore / Akamai etc.
- `MS_SMOOTH` — legacy.
- `RTMP` — push to YouTube / Twitch / Facebook / partner ingest endpoint.
- `RTMP_GROUP` — multi-bitrate [[rtmp-and-srt|RTMP]] variants.
- `UDP` — [[mpeg-ts-over-udp|MPEG-TS over UDP]] (broadcast workflows).
- `MEDIAPACKAGE` — direct hand-off to [[aws-mediapackage-entity]] for downstream packaging.
- `ARCHIVE` — segmented MP4/TS files to S3.
- `FRAME_CAPTURE` — periodic still images (a low-rent Rekognition pipeline, basically).
- `CMAF_INGEST` — CMAF push to a [[aws-mediapackage-entity|MediaPackage]] v2 channel.

**Statistical multiplexing (statmux)** — a separate sub-feature where multiple channels share an aggregate bitrate budget and steal capacity from each other based on scene complexity. Used in broadcast multiplexes (DVB / ATSC packaging). Effectively never relevant outside broadcast.

`boto3.client("medialive")` is the API surface, with the usual `create_channel` / `start_channel` / `stop_channel` / `delete_channel` / `update_channel_class` lifecycle.

## Pricing model

- **Per channel-hour**, by **input resolution + codec tier + channel class**:
  - Single-pipeline (`SINGLE_PIPELINE`) vs Standard (`STANDARD`, redundant) channels — Standard is ~2x.
  - SD / HD / UHD tiers.
  - [[h264-deep-dive|AVC]] vs [[h265-hevc-deep-dive|HEVC]] vs MPEG-2.
  - ~$1.50/hr for a tiny SD [[h264-deep-dive|AVC]] single-pipeline channel up to ~$30+/hr for UHD [[h265-hevc-deep-dive|HEVC]] standard.
- **Idle is not free** — a stopped channel costs nothing, a running channel with no input still bills.
- Per-minute input / output transfer charges are usually trivial relative to channel-hour cost.

A 24/7 single HD-AVC standard channel runs ~$5-8/hr → ~$3-5K/month per channel. This is the cost shape that kills MediaLive for surveillance use cases.

## When to reach for it

- ✅ Contribution-grade live encoding for a broadcast / live-event workflow.
- ✅ You need redundant pipelines, SCTE-35 ad-marker preservation, and SLA-grade uptime on a small number of channels.
- ✅ You're ingesting partner contribution feeds via [[rtmp-and-srt|SRT]] or MediaConnect and need transcode + transmux to [[hls-and-dash|HLS]]/[[hls-and-dash|DASH]].
- ✅ Re-streaming to YouTube / Twitch / Facebook simultaneously.

## When not to reach for it

- ❌ Surveillance / IoT / many-low-bitrate streams. The per-channel-hour pricing assumes one channel = one premium broadcast feed; it is wildly wrong for hundreds-of-cameras-at-low-bitrate workloads.
- ❌ Sub-second latency needs — MediaLive [[hls-and-dash|HLS]] output is multi-second by design. Use [[aws-ivs-entity]] Real-Time or [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]].
- ❌ File-based work — that's [[aws-mediaconvert-entity]].

## Actuate touchpoints

**Not used.** No `medialive` boto3 client invocations anywhere in the actuate-libraries scout (`actuate-pullers`, `actuate-pipeline`, `actuate-alarm-senders`).

MediaLive is **over-engineered for our problem shape**. Actuate's frame ingest is dominated by 5-30 fps surveillance feeds — we do not need contribution-grade redundancy, broadcast IP transport, statmux, or SCTE-35. The economics are wrong: a fleet running thousands of camera streams at a few-hundred-kbps each cannot afford ~$5/hr/channel.

The plausible Actuate scenarios where MediaLive *might* enter the picture are narrow:

1. A future "monitoring-center situation room" UI that shows a small curated set (≤10) of premium customer feeds with broadcast-grade reliability.
2. A partner that requires us to publish back into their broadcast-style ingest ([[rtmp-and-srt|RTMP]] / [[rtmp-and-srt|SRT]] / MediaConnect) — MediaLive would be the delivery side, not the ingest.

Neither of these is on any current roadmap. Default verdict: **skip**, and revisit only if the broadcast-style monitoring product becomes real.

For everything live-ish today ([[rtsp-deep-dive|RTSP]] from cameras → decode → infer), the right primitive is [[gstreamer-entity]] / [[ffmpeg-entity]] in-pod, not MediaLive. See [[aws-video-services-decision-matrix]] for the side-by-side.
