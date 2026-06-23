---
title: "Brain-in-jar arc handoff (2026-05-27)"
type: synthesis
topic: personal-notes
tags: [handoff, brain-in-jar, actuate-integration-tools, actuate-libraries, ait, phase-4, phase-5, phase-6, phase-7, phase-11, session-resume]
created: 2026-05-27
updated: 2026-05-27
author: mark
incoming:
  - topics/engineering-process/notes/entities/actuate-integration-tools.md
  - topics/engineering-process/notes/syntheses/2026-05-27_zack-coordination-brain-in-jar.md
  - topics/engineering-process/notes/syntheses/2026-05-29_ait-watch-manager-integration.md
  - topics/personal-notes/notes/daily/2026-05-27.md
  - topics/personal-notes/notes/daily/2026-06-04.md
incoming_updated: 2026-06-19
---

# Brain-in-jar arc — handoff (2026-05-27)

State-of-the-world for picking up where I left off after a long session block. Every commit, branch, test count, and pending coordination item — all in one place so the next session can start cold without re-deriving context.

## TL;DR

**Shipped this arc**: Phases 1 (inspect) + 2 (validate) + 4 (IDP serializer) + 5 (DumpReplayPuller) + 6a (replay inspect/diff) + 6b (replay --step) + 7 (alert capture/replay) + 11 (simulate). Five new library commits sit on `feat/idp-serializer-brain-in-jar-phase-4` of `actuate-libraries`, **not yet pushed**. AIT (local-only repo) has all its phase commits on `main`.

**Blocked on**: pushing the libs branch + opening a PR so Zack can pick up Plays A + B (validator-side coordination) and so AIT can drop path-pins to version pins. Coordination message drafted: [[2026-05-27_zack-coordination-brain-in-jar]].

> **Update 2026-06-04 — PR #359 conflicts resolved + pushed.** The branch was pushed and PR [#359](https://github.com/aegissystems/actuate-libraries/pull/359) opened (since 2026-05-27); it went CONFLICTING as main advanced 36 commits. Resolved in worktree `/tmp/aclibs-brain-in-jar` (team `/tmp/aclibs-*` pattern; main checkout left on a sibling's `fix/actuate-pullers-pyav17-followups`). The only conflicts were 3 CI-managed version fields — `actuate-pipeline/pyproject.toml`→2.12.3, `actuate-pullers/pyproject.toml`→1.17.20, and the matching `uv.lock` stanzas — resolved to **main's stable** (dropping the dev-version artifacts from the `[no ci]` auto-bump; CI re-bumps from the `[minor:...]` tags at squash-merge). Merge commit `00f58779` pushed → **#359 MERGEABLE**, CI running. Zack coordination held on Mark's side (has Zack's reply re: the plans). At squash-merge: strip `[no ci]` lines per [[feedback_library_no_dev_versions]]; keep the `[minor:actuate-pipeline-objects] [minor:actuate-instrumentation] [patch:actuate-pipeline] [minor:actuate-alarm-senders] [minor:actuate-pullers]` tag list.

**Next phase candidates** (independent, pick any): Phase 8 (camera from_dump — needs Plays B+C), Phase 9+10 (production-side crash hook + S3 sink), Phase 12 (`ait sweep` for QA — blocked on Plays A+B).

## Repo state

### actuate-libraries (`/home/mork/work/actuate-libraries/`)

Branch: `feat/idp-serializer-brain-in-jar-phase-4`, **5 commits ahead of `origin/main`, not pushed**:

```
78a46cf9 [minor:actuate-pullers]           feat: Phase 5 — DumpReplayPuller
e1c4bffe [minor:actuate-alarm-senders]     feat: Phase 7 — AlertData round-trip + Capturing + Replay senders
d0390952 [minor:actuate-pipeline-objects]  feat: testing factories + Hypothesis strategies (Phase 11)
9684b950 docs                              Phase 4 follow-ups — READMEs + full-shape smoke test
50e961ba [patch:actuate-pipeline]          fix: DataDumpLink calls to_dict() (Phase 4 fix)
48954367 [minor:actuate-instrumentation]   feat: extend data_dump with sidecars + lazy loader (Phase 4)
dd0542d6 [patch:actuate-pipeline-objects]  feat: brain-in-jar serialization for IDP/PDP/WDP (Phase 4)
```

Tag conventions on these commits already match the CI's bump-on-merge convention. When the PR squash-merges to `main`, each `[major|minor|patch:<lib>]` tag fires a CI bump + publish. **[[watch-entity|Watch]] the squash subject** per [[feedback_library_no_dev_versions]] — strip any `[no ci]` from the dev-bump auto-commits.

### actuate-integration-tools (`/home/mork/work/actuate-integration-tools/`)

Local-only repo. Branch `main`, 6 phase commits on top of the initial three:

```
fde7b93  feat: Phase 7 (AIT side) — ait replay-alert list/show/diff
5d5b7b1  feat: Phase 6b — ait replay step (single-step replay against captured IDP)
c91dcae  feat: Phase 6a — DumpLoader + ait replay (read-only inspect + diff)
79d482e  feat: Phase 11 — ait simulate (synthetic IDPs + Hypothesis fuzz)
df9edae  feat: Phase 2 — ait validate <deployment_id>
3c810c6  chore: Phase 1 polish — tests, README, dedupe
```

No remote configured. Per [[actuate-integration-tools]] entity note, the promotion criterion is "3+ subcommands in active use AND a second contributor" — both arguably met now (validate / diff / simulate / replay / replay-alert all in use; Zack is a probable next contributor). Worth considering promotion to `aegissystems/actuate-integration-tools`.

### Path-pins to drop once libs publish

AIT `pyproject.toml` has these `[tool.uv.sources]` block entries:

```toml
[tool.uv.sources]
actuate-pipeline-objects = { path = "...", editable = true }
actuate-instrumentation = { path = "...", editable = true }
actuate-pipeline = { path = "...", editable = true }
# actuate-alarm-senders deliberately NOT pinned — transitive-dep resolver conflict;
# AIT reads alert capture JSONs directly without importing AlertData
```

Once the libs PR merges + CI publishes each `[minor:...]`, these come out. Replace with version pins. The [[actuate-alarm-senders]] skip is intentional and documented inline.

## Phase completion map

| Arc | Phase | Status | Files |
|---|---|---|---|
| Inspect | 1 (diff) | ✅ shipped 2026-05-19/20 | AIT `config_diff.py`, `parser_subprocess.py`, `s3_settings.py` |
| Inspect | 2 (validate) | ✅ shipped 2026-05-20 | AIT `validators/` (9 invariants) |
| Inspect | 3 (audit-tier-emissions) | sketched | needs NRClient module; ~3-4h |
| Replay | 4 (IDP serializer) | ✅ shipped 2026-05-20 | libs `actuate-pipeline-objects` + `actuate-instrumentation` + `actuate-pipeline` |
| Replay | 5 (DumpReplayPuller) | ✅ shipped 2026-05-22 | libs `actuate-pullers/dump_replay/` |
| Replay | 6a (DumpLoader + inspect/diff) | ✅ shipped 2026-05-21 | AIT `dump_loader.py`, `replay.py`, `replay_cli/` |
| Replay | 6b (replay --step) | ✅ shipped 2026-05-21/22 | AIT `step_replay.py` |
| Replay | 7 (alert capture/replay) | ✅ shipped 2026-05-22 | libs `actuate-alarm-senders/shared_alert/` + AIT `replay_alert_cli/` |
| Replay | 8 (camera from_dump) | sketched; blocked on Plays B+C | vms-connector `camera/` (not yet touched) |
| Replay | 9 (site dump + crash hook) | sketched; perf-discipline-reworked | vms-connector `site_manager/` + `connector.py` |
| Replay | 10 (S3 sink + dumps UX) | sketched | terraform `ds-terraform-eks-v2/modules/test-data-bucket/` + AIT `dumps/` |
| Simulate | 11 (ait simulate) | ✅ shipped 2026-05-20 | libs factories/[[strategies]] + AIT `simulate/` |
| Sweep | 12 (ait sweep for QA) | sketched; blocked on Plays A+B | AIT `sweep/` (not yet started) |

## Test totals across the arc

| Package | Tests | Δ from arc start |
|---|---|---|
| `actuate-pipeline-objects` | 53 | +43 (27 Phase 4 + 22 factories + 4 Hypothesis) |
| `actuate-instrumentation` | 9 | +9 (Phase 4 data_dump sidecars) |
| `actuate-pipeline` | 15 | +2 (Phase 4 DataDumpLink regression + full-shape smoke) |
| `actuate-alarm-senders` | 56 | +20 (Phase 7 AlertData + Capturing + Replay) |
| `actuate-pullers` | 46 | +17 (Phase 5 DumpReplayPuller) |
| `actuate-integration-tools` | 107 | from zero |

**Σ new across the arc: ~91 tests.**

## KB syntheses (all the per-phase + cross-cutting docs)

### Per-phase (each is its own synthesis note)

- [[2026-05-19_ait-extensions-spec]] — parent for Phases 1-3
- [[2026-05-19_ait-phase-1-diff]] — Phase 1 (shipped)
- [[2026-05-19_ait-phase-2-validate]] — Phase 2 (shipped)
- [[2026-05-19_ait-phase-3-audit-tier-emissions]] — Phase 3 (sketched)
- [[2026-05-20_ait-brain-in-jar-spec]] — parent for Phases 4-10 + Phase 11 + perf-discipline rule
- [[2026-05-20_ait-phase-4-idp-serializer]] — Phase 4 (shipped)
- [[2026-05-20_ait-phase-5-dump-replay-puller]] — Phase 5 (shipped)
- [[2026-05-20_ait-phase-6-pipeline-replay]] — Phase 6a + 6b (shipped)
- [[2026-05-20_ait-phase-7-alert-capture-replay]] — Phase 7 (shipped; perf-discipline-updated)
- [[2026-05-20_ait-phase-8-camera-from-dump]] — Phase 8 (sketched; blocked on Plays B+C)
- [[2026-05-20_ait-phase-9-site-dump-crash-hook]] — Phase 9 (sketched; **reworked** post-perf-discipline)
- [[2026-05-20_ait-phase-10-s3-sink-review-ux]] — Phase 10 (sketched)
- [[2026-05-21_ait-phase-11-simulate]] — Phase 11 (shipped)
- [[2026-05-22_ait-phase-12-sweep]] — Phase 12 (sketched; QA-driven; blocked on Plays A+B)

### Cross-cutting

- [[2026-05-22_actuate-testing-toolkit-overview]] — **master synthesis** mapping all five tools + per-persona workflows
- [[2026-05-21_ait-validator-dovetail]] — six dovetail plays (A-F) between AIT and validator
- [[2026-05-21_ait-validator-integration-plan]] — **gating doc** for further AIT dev. Fault-line analysis + alignment decisions + bucket-safety constraints.
- [[2026-05-27_zack-coordination-brain-in-jar]] — Zack-bound coordination message (this session)

### Topic-level

- [[actuate-integration-tools]] — entity
- [[actuate-validator]] — entity (Zack's library survey)
- [[hypothesis/_summary|Hypothesis (property-based testing)]] — full reference for property-based testing as we use it
- [[2026-05-21_hypothesis-in-actuate]] — how we layer factories + [[strategies]]

### Memories

- [[project_actuate_instrumentation_intent]] — [[actuate-instrumentation]] was always meant to be the home for state-capture primitives
- [[feedback_library_version_field_ci_managed]] — never edit `version = ` field manually; CI bumps from tag
- [[feedback_library_no_dev_versions]] — strip `[no ci]` from squash bodies on library PRs

## Pending action items, prioritized

### P0 — clears the most blocks

1. **Push `feat/idp-serializer-brain-in-jar-phase-4` to `actuate-libraries` + open PR.** Then [[watch-entity|watch]] CI's Publish Stable run for each `[minor:...]` tag and confirm CodeArtifact gets the new versions. Refer to the squash-body discipline before merging.
2. **Send [[2026-05-27_zack-coordination-brain-in-jar]] to Zack** — picks up Plays A + B + C + D + the lib-home question. The doc is written to be shareable as-is (copy the body to Slack / email / Jira comment).
3. **Once libs publish, drop AIT's path-pins to version-pins** in `pyproject.toml`. The block to remove is noted inline.

### P1 — independent dev (any of these unblocks itself)

1. **Phase 8 (camera from_dump)** — start once Play B lands (validator's `MockDaoManager` + `MockImageCache` lifted to upstream libs' `testing/` subpackages). Until then, can be drafted using validator's existing mocks at their current location, with the import path expected to change.
2. **Phase 9 (site dump + crash hook)** — independent of validator coordination. Connector-side work in `vms-connector`. The KB synthesis is already perf-discipline-reworked (no polling watcher; signal-only triggers). ~3-4h.
3. **Phase 10 (S3 sink + AIT dumps UX)** — needs Terraform module + a real S3 bucket. The KB synthesis has the spec. Order it AFTER Phase 9 (Phase 9 writes; Phase 10 uploads).
4. **Phase 12 (ait sweep for QA)** — blocked on Plays A+B from the integration plan. Don't start until those land.

### P2 — opportunistic

- Investigate whether `actuate-integration-tools` should leave the local-only state for a real GitHub repo (`aegissystems/actuate-integration-tools`). Promotion criterion met.
- Consider whether validator's manifest schema should adopt the Phase 4 `to_dict` / `from_dict` convention for the AlertData fields it might capture in golden-set entries.
- The `actuate-instrumentation` README now has substantial content — worth a `kb-ingest` pass to extract any KB-worthy reference content from it.

## Resumption checklist (for the next session)

```bash
# 1. Re-orient
cd /home/mork/Documents/worklog/knowledgebase
less topics/personal-notes/notes/syntheses/2026-05-27_brain-in-jar-handoff.md

# 2. Repo states
cd /home/mork/work/actuate-libraries && git log --oneline -10 feat/idp-serializer-brain-in-jar-phase-4
cd /home/mork/work/actuate-integration-tools && git log --oneline -10

# 3. Test counts (smoke that things still work)
cd /home/mork/work/actuate-libraries/actuate-pipeline-objects && uv run --group dev python -m pytest tests/ -q
cd /home/mork/work/actuate-libraries/actuate-pullers && uv run python -m pytest tests/ -q
cd /home/mork/work/actuate-libraries/actuate-alarm-senders && uv run python -m pytest tests/ -q
cd /home/mork/work/actuate-integration-tools && uv run python -m pytest tests/ -q

# 4. Decide next phase from the Pending action items above
```

## Open questions worth re-asking the user

- **Push the libs PR yourself?** The 5-commit feature branch is squash-ready; the PR body wants a clear `[minor:actuate-pipeline-objects] [minor:actuate-instrumentation] [patch:actuate-pipeline] [minor:actuate-alarm-senders] [minor:actuate-pullers]` tag list in the squash subject. User has historically wanted to review library PRs personally before merging.
- **Promotion of actuate-integration-tools** to `aegissystems/actuate-integration-tools`? Decision criteria from the entity note are arguably met.
- **Phase 9 prioritization** — connector-side work is independent and would let us start collecting real production crash captures on internal test deployments. Worth bumping ahead of waiting on Zack coordination?

## Cross-references

- [[2026-05-22_actuate-testing-toolkit-overview]] — toolkit-wide map
- [[2026-05-21_ait-validator-integration-plan]] — gating doc for further dev
- [[2026-05-27_zack-coordination-brain-in-jar]] — coordination message for Zack
- [[mark-todos]] — workstream tracker (no §N for this arc yet; tracked entirely via KB)
