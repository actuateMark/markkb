---
title: "Live Streaming v1 ↔ #1703 PyAV/FFmpeg bump — sequencing crosscut"
type: synthesis
topic: vms-connector
tags: [live-streaming, pyav, ffmpeg, av_url_puller, sequencing, §30, dependency-bump]
created: 2026-05-19
updated: 2026-05-19
author: kb-bot
incoming:
  - topics/actuate-libraries/notes/concepts/2026-05-19_pyav17-ffmpeg8-migration.md
  - topics/actuate-libraries/notes/concepts/2026-05-19_stream-publisher-design.md
  - topics/personal-notes/notes/daily/2026-05-19.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/vms-connector/notes/syntheses/2026-05-19_live-streaming-v1-plan.md
  - topics/vms-connector/notes/syntheses/2026-05-19_live-streaming-v1-status.md
  - topics/vms-connector/notes/syntheses/2026-05-26_pyav17-local-validation.md
incoming_updated: 2026-05-27
---

# Streaming v1 ↔ #1703 crosscut

The two concurrent changes both modify `actuate-pullers/src/actuate_pullers/url/av_url_puller.py` — the same file. The Live Streaming v1 plan threads a `StreamPublisher` collaborator into the demux loop ([[2026-05-19_stream-publisher-design]]); [vms-connector#1703](https://github.com/aegissystems/vms-connector/issues/1703) bumps the [[pyav-entity|PyAV]] API the file uses ([[2026-05-19_pyav17-ffmpeg8-migration]]). Order matters.

## Overlap surface (concrete, not theoretical)

| Touchpoint | Streaming v1 needs it | #1703 changes it |
|---|---|---|
| `except av.AVError` in `autopatrol_websocket_stream_puller.py:251,371` | `StreamPublisher`'s `BrokenPipeError` recovery is one `OSError` catch over from these | renames to `av.FFmpegError` |
| `codec_context.skip_frame = "DEFAULT"/"NONKEY"` (6 sites in `av_url_puller.py`) | codec gate uses `codec_context.codec.name` — adjacent API surface | replace string with `SkipType` enum |
| `av.open(url, mode="w", format="rtsp")` + `add_stream(template=...)` + `packet.stream = ...; mux()` | Phase 0 spike measured this on [[pyav-entity|PyAV]] 13.1 | [[pyav-entity|PyAV]] 17 keeps the API but FFmpeg-8 ABI under the hood changes [[rtsp-deep-dive|RTSP]] transport defaults + demuxer probe behavior |
| Custom `build_ffmpeg.sh` ([[ffmpeg-entity|FFmpeg]] n7.1.3) in `docker_files/dependencies/` | streaming inherits whatever Dockerfile shape lands first; nothing required from streaming side | option to drop entirely (stock [[pyav-entity|PyAV]] 17 wheel bundles [[ffmpeg-entity|FFmpeg]] 8.0) |
| `frame.rotation` (new in [[pyav-entity|PyAV]] 14.1.0) | passthrough mux doesn't decode, so not used by streaming | optional cleanup: replaces 20 lines of manual displaymatrix matrix math in `av_url_puller.py:143` |

## The actual coupling

The `StreamPublisher`'s own error handling catches `OSError` from `mux()` calls — *that doesn't change*. But the file it lives in catches `av.AVError` in two unrelated sites. If we land streaming first against [[pyav-entity|PyAV]] 13's `av.AVError`, and then land #1703, we have to migrate the streaming-adjacent exception handling at the same time. If we land #1703 first, streaming code gets written against the modern names from day 1.

This is a one-PR problem either way; the question is which PR.

## Likely strategic motivation for #1703 (the user's hunch)

The MISS-685 / [[h265-hevc-deep-dive|HEVC]] corruption framing is the primary driver — that case stands alone. But there's a second motivation that's worth naming:

**The Live Streaming v1 plan was Phase-0-validated on [[pyav-entity|PyAV]] 13.1.0.** If the v1 build phases (Phase 1 lands `StreamPublisher`, Phase 2 lands MediaMTX chart, etc.) proceed on [[pyav-entity|PyAV]] 13 and *then* we bump to v17, the streaming code has to be re-validated against the new [[ffmpeg-entity|FFmpeg]] ABI ([[rtsp-deep-dive|RTSP]] transport defaults, container teardown timing, demuxer probe behavior — all changed at the [[ffmpeg-entity|FFmpeg]] 6 → 8 boundary). Doing the bump first means streaming Phase 1 is written and validated **once**, on the long-term API surface.

Additionally:
- The Dockerfile cleanup (dropping `build_ffmpeg.sh`) is a connector-image change. Both streaming and #1703 will rebuild the connector image; landing the cleanup with the bump means the streaming chart deploys against a smaller / faster-built image from Phase 1.
- [[h265-hevc-deep-dive|HEVC]] corruption affects inference *now*, on cameras that streaming v1 won't touch ([[h265-hevc-deep-dive|HEVC]] is gated out of streaming v1 per the codec gate). But customers with mixed [[h265-hevc-deep-dive|HEVC]] + [[h264-deep-dive|H.264]] fleets get the inference-path corruption fix *and* the [[h264-deep-dive|H.264]] streaming path simultaneously.

## Recommended sequencing

```
NOW                                                  Phase 6 / TURN decision
 │                                                              │
 ▼                                                              ▼
 ├─ #1703 library feature branch ─┐
 │   (actuate-pullers PyAV bump)   │
 │                                  ▼
 │                            dev wheel published
 │                                  │
 │                                  ▼
 │                   ┌── vms-connector dev pin ──── cust 41399 (AmeriGas) soak ──┐
 │                   │                                                            │
 │                   │   (clean signal: HEVC corruption + reconnect rate)         │
 │                   │                                                            ▼
 │                   │                                                       stage merge
 │                   │                                                            │
 │                   ▼                                                            │
 │       Streaming Phase 1 (StreamPublisher) ─────────────────────────────────────┤
 │       written against av.FFmpegError + SkipType from day 1                     │
 │                                                                                ▼
 └──── Streaming Phases 2-6 proceed in parallel ─────────────────────  v1 to ops
```

**Sequencing rule of thumb:**
- Streaming Phase 1 (`StreamPublisher` in [[actuate-pullers]]) **should be written against [[pyav-entity|PyAV]] 17 API surface from day 1**, even if it ships before the bump fully lands. Cheap insurance against having to migrate the new code on the same PR.
- The bump testing arc (AmeriGas soak → stage → rearch) and the streaming dev arc are independent until the bump lands stable; they re-converge when streaming Phase 1 needs to ship.

## Anti-recommendation

Don't bundle #1703 and Streaming Phase 1 into one PR. They have orthogonal risk surfaces ([[h265-hevc-deep-dive|HEVC]] NALU rejection vs [[rtsp-deep-dive|RTSP]] passthrough mux) and orthogonal validation arcs (single MISS-685 site vs multi-component WHEP handshake). A bug in either is harder to attribute if they ship together.

## Related

- [[2026-05-19_live-streaming-v1-plan]] — the streaming plan
- [[2026-05-19_pyav17-ffmpeg8-migration]] — the bump risk surface
- [[2026-05-19_stream-publisher-design]] — the specific [[actuate-pullers]] diff
- Workstream: §30 in `mark-todos.md`
- Issue: [vms-connector#1703](https://github.com/aegissystems/vms-connector/issues/1703)
- Source PR (superseded): [vms-connector#1621](https://github.com/aegissystems/vms-connector/pull/1621)
