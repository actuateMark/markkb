---
title: "AIT Phase 2 — `ait validate <deployment_id>`"
type: synthesis
topic: engineering-process
tags: [tooling, actuate-integration-tools, ait, validation, pre-flight, roadmap]
created: 2026-05-19
updated: 2026-05-19
author: mark
[]
incoming:
  - topics/engineering-process/notes/syntheses/2026-05-19_ait-extensions-spec.md
  - topics/engineering-process/notes/syntheses/2026-05-19_ait-phase-1-diff.md
  - topics/engineering-process/notes/syntheses/2026-05-19_ait-phase-3-audit-tier-emissions.md
  - topics/personal-notes/notes/daily/2026-05-19.md
incoming_updated: 2026-05-20
---

# AIT Phase 2 — `ait validate <deployment_id>`

Beyond "did it parse without exception" — a battery of semantic invariants over the parsed config, surfaced as a pre-flight checklist for customer-facing deploys.

## Why this is Phase 2

Phase 1's `ait dump` / `ait tier` / `ait detections` are great for *exploration* — "what does this config look like?". Phase 2 is for *gating* — "should this config be deployed at all?". The shape is different: a battery of small assertions, each returning `(passed, message, severity)`, runnable against an arbitrary deployment.

It depends on Phase 1's `SettingsFetcher` (and shares no other infra), so once Phase 1 lands the lift is small.

## Initial invariant checklist

Each entry below is a small Python function returning `(passed: bool, message: str, severity: Literal["error", "warning", "info"])`. The table is extensible — every time we find a new "config that shipped but shouldn't have" failure mode, add a row.

| Check | Severity | What it catches |
|---|---|---|
| `patrol_type` aligns with `integration_type` (e.g. no `VisualCameraHealth` on a non-VCH integration) | error | Admin-side misclassification |
| Branded vehicle ID feature_deployment paired with a base `intruder` or `vehicle` deployment | warning | Branded-only patrols (the 2026-05-19 bug shape — tier could under-classify) |
| Every camera has at least one feature_deployment with `plain_metrics` non-empty | error | Empty patrols / degenerate cameras |
| Every recipient (lisa, hikcentral, patriot, etc.) has scheme + auth token where required | error | Customer config errors that'd fail at runtime |
| `customer.healthcheck.*` boolean flags are bool, not "true"/"false" strings | warning | Admin-API serialization bugs |
| No `.devN+` version strings anywhere in model_name / feature deployment fields | error | Dev pins leaking through to customer configs |
| `autopatrol.duration` is in the expected range per `patrol_type` (VCH ~2s, AP ~10s) | warning | Out-of-spec durations that could blow Immix billing budget |
| Camera count > 0 | error | Patrol with no cameras |
| All model_name values resolve in a known model registry | warning | Drift between admin and connector deploys |

Each invariant lives in `src/actuate_integration_tools/validators/<name>.py` so the catalog is browseable and each rule has its own unit tests.

## CLI shape

```bash
# Default: full battery, exit 0 if no errors (warnings OK)
ait validate <deployment_id>

# Strict mode: exit non-zero on any warning too
ait validate <deployment_id> --strict

# Run a single invariant
ait validate <deployment_id> --check branded-vehicle-pairing

# JSON output for piping into other tools
ait validate <deployment_id> --json
```

## Composition with Phase 1

Two flows reuse Phase 1 infra:

- **Cross-version validation:** `ait validate <deployment_id> --library actuate-config --version 1.10.1` runs the battery with the parsed config produced by a specific library version. Useful for "will this customer's config still pass validation after I bump the library?".
- **Pre-deploy diff guard:** `ait diff <deployment_id> --baseline <last-deploy-date> | ait validate --filter changed-codes` — only run validators against fields that changed since the last deploy. (Optional polish — not in the initial table.)

## TODOs (Phase 2)

### Core

- [ ] Create `src/actuate_integration_tools/validators/__init__.py` with a `Validator` protocol/dataclass: `(name: str, severity: str, check: Callable[[Config], tuple[bool, str]])`.
- [ ] Implement each invariant as its own module under `validators/`:
  - [ ] `validators/patrol_type_alignment.py`
  - [ ] `validators/branded_vehicle_pairing.py`
  - [ ] `validators/non_empty_feature_deployments.py`
  - [ ] `validators/recipient_auth.py`
  - [ ] `validators/healthcheck_flag_types.py`
  - [ ] `validators/no_dev_version_strings.py`
  - [ ] `validators/autopatrol_duration_range.py`
  - [ ] `validators/camera_count.py`
  - [ ] `validators/model_name_resolves.py`
- [ ] Create a `ValidatorRegistry` that exposes the full catalog (auto-discovery via `pkgutil.iter_modules` or explicit table).
- [ ] Add `ait validate <deployment_id>` subcommand in `cli.py`.
- [ ] Add `--strict`, `--check <name>`, `--json` flags.
- [ ] Add per-validator unit tests under `tests/validators/test_<name>.py` — each gets a passing fixture + a failing fixture.

### Real-customer smoke tests

- [ ] Run the full battery against site 35831 and site 40799 — both should pass cleanly today since they're known-good production sites.
- [ ] Run against a deliberately-malformed synthetic settings dict — assert each validator catches its target failure mode.

### Documentation

- [ ] Add a "Validators" section to `actuate-integration-tools/README.md` listing the catalog + how to add new ones.
- [ ] Update [[actuate-integration-tools]] entity note with the `ait validate` command.
- [ ] Add a "Validation gate" step to the [[2026-04-14_connector-library-deployment-lifecycle|connector-library-deployment-lifecycle]] synthesis — between Phase 2.5 (ait sanity-check) and Phase 3 (PR cleanup).

### Stretch (defer if scope creeps)

- [ ] Cross-version validation flag (`--library --version`) wires through Phase 1's `ParserSubprocess`.
- [ ] Fleet-validate mode (`ait validate --all` runs the battery across every deployment in the bucket). Risk: bucket-scale parallel work; bound carefully. Probably its own follow-up rather than in Phase 2.

## Estimate

~2-3h focused work for the initial 9 validators + CLI wiring + tests. Roughly linear thereafter — each new validator is ~15-20 min to add (module + 2 tests). Catalog grows naturally as we learn new failure modes.

## Status — ✅ shipped 2026-05-20

Landed on `actuate-integration-tools` `main` as commit (Phase 2 polish committed alongside the validator framework). 9 validators registered; CLI surface `ait validate <deployment_id>` with `--strict` / `--check` / `--json` / `--list`. Real-customer smoke tests on sites 35831 (AutoPatrol) and 40799 (VCH) both pass cleanly after two schema fixes caught during the smoke run:

- `healthcheck-flag-types` reads `.enabled` on each flag object (real shape is `{enabled: bool, alert_emails: [], ...}`, not bare bool).
- `model-name-resolves` uses `model_name` key (not `name`) for the `settings["models"]` registry.
- `non-empty-feature-deployments` scopes to `AutoPatrol` — VCH cameras legitimately have no detection metrics.

30 new tests; 59 total in the repo. README updated with the catalog table.

## Cross-references

- [[actuate-integration-tools]] — entity
- [[2026-05-19_ait-extensions-spec]] — parent spec (Phases 1–3 arc)
- [[2026-05-19_ait-phase-1-diff]] — Phase 1 (depends on `SettingsFetcher`)
- [[2026-05-19_ait-phase-3-audit-tier-emissions]] — Phase 3 (sibling, independent)
- [[2026-05-20_ait-brain-in-jar-spec]] — Phases 4–10 (the next arc — state capture + replay)
- [[2026-04-14_connector-library-deployment-lifecycle]] — the workflow this gates
