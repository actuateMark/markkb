---
title: AV1 / VP9 — The Future We're Not in Yet
type: concept
topic: video-processing
tags: [codec, av1, vp9, aomedia, future]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/engineering-process/notes/syntheses/2026-04-21_rd-agent-pilot-learnings.md
  - topics/fleet-architecture/notes/concepts/frame-storage-current-state.md
  - topics/personal-notes/notes/daily/2026-04-27.md
  - topics/video-processing/_summary.md
  - topics/video-processing/notes/concepts/codecs-overview.md
  - topics/video-processing/notes/concepts/containers-overview.md
  - topics/video-processing/notes/concepts/eks-prod-node-pool-gpu-availability.md
  - topics/video-processing/notes/concepts/gst-rtsp-h264-only-audit.md
  - topics/video-processing/notes/concepts/h265-hevc-deep-dive.md
  - topics/video-processing/notes/concepts/hardware-accelerated-codecs.md
incoming_updated: 2026-05-01
---

# AV1 / VP9 — The Future We're Not in Yet

**VP9** (Google, 2013) and **AV1** (AOMedia, 2018) are the royalty-free counter-[[codecs-overview|codecs]] to [[h264-deep-dive|H.264]] and [[h265-hevc-deep-dive|H.265]]. They exist primarily because the [[h265-hevc-deep-dive|H.265]] patent thicket made the streaming and browser industries unwilling to lock themselves into another paid royalty regime. AV1 in particular is a consortium product: Google + Netflix + Amazon + Apple + Microsoft + Cisco + NVIDIA + AMD + Intel formed AOMedia explicitly to ship a "next-generation codec we all agree to never sue each other over."

For Actuate, neither matters in production today. This note explains why, and when that might change.

## VP9, briefly

VP9 is the successor to VP8 (Google, 2010, ex-On2). Roughly [[h265-hevc-deep-dive|H.265]]-class compression efficiency at notably higher encoder cost, and with a much narrower ecosystem. Used at scale by:

- **YouTube** — VP9 is YouTube's primary delivery codec for high-resolution non-AV1 content
- **Some Android camera apps** — for the same "no royalties" reason
- **WebM** ([[containers-overview|see containers overview]]) is the WebM-restricted MKV container holding VP9

VP9 in surveillance: effectively zero. We've never seen a camera output it. Treat VP9 as "supported by [[ffmpeg-entity|ffmpeg]]'s `libvpx` and `vp9` decoders if a stream ever arrives, otherwise irrelevant."

## AV1: what's interesting

AV1's compression efficiency is roughly 30% better than [[h265-hevc-deep-dive|H.265]] at equivalent quality (industry consensus from formal subjective tests; the precise number depends on content). Architecturally it shares [[h265-hevc-deep-dive|H.265]]'s spirit — quadtree partitioning, larger blocks, more directional prediction modes — and pushes further: 128×128 superblocks, 56 directional intra modes, more flexible transform shapes, a learned-codec-style emphasis on quality at low bitrates.

The **encoder cost** has been the deployment bottleneck. The reference encoder (`libaom` / `aom-av1`) is ~50–100× slower than `x264` at comparable settings — unworkable for live encode. **SVT-AV1** (Intel-led, in libavcodec) has changed this dramatically: it's now within ~3–5× of x265 for live use cases at scale. Hardware encoders (NVIDIA Ada, Intel Arc, AMD RDNA3) have closed the gap further for newer silicon.

The **decoder** is in much better shape: `dav1d` (VideoLAN-led) is fast enough that software AV1 decode at 1080p is comfortable on any modern x86 core. Hardware decode is now widespread (NVIDIA Ampere+, Intel Tiger Lake+, AMD Navi 21+, Apple M3+). See [[hardware-accelerated-codecs]] for what's available on our EC2 substrate.

## Why neither matters for surveillance today

Three structural reasons:

1. **Camera firmware doesn't ship AV1 / VP9.** SoC vendors (HiSilicon, Ambarella, Novatek) sell [[h264-deep-dive|H.264]]/[[h265-hevc-deep-dive|H.265]] IP and gate-level encoders; AV1 encoder IP is just starting to appear and not yet in the camera-class price band. Until cameras emit it, we don't ingest it.
2. **VMS / cloud sides aren't asking.** Genetec, Milestone, Avigilon, Eagle Eye — none default to AV1. Cloud-VMS partners may eventually for delivery (browser side), but their camera-ingestion side remains [[h264-deep-dive|H.264]]/[[h265-hevc-deep-dive|H.265]].
3. **Decoder install-base is fine on our side, but worthless without producers.** We have the hardware to decode AV1 on G5/G6/L4 nodes; nobody is sending it.

The corollary: **AV1 won't matter for our ingestion path until cameras ship it**, which is a 5+ year horizon for any meaningful share. Watch the SoC vendors, not the standards bodies.

## Where AV1 / VP9 *could* matter for Actuate

Three places:

**(1) [[aws-kvs-entity|AWS KVS]] [[webrtc-deep-dive|WebRTC]] / [[aws-ivs-entity|AWS IVS]] Real-Time** — these services use [[webrtc-deep-dive|WebRTC]], which now negotiates AV1 alongside [[h264-deep-dive|H.264]] and VP9 in the SDP offer. If we ever build a low-latency live-preview path on [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] (a recurring strategic question), we may end up *receiving* AV1 from the browser side, even though we send [[h264-deep-dive|H.264]] from the camera side. Decoder availability in our pull/inference path then becomes a practical concern. See [[webrtc-deep-dive]] and [[aws-kvs-entity]].

**(2) Partner cloud platforms.** Some cloud-VMS partners (Eagle Eye, Verkada, Avigilon Cloud) may move their delivery codec to AV1 for their browser players, decoupled from camera-ingestion codec. Our integrations consume their API streams; if a partner's API delivers AV1, we need to decode it. So far this hasn't happened.

**(3) Storage cost reduction (theoretical).** Re-encoding our JPEG-everywhere detection-frame storage ([[mjpeg-and-still-image-formats]]) into AVIF (AV1's still-image profile) would reduce S3 footprint substantially. But we'd lose the universal-decoder convenience of JPEG, and AVIF encode cost is still high. No production motion in this direction; mention only because it surfaces in cost-reduction conversations.

## Decoder support in Actuate

The `HW_DECODERS` table at `actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py:24-77` already lists AV1 and VP8/VP9 mappings (`av1_cuvid` for NVIDIA, `vp9_cuvid`, `vp8_cuvid`, plus the corresponding [[hardware-accelerated-codecs|VAAPI]] / [[hardware-accelerated-codecs|VideoToolbox]] / AMF / mediacodec / v4l2m2m variants). This is "ready if needed" plumbing — the table is populated based on what libavcodec advertises, not because we currently encounter these [[codecs-overview|codecs]] in production.

[[pyav-entity|PyAV]]'s libavformat / libavcodec wrapper handles AV1 demux + decode without any Actuate-specific code; the same `av.open(url)` path used for [[h264-deep-dive|H.264]] would handle AV1 if a stream advertised it.

## What to watch for as adoption shifts

- **NVIDIA driver release notes** for AV1 [[hardware-accelerated-codecs|NVENC]] / [[hardware-accelerated-codecs|NVDEC]] matrix updates — affects our G5/G6/L4 capacity
- **Camera-firmware release notes** from Hikvision, Hanwha, Bosch, Axis — first AV1-emitting camera is the surveillance-industry signal
- **Intel SVT-AV1 release cadence** — encoder maturity for any future Actuate-side encode
- **[[webrtc-deep-dive|WebRTC]] SDP negotiation defaults** — already AV1-capable in Chrome and Firefox; uptake on the publish side will depend on broadcaster and SFU support
- **AOMedia / MPEG-LA AV1 patent claims** — Sisvel formed an AV1 patent pool in 2020 contending royalties are owed despite AOMedia's claims of cleanness. So far this has not chilled adoption, but it's the same pattern that hurt [[h265-hevc-deep-dive|H.265]].

## Reading-list pointers

The encoder/decoder libraries themselves — **SVT-AV1**, **dav1d**, **aom-av1** — are cataloged in [[reading-list]]. Worth a deeper read if/when AV1 enters our ingestion path. **VVC / H.266** is also in the reading list as the *next* codec after [[h265-hevc-deep-dive|HEVC]]; effectively zero production deployment, even less surveillance-relevant than AV1.

## Actuate touchpoints

**AV1 / VP9 are not used in Actuate production today.** The decoder plumbing is in place via libavcodec, but no ingested stream currently uses these [[codecs-overview|codecs]].

Potential applications:

- [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] live-preview path (if pursued) — may negotiate AV1 in browser-side SDP. See [[webrtc-deep-dive]], [[aws-kvs-entity]].
- Future cloud-VMS partner integrations whose delivery codec moves to AV1.
- AVIF as a JPEG replacement for detection-frame storage (cost-driven, hypothetical) — see [[mjpeg-and-still-image-formats]].

Decoder mapping table (latent capability) — `actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py:24-77` (`HW_DECODERS`).

Cross-references: [[codecs-overview]], [[hardware-accelerated-codecs]], [[reading-list]].
