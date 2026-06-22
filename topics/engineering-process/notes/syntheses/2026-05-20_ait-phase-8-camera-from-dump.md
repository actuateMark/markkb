---
title: "AIT Phase 8 — camera `from_dump` constructor"
type: synthesis
topic: engineering-process
tags: [tooling, actuate-integration-tools, ait, brain-in-jar, camera, base-camera, vms-connector, replay, roadmap]
created: 2026-05-20
updated: 2026-05-20
author: mark
incoming:
  - topics/engineering-process/notes/entities/actuate-integration-tools.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-brain-in-jar-spec.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-6-pipeline-replay.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-9-site-dump-crash-hook.md
  - topics/engineering-process/notes/syntheses/2026-05-21_ait-validator-dovetail.md
  - topics/engineering-process/notes/syntheses/2026-05-21_ait-validator-integration-plan.md
  - topics/personal-notes/notes/syntheses/2026-05-27_brain-in-jar-handoff.md
incoming_updated: 2026-05-27
---

# AIT Phase 8 — camera `from_dump` constructor

The hardest brain-in-jar phase. Camera objects in `vms-connector` are tightly coupled to live threads, queues, observer state, and puller handles. There's no stateless constructor today. Phase 8 introduces one, with an ADR-level decision on what counts as "camera state" vs "camera machinery".

## Why this is Phase 8

Cameras are the glue between everything else. Phase 5 gives us a fake puller; Phase 6 gives us replayable pipeline steps; Phase 7 gives us a capturing sender. But none of it is *end-to-end* until we can reconstitute the camera that wires them together. Without `from_dump`, brain-in-jar replay is "run individual steps and squint" — useful but not a full reproduction.

This phase requires Phases 4–7 to land first because the camera dump pulls in IDPs (4), puller state (5), pipeline state (6), and alert sender captures (7).

## The ADR: what counts as "camera state"

State (must dump, must reconstitute):

- Camera config (`name`, `admin_camera_id`, `is_ptz`, `device_id`, stream URLs, model assignments, [[ignore-zones|ignore zones]])
- Observer accumulators (per-product window state, motion accumulators, frame counters)
- Sliding-window detection state (per-product window contents, last-fire timestamps, deferred-alert queue)
- Ignore-zone state (current zone polygons, time-windowed overrides)
- Motion detection state (last motion timestamp, current motion intensity, background model snapshot)
- Pipeline state attached to the camera (cached pre-process parameters, last frame ID, etc.)
- Recent IDP history (last 3–5 frames worth of IDP state, for context around the crash)
- Pending alerts that hadn't fired yet at the time of dump

Machinery (do NOT dump, reconstitute from scratch on `from_dump`):

- Thread references (`threading.Thread` instances, locks, condition variables)
- Queue handles (`queue.Queue`, `multiprocessing.Queue`)
- Live puller instance (replaced by `DumpReplayPuller` on replay)
- Socket / HTTP client handles
- [[inference-pool|Inference pool]] handles
- Process handles (`subprocess.Popen`, `multiprocessing.Process`)

The state list is **required to be complete** — those are the fields whose absence makes replay useless because the actual *signal* lives there. Machinery is re-created freely.

## Design

### `BaseCamera.from_dump(...)` constructor

A class method on `BaseCamera` that builds a non-threaded shell of a camera, suitable for replay:

```python
camera = BaseCamera.from_dump(
    dump_path=Path("..."),
    camera_name="Axis office camera",
    config_overrides=None,                # optional — override any state field
    puller_factory=DumpReplayPuller,      # injected puller class for replay
    sender_factory=ReplaySender,          # injected sender class for replay
    pipeline_factory=ReplayPipeline,      # uses MockPipelineRunner under the hood
)
```

Reads the camera's serialized state from the dump, instantiates the integration-specific subclass ([[rtsp-deep-dive|RTSP]] / Milestone / Avigilon / etc.), injects the replay-mode puller/sender/pipeline, and returns a camera that can be `start()`ed and will process the captured frame stream end-to-end.

Each integration subclass overrides `_from_dump_hook(self, state)` to handle its quirks (e.g. `AvigilonCamera` may need to skip its login flow when reconstituted from a dump).

### Camera state serialization

Each camera knows how to serialize its own state via a new method:

```python
class BaseCamera:
    def to_dump_dict(self) -> dict: ...    # returns serializable state
    @classmethod
    def from_dump_dict(cls, data: dict, ...) -> "BaseCamera": ...
```

Subclass overrides extend the base dict with integration-specific state (e.g. `AvigilonCamera.to_dump_dict()` adds the NVR session token, etc.).

The base `BaseCamera.to_dump_dict()` walks the state list above; the override convention is "call super, then add my fields."

### End-to-end replay fixture

Given a brain-in-jar dump, the full replay flow is:

```python
camera = BaseCamera.from_dump(dump_path, camera_name="Cam 1")
camera.start()
# DumpReplayPuller feeds frames in fast mode → ReplayPipeline runs each step
# → captured detection results → ReplaySender records what would-be-sent alerts look like
camera.join()  # exits when the dump's frames are exhausted

# Inspect results
result = camera.replay_result()  # captured outputs from the run
```

The fixture has tight integration with Phase 9 (the site-level dump) — a site-level dump produces one of these per camera in the patrol.

### Where the code lives

Camera state machinery lives in `vms-connector` (`camera/shared/base_camera.py` + integration subclasses), not in `actuate-libraries`. `from_dump` is a connector-side change.

`DumpReplayPuller` factory injection comes from `actuate-pullers`; `ReplaySender` from `actuate-alarm-senders`; `ReplayPipeline` is a small wrapper in `actuate-integration-tools` that drives `MockPipelineRunner` against captured IDPs.

## TODOs (Phase 8)

### 8A — ADR: camera state vs machinery

- [ ] Write `2026-05-20_adr-camera-state-vs-machinery.md` formalizing the state / machinery decision.
- [ ] List every field on `BaseCamera`, `BaseStreamCamera`, and the most-common integration subclasses ([[rtsp-deep-dive|RTSP]], Milestone, Avigilon, ExacQ). Classify each.
- [ ] Identify "surprising" fields that don't fit cleanly (e.g. `_last_alert_payload` — is it state or machinery?). Document the call + rationale.
- [ ] Cross-link from connector CLAUDE.md "Review Heuristics" section.

### 8B — `BaseCamera.to_dump_dict` / `from_dump_dict`

- [ ] Implement on `BaseCamera` in `camera/shared/base_camera.py`.
- [ ] Walk every state field per the ADR; populate the dict.
- [ ] `from_dump_dict` reconstitutes; thread refs / queues left as `None` (created on first `start()` call).
- [ ] Add the override extension point for subclasses.

### 8C — Per-integration overrides

- [ ] Walk each integration subclass ([[rtsp-deep-dive|rtsp]], milestone, avigilon, exacq, video_insight, kvs, star4live, salient, etc.).
- [ ] Identify integration-specific state vs machinery.
- [ ] Add `_to_dump_dict_hook` / `_from_dump_dict_hook` overrides where needed.
- [ ] At minimum, [[rtsp-deep-dive|RTSP]], Avigilon, and VCH must work — they're the most-deployed.

### 8D — Factory injection on `from_dump`

- [ ] Accept `puller_factory`, `sender_factory`, `pipeline_factory` kwargs.
- [ ] Default to `DumpReplayPuller` / `ReplaySender(transport="mock")` / `ReplayPipeline` if not provided.
- [ ] Validate factories satisfy the expected interface; surface mismatches with a helpful error.

### 8E — End-to-end fixture test

- [ ] Capture a brain-in-jar dump on a local connector run.
- [ ] Build the end-to-end replay fixture: `BaseCamera.from_dump → start → join → result`.
- [ ] Assert the replay reproduces the captured outputs (frames processed, detections fired, alerts emitted match the originals).
- [ ] Add as a regression test in `vms-connector/test_vms/test_brain_in_jar.py`.

### 8F — Documentation

- [ ] Add a "Brain-in-jar camera replay" section to the connector CLAUDE.md.
- [ ] Cookbook a couple of common debug workflows: "I want to see what step X did on this captured frame", "I want to test my new ignore-zone logic against real production frames".

## Estimate

~4–6h. ADR is ~1h; base `to_dump_dict`/`from_dump_dict` ~1h; per-integration overrides ~2h (most of the time on the trickier integrations like Avigilon); fixture + docs ~1h.

## Risk

The biggest unknown is **integration-specific quirks**. Avigilon's NVR session token, Milestone's event subscription state, [[rtsp-deep-dive|RTSP]]'s reconnect state machine — each of these has hidden state that doesn't fit cleanly into "config" or "observer accumulator". Mitigation: 8C is gated on per-integration testing; if an integration proves too quirky, mark it deferred and ship the rest.

A secondary risk: **`from_dump` could grow into a parallel construction path that diverges from the live factory path over time.** Mitigation: a regression test that compares `from_dump(dump)` against `factory.build_camera(dump_config)` for the live-construction-equivalent fields. Differences are bugs in one direction or the other.

## Cross-references

- [[2026-05-20_ait-brain-in-jar-spec]] — parent
- [[2026-05-20_ait-phase-4-idp-serializer]] — Phase 4 (required)
- [[2026-05-20_ait-phase-5-dump-replay-puller]] — Phase 5 (puller injection)
- [[2026-05-20_ait-phase-6-pipeline-replay]] — Phase 6 (pipeline injection)
- [[2026-05-20_ait-phase-7-alert-capture-replay]] — Phase 7 (sender injection)
- [[2026-05-20_ait-phase-9-site-dump-crash-hook]] — Phase 9 builds on this for site-level state
- [[actuate-validator]] — has `MockDaoManager` + `MockImageCache` we can adopt rather than reinvent ([[2026-05-21_ait-validator-dovetail]] Play B)
