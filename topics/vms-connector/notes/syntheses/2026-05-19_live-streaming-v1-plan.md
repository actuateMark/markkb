---
title: "Live Streaming for Operator Viewing — v1 Plan (decomposed)"
type: synthesis
topic: vms-connector
tags: [live-streaming, mediamtx, webrtc, whep, pyav, push-on-demand, actuate-pullers, monitoring-api, jacob-weiss, §30]
created: 2026-05-19
updated: 2026-05-19
author: kb-bot
outgoing:
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/video-processing/notes/concepts/2026-05-18_mediamtx.md
sources:
  - https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/579862531/Live+Streaming+for+Operator+Viewing+v1+Plan
incoming:
  - topics/actuate-libraries/notes/concepts/2026-05-19_pyav17-ffmpeg8-migration.md
  - topics/actuate-libraries/notes/concepts/2026-05-19_stream-publisher-design.md
  - topics/admin-api/notes/concepts/2026-05-19_streaming-monitoring-api.md
  - topics/infrastructure/notes/concepts/2026-05-19_mediamtx-chart-design.md
  - topics/personal-notes/notes/daily/2026-05-19.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/vms-connector/notes/concepts/2026-06-02_handoff-pyav17-corner-case-plan.md
  - topics/vms-connector/notes/syntheses/2026-05-19_live-streaming-v1-status.md
  - topics/vms-connector/notes/syntheses/2026-05-19_streaming-pyav17-crosscut.md
incoming_updated: 2026-06-19
---

# Live Streaming for Operator Viewing — v1 Plan

Distilled from [[jacob-weiss|Jacob Weiss]]'s 2026-05-14 EDOCS draft (Confluence page 579862531). The plan lets operators view live camera feeds in camera-ui without adding a second [[rtsp-deep-dive|RTSP]] connection to the camera or breaking the inference path. The architectural commitment is **passthrough mux** off the existing connector demux loop into [[2026-05-18_mediamtx|MediaMTX]], then WHEP/[[webrtc-deep-dive|WebRTC]] to the browser. Phase 0 spike is complete; Phases 1–6 are the v1 commitment.

## The architectural lever

The vms-connector already maintains one [[rtsp-deep-dive|RTSP]] connection per camera for inference. The plan threads a `StreamPublisher` collaborator into [[actuate-pullers]]'s `AvUrlFramePuller` demux loop and, when commanded, passthrough-muxes [[h264-deep-dive|H.264]] packets out to MediaMTX *before* the decode step. Inference is unaffected — packets fork; they don't queue. See [[2026-05-19_stream-publisher-design]].

Phase 0 spike measured per-camera overhead at **+1% of one core and +0 MB RSS** when a stream is publishing. Idle cost is zero — the publisher is a no-op until `set_enabled` is called from SQS.

## Six-repo v1 split

| Repo | Change | Concept |
|---|---|---|
| [[actuate-pullers]] | `StreamPublisher` collaborator on `AvUrlFramePuller`, codec gate, `BrokenPipeError` reopen-on-keyframe | [[2026-05-19_stream-publisher-design]] |
| [[actuate-config]] | `StreamingConfig.enabled` (site) + `CameraStream.streaming_eligible` (per-camera) | same as above |
| vms-connector | `streaming/stream_command_consumer.py` (post-fork, per-customer FIFO SQS), publisher-token env var, `POD_AZ` downward API | this synthesis |
| [[kubernetes-deployments]] | New `mediamtx/` Helm chart — StatefulSet per AZ, per-pod Ingress hostnames, JWT auth, ICE-TCP via ALB:443, [[argocd|ArgoCD]] app | [[2026-05-19_mediamtx-chart-design]] |
| [[actuate-monitoring-api|actuate_monitoring_api]] | New `monitoring/views/streaming/`: `stream-session`, internal MediaMTX lifecycle webhooks, ICE-event sink, reconciliation worker, JWT issuance | [[2026-05-19_streaming-monitoring-api]] |
| camera-ui | `<LiveStream>` WHEP component behind LD flag `enable-live-streaming`, heartbeat + ICE telemetry + idle protections | (in this synthesis until split out) |
| [[actuate_admin]] (Phase 5) | `Camera.streaming_eligible: bool` field + admin checkbox + settings.json export | (deferred) |

## Push-on-demand flow

1. Operator clicks "View live" → camera-ui `POST /monitoring-api/streaming/stream-session/<id>`
2. monitoring-api **authorizes** via existing `Group.objects.with_access(request.user)` + `check_access_to_customer` + `streaming_eligible`, issues 300 s JWT with claims `{sub, aud, path: cam/<id>, exp}`, returns `{whep_url, token, session_id}`
3. Browser opens `RTCPeerConnection`, POSTs SDP offer to WHEP URL with bearer token
4. MediaMTX **validates JWT locally** (HS256, signature/exp/aud/path-claim — no callback to monitoring-api)
5. No publisher → MediaMTX fires `on-demand` webhook (HMAC-signed body) → monitoring-api pushes SQS FIFO message `{camera_id, desired: pushing, mediamtx_target}` to the owning customer's queue
6. Connector consumer (`stream_command_consumer.py`) calls `puller.stream_publisher.set_enabled(True, target_url)`; demux loop waits for next keyframe, opens [[rtsp-deep-dive|RTSP]] output, starts muxing
7. Browser sends `/heartbeat` every 15 s; reconciliation worker force-expires sessions on >90 s gaps → 60 s debounce → `idle` SQS → connector stops pushing

Worst-case "browser closed" → connector idle: ~150 s. Graceful close: ~60 s.

## Hard architectural commitments

- **AZ-local invariant.** `mediamtx_pod_id ∈ pods_in(camera.az)`. The expensive leg (camera × bitrate) stays inside one AZ. Browser → MediaMTX may cross AZs (small egress).
- **Assigned-pod, not load-balanced.** Publisher and viewer must land on the same MediaMTX pod ([[rtsp-deep-dive|RTSP]] publish + [[webrtc-deep-dive|WebRTC]] fan-out are pod-local). monitoring-api owns assignment via consistent hash within an AZ; per-pod Ingress hostnames give each pod a stable external identity.
- **Push-on-demand only.** Cameras only publish while at least one operator is watching. Cost scales with viewer activity, not camera count — this is what makes the economics work (terminal-scale egress ~$26K/mo vs always-on which would be ~30× worse).
- **[[h264-deep-dive|H.264]] only in v1.** Codec gate fires at connect time on `video_stream.codec_context.codec.name`. [[h265-hevc-deep-dive|HEVC]] + [[mjpeg-and-still-image-formats|MJPEG]] cameras are silently non-publishable until v2 ([[hardware-accelerated-codecs|NVENC]] transcode).
- **No TURN in v1.** ICE-TCP on MediaMTX + ALB:443 routing + per-pod Ingress is the free mitigation. Phase 6 measures fleet ICE failure rate; only deploys TURN if >3% sustained or >10% in any segment.

## Auth model (highest reuse value)

The `stream-session` view reuses [[actuate-monitoring-api]]'s existing `Group.objects.with_access` + `check_access_to_customer` primitives (pattern from `monitoring/views/alert_routing_view.py`). `get_object_or_404` against the access-filtered Camera queryset returns 404 for both "doesn't exist" and "exists-but-you-can't-see-it" — closes camera-ID enumeration. JWT path claim binds the token to one camera; MediaMTX validates locally so no per-request callback. Detail + diagram: [[2026-05-19_streaming-monitoring-api]].

## Cost shape

- **Dev (Phase 1–3):** ~$300/mo
- **Pilot (Phase 5):** ~$1,200/mo
- **Full rollout (Phase 6, ~2K avg concurrent viewers):** ~$26,000/mo, ~90 % egress

Biggest lever is **defaulting `<LiveStream>` to substream** (halves egress, ~$13K/mo savings at terminal scale). Strict idle/off-tab enforcement saves the long tail of forgotten tabs.

Phase 7 (recording for flagged cameras) inverts push-on-demand — costs scale with `flagged_cameras × retention × bitrate`. EBS gp3 stays economical below ~3–4 days retention; above that, a dedicated S3-backed recording service starts to pay for itself. Not in v1.

## Where this intersects with #1703

This plan was prototyped on [[pyav-entity|PyAV]] 13.1.0. The `StreamPublisher` mux code lives in the same `av_url_puller.py` that issue [vms-connector#1703](https://github.com/aegissystems/vms-connector/issues/1703) wants to migrate to [[pyav-entity|PyAV]] 17 / [[ffmpeg-entity|FFmpeg]] 8. The `except av.AVError` → `except av.FFmpegError` rename matters because `StreamPublisher`'s `BrokenPipeError` recovery loop catches `OSError`; if we leave the surrounding error catches on the old name we'll regress on the streaming path the day the bump lands. Treated end-to-end in [[2026-05-19_streaming-pyav17-crosscut]].

## Related

- **Status tracker (live):** [[2026-05-19_live-streaming-v1-status]]
- Source: Confluence EDOCS/579862531 ([[jacob-weiss|Jacob Weiss]], 2026-05-14, version 7)
- MediaMTX background: [[2026-05-18_mediamtx]]
- [[webrtc-deep-dive|WebRTC]] primitives: [[2026-05-18_pion-webrtc]], [[webrtc-deep-dive]]
- Cross-cut with bump: [[2026-05-19_streaming-pyav17-crosscut]]
- Bump itself: [[2026-05-19_pyav17-ffmpeg8-migration]]
- Auth pattern source: `actuate_monitoring_api/monitoring/views/alert_routing_view.py:34,62`
- Workstream: §30 in `mark-todos.md`
