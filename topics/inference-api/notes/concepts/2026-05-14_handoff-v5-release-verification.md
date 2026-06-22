---
title: "Handoff: PR #60 pre-merge verification for Monday cutover"
type: concept
topic: inference-api
tags: [handoff, v5, pr-60, verification, monday-cutover]
created: 2026-05-14
updated: 2026-05-14
author: kb-bot
incoming:
  - topics/inference-api/notes/concepts/2026-05-19_handoff-v5-post-release-watch.md
  - topics/personal-notes/notes/daily/2026-05-14.md
  - topics/personal-notes/notes/daily/2026-05-15.md
  - topics/personal-notes/notes/daily/2026-05-18.md
  - topics/personal-notes/notes/daily/2026-05-19.md
incoming_updated: 2026-05-27
---

# Handoff: PR #60 pre-merge verification for Monday cutover

## Entry point

Read [[2026-05-14_v5-motion-history-single-frame-design]] § "Live E2E results" then [[topics/inference-api/_summary]] § "v5 prod-release work (2026-05-14)" for the full PR chain.

## Why this handoff exists

PR #60 (`develop → main`, v5 prod release) is paused until Monday per partner feedback timing. Between today's wrap and Monday morning, the goal is to **re-confirm the v5 surface area on dev-api is still healthy** before clicking merge — not to add new work to the PR. Nine PRs (#68 through #76) landed in develop today; any drift between now and Monday (rolling deploys, infra changes, partner traffic patterns) needs a sanity check.

## Current state

- **PR #60 (last verified 2026-05-15 ~14:42Z):** OPEN, MERGEABLE, `mergeStateStatus: CLEAN`, **11/11 GH Actions GREEN**, cursor scanned (0 new findings since 2026-05-14T20:18Z), HEAD `0cd2100a2` pointing at develop tip including PRs #68–#76.
- **dev-api re-verified 2026-05-15 ~14:42Z (Friday morning soak):** 9/9 `detect_motion` E2E pass + 6/6 model-swap regression pass. Cache-flow wire-level proof captured in [[2026-05-14_v5-motion-history-single-frame-design#re-verified-2026-05-15-friday-morning-pr-60-still-parked-for-monday-cutover]] with full JSON responses + S3 object metadata.
- **S3 cache state:** 11 objects in `actuate-inference-api-frame-cache-dev-388576304176-us-west-2/inference-api/v5/last-frame/verisure-dev/`. Lifecycle (`delete-stale-frames`, 1-day expiry) is attached to every object. SSE-AES256 at rest. Object ETags match local fixture md5s — Lambda PUTs the decoded frame verbatim, no transformation.
- **Lambda env (us-west-2 dev):** `FRAME_CACHE_BUCKET=actuate-inference-api-frame-cache-dev-388576304176-us-west-2`, `INTRUDER_ENDPOINT_URL=https://ingress.actuateui.net/prod/int07-actuate003-v8/infer`, `SLICED_INTRUDER_PLUS_WITH_VEHICLE_ENDPOINT_URL=https://ingress.actuateui.net/prod/slicing/int07-actuate003-v8/infer`.

## Concrete next steps

1. **Re-run targeted regression (no network):**
   ```bash
   cd /home/mork/work/actuate-inference-api
   ./scripts/v5_targeted_regression.sh
   ```
   *Note: the script + the parity-check script are still stashed locally; pop the stash first → `git stash list` → `git stash pop <ref>`. The scripts haven't landed in a PR yet (separate follow-up).*

2. **Re-run the dev-api detect_motion E2E:**
   ```bash
   uv run --project=inference_api python /tmp/v5_detect_motion_verify.py
   ```
   Expect 9/9 PASS. The script uses a unique-per-run `camera_id` so re-running doesn't trip on stale S3 cache.

3. **Re-run the int07-actuate003-v8 model verification:**
   ```bash
   uv run --project=inference_api python /tmp/v5_int07_model_verify.py
   ```
   Expect 6/6 PASS (intruder direct + sliced + weapon + pet + motion-plus + GET /v5/models).

4. **Re-run the v1-v4 parity check against prod** (as a release sanity):
   ```bash
   uv run --project=inference_api python scripts/v5_prod_parity_check.py
   ```
   Expects "skip v5/models (not deployed on prod yet)" + 12/12 PASS on v1-v4 dev↔prod parity.

5. **Confirm pre-merge gates on PR #60:**
   - Lambda authorizer prod DDB has `v5_detect` role on at least one partner key
   - Partner cutover timing confirmed
   - `WEBHOOK_SECRET` set on the Confluence-notifier Lambda env in prod account

6. **If all green: merge `gh pr merge 60 --squash --repo aegissystems/actuate-inference-api`** and monitor `deploy-prod.yaml` (us-west-2 → eu-west-1 388 → eu-west-1 558, `max-parallel: 1`).

## Gotchas

- **CodeArtifact token for tox/pytest expires every 12h.** Re-export:
  ```bash
  export UV_INDEX_CODEARTIFACT_USERNAME=aws
  export UV_INDEX_CODEARTIFACT_PASSWORD=$(AWS_PROFILE=prod aws codeartifact get-authorization-token \
    --domain actuate --domain-owner 388576304176 --region us-west-2 \
    --query authorizationToken --output text)
  ```

- **`actuate-internal-v5-test` API key on prod** has `full_access` + `v5_detect` + `docs` roles (per the upgrade run earlier today via `generate_api_key.py`). The key is in `.env` as `PROD_API_KEY`.

- **`generate_api_key.py` was patched locally** to add `--v5_detect` flag — that's in the stash, not yet committed to a PR. If someone else runs the script, they'll be missing the flag.

- **Two stale-from-earlier-days `[x]` items were swept** in today's wrap (§12 line 350 closed 2026-05-07, §28 NF2 closed 2026-05-11) — they're now in [[2026-05-14]] § "Closed Sub-items" with the "swept earlier" qualifier per the rolling-forward convention. If you see those bullets referenced anywhere as still-open, they're not.

## Outstanding follow-ups (post-cutover)

- **EU regions still on old INTRUDER + slicing URLs.** PR #76 only updated `dev us-west-2`. EU regions use different ingress hosts and need a separate decision (per-region model server or cross-region call).
- **Prod tfvars int07 swap.** Same as above — deferred until dev has a few days of soak.
- **New E2M rules for per-camera + detect_motion dimensions.** Documented in [[2026-05-14_v5-tracking-fields-e2m-design]] § "Gap analysis"; gated on resolving the NR `7081731` vs `3421145` account question first.
- **Dashboard signals for new E2M rules.** Per the §9 mark-todos discipline rule — every new E2M rule must ship with a dashboard signal.
- **`generate_api_key.py` `--v5_detect` flag + parity scripts** — small follow-up PR to land the stashed tooling.
- **Confluence sync (PR #67) silent-403'ing.** Pre-existing, not my work. Mark on the cursor finding from yesterday.

## Links

- PR #60: https://github.com/aegissystems/actuate-inference-api/pull/60
- Today's PR chain (10 total): #66 (Jacob), #68–#76 (this session)
- Design synthesis: [[2026-05-14_v5-motion-history-single-frame-design]]
- E2M design: [[2026-05-14_v5-tracking-fields-e2m-design]]
- E2M existing rules: [[2026-05-14_inference-api-e2m-rules]]
- Yesterday's verification: [[2026-05-13_v5-prod-release]]
