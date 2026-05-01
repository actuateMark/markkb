---
title: "Connector Docker Image: Video-Processing System Deps Audit"
type: concept
topic: video-processing
tags: [docker, dockerfile, system-deps, ffmpeg, gstreamer, nvidia, libturbojpeg, follow-up]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/video-processing/_summary.md
  - topics/video-processing/notes/concepts/eks-prod-node-pool-gpu-availability.md
  - topics/video-processing/notes/syntheses/gpu-substrate-and-fleet-placement.md
incoming_updated: 2026-05-01
---

# Connector Docker Image: Video-Processing System Deps Audit

Audit of the four `vms-connector` Dockerfiles against the actual runtime needs of the video-processing libraries used in `actuate-pullers`, `actuate-pipeline`, and `actuate-image-cache`. Goal: catch any system dep that's expected by the libs but not present in the image, plus document what each variant actually targets.

## Variants & wiring

All Dockerfiles live in `docker_files/`. CI wiring (`.github/workflows/*.yml`):

| Variant | File | Base image | Target hosts | CI workflows |
|---|---|---|---|---|
| **x86 CPU** | `x86_dockerfile` | `python:3.12-slim` | x86 EKS nodegroups (default) | `master`, `develop`, `stage`, `rearch*`, `custom` |
| **x86 GPU** | `x86_dockerfile.gpu` | `nvidia/cuda:12.1.0-devel-ubuntu22.04` | g4dn (T4), g5 (A10G), g6 (L4) | `gpu.yml` |
| **ARM CPU** | `arm_dockerfile` | `python:3.12-slim` (aarch64) | Graviton2/3/4 EKS nodegroups | `master`, `develop`, `stage`, `rearch*`, `custom` |
| **ARM GPU** | `arm_dockerfile.gpu` | `nvidia/cuda:12.1.0-devel-ubuntu22.04` (aarch64) | **g5g** (Graviton3 + T4G) | `gpu-arm.yml` |

CPU variants pull apt packages via three list files in `docker_files/dependencies/apt/`:
- `apt_requirements.txt` — base build/runtime libs (40 lines)
- `apt_requirements_gst.txt` — [[gstreamer-entity|GStreamer]] 1.0 plugin set (-good, -bad, -ugly, -libav, -vaapi, -nice, plus tools and -dev headers)
- `apt_requirements_pyav.txt` — codec/swscale/[[hardware-accelerated-codecs|VAAPI]]/VDPAU dev headers (used only by ARM CPU + both GPUs, not x86 CPU)

GPU variants additionally compile [[ffmpeg-entity|FFmpeg]] 7.1.3 + [[opencv-entity|OpenCV]] 4.10.0 from source against the CUDA SDK ([[hardware-accelerated-codecs|NVDEC]] enabled, [[hardware-accelerated-codecs|NVENC]] disabled — see x86_dockerfile.gpu:75-80) and rebuild [[pyav-entity|PyAV]] with `--no-binary av` against that custom [[ffmpeg-entity|FFmpeg]] with RPATH `/usr/local/lib`.

## Library × variant grid

Legend: ✅ present | ⚠ partial / via wheel | ❌ missing

| Runtime path | Lib needed | x86 CPU | x86 GPU | ARM CPU | ARM GPU |
|---|---|---|---|---|---|
| `av_url_puller` (default [[rtsp-deep-dive|RTSP]]/HTTP) | [[pyav-entity|PyAV]] (libav* shared libs) | ⚠ wheel-bundled [[ffmpeg-entity|FFmpeg]] | ✅ source [[ffmpeg-entity|FFmpeg]] 7.1.3 + [[hardware-accelerated-codecs|NVDEC]] | ✅ source [[ffmpeg-entity|FFmpeg]] 7.1.3 (`build_ffmpeg.sh`) | ✅ source [[ffmpeg-entity|FFmpeg]] 7.1.3 + [[hardware-accelerated-codecs|NVDEC]] + NEON |
| `actuate-image-cache/_decode.py`, `turbojpegencode_step.py` | `libturbojpeg0` (via `libturbojpeg0-dev`) + `PyTurboJPEG~=1.7` | ✅ apt_requirements.txt:39 | ✅ (less `libjpeg62-turbo-dev`, see line 34 of dockerfile.gpu) | ✅ apt_requirements.txt:39 | ✅ |
| `gst_url_puller` ([[rtsp-deep-dive|RTSP]] via [[gstreamer-entity|GStreamer]]) | `gstreamer1.0-libav`, `-plugins-good`, `-plugins-base`, `-tools` | ✅ all incl. `-bad`, `-ugly`, `-vaapi` | ✅ | ✅ | ✅ |
| `kvs_url_puller` ([[kvs-components|KVS]] via boto3 `appsrc` → `matroskademux` → `decodebin` → `videoconvert` → `jpegenc` → `appsink`) | `gstreamer1.0-plugins-good` (matroskademux), `-libav` (decodebin codec), base | ✅ | ✅ | ✅ | ✅ |
| [[opencv-entity|OpenCV]] `cv2.VideoCapture` (fallback) | bundled [[ffmpeg-entity|FFmpeg]] in `opencv-python-headless~=4.10` wheel | ✅ self-contained | ✅ source build w/ CUDA + [[gstreamer-entity|GStreamer]] | ✅ self-contained | ✅ source build w/ CUDA + [[gstreamer-entity|GStreamer]] + NEON dispatch |
| [[hardware-accelerated-codecs|NVDEC]] hwaccel detection (`av_url_puller.py:527-607`) | `nvidia-smi` binary, `libnvidia-decode-XXX`, NVIDIA Container Toolkit on host | ❌ N/A — no GPU attached, gracefully falls through `FileNotFoundError` | ✅ via `nvidia/cuda` runtime + Container Toolkit on g4/g5/g6 nodes | ❌ N/A | ✅ via `nvidia/cuda` runtime + Container Toolkit on g5g nodes (T4G, compute 8.7) |
| `fish2pano` panorama dewarp (`base_puller.py:215`) | bundled `.so`/binary at `actuate_pullers/shared/lib/fish2pano/` | ✅ shipped inside `actuate-pullers` wheel | ✅ | ✅ | ✅ |
| PyGObject ([[gstreamer-entity|Gst]] Python bindings) | `python3-gi`, **OR** `libgirepository1.0-dev` + `libcairo2-dev` for source-build wheel | ✅ source-build path (deps in apt_requirements.txt:31, 33) | ✅ | ✅ | ✅ |
| [[ffmpeg-entity|FFmpeg]] TLS for `https://`/`rtsps://` | GnuTLS or OpenSSL | ⚠ depends on [[pyav-entity|PyAV]] wheel's bundled FFmpeg config (typically GnuTLS) | ✅ `--enable-gnutls` not set in GPU configure (see line 85+) — **SEE GAP** | ✅ `--enable-gnutls` in `build_ffmpeg.sh:54` | ⚠ GPU configure does **not** include `--enable-gnutls` — **SEE GAP** |
| Star4Live (Dahua NetSDK x86) | `libnetsdk.so` + `Star4LiveDemo` binary | ✅ COPYed from `dependencies/x86/star4live/` | ✅ | ❌ N/A (x86-only) | ❌ N/A (x86-only) |
| jemalloc (memory fragmentation mitigation) | `libjemalloc2` | ✅ release stage | ✅ release stage | ✅ release stage | ✅ release stage |

## Gap analysis

### Gap 1 — GPU [[ffmpeg-entity|FFmpeg]] builds omit `--enable-gnutls`

**Impact:** medium — silent failure of `https://` snapshot URLs and `rtsps://` cameras on GPU instances.

The CPU ARM build script (`build_ffmpeg.sh:54`) explicitly calls `--enable-gnutls`. Both GPU dockerfiles (`x86_dockerfile.gpu:85-115`, `arm_dockerfile.gpu:92-116`) configure [[ffmpeg-entity|FFmpeg]] with `--enable-gpl --enable-nonfree --enable-shared` plus codec/CUDA flags, but **no TLS provider is enabled**. [[pyav-entity|PyAV]] opening an `https://` or `rtsps://` URL on a GPU node will fail with `"Protocol not supported"` or similar — falling back to CPU on different nodes would mask the problem.

What would silently fail: any partner camera served over TLS (Eagle Eye, OpenEye snapshot, anything `rtsps://`). Probably never noticed because most VMS pulls are plain `rtsp://` from on-prem appliances, but worth fixing before shipping a GPU rollout to a customer with TLS-fronted cameras.

### Gap 2 — `apt_requirements_pyav.txt` excluded from x86 CPU image

The x86 CPU Dockerfile (`x86_dockerfile:17-19`) installs `apt_requirements.txt` and `apt_requirements_gst.txt`, but **not** `apt_requirements_pyav.txt`. This is intentional and correct because x86 CPU uses the **[[pyav-entity|PyAV]] wheel from PyPI with bundled [[ffmpeg-entity|FFmpeg]]** (no custom build), so `libx264-dev`, `libvpx-dev`, etc. aren't needed. ARM CPU includes them because it builds [[ffmpeg-entity|FFmpeg]] from source.

No action — design is consistent. Documenting because the asymmetry looks odd at first glance.

### Gap 3 — KVS `gstreamer1.0-plugins-bad` not strictly required, but installed

[[kvs-components|KVS]] pipeline string (`kvs_ingestor.py:148-158`) is `appsrc → matroskademux → decodebin → videoconvert → jpegenc → appsink`. `matroskademux` and `videoconvert` are in **plugins-good**; `jpegenc` is in **plugins-good**; `decodebin` is in **plugins-base**. `appsrc`/`appsink` are in **base**. **`plugins-bad` is not needed for the [[kvs-components|KVS]] path** — it's installed via `apt_requirements_gst.txt` for safety / future [[rtsp-deep-dive|RTSP]] pipelines using `rtspsrc` extras. Fine.

### Gap 4 — `souphttpsrc` referenced in audit prompt but not actually used

Audit task mentioned [[kvs-components|KVS]] needs `souphttpsrc`. Reality: [[kvs-components|KVS]] pulls bytes via `boto3 KinesisVideoMedia.get_media()` and feeds them to a [[gstreamer-entity|GStreamer]] **`appsrc`** in Python. No HTTP plugin is needed inside [[gstreamer-entity|GStreamer]]. `souphttpsrc` (in `gstreamer1.0-plugins-good`) is present anyway as a side-effect of the broader plugin install, so even if a future code path needed it, no Dockerfile change required.

### Gap 5 — ARM-GPU clarification

ARM GPU is **real** and CI-built (`.github/workflows/gpu-arm.yml`, `docker_files/arm_dockerfile.gpu`). Target: AWS **g5g** instances which combine Graviton 3 (Neoverse V1) cores with NVIDIA T4G GPUs (Ampere, compute capability 8.7). The Dockerfile targets `CUDA_ARCH_BIN="8.7"` exclusively (vs x86 GPU's `"7.5;8.6;8.9"` for T4/A10G/L4). [[ffmpeg-entity|FFmpeg]] is built with `--enable-neon` plus [[hardware-accelerated-codecs|NVDEC]]/cuvid. So "ARM GPU" is **NOT** an oxymoron — it's CPU-Graviton + GPU-NVIDIA-T4G, distinct from x86 GPU and from plain ARM CPU. Whether g5g is *currently provisioned* in any EKS cluster is a separate infra question (see [[infrastructure/_summary]] / `ds-terraform-eks-v2` nodegroup configs).

## Cross-references

- [[ffmpeg-entity]], [[gstreamer-entity]], [[opencv-entity]], [[pyav-entity]] — the libraries themselves
- [[hardware-accelerated-codecs]], [[ffmpeg-hardware-acceleration]] — [[hardware-accelerated-codecs|NVDEC]]/[[hardware-accelerated-codecs|VAAPI]] background
- [[mjpeg-and-still-image-formats]] — TurboJPEG context (encode path on hot frames)
- [[vms-connector/_summary]] — connector architecture and integration map
- [[infrastructure/_summary]] — EKS nodegroup composition (CPU vs GPU, x86 vs Graviton)

## Follow-ups

1. **Decide on `--enable-gnutls` for GPU [[ffmpeg-entity|FFmpeg]] builds.** If TLS-fronted cameras are in scope for any GPU-eligible customer, add the flag (and `libgnutls28-dev` apt package — already installed via `apt_requirements.txt`) to both GPU Dockerfile configure invocations.
2. **Add an import + protocol smoke test to GPU release stage.** The GPU dockerfiles already run `python3 -c "import pydantic_settings; import cv2; import av; print('✓ All imports OK')"`. Extend it to a quick `av.open("https://...")` against a known-good public stream so regressions on TLS / [[hardware-accelerated-codecs|NVDEC]] compile flags surface in CI.
3. **Consider a runtime startup probe** that logs the actual `ffmpeg -version` and the selected hwaccel (already partly done by `_detect_hardware_acceleration` — but write the result once at boot, not per-camera).
