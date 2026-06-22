---
title: Out-of-Process Profilers and Samplers
type: concept
topic: profiling-and-performance
tags: [profiling, py-spy, memray, austin, scalene, sampling, flamegraph, ptrace]
created: 2026-05-12
updated: 2026-05-12
author: kb-bot
incoming:
  - topics/profiling-and-performance/_summary.md
  - topics/profiling-and-performance/notes/concepts/in-process-hooks.md
  - topics/profiling-and-performance/notes/syntheses/2026-05-12_actuate-instrumentation-v1-verification-plan.md
  - topics/profiling-and-performance/notes/syntheses/2026-05-12_profiling-toolkit-and-roadmap.md
  - topics/profiling-and-performance/notes/syntheses/2026-05-12_python-3.15-profiling-sampling-watchlist.md
incoming_updated: 2026-05-13
---

# Out-of-Process Profilers and Samplers

Tools that attach to a running Python process (or wrap its startup) and read its memory/stacks externally. Complement to [[in-process-hooks]]: those run inside the process and are always-on but coarse-grained; these are external, opt-in, and fine-grained.

All Linux out-of-process samplers require either root, `CAP_SYS_PTRACE`, or `kernel.yama.ptrace_scope=0` — this is the dominant friction in K8s deployments.

## What we currently use

### py-spy — CPU sampling

Already wired in via `vms-connector/cpu_profile.sh`:

```
py-spy record -o profile.speedscope.json -f speedscope -- python connector.py -l
```

- Out-of-process sampling, Rust binary, default 100 Hz.
- Reads frames via `process_vm_readv` (or `ptrace` fallback).
- Output formats: speedscope JSON (preferred — drag into [speedscope.app](https://www.speedscope.app/)), flamegraph SVG, raw.
- `py-spy dump <pid>` for a single-snapshot stack-of-every-thread.
- Pip-installable but pulls a Rust binary on first use.

**Local use:** great. Wrap `connector.py -l` and let it sample for as long as you need.

**Production use:** blocked by missing `CAP_SYS_PTRACE` on stock connector pods. Workaround is a debug pod with `securityContext.capabilities.add: [SYS_PTRACE]` and `shareProcessNamespace: true`. Roadmap item 7 proposes a built-in `ACTUATE_PYSPY=1` sidecar that handles this.

### memray — Native allocation profiling

Already wired in via `vms-connector/memory_profile.sh`:

```
memray run --native -o output.bin connector.py -l
memray flamegraph output.bin   # render HTML
```

- **Wrap-mode**, not attach-mode. Has to start the process; cannot attach to an already-running connector.
- `--native` resolves C-level stacks ([[pyav-entity|PyAV]], [[opencv-entity|OpenCV]], libjemalloc) using debug symbols. Worth it.
- Output is a `.bin` you render later — `flamegraph`, `summary`, `tree`, `parse` subcommands.
- Tracks every allocation; overhead is non-trivial (typically 2–4×). Only run for the duration needed to reproduce a leak.

**Production use:** wrap-mode means you can't attach to a live pod. Either reproduce locally with realistic settings, or rebuild a debug image with memray as the entrypoint. The latter is rare; the former is the default workflow.

## What we don't currently use (and why)

### austin

Out-of-process sampler, C implementation. Functionally overlaps py-spy. We chose py-spy because:
- Speedscope output is more convenient than austin's collapsed-stack format.
- Same ptrace mechanics, same K8s friction — no advantage.

Keep on the radar in case py-spy ever breaks for a Python version we need.

### scalene

CPU + memory + GPU profiler, line-level attribution, both in-process and out-of-process modes.

- More expensive in overhead than py-spy.
- Memory dimension overlaps memray; for our workload memray's `--native` is the more useful surface.
- Line-level CPU attribution is occasionally useful, but py-spy + speedscope's source view is usually enough.

Not adopted. Revisit if we hit a hotspot that needs line-level attribution (rare — most of our hot loops are in C extensions where line-level Python attribution is misleading anyway).

### viztracer

Trace-based (not sampling). Records every function call. Referenced as a commented-out line in `cpu_profile.sh`.

- Excellent for understanding **causality** of a few seconds of execution (waterfall view, async tasks).
- Terrible for steady-state profiling (file size explodes).
- Use case: debug a one-off "why does startup take 30 s" question, not "where is CPU spent over 10 minutes."

Reach for it ad-hoc, not standard tooling.

### Python 3.15 `profiling.sampling` (PEP 799, "Tachyon")

**Not yet adoptable.** See [[2026-05-12_python-3.15-profiling-sampling-watchlist]] for full brief. Summary:

- Stdlib sampling profiler, ships in 3.15.
- Architecturally similar to py-spy / austin (out-of-process, ptrace-based).
- Adds: differential flamegraphs, async-aware mode, Gecko/Firefox JSON output, in-stdlib (no Rust install).
- **Blocked by:** Python 3.15 final is **October 2027**; connector currently on 3.12; profiler must match target's minor version. Same ptrace friction as py-spy.
- **Plan:** revisit when connector reaches 3.15. Until then py-spy is the equivalent.

## When to reach for which

| Question | Tool | Mode |
|---|---|---|
| "What's hot on CPU in a running stage pod?" | py-spy | attach |
| "Where is my local connector spending time?" | py-spy | wrap |
| "Why is RSS climbing over hours in a single site?" | memray (locally with prod-like settings) + jemalloc breakdown logs | wrap + in-process |
| "What Python objects are leaking?" | tracemalloc (`ACTUATE_TRACEMALLOC=1`) | in-process |
| "Why is startup slow?" | viztracer or `py-spy record` over startup | wrap |
| "Did the last library bump regress CPU?" | py-spy speedscope on stage before + after | attach × 2 |
| "Did the last library bump regress memory?" | jemalloc breakdown lines in NR `before/after` | in-process |
| "Per-line CPU within a specific function" | scalene (rare) | wrap |

## Operational mechanics in K8s

Until the sidecar in roadmap item 7 lands:

1. **Reproducing locally** is the primary workflow. `python connector.py -l` with a representative `settings.json` lets you attach py-spy / wrap memray freely.
2. **One-off stage profiling** via a debug pod:
   - `kubectl debug -n rearchitecture <pod> --image=python:3.12 --target=<container> --share-processes -it`
   - Inside: `pip install py-spy && py-spy dump --pid 1`
   - Requires `shareProcessNamespace: true` on the deployment (not default).
3. **Persistent in-pod profiling** requires the sidecar — Roadmap §30 item 7.

## Production-safety notes

- **py-spy attach overhead** is negligible on the target (reads memory externally); the sampler process itself uses ~1% CPU at 100 Hz.
- **memray wrap overhead** is 2–4×. Never run memray in a customer-serving production pod.
- **scalene** has higher in-process overhead (~10-30%); avoid in production.
- **Stop-the-world** is not a property of py-spy / austin / `profiling.sampling` (`--blocking` mode of the last is opt-in and explicitly off by default). All three use lock-free reads of target memory.

## Related

- [[in-process-hooks]] — the always-on production telemetry
- [[2026-05-12_python-3.15-profiling-sampling-watchlist]] — Tachyon brief
- [[2026-05-12_profiling-toolkit-and-roadmap]] — the §30 work items
- [[tooling-inventory]] — full list with status
