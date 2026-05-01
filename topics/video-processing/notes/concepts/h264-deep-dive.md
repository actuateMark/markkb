---
title: H.264 / AVC Deep Dive
type: concept
topic: video-processing
tags: [codec, h264, avc, nal, surveillance]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/camera-health-monitoring/notes/syntheses/chm-phase2-stream-probe.md
  - topics/fleet-architecture/notes/concepts/frame-storage-current-state.md
  - topics/fleet-architecture/notes/syntheses/2026-04-22_frame-storage-design-deltas.md
  - topics/integrations/rtsp/notes/entities/rtsp-components.md
  - topics/personal-notes/notes/daily/2026-04-27.md
  - topics/video-processing/_summary.md
  - topics/video-processing/notes/concepts/av1-vp9-future.md
  - topics/video-processing/notes/concepts/codecs-overview.md
  - topics/video-processing/notes/concepts/connector-decoder-routing-map.md
  - topics/video-processing/notes/concepts/containers-overview.md
incoming_updated: 2026-05-01
---

# H.264 / AVC Deep Dive

H.264 (a.k.a. AVC, MPEG-4 Part 10, ITU-T Rec. H.264) is the **default codec of the surveillance industry** and the overwhelming majority of what Actuate decodes. Standardized in 2003, it sits in a sweet spot of compression efficiency, decoder ubiquity, hardware-accel coverage, and (post-2013-ish) stable patent licensing. Every IP camera made in the last decade can output it; every consumer device, browser, and SoC can decode it; nothing else in the surveillance space comes close to its install-base inertia.

## Bitstream model: NAL units

The H.264 bitstream is a sequence of **NAL units** (Network Abstraction Layer). Each NAL unit has a 1-byte header indicating its type and a payload. The two delivery formats:

- **Annex-B / byte-stream** — NAL units separated by `0x000001` or `0x00000001` start codes. Used by RTP ([[rtsp-deep-dive|RTSP]] transports), [[mpeg-ts-over-udp|MPEG-TS]], raw `.h264` files, anything that needs to be self-synchronizing.
- **AVCC / length-prefixed** — each NAL unit prefixed by a 4-byte length. Used in MP4 / fMP4 (`avcC` configuration box carries the SPS/PPS out-of-band).

Conversion between the two is a packing-only operation, no re-encode required. Many libavformat bugs and integration-layer surprises trace back to this dichotomy — code that assumes one format hits a stream in the other.

NAL unit types you'll encounter when debugging:

| Type | Name | Purpose |
|---|---|---|
| 1 | Non-IDR slice | P/B-frame slice |
| 5 | IDR slice | Keyframe slice (I-frame that breaks all reference chains) |
| 6 | SEI | Supplemental Enhancement Info — captioning, picture timing, user data |
| 7 | SPS | Sequence Parameter Set |
| 8 | PPS | Picture Parameter Set |
| 9 | Access Unit Delimiter | Frame boundary marker |

## Parameter sets: SPS and PPS

The **SPS** (Sequence Parameter Set) carries stream-wide configuration: resolution, profile/level, bit depth, chroma format (typically 4:2:0), max reference frame count. The **PPS** (Picture Parameter Set) carries picture-coding choices: entropy coding mode (CAVLC vs CABAC), deblocking filter params, slice group config.

The decoder cannot decode a single VCL NAL unit without knowing the SPS and PPS that govern it. In Annex-B streams these are sent in-band, periodically, and refreshed at every IDR (typical setting). In AVCC streams (MP4/fMP4) they live in the `avcC` box at container init.

This matters in practice when a stream is joined mid-flight ([[rtsp-deep-dive|RTSP]] reconnect, fMP4 fragment skip): until SPS/PPS arrive, no decode is possible — slices arrive but are dropped. This is one reason [[rtsp-deep-dive|RTSP]] servers often send an out-of-band SPS/PPS in the SDP `sprop-parameter-sets` field, which `actuate-pullers` and other pull paths must propagate to the decoder context.

## Profiles and levels

A **profile** is a feature subset. A **level** is a resource bound (max resolution, bitrate, decoded picture buffer size).

- **Baseline** — no B-frames, no CABAC. Designed for low-power devices. Mostly historical now; some legacy cameras still emit it.
- **Main** — adds B-frames and CABAC. Common in older cameras.
- **High** — adds 8×8 transforms, monochrome support, custom quant matrices. Default for modern cameras and BD-Video.

Profile mismatch is the #1 reason a hardware decoder rejects a stream that software decode handles fine. [[hardware-accelerated-codecs|NVDEC]], for instance, has tightened constraints on Main vs. High streams across driver versions — we've seen field reports where a stream worked on driver N and refused on N+1 for what looks like a profile-edge issue.

## I/P/B frames and slice types

- **I-frame (intra)** — coded without reference to other frames. **IDR I-frame** additionally invalidates all prior reference buffers — required entry point for clean stream join.
- **P-frame (predictive)** — references prior frames via motion vectors + residual.
- **B-frame (bidirectional)** — references both prior and future frames. Better compression, but introduces decode-order ≠ display-order, and adds latency equal to the longest forward reference.

H.264 allows multiple reference frames (the `max_num_ref_frames` SPS field), so a P-frame can reference any of the last N decoded frames, not just the immediately previous one. This is what gives H.264 its compression edge over MPEG-2 — and why corrupt frames cause cascading damage until the next IDR.

Slice-level granularity below frame: each frame is one or more slices. Slices are independently decodable within a frame, which is the basis for parallel decoding (slice-level threading in x264) and error resilience.

## Why H.264 is the surveillance default

Several converging reasons:

1. **Encoder maturity** — x264 is fast and high-quality; cheap camera SoCs all ship with H.264 hardware encoders that hit decent quality at 2–4 Mbps for 1080p30.
2. **Hardware decode everywhere** — [[hardware-accelerated-codecs|NVDEC]], [[hardware-accelerated-codecs|VAAPI]], [[hardware-accelerated-codecs|QuickSync]], [[hardware-accelerated-codecs|VideoToolbox]], all SoC video engines, all browser stacks. See [[hardware-accelerated-codecs]].
3. **Licensing settled** — the MPEG-LA pool stabilized; the per-unit royalty is small enough to be a non-issue for camera vendors.
4. **Network-friendly bitrates** — 2 Mbps over a typical IP-camera uplink is comfortable. [[h265-hevc-deep-dive|H.265]] is more efficient but doesn't move enough cameras off uplink-constrained sites to justify the licensing complexity.
5. **VMS compatibility** — every VMS, every NVR, every cloud platform handles H.264. New camera firmware that breaks H.264 compatibility costs the manufacturer customers.

## Decoding H.264 in Actuate

The primary path is **[[pyav-entity|PyAV]] inside `actuate-pullers`**, specifically `av_url_puller.py`. The puller calls `av.open(url, options=...)` (which goes through libavformat's [[rtsp-deep-dive|RTSP]]/HTTP demuxer), then iterates `container.demux(stream)` to get H.264 packets and `packet.decode()` to get YUV frames. The frames are then converted to BGR numpy arrays via `frame.to_ndarray(format="bgr24")`.

For hardware decode, the codec name is mapped through `HW_DECODERS` at `av_url_puller.py:24-77` — H.264 maps to `h264_cuvid` on NVIDIA, `h264_videotoolbox` on macOS, `h264_vaapi` on Linux Intel/AMD, etc. The decoder context is constructed via `create_hw_decoder_context()` at `av_url_puller.py:83-131` using `av.CodecContext.create(codec_name, "r")` rather than letting libav auto-select. Critical detail: `hwaccel_output_format` is **deliberately unset** at `:454-456, 432-434` — leaving it at default produces frames in CPU-accessible NV12 in main memory; setting it to a GPU-residency format breaks `frame.to_ndarray()` because the data isn't in CPU memory. We pay the GPU→CPU copy on every frame; the alternative is rewriting the downstream pipeline to consume GPU buffers.

There is also a brittle workaround at `url_puller.py:150-151, 1121-1122` where the URL is rewritten to add `videocodec=h264&` — this is a hint to certain camera/VMS firmwares whose default codec advertisement is unreliable, forcing them to deliver H.264 specifically. It's a string-replace; it should be replaced with proper SDP/codec negotiation but the cameras that need it don't always cooperate.

## Common failure modes

1. **Corrupt slices propagate until next IDR** — a packet drop on UDP [[rtsp-deep-dive|RTSP]] causes visible smear/macroblock damage for the entire [[gop-keyframe-fundamentals|GOP]]. Mitigation: `fflags=discardcorrupt` ([[gop-keyframe-fundamentals|see GOP fundamentals]]) plus the keyframe-wait guard ([[h265-hevc-deep-dive]] uses the same guard).
2. **B-frame latency** — cameras with B-frames enabled add 1–2 frames of latency to first-frame-decode. Most surveillance cameras default to no B-frames for this reason.
3. **Profile/level mismatch on hardware decode** — fall back to software decode and log loudly.
4. **SPS/PPS lost on reconnect** — the puller's reconnect logic must re-fetch from SDP, not assume parameter sets carry over.

## Actuate touchpoints

- Primary decode path — `actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py`
- Hardware decoder mapping table — `av_url_puller.py:24-77` (`HW_DECODERS`)
- HW codec context construction — `av_url_puller.py:83-131` (`create_hw_decoder_context`)
- Per-hwaccel option dict / [[rtsp-deep-dive|RTSP]] low-latency tuning — `av_url_puller.py:412-494`
- Deliberate-no-hwaccel-output-format note — `av_url_puller.py:454-456, 432-434`
- URL-rewrite hack to force H.264 — `actuate-libraries/actuate-pullers/src/actuate_pullers/url/url_puller.py:150-151, 1121-1122`
- Cross-topic: [[vms-connector/_summary]], [[hardware-accelerated-codecs]], [[gop-keyframe-fundamentals]], [[reading-list]] for x264/openh264 alternatives.
