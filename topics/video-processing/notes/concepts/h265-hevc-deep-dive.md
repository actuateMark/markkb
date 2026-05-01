---
title: H.265 / HEVC Deep Dive
type: concept
topic: video-processing
tags: [codec, h265, hevc, surveillance, licensing]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/engineering-process/notes/syntheses/2026-04-21_rd-agent-pilot-learnings.md
  - topics/fleet-architecture/notes/concepts/frame-storage-current-state.md
  - topics/personal-notes/notes/daily/2026-04-27.md
  - topics/video-processing/_summary.md
  - topics/video-processing/notes/concepts/av1-vp9-future.md
  - topics/video-processing/notes/concepts/codecs-overview.md
  - topics/video-processing/notes/concepts/containers-overview.md
  - topics/video-processing/notes/concepts/eks-prod-node-pool-gpu-availability.md
  - topics/video-processing/notes/concepts/ffmpeg-command-anatomy.md
  - topics/video-processing/notes/concepts/ffmpeg-hardware-acceleration.md
incoming_updated: 2026-05-01
---

# H.265 / HEVC Deep Dive

H.265 / HEVC (ITU-T Rec. H.265, ISO/IEC 23008-2, finalized 2013) is the successor to [[h264-deep-dive|H.264/AVC]] and the practical "next codec" for surveillance video. The headline number is **~50% bitrate reduction at equivalent perceptual quality**, achieved through more flexible block partitioning, larger transform sizes, and improved intra prediction. The reason it didn't conquer surveillance the way [[h264-deep-dive|H.264]] did is not technical — it's the licensing situation, plus the higher decode cost.

## What's new architecturally

The biggest structural changes from [[h264-deep-dive|H.264]]:

**Coding Tree Unit (CTU) replaces the macroblock.** [[h264-deep-dive|H.264]] has 16×16 macroblocks, optionally subdivided to 4×4. H.265 has 64×64 CTUs that recursively split into 32×32, 16×16, 8×8 Coding Units (CUs) via a quadtree. Larger blocks compress smooth regions much better; finer subdivision still works in detailed regions. This single change drives most of the compression gain.

**Tiles and slices for parallelism.** [[h264-deep-dive|H.264]] already had slices; H.265 adds **tiles** — rectangular regions of CTUs that are independently decodable. Tiles enable wavefront / true parallel decode in a way slices can't. This is also the foundation of region-of-interest coding and 360°/VR delivery, which surveillance occasionally borrows.

**35 intra-prediction modes** vs [[h264-deep-dive|H.264]]'s 9 (or 4 for chroma). Better at directional structure (edges, gradients) common in real scenes. Improved intra coding is the biggest reason H.265 is useful for I-frame-heavy content like surveillance with frequent keyframes.

**Larger transforms** — up to 32×32 DCT-like transforms ([[h264-deep-dive|H.264]] capped at 8×8). Plus an integer DST for 4×4 intra residuals (better for high-frequency edge content).

**Improved deblocking + SAO (Sample Adaptive Offset).** SAO is a second post-filter after deblocking that reduces ringing at quantization boundaries. Real perceptual win; computational cost is non-trivial.

**Parameter set hierarchy.** [[h264-deep-dive|H.264]] has SPS + PPS. H.265 adds **VPS** (Video Parameter Set) above SPS. VPS describes the layered structure (scalability / multi-view), most surveillance streams have a single trivial VPS. Decoder still needs all three before it can decode.

The cumulative effect: the same scene at the same perceptual quality is roughly half the bitrate. A 4 Mbps [[h264-deep-dive|H.264]] stream becomes a 2 Mbps H.265 stream — meaningful for bandwidth-constrained sites with large camera counts.

## The patent thicket

[[h264-deep-dive|H.264]] had one royalty pool (MPEG-LA) that camera vendors learned to live with. H.265 has **at least three** royalty pools — MPEG-LA, HEVC Advance, and Velos Media — plus a long tail of patent holders who never joined any pool. Royalty caps differ, terms differ, and there is no single license that buys you patent peace. The fragmentation is widely understood as the proximate cause of H.265's slow adoption in browsers (Chrome added support reluctantly in 2023, only on hardware-decode-equipped devices) and consumer-product flows.

For surveillance specifically: most camera vendors do ship H.265 (the per-unit royalty isn't a deal-breaker on a $500 camera), but the **VMS / cloud** side is more cautious. AWS doesn't officially commit to HEVC support across all media services; we treat H.265 as a "we'll decode it if you send it" capability rather than a first-class encode target.

This matters strategically: the bandwidth savings are real, but transcoding **out of** H.265 (to [[h264-deep-dive|H.264]] for delivery, to JPEG for storage) costs CPU on our side, and re-encoding to H.265 ourselves opens licensing exposure we'd rather not invite. Practical posture: decode H.265 when cameras send it, never produce it.

## Why surveillance is moving slowly

1. **Decoder cost** — a software H.265 decode is roughly 2× the CPU of [[h264-deep-dive|H.264]]. Hardware decode is broadly available now ([[hardware-accelerated-codecs|NVDEC]] since Maxwell, [[hardware-accelerated-codecs|VAAPI]] on Skylake+, [[hardware-accelerated-codecs|VideoToolbox]] since A10) but the install base of older nodes still matters.
2. **Licensing uncertainty** — VMS vendors carry the cost / risk; cameras pass it through. This produces a "[[h264-deep-dive|H.264]] default, H.265 optional" posture across the industry.
3. **Marginal ROI** — for an N-camera site already provisioned for [[h264-deep-dive|H.264]] bandwidth, the upgrade-to-H.265 work is plumbing without an obvious user-visible benefit.
4. **First-frame latency penalty** — the keyframe-wait problem (below) is more acute with H.265 because of its more aggressive inter-frame dependencies.

What's nudging adoption: **4K cameras**. At 4K resolution [[h264-deep-dive|H.264]] starts to struggle (high bitrates, weak hardware encoders), and H.265's compression advantage becomes a deployment-cost rather than a "nice to have".

## Decoding H.265 in Actuate

The same [[pyav-entity|PyAV]] path used for [[h264-deep-dive|H.264]] handles H.265 — libavcodec `hevc` decoder via `av_url_puller.py`. There is **no special tuning** for H.265 beyond what's already in the per-hwaccel option dict; the puller treats it as a slightly-more-fragile [[h264-deep-dive|H.264]].

What is special:

**Explicit warning at `av_url_puller.py:910-913`** — when the puller detects an H.265 stream, it logs `"H265 in use, potential performance issues"`. This is a deliberate breadcrumb so on-call can correlate elevated CPU / decode-stall issues against H.265 cameras when the metric tail-fires.

**Keyframe-wait guard at `av_url_puller.py:1318-1335`** — the puller skips packets until the first keyframe arrives. The motivation is specifically H.265: corrupt non-IDR slices on an H.265 stream produce visually worse artifacts (full-frame ringing, color smearing) than the corresponding [[h264-deep-dive|H.264]] case, and the artifacts persist longer because H.265's larger reference range means more downstream frames inherit the corruption. Discarding packets until the first IDR avoids feeding the AI pipeline a frame full of garbage.

**Hardware decoder mapping** — H.265 → `hevc_cuvid` (NVIDIA), `hevc_videotoolbox` (macOS), `hevc_vaapi` (Intel/AMD Linux). Mapped in `HW_DECODERS` at `av_url_puller.py:24-77`. If the hwaccel is unavailable (`_detect_hardware_acceleration()`, see [[hardware-accelerated-codecs]]), we fall through to software decode, which is when the "potential performance issues" warning becomes operationally relevant.

## Hardware decoder availability matrix

Coarse picture as of 2026:

| Platform | H.265 decode | Notes |
|---|---|---|
| NVIDIA Maxwell+ | Yes | [[hardware-accelerated-codecs|NVDEC]]; full Main / Main10 |
| NVIDIA Ampere+ | Yes | Adds [[av1-vp9-future|AV1]] alongside |
| Intel Skylake+ | Yes (partial) | [[hardware-accelerated-codecs|QuickSync]] / [[hardware-accelerated-codecs|VAAPI]]; Main10 from Kaby Lake |
| AMD Polaris+ | Yes | AMF / [[hardware-accelerated-codecs|VAAPI]] |
| Apple A10+ | Yes | [[hardware-accelerated-codecs|VideoToolbox]] |
| Generic ARM SoCs | Mixed | Camera SoCs and Raspberry Pi vary; check per-chip |

EC2-side, our G5/G6/L4 substrate has full [[hardware-accelerated-codecs|NVDEC]] H.265 (and [[av1-vp9-future|AV1]] on L4). See [[hardware-accelerated-codecs]] for the EC2 / driver detail.

## Common gotchas

1. **Profile mismatch on hardware decode** — Main10 (10-bit) vs Main (8-bit) is a frequent mismatch source. Surveillance is overwhelmingly 8-bit; if a camera offers Main10 it's worth verifying we're getting Main.
2. **[[gop-keyframe-fundamentals|Keyframe interval]] too long** — some H.265 cameras default to GOPs of 60 (2s @ 30fps) or worse. Combined with the keyframe-wait guard, that's 2s of "no frames" on every reconnect. See [[gop-keyframe-fundamentals]].
3. **Parameter set fragility** — VPS/SPS/PPS is a longer chain than [[h264-deep-dive|H.264]]'s two; if any are missing/stale, decode is dead until the next refresh.
4. **Software decode CPU spikes** — when hwaccel falls through, H.265 software decode at 1080p30 can saturate a core. Watch for this pattern in logs around the H.265-warning line.

## Actuate touchpoints

- H.265 explicit warning — `actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py:910-913`
- Keyframe-wait guard (skip packets until first IDR) — `av_url_puller.py:1318-1335`
- HW decoder mapping (`hevc_cuvid` etc.) — `av_url_puller.py:24-77`
- Per-hwaccel options / no special H.265 tuning — `av_url_puller.py:412-494`
- Cross-topic: [[hardware-accelerated-codecs]], [[h264-deep-dive]], [[gop-keyframe-fundamentals]], [[reading-list]] for x265 / openHEVC encoder/decoder reference.
