---
title: "Handoff: v5 post-release watch (PR #60 + PR #87 deployed 2026-05-19)"
type: concept
topic: inference-api
tags: [handoff, v5, pr-60, pr-87, post-release, monitoring]
created: 2026-05-19
updated: 2026-05-19
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/2026-05-19.md
  - topics/personal-notes/notes/daily/2026-05-20.md
incoming_updated: 2026-05-21
---

# Handoff: v5 post-release watch (PR #60 + PR #87 deployed 2026-05-19)

## Entry point

Read this first, then [[2026-05-14_handoff-v5-release-verification]] for the pre-merge runbook + verification scripts location, and [[topics/inference-api/_summary]] § "v5 prod-release work" for the PR chain.

## Why this handoff exists

PR #60 (v5 unified API promote to prod) and PR #87 (billing-line `request_id` fix follow-up) shipped to prod today within ~40 min of each other. v5 is **live but dark** — deployed across all three (region, account) combos, zero `/v5/*` traffic in prod. The first real test happens when the partner cutover lands and the first integration call hits prod. This handoff captures the as-of-deploy baselines so any regression after that flip is immediately visible, and flags the one pre-existing observability gap that becomes load-bearing the moment eu-west-1 sees real v5 traffic.

## Current state (as of 2026-05-19 ~17:30 UTC)

- **PR #60** merged `develop → main` at 2026-05-19 15:20 UTC. `deploy-prod.yaml` run [26106835649](https://github.com/aegissystems/actuate-inference-api/actions/runs/26106835649) completed 15:28 UTC across `us-west-2 / 388576304176`, `eu-west-1 / 388576304176`, `eu-west-1 / 558106312574` under `max-parallel: 1`. SUCCESS.
- **PR #87** (billing-line `request_id` fix) merged 15:53 UTC. `deploy-prod.yaml` run [26109022530](https://github.com/aegissystems/actuate-inference-api/actions/runs/26109022530) completed ~16:02 UTC. SUCCESS.
- **PR #85** (docs gap closure — v4 `id` field + v5 error shape) and **PR #88** (E2M rule definitions doc) merged the same afternoon — docs-only, no runtime impact.
- **us-west-2 prod Lambda** (`arn:aws:lambda:us-west-2:388576304176:function:InferenceAPI-prod`): healthy. Numbers below.
- **eu-west-1 prod-eu Lambda(s):** no `AwsLambdaInvocation` telemetry in NR account `3421145` over 7 days. Either a different NR account or missing agent. **Pre-existing gap.** Not regressed by this release — but unresolved before any eu v5 traffic.
- **v5 traffic in prod:** zero. Dark launch confirmed via FACET on `request.uri`.

## us-west-2 baseline (capture immediately post-deploy)

NR account `3421145`. Lambda `InferenceAPI-prod`. Windows: baseline `14:20–15:20 UTC` (pre-deploy), post-deploy `15:28–~17:30 UTC` (includes both deploys + soak).

| Endpoint | Base req/hr | Post req/hr | Base p50 | Post p50 | Base p95 | Post p95 | Base p99 | Post p99 | 5xx base | 5xx post |
|---|---|---|---|---|---|---|---|---|---|---|
| /v4/motionplus/detections | 679 | 4,638 | 53ms | 54ms | 149ms | 177ms | 322ms | 295ms | 0 | 0 |
| /v3/intruderpluswithvehicle/detections | 587 | 1,119 | 222ms | 236ms | 361ms | 371ms | 459ms | 508ms | 0 | 1¹ |
| /v4/intruderpluswithvehicle/detections | 267 | 749 | 151ms | 157ms | 202ms | 214ms | 247ms | 307ms | 0 | 0 |
| /v4/intruderpluswithvehicle/slice/detections | 23 | 15 | 439ms | 436ms | 477ms | 520ms | 477ms | 586ms | 0 | 0 |
| /v5/* | — | 0 | — | — | — | — | — | — | — | — |

¹ Single 500 on `/v3/intruderpluswithvehicle/detections` at 15:29 UTC, 60s after first deploy land, 3.05s duration — cold-start profile, accounted for, no recurrence.

Volume increase on v1–v4 reflects time-of-day load growth (baseline window was lower-traffic hour), not a deploy artifact. Auth errors (401/403): zero in both windows — shared RBAC middleware touched by PR #60 + PR #83 is intact for v1–v4.

**Lambda-level:**
- Cold-start spikes at 15:20 UTC (+14) and 16:00 UTC (+19) aligned with the two deploys; each resolved to 0–3/bucket within one 10-min bucket.
- Avg duration stable: post-deploy ~130ms vs. baseline ~150ms.
- Avg memory: post-deploy 294 MB vs. baseline 252 MB (+17%). Consistent with v5 registry loading. New baseline; [[watch-entity|watch]] as more models join the registry.
- No throttle errors in `AwsLambdaInvocationError`.

## Concrete next steps when first v5 customer is routed

1. **Confirm v5 traffic is actually landing:**
   ```nrql
   FROM AwsLambdaInvocation
   SELECT count(*)
   WHERE entityGuid = '<InferenceAPI-prod-guid>'
     AND request.uri LIKE '%/v5/%'
   FACET request.uri, response.status
   SINCE 30 minutes ago
   ```
   Expect first hits on `/v5/detect` (and possibly `/v5/models`, `/v5/detect_motion`). If status is non-2xx, drill into individual records — but follow the global NRQL rules (no `SELECT *`, tight window, small LIMIT).

2. **[[watch-entity|Watch]] v1–v4 don't regress when v5 takes load.** Re-run the per-endpoint compare above with `SINCE` covering the cutover window. p95 deltas >50ms or any sustained 5xx on the v3/v4 intruder endpoints is the early signal that v5 traffic is starving the shared container (memory, concurrency, model server pool).

3. **Verify partner is hitting the right region.** API Gateway routes by hostname; if the partner is configured against an eu-west-1 endpoint, we have no NR telemetry — see eu observability gap below.

4. **Billing log soak.** PR #87 attached `request_id` to the billing log context inside the frame-handler dep. When v5 traffic starts, confirm v5 billing lines carry both `request_id` and `actuate_camera_id` (PR #71 fields) — see [[2026-05-14_v5-tracking-fields-e2m-design]] for the rule structure. If `request_id` is missing on v5 lines specifically, that's a regression of #87.

## Open follow-ups (not blocking, surface to next session)

- **eu-west-1 observability gap (HIGH if partner routes here).** Determine whether prod-eu Lambda reports to a different NR account, or whether the NR agent / `NEW_RELIC_LAMBDA_HANDLER` env var is missing from the eu function. The eu-west-1 Terraform plan from `deploy-prod.yaml` would have applied the same config the us-west-2 stack has — diff the two function definitions in console or via `aws lambda get-function-configuration` per region. Resolve before any partner is cutover to eu.
- **Lambda logs → NR forwarding.** No `logGroup` data in NR for us-west-2 either. Deep log greps currently fall back to CloudWatch. Worth confirming whether the NR Lambda extension is shipping logs as designed or whether `NEW_RELIC_EXTENSION_SEND_FUNCTION_LOGS=true` is missing.
- **v4 `infer_intruder_plus_with_vehicle_sequence` lost `logger.append_keys(request_id=id)`** — flagged on [[2026-05-14_handoff-v5-release-verification]] pre-merge; post-deploy this means NR log correlation drops on that one endpoint. File `chore(v4)` issue; not surfaced as a runtime problem yet because we're not log-grepping NR.
- **Confluence sync (GH #67) silent-403'ing** — CI green but EDOCS not receiving docs. Pre-existing flag; not a release blocker. Separate follow-up.
- **Memory ceiling.** Post-deploy +17% (252→294 MB) is fine now. When v5 traffic ramps and the registry grows, recheck against the Lambda memory limit set in Terraform.

## Cross-links

- [[2026-05-14_handoff-v5-release-verification]] — pre-merge runbook, verification scripts, S3 cache wire-proof
- [[2026-05-14_v5-motion-history-single-frame-design]] — design surface for the motion-history feature
- [[2026-05-14_v5-tracking-fields-e2m-design]] — billing rule structure incorporating PR #71 tracking fields
- [[2026-05-19]] — daily note with the verification narrative
- [[mark-todos]] § Today's Scope (2026-05-19) "PR #60 v5 cutover — standing [[watch-entity|watch]] only"
- Jira: ENG-259 (release-train + Intruder v5 promotion, EBÜS path)
