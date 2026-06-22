---
title: "Live Streaming v1 — status tracker"
type: synthesis
topic: vms-connector
tags: [live-streaming, mediamtx, webrtc, whep, pyav, push-on-demand, actuate-pullers, monitoring-api, status-tracker, §30]
created: 2026-05-19
updated: 2026-05-19
author: kb-bot
outgoing:
  - topics/vms-connector/notes/syntheses/2026-05-19_live-streaming-v1-plan.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming:
  - topics/personal-notes/notes/daily/2026-05-19.md
  - topics/personal-notes/notes/daily/2026-05-20.md
  - topics/profiling-and-performance/notes/concepts/2026-05-19_cv2-dst-soak-status.md
  - topics/vms-connector/notes/syntheses/2026-05-19_live-streaming-v1-plan.md
incoming_updated: 2026-05-27
---

# Live Streaming v1 — status tracker

> 🛑 **Do NOT begin implementation work on Phases 1–6 without explicit user approval.** Project is documented but execution is paused. The cv2-dst preallocation soak ([[2026-05-19_cv2-dst-soak-status]]) and the PyAV-17 bump ([vms-connector#1703](https://github.com/aegissystems/vms-connector/issues/1703)) must land first; the `StreamPublisher` mux code sits in the same `av_url_puller.py` that #1703 rewrites. Set per user instruction 2026-05-20. KB writes, design refinement, and cross-cut analysis are fine; branch creation, code edits, or PR drafts in any of the six target repos are not.

The durable "where are we" view for the Live Streaming for Operator Viewing v1 project (Confluence EDOCS/579862531, [[jacob-weiss|Jacob Weiss]]). Companion to [[2026-05-19_live-streaming-v1-plan]] which is the **plan**; this note is the **status**. Update by appending dated entries to the **History** section and editing the Phase Status table + Per-repo Branch State + Blockers as state changes — never rewrite history entries.

> **Convention.** Status fields are short. Detail belongs in linked phase notes / per-repo concept notes / handoff notes. This tracker stays scannable across sessions.

## Phase Status

| Phase | Scope | Status | Started | Landed | Owner | Notes |
|---|---|---|---|---|---|---|
| 0 — Spike | Passthrough mux prototype on `AvUrlFramePuller` + MediaMTX | ✅ Done | pre-2026-05-14 | 2026-05-14 | Jacob | +1% / +0 MB RSS per camera when publishing; idle no-op |
| 1 — [[actuate-pullers]] + [[actuate-config]] | `StreamPublisher` collaborator, codec gate, `BrokenPipeError` reopen-on-keyframe; `StreamingConfig.enabled` + `CameraStream.streaming_eligible` | ⬜ Not started | — | — | — | Design in [[2026-05-19_stream-publisher-design]] |
| 2 — vms-connector | `streaming/stream_command_consumer.py` (post-fork, per-customer FIFO SQS), publisher-token env var, `POD_AZ` downward API | ⬜ Not started | — | — | — | Fork-safety rules from `CLAUDE.md` apply |
| 3 — [[kubernetes-deployments]] | `mediamtx/` Helm chart — StatefulSet per AZ, per-pod Ingress hostnames, JWT auth, ICE-TCP via ALB:443, [[argocd|ArgoCD]] app | ⬜ Not started | — | — | — | Design in [[2026-05-19_mediamtx-chart-design]] |
| 4 — [[actuate-monitoring-api|actuate_monitoring_api]] | `monitoring/views/streaming/` — `stream-session`, MediaMTX lifecycle webhooks, ICE-event sink, reconciliation worker, JWT issuance | ⬜ Not started | — | — | — | Design in [[2026-05-19_streaming-monitoring-api]]; auth pattern from `monitoring/views/alert_routing_view.py` |
| 5 — camera-ui + [[actuate_admin]] | `<LiveStream>` WHEP component behind LD flag `enable-live-streaming`; admin `Camera.streaming_eligible` field + settings.json export | ⬜ Not started | — | — | — | Phase 5 only — pilot gate |
| 6 — Pilot + scale-out | LD ramp, fleet ICE failure measurement, TURN-or-not decision | ⬜ Not started | — | — | — | Goes/no-goes on TURN if ICE failure >3% sustained or >10% any segment |

Legend: ⬜ not started · 🟡 in progress · 🔵 blocked · ✅ done

## Per-repo Branch State

| Repo | Branch | State |
|---|---|---|
| [[actuate-pullers]] | — | No branch yet |
| [[actuate-config]] | — | No branch yet |
| vms-connector | — | No branch yet |
| [[kubernetes-deployments]] | — | No branch yet |
| [[actuate-monitoring-api|actuate_monitoring_api]] | — | No branch yet |
| camera-ui | — | No branch yet |
| [[actuate_admin]] | — | No branch yet (Phase 5 only) |

## Blockers / Open Decisions

- **[[pyav-entity|PyAV]] 17 cross-cut.** Phase 1's `StreamPublisher` mux code lives in `av_url_puller.py` — the same file vms-connector#1703 wants to migrate to [[pyav-entity|PyAV]] 17 / [[ffmpeg-entity|FFmpeg]] 8. Order matters: the `except av.AVError` → `except av.FFmpegError` rename around the `BrokenPipeError` recovery loop must land on the same side of the bump as the `StreamPublisher` code. Full treatment: [[2026-05-19_streaming-pyav17-crosscut]]. **Open:** do we land #1703 before Phase 1, or carry the `StreamPublisher` rename forward into the bump PR?
- **Codec gate scope.** [[h264-deep-dive|H.264]] only in v1. [[h265-hevc-deep-dive|HEVC]] + [[mjpeg-and-still-image-formats|MJPEG]] cameras silently non-publishable until v2 ([[hardware-accelerated-codecs|NVENC]] transcode). Confirmed scope.
- **No TURN in v1.** ICE-TCP + ALB:443 + per-pod Ingress is the free mitigation; Phase 6 measures and decides on TURN.
- **Push-on-demand only.** Cost shape commits to this — terminal-scale egress ~$26K/mo vs ~30× worse always-on.

## Hard architectural commitments (carried from the plan)

- **AZ-local invariant** — `mediamtx_pod_id ∈ pods_in(camera.az)`. The expensive leg (camera × bitrate) stays inside one AZ.
- **Assigned-pod, not load-balanced** — publisher and viewer must land on the same MediaMTX pod. monitoring-api owns assignment via consistent hash within an AZ.
- **JWT validated locally at MediaMTX** — no per-request callback to monitoring-api. Path claim binds the token to one camera.
- **`get_object_or_404` against access-filtered Camera queryset** — closes camera-ID enumeration; 404 for both "doesn't exist" and "exists-but-you-can't-see-it".

## Cost shape (carried from the plan)

| Phase | Monthly | Notes |
|---|---|---|
| Dev (Phase 1–3) | ~$300 | dev cluster + dev MediaMTX |
| Pilot (Phase 5) | ~$1,200 | LD-gated subset of customers |
| Full (Phase 6) | ~$26,000 | ~2K avg concurrent viewers, ~90 % egress |

Biggest unspent lever: defaulting `<LiveStream>` to substream halves egress (~$13K/mo at terminal scale).

## Next Action

Land the cv2-dst webcam re-run (see [[2026-05-19_cv2-dst-soak-status]]) so the §30 instrumentation harness clears its papercut backlog; then re-evaluate Phase 1 sequencing vs the #1703 bump.

## History

- **2026-05-14** — Phase 0 spike measured (+1% / +0 MB RSS per camera when publishing, idle no-op). Confluence page 579862531 published v7.
- **2026-05-19** — Plan decomposed into KB: umbrella [[2026-05-19_live-streaming-v1-plan]], per-repo concepts ([[2026-05-19_stream-publisher-design]], [[2026-05-19_mediamtx-chart-design]], [[2026-05-19_streaming-monitoring-api]]), cross-cut with #1703 ([[2026-05-19_streaming-pyav17-crosscut]]). This status tracker created the same day during a session-wrap after a lost session; phases 1–6 not yet started.

## Related

- Plan: [[2026-05-19_live-streaming-v1-plan]]
- Per-repo design notes: [[2026-05-19_stream-publisher-design]], [[2026-05-19_mediamtx-chart-design]], [[2026-05-19_streaming-monitoring-api]]
- [[pyav-entity|PyAV]] 17 cross-cut: [[2026-05-19_streaming-pyav17-crosscut]]
- MediaMTX background: [[2026-05-18_mediamtx]]
- Workstream: §30 in `mark-todos.md` (umbrella for profiling + streaming work)
- Confluence source: EDOCS/579862531 ([[jacob-weiss|Jacob Weiss]], v7, 2026-05-14)
