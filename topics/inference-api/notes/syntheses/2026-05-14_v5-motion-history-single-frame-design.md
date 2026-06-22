---
title: "v5 detect_motion — single-frame stationary indicator"
type: synthesis
topic: inference-api
tags: [v5, inference-api, detect-motion, stationary, s3, design, e2m]
status: shipped to dev-api, ready for prod (PR #60 cutover Monday)
created: 2026-05-14
updated: 2026-05-15
author: kb-bot
incoming:
  - topics/actuate-platform/notes/concepts/2026-05-18_handoff-deploy-branch-phase1-resume.md
  - topics/inference-api/notes/concepts/2026-05-14_handoff-v5-release-verification.md
  - topics/inference-api/notes/concepts/2026-05-19_handoff-v5-post-release-watch.md
  - topics/personal-notes/notes/daily/2026-05-14.md
  - topics/personal-notes/notes/daily/2026-05-15.md
incoming_updated: 2026-05-27
---

# v5 `detect_motion` — single-frame stationary indicator (design)

**Status: shipped to dev-api on 2026-05-14, verified live (9/9 E2E), rolls into PR #60 prod cutover Monday.** All open questions resolved per [§Open questions](#open-questions). Required four PRs in total to land cleanly (one feature + three infra hotfixes); the recovery trail is documented below.

## PR chain

| PR | Subject | Outcome |
|---|---|---|
| [#72](https://github.com/aegissystems/actuate-inference-api/pull/72) | Initial feature land — Terraform + cache module + endpoint wiring + tests | Merged. First deploy-dev attempt failed on S3 bucket name collision (globally unique across the 3 deploy targets) + missing `iam:PutRolePolicy` on the CI role. |
| [#73](https://github.com/aegissystems/actuate-inference-api/pull/73) | Unique-per-region bucket name + IAMRoleManagement extension | Merged. Required two reruns due to IAM eventual-consistency on the policy update + orphan-bucket cleanup via `aws s3 rb`. |
| [#74](https://github.com/aegissystems/actuate-inference-api/pull/74) | `s3:ListBucket` grant so cache misses return `NoSuchKey` instead of `AccessDenied` | Merged. Discovered via E2E verification on dev-api — Lambda had GetObject + PutObject but without ListBucket S3 hides key existence from unauthorized listers and returns 403 for missing keys, which `frame_cache.py` correctly classifies as `s3_error` rather than the actual `no_previous_frame` cache miss. |

After PR #74, the live E2E verification on dev-api passed **9/9** (every outcome code + the 422 constraint + sanitization).

## Implementation map (final)

| Layer | File | Notes |
|---|---|---|
| Terraform — bucket + lifecycle + IAM | `terraform/s3-frame-cache.tf` | Bucket name `actuate-inference-api-frame-cache-${stage}-${account}-${region}` (61 chars max, S3 cap 63). One bucket per Lambda instance, co-located. Inline policy on the Lambda role grants `s3:GetObject` + `s3:PutObject` on `arn/*` AND `s3:ListBucket` on `arn` (latter is needed so cache-miss returns `NoSuchKey`/404 instead of `AccessDenied`/403). |
| Terraform — Lambda env | `terraform/lambda.tf` | `FRAME_CACHE_BUCKET` plumbed. |
| Terraform — CI role grants | `terraform/cicd.tf` | `S3BucketManagement` Sid extended for the new resource pattern + `s3:PutLifecycleConfiguration`. `IAMRoleManagement` Sid extended for `iam:PutRolePolicy` + `iam:DeleteRolePolicy`. |
| Request/response models | `inference_api/inference_api/models/v5.py` | `detect_motion: bool` field; `DetectMotionResult` model nested under `detect_motion_result` on `V5DetectResponse`. |
| Cache module | `inference_api/inference_api/api/dependencies/frame_cache.py` | `compute_cache_key` (compound on `actuate_camera_id` + `camera_id` partitioned by `requester_name`), `_sanitize_camera_id_for_path`, async S3 GET/PUT wrappers around sync `boto3` ops via `asyncio.to_thread`. 20-min TTL enforced at read time via `LastModified`. |
| Endpoint wiring | `inference_api/inference_api/api/endpoints/v5.py` | `_run_detect_motion` helper called AFTER inference; inference unconditional. 422 on multi-frame. `_get_requester_name` mirrors the middleware lookup. |
| Cache unit tests | `inference_api/inference_api/test/test_frame_cache.py` | 21 cases — every `compute_cache_key` combination, S3 freshness + error mapping, async wrappers. |
| Endpoint integration tests | `inference_api/inference_api/test/test_v5.py::TestV5DetectMotion` | 9 cases — multi-frame 422, every outcome code, cache hit/miss, sanitization rejection, inference invariance. |
| Docs | `docs/api/v5/detect.md` | New param + nested response shape with all 5 error codes documented. |
| E2M rule | `EventsToMetricRules.graphql` | `inferenceApi.detect_motion.requests` faceted by `fastapi.path`, `requester_name`, `detect_motion_outcome`. |
| Dashboard signal in `signals.json` | pending — per §9 mark-todos discipline rule | Track post-cutover. |

## Live E2E results (dev-api)

Verified via `/tmp/v5_detect_motion_verify.py` after PR #74 deploy. 9/9 PASS:

| # | Test | Result |
|---|---|---|
| 1 | `detect_motion=false` → no `detect_motion_result` field | PASS |
| 2 | No camera identifier → `error: no_camera_identifier`, inference still returned | PASS |
| 3 | First call (cold cache) → `error: no_previous_frame` | PASS |
| 4 | Same frame twice → `stationary: true` | PASS |
| 5 | Different frame (same dimensions) → `stationary: false` | PASS |
| 6 | `actuate_camera_id`-only partition starts cold | PASS |
| 7 | Multi-frame + `detect_motion=true` → 422 | PASS |
| 8 | `camera_id='../escape'` → `error: invalid_camera_id` | PASS |

### Re-verified 2026-05-15 (Friday morning, PR #60 still parked for Monday cutover)

Both regression suites re-run live against `dev-api.actuateui.net`:

- `/tmp/v5_detect_motion_verify.py` → 9/9 PASS
- `/tmp/v5_int07_model_verify.py` → 6/6 PASS (int07-actuate003-v8 direct + sliced + weapon/pet/motion-plus regression + `GET /v5/models`)

#### Wire-level proof of the cache flow

Cold-cache then warm-cache pair, same request body, same camera. Camera identifiers: `camera_id="demo-1778856098"`, `actuate_camera_id=9098`. Tracking fields supplied client-side; server generated `request_id` per request.

**Request 1 response (cold cache):**

```json
{
  "model_id": "intruder",
  "detections": {
    "0": [
      {"label": "person", "confidence": 0.75, "center_x": 708.52, "center_y": 389.91, "width": 29.69, "height": 33.79},
      {"label": "person", "confidence": 0.70, "center_x": 963.43, "center_y": 414.59, "width": 46.27, "height": 49.66}
    ]
  },
  "camera_id": "demo-1778856098",
  "request_id": "646d868a-2c4f-4e5e-9e05-4b908bae3ebb",
  "actuate_camera_id": 9098,
  "detect_motion_result": { "error": "no_previous_frame" }
}
```

**Request 2 response (~milliseconds later, same body):**

```json
{
  "model_id": "intruder",
  "detections": { "0": [ ...same 2 person detections... ] },
  "camera_id": "demo-1778856098",
  "request_id": "72e1b759-b6a5-4b89-9167-ba72523f82f8",
  "actuate_camera_id": 9098,
  "detect_motion_result": { "stationary": true }
}
```

The detection payload is byte-identical between calls; the only delta is `detect_motion_result` flipping from `{error: "no_previous_frame"}` to `{stationary: true}`. That's the cache PUT (after call 1) → cache GET + motion-mask compute (during call 2) → no motion → `stationary: true`.

#### S3 cache state

10 objects pre-existing from Thursday's verification runs (5 `cverify-` for camera_id-only + 5 `a99x` for actuate_camera_id-only test paths). The cold-cache request above wrote object 11.

```
$ aws s3api head-object --bucket actuate-inference-api-frame-cache-dev-388576304176-us-west-2 \
    --key inference-api/v5/last-frame/verisure-dev/a9098_cdemo-1778856098.jpg
{
    "LastModified": "2026-05-15T14:41:42+00:00",
    "ContentLength": 245771,
    "ETag": "\"858ecd970cc28ecfeebb26658dacf9c2\"",
    "ContentType": "image/jpeg",
    "ServerSideEncryption": "AES256",
    "Expiration": "expiry-date=\"Sun, 17 May 2026 00:00:00 GMT\", rule-id=\"delete-stale-frames\""
}
```

- **Compound-key path** confirmed: `a{actuate_camera_id}_c{camera_id}.jpg` (both identifiers supplied).
- **ETag matches `test_gun.jpg` byte-for-byte** — md5 `858ecd970cc28ecfeebb26658dacf9c2` on both the local fixture and the S3 object. Lambda stored the exact decoded frame, no transformation.
- **Lifecycle rule attached** (`delete-stale-frames`, expires 2026-05-17). The 1-day housekeeping rule sits on top of the runtime 20-min read-time freshness check.
- **SSE-AES256 at rest.**
- **Content-Type `image/jpeg`.**

#### What this exercise proves end-to-end

| Concern | Evidence |
|---|---|
| New `int07-actuate003-v8` direct endpoint reachable + returning detections | 6/6 model verify; `intruder` direct = 617ms latency, 2 person detections returned |
| New `int07-actuate003-v8` sliced endpoint reachable + slicing | 6/6 model verify; `intruder` sliced (`max_slices=4`) = 511ms, 3 detections (slicing finds more) |
| v5 detect_motion correctly handles cold cache | Request 1: `detect_motion_result.error = "no_previous_frame"` |
| v5 detect_motion correctly handles warm cache + zero motion | Request 2 (same frame): `detect_motion_result.stationary = true` |
| Compound cache key is the partition format when both IDs are supplied | S3 key `a9098_cdemo-1778856098.jpg` |
| Lambda PUTs the decoded frame bytes to S3 | ETag md5 matches `test_gun.jpg` on disk |
| S3 bucket lifecycle is wired | `Expiration: rule-id="delete-stale-frames"` on every object |
| All four tracking IDs echo correctly | Both responses contain `camera_id`, `actuate_camera_id`, `request_id` (and `site_id` would too when supplied) |
| Inference is unaffected by detect_motion flag | Identical `detections` payload between the cold-cache and warm-cache calls |

## Lessons learned for future S3-cache features

- **S3 bucket names are globally unique** — always include account + region in the name when the same logical resource is deployed across multi-region/multi-account stacks.
- **CI role needs `iam:PutRolePolicy` + `iam:DeleteRolePolicy`** to manage inline policies (`aws_iam_role_policy`) on existing roles. The standard `AttachRolePolicy` / `DetachRolePolicy` is for **managed** policies, not inline.
- **IAM eventual consistency** — when Terraform updates the deploy role's policy AND uses the new perms in the SAME apply, expect a 403 on the first attempt and a clean rerun. A rerun usually picks up a fresh session token that sees the updated perms.
- **`s3:ListBucket` is required for canonical 404 on missing keys** — without it S3 returns 403 to avoid disclosing key existence to unauthorized listers. Cache implementations need ListBucket to distinguish "miss" from "permission failure."
- **Test frames need matching dimensions** — `cv2.absdiff` fails on shape mismatch. In real partner traffic frames from the same camera are always the same size, but synthetic test frames have to honor that constraint.

## What the feature does

Opt-in flag on `/v5/detect` (single-frame requests) that:

1. **Always runs inference normally** — model output is unaffected by the flag.
2. Returns a new top-level boolean: **is the current frame stationary relative to the prior frame seen for this camera?** (i.e., is there meaningful pixel-level motion between them?)
3. Uses S3 as a short-lived cache of the previous frame, keyed by `(actuate_camera_id, camera_id)` within the caller's `requester_name`.
4. Auto-tracked in NR via `logger.append_keys` so we can observe usage volume + cache-hit rate via E2M.

The stationary boolean is **orthogonal** to the existing `data.stationary_filter` (which tags individual detections inside multi-frame payloads). They compose:

| Concern | Owned by |
|---|---|
| "Is this single frame stationary as a whole, compared to the last one I sent?" | `detect_motion` (NEW, frame-level) |
| "Mark each detection that has no motion at its bounding box" | `stationary_filter` (existing, per-detection, multi-frame only) |

## Algorithm (lifted from v4 motion-detection)

Reuses `FdmdMotionFilter.get_motion_boxes([prev, curr])` — the same primitive v4's stationary filter calls. The interpretation is simpler: compute the motion mask, then collapse to a single boolean for the frame.

```
motion_boxes = FdmdMotionFilter.get_motion_boxes([prev_bytes, curr_bytes])
# motion_boxes is a list of one MultiPolygon (motion between prev and curr).
# If the total motion-mask area is below a threshold → stationary=true.
# Threshold: configurable; start with "any non-empty motion box" → false
# (matches v4's bias of "any motion at all means not stationary").
```

Final boolean lands in the response as `detect_motion_result.stationary`.

## Architecture

```
Client                v5/detect Lambda                            S3
──────                ────────────────                            ──
                                                                  bucket: TBD per Q1
POST /v5/detect ──▶ decode_v5_frames(1 frame)
   frames=[1]
   detect_motion=true
   camera_id=X (and/or actuate_camera_id=N)
                                                                  
                    inference on current frame  ←─ always runs
                    (independent of detect_motion)
                    
                    if detect_motion:
                      cache_key = compound(act_cam_id, cam_id, requester)
                      if cache_key is None:
                        result = {error: "no_camera_identifier"}
                      else:
                        GET <bucket>/<cache_key>            ◀──▶ + LastModified
                        if 404:
                          result = {error: "no_previous_frame"}
                        elif age > 20min:
                          result = {error: "previous_frame_stale"}
                        else:
                          motion_boxes = FdmdMotionFilter.get_motion_boxes([prev, curr])
                          result = {stationary: <bool>}
                        
                        PUT <bucket>/<cache_key> ← curr     ◀──▶ overwrites
                      
                      response.detect_motion_result = result
                    
                    logger.append_keys(
                      detect_motion=true,
                      detect_motion_outcome=<stationary|no_previous|stale|no_identifier>
                    )

  response ◀────  V5DetectResponse with detect_motion_result populated
```

### Inference is unconditional

Model inference runs **regardless** of the `detect_motion` flag. The flag only adds (a) the S3 GET/PUT cycle and (b) the response field. If everything S3-related fails (network, permission, key missing), the detection result is **still returned** — only the `detect_motion_result` carries an error explanation.

This is critical: a partner who opts in must never get worse inference latency or a missing detection result because the cache layer hiccupped.

### Compound cache key

```python
def compute_cache_key(actuate_camera_id, camera_id, requester_name):
    parts = []
    if actuate_camera_id is not None:
        parts.append(f"a{actuate_camera_id}")          # e.g., "a42"
    if camera_id is not None:
        sanitized = _sanitize_for_s3_path(camera_id)
        parts.append(f"c{sanitized}")                   # e.g., "ccam-lobby-01"
    if not parts:
        return None                                     # neither supplied
    return f"inference-api/v5/last-frame/{requester_name}/{'_'.join(parts)}.jpg"
```

- **Both supplied** → key like `.../verisure-dev/a42_ccam-lobby-01.jpg`
- **Only `camera_id`** → `.../verisure-dev/ccam-lobby-01.jpg`
- **Only `actuate_camera_id`** → `.../verisure-dev/a42.jpg`
- **Neither** → returns None; handler short-circuits to `error: "no_camera_identifier"`

Partner-side caveat to document: if they're inconsistent about whether they send `actuate_camera_id` between calls for the same physical camera, the cache will fragment (calls with `(42, "cam1")` get a different cache slot than calls with `(None, "cam1")`). Consistency on the partner side is required for the cache to be useful.

### Camera-id sanitization

Partner-supplied `camera_id` is free-text (max 256 chars). For S3 path use:

- Reject anything matching `/[/\x00\\]/` or containing `..`
- Cap length at 128 chars on the cache-key axis specifically (the wire-format max remains 256)
- Allow `A-Za-z0-9._-` and a small set of safe punctuation

If sanitization rejects the value → cache_key returns None → `error: "invalid_camera_id"` (separate from `"no_camera_identifier"` so the partner knows the difference).

### TTL via read-time freshness

The lookback is only meaningful for "recently-prior" frames. **20-minute TTL** enforced at read time:

- On GET: inspect `LastModified` response header. If `(now - LastModified) > 20 min` → treat as stale, set `error: "previous_frame_stale"`, still PUT the current frame to refresh the cache. The next call within 20 min will find it fresh.
- On PUT: always overwrite.
- S3 lifecycle rule: an additional janitor rule that **deletes objects older than 1 day** to bound storage (the 20-min freshness gate is the runtime semantic; the lifecycle rule is housekeeping). Lifecycle minimum granularity is 1 day, so we can't enforce the 20-min cap via S3 alone.

### Response shape (proposed)

New optional response field, present only when `detect_motion=true` was sent:

```python
class DetectMotionResult(BaseModel):
    stationary: Optional[bool] = Field(
        default=None,
        description=(
            "True when no significant pixel motion was detected between "
            "this frame and the prior cached frame for the same camera. "
            "False when motion was detected. Null when the comparison "
            "couldn't run — see `error` for why."
        ),
    )
    error: Optional[str] = Field(
        default=None,
        description=(
            "One of: 'no_camera_identifier', 'invalid_camera_id', "
            "'no_previous_frame', 'previous_frame_stale', 's3_error'. "
            "Null when stationary was computed successfully."
        ),
    )

class V5DetectResponse(BaseModel):
    ...
    detect_motion_result: Optional[DetectMotionResult] = None
```

Exactly one of `stationary` or `error` is populated. The field itself is omitted from the response when `detect_motion=false` (or absent).

## Parameter

```python
detect_motion: bool = Field(
    default=False,
    description=(
        "Single-frame only. When true, compute a frame-level stationary "
        "indicator by comparing this frame against the prior frame seen "
        "for the same camera in the last 20 minutes. Requires camera_id "
        "and/or actuate_camera_id. Inference is unaffected — the model "
        "always runs. See response.detect_motion_result."
    ),
)
```

v4 has no equivalent param; `detect_motion` is a clean new name. (Internal `update_on_motion` flag on `FdmdMotionFilter` is unrelated — it controls the background-reference-frame update inside the algorithm, not request-level behavior.)

## Constraint enforcement

| Condition | Behavior |
|---|---|
| `detect_motion=false` (default) | No-op — no S3 ops, no `detect_motion_result` field in response |
| `detect_motion=true` + `frames.length > 1` | **422** — "detect_motion is single-frame only; use data.stationary_filter for multi-frame" |
| `detect_motion=true` + no `camera_id` and no `actuate_camera_id` | **200** with `detect_motion_result.error = "no_camera_identifier"`; inference unaffected |
| `detect_motion=true` + invalid `camera_id` (path-unsafe chars) | **200** with `error = "invalid_camera_id"`; inference unaffected |
| `detect_motion=true` + S3 GET 404 | **200** with `error = "no_previous_frame"`; PUT current frame so next call has it |
| `detect_motion=true` + S3 GET returns stale object (>20 min) | **200** with `error = "previous_frame_stale"`; PUT current frame to refresh |
| `detect_motion=true` + S3 GET fails (network / permission) | **200** with `error = "s3_error"`; do NOT PUT (couldn't read; don't compound the failure); log warn |
| `detect_motion=true` + S3 PUT fails | **200** with `error = null, stationary = <computed>`; warn-log the PUT failure; next call sees the older cache entry |

The principle is consistent: inference always returns. The `detect_motion_result` carries the truthfulness signal.

## Interaction with existing stationary_filter

Both can be active on the same request and **they don't interact**:

- `data.stationary_filter` ("true"/"tag"/"false"): operates on per-detection bbox-vs-motion-mask checks, requires multi-frame input. Tags or drops individual detections.
- `detect_motion`: operates on whole-frame pixel-motion between current and prior cached frame. Produces a top-level boolean.

A multi-frame request with both `stationary_filter="tag"` AND `detect_motion=true` would fail the 422 constraint above (`detect_motion` is single-frame-only). On single-frame requests, the in-request stationary filter is a no-op anyway (it needs ≥2 frames to compute motion).

So in practice:

- **Single-frame**: `detect_motion` works, `stationary_filter` is moot
- **Multi-frame**: `stationary_filter` works, `detect_motion` is rejected

## E2M wiring

```python
logger.append_keys(
    detect_motion=body.detect_motion,
    detect_motion_outcome=<one of: 'stationary' | 'in_motion' | 'no_previous' |
                            'previous_stale' | 'no_identifier' | 'invalid_id' |
                            's3_error'>,
)
```

Proposed new E2M rule to add alongside the existing three in `EventsToMetricRules.graphql`:

```sql
FROM Log SELECT count(*) AS 'inferenceApi.detect_motion.requests'
WHERE function_name = 'InferenceAPI-prod'
  AND message LIKE 'Received % frames for inference - starting inference'
  AND detect_motion IS true
FACET `fastapi.path`, requester_name, detect_motion_outcome
```

Gives us per-partner volume of opted-in calls plus the outcome distribution (how often the cache is cold, how often partners send no identifier, how often motion was actually detected). Cross-links to the §9 mark-todos discipline rule — this rule also gets a sibling dashboard signal in `signals.json`.

## Concurrency

Two in-flight requests for the same cache key can race on the PUT. Last-write-wins is fine here — the cache is "the most recent frame we happened to see," not an ordered log.

GET-then-PUT is also not atomic, but the only failure mode is "I read prev=t0 and wrote curr=t1; meanwhile another call also read prev=t0 and wrote curr=t1.5 — its t1.5 wins, mine is overwritten." Either way the next read sees one of the recent frames; no data corruption, just minor ordering jitter on writes. Acceptable.

## Test plan

Mocking the S3 client (don't hit real S3 in unit tests):

1. `detect_motion=False` → no S3 ops, no `detect_motion_result` field
2. `detect_motion=True` + multi-frame → 422
3. `detect_motion=True` + neither `camera_id` nor `actuate_camera_id` → 200, `error: "no_camera_identifier"`, no S3 ops
4. `detect_motion=True` + only `camera_id` → cache key uses `camera_id` only; S3 GET attempted
5. `detect_motion=True` + only `actuate_camera_id` → cache key uses `actuate_camera_id` only
6. `detect_motion=True` + both → compound key
7. `detect_motion=True` + path-unsafe `camera_id` (e.g., `"../etc"`) → 200, `error: "invalid_camera_id"`
8. `detect_motion=True` + fresh previous in S3 (LastModified < 20 min) → motion check runs, `stationary` populated
9. `detect_motion=True` + stale previous (>20 min) → 200, `error: "previous_frame_stale"`, current frame PUT
10. `detect_motion=True` + no previous in S3 (404) → 200, `error: "no_previous_frame"`, current frame PUT
11. `detect_motion=True` + S3 GET network error → 200, `error: "s3_error"`, inference still returned, no PUT attempted
12. `detect_motion=True` + S3 PUT fails → 200, `error: null, stationary: <bool>`; warn-log on PUT failure
13. **Inference invariance**: `detect_motion=True` should produce the same `detections` payload as `detect_motion=False` for the same frame + model (only the `detect_motion_result` field differs)
14. `logger.append_keys` assertions: both `detect_motion` + `detect_motion_outcome` show up on every opted-in request

Live verification post-deploy: similar pattern to the `tracking-fields` verification script — send a request with `detect_motion=true`, no prior; send again same camera_id and assert the second response has `stationary` populated.

## Open questions

### Q1 — S3 bucket (still open)

- **Option A**: new dedicated bucket `actuate-inference-api-frame-cache-{stage}` (clean isolation, dedicated lifecycle / IAM)
- **Option B**: reuse an existing inference-api bucket — repo's Terraform doesn't surface one today

Recommendation: **A**, one per stage (`-dev`, `-prod`), regional to the Lambda. New bucket also lets us scope IAM tightly to `s3:GetObject` + `s3:PutObject` on this bucket only.

### Q2 — Motion threshold

The simplest "stationary = no motion boxes at all" rule is conservative but might be noisy in practice (a single windblown leaf = "moved"). v4's per-detection logic uses a 10% area-ratio threshold *against the detection's bbox*. For frame-level motion, options:

- **Naive**: any non-empty motion mask → `stationary=false`. Simple, easy to reason about, easy to test.
- **Area-thresholded**: total motion-mask area as a fraction of frame area > T → `stationary=false`. Better signal-to-noise but introduces a tunable knob.

Recommendation: **start naive**. If partners report false-positives in production, add an optional `motion_threshold: float` param later.

### Q3 — IAM in same PR

The Lambda execution role needs `s3:GetObject` + `s3:PutObject` on the new bucket. Adding to `terraform/cicd.tf` (where the CI role lives) AND `terraform/lambda.tf` (Lambda execution role) lands in the same PR as the code change so the bucket exists, the role can write, and the code can call all together.

Recommendation: **yes, same PR**.

### Q4 — Where does this land?

- **Separate post-#60 feature PR** — clean review, doesn't expand v5 prod release scope
- **Roll into PR #60** — ships with the rest of v5 at partner cutover

Recommendation: **separate post-#60 PR**. The current v5 prod release is fully verified; piling on a new S3-touching, Terraform-touching feature now would force another round of verification. Better to merge #60, validate against partners, then ship `detect_motion` as a quick follow-up release.

### Q5 — Naming the response field

I went with `detect_motion_result` (matches the request param name + carries both `stationary` and `error` together as a nested object). Alternatives:
- `motion` (terse)
- `stationary` (just the boolean at top level, with `motion_error` as a sibling — flatter)
- `detect_motion_result` (proposed)

Recommendation: **`detect_motion_result`** — the nested object lets us add fields later without breaking the contract.

## Implementation plan (once Q1–Q5 are answered)

1. **Terraform** (`terraform/s3.tf` or new file): bucket per stage, lifecycle rule (1-day delete), IAM grant on Lambda execution role + CI deploy role.
2. **Models** (`models/v5.py`): `detect_motion: bool` on request; `DetectMotionResult` model; `detect_motion_result: Optional[DetectMotionResult]` on response.
3. **S3 client** (`api/dependencies/frame_cache.py` or similar): `get_previous_frame(cache_key) -> (bytes | None, error | None)` returning bytes + freshness verdict; `put_previous_frame(cache_key, bytes) -> bool`.
4. **Compound-key helper** (`api/dependencies/frame_cache.py`): `compute_cache_key(...)` + `_sanitize_for_s3_path(...)`.
5. **Endpoint** (`endpoints/v5.py::detect`): wire the lookup + put + response field; ensure inference path is unchanged when flag is false.
6. **Tests** (`test_v5.py` + new `test_frame_cache.py`): 14 cases per [§Test plan](#test-plan).
7. **Docs** (`docs/api/v5/detect.md`): new param + response field + behavior table.
8. **E2M** (`EventsToMetricRules.graphql`): new rule for `inferenceApi.detect_motion.requests`.
9. **Dashboard signal** (per §9 discipline rule): add to `~/.claude/skills/dashboard-check/config/signals.json`.

## Cross-reference

- [[fdmd_stationary_filter]] — algorithmic basis (`FdmdMotionFilter.get_motion_boxes` is the primitive we reuse)
- [[2026-05-14_v5-tracking-fields-e2m-design]] — sibling v5 E2M work; `detect_motion` adds another E2M rule to the same family
- [[2026-05-14_inference-api-e2m-rules]] — existing E2M baseline
- PR [#66](https://github.com/aegissystems/actuate-inference-api/pull/66) — [[actuate-movement]] FDMD library introduction
- PR [#71](https://github.com/aegissystems/actuate-inference-api/pull/71) — v5 tracking fields (`actuate_camera_id`, `camera_id`, `request_id`) that this feature depends on
- PR [#60](https://github.com/aegissystems/actuate-inference-api/pull/60) — v5 prod release; `detect_motion` ships in a follow-up
- PR [#77](https://github.com/aegissystems/actuate-inference-api/pull/77) — contract refinement: `reason`/`error` split + always-present `stationary` + `/v5/test/motion` demo page (see §Contract refinement 2026-05-15 below)

---

## Contract refinement — 2026-05-15 (PR #77)

After re-verifying the cold→warm flow with a partner-supplied parking-lot JPEG on dev-api, the user surfaced the wording issue: the cold-cache response carried `{"error": "no_previous_frame"}`, but cold-cache is **normal flow**, not an error. Surfacing it under `error` invites partners to wire alarms at the wrong threshold.

### Final wire contract

`stationary` is **always populated**. At most one of `reason` / `error` is also set, and only when the pixel comparison didn't run. Both are absent on success.

| Path | Wire shape |
|------|------------|
| Comparison ran, no motion | `{"stationary": true}` |
| Comparison ran, motion seen | `{"stationary": false}` |
| Benign — first call for camera | `{"stationary": false, "reason": "no_previous_frame"}` |
| Benign — >20 min since last frame | `{"stationary": false, "reason": "previous_frame_stale"}` |
| Real — caller mistake | `{"stationary": false, "error": "no_camera_identifier"}` |
| Real — path-unsafe characters | `{"stationary": false, "error": "invalid_camera_id"}` |
| Real — backend unreachable | `{"stationary": false, "error": "s3_error"}` |

### Why `stationary: false` on every non-success path

Consumer-friendliness over semantic purity. Two alternatives considered and rejected:
- **`stationary: null` when comparison didn't run** — forces every consumer to write null-handling boilerplate. The whole point of detect_motion is a single boolean.
- **Default `stationary: true` (assume safe)** — too dangerous; would suppress alarms on first frame for every new camera.

Defaulting to `false` makes the partner-side rule simple: "if `stationary === false`, treat as motion, fire whatever you'd normally fire." Cold cache becomes a self-clearing transient — second call returns a real verdict.

### Why split `reason` from `error`

Telemetry, primarily. The five codes had wildly different meanings:
- `no_previous_frame`, `previous_frame_stale` — frequent, expected, no action needed
- `no_camera_identifier`, `invalid_camera_id` — partner is sending bad requests; reach out
- `s3_error` — our backend is unhealthy; page

Lumping them under `error` made signal-watching impossible: the first two would dominate the volume even in a healthy system, drowning out the real-alert codes. Splitting along the benign/actionable axis means `error`-rate is now a real health signal worth alerting on.

### Demo page

`tools/v5-test-page/motion-demo.html` mounted at `/v5/test/motion` (local-dev only, parity with `/v5/test/regression`). Side-by-side layout:
- Left: setup — env switcher (Local/Dev/Prod), API key, image drop-zone, model picker, camera id fields (auto-seeded per run), wait seconds (default 32).
- Right: two response cards (Call 1 cold, Call 2 warm) each with a colored verdict badge, timing, request body (frames truncated), full response JSON. Summary row underneath.

Designed for clean screenshots of the cold→warm flow. Auto-loads `DEV_API_KEY` from `/v5/test/env` when run locally; proxies through `/v5/proxy` to dodge CORS.

### Why now

1. `detect_motion` is brand-new in PR #60 — no external consumers yet, no migration cost.
2. PR #60 (develop→main) is parked for Monday cutover — anything on develop today lands automatically.
3. The rename is a string change in client-side code if any consumer ever did start reading the field before Monday.
