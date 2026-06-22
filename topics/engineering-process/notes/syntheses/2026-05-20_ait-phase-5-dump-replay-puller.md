---
title: "AIT Phase 5 — `DumpReplayPuller`"
type: synthesis
topic: engineering-process
tags: [tooling, actuate-integration-tools, ait, brain-in-jar, puller, actuate-pullers, replay, roadmap]
created: 2026-05-20
updated: 2026-05-20
author: mark
incoming:
  - topics/engineering-process/notes/entities/actuate-integration-tools.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-brain-in-jar-spec.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-4-idp-serializer.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-8-camera-from-dump.md
  - topics/engineering-process/notes/syntheses/2026-05-21_ait-phase-11-simulate.md
  - topics/personal-notes/notes/syntheses/2026-05-27_brain-in-jar-handoff.md
incoming_updated: 2026-05-27
---

# AIT Phase 5 — `DumpReplayPuller`

A puller that consumes a brain-in-jar dump archive and feeds the captured frames back into a downstream pipeline via the existing `BasePuller.push_frame` interface. Lives in `actuate-pullers` next to its siblings.

## Why this is Phase 5

`actuate-pullers` is the most-solved component for brain-in-jar. The package already ships four pullers that are 90% of what we need:

- `S3FramePuller` — reads frames from an S3 prefix, `cv2.imread` loop.
- `BufferFramePuller` — reads from a named pipe.
- `JpgFrameQueuePuller` — driven by enqueued JPEG bytes; closest existing analogue.
- `DummyPuller` — canned healthcheck packets, no real source.

All four push frames through `BasePuller.push_frame(frame, timestamp, frame_jpg_bytes)`. That's the universal feed point. A "DumpReplayPuller" is a thin wrapper: walk the dump's frames in timestamp order, call `push_frame` for each, optionally honour timestamp gaps with `time.sleep(delta)` (or jump as fast as possible in deterministic-test mode).

## Why it can land in parallel with Phase 4

`DumpReplayPuller` only needs the *frames* in the dump (the `.jpg` sidecars), not the IDP JSONs. So the dump format minimum-viable surface for Phase 5 is just "a directory of timestamped JPEGs" — which we can write today with a 10-line helper, well before Phase 4 lands the full IDP serializer.

This lets work parallelize. Phase 4 owner builds the keystone; Phase 5 owner can land the puller against a synthetic dump dir made from any existing `S3FramePuller` test fixture. They merge cleanly when Phase 4 standardizes the dump format.

## Design

### Two replay modes

```bash
ait replay-puller <dump_path> --mode realtime   # honour timestamp gaps
ait replay-puller <dump_path> --mode fast       # push as fast as downstream consumes
```

`realtime` mimics the original wallclock cadence (useful for soak / load testing replays). `fast` is the deterministic mode for unit tests.

### Configuration

The puller takes a config like:

```python
DumpReplayPuller(
    dump_path=Path("/tmp/dump-2026-05-20.zip"),
    mode="fast",                      # or "realtime"
    loop=False,                       # repeat the dump indefinitely
    speed_multiplier=1.0,             # 2.0 = 2x realtime
    on_exhausted="stop",              # or "raise" or "loop"
)
```

Unzips the archive to a temp dir (or reads in-place if already extracted). Discovers frames via the manifest if present, falls back to globbing `*.frame.jpg` if not (which is the "synthetic dump dir" mode for parallel landing).

### Integration with `BasePuller`

Honours every contract `BasePuller` enforces — same `start`/`stop`/`is_alive`/`push_frame` semantics, same threading model. The downstream pipeline shouldn't know it's getting replayed frames.

Exception: there's no live camera to disconnect from, so SIGTERM cleanup is a no-op beyond closing the temp dir.

## TODOs (Phase 5)

### 5A — Synthetic dump format (works before Phase 4)

- [ ] Define the minimum-viable dump layout the puller will consume: `dump_path/*.frame.jpg` + optional `dump_path/manifest.json`.
- [ ] Add a tiny helper `actuate_pullers.testing.make_synthetic_dump(source_pattern, output_dir)` that turns a directory of arbitrary JPEGs into a brain-in-jar-compatible dump dir. Useful for tests AND for hand-crafting dumps from misc sources.
- [ ] Test against an existing `S3FramePuller` test fixture (it already has a directory of JPEGs to read).

### 5B — `DumpReplayPuller` core

- [ ] Create `actuate_pullers/dump_replay/dump_replay_puller.py`.
- [ ] Inherit from `BasePuller`. Implement `run()` to walk frames + call `push_frame`.
- [ ] Support both `realtime` and `fast` modes; the timing logic goes in a tiny helper that returns `0` for fast, `delta_seconds` for realtime.
- [ ] Support `loop` mode for soak testing.
- [ ] Support `speed_multiplier` for accelerated realtime.
- [ ] Handle archive-vs-directory transparently (unzip-to-temp on archive paths).
- [ ] Unit tests: synthetic dump in fast mode; realtime mode within tolerance; loop mode; exhaustion behaviour.

### 5C — `ait replay-puller` CLI

- [ ] Add `ait replay-puller <dump_path>` subcommand in `actuate-integration-tools/cli.py`.
- [ ] Wire `--mode`, `--loop`, `--speed`, `--on-exhausted` flags.
- [ ] Default behaviour: emit pushed-frame metadata to stdout (`frame_id ts size`) so the CLI is useful even without a downstream consumer attached.
- [ ] Add a `--consumer` flag that takes a Python entrypoint string and instantiates a downstream component (defer this to Phase 6 — it's cleaner once `MockStepRunner` integrates).

### 5D — Smoke test against a real captured dump

- [ ] After Phase 4 lands, capture a dump from a local connector run.
- [ ] Replay it via `ait replay-puller`; confirm frames push through in order with correct metadata.

### 5E — Documentation

- [ ] Add a "DumpReplayPuller" section to `actuate-pullers/README.md`.
- [ ] Update `actuate-integration-tools/README.md` with the `ait replay-puller` example.
- [ ] Bump `actuate-pullers` with `[minor:actuate-pullers]`.

## Estimate

~1–2h. The pattern is exactly `JpgFrameQueuePuller` with a different feed source.

## Risk

Low. The puller is a thin wrapper over already-proven `BasePuller` mechanics. The dump-format coupling is the only real gotcha — explicit fallback to "directory of JPEGs" lets Phase 5 land before Phase 4 is done.

## Cross-references

- [[2026-05-20_ait-brain-in-jar-spec]] — parent
- [[2026-05-20_ait-phase-4-idp-serializer]] — Phase 4 (lands in parallel)
- [[2026-05-20_ait-phase-6-pipeline-replay]] — Phase 6 (downstream consumer)
