---
title: "AIT Phase 6 — `ait replay` CLI + pipeline-step replay"
type: synthesis
topic: engineering-process
tags: [tooling, actuate-integration-tools, ait, brain-in-jar, pipeline, mock-step-runner, replay, roadmap]
created: 2026-05-20
updated: 2026-05-20
author: mark
incoming:
  - topics/engineering-process/notes/entities/actuate-integration-tools.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-brain-in-jar-spec.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-10-s3-sink-review-ux.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-4-idp-serializer.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-5-dump-replay-puller.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-7-alert-capture-replay.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-8-camera-from-dump.md
  - topics/engineering-process/notes/syntheses/2026-05-21_ait-phase-11-simulate.md
  - topics/personal-notes/notes/syntheses/2026-05-27_brain-in-jar-handoff.md
incoming_updated: 2026-05-27
---

# AIT Phase 6 — `ait replay` CLI + pipeline-step replay

A CLI that drives any single pipeline step against a captured `ImageDataPacket`, plus the fixture-loader plumbing that makes brain-in-jar dumps queryable from anywhere.

## Why this is Phase 6

The pipeline-replay infrastructure is **already 80% built** in `actuate-pipeline`:

- `actuate-libraries/actuate-pipeline/src/actuate_pipeline/steps/shared/mock_step_runner.py::MockStepRunner` — runs a single step against an arbitrary IDP and returns the result. `set_step(step)`, `set_prev_result(idp)`, `run()`.
- `mock_pipeline_runner.py` — same idea for a full chain.
- `links/mock_link.py` — terminates the chain so a step can be exercised without a real downstream.
- `steps/shared/dummy_step.py` — no-op step for splicing.

What's missing is **the wiring between captured dumps and these runners**, plus a CLI to drive it. The runners take an IDP object; brain-in-jar dumps store IDPs as serialized state. Phase 4 makes them round-trippable. Phase 6 connects the two.

## Design

### CLI surface

```bash
# Run a single named step against the IDP at index N in the dump
ait replay <dump_path> --step pre_inference --idp 0

# Run a chain of steps
ait replay <dump_path> --pipeline pre_inference,inference,post_inference --idp 0

# Diff the captured IDP against the replayed one (was the captured one mid-stage?)
ait replay <dump_path> --step pre_inference --idp 0 --diff

# Iterate over every IDP in the dump
ait replay <dump_path> --step post_inference --all --diff
```

`--diff` is the most-valuable mode for crash investigation: "given the IDP I captured at the moment of the crash, what does step X produce?". If the captured IDP was *itself* the output of step X, the replay should reproduce it. If they diverge, that's a regression signal.

### Fixture-loader plumbing

A new module `actuate_integration_tools.dump_loader`:

```python
class DumpLoader:
    def __init__(self, dump_path: Path | str): ...
    def list_idps(self) -> list[str]: ...                          # all IDP indices
    def get_idp(self, index: int | str) -> ImageDataPacket: ...    # via from_dict
    def get_alert(self, index: int | str) -> AlertData: ...        # for Phase 7
    def get_camera_state(self, camera_name: str) -> dict: ...      # for Phase 8
    @property
    def manifest(self) -> dict: ...                                 # dump-level metadata
```

`DumpLoader` is the **single point of access** for everything in a dump. Other phases (7, 8) reuse it for their own subcommands.

### Step name resolution

A connector's pipeline is configured per-deployment — step names like `pre_inference` aren't universal. The dump's manifest must include the *exact* pipeline configuration that was running when the dump was captured, including step class names and parameters.

`ait replay --list-steps <dump_path>` reads the manifest and shows what's available. `--step <name>` matches against that list. If the step isn't in the dump's pipeline, the CLI errors with a hint.

### Pipeline reconstruction

For multi-step replay, `MockPipelineRunner` (or its successor) needs to materialize each step from the manifest's class name + params. This means **step classes must be import-discoverable** from `actuate-pipeline`. Most are already, but new steps added between dump capture and replay may not match — log a warning, fall back to "skip this step" with a placeholder result.

## TODOs (Phase 6)

### 6A — `DumpLoader` module

- [ ] Create `actuate_integration_tools/dump_loader.py`.
- [ ] Implement `__init__`, `list_idps`, `get_idp`, `manifest` properties.
- [ ] Handle archive-vs-directory transparently (same logic as Phase 5's `DumpReplayPuller`; consider factoring shared helper into `actuate-instrumentation`).
- [ ] Unit tests against a hand-built synthetic dump (a tiny dump dir checked into `tests/fixtures/`).

### 6B — `ait replay` subcommand

- [ ] Add `ait replay <dump_path>` to `cli.py`.
- [ ] Flags: `--step`, `--pipeline`, `--idp`, `--all`, `--diff`, `--list-steps`, `--json`, `--verbose`.
- [ ] Wire to `MockStepRunner` / `MockPipelineRunner` via the dump manifest.
- [ ] Render the result IDP via `rich` (consistent with the rest of `ait`).

### 6C — IDP-vs-IDP diff renderer

- [ ] Implement a structural diff between two IDPs (similar pattern to Phase 1's `config_diff.py`, but for IDPs).
- [ ] Identify the "interesting" fields per step — for `pre_inference` the diff cares about resize parameters and ROI; for `inference` it's detection results; etc.
- [ ] Render as a side-by-side `rich` table.

### 6D — Step-name discovery from manifest

- [ ] Define the manifest's pipeline-spec schema (step class + ctor kwargs + ordinal).
- [ ] Phase 4 must populate this schema as part of the dump. Document the requirement in `2026-05-20_idp-serialization-contract.md` (the Phase 4 doc).
- [ ] CLI `--list-steps` reads + prints; `--step <name>` validates against the list.

### 6E — Integration test against a real dump

- [ ] After Phases 4 + 5 land, capture a dump from a local connector run.
- [ ] Replay each step in the captured pipeline; assert each step's replayed output matches the captured next-step input (within a tolerance for stochastic steps).

### 6F — Documentation

- [ ] Add an "ait replay" section to `actuate-integration-tools/README.md`.
- [ ] Add a "Brain-in-jar" section to the AIT entity note showing how to inspect a captured dump.
- [ ] Cookbook a couple of common workflows: "I think step X is wrong on a specific IDP — how do I check?", "I want to test my new step against real production IDPs — how do I drive it?".

## Estimate

~2–3h. Most of the logic is wiring + a diff renderer; the runtime is already provided by `MockStepRunner`.

## Risk

The biggest unknown is **how stable step class names + signatures are between dump capture and replay**. If a step is renamed mid-investigation, the replay breaks. Mitigation: dumps record `actuate-pipeline` version explicitly, and replay surfaces a "library drift" warning if the running version differs.

## Cross-references

- [[2026-05-20_ait-brain-in-jar-spec]] — parent
- [[2026-05-20_ait-phase-4-idp-serializer]] — required dependency
- [[2026-05-20_ait-phase-7-alert-capture-replay]] — Phase 7 reuses `DumpLoader`
- [[2026-05-20_ait-phase-8-camera-from-dump]] — Phase 8 reuses `DumpLoader`
