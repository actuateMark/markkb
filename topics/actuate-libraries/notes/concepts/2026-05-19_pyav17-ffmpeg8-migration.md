---
title: "PyAV 13 → 17 / FFmpeg 7 → 8 / OpenCV 4.11 → 4.13 — migration risk surface"
type: concept
topic: actuate-libraries
tags: [pyav, ffmpeg, opencv, hevc, miss-685, dependency-bump, av_url_puller, autopatrol_websocket_stream_puller, graviton, §30]
created: 2026-05-19
updated: 2026-05-19
author: kb-bot
sources:
  - https://github.com/aegissystems/vms-connector/issues/1703
  - https://github.com/aegissystems/vms-connector/pull/1621
incoming:
  - topics/actuate-libraries/notes/concepts/2026-05-19_stream-publisher-design.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/vms-connector/notes/syntheses/2026-05-19_live-streaming-v1-plan.md
  - topics/vms-connector/notes/syntheses/2026-05-19_streaming-pyav17-crosscut.md
incoming_updated: 2026-05-20
---

# PyAV 17 / FFmpeg 8 / OpenCV 4.13 — migration risk surface

Decomposition of [vms-connector#1703](https://github.com/aegissystems/vms-connector/issues/1703) — the proposal to bump three coupled video deps. The driving incident is MISS-685 ([[h265-hevc-deep-dive|HEVC]] gray-frame missed detection at AmeriGas Sacramento); the supporting upside is a custom-FFmpeg-build drop, [[opencv-entity|OpenCV]] perf, and reduced maintenance.

## The three bumps

| Pin | Current | Target |
|---|---|---|
| `av` ([[pyav-entity|PyAV]]) | `~=13.1.0` | `~=17.0.1` |
| `opencv-python-headless` | `~=4.10` (resolves to 4.11) | `~=4.13` |
| [[ffmpeg-entity|FFmpeg]] in `docker_files/dependencies/build_ffmpeg.sh` | `n7.1.3` | `n8.1.1` *(or drop the build entirely — see below)* |

## The motivating defect — FFmpeg #9805 / HEVC corruption silence

Investigation around MISS-685 confirmed:

- [[h265-hevc-deep-dive|HEVC]] mid-stream reference loss is common at AmeriGas Sacramento (cam ST24-3 reconnects ~28×/4h with `Could not find ref with POC X` / `PPS id out of range` / `cu_qp_delta` errors)
- Between exception-driven reconnects, the decoder silently emits **visually-degraded frames** (gray fields, sparse macroblock artifacts) that look fine to the API but are unusable for inference — fed to YOLO → missed detections; uploaded as 5-min preview snapshots → "stale grey snapshot"
- On [[ffmpeg-entity|FFmpeg]] 7.1.3 / [[pyav-entity|PyAV]] 13.1.0, `frame.is_corrupt` (`AV_FRAME_FLAG_CORRUPT`) fires **zero times** across 6,000+ frames during clearly-corrupt windows. This is [FFmpeg #9805](https://fftrac-bg.ffmpeg.org/ticket/9805) — known [[h265-hevc-deep-dive|HEVC]] error-reporting gap.

[[ffmpeg-entity|FFmpeg]] 8.1 added [commit bc1a3bfd2](https://github.com/FFmpeg/FFmpeg/commit/bc1a3bfd2cbc01ffa386312662af8a014890d861) (Tencent / Zhao Zhili) that **rejects undecodable [[h265-hevc-deep-dive|HEVC]] NALUs at parse time** instead of silently decoding with stale references. Live testing against cam1 confirms bad NALUs now get dropped upstream during `Could not find ref with POC` events — frame rate drops briefly but visually-bad frames stop. Sustained MISS-685-magnitude validation is the goal of stage soak.

## Why this supersedes the prototyped workaround

An `actuate-pullers` prototype hooked `av.logging` to catch [[h265-hevc-deep-dive|HEVC]] warnings via the `libav` Python logger and skip frames decoded within a quarantine window. Validated on cam1; would catch ~2 % of frames during corruption windows. **Abandoned** in favor of the upstream version bump — moving the gate from "match against log strings" to "[[ffmpeg-entity|FFmpeg]] rejects NALUs natively" is a strict improvement.

## Secondary benefits

- **[[pyav-entity|PyAV]] 17.0.1 leak fix** — `StreamContainer.get()` reference cycle that affected long-running pullers (us)
- **[[pyav-entity|PyAV]] 14.3.0 [[ffmpeg-entity|FFmpeg]] 7.1 deadlock fix** — net positive on long uptime
- **[[opencv-entity|OpenCV]] 4.13 perf** — AVX-512 + general work on `GaussianBlur`, `resize`, `warpAffine` (cited 10–300 % depending on platform/kernel); visible on the pre-processing CPU budget
- **CVE currency** — [[ffmpeg-entity|FFmpeg]] 7.1.3 was specifically pinned for CVE-2025-1816; 8.1.1 has additional fixes since

## Breaking-changes audit (PyAV v14–v17)

| Change | Impact | Fix |
|---|---|---|
| `av.AVError` alias removed (v14) | **Crash on autopatrol decode errors** | Rename to `av.FFmpegError` — 2 sites in `actuate-pullers/socket/autopatrol_websocket_stream_puller.py:251,371` |
| `codec_context.skip_frame = "DEFAULT"/"NONKEY"` (custom Enum removed, v15) | Logic break in AVDiscard path | `from av.codec.context import SkipType` + use enum members — 6 sites in `actuate-pullers/url/av_url_puller.py` |
| `Stream.side_data` removed (v14) | None — `Frame.side_data` still present | none |
| `CodecContext.close()` removed (v14) | None — connector uses `container.close()` | none |
| Python 3.9 dropped (v16) | None — we require ≥3.12 | none |
| `ValueError` → `av.ArgumentError` (v17) | Low — broad `Exception` catches | none |
| libaom ([[av1-vp9-future|AV1]]) removed (v17) | None — not used | none |

Total migration: ~8 line changes, all in `actuate-libraries/actuate-pullers/src/actuate_pullers/`. **Zero changes in `vms-connector` itself**, only the pin bump + the [[ffmpeg-entity|FFmpeg]] version in `build_ffmpeg.sh`.

## The Graviton 4 caveat (from PR #1621 — read this before optimism)

The original [[pyav-entity|PyAV]] 17 PR ([vms-connector#1621](https://github.com/aegissystems/vms-connector/pull/1621)) was framed as a "5.9× speedup" win. Graviton 4 benchmarks (c8g.xlarge, 2026-05-11) said otherwise:

| Mode | Decode | Convert | CPU/frame |
|---|---|---|---|
| [[pyav-entity|PyAV]] 13.1.0 ([[ffmpeg-entity|FFmpeg]] 7.0) | 8.00 ms | 5.14 ms | 14.70 ms |
| [[pyav-entity|PyAV]] 17.0.1, `threads=auto` | 7.92 ms | **2.31 ms** | **14.90 ms** |
| [[pyav-entity|PyAV]] 17.0.1, `threads=1` | 7.91 ms | 5.09 ms | 14.53 ms |

Forcing `threads=1` makes convert time identical to v13 — **the entire 2× speedup is from [[pyav-entity|PyAV]]'s new multithreaded `sws_scale_frame`**, not from [[ffmpeg-entity|FFmpeg]] 8. There is **no algorithmic improvement** in [[ffmpeg-entity|FFmpeg]] 8 for this codepath. Total CPU is ~1–6 % higher on Graviton 4 because of the threading overhead.

This reframes the value prop: #1703 is **a latency/quality change, not a cost reduction**. CPU-bound pods (high-density 4K/[[h265-hevc-deep-dive|HEVC]] like connector-24367) will *cost* ~5 % more vCPU. Latency-sensitive pods with spare CPU get ~2× faster per-frame `to_ndarray` wall-clock. GIL contention with `gc.collect()` may improve as a secondary benefit (nogil reformat allows other threads to run during conversion) — not measured.

**Alternative if CPU regression matters:** ship [[pyav-entity|PyAV]] 17 but explicitly call `reformat(format="bgr24", threads=1)` instead of `to_ndarray("bgr24")` to get the small Python-overhead reduction without the threading CPU cost. Best of both worlds for CPU-bound deployments.

## Drop the custom FFmpeg build?

Option in the proposal — drop `docker_files/dependencies/build_ffmpeg.sh` entirely and use the stock [[pyav-entity|PyAV]] wheel's bundled [[ffmpeg-entity|FFmpeg]] (bundled 8.0 in 17.0.1, 8.1.1 in upcoming 17.1).

Pros: simpler Dockerfile, smaller image, ~5 min faster builds on cold cache.
Cons: loses vaapi/cuda HW accel.

The connector currently runs CPU-only on every production node, so this is **free in practice today** — but it forecloses GPU-based connector deployments without re-introducing the source build. Decision deferred until the GPU connector story is concrete.

## Validation arc

1. Bump in a feature branch of [[actuate-pullers]]; wait for dev wheel publish
2. Pin dev wheel in a vms-connector feature branch
3. Deploy via connector_deployer to **cust 41399 (Eyeforce: AmeriGas Sacramento)** — the MISS-685 site, known-bad camera, immediate signal
4. Run 24–48 h; compare:
   - Stream-lost / broken-stream reconnect rate vs current baseline (~28/4h)
   - Snapshot preview quality in admin UI (no gray previews)
   - Inference detection rate
5. If clean, deploy to one or two other HEVC-heavy sites for wider read
6. Promote to `stage` for fleet soak
7. Promote to `rearchitecture` with `[minor:actuate-pullers]` tag

## Status / sequencing

- Investigation history + abandoned prototype branches: closed `feature/hevc-decode-error-reconnect` (deleted from both `vms-connector` and `actuate-libraries`)
- The older PyAV-only attempt ([#1621](https://github.com/aegissystems/vms-connector/pull/1621)) is superseded by the broader #1703 framing
- See [[2026-05-19_streaming-pyav17-crosscut]] for sequencing relative to Live Streaming v1

## Related

- [[2026-05-19_streaming-pyav17-crosscut]] — sequencing with Live Streaming
- [[2026-05-19_live-streaming-v1-plan]] — concurrent change to the same file
- [[2026-05-19_stream-publisher-design]] — `BrokenPipeError` recovery loop affected by `av.FFmpegError` rename
- [[actuate-pullers]] — library entity
- Tracking workstream: §30 in `mark-todos.md`
