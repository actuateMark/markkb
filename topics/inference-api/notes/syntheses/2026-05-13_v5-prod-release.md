---
title: "v5 Prod Release — Pre-merge Verification & Cutover Notes"
type: synthesis
topic: inference-api
tags: [v5, release, ebus, ed-32, regression-testing, prod-promotion]
jira: "ED-32"
pr: "https://github.com/aegissystems/actuate-inference-api/pull/60"
created: 2026-05-13
updated: 2026-05-13
author: kb-bot
incoming:
  - topics/billing/notes/syntheses/2026-05-14_v5-tracking-fields-e2m-design.md
  - topics/inference-api/notes/concepts/2026-05-14_handoff-v5-release-verification.md
  - topics/personal-notes/notes/daily/2026-05-13.md
  - topics/personal-notes/notes/daily/2026-05-14.md
incoming_updated: 2026-05-27
---

# v5 Prod Release — 2026-05-13

[PR #60](https://github.com/aegissystems/actuate-inference-api/pull/60) promotes the unified v5 partner API (`POST /v5/detect`, `GET /v5/models`) from `develop` to `main` for the [[ebus|EBUS]] cutover. See [[v5-api-design]] for the design baseline and [[2026-04-14_v5-implementation-complete]] for the original implementation record; this note captures pre-merge verification only.

## Test evidence (against `develop` @ `aa89e68`)

Driven through the extended `tools/v5-test-page/regression.html` against the local Lambda runtime via `kubefwd` proxying `ds-model-prod`:

- **v1–v4 happy paths** — pass. Identical detection counts across versions for the same image (v2 intruder = v3 intruder = v4 intruder = v5 intruder = 15 detections). Filter chain refactor (the `make_filters` extraction into `filter_builder.py`) is byte-clean.
- **v5 happy paths** — pass across `intruder` (`max_slices=1`), `intruder` slicing (`max_slices=4`), `weapon`, `pet`, `motion-plus`.
- **Sensitivity sweep** (`low` / `medium` / `high` / numeric float) — v4 ↔ v5 byte-consistent at every band; strongest single signal that the threshold mapping is unchanged.
- **v5 error paths** — `404` on unknown `model_id`, `400` on invalid base64, `422` on data-schema violation (`max_slices=99` exceeds `le=9` bound).
- **Tracking-id round-trip** — v4 non-legacy routes echo `id` form field via `X-Request-Id` header; legacy `/vs/` routes echo via `body.id`; v5 `camera_id` / `site_id` echo in response body.
- **URL-frame `/v4/*/vs/detections`** — verified end-to-end against `httpbin.org/image/jpeg`. Download + inference + response built correctly with the per-frame `image.id` set to the source URL.
- **LegacyError envelope fix from [PR #63](https://github.com/aegissystems/actuate-inference-api/pull/63)** — live-verified. URL-fetch failures now return proper JSON 400 envelopes; previously the `LegacyError` Pydantic-v2 construction crashed inside `v4.py`'s catch-all, surfacing a plain-text 500 to clients.

## Acknowledged behavior change at cutover

`/v4/*/vs/detections` with URL-sourced frames previously echoed `image.id == "url"` for every frame regardless of input. The per-frame URL fix (commit `5011439`) now echoes the source URL string. **No partner pins on the old value** per stakeholder confirmation 2026-05-13. This is the only 200-path response shape change reaching live v1-v4 traffic at cutover.

## Follow-up (post-merge, not a blocker)

`inference_api/api/endpoints/v4.py:340` removed `logger.append_keys(request_id=id)` in `infer_intruder_plus_with_vehicle_sequence` when refactoring to align with the seven other v4 endpoints (which set the X-Request-Id header but never used `append_keys`). The header echo is intact and verified live, but **[[new-relic|New Relic]] log correlation by `request_id` will stop working on this one endpoint** until the line is restored. Worth a `chore(v4)` issue post-merge.

## Process notes worth keeping

- **Local branch can be stale vs `origin/develop` for hours** without `git fetch` reflecting in `git status` if the fetch isn't run fresh. The full first day of regression runs in this release was against five-commits-stale local code; live behaviour didn't match the PR contents. Always `git pull --ff-only` before running pre-release regression against PR head.
- **PR audit findings cannot be taken on faith** — the auditor's claim about a fix being on `develop` was *correct for `origin/develop`* but the local working tree didn't have it. Live-test the audit's claims before transcribing them into a PR body.
- The `tools/v5-test-page/run.sh` now tees server stdout to `/tmp/inference-api-local.log` — investigations into 5xx responses no longer require copy-paste from the terminal.

## Cross-references

- [[v5-api-design]] — design baseline
- [[v5-implementation-patterns]] — implementation reference
- [[2026-04-29_v5-slicing-as-parameter]] — slicing-as-parameter consolidation that produced the registry's 4-model shape
- [[2026-04-14_v5-implementation-complete]] — original implementation synthesis
- [[rust-lambda-authorizer]] — RBAC chain that gates v5 model visibility
