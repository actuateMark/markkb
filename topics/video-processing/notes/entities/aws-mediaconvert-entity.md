---
title: AWS Elemental MediaConvert
type: entity
topic: video-processing
tags: [aws, mediaconvert, transcoding, offline, hls, dash, hevc, av1]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/2026-04-27.md
  - topics/video-processing/_summary.md
  - topics/video-processing/notes/concepts/hls-and-dash.md
  - topics/video-processing/notes/concepts/immix-mp4-mux-downstream.md
  - topics/video-processing/notes/concepts/protocol-latency-comparison.md
  - topics/video-processing/notes/entities/aws-elemental-live-entity.md
  - topics/video-processing/notes/entities/aws-ivs-entity.md
  - topics/video-processing/notes/entities/aws-medialive-entity.md
  - topics/video-processing/notes/entities/aws-mediapackage-entity.md
  - topics/video-processing/notes/entities/ffmpeg-entity.md
incoming_updated: 2026-05-01
---

# AWS Elemental MediaConvert

## What it is

File-based ("offline" / non-real-time) video transcoding as a managed service. You drop an input file in S3, submit a JSON **job specification** describing inputs, output groups, codec settings, audio mappings, captions, and watermarks, and MediaConvert returns transcoded files (or [[hls-and-dash|HLS]]/[[hls-and-dash|DASH]] packages) in your output S3 bucket. The job runs on AWS-managed Elemental encoder fleet — no instances to provision.

It is the spiritual descendant of the on-prem AWS Elemental Server / Convoy encoders ([[aws-elemental-live-entity]] is the live cousin); the same Elemental codec stack runs underneath, exposed as a job API.

This is **not** a live encoder. For 24/7 channel encoding see [[aws-medialive-entity]].

## API surface

A MediaConvert job is one large JSON document submitted via `boto3.client("mediaconvert").create_job(...)`. The interesting parts of the schema:

- **Inputs** — list of S3 input files with optional input clipping (`InputClippings: [{StartTimecode, EndTimecode}]`), audio selectors, caption selectors, deinterlacing, image inserter overlays.
- **Output groups** — what's emitted. The five group types span almost every shipping format:
  - `FILE_GROUP_SETTINGS` — single MP4 / MOV / MXF / WebM files.
  - `HLS_GROUP_SETTINGS` — adaptive [[hls-and-dash|HLS]] bitrate ladder, segment duration, encryption (AES-128, SAMPLE-AES, SPEKE-DRM), [[aws-mediapackage-entity|MediaPackage]] handoff.
  - `DASH_ISO_GROUP_SETTINGS` — [[hls-and-dash|MPEG-DASH]] manifests + segments.
  - `MS_SMOOTH_GROUP_SETTINGS` — Microsoft Smooth Streaming (legacy).
  - `CMAF_GROUP_SETTINGS` — unified [[hls-and-dash|HLS]]+[[hls-and-dash|DASH]] via CMAF, with low-latency variants.
- **Codec settings** — [[h264-deep-dive|H.264]] (`H_264`), [[h265-hevc-deep-dive|H.265]] (`H_265`), [[av1-vp9-future|AV1]] (`AV1`), [[av1-vp9-future|VP9]], ProRes, MPEG-2, XAVC. Per-codec controls for rate-control mode (CBR / VBR / QVBR), [[gop-keyframe-fundamentals|GOP]] structure, B-frames, slices, tier/level.
- **Audio descriptions** — codec, bitrate, channel layout, language code per output.
- **Job templates / presets** — saved JSON fragments for outputs you reuse.
- **Queues** — on-demand vs reserved capacity. Reserved = predictable monthly cost, on-demand = per-minute pricing.

Endpoints are **per-account regional** (`describe_endpoints` resolves the endpoint URL); clients must be constructed with `endpoint_url=...` like [[kvs-components|KVS]] data clients.

## Pricing model

Per-minute-of-output-video, billed in tiers:

- **Basic tier** (≤ SD, simple [[codecs-overview|codecs]]).
- **Professional tier** (HD/UHD, [[h265-hevc-deep-dive|HEVC]]/[[av1-vp9-future|AV1]], advanced rate control, 10-bit, HDR).
- Modifiers for **frame-rate doubling** (60 fps → +50%), **multiple-pass encoding** (+50%), **audio-only** (cheap).

A 30-second 1080p [[h264-deep-dive|H.264]] clip transcoded to one MP4 is ~$0.015 in the professional tier. Doing 10 K such clips/day = ~$150/day. [[av1-vp9-future|AV1]] is ~3-4x more than [[h264-deep-dive|H.264]] per minute, [[h265-hevc-deep-dive|HEVC]] ~2x.

Reserved queues have flat hourly cost with implicit minute caps; predictable but you pay even when idle.

## When to reach for it

- ✅ **Clip-archive transcoding** — reformatting alert clips into per-partner codec/container/resolution combinations.
- ✅ **Format normalization** — partner sent us an XAVC clip, our UI player wants [[h264-deep-dive|H.264]] MP4.
- ✅ **Per-title encoding ladders** — generate the full [[hls-and-dash|HLS]] ladder for a clip-replay UI.
- ✅ **Deinterlacing legacy SD content** — MediaConvert deinterlace filters are quite good.
- ✅ Anywhere [[ffmpeg-entity|ffmpeg]]-on-EKS is your current answer but operational toil is the bottleneck — MediaConvert removes the queue + worker fleet.

## When not to reach for it

- Live / real-time / sub-30-second-latency encoding — that's [[aws-medialive-entity]] or in-process encoding.
- Tiny clips at huge volume — at low single-digit-second clips the per-minute pricing rounds up unfavorably and [[ffmpeg-entity|ffmpeg]]-in-Lambda is cheaper.
- Anything where you don't already have the input file in S3 — getting it there is its own cost / latency.

## Actuate touchpoints

**Not currently used.** No `mediaconvert` boto3 client invocations exist in `actuate-pullers`, `actuate-pipeline`, or `actuate-alarm-senders`.

There is one indirect lead worth tracking: the Immix `use_mp4=True` alert path. `actuate-libraries/actuate-alarm-senders/src/actuate_alarm_senders/immix/immix_alert_sender.py:88-100` enqueues `event_type`, `s3_folder`, and `attachment_frames` onto the `event_queue_immix_alarm.fifo` SQS queue. The actual MP4 muxing for that mode happens in a downstream consumer (likely a Lambda) that lives outside the libraries scout looked at. **If that downstream muxer is currently shelling out to [[ffmpeg-entity|ffmpeg]] or [[pyav-entity|PyAV]], MediaConvert is a plausible drop-in.** Worth confirming when the Immix MP4 pipeline gets its own KB note.

Plausible Actuate applications, in priority order:

1. **Per-partner clip assembly.** Some partners want [[h264-deep-dive|H.264]] baseline + AAC in MP4, some want [[h265-hevc-deep-dive|HEVC]], some want a specific frame rate. A MediaConvert job template per partner profile, fed from the existing S3 clip bucket, would replace bespoke [[ffmpeg-entity|ffmpeg]] invocations.
2. **Clip-replay UI [[hls-and-dash|HLS]] packaging** ([[actuate-clip-generation-flow]]). Today every alert frame is a JPEG in S3 (`actuate-libraries/actuate-frames/src/actuate_frames/save_frame_meta.py:43`); a clip-replay UI would need MP4 or [[hls-and-dash|HLS]], generated on demand or pre-rendered. MediaConvert + [[aws-mediapackage-entity]] is the canonical combo.
3. **Format-canonicalization on inbound SMTP/SMTP-attachment clips** (the `actuate-temp-smtp` bucket).

Referenced reading: AWS MediaConvert job specification docs ([[knowledgebase/topics/billing/reading-list]]), [[ffmpeg-entity]] for the in-house alternative.
