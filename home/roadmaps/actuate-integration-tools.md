---
title: "Roadmap — AIT (Actuate Integration Tools)"
type: synthesis
tags: [roadmap, ait, integration-tools, testing, home, handoff]
updated: 2026-06-25
author: kb-bot
incoming:
  - home/README.md
  - home/roadmaps/roadmaps.md
  - topics/engineering-process/notes/syntheses/2026-05-19_ait-extensions-spec.md
  - topics/engineering-process/notes/syntheses/2026-05-19_ait-phase-1-diff.md
  - topics/engineering-process/notes/syntheses/2026-05-19_ait-phase-2-validate.md
  - topics/engineering-process/notes/syntheses/2026-05-19_ait-phase-3-audit-tier-emissions.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-brain-in-jar-spec.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-10-s3-sink-review-ux.md
  - topics/engineering-process/notes/syntheses/2026-05-21_ait-validator-dovetail.md
  - topics/engineering-process/notes/syntheses/2026-05-21_ait-validator-integration-plan.md
incoming_updated: 2026-06-25
---

# Roadmap — AIT (Actuate Integration Tools)

> A standalone Python toolkit (`ait` CLI) for **inspecting + validating live connector deployments without booting the connector**, grown into a broader engineering/QA/SRE testing kit. Deep design record: [[actuate-integration-tools]] (entity) + [[2026-05-22_actuate-testing-toolkit-overview]] (master synthesis). Repo: `aegissystems/actuate-integration-tools` (pushed to the org 2026-06-23). **Owner: TBD — see "decision" below.**

## What it is
Given a deployment ID (e.g. `connector-35831-autopatrol-259`), AIT loads that deployment's real `settings.json` from S3, parses it through the **production `actuate-config` library pinned to the same versions stage runs** (so behaviour matches the live pods), and surfaces derived properties — tier, detection codes, integration type, per-camera features — in *seconds* instead of code-spelunking, waiting on a cron + [[new-relic|New Relic]], or booting a local connector. It's **read-only** (no infra writes, no Immix/NR calls). It found a real under-classification bug in `actuate-config` on day one (missing branded-vehicle metric keys → wrong AutoPatrol tier; fixed via actuate-libraries#353).

It has since grown a **"brain-in-jar"** substrate: serialize in-memory pipeline state to a dump, then replay pipeline components in isolation on a laptop — plus a `simulate` synthetic-data + Hypothesis fuzz arc.

## Current state — working tool, bus-factor 1
*Snapshot 2026-06-25. Per-phase status can drift as work resumes — trust the repo's `CLAUDE.md` + `uv run pytest` over this table if they disagree.*

Single-author (Mark), ~107 tests, version 0.1.0, recently promoted to the org. **Unusually well-documented in the KB** (entity note + ~15 per-phase syntheses) — but **absent from product-roadmap and team-structure**, so it has no org ownership signal beyond Mark.

| Arc | Surface | Status |
|---|---|---|
| Inspect | `ait diff` (site / lib-version / time) · `ait validate` (9-invariant battery) | ✅ shipped |
| Inspect | `ait audit-tier-emissions` (predicted vs actual tier from NR) | ⬜ sketched (~3–4h, needs NRClient) |
| Brain-in-jar | IDP serializer (keystone) · `DumpReplayPuller` · `ait replay` / `replay step` / `replay-alert` | ✅ shipped (library-side via actuate-libraries#359) |
| Brain-in-jar | camera `from_dump` · site-manager crash hook · S3 dump sink + `ait dumps` UX | ⬜ sketched (8/9/10) |
| QA | `ait simulate` (6 scenarios + Hypothesis fuzz) | ✅ shipped |
| QA | `ait sweep` (config search: video + expected alert → config) | ⬜ sketched (blocked) |

## Architecture
Three arcs over one substrate: **inspection** (`s3_settings` → `config_loader` → `config_diff`/`parser_subprocess` + `validators/`), **brain-in-jar** replay (much of it lives library-side in actuate-libraries: IDP `to_dict`/`from_dict`, `data_dump` sidecars, `DumpReplayPuller`, capturing/replay alert senders), and **simulate/QA** (factories-then-strategies convention). The **keystone is the IDP serializer** — replay and simulate both round-trip through it, so one path serves synthetic data *and* (future) production crash dumps. Capture is **off-by-default, env-gated, zero-I/O-when-off** by design (per-pod taxes compound across 100+ pods).

## Recommended roadmap
**Immediate (inheritor onboarding, ~1 day) — do these first:**
1. **Drop the `[tool.uv.sources]` path-pin block → version pins.** It currently editable-pins libraries to Mark's local `/home/mork/work/actuate-libraries` checkout, so **`uv sync` fails on any other machine.** The libraries have published — swap to version pins. *Highest-priority, easily-missed portability blocker.*
2. **Make the promote-vs-freeze call:** assign an owner, or it orphans. It has deep docs but no roadmap presence.
3. Smoke-test: `uv run pytest` (107 tests) + `ait validate`/`diff`/`simulate` against 2–3 real deployments.

**Near-term, high-leverage (independent):** Phase 9 (site-manager crash hook → real production captures) then Phase 10 (S3 sink + `ait dumps`); Phase 3 (`audit-tier-emissions`, ~3–4h); fleet-wide `ait validate --all` / `scan-fleet --metric-key X`.

**Coordination-gated:** Phase 8 (camera `from_dump`, blocked on lifting validator mocks upstream); Phase 12 (`ait sweep` for QA — answers a stated QA gap); **[[watch-entity|Watch]] Manager integration** — the biggest strategic vector: AIT's Hypothesis primitives fit the upcoming [[watch-entity|Watch]] Manager (a pure function of time + DB state) *better than the monolithic connector*, ~80% coverable today. Ties AIT directly to the [[watchman-fleet-architecture|fleet re-architecture]].

## Risks
- **Bus-factor 1, departing** — without an owner it freezes (deep KB docs mitigate but don't replace ownership).
- **Portability blocker live today** (the path-pins above).
- **Version drift** — AIT pins `actuate-config`/`actuate-integration-calls` to match connector stage; if not kept in sync, the "matches live pods" guarantee silently breaks. No automation enforces it.
- **In-repo CLAUDE.md still says "local-only"** (stale — it was pushed 2026-06-23). Trust code first.

## Read next (ranked)
1. `actuate-integration-tools/CLAUDE.md` (repo) — the definitive orientation/handoff (per-phase status, auth, fragility warnings).
2. `actuate-integration-tools/README.md` (repo) — full command surface with examples.
3. [[actuate-integration-tools]] — KB entity note (origin, when-to-use, roadmap).
4. [[2026-05-22_actuate-testing-toolkit-overview]] — master synthesis (5-tool map, per-persona workflows).
5. [[2026-05-29_ait-watch-manager-integration]] — the forward expansion onto the [[watch-entity|Watch]] Manager test surface.
