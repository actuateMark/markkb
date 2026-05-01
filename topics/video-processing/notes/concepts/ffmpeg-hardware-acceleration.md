---
title: "FFmpeg hardware acceleration"
type: concept
topic: video-processing
tags: [ffmpeg, hwaccel, nvdec, nvenc, vaapi, qsv, videotoolbox, gpu]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/2026-04-27.md
  - topics/video-processing/_summary.md
  - topics/video-processing/notes/concepts/connector-docker-system-deps.md
  - topics/video-processing/notes/concepts/eks-prod-node-pool-gpu-availability.md
  - topics/video-processing/notes/concepts/ffmpeg-command-anatomy.md
  - topics/video-processing/notes/concepts/ffmpeg-filtergraphs.md
  - topics/video-processing/notes/concepts/ffmpeg-libav-libraries.md
  - topics/video-processing/notes/concepts/ffmpeg-python-bindings.md
  - topics/video-processing/notes/entities/ffmpeg-entity.md
  - topics/video-processing/notes/syntheses/actuate-build-vs-buy-tradeoffs.md
incoming_updated: 2026-05-01
---

# [[ffmpeg-entity|FFmpeg]] hardware acceleration

Hardware-accelerated decode/encode is the difference between **150 fps per CPU core** and **1000+ fps per GPU** for [[h264-deep-dive|H.264]]. For Actuate, where a single fleet pod may decode dozens of [[rtsp-deep-dive|RTSP]] streams, hwaccel is not optional — it's the only way the math works on EC2 G-class instances. This note covers [[ffmpeg-entity|FFmpeg]]'s hwaccel surface, the gotchas (especially `hwaccel_output_format`), Actuate's specific configuration in `av_url_puller.py`, and the container-image implications.

See [[hardware-accelerated-codecs]] for the codec-level / vendor-by-vendor matrix; this note is the **FFmpeg-side knobs and Actuate-side wiring**.

## The CLI surface

```
ffmpeg \
  -hwaccel <name>                  \
  -hwaccel_device <device>         \
  -hwaccel_output_format <fmt>     \
  -c:v <hwdec>                     \
  -i input \
  ...
```

| Flag | Purpose | Common values |
|------|---------|---------------|
| `-hwaccel` | Selects the hardware acceleration **method** (handle frame buffers in GPU memory) | `cuda`, `vaapi`, `qsv`, `videotoolbox`, `amf`, `d3d11va`, `dxva2`, `vulkan` |
| `-hwaccel_device` | Selects the **device** when multiple are present | `0` (NV index), `/dev/dri/renderD128` ([[hardware-accelerated-codecs|VAAPI]] render node) |
| `-hwaccel_output_format` | What the decoded frame buffer's pixel format is | `cuda`, `vaapi`, `nv12`, `yuv420p` (CPU) |
| `-c:v <hwdec>` | Use a specific **hardware decoder** (separate from `-hwaccel`) | `h264_cuvid`, `hevc_cuvid`, `h264_qsv`, `h264_vaapi` |

**Critical distinction**: `-hwaccel cuda -c:v h264` and `-c:v h264_cuvid` are not the same.

- `-hwaccel cuda` tells the **software decoder** (`h264`) to push hardware buffers via libavutil's `AVHWFramesContext`. Software dispatch + hardware acceleration of the heavy bits.
- `-c:v h264_cuvid` selects a **fully separate decoder** (cuvid = CUDA Video Decoder, [[hardware-accelerated-codecs|NVDEC]]). Different code path entirely. Generally faster, less flexible.

NVIDIA's recommendation is to use `h264_cuvid` directly for ingest workloads. [[ffmpeg-entity|FFmpeg]]'s docs recommend `-hwaccel` for transcoding pipelines because the frames come out in a normalized format. Both paths land at [[hardware-accelerated-codecs|NVDEC]] silicon eventually.

## The `hwaccel_output_format` gotcha

This is the single most-bitten foot in [[ffmpeg-entity|FFmpeg]] hwaccel. Here's the trap:

- **Default** (no `-hwaccel_output_format` set): frames are **downloaded to system memory** after decode. You get YUV/NV12/whatever in regular RAM, ready to convert with swscale or hand to numpy.
- **Set** (`-hwaccel_output_format cuda`): frames **stay in GPU memory** as `AV_PIX_FMT_CUDA` opaque references. Faster for transcode chains where you also encode on GPU. **But** any code that calls `frame.to_ndarray()` or `sws_scale()` to system memory will **fail** unless you explicitly insert an `hwdownload` filter first.

The right choice depends on what you do next:

| Pipeline | `hwaccel_output_format` |
|----------|------------------------|
| Decode → CPU inference / numpy | **don't set it** — keep frames on CPU |
| Decode → re-encode on same GPU | **set to GPU format** (`cuda`/`vaapi`) — avoid copies |
| Decode → GPU inference ([[nvidia-deepstream|DeepStream]] / DALI) | **set to GPU format** — keep zero-copy |
| Decode → GPU filter (`scale_npp`) → CPU egress | set, then explicit `hwdownload` after the filter |

Actuate does **CPU inference** (numpy egress to [[opencv-entity|OpenCV]] / YOLO models). The `hwaccel_output_format` is therefore deliberately **not set** so that [[pyav-entity|PyAV]]'s `frame.to_ndarray(format="bgr24")` works as expected. The `av_url_puller.py:454-456, 432-434` comments explain this exactly.

## The hwaccel families (with [[ffmpeg-entity|FFmpeg]] names)

| Family | Hardware | `-hwaccel` name | Decoder names | Encoder names |
|--------|----------|-----------------|---------------|---------------|
| **NVIDIA [[hardware-accelerated-codecs|NVDEC]]/[[hardware-accelerated-codecs|NVENC]]** | Any modern NVIDIA GPU (T4/L4/A10/RTX/...) | `cuda` | `h264_cuvid`, `hevc_cuvid`, `mjpeg_cuvid`, `vp9_cuvid`, `av1_cuvid` | `h264_nvenc`, `hevc_nvenc`, `av1_nvenc` |
| **Intel [[hardware-accelerated-codecs|QuickSync]]** | Intel iGPU + Arc | `qsv` | `h264_qsv`, `hevc_qsv`, `av1_qsv` | `h264_qsv`, `hevc_qsv`, `av1_qsv` |
| **[[hardware-accelerated-codecs|VAAPI]]** | AMD/Intel on Linux (and others) | `vaapi` | `h264_vaapi`, `hevc_vaapi` | `h264_vaapi`, `hevc_vaapi` |
| **AMD AMF** | AMD GPU on Windows / Linux | `amf` | (decoders limited) | `h264_amf`, `hevc_amf`, `av1_amf` |
| **Apple [[hardware-accelerated-codecs|VideoToolbox]]** | macOS / iOS | `videotoolbox` | `h264_videotoolbox`, `hevc_videotoolbox` | `h264_videotoolbox`, `hevc_videotoolbox` |
| **D3D11VA / DXVA2** | Windows generic | `d3d11va`, `dxva2` | dispatched via `h264` etc. | (decode-only) |
| **Vulkan Video** | Recent NVIDIA/AMD/Intel (frontier) | `vulkan` | nascent | nascent |

[[hardware-accelerated-codecs|NVENC]]/[[hardware-accelerated-codecs|NVDEC]] and QSV are the production options on AWS. [[hardware-accelerated-codecs|VAAPI]] mostly comes up with on-prem AMD/Intel boxes. [[hardware-accelerated-codecs|VideoToolbox]] is for developer laptops.

## Actuate's hwaccel configuration

The decode-side configuration lives in **`actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py`**.

### `HW_DECODERS` table — codec → hwaccel decoder name (lines 24-77)

A flat dictionary keyed by `(codec, hwaccel_method)` returning the appropriate libavcodec hardware-decoder name. Roughly:

| Codec | CUDA | [[hardware-accelerated-codecs|VAAPI]] | QSV | [[hardware-accelerated-codecs|VideoToolbox]] |
|-------|------|-------|-----|--------------|
| [[h264-deep-dive|h264]] | `h264_cuvid` | `h264_vaapi` | `h264_qsv` | `h264_videotoolbox` |
| hevc | `hevc_cuvid` | `hevc_vaapi` | `hevc_qsv` | `hevc_videotoolbox` |
| mjpeg | `mjpeg_cuvid` | (none) | (none) | (none) |
| mpeg2 / mpeg4 | `mpeg2_cuvid` / `mpeg4_cuvid` | ... | ... | ... |
| vp8 / vp9 | `vp8_cuvid` / `vp9_cuvid` | ... | ... | ... |
| av1 | `av1_cuvid` | `av1_vaapi` | `av1_qsv` | (limited) |
| vc1 / prores | covered | covered | partial | partial |

This drives `create_hw_decoder_context` at lines 83-131, which calls `av.CodecContext.create(name, "r")` with the right name based on the detected codec and the auto-detected hwaccel method.

### Per-hwaccel option dict (lines 412-494)

For each supported hwaccel method, there's a dict of libav* options applied to the decoder/format context. Notable entries:

- **`hwaccel_device=/dev/dri/renderD128`** for [[hardware-accelerated-codecs|VAAPI]] (the standard Linux DRI render node).
- **Low-latency [[rtsp-deep-dive|RTSP]] tuning** for all paths: `rtsp_transport=tcp`, `stimeout` / `rw_timeout` for stalled-stream detection, `fflags=nobuffer`, `flags=low_delay`.
- **`hwaccel_output_format` deliberately not set** (lines 454-456, 432-434): a comment explains that GPU-memory frames break `to_ndarray()` and the team accepts the GPU→CPU copy as the cost of doing inference in Python.

### Hwaccel auto-detection (lines 527-607)

Detection runs at puller startup and selects the first available hwaccel by priority:

1. **macOS** → [[hardware-accelerated-codecs|VideoToolbox]] (developer laptops).
2. **NVIDIA present** (`subprocess.run(["nvidia-smi", "-L"])` succeeds, line 567) → CUDA.
3. **Intel iGPU present** (`lspci | grep -i intel`, line 587) → [[hardware-accelerated-codecs|VAAPI]] (we don't currently default to QSV; [[hardware-accelerated-codecs|VAAPI]] is broader and works on AMD GPUs too).
4. **AMD GPU present** (`lspci`, line 597) → AMF on Windows, [[hardware-accelerated-codecs|VAAPI]] on Linux.
5. **Otherwise** → CPU decode.

The probe also runs **`ffmpeg -hide_banner -hwaccels`** (line 546) — this is the only place the codebase shells out to `ffmpeg` for media-adjacent work, and only as a sanity check that the [[ffmpeg-entity|FFmpeg]] binary on the container image supports the hwaccel the host has hardware for.

The `subprocess.run(..., timeout=5)` calls all have short timeouts so a slow probe (e.g. a misconfigured `nvidia-smi`) doesn't hang puller startup.

## EC2 instance families

| Family | GPU | Use case |
|--------|-----|----------|
| **G4dn** | NVIDIA T4 | Older fleet pods; [[hardware-accelerated-codecs|NVDEC]]-capable for [[h264-deep-dive|H.264]]/[[h265-hevc-deep-dive|H.265]]/[[av1-vp9-future|VP9]] (no [[av1-vp9-future|AV1]]) |
| **G5** | NVIDIA A10G | Mid-tier; [[hardware-accelerated-codecs|NVDEC]] [[av1-vp9-future|AV1]], [[hardware-accelerated-codecs|NVENC]] [[av1-vp9-future|AV1]] |
| **G6** | NVIDIA L4 | Current standard for inference + decode pods. Best perf/$ for our workload |
| **G6e** | NVIDIA L40S | Heavy mixed inference + decode |
| **P-class** | A100 / H100 | Training / heavy inference; overkill for decode |

L4 [[hardware-accelerated-codecs|NVDEC]] limits: ~1080p @ 1080 fps for [[h264-deep-dive|H.264]], ~1080p @ 800 fps for [[h265-hevc-deep-dive|H.265]]. Multi-stream decode batches well. Multiple sessions share the [[hardware-accelerated-codecs|NVENC]]/[[hardware-accelerated-codecs|NVDEC]] slots; the hardware doesn't have many of them, so very-high-fanout decode benefits from running multiple smaller pods on the same GPU rather than one giant pod.

## Container image implications

For Actuate's container images to actually use hwaccel:

- **Base image**: needs `libnvidia-decode`/`libnvidia-encode` userspace (CUDA driver). NVIDIA Container Toolkit on the host bridges to driver kernel modules.
- **[[ffmpeg-entity|FFmpeg]] build**: must be built with `--enable-cuda --enable-cuvid --enable-nvenc --enable-libnpp`. Distro `apt install ffmpeg` is usually fine; jellyfin-ffmpeg or BtbN's nightly statics give more recent codec coverage.
- **[[pyav-entity|PyAV]] wheel**: the wheel must be built against an [[ffmpeg-entity|FFmpeg]] with hwaccel support. PyPI wheels generally are; if you build from source, follow the [[pyav-entity|PyAV]] docs for `--enable-cuda` configure flags.
- **`libavcodec-extra`**: distro-only meta-package that pulls in additional [[codecs-overview|codecs]] (`x265`, etc.). Useful for breadth.
- **`/dev/nvidia*` device passthrough**: the runtime (Docker/containerd) must mount the NVIDIA devices into the container. The NVIDIA Container Toolkit handles this with `--gpus all`.
- **[[hardware-accelerated-codecs|VAAPI]]**: needs `/dev/dri/renderD128` mounted, plus `intel-media-va-driver` or `mesa-va-drivers`. Worth knowing for on-prem boxes.

EKS specifics: G-class node groups need the NVIDIA device plugin DaemonSet running, plus the appropriate AMI (the EKS-optimized GPU AMI handles this). Tainting GPU nodes prevents stray non-GPU pods from scheduling there.

## Common failure modes

- **"Cannot load nvcuda.dll" / "no CUDA-capable device"** — driver/userspace mismatch in container. Check the NVIDIA Container Toolkit version against the driver on the host.
- **`Cannot allocate hardware frames context`** — `hwaccel_output_format` is set but you're trying to read frames with `to_ndarray()`. Either unset it, or insert an `hwdownload` step.
- **Decoder reports success but frames are corrupt** — codec parameter set headers (SPS/PPS) not being parsed correctly by the hardware decoder. Often a `extradata` issue; can be worked around by forcing `bsf:v h264_mp4toannexb` in the bitstream filters.
- **[[hardware-accelerated-codecs|NVENC]] sessions exhausted** — consumer NVIDIA cards have very few [[hardware-accelerated-codecs|NVENC]] sessions (T4 has 3-ish). Datacenter cards have more. If you hit this, fewer-larger-pods pattern helps.

## Actuate touchpoints

Actuate's hwaccel story is concentrated in **`actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py`**:

- **`HW_DECODERS` table (lines 24-77)** — the codec→hwaccel-decoder-name mapping driving auto-selection.
- **`create_hw_decoder_context()` (lines 83-131)** — instantiates `av.CodecContext` with the chosen hardware decoder name (e.g. `h264_cuvid`).
- **Per-hwaccel option dicts (lines 412-494)** — [[hardware-accelerated-codecs|VAAPI]] device path, low-latency [[rtsp-deep-dive|RTSP]] tuning, the deliberate omission of `hwaccel_output_format` (lines 454-456, 432-434) so frames egress to system memory for `to_ndarray()`.
- **Auto-detection logic (lines 527-607)** — `subprocess.run(["ffmpeg", "-hide_banner", "-hwaccels"], timeout=5)` at line 546, `nvidia-smi -L` at 567, `lspci` at 587/597. Priority: macOS [[hardware-accelerated-codecs|VideoToolbox]] → CUDA → [[hardware-accelerated-codecs|VAAPI]] → AMF.
- **No [[hardware-accelerated-codecs|NVENC]] encode path** — Actuate decodes on GPU but **does not currently encode on GPU**. Clip generation paths do CPU-side encoding through [[opencv-entity|OpenCV]]'s `VideoWriter` or [[pyav-entity|PyAV]]'s encoder. Migrating these to [[hardware-accelerated-codecs|NVENC]] is a [[actuate-build-vs-buy-tradeoffs]] topic; mostly gated on whether the additional encoder-session pressure is worth the CPU savings.
- **Container image dependencies** — production pod images must include `ffmpeg` with CUDA support, the NVIDIA Container Toolkit on the host, and a [[pyav-entity|PyAV]] wheel built against a hwaccel-enabled [[ffmpeg-entity|FFmpeg]]. See [[infrastructure/_summary]] for the EKS GPU node-group config and [[fleet-architecture/_summary]] for the per-pod GPU fan-in.

Cross-refs: [[ffmpeg-entity]] | [[ffmpeg-command-anatomy]] | [[ffmpeg-libav-libraries]] | [[ffmpeg-filtergraphs]] | [[hardware-accelerated-codecs]] | [[h264-deep-dive]] | [[h265-hevc-deep-dive]] | [[actuate-frame-ingest-decode-paths]] | [[gstreamer-vs-ffmpeg]]
