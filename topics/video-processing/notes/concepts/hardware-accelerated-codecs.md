---
title: Hardware-Accelerated Codecs
type: concept
topic: video-processing
tags: [hwaccel, nvenc, nvdec, vaapi, quicksync, videotoolbox, gpu]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/actuate-libraries/notes/concepts/2026-05-19_stream-publisher-design.md
  - topics/integrations/rtsp/notes/entities/rtsp-components.md
  - topics/integrations/rtsp/notes/syntheses/rtsp-robustness-enhancement-plan.md
  - topics/personal-notes/notes/daily/2026-04-27.md
  - topics/video-processing/_summary.md
  - topics/video-processing/notes/concepts/av1-vp9-future.md
  - topics/video-processing/notes/concepts/codecs-overview.md
  - topics/video-processing/notes/concepts/connector-decoder-routing-map.md
  - topics/video-processing/notes/concepts/connector-docker-system-deps.md
  - topics/video-processing/notes/concepts/containers-overview.md
incoming_updated: 2026-05-27
---

# Hardware-Accelerated [[codecs-overview|Codecs]]

"Hardware acceleration" for video codecs means delegating encode/decode from the CPU to fixed-function silicon — a dedicated block on a GPU, integrated GPU, or SoC media engine. The win is large: a single NVDEC engine on an L4 GPU handles 30+ concurrent 1080p [[h264-deep-dive|H.264]] decodes at single-digit % utilization, where the equivalent software decode would saturate multiple CPU cores. The cost is complexity — different vendors have different APIs, different codec/profile coverage, and frames live in GPU memory by default which forces a copy back to CPU before our pipeline can use them.

This note maps the vendor landscape onto Actuate's actual implementation in `av_url_puller.py`.

## The vendor matrix

| Vendor / API | Encode | Decode | Where it lives | [[ffmpeg-entity|ffmpeg]] name examples |
|---|---|---|---|---|
| **NVIDIA NVENC / NVDEC** | Yes | Yes | GeForce, Quadro, Tesla, datacenter (T4 / A10 / L4 / L40S) | `h264_cuvid`, `hevc_cuvid`, `av1_cuvid`, `h264_nvenc` |
| **Intel QuickSync** | Yes | Yes | Intel iGPU (Skylake+); Arc dGPU | `h264_qsv`, `hevc_qsv`, `h264_vaapi` |
| **VAAPI** (Linux abstraction) | Yes | Yes | Intel + AMD on Linux; libva | `h264_vaapi`, `hevc_vaapi` |
| **AMD AMF** | Yes | Yes | AMD GPUs (Polaris+) | `h264_amf`, `hevc_amf` |
| **Apple VideoToolbox** | Yes | Yes | macOS / iOS | `h264_videotoolbox`, `hevc_videotoolbox` |
| **Android MediaCodec** | Yes | Yes | Android SoCs | `h264_mediacodec` |
| **V4L2 M2M** | Yes | Yes | Embedded Linux (RPi, NXP) | `h264_v4l2m2m` |

Cross-vendor coverage is uneven for newer [[codecs-overview|codecs]] — see [[av1-vp9-future]] for [[av1-vp9-future|AV1]] specifically, [[h265-hevc-deep-dive]] for [[h265-hevc-deep-dive|H.265]] hardware-decode availability per chip family.

## NVENC / NVDEC: what we run on

Actuate's inference substrate runs on AWS EC2 G5 / G6 / G6e instances backed by NVIDIA T4 / A10 / L4 / L40S GPUs (see [[knowledgebase/topics/billing/reading-list]] for the family overview). NVDEC is the relevant block — we decode camera streams; we don't encode. Per generation:

- **T4 (Turing)** — 1× NVDEC. [[h264-deep-dive|H.264]], [[h265-hevc-deep-dive|H.265]] (Main / Main10), [[av1-vp9-future|VP9]].
- **A10 (Ampere)** — 1× NVDEC, plus [[av1-vp9-future|AV1]] decode added.
- **L4 (Ada Lovelace)** — 2× NVDEC, [[av1-vp9-future|AV1]] + [[av1-vp9-future|AV1]] encode.
- **L40S (Ada Lovelace, large)** — 3× NVDEC.

Throughput is "many simultaneous streams per engine" rather than a hard count — depends on resolution, codec, and per-stream bitrate. In practice we don't push the NVDEC saturation envelope; CPU and GPU compute (inference) are the more common bottlenecks.

NVDEC is accessed via libavcodec's `*_cuvid` decoders, which under the hood call into the **NVIDIA Video Codec SDK** (cuvid is the legacy name; `nvdec` is the newer name; both work). The CUDA dependency is the catch: a node without CUDA runtime libs can't hit `h264_cuvid`. Driver and CUDA toolkit versions must align with the encoded-codec capabilities the application advertises — version skew here is a recurring failure source.

## How Actuate selects a hardware decoder

The control flow lives in `actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py`:

**Codec → hwaccel mapping** at `:24-77` is the **canonical Actuate inventory** of supported decoder paths. It's a 2-level dict: codec name (`h264`, `hevc`, `av1`, `vp8`, `vp9`, `mjpeg`, `mpeg2video`, `mpeg4`, `vc1`, `prores`) → hwaccel kind (`cuda`, `videotoolbox`, `vaapi`, `amf`, `mediacodec`, `v4l2m2m`) → [[ffmpeg-entity|ffmpeg]] decoder name. This table is the source of truth when asking "what hardware path do we have for codec X?"

**Auto-detection** at `_detect_hardware_acceleration()` (`:527-607`):

1. Run `subprocess.run(["nvidia-smi", "-L"])` with `timeout=5s`. If it succeeds, we have NVIDIA hardware — try CUDA path first.
2. Run `["ffmpeg", "-hwaccels"]` to get libav's installed hwaccel list. This catches missing builds (e.g., a container without VAAPI libs even though the host has Intel iGPU).
3. Run `["lspci"]` as a fallback / sanity check — useful for distinguishing NVIDIA presence from "we have an `nvidia-smi` binary but no actual GPU."
4. Apply priority: **macOS VideoToolbox → NVIDIA CUDA → Intel VAAPI → AMD AMF → software**. The macOS-first ordering matters only for dev laptops; in production we're always on the NVIDIA path.

The 5-second subprocess timeout is important — Lambda cold starts and pod startups have hit hangs from `nvidia-smi` blocking on a contested GPU; bounded timeout converts a hang into a fall-through to software decode.

**Decoder context construction** at `create_hw_decoder_context()` (`:83-131`): rather than `av.open(url)` and let libav auto-pick, we explicitly construct an `av.CodecContext.create(decoder_name, "r")` for the chosen decoder (e.g., `h264_cuvid`). This gives us control over codec-context-level options (extradata, low-delay flags) that auto-pick wouldn't expose.

## The `hwaccel_output_format` trap

The single most important non-obvious detail in our hardware-decode setup, called out in comments at `av_url_puller.py:454-456` and `:432-434`:

> `hwaccel_output_format` is **deliberately unset**.

What does this mean? When you set `hwaccel_output_format=cuda` (or `vaapi`, etc.), the decoder produces frames whose data resides in **GPU memory**. This is faster — no GPU→CPU copy — and the right answer if the downstream consumer is also GPU-resident (a CUDA inference pipeline, an OpenGL display path, etc.).

But our downstream is `frame.to_ndarray(format="bgr24")`, which needs CPU-accessible memory. With `hwaccel_output_format=cuda`, `to_ndarray()` either fails outright or silently gets garbage (the exact failure mode varies by libav version). By leaving the option unset, libavcodec falls back to copying the decoded frame back to CPU memory in NV12/YUV420P, where `to_ndarray()` can convert it to BGR.

The cost is real — every frame eats a GPU→CPU memcpy of (1920×1080×1.5) ≈ 3 MB per frame. At 30fps that's 90 MB/s per stream of PCIe traffic. We accept this because the alternative is rewriting `actuate-pipeline` to consume GPU buffers (a much larger project — see [[actuate-build-vs-buy-tradeoffs]] for context).

This is the kind of detail that's invisible in the code without the comment, and the comment exists because someone (likely a previous self) burned a day debugging "frames look right but downstream segfaults."

## Per-hwaccel option dicts

The puller maintains a per-hwaccel option dictionary at `av_url_puller.py:412-494` mixing in:

- **[[rtsp-deep-dive|RTSP]] low-latency tuning** — probesize=128KB, analyzeduration=300ms, fflags=discardcorrupt (see [[gop-keyframe-fundamentals]])
- **Hardware-specific knobs** — e.g., `surfaces=N` for cuvid (decode surface count), `extra_hw_frames` for some VAAPI configurations
- **`hwaccel_output_format` deliberate omission** as described above

This dictionary is per-hwaccel rather than per-codec — most options are codec-agnostic.

## When hardware decode falls through to software

Several paths land us on CPU decode:

1. **No hardware detected** — `_detect_hardware_acceleration()` returns `None`. Common in dev / CI environments without GPUs.
2. **Codec not in the table** — `HW_DECODERS` doesn't list it. Less common; the table is broad.
3. **Hardware decoder rejects the bitstream** — profile/level mismatch, unsupported feature. NVDEC has tightened constraints across driver versions; an upgrade can break a stream that worked before. The puller catches the decoder-init exception and falls back.
4. **Hardware decode succeeds but frame is unusable** — rarer; usually surfaces as `to_ndarray()` errors.

Each path logs distinctively. The right operational signal for "we silently fell to software decode at scale" is a CPU-utilization regression on the inference pods, plus a spike in `_detect_hardware_acceleration()` log lines. We don't have a metric for this directly today — it's a [[knowledgebase/topics/billing/reading-list]] follow-up to add.

## What's *not* in our hardware path

- **No hardware encode.** We don't run NVENC anywhere — encode is JPEG-only and stays on CPU via libjpeg-turbo (see [[mjpeg-and-still-image-formats]]).
- **No [[nvidia-deepstream|DeepStream]].** NVIDIA's full [[gstreamer-entity|GStreamer]]-based [[nvidia-deepstream|DeepStream]] SDK ([[knowledgebase/topics/billing/reading-list]]) is "the right way" to do GPU-resident multi-stream inference. We don't use it. We do per-stream [[pyav-entity|PyAV]] decode → CPU numpy → CPU/GPU inference. Deviating from this is a [[actuate-build-vs-buy-tradeoffs]] question.
- **No GPU-resident pipeline.** The deliberate `hwaccel_output_format` omission is the line we drew. Crossing it requires a downstream pipeline rewrite.
- **No transcode.** We never re-encode video, only decode + JPEG-encode.

## Common gotchas

1. **Driver version skew across pod / container / host.** CUDA toolkit at the build layer must match the driver on the EC2 host. NVIDIA's compatibility matrix is forgiving but not infinite.
2. **`nvidia-smi` not available in container** — even if the host has a GPU, the container needs the NVIDIA Container Toolkit to surface it. `nvidia-smi -L` returning empty inside a container with the GPU present is a config problem, not a hardware one.
3. **Multiple processes contending for one decode engine** — NVDEC throughput is a shared resource across the host. Pod density on g5.xlarge (1× NVDEC) needs scheduler attention.
4. **`hwaccel_output_format`** — see the dedicated section. Don't set it without rewriting the consumer.
5. **VAAPI on Linux requires render node permissions** — `/dev/dri/renderD128` access. [[containers-overview|Containers]] without the right device pass-through fall through to software.

## Actuate touchpoints

- Codec → hwaccel mapping table — `actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py:24-77` (`HW_DECODERS`)
- Auto-detection (`nvidia-smi`, `ffmpeg -hwaccels`, `lspci`, 5s timeout) — `av_url_puller.py:527-607` (`_detect_hardware_acceleration()`)
- Hardware decoder context construction — `av_url_puller.py:83-131` (`create_hw_decoder_context`)
- Per-hwaccel option dicts — `av_url_puller.py:412-494`
- `hwaccel_output_format` deliberate-omit comments — `av_url_puller.py:454-456, 432-434`
- Cross-topic: [[h264-deep-dive]], [[h265-hevc-deep-dive]], [[av1-vp9-future]], [[gop-keyframe-fundamentals]], [[infrastructure/_summary]] for EC2 GPU substrate, [[ai-models/_summary]] for downstream inference, [[knowledgebase/topics/billing/reading-list]] for [[nvidia-deepstream|DeepStream]] / DALI / Video Codec SDK reference material.
