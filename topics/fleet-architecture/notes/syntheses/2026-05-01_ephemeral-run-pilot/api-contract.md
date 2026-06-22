---
title: "Run Service — API Contract"
type: synthesis
topic: fleet-architecture
tags: [fleet-architecture, run-service, control-plane, api-gateway, api-contract, run-spec, detection-events, dynamodb]
created: 2026-05-01
updated: 2026-05-01
author: kb-bot
status: drafting
incoming:
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/paradigm-c.md
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/paradigm-d.md
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/paradigm-e.md
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/translation-layer.md
incoming_updated: 2026-05-27
---

# Run Service — API Contract

Public API surface for [[_overview|run-service]]. Defines `RunSpec.v1`, `DetectionEvent.v1`, lifecycle endpoints, auth, alert plumbing, event-delivery channels, error taxonomy, and the DynamoDB schema. Independent of which fleet paradigm executes the run (C, D, or E).

## Surface map

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/v1/runs` | Create a run (`mode: ephemeral` or `mode: persistent`). Returns `run_id` + status URL. |
| `GET` | `/v1/runs/{run_id}` | Poll run state, per-camera stream health, event counts, latest events. |
| `DELETE` | `/v1/runs/{run_id}` | Cancel (ephemeral) or stop (persistent); pod gets SIGTERM, drains. |
| `GET` | `/v1/runs/{run_id}/events` | SSE stream of `DetectionEvent.v1`; live tail or replay (when enabled). |
| `POST` | `/v1/alert-configs` | Pre-register an alert routing config; returns short id. |
| `GET` | `/v1/alert-configs/{id}` | Read back. |
| `DELETE` | `/v1/alert-configs/{id}` | Revoke. |
| `POST` | `/v1/secrets` | Pre-register a secret (webhook signing key, integration creds, etc.); returns short id. |
| `GET` | `/v1/healthz` | Liveness for the API itself (not for runs). |

Versioned in URL path. v2 lives at `/v2/runs` for breaking changes. Within v1, only **additive** changes (new optional fields, new enum values surfaced via `warnings[]`).

## Auth — two modes behind one authorizer

A single Lambda authorizer handles both. The authorizer attaches a `principal` object to the request context with `{tenant_id, identity, scopes}` regardless of which mode authenticated.

| Mode | Use case | Identity material |
|---|---|---|
| **API key + tenant** | Partner integrations, autopatrol-style callers, sales scripts | `X-API-Key` header + `tenant_id` in the payload (validated against the key's allowed tenants in DynamoDB) |
| **Cognito** | Internal users, customer-portal callers | Bearer token; `tenant_id` derived from token claims, payload field optional but if present must match |

Both modes resolve to the same downstream principal contract; the orchestrator Lambda does not branch on auth mode after the authorizer runs.

**Why both:** API key is fastest to provision for partners and doesn't require Cognito user records. Cognito gives proper per-user identity for internal tooling and the future customer portal. Picking one now would foreclose the other; running both behind one authorizer costs ~80 lines of code and zero ongoing complexity.

## `RunSpec.v1` — request body for `POST /v1/runs`

```json
{
  "spec_version": "v1",
  "mode": "ephemeral",
  "name": "smith-warehouse-trial",
  "tenant_id": "acme-corp",
  "duration_seconds": 3600,
  "callback_url": "https://acme.example.com/hooks/runs",
  "events_webhook_url": "https://acme.example.com/hooks/events",
  "idempotency_key": "sales-demo-2026-05-01-bay-7",

  "site": {
    "integration_type": "rtsp",
    "locale": "us",
    "timezone": "US/Eastern"
  },

  "cameras": [
    {
      "id": "cam-1",
      "name": "Loading Bay",
      "rtsp": {
        "url": "rtsp://158.106.215.138:8500/live",
        "username": "viewer",
        "password": "...",
        "transport": "tcp"
      },
      "schedule": { "mode": "always" },
      "crop": null,
      "products": [
        {
          "product": "intruder",
          "sensitivity": "medium",
          "models": ["weapon-mid"],
          "zones": [],
          "line_crossings": [],
          "alert_triggers": ["main-ops"]
        },
        {
          "product": "loitering",
          "sensitivity": "low",
          "alert_triggers": ["main-ops"]
        }
      ]
    }
  ],

  "alerts": [
    {
      "id": "main-ops",
      "channels": [
        { "type": "email",       "address": "ops@acme.example.com" },
        { "type": "sms",         "number":  "+15551234567" },
        { "type": "webhook",     "url": "https://acme.example.com/alerts", "secret_id": "sec_x9k2" },
        { "type": "sns",         "topic_arn": "arn:aws:sns:us-east-1:000000000000:acme-alerts" },
        { "type": "integration", "kind": "crisis_go", "config": { "site_id": "..." } }
      ],
      "triggers": ["product_alert"]
    },
    {
      "id": "ops-on-call",
      "channels": [{ "type": "sms", "number": "+15551234999" }],
      "triggers": ["healthcheck", "scene_change", "stream_quality", "connectivity"]
    }
  ],

  "events": {
    "delivery": ["sse", "webhook"],
    "include_frames": true,
    "frame_url_ttl_seconds": 3600,
    "include_tracker_ids": true,
    "replay_enabled": false
  }
}
```

### Top-level fields

| Field | Type | Required | Notes |
|---|---|---|---|
| `spec_version` | string | yes | Always `"v1"` for this schema. |
| `mode` | enum | yes | `"ephemeral"` or `"persistent"`. (`"scheduled"` reserved for future.) |
| `name` | string | yes | Human-readable label, ≤64 chars. Surfaced in status, alerts, NR tags. |
| `tenant_id` | string | yes | Validated against authorizer principal. |
| `duration_seconds` | int | conditional | Required when `mode: ephemeral` (60 ≤ value ≤ 86400). Forbidden when `mode: persistent`. |
| `callback_url` | string | no | HTTPS-only URL for **run-state-transition** webhooks (lifecycle, not events). |
| `events_webhook_url` | string | no | HTTPS-only URL for **per-detection** webhooks. |
| `idempotency_key` | string | no | Tenant-scoped, 24h window. Re-POSTing same key returns the same `run_id`. |
| `site` | object | yes | Site-level integration config and metadata. |
| `cameras` | array | yes | 1 ≤ count ≤ 48 per run (initial cap; tunable per tenant). |
| `alerts` | array | conditional | Required if any product references an `alert_trigger`. |
| `events` | object | no | Event-delivery preferences. Defaults applied if omitted. |

### `site` — site-level integration config

| Field | Required | Notes |
|---|---|---|
| `integration_type` | yes | Discriminator. v1 supports `"rtsp"` only. Future: `"avigilon"`, `"milestone"`, `"genetec"`, etc. |
| `locale` | no | Affects formatting of dates, numbers, units in alerts. Default `"us"`. |
| `timezone` | no | IANA timezone (e.g., `"US/Eastern"`). Affects schedule evaluation and event timestamps. Default `"UTC"`. |
| `<integration>` | conditional | Per-integration auth/config block. For [[rtsp-deep-dive|RTSP]], omitted (camera credentials live per-camera). For VMS integrations, holds VMS server creds. |

### Camera entries

Each camera carries its own credentials and product config. The credential block name (`rtsp`, `avigilon`, etc.) matches `site.integration_type`.

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Caller-stable id; surfaces in alerts, status, and detection events. |
| `name` | yes | Human label. |
| `rtsp` | yes (when `integration_type=rtsp`) | `{url, username, password, transport}`. Password is treated as a secret end-to-end (see Secrets handling). |
| `schedule` | no | `{mode: "always"}` (default) or `{mode: "windows", windows: [{days, start, end}]}`. |
| `crop` | no | Bounding-box for ROI. Pass-through to settings.json. |
| `products` | yes | One or more detection-product configs. |

### Detection products

A product is a detection use-case configuration (intruder, weapon, loitering, line-crossing, etc.). Each product names its driving model(s), picks a sensitivity preset, and references which alert configs fire.

| Field | Required | Notes |
|---|---|---|
| `product` | yes | Product identifier — `"intruder"`, `"weapon"`, `"loitering"`, `"line-crossing"`, etc. Registry maintained by run-service + connector image. |
| `sensitivity` | yes | Us-defined preset: `"low"`, `"medium"`, `"high"`. Maps to internal numeric thresholds in the translator. |
| `models` | no | Models driving this product. Defaults to product's canonical model set if omitted. |
| `zones` | no | Tag zones — polygon list with names. Used by zone-based products. |
| `line_crossings` | no | Line-crossing detector config (used by line-crossing product). |
| `alert_triggers` | no | List of alert config ids to fire when this product detects. Empty means no alerts (events still delivered to caller). |

**Sensitivity is a us-defined preset, not free numeric tuning.** Today's `"medium"` maps to specific values for `first_layer_confidence`, `iou_thresh`, `denominator`, etc.; if we tune those values, all callers benefit. Callers don't see or set the underlying numbers. Preset → numeric mapping lives in [[translation-layer]].

### Alert configs

An alert config bundles channels with a list of trigger types it fires on.

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Caller-defined string. Referenced from `cameras[].products[].alert_triggers[]`. Unique within the run. |
| `channels` | yes | One or more channel objects (see below). Inline shape; alternatively use `ref: "ac_..."` to reference a pre-registered config. |
| `triggers` | yes | List of trigger types. Channels in this config fire when **any** trigger fires for any camera in this run. |

**Trigger types:**

- `product_alert` — a configured product detected something.
- `healthcheck` — site-level healthcheck failure (deployment alarm gate, etc.).
- `scene_change` — scene-change detector fired.
- `stream_quality` — image-quality or stream-quality check failed.
- `motion_status` — motion subsystem status changed.
- `connectivity` — camera lost connectivity.

**Channel types:**

| Type | Fields | Notes |
|---|---|---|
| `email` | `address` | SMTP via the alert-sender. |
| `sms` | `number` (E.164) | Twilio via alert-sender. |
| `webhook` | `url`, `secret_id` (optional) | HMAC-signed POST per alert. |
| `sns` | `topic_arn` | SNS publish; cross-account requires the topic to allow our principal. |
| `integration` | `kind`, `config` | Pre-built integration: `crisis_go`, `envera`, `genetec`, `immix`, `stages`, `label_watch`, etc. `config` is integration-specific. |

### Alert-config pre-registration

Inline configs (above) live inside the RunSpec. The same shape can be pre-registered via `POST /v1/alert-configs` and referenced inside RunSpec by short id:

```json
"alerts": [
  { "id": "main-ops", "ref": "ac_a3k7qz", "triggers": ["product_alert"] }
]
```

The `channels[]` list is replaced with a `ref` field; `triggers[]` is still per-run (so the same pre-registered channels can fire on different trigger sets in different runs). Pre-registered configs are tenant-scoped and survive across runs; default expiry: 90d sliding.

### `events` — event-delivery preferences

| Field | Default | Notes |
|---|---|---|
| `delivery` | `[]` | Subset of `["sse", "webhook"]`. Polling summary via `GET /v1/runs/{id}` is always available regardless. |
| `include_frames` | `true` | If false, `frame_ref` omitted from `DetectionEvent.v1`. |
| `frame_url_ttl_seconds` | `3600` | Presigned URL expiry. Tunable per tenant up to 24h. |
| `include_tracker_ids` | `true` | If false, `tracker_id` omitted from `DetectionEvent.v1`. |
| `replay_enabled` | per-tenant default | When true, events stored for the run's retention window; queryable post-run. Costs storage. |

### Secrets handling

Camera passwords, webhook signing keys, integration creds — all sensitive. Two options:

- **Inline** — included in the POST body. TLS-only; Lambda materializes a Kubernetes `Secret` in the run-service namespace, references from the pod spec, deletes with the run (`ownerReferences`). Lambda log redacts cleartext.
- **Pre-registered** — `POST /v1/secrets` with `{kind, value, name}` returns a short id (`sec_x9k2`). Reference inside RunSpec by id (`secret_id` field).

v1 supports both. Pre-registration is recommended for any credential reused across runs.

## `POST /v1/runs` — response

`202 Accepted`:

```json
{
  "run_id": "run_xy7k2m",
  "state": "scheduled",
  "tenant_id": "acme-corp",
  "mode": "ephemeral",
  "status_url": "/v1/runs/run_xy7k2m",
  "events_url": "/v1/runs/run_xy7k2m/events",
  "expires_at": "2026-05-02T14:30:00Z",
  "spec_version": "v1",
  "warnings": []
}
```

For `mode: persistent`, `expires_at` is `null`. `warnings[]` carries non-fatal observations the translator made (e.g., "model `weapon-old` is deprecated, mapped to `weapon-mid`").

## `GET /v1/runs/{run_id}` — response

```json
{
  "run_id": "run_xy7k2m",
  "tenant_id": "acme-corp",
  "name": "smith-warehouse-trial",
  "mode": "ephemeral",
  "state": "running",
  "states_history": [
    {"state": "scheduled",  "at": "...", "detail": "queued"},
    {"state": "starting",   "at": "...", "detail": "pod-pulling"},
    {"state": "running",    "at": "...", "detail": "first-frame-received"}
  ],
  "started_at": "...",
  "expires_at": "...",
  "cameras": [
    {
      "id": "cam-1",
      "stream_state": "streaming",
      "frames_processed": 12345,
      "events_detected": 3,
      "last_frame_at": "..."
    }
  ],
  "events_summary": {
    "total": 5,
    "by_product": { "intruder": 4, "loitering": 1 },
    "by_camera": { "cam-1": 3, "cam-2": 2 },
    "first_at": "...",
    "last_at": "..."
  },
  "latest_events": [
    /* up to N most recent DetectionEvent.v1 records */
  ],
  "errors": []
}
```

State machines:

```
ephemeral:  scheduled → starting → running → terminating → {completed, failed, cancelled, expired}
persistent: scheduled → starting → running → terminating → {failed, cancelled}
```

- `completed` (ephemeral only) — TTL hit and all cameras drained cleanly.
- `expired` (ephemeral only) — TTL hit; drain may have been incomplete.
- `cancelled` — explicit `DELETE`.
- `failed` — pipeline crashed beyond recovery, all retries exhausted.

## `DELETE /v1/runs/{run_id}`

`202 Accepted`. Pod gets SIGTERM via paradigm-specific drain; the connector's preStop has up to `terminationGracePeriodSeconds` to flush in-flight detections to the alert-sender and the event bus. Caller polls `GET` to observe `terminating → cancelled`.

## `GET /v1/runs/{run_id}/events` — SSE stream

Server-sent events stream of `DetectionEvent.v1`. Live during the run; for replay-enabled runs, also serves historical events post-completion.

```http
GET /v1/runs/run_xy7k2m/events
Accept: text/event-stream
Last-Event-ID: evt_a3k7qz       ← optional, for resume

→ HTTP/1.1 200 OK
  Content-Type: text/event-stream

  id: evt_a3k7qz
  event: detection
  data: { ...DetectionEvent.v1 JSON... }

  id: evt_a3k7r2
  event: detection
  data: { ...DetectionEvent.v1 JSON... }

  ...
```

Query params:

| Param | Notes |
|---|---|
| `since=<event_id>` | Start from after this id (alternative to `Last-Event-ID`). |
| `since_at=<RFC3339>` | Start from this time. |
| `cameras=cam-1,cam-2` | Filter to specific camera ids. |
| `products=intruder,weapon` | Filter to specific products. |

For replay-disabled runs, querying past completion returns `410 Gone` with code `replay_disabled`.

## `DetectionEvent.v1` — event schema

```json
{
  "event_id": "evt_a3k7qz",
  "schema_version": "v1",
  "run_id": "run_xy7k2m",
  "tenant_id": "acme-corp",
  "occurred_at": "2026-05-01T15:42:18.234Z",
  "camera": { "id": "cam-1", "name": "Loading Bay" },
  "product": "intruder",
  "model": "weapon-mid",
  "confidence": 0.87,
  "bbox": [0.21, 0.34, 0.18, 0.47],
  "classes_detected": ["person", "weapon"],
  "tracker_id": "track_8821",
  "zone": "bay-7",
  "frame_ref": {
    "url": "https://signed-url-to-jpeg",
    "expires_at": "2026-05-01T16:42:18Z"
  },
  "alert_fired": true,
  "alert_triggers": ["main-ops"]
}
```

| Field | Notes |
|---|---|
| `event_id` | Unique within the run; lexicographically sortable. |
| `bbox` | Normalized `[x, y, w, h]` in image coordinates 0..1. |
| `classes_detected` | Raw class list from inference (e.g., `["person", "car"]`). |
| `tracker_id` | Stable across frames for the same tracked object. Omitted if `events.include_tracker_ids: false`. |
| `zone` | Present when product uses zone tagging and the detection landed in a tagged zone. |
| `frame_ref` | Presigned S3 URL + expiry. Omitted if `events.include_frames: false`. |
| `alert_fired` / `alert_triggers` | What the alert-sender did synchronously with this detection. |

**What's filtered out as internal:**

- `admin_camera_id`, internal `stream_id`, internal `model_id` (replaced with caller-friendly names from RunSpec).
- S3 bucket names, K8s pod / container ids, NR account info, internal correlation ids.
- Internal numeric thresholds (`first_layer_confidence`, `iou_thresh`, etc.) — caller sees `sensitivity: "medium"` from the original RunSpec, not the underlying numbers.

### Per-event webhook

If `events_webhook_url` is set on the RunSpec, run-service POSTs `DetectionEvent.v1` records to that URL one-by-one (or batched up to 100 per POST when load demands).

```http
POST {events_webhook_url}
Content-Type: application/json
X-Run-Id: run_xy7k2m
X-Event-Id: evt_a3k7qz
X-Signature: sha256=<HMAC over body>
X-Timestamp: 2026-05-01T15:42:00Z

{ ...DetectionEvent.v1... }
```

For batched delivery: body is `{"events": [...]}`. `X-Event-Id` is the first event id in the batch; `X-Batch-Size` is set.

Retry policy: 3 attempts on 5xx (1s, 5s, 30s backoff). After 3 fails, drop and emit NR error event. Caller has SSE / polling as fallback.

## Lifecycle webhook (`callback_url`)

Optional. Fires on every state transition (`scheduled → starting`, `starting → running`, etc.) and once at terminal state. **Distinct from the per-event webhook above** — this one is for run lifecycle, not detections.

```http
POST {callback_url}
Content-Type: application/json
X-Run-Id: run_xy7k2m
X-Signature: sha256=<HMAC over body>
X-Timestamp: 2026-05-01T15:42:00Z

{
  "run_id": "run_xy7k2m",
  "tenant_id": "acme-corp",
  "state": "running",
  "previous_state": "starting",
  "at": "2026-05-01T15:42:00Z",
  "summary": { "events_detected": 0, "cameras_streaming": 1 }
}
```

HMAC signing key is per-tenant, rotatable via `PUT /v1/tenants/{id}/webhook-secret` (admin-only). Receivers verify signature + reject stale timestamps (>5min skew).

Retry policy: 3 attempts on 5xx (1s, 5s, 30s). After 3 fails, log + emit NR error event. Caller can poll `GET /runs/{id}` as fallback.

## Real-time alerts vs detection events — distinct paths

Two output streams flow out of run-service. Different audiences, different SLAs:

| Output | Audience | Path | SLA |
|---|---|---|---|
| **Alerts** | Recipients (humans, partner systems via integration alarms, SNS subscribers) | Connector pipeline → existing alert-sender → recipient directly. **Does not flow through API Gateway.** | Sub-10s to recipient. |
| **Detection events** | The caller of `POST /v1/runs`, programmatically | Connector pipeline → run-service event bus → caller (SSE / webhook / GET) | Sub-second to API consumer; webhook delivery best-effort with retries. |

The two paths never merge. A detection can fire both — alert recipients get the human-readable alert via the alert-sender; the caller of the API gets the structured `DetectionEvent.v1` via the event bus.

This split is deliberate:

1. Alerts must hit recipients in seconds; routing them through API Gateway + Lambda dispatch adds unacceptable latency.
2. The alert-sender is already wired up, tested, and observed in production.
3. The API surface stays scoped to "manage runs and observe detections," not "be the connector's bus."

## Idempotency

`idempotency_key` is tenant-scoped and stored with TTL = 24h.

| Scenario | Behavior |
|---|---|
| Same key, identical body | Return original `run_id` + current `state`. |
| Same key, different body | `409 Conflict` with `idempotency_mismatch`. |
| Same key, > 24h since first POST | Treated as new request; new `run_id`. |

## Versioning

URL path. `/v1/...` is stable; breaking changes mean `/v2/...` side-by-side. Within v1, only **additive** changes — new optional fields, new enum values surfaced via `warnings[]`. Pydantic model is the source of truth; OpenAPI spec generated from it (recommended).

## Rate limits + concurrency

| Limit | Default | Notes |
|---|---|---|
| `POST /v1/runs` per tenant | 60/hour, 10/min burst | Returns `429`. |
| Concurrent active runs per tenant | 5 | Returns `503` with `capacity_exceeded`. Tunable per tenant. |
| Cameras per run | 48 | Returns `422`. Tunable per tenant. |
| Total camera-hours per ephemeral run | 48 × 24 = 1152 | Implied by the two ceilings. |
| Persistent runs per tenant | 50 | Higher cap because they don't churn; tunable. |

## Cost ceiling

For ephemeral runs, server estimates cost as `camera_count × duration_seconds × $/camera-hour`. If estimate exceeds `tenant.max_run_cost_usd` (default $50), refuse with `422` + `cost_ceiling_exceeded`. Coefficient TBD — needs a baseline from connector image's per-camera resource curve.

For persistent runs, no per-run ceiling (runs are open-ended). Per-tenant monthly spend ceiling enforced at billing layer (out of v1 scope).

This is intentionally a **server-side refusal**, not a billing gate. v1 doesn't bill; the ceiling exists to prevent runaway accidents.

## Error taxonomy

| HTTP | Code | Meaning |
|---|---|---|
| `400` | `invalid_request` | Malformed JSON or missing required field. |
| `401` | `unauthenticated` | Missing or invalid auth material. |
| `403` | `forbidden` | Authenticated but tenant doesn't allow this op. |
| `404` | `not_found` | Run id / alert config / secret id not recognized. |
| `409` | `idempotency_mismatch` | Same key, different body within 24h window. |
| `410` | `replay_disabled` | Querying events on a non-replay-enabled completed run. |
| `422` | `spec_validation_failed` | Body parses but fails `RunSpec.v1` validation. Field-level details in body. |
| `422` | `connector_validation_failed` | Translator output rejected by `connector validate`. **Drift signal — page on this.** |
| `422` | `cost_ceiling_exceeded` | Estimated cost > tenant max. |
| `422` | `unsupported_integration` | v1 scope: only `rtsp`. Avigilon / Milestone return this. |
| `422` | `unknown_product` | Product id not in registry. |
| `422` | `unknown_model` | Model id not in registry. |
| `422` | `unknown_alert_config` | Referenced alert config id doesn't exist. |
| `422` | `mode_validation_failed` | E.g., `duration_seconds` set on `mode: persistent`, or omitted on `mode: ephemeral`. |
| `429` | `rate_limited` | Per-tenant POST rate exceeded. |
| `503` | `capacity_exceeded` | Per-tenant concurrent-run cap exceeded. |
| `500` | `internal_error` | Generic. Logged with correlation id; body returns the id only. |

Error bodies follow [RFC 7807](https://datatracker.ietf.org/doc/html/rfc7807) (`application/problem+json`):

```json
{
  "type": "https://api.actuate.ai/errors/spec_validation_failed",
  "title": "Spec validation failed",
  "status": 422,
  "detail": "duration_seconds must be ≤ 86400",
  "instance": "/v1/runs",
  "errors": [
    {"path": "duration_seconds", "code": "max_value", "max": 86400, "got": 172800}
  ]
}
```

Internal state never leaks: connector container ids, k8s namespaces, NR account info, etc., are not in error bodies.

## Run history retention

DynamoDB `run_service_runs` table: TTL on `expires_at + 90 days` (or `terminated_at + 90 days` for persistent runs).

- 90 days lets sales call back a customer 6+ weeks later and still pull "here's what we caught during your trial."
- Beyond 90 days the value drops sharply; storage costs creep.
- Tenants with longer audit needs can override (`tenant.run_retention_days`).

The `run_service_runs` table holds the spec, state history, and per-camera summary. **Detection event details** live in the separate `run_service_events` table for replay-enabled tenants only.

## DynamoDB schema sketch

| Table | PK | SK | Attributes | TTL |
|---|---|---|---|---|
| `run_service_runs` | `tenant_id` | `run_id` | spec_v1 (compressed), mode, state, state_history, started_at, expires_at, summary | `(expires_at OR terminated_at) + retention_days` |
| `run_service_run_idempotency` | `tenant_id` | `idempotency_key` | run_id, body_hash, created_at | 24h |
| `run_service_alert_configs` | `tenant_id` | `alert_config_id` | channels (encrypted), created_at, last_used_at | 90d sliding |
| `run_service_secrets` | `tenant_id` | `secret_id` | kind, value (encrypted), created_at | 90d sliding |
| `run_service_events` (replay-enabled tenants only) | `run_id` | `event_id` | DetectionEvent.v1 (compressed) | `event.occurred_at + retention_days` |
| `run_service_tenants` | `tenant_id` | `_` | concurrent_cap, rate_limits, max_run_cost_usd, allowed_integrations[], retention_days, replay_enabled, frame_url_max_ttl | none |
| `run_service_api_keys` | `key_hash` | `_` | tenant_ids[], scopes[], created_at, expires_at | configurable |

For high-volume `run_service_events` at scale, the table may need a different store (S3 + Athena via Firehose, or Aurora). DynamoDB is sketched for v1; revisit once write throughput is characterized.

## Observability

- Every API call writes a structured log line with `correlation_id`, `tenant_id`, `run_id`, `endpoint`, `latency_ms`, `result_code`.
- NR custom events: `RunServiceCreated`, `RunServiceStateChange`, `RunServiceTerminated`, `RunServiceFailed`, `RunServiceEventDelivered`, `RunServiceWebhookFailed`. Faceted by `tenant_id`, `mode`, `paradigm` (c/d/e), `camera_count`, `duration_seconds`.
- Per-paradigm dashboards: cold-start latency p50/p95, per-run cost, alert-firing latency, event-delivery latency, tear-down cleanliness (lingering resources count). Feeds `comparison-matrix.md`.
- Drift-detection alert: page on any `connector_validation_failed` 422 — that means the canary missed a real drift event, or the canary itself is broken.
- SLOs (initial targets): `POST /v1/runs` p95 < 2s; first-frame-received p95 < 60s; SSE event delivery p95 < 1s after detection.

## Open questions

1. **Cognito vs API-key — both, or pick one for v1?** Default plan: both. Push back if you'd rather defer Cognito.
2. **Cost-coefficient calibration** — what's the right `$/camera-hour` number? Needs a benchmark; can ship with a high default ($1/cam-hour) and tighten.
3. **Alert-config short id format** — proposing `ac_<6-char base32>` (~33M ids per tenant before collision). Alternative: human-readable slug. Default to base32 for uniqueness.
4. **Per-tenant overrides location** — DynamoDB `run_service_tenants` works. If admin-api ever holds a `tenant` record and we want alignment, revisit.
5. **API-Gateway product (REST vs HTTP API)** — HTTP API is cheaper and faster but has fewer features (no request/response transforms, weaker authorizer ergonomics). REST is the safer pick; revisit if cost matters at scale.
6. **Webhook batching threshold** — when does run-service switch from per-event POST to batched? Fixed batch size (100) or rate-aware?
7. **Sensitivity preset versioning** — when we tune `medium`'s underlying numbers, do we pin existing runs to old values, or migrate them live? Pinning is cleaner; migration may be necessary if a tuning fixes a bug.
8. **Persistent-mode webhook fanout cost** — a long-running site might fire millions of detection events; webhook delivery adds Lambda + egress cost. Should persistent mode require pull (SSE / GET) by default and webhook be opt-in?
9. **Events store at scale** — DynamoDB writes get expensive at high event volume; when do we move to S3-Parquet + Athena for query? Threshold-driven migration?
10. **Per-product alert filters** — currently a config's `triggers[]` applies to all products in the run. Should we allow per-product filtering inside a config (e.g., "main-ops gets intruder + weapon, not loitering")? Defer unless requested.
11. **OpenAPI generation** — generate from Pydantic (recommended) or hand-author? Generation guarantees alignment but adds a build step.
12. **Multi-region** — single-region for v1 (us-east-1 likely)? When does multi-region become required?

## Cross-references

- [[_overview]] — project framing, modes, schema-drift design, evaluation rubric
- [[translation-layer]] — how `RunSpec.v1` becomes a settings.json, sensitivity preset → numeric mapping, canary
- [[paradigm-c]] / [[paradigm-d]] / [[paradigm-e]] — execution layer (per fleet paradigm)
- [[admin-api/_summary]] — parallel system, not a runtime dependency
- [[settings-automation/_summary]] — adjacent settings.json work; translation-layer borrows patterns
- [[tracker-snapshot-schema]] — `tracker_id` stability guarantee that this contract depends on
