---
title: "v5 tracking fields → E2M design"
type: synthesis
topic: billing
tags: [billing, inference-api, v5, e2m, new-relic, request-correlation, design]
created: 2026-05-14
updated: 2026-05-14
author: kb-bot
incoming:
  - topics/billing/_summary.md
  - topics/billing/notes/concepts/2026-05-14_inference-api-e2m-rules.md
  - topics/inference-api/notes/concepts/2026-05-14_handoff-v5-release-verification.md
  - topics/inference-api/notes/concepts/2026-05-19_handoff-v5-post-release-watch.md
  - topics/inference-api/notes/syntheses/2026-05-14_v5-motion-history-single-frame-design.md
  - topics/personal-notes/notes/daily/2026-05-14.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-27
---

# v5 tracking fields → E2M design

PR [#71](https://github.com/aegissystems/actuate-inference-api/pull/71) adds two new optional fields to `POST /v5/detect` whose **only purpose** is enriching [[new-relic|New Relic]] log records so E2M can pivot on richer dimensions. No inference behavior changes; no SQS event flow changes; no Snowflake schema changes.

This synthesis explains what the new fields buy us, what's already in place, and what's left.

## What landed in PR #71

```python
class V5DetectRequest(BaseModel):
    ...
    request_id: Optional[str]    # max 36 chars (UUID-canonical), min 1
    actuate_camera_id: Optional[int]  # ge=1
```

Existing fields unchanged: `camera_id: Optional[str]` (max 256) and `site_id: Optional[str]` (max 256).

At the top of the detect handler:

```python
request_id = body.request_id or str(uuid.uuid4())
logger.append_keys(
    request_id=request_id,
    camera_id=body.camera_id,
    site_id=body.site_id,
    actuate_camera_id=body.actuate_camera_id,
)
```

All four IDs ride along on every log line emitted during that request — Powertools attaches them as structured fields, NR ingests them, E2M can FACET on them.

The resolved `request_id` is **always** present in the response (server-generated UUIDv4 when the caller didn't send one). The other three are echoed only when supplied.

## Where these hook into existing telemetry

The three E2M rules described in [[2026-05-14_inference-api-e2m-rules]] continue to count v5 traffic untouched:

| Metric | v5 behavior |
|---|---|
| `inferenceApi.billing.requests` | One per v5/detect call (FACET on `fastapi.path = '/v5/detect'`) |
| `inferenceApi.billing.frames` | Sum of frames-per-request, including v5 |
| `inferenceApi.inference.slices` | Sum of slices when the v5 sliced path is taken |

What they **don't** do is pivot on the new dimensions. A query like _"how many v5 inference calls did camera X make this week"_ today returns one row keyed by `requester_name` (the API-key holder), not per-camera. After PR #71 the dimensional data is available in `FROM Log`, but `FROM Metric` won't carry it until new E2M rules are created.

## Gap analysis — proposed follow-up rules

Three candidate rules would unlock the per-camera and per-request views. Each is additive to the existing three.

### 1. `inferenceApi.billing.requests by camera`

```sql
FROM Log SELECT summary(1) AS 'inferenceApi.billing.requests'
WHERE function_name = 'InferenceAPI-prod'
  AND message LIKE 'Received % frames for inference - starting inference'
  AND `fastapi.x-api-key` IS NOT NULL
FACET `fastapi.path`, `requester_name`, `camera_id`, `actuate_camera_id`
```

**Cardinality [[watch-entity|watch]]:** `camera_id` is partner-supplied free-text (max 256 chars) — capping at 36 was deliberately *not* done in PR #71 per design discussion. The `actuate_camera_id` int is the bounded, blast-radius-controlled dimension; prefer it for billing-grade rollups once partners are sending it consistently.

### 2. `inferenceApi.requests.correlation`

Per-request unique-count view, useful for trace replay and dedup. Doesn't FACET on request_id directly (would create one metric series per UUID — cardinality explosion); instead uses request_id only as the join key for log-to-metric reconciliation.

### 3. `inferenceApi.errors by camera`

Couples to the existing error log lines (e.g., 422 schema rejection, 400 frame decode failure) and faceting on `camera_id` / `actuate_camera_id` to surface which cameras / customer integrations are pushing malformed traffic.

## Why we did this even though E2M rules aren't written yet

The rules can be created in NR UI (or via NerdGraph mutation alongside the existing graphql file) any time post-merge. **Wiring the fields through the handler is the constraint** — once log records carry the structured fields in prod, the rules become a 10-minute NR UI exercise. Doing the wiring with the v5 release means the moment partners start sending real traffic post-cutover, the dimensional data is captured even if dashboards lag.

The reverse order (rules first, fields later) would just give us empty metric series.

## Cardinality + cost caveats

E2M metric series are billed by cardinality. The current rules have low cardinality (~handful of `requester_name` × handful of paths = <100 series). Adding `camera_id` could explode this:

- A partner with 10,000 cameras × 4 paths × 1 requester_name = 40,000 series per metric per rule
- At three rules × that, ~120k series — close to NR's per-account caps

Mitigations:

1. **Prefer `actuate_camera_id` over `camera_id`** for billing-grade rules — bounded by admin DB row count, naturally capped.
2. **Drop `requester_name`** from per-camera rules — redundant once `actuate_camera_id` exists (admin DB joins camera→customer).
3. **Filter aggressively** — `WHERE actuate_camera_id IS NOT NULL` to exclude requests that didn't ship the field, until partners are reliably populating it.

## Cross-reference

- [[2026-05-14_inference-api-e2m-rules]] — the three existing rules + how dimensions are attached
- [[billing/_summary]] — broader billing surface (SQS path is the other half)
- [[new-relic/_summary]] — NR account context
- [[2026-05-13_v5-prod-release]] — PR #60 release record (PR #71 lands in same release chain)
- [[inference-api/_summary]] — service-level context
- PR [#71](https://github.com/aegissystems/actuate-inference-api/pull/71) — the code change

## Action items (post-PR-#71-merge)

- [ ] Verify which NR account actually owns the three existing E2M rules — graphql file targets `7081731`, primary KB-documented account is `3421145`
- [ ] Decide cardinality strategy for the new rules (separate per-camera rules vs. extended FACET on existing) — design call
- [ ] Add the new rules to `EventsToMetricRules.graphql` if going that route, or document creation in NR UI
- [ ] Backfill `actuate_camera_id` plumbing on the partner integration side (today no caller sends it)
- [ ] Decide whether `request_id` ever ends up as a metric series — likely no (cardinality), but as a log-side correlation key it's already valuable
