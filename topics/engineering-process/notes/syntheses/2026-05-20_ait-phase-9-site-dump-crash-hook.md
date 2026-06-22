---
title: "AIT Phase 9 — site manager dump + crash hook"
type: synthesis
topic: engineering-process
tags: [tooling, actuate-integration-tools, ait, brain-in-jar, site-manager, crash-handler, faulthandler, vms-connector, roadmap]
created: 2026-05-20
updated: 2026-05-20
author: mark
incoming:
  - topics/engineering-process/notes/entities/actuate-integration-tools.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-brain-in-jar-spec.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-10-s3-sink-review-ux.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-7-alert-capture-replay.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-8-camera-from-dump.md
  - topics/personal-notes/notes/syntheses/2026-05-27_brain-in-jar-handoff.md
incoming_updated: 2026-05-27
---

# AIT Phase 9 — site manager dump + crash hook

Closes the production-side capture loop. The connector dumps its full in-memory state to local disk on a crash or critical failure, *before* the pod terminates. Phase 10 then ships the dump to S3.

## Why this is Phase 9

Phases 4–8 give us the *ability* to capture and replay everything. Phase 9 is the *production trigger* — the thing that actually fires the dump when something goes wrong, while the pod is still alive enough to write to disk.

Without this, brain-in-jar is a development-only tool. With this, it's a production observability primitive.

## Design

### `AnalyticsSiteManager.dump_state()`

A new top-level method on the site manager that walks the full site state and writes a brain-in-jar dump:

```python
def dump_state(self, reason: str = "manual", dump_dir: Path | None = None) -> Path:
    """Walk site → cameras → pipeline → puller → alert sender; write a dump.
    Returns the path to the written dump dir (per the spec's directory-during-write
    rule)."""
```

The walk:

1. Site-level manifest (deployment_id, run_id, library versions, settings hash, timestamp, reason).
2. Each `Camera` calls its `to_dump_dict()` (per Phase 8).
3. Each in-flight `ImageDataPacket` serializes via `to_dict()` (per Phase 4) → JSON + sidecar files.
4. Each `CapturingAlertSender`'s capture buffer is flushed to the dump.
5. Site-level state: thread counts, queue depths, memory metrics, the last N log lines.

Writes to `/tmp/connector-dumps/<run_id>/<timestamp>-<reason>/` per the spec's directory-during-write rule. The recovery sweep on next pod start zips orphan dirs.

### Crash trigger wiring

Three trigger paths:

**Path A — Python exception handlers.** Wrap the site manager's top-level run loop in a `try / except / finally`:

```python
try:
    site_manager.run()
except Exception as exc:
    site_manager.dump_state(reason=f"exception-{type(exc).__name__}")
    raise
finally:
    if shutdown_was_unclean:
        site_manager.dump_state(reason="unclean-shutdown")
```

Catches `RuntimeError`, `KeyError`, etc. — anything the pipeline raises that bubbles up.

**Path B — Native crashes via `faulthandler`.** Register `faulthandler.register(signal.SIGSEGV, ...)`, `SIGABRT`, `SIGFPE`. These fire on C-level segfaults ([[ffmpeg-entity|FFmpeg]], [[opencv-entity|OpenCV]], torch).

The handler is **constrained** — it can only call async-signal-safe functions. So it doesn't call `dump_state()` directly; it writes a flag file `/tmp/connector-dumps/<run_id>/.crash-signal-<signum>` and lets the watcher thread observe + flush state. (See "watcher thread" below.)

**Path C — SIGTERM (graceful shutdown).** Already handled in `connector.py` for billing-event emission. Extend the SIGTERM path to also call `dump_state(reason="sigterm")` when an env var `ACTUATE_DUMP_ON_SIGTERM=1` is set. Off by default in production (creates noise on routine pod restarts).

### Triggers — signal-only, NO polling thread

**Constraint (Mark 2026-05-22):** brain-in-jar must be 1:1 with off-baseline when not opt-in. No polling thread, no background CPU, no extra memory. Manual opt-in via env var is fine, including the cost of that opt-in mode.

This kills the "watcher thread" idea from earlier drafts of this synthesis. Triggers are now:

- **`faulthandler.register(SIGSEGV/SIGABRT/SIGFPE)`** — kernel-installed, zero steady-state cost. Async-signal-safe handler writes the IDP state to disk directly from the signal handler (no thread roundtrip).
- **Python exception handlers** in `connector.py` — `try/except` is free at steady state; only fires on the exception path.
- **`SIGUSR1` for manual on-demand dumps** — operator sends `kill -USR1 <pod_pid>` (or `kubectl exec` runs it). The signal handler triggers `dump_state(reason="manual-sigusr1")`. Cost: zero until signal arrives.
- **`atexit`** — Python-level shutdown hook. Fires on clean exits when `ACTUATE_DUMP_ON_EXIT=1` is set.

OOM detection is **moved out of the pod**. Kubernetes already labels OOMKilled pods (`reason: OOMKilled` in container status). The recovery sweep on the next pod's startup picks up any orphan directory left by an OOMKilled previous incarnation. No in-pod memory polling needed.

For manual-trigger latency: a `kubectl exec -- kill -USR1 1` round-trip is ~200ms — fast enough for operator-driven captures.

### Per-pod dump cap

Per the spec, **3 most recent dumps per pod**. Implementation: on every new `dump_state()` call, walk `/tmp/connector-dumps/<run_id>/`, sort by mtime, remove anything beyond the 3 newest.

If a pod is crash-looping, the 3 most-recent are the most useful (they're the freshest reproductions of the failure mode). Older dumps would get rolled over by S3 lifecycle anyway.

### Recovery sweep

On `connector.py` startup, before `site_manager.run()`, scan `/tmp/connector-dumps/` for orphan directories from previous runs that died mid-dump. For each:

1. If the directory contains a `manifest.json`, it's complete enough to zip; zip + queue for S3 upload (Phase 10).
2. If not, it's a partial dump from a crash that died mid-write. Best-effort: write a placeholder manifest with `incomplete: true`, zip anyway. Upload.
3. Remove the source directory.

This is the "zip-on-finalize" half of the directory-during-write / zip-on-finalize pattern. It handles the case where the crash killed the process *between* `dump_state()` writing files and a clean zip-and-upload step.

### Configuration

```bash
ACTUATE_BRAIN_IN_JAR_ENABLED=0            # master switch — DEFAULT OFF (perf-discipline rule)
ACTUATE_BRAIN_IN_JAR_DUMP_DIR=/tmp/...    # override dump root (only checked when enabled)
ACTUATE_BRAIN_IN_JAR_DUMP_CAP=3            # per-pod dump cap (only relevant when enabled)
ACTUATE_DUMP_ON_SIGTERM=0                  # opt in to SIGTERM dumps (only when master is on)
ACTUATE_DUMP_ON_EXIT=0                     # opt in to atexit dumps (only when master is on)
```

When `ACTUATE_BRAIN_IN_JAR_ENABLED=0` (default): NO signal handlers registered, NO try/except wrapping, NO file system access, NO additional imports beyond what's lazily loaded. The connector behaves byte-identical to a no-replay build.

Roll out plan: enable on Actuate's own internal test deployments first (NOT customer pods — explicit Mark guidance 2026-05-22). Observe a week. If the on-path overhead is acceptable, expand to a single customer test deployment with their consent.

## TODOs (Phase 9)

### 9A — `AnalyticsSiteManager.dump_state()`

- [ ] Implement the method per the walk above.
- [ ] Write to the directory-during-write layout.
- [ ] Populate the manifest with deployment_id, run_id, library versions, settings hash, timestamp, reason.
- [ ] Unit tests: synthetic site manager + dummy cameras dump to a temp dir; reload via `DumpLoader` (Phase 6) round-trips cleanly.

### 9B — Python-exception trigger path

- [ ] Wrap `connector.py` main run in `try / except / finally`.
- [ ] Call `dump_state(reason="exception-...")` on exception.
- [ ] Preserve the original exception (`raise` after dumping).
- [ ] Integration test: deliberately raise inside a pipeline step on a local connector; confirm dump materializes.

### 9C — Native-crash trigger via `faulthandler`

- [ ] Register `faulthandler.register` for SIGSEGV, SIGABRT, SIGFPE in `connector.py`.
- [ ] The signal handler writes a `.crash-signal-<signum>` flag file (async-signal-safe).
- [ ] Document the constraint loudly so future contributors don't add more work to the handler.
- [ ] Manual test: inject a deliberate `ctypes` segfault on a local connector; confirm flag file is created.

### 9D — `SIGUSR1` manual-trigger handler

- [ ] Register `signal.signal(SIGUSR1, ...)` in `connector.py` when `ACTUATE_BRAIN_IN_JAR_ENABLED=1`.
- [ ] Handler calls `dump_state(reason="manual-sigusr1")` directly.
- [ ] Per Python signal model: handler runs on the main thread between bytecode instructions, so it can safely call user code.
- [ ] Document the on-demand capture flow: `kubectl exec <pod> -- kill -USR1 1`.
- [ ] Unit test: send SIGUSR1 to a local process running the site manager; confirm a dump appears.

### 9E — Per-pod dump cap

- [ ] Implement rotation logic on every `dump_state()` call.
- [ ] Unit test: ten consecutive dumps leave only 3 most recent.

### 9F — Recovery sweep

- [ ] Implement on `connector.py` startup.
- [ ] Scan `/tmp/connector-dumps/`, zip orphans, queue for upload.
- [ ] Unit tests: orphan with manifest → clean zip; orphan without manifest → placeholder manifest + zip; nothing to recover → no-op.

### 9G — Configuration

- [ ] Add the env vars to the connector's config surface.
- [ ] Default state: `ACTUATE_BRAIN_IN_JAR_ENABLED=0` until Phase 10 ships S3 upload.
- [ ] Document each env var in connector CLAUDE.md.

### 9H — Documentation

- [ ] Add a "Brain-in-jar" section to connector CLAUDE.md.
- [ ] Cookbook: "I want to capture the next crash from deployment X" → `kubectl exec` → write `.manual-dump` flag → wait for next crash → fetch dump via Phase 10.
- [ ] Document the `faulthandler` signal-handler constraint (don't add work to it; route through the watcher).

## Estimate

~4–6h. The trigger paths and recovery sweep are the tricky parts; the dump-state walk itself is mechanical once Phases 4–8 land.

## Risk

The biggest unknown is **`faulthandler` interaction with the existing signal handling** in `connector.py` (SIGTERM for billing). If they conflict, native crashes could lose billing events or vice versa. Plan: cover both in 9C's integration test; if conflict appears, prefer billing emission first (it's revenue-critical) and emit a `.crash-signal-pending` flag the watcher can pick up after billing finishes.

A secondary risk: **disk pressure from runaway dumps**. The per-pod cap mitigates the steady state; the recovery sweep prevents orphan dirs from accumulating. But a pod with extremely large dumps (close to the 50 MB hard cap) could still strain `/tmp` if it sits at the 3-dump max with 50 MB each. Recommend `/tmp` on a `tmpfs` mount sized for at least 200 MB.

## Cross-references

- [[2026-05-20_ait-brain-in-jar-spec]] — parent
- [[2026-05-20_ait-phase-4-idp-serializer]] — IDP serialization is consumed here
- [[2026-05-20_ait-phase-8-camera-from-dump]] — camera state is consumed here
- [[2026-05-20_ait-phase-10-s3-sink-review-ux]] — uploads what this writes
- [[CONNECTOR-OPERATIONS]] — operational knowledge; brain-in-jar belongs in this list once shipped
