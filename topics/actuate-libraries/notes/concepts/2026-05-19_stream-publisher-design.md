---
title: "StreamPublisher — passthrough mux collaborator for AvUrlFramePuller"
type: concept
topic: actuate-libraries
tags: [actuate-pullers, av_url_puller, pyav, mediamtx, live-streaming, codec-gate, broken-pipe]
created: 2026-05-19
updated: 2026-05-19
author: kb-bot
sources:
  - https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/579862531
incoming:
  - topics/actuate-libraries/notes/concepts/2026-05-19_pyav17-ffmpeg8-migration.md
  - topics/personal-notes/notes/daily/2026-05-19.md
  - topics/vms-connector/notes/syntheses/2026-05-19_live-streaming-v1-plan.md
  - topics/vms-connector/notes/syntheses/2026-05-19_live-streaming-v1-status.md
  - topics/vms-connector/notes/syntheses/2026-05-19_streaming-pyav17-crosscut.md
incoming_updated: 2026-05-20
---

# StreamPublisher

The Phase 1 deliverable in [[2026-05-19_live-streaming-v1-plan|Live Streaming v1]] inside [[actuate-pullers]]. A small state machine + [[pyav-entity|PyAV]] mux loop that lets the existing `AvUrlFramePuller` demux loop fork [[h264-deep-dive|H.264]] packets to [[2026-05-18_mediamtx|MediaMTX]] without re-encoding and without adding a second [[rtsp-deep-dive|RTSP]] connection to the camera.

File: `actuate-pullers/src/actuate_pullers/url/av_url_puller.py` (~line 1270, after keyframe gate, before `_decode_packet`).

## Surface

The puller's `__init__` instantiates `self.stream_publisher = StreamPublisher()`. Three methods:

- **`configure(video_stream)`** — called from `connect_stream`; records codec name; sets `_codec_supported = (codec_name == "h264")`. Non-H.264 cameras log one line and are permanently no-op even if commanded.
- **`set_enabled(enabled, target_url, source)`** — called from the SQS consumer thread. Idempotent; accepts the target URL on each enable so a future reassignment can move a camera from one MediaMTX pod to another mid-stream. No-op if codec unsupported.
- **`maybe_mux(packet)`** — checks enable flag; opens output container at next keyframe via `av.open(url, mode="w", format="rtsp")` + `add_stream(template=video_stream)`; on `OSError` closes output and re-opens at next keyframe; assigns `packet.stream = self._out_stream` before `mux()`.

The publisher accepts the target URL via `set_enabled` — it never reads config itself. This keeps the library decoupled from runtime config plumbing.

## State machine

```
   idle ─── set_enabled(True, url) ──► armed
                                         │
                                         │  next keyframe seen
                                         ▼
   armed ─────────────────────────► publishing
                                         │
                                         │  OSError on mux()
                                         ▼
                                       error
                                         │
                                         │  next keyframe
                                         ▼
                                    publishing
                                         │
                              set_enabled(False)
                                         │
                                         ▼
                                        idle
```

Reassignment (`set_enabled(True, new_url)` while already publishing) closes the current output container and arms with the new URL on next keyframe. The brief blackout is bounded by the [[gop-keyframe-fundamentals|GOP]] interval.

## BrokenPipeError recovery — the key failure mode

When a camera goes idle for ~30 s, MediaMTX tears down the publisher socket and the next mux call raises `BrokenPipeError`. This is **the expected failure mode**, not a bug. The Phase 0 spike characterized it explicitly. Recovery: catch `OSError`, close output container, mark state `error`, wait for next keyframe, reopen.

**Cross-reference to [[2026-05-19_pyav17-ffmpeg8-migration|the PyAV 17 bump]]:** the surrounding `except av.AVError` clauses in `av_url_puller.py:251,371` rename to `except av.FFmpegError`. The publisher's own `except OSError` doesn't change, but **co-residing exception handling must migrate together** or we trade one regression for another.

## Codec gate

One-liner using `video_stream.codec_context.codec.name`. [[h265-hevc-deep-dive|HEVC]] + [[mjpeg-and-still-image-formats|MJPEG]] cameras log a single startup line and the publisher refuses to arm even if commanded. v2 would add an [[hardware-accelerated-codecs|NVENC]] transcode path; out of scope for v1.

## Spike measurements (PyAV 13.1.0, macOS, MediaMTX 1.18.1)

Per pushing camera, single-threaded:

| Metric | Baseline (demux+decode) | + passthrough mux | Δ |
|---|---|---|---|
| CPU % of 1 core | 3.94 % | 4.91 % | **+0.97 pp** |
| CPU per packet | 2425 µs | 3089 µs | **+613 µs** |
| Peak RSS | 52.8 MB | 52.8 MB | **0 MB** |

Per-mux-call latency (478 samples): median 395 µs, p95 1994 µs, p99 3405 µs, max 7870 µs.

End-to-end pixels verified via `ffmpeg -frames:v 1` from `/passthrough` against both testsrc2 and a real overhead camera.

## Test plan

- Unit-test the state machine (idle → publishing → error → idle), and the reassignment path (publishing-to-old-url → publishing-to-new-url with explicit blackout assertion)
- Integration test against a local MediaMTX in CI via a docker-compose service
- 24 h soak on a real camera in Phase 6 to validate the `BrokenPipeError` reopen loop under sustained idle/active cycles

## Versioning

`[minor:actuate-pullers]` on the squash commit. The `StreamPublisher` import is new public surface; the underlying `AvUrlFramePuller.__init__` change is additive (instantiation + one call site in the demux loop). No breaking change for existing consumers.

## Related

- [[2026-05-19_live-streaming-v1-plan|Live Streaming v1 Plan]] — the umbrella synthesis
- [[2026-05-19_pyav17-ffmpeg8-migration|PyAV 17 / FFmpeg 8 migration]] — concurrent change to the same file
- [[2026-05-19_streaming-pyav17-crosscut|The crosscut]] — sequencing recommendation
- [[actuate-pullers]] — library entity
- Confluence source: EDOCS/579862531 §1 actuate-libraries/[[actuate-pullers]]
