---
title: "AIT Phase 1 — `ait diff` (site / library-version / time)"
type: synthesis
topic: engineering-process
tags: [tooling, actuate-integration-tools, ait, diff, s3-versioning, library-version, roadmap]
created: 2026-05-19
updated: 2026-05-19
author: mark
[]
incoming:
  - topics/engineering-process/notes/syntheses/2026-05-19_ait-extensions-spec.md
  - topics/engineering-process/notes/syntheses/2026-05-19_ait-phase-2-validate.md
  - topics/engineering-process/notes/syntheses/2026-05-19_ait-phase-3-audit-tier-emissions.md
  - topics/personal-notes/notes/daily/2026-05-19.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-20
---

# AIT Phase 1 — `ait diff` (site / library-version / time)

The first and foundational Tier 1 extension to [[actuate-integration-tools|`ait`]]. Establishes the diff renderer that Phase 2 (validate) and Phase 3 (audit-tier-emissions) build on top of, plus delivers three high-value diff modes that share one code path.

## Why this is Phase 1

All three diff modes share the same fundamental operation — **load two parsed configs, render their structural delta** — but answer three different operational questions:

- **Mode A (site-vs-site):** "Why is site A behaving differently from site B?"
- **Mode B (cross-library-version):** "Did this library bump silently change how a real customer's config parses?"
- **Mode C (time-version):** "When did this customer's config change?"

Mode B is the bug-prevention payload — would have caught the 2026-05-19 branded-vehicle-ID `METRIC_KEY_TO_AUTOPATROL_CODE` gap mechanically by parsing one settings.json through `actuate-config==1.10.0` vs `==1.10.1` and showing the new `UPS` entry. That's the highest-leverage capability in the entire AIT roadmap.

Modes A and C are valuable independently for triage and incident reconstruction, and they amortize the diff renderer cost.

## Mode A — site-vs-site

```bash
ait diff <deployment_a> <deployment_b>
```

Two S3 fetches, two parses (same library version), structural diff. Default to "changes only" output via `rich` unified-diff style; `--full` flag dumps everything for sanity-checking.

**Diff scope** (decide what counts as "different"):

- `integration_type`, `patrol_type`
- `configured_detection_codes` (the patrol-wide set)
- Per-camera: `feature_deployments[].plain_metrics` keys + values, `feature_deployments[].name`, `model_name`
- `customer.healthcheck.*` boolean flags (image_quality_check, scene_change_check, etc.)
- Recipients list (lisa, hikcentral, etc.) — names + URLs only, redact tokens
- `autopatrol.duration`, `autopatrol.batch_size`, schedule fields

Skip: timestamps, S3 keys, internal IDs that are expected to differ.

## Mode B — same-site, cross-library-version

```bash
ait diff <deployment_id> --library actuate-config --from 1.9.13 --to 1.10.1
ait diff <deployment_id> --library actuate-integration-calls --from 1.11.8 --to 1.11.9
```

Single S3 fetch. Two parses via subprocesses with different library versions pinned. Renderer is identical to Mode A.

The subprocess trick: `uv run --with actuate-config==<version> python -m actuate_integration_tools.parse_to_json <settings-file>` produces a stable JSON dump per version. Parent diffs the JSONs.

Pre-warm the per-version venvs in a cache (`~/.cache/ait/venvs/`) to avoid 15-30s first-call penalty. Use `uv tool install` or a per-version directory with a small lockfile.

This mode also generalizes to multi-library diffs: `--library actuate-config==1.10.0 --library actuate-integration-calls==1.11.9 --to actuate-config==1.10.1` — diff after bumping one of several libraries.

## Mode C — same-site, time-version

```bash
ait history <deployment_id>                                              # list S3 versions + timestamps
ait diff <deployment_id> --from-version <vid_a> --to-version <vid_b>     # explicit version IDs
ait diff <deployment_id> --baseline 2026-05-15                           # snap to nearest version on/before date
ait diff <deployment_id> --last 5                                        # diff most-recent vs N-back
```

`s3:ListObjectVersions` on `actuate-settings/<deployment_id>/settings.json` returns version IDs + LastModified timestamps. S3 versioning is **confirmed enabled** on the bucket as of 2026-05-19, so this mode is viable today.

Per-version fetch uses `s3.get_object(Bucket=..., Key=..., VersionId=...)`. Diff renderer is identical to Mode A.

## Shared infrastructure (built once)

These modules land in `src/actuate_integration_tools/` and get reused by Phase 2 + Phase 3:

- **`SettingsFetcher`** — extends current `s3_settings.fetch_settings` with optional `version_id` param; `list_versions(deployment_id)` for Mode C.
- **`ConfigDiff`** — takes two parsed-config dicts, renders unified-diff. Pure Python, no external deps beyond `rich`.
- **`VenvCache`** — `~/.cache/ait/venvs/<library>=<version>/` materialization. Idempotent — checks for existing venv before recreating.
- **`ParserSubprocess`** — invokes the cached venv to parse a settings dict and return JSON; abstracted so other commands (e.g. `validate`) can also run cross-version checks.

## TODOs (Phase 1)

### 1A — site-vs-site (smallest, ship first) — **SHIPPED 2026-05-19**

- [x] Create `src/actuate_integration_tools/config_diff.py` with `ConfigView`, `view_from_config`, `diff_views`, `render_diff`.
- [x] Define the "what counts as a diff" key list (integration_type, patrol_type, num_cameras, configured_detection_codes, per-camera feature_deployments + metric keys, healthcheck flags, recipients with redacted tokens). Module-level constant for healthcheck flags so the list is reviewable.
- [x] Add `ait diff <a> <b>` subcommand in `cli.py`. Single S3 fetch + single parse per side.
- [x] Smoke-test: site 35831 vs site 35832 (both AP). Output renders correctly; surfaces a real finding — site 35832 has a `non_ups` metric key not appearing in `configured_detection_codes`. **Logged as a separate library follow-up below.**
- [x] Smoke-test: site 35831 vs site 40799 (AP vs VCH). `integration_type`, `patrol_type`, num_cameras (1 vs 42), configured codes all diff cleanly.
- [x] Add `--full` flag for verbose output (prints both views after the delta when set).
- [x] 8 unit tests in `tests/test_config_diff.py` covering empty diff, integration-type change, added camera, metric-key change (the 2026-05-19 bug shape), configured-codes change, healthcheck-flag flip, missing-attribute graceful handling.

**Bug surfaced by 1A on first real use** — same bug-class as the 2026-05-19 branded-vehicle-ID fix. The `non_ups` metric key (Immix spec "Non-UPS Vehicle ID", Tier 3) is being silently dropped by `METRIC_KEY_TO_AUTOPATROL_CODE`. **Deferred 2026-05-19** — needs product input before fix can ship:

- [ ] **(library) Non-UPS mapping fix** — two halves:
  1. *Config side* (configured_detection_codes): add `"non_ups"` → enum code to `METRIC_KEY_TO_AUTOPATROL_CODE` in `actuate-config/.../immix_config.py`. **Open question:** which `AutoPatrolDetectionCodeEnum` value? `NO_LABEL` exists in the enum but isn't currently in `DETECTION_CODE_TIER`. Either map `non_ups → NO_LABEL` and add `NO_LABEL → THREAT`, OR add a new `NON_UPS` enum value (cleaner semantically, but check wire-compat with Immix expectations).
  2. *Sender side* (firing detections): `get_autopatrol_alert_type` in `autopatrol_sender.py` has switch cases for `amazon`/`dhl`/`ups`/`usps`/`fedex`/`school_bus`/`fire_truck` but **not** `non_ups`. Without this case, a `non_ups` model output falls through the else branch and raises `ValueError` — so the runtime can't actually emit a non_ups alert even if the metric is configured.
- [ ] **Runtime-impact today: zero.** Site 35832 (only fleet site with non_ups configured today, that we've checked) is emitting tier=3 correctly because CROWD/SMOKE/branded codes are also configured. No non_ups-only patrol exists in the fleet that would mis-tier. Fix is correctness-only, not customer-impacting.
- [ ] **Trigger:** product window to confirm the enum mapping. After that, the actual library change is small (one mapping line + one `DETECTION_CODE_TIER` entry + one `get_autopatrol_alert_type` case + tests).

### 1B — cross-library-version (highest bug-prevention value) — **SHIPPED 2026-05-19**

- [x] Skipped explicit `VenvCache` module — uv's own `--with` caching is sufficient and avoids reimplementing what uv already does well. Subsequent invocations with the same pin set reuse uv's resolution cache transparently. The `~/.cache/ait/venvs/` idea was pre-emptive optimization; revisit only if uv's cache proves insufficient (e.g. multi-package pin sets we want to materialize ahead of time).
- [x] Create `src/actuate_integration_tools/parser_subprocess.py` — `parse_with_library_version(settings, library, version)` spawns `uv run --no-project --with actuate-config==<version> --with actuate-integration-calls --with shapely python _view_extractor.py`. Pipes settings on stdin, reads ConfigView-shaped JSON from stdout.
- [x] Create `src/actuate_integration_tools/_view_extractor.py` — standalone script with the view-extraction logic. No imports from the parent package so it runs in any isolated venv. Shape must stay in sync with `config_diff.ConfigView` (documented in module docstring).
- [x] Add `view_from_dict` to `config_diff.py` for parent-process deserialization.
- [x] Add `--library --from --to` flag handling on `ait diff`. Validates the flag triad and routes to `_diff_library_version` helper.
- [x] Pass CodeArtifact creds through to the subprocess via `UV_INDEX_CODEARTIFACT_*` env vars so it can pull private packages.
- [x] Smoke-test: parse site 35831's settings through `actuate-config==1.10.0` vs `==1.10.1`. Confirmed `UPS` appears only in the 1.10.1 output (regression cover for the 2026-05-19 branded-vehicle-ID bug).
- [ ] Document the cross-version diff usage in `actuate-integration-tools/README.md`.
- [ ] Unit-test `view_from_dict` against synthetic dicts (round-trip with `view_from_config`).

### 1C — time-version (S3 versioning) — **SHIPPED 2026-05-19**

- [x] Extend `fetch_settings(deployment_id, version_id=None)` — passes `VersionId` to `s3.get_object` when set.
- [x] Add `list_settings_versions(deployment_id) -> list[{version_id, last_modified, is_latest, size}]` using `list_object_versions` paginator (handles >1000-version histories transparently).
- [x] Add `ait history <deployment_id>` subcommand printing the version timeline. `--limit` flag bounds output (default 20) with a "+N older" note when truncated.
- [x] Add `ait diff <deployment_id> --from-version <id> [--to-version <id>]` flag handling. `--to-version` defaults to latest if omitted.
- [x] Add `--last <N>` shorthand for "current vs N-back". Resolves against the version list and validates bounds.
- [x] Smoke-test on site 35831: pulled 26-version history going back to 2025-12-09; diff'd oldest vs newest and surfaced the full customer-side config evolution (detection codes 0 → 3, healthcheck flags flipped, new feature deployments added).
- [x] Smoke-test on site 35832: confirmed renderer is silent on size-change-only diffs (40,889 → 62,743 bytes between versions 4 and 0, no tracked-field deltas).
- [ ] Add `--baseline <YYYY-MM-DD>` snap-to-nearest-before-date convenience flag. **Deferred** — `--last N` covers the common case and `--from-version <vid>` covers explicit version pinning; date-based snapping is convenience polish.
- [ ] Unit tests for `list_settings_versions` (mock S3 client returning a paginated response) and the `--last` resolution logic.

### Cross-phase polish

- [ ] All three modes share `ConfigDiff` — write one set of tests in `tests/test_config_diff.py` against synthetic config dicts (no real S3 / library version needed).
- [ ] Update `actuate-integration-tools/README.md` Usage section with examples for all three modes.
- [ ] Update [[actuate-integration-tools]] KB entity note's "Commands today" section once Phase 1 ships.
- [ ] Update `pre-merge-workflow` skill's Step 3.5 to recommend Mode B explicitly for library bumps.

## Estimate

~4-6h focused work for the complete Phase 1 set. 1A is ~1h, 1B is ~3h (subprocess machinery is the chunk), 1C is ~1-2h.

## Cross-references

- [[actuate-integration-tools]] — entity
- [[2026-05-19_ait-extensions-spec]] — parent spec (Phases 1–3 arc)
- [[2026-05-19_ait-phase-2-validate]] — Phase 2 (builds on `SettingsFetcher`) ✅ shipped 2026-05-20
- [[2026-05-19_ait-phase-3-audit-tier-emissions]] — Phase 3 (builds on `ConfigDiff` + new NR client)
- [[2026-05-20_ait-brain-in-jar-spec]] — Phases 4–10 (the next arc — state capture + replay)
- [[2026-05-18_libav-decoder-warmup-frame-fix]] — Eyeforce work that surfaced the toolchain need
