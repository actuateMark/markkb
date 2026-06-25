---
title: "AIT brain-in-jar — spec & phase map (Phases 4–10)"
type: synthesis
topic: engineering-process
tags: [tooling, actuate-integration-tools, ait, brain-in-jar, crash-dump, state-capture, replay, debugging, roadmap]
created: 2026-05-20
updated: 2026-05-20
author: mark
outgoing:
  - topics/engineering-process/notes/entities/actuate-integration-tools.md
  - topics/engineering-process/notes/syntheses/2026-05-19_ait-extensions-spec.md
incoming:
  - home/offboarding/2026-06-23_local-repo-audit.md
  - topics/engineering-process/notes/entities/actuate-integration-tools.md
  - topics/engineering-process/notes/entities/actuate-validator.md
  - topics/engineering-process/notes/syntheses/2026-05-19_ait-phase-1-diff.md
  - topics/engineering-process/notes/syntheses/2026-05-19_ait-phase-2-validate.md
  - topics/engineering-process/notes/syntheses/2026-05-19_ait-phase-3-audit-tier-emissions.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-10-s3-sink-review-ux.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-4-idp-serializer.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-5-dump-replay-puller.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-6-pipeline-replay.md
incoming_updated: 2026-06-25
---

# AIT brain-in-jar — spec & phase map (Phases 4–10)

The second major arc of [[actuate-integration-tools|`ait`]] extensions, distinct from Phase 1–3 (which were about *inspecting* a live deployment's config / behaviour). Phases 4–10 are about **capturing the in-memory state of a running connector pod, persisting it durably, and re-running pipeline components against that state in isolation** — the "brain-in-jar" vision.

## The vision in one paragraph

When a connector pod crashes or hits a critical failure in production, it should dump the in-memory state of major components (camera objects, pipeline steps, alert sender, puller buffers, site manager) to S3. The next morning, a developer pulls the dump locally via `ait dumps fetch <deployment_id> <timestamp>`, then replays individual components against the captured state (`ait replay <dump> --step pre_inference`, `ait replay-alert <dump>`, etc.). The same machinery doubles as a unit-test substrate — any pipeline step, sender, or camera component can be exercised in isolation against a real captured frame stream.

The win: today, post-mortems on connector crashes rely on log scraping + speculation. With brain-in-jar, the post-mortem is *reproducing the crash deterministically on the developer's laptop from the captured state*.

## Why now (rather than later)

Three converging pressures:

1. **Crash post-mortem is currently lossy.** Logs tell you *what happened* but not *what the runtime state was* — what the IDP looked like when the pipeline step blew up, which frames were in flight, which alerts had buffered. A captured snapshot closes that gap.
2. **Pipeline step testing is currently coarse.** Each step has unit tests but they use synthetic IDPs that don't match the real input distribution. Real captured IDPs would surface edge cases that synthetic data misses.
3. **The infrastructure is half-built already.** `actuate-instrumentation`'s `data_dump`/`data_load` was *intended* for exactly this (`project_actuate_instrumentation_intent.md`), and the pullers + pipeline mock-runners already expose 80% of the replay surface. The gap is mostly **the `ImageDataPacket` serializer** (which doesn't exist today) plus the crash-time wiring. See the inventory: [[2026-05-20_brain-in-jar-existing-infra-inventory]] (research done 2026-05-20).

## Two complementary arcs

**Replay arc (Phases 4–10)** — capture real production state, replay components against it. Best for post-mortems and deterministic reproduction of "this specific failure".

**Simulate arc (Phase 11)** — synthetic IDPs + Hypothesis-driven fuzzing. Best for pre-merge / dev iteration / "I want to test a case I haven't captured yet." Shares Phase 4's serialization keystone but otherwise independent. See [[2026-05-21_ait-phase-11-simulate]].

The two arcs share the dump format and feed each other: simulator output is a valid brain-in-jar dump, so `DumpReplayPuller` (Phase 5) can drive synthetic dumps the same way it drives captured ones.

## Per-component map

What "brain-in-jar" means for each major component, what already exists, and what's missing:

| Component | Existing infrastructure | Gap | Phase |
|---|---|---|---|
| **`ImageDataPacket`** (the pipeline currency) | `DataDumpLink` exists in `actuate-pipeline` but calls `result.json()` — which the IDP doesn't implement; the link is aspirational/broken today | `to_dict`/`from_dict` + binary side-channel for numpy frames | **Phase 4** (keystone) |
| **Pipeline steps** | `MockStepRunner` + `MockPipelineRunner` in `actuate-pipeline` already do "run one step against an arbitrary IDP" | Useless until IDP serializes; trivial wiring after that | **Phase 6** |
| **Puller** | `JpgFrameQueuePuller`, `S3FramePuller`, `DummyPuller`, `BufferFramePuller`; `BasePuller.push_frame` is the universal feed point | Thin "DumpReplayPuller" wrapping `push_frame` from a dump archive | **Phase 5** |
| **Alert sender** | `AlertData.to_json()` exists sender-side in `actuate-alarm-senders` | `AlertData.from_json`; CapturingAlertSender (record); ReplaySender (drive real code path against captured payload) | **Phase 7** |
| **Camera objects** | Nothing — tightly coupled to factory + live threads/queues; no stateless constructor | `BaseCamera.from_dump(...)` + decision on what counts as camera state | **Phase 8** |
| **Site manager** | Nothing — no dump hooks, no crash trap, no `faulthandler` registration | `AnalyticsSiteManager.dump_state()` + signal wiring (`faulthandler.register`, SIGABRT/SIGSEGV, atexit) | **Phase 9** |
| **Crash → S3 sink** | Nothing | Atomic local write + background uploader to `s3://actuate-crash-dumps/<deployment_id>/<timestamp>/` | **Phase 10** |
| **Centralized helper** | `actuate_instrumentation.data_dump` (~20 lines, JSON only, lib v0.0.3 stub) | The intended home — needs to grow binary attachments, S3 sink, crash trigger | **cross-cuts Phases 4 + 9 + 10** |

## Sequencing

The dependency DAG:

```
                  Phase 4 (IDP serializer)        [keystone]
                       │
       ┌───────────────┼───────────────┬───────────────┐
       ▼               ▼               ▼               ▼
   Phase 5         Phase 6         Phase 7         Phase 11
   (puller)        (pipeline)      (alert sender)  (simulate — synthetic IDPs)
       │               │               │
       └───────────────┼───────────────┘
                       ▼
                   Phase 8 (camera from_dump)
                       │
                       ▼
                   Phase 9 (site dump + crash hook)
                       │
                       ▼
                   Phase 10 (S3 sink + ait dumps UX)
```

Phase 4 unblocks everything. Phases 5–7 can land in parallel. Phase 8 needs all of 4–7. Phases 9–10 close the production-crash loop.

## Cross-cutting concerns

### Dump format: directory-during-write, zip-on-finalize

Decided 2026-05-20 with Mark.

- **During write** (especially crash-time): write each piece (JSON manifest, per-frame `.jpg` / `.npy`, IDP-state JSONs, alert payloads) to a flat directory `/tmp/connector-dumps/<run_id>/`. Atomic per-file. If the process dies mid-write, whatever made it to disk is durable and inspectable.
- **On finalize** (normal end-of-run *or* post-crash via a recovery sweep): zip the directory into `<run_id>.zip` and remove the source dir. Upload the zip to S3.

A zip is *nicer* for transport and storage. A directory is *safer* during a crash. Doing both gets the best of both — the only complexity is the recovery sweep that zips orphan directories on next pod start. That sweep lives next to the crash hook in Phase 9.

### What counts as "camera state" (Phase 8 ADR)

Decided in spirit 2026-05-20: **observer accumulators, sliding-window state, ignore-zone state, motion detection state.** All worth dumping. **Thread refs, queues, socket handles, live puller handle** are *not* state — they're machinery, re-created on `from_dump`. Phase 8 nails this down formally.

The required-to-dump list is non-negotiable because those are the fields whose absence renders a replay useless — they're where the actual *signal* lives.

### Per-pod dump cap

A pod crash-looping shouldn't blow the S3 bucket. Cap: **3 most recent dumps per pod** kept locally; subsequent crashes overwrite the oldest. The upload-to-S3 path also has a per-deployment rate limit so a flapping pod doesn't drown the bucket.

If a pod is in a crash loop, it's almost always the same root cause — capturing 3 representative dumps is plenty for triage.

### TTL: weekend-survival, then Lambda-compact

S3 lifecycle policy on `actuate-crash-dumps`:

- **Raw dumps**: 3 days TTL. Long enough for Monday-morning review of a Friday-night crash; not long enough for cumulative storage to matter.
- **Compaction Lambda**: triggered on object create. Reads the dump zip, extracts a *summary* (logs, alert payloads, key IDP metadata, NO frames), writes the summary to a sibling key `actuate-crash-dump-summaries/<deployment_id>/<timestamp>.json` with 90-day TTL.

The summary is the durable record. The raw dump is the "I need it now" forensic asset. If we never need the full dump within 3 days, the summary still tells us the crash happened, what the failure mode was, and which deployment.

### Dump size

Target: **<5 MB per dump** under normal conditions. Stretch: **<1 MB** if we serialize only deltas from the last known-good IDP. Hard cap: **50 MB**, refuse to write past that.

Optimizations:
- Frames as JPEG (already what the puller emits), not raw numpy.
- One representative frame per camera, not every in-flight frame.
- IDPs serialized as deltas from the previous one (last 3–5 IDPs only).
- Skip per-camera per-frame data — keep aggregate counters only.
- ZIP compression at zip-finalize time.

If the realistic size lands above this, the spec gets revisited.

### Perf discipline — 1:1 or off-by-default

**Decided 2026-05-22 with Mark:** every brain-in-jar feature must be **1:1 with the off-baseline** when not opt-in, or **off by default** with explicit opt-in (env var). No exceptions for "trivial" overhead — even small CPU / memory taxes compound across 100+ pods and matter at the connector's scale.

What this means concretely:

- **No polling threads.** Triggers are signal-based (`faulthandler`, `SIGUSR1`, `atexit`) or exception-handler-based (`try/except` in connector.py). Polling = continuous CPU = forbidden at steady state.
- **Env-var gated wrappers** (e.g. `CapturingAlertSender`) **short-circuit at init**, not per call. Reading the env var once at start = free at steady state. Re-checking it per send = NOT 1:1.
- **No extra imports at module load** when the master switch is off. Imports cost startup time + memory. Lazy-import behind the master-switch check.
- **No file-system access** when the master switch is off. Even an `os.path.exists()` on a `.flag` file is forbidden — kernel syscall overhead is the wrong direction.
- **Production roll-out**: Actuate-internal test deployments first, NOT customer pods. Manual flip when investigating; never default-on.

The cost of the on-path mode (capture / dump / send) is acceptable when explicitly opted in — that's why it's opt-in. The cost of the off-path mode is **exactly zero**.

This rule is referenced from every phase's "Configuration" section. When designing a new phase, the first question is "what's the steady-state cost when off?" and the only acceptable answer is "zero."

### PII

Frames *are* PII (customer scenes). The connector already stores frames in other S3 buckets (VCH frame uploads, detection event clips), so brain-in-jar dumps don't introduce a new PII surface — they reuse the existing exposure class.

That said: **dumps live in a dedicated bucket with tighter RBAC than the rest of the stack.** Lambda compaction strips frames from the long-lived summary. Dump bucket access scoped to engineering only, not operations. We lean toward limiting PII where it costs us nothing, accept it where it's required to make replay useful (i.e. the frames themselves).

Per-site opt-out is a v2 concern if a customer requests it.

## Estimate

- Phase 4: ~3–4h (IDP serializer + binary side-channel + DataDumpLink fix + tests)
- Phase 5: ~1–2h (thin puller wrapper + tests)
- Phase 6: ~2–3h (CLI + MockStepRunner integration + fixture loader)
- Phase 7: ~3h (from_json + capture sender + replay sender)
- Phase 8: ~4–6h (camera ADR + from_dump + e2e fixture)
- Phase 9: ~4–6h (site dump_state + crash wiring + recovery sweep)
- Phase 10: ~3–5h (S3 sink + Lambda compaction + ait dumps UX)

Total: ~20–30h to land the full arc. Realistically split across 3–4 working days, not contiguous — each phase is self-contained and benefits from soak before the next.

## What this is NOT

- **Not** an in-pod debugger. We don't ship `pdb` to prod; we ship one-shot crash snapshots.
- **Not** a full execution-replay. We capture *state*, not the instruction stream. Replay re-runs the *code* against the captured state, which may diverge if the code has changed since the dump.
- **Not** a perf profiling tool. `/dashboard-check` + [[new-relic|New Relic]] cover that.
- **Not** a substitute for unit tests. Brain-in-jar fixtures *augment* the synthetic-input test suite; they don't replace it.

## Cross-references

- [[actuate-integration-tools]] — entity
- [[2026-05-19_ait-extensions-spec]] — Phase 1–3 parent spec
- [[2026-05-20_ait-phase-4-idp-serializer]] — Phase 4 detail (keystone)
- [[2026-05-20_ait-phase-5-dump-replay-puller]] — Phase 5
- [[2026-05-20_ait-phase-6-pipeline-replay]] — Phase 6
- [[2026-05-20_ait-phase-7-alert-capture-replay]] — Phase 7
- [[2026-05-20_ait-phase-8-camera-from-dump]] — Phase 8
- [[2026-05-20_ait-phase-9-site-dump-crash-hook]] — Phase 9
- [[2026-05-20_ait-phase-10-s3-sink-review-ux]] — Phase 10
- [[2026-05-21_ait-phase-11-simulate]] — Phase 11 (simulate arc, independent of replay arc)
- [[project_actuate_instrumentation_intent]] — memory pointing at the intended home
