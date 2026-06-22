---
title: "Streaming endpoints in actuate_monitoring_api"
type: concept
topic: admin-api
tags: [actuate-monitoring-api, live-streaming, jwt, hmac, authorization, mediamtx, reconciliation, sqs-fifo]
created: 2026-05-19
updated: 2026-05-19
author: kb-bot
sources:
  - https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/579862531
incoming:
  - topics/infrastructure/notes/concepts/2026-05-19_mediamtx-chart-design.md
  - topics/personal-notes/notes/daily/2026-05-19.md
  - topics/vms-connector/notes/syntheses/2026-05-19_live-streaming-v1-plan.md
  - topics/vms-connector/notes/syntheses/2026-05-19_live-streaming-v1-status.md
incoming_updated: 2026-05-20
---

# Streaming endpoints (actuate_monitoring_api)

The control plane for [[2026-05-19_live-streaming-v1-plan|Live Streaming v1]]. New module `monitoring/views/streaming/` mounted under `/monitoring-api/streaming/`. Owns session issuance, MediaMTX assignment, the reconciliation worker, and ICE telemetry intake.

## Endpoint surface

| Method | Path | Caller | Purpose |
|---|---|---|---|
| POST | `/streaming/stream-session/<camera_id>` | camera-ui (operator session cookie) | Authorize, assign MediaMTX pod, issue 300 s JWT, return `{whep_url, token, expires_at, session_id}` |
| POST | `/streaming/ice-event/<session_id>` | camera-ui (per-event) | Append `{state, age_ms}` for fleet ICE-failure-rate metric |
| POST | `/_internal/mediamtx/on-demand` | MediaMTX (HMAC-signed) | Publisher requested for a path → dispatch SQS `pushing` |
| POST | `/_internal/mediamtx/on-unread` | MediaMTX (HMAC-signed) | Last viewer left → 60 s debounce → SQS `idle` |
| POST | `/_internal/mediamtx/heartbeat` | camera-ui (per 15 s) | Update `StreamSession.last_heartbeat_at`; absent for 90 s = force-expire |

There is no `/_internal/mediamtx/auth`. MediaMTX validates WHEP JWTs locally — no per-request callback to monitoring-api.

## Authorization model (highest reuse value)

The `stream-session` view reuses [[actuate-monitoring-api]]'s existing primitives from `monitoring/views/alert_routing_view.py:34,62`:

```python
def create(self, request, camera_id):
    camera = get_object_or_404(
        Camera.objects.filter(customer__group__in=Group.objects.with_access(request.user)),
        id=camera_id,
    )
    check_access_to_customer(request, camera.customer)  # belt + suspenders
    if not camera.streaming_eligible:
        raise PermissionDenied("camera not enabled for streaming")
    # quota check, JWT issue, SQS push...
```

Three layered checks:
1. **`get_object_or_404` against the access-filtered queryset** — returns 404 for both "doesn't exist" and "exists-but-you-can't-see-it." Closes the camera-ID enumeration channel.
2. **`check_access_to_customer`** — redundant but cheap and prevents future drift if either primitive changes.
3. **`streaming_eligible` ([[actuate_admin]] floor)** — even an authorized operator can't request a stream on a camera that's been opted out at the admin level.

Heartbeat and ICE-event endpoints lookup by `session_id` and verify `request.user == session.user` — a leaked `session_id` can't be re-pointed at a different camera.

## JWT claims

```
{
  sub: user_id,
  aud: "mediamtx",
  path: "cam/<camera_id>",
  customer_id,
  exp: now + 300
}
```

HS256 signed with a shared secret in [[secrets-management|AWS Secrets Manager]] (via External Secrets Operator). MediaMTX validates signature, `exp`, `aud == "mediamtx"`, and that `path` claim matches the requested path. **No callback to monitoring-api per request** — local check, no round-trip latency.

If the token were exfiltrated, MediaMTX rejects any request whose path doesn't match `cam/<that_one_camera>`. The 300 s TTL bounds the exfiltration window.

**Out of scope for v1:** live revocation. If an operator is fired during a 300 s session window, their token remains valid until expiry. Adding a small Redis revocation list checked by MediaMTX is the proposed v1.1 path (see Confluence Open Question 9).

## HMAC on lifecycle webhooks

All `/_internal/mediamtx/*` endpoints require an HMAC signature on the request body using a shared secret with MediaMTX (Secrets Manager → ESO). Protects against random callers hitting the lifecycle hooks. Standard pattern; rotates with the publisher token.

## Models

- **`CameraStreamingAssignment`** — `camera_id → (customer_name, connector_pod_id, shard_index, az, mediamtx_pod_id)`. SQS queue URLs and MediaMTX hostnames are **derived from these fields at send time**, not stored as URLs. Keeps the row stable across DNS / chart changes.
- **`StreamSession`** — audit row: `user_id, camera_id, customer_id, source_ip, started_at, ended_at, mediamtx_instance, end_reason, terminal_ice_state, last_heartbeat_at`. Confluence Open Q6: ~5–10K rows/day at terminal scale; proposed 90 days hot + S3 archive.
- **`StreamingQuotaCounter`** — denormalized `(user_id, camera_id, date) → minutes_used`. Soft cap 60 min/day (warning modal), hard cap 4 h/day (refuse). Configurable per role.

## SQS dispatch

Per-customer **FIFO** queue, separate from the existing standard motion-signals queue: `stream-{customer_name}.fifo`. Streaming requires per-camera ordering (declarative-state semantics with `MessageGroupId = camera_id`); motion signals don't. State-declaration payload: `{camera_id, desired_state, mediamtx_target, as_of_ts}`. `mediamtx_target` is the **specific pod's internal hostname** (e.g. `mediamtx-us-west-2a-1.streaming.svc.cluster.local:8554`), set by monitoring-api when transitioning to `pushing`.

IAM is IRSA — same role pattern as motion-signal queues.

## Reconciliation worker

`streaming/reconciliation.py` — every 30–60 s:

- Polls each MediaMTX instance's API for active paths
- Compares against expected state from `CameraStreamingAssignment` + recent webhook events
- Emits corrective SQS messages for drift
- **Handles MediaMTX scale-up/down:** when `replicas` per AZ changes, the consistent hash ring shifts. Worker recomputes assignments, emits `idle` to old targets and `pushing` (with new `mediamtx_target`) to the connector for affected cameras. Brief blackout (~1 [[gop-keyframe-fundamentals|keyframe interval]]).
- **Handles connector pod restart:** next cycle sees missing publisher for an active session, re-sends `pushing` SQS with the current `mediamtx_target`.

## Metrics emitted

- `monitoring_api_stream_session_created_total{camera_id, user_id}`
- `monitoring_api_stream_session_denied_total{reason: no_access|not_eligible|quota_exceeded}` — surfaces auth-bypass attempts
- `monitoring_api_stream_session_egress_bytes{user_id}` — nightly egress audit input
- `monitoring_api_stream_ice_total{terminal_state}` / `_failures_total` — drives TURN-deployment decision (Phase 6)
- `monitoring_api_reconciliation_drift_total`

## Related

- [[2026-05-19_live-streaming-v1-plan]] — umbrella plan
- [[2026-05-19_mediamtx-chart-design]] — what's on the other end of the JWT
- [[actuate-monitoring-api]] — service entity
- Pattern source: `actuate_monitoring_api/monitoring/views/alert_routing_view.py:34,62`
- Confluence: EDOCS/579862531 §5 [[actuate-monitoring-api|actuate_monitoring_api]]
