---
title: "PyAV 17 migration — local-validation ladder + actuate-libraries PR #358"
type: synthesis
topic: vms-connector
tags: [pyav, ffmpeg, av_url_puller, autopatrol_websocket_stream_puller, migration, local-test-stack, rtsp-camera-simulator, compat-shim, "§30", dependency-bump, vms-connector]
created: 2026-05-26
updated: 2026-05-26
author: mark
incoming:
  - topics/personal-notes/notes/concepts/2026-05-28_session-handoff.md
  - topics/personal-notes/notes/daily/2026-05-26.md
  - topics/personal-notes/notes/daily/2026-05-27.md
  - topics/personal-notes/notes/daily/2026-05-28.md
  - topics/personal-notes/notes/daily/2026-06-02.md
  - topics/vms-connector/notes/concepts/2026-06-02_handoff-pyav17-corner-case-plan.md
incoming_updated: 2026-06-19
---

# PyAV 17 migration — local-validation ladder

Captures the 2026-05-26 work to test + verify the [[actuate-pullers]] half of the [[pyav-entity|PyAV]] 13 → 17 bump locally before pushing toward release. Concrete results from each tier of a 4-tier local test plan; the surprising finding that materially shrinks the migration scope; and the residual-risk handoff to AmeriGas soak.

Paired with: actuate-libraries PR [#358](https://github.com/aegissystems/actuate-libraries/pull/358) (draft) and vms-connector branch `feature/pyav-17-bump-clean` (staged, not pushed).

## Context

[vms-connector#1703](https://github.com/aegissystems/vms-connector/issues/1703) proposed the bump ([[pyav-entity|PyAV]] 13.1.0 → 17.0.1, [[ffmpeg-entity|FFmpeg]] 7.1.3 → 8.1.1, [[opencv-entity|OpenCV]] 4.10 → 4.13) to fix MISS-685's [[h265-hevc-deep-dive|HEVC]] silent-corruption gap at AmeriGas Sacramento. The issue's validation plan calls for an AmeriGas soak as the gating test, but doesn't define what local validation should look like first. Mark's standing rule (per [[2026-05-22_actuate-testing-toolkit-overview]]): use the new tooling end-to-end locally before moving anything significant.

The two repos that touch `av` directly:
- `actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py` — 7 sites where `codec_context.skip_frame` is assigned a string
- `actuate-libraries/actuate-pullers/src/actuate_pullers/socket/autopatrol_websocket_stream_puller.py` — 1 site catching `av.AVError`

`av` is not declared as an [[actuate-pullers]] dependency; consumers (vms-connector, autopatrol-server) pin it.

## The four-tier ladder

| Tier | Question it answers | Concrete shape |
|---|---|---|
| **T0** | Does the migration build and pass existing tests on both av versions? | `uv pip install av==X`; import smoke; run [[actuate-pullers]] unit tests |
| **T1** | Does the av API surface the migrated code uses behave identically on av13 vs av17? | [[rtsp-deep-dive|RTSP]] stream from `rtsp-camera-simulator`; `av.open`/decode/`skip_frame` set/bad-URL catch |
| **T2** | Does the connector boot + complete an AP cycle against av17 + migrated pullers? | local-test-stack at `/home/mork/work/local-test-stack` — boot LocalStack + run connector against modified worktree |
| **T3** | Do IDPs from a brain-in-jar dump still match shape after the bump? | (n/a — T2-lite produces no frames; needs T2-rtsp or T2-ws scope to capture meaningful dump) |

T0 + T1 cover the API/library layer; T2 covers the integration layer; T3 covers the IDP-shape regression layer. Each gates the next.

## What ran (compat-shim migration in /tmp/aclibs-pyav17)

The migration takes a defensive-shim shape rather than the direct-rename shape in #1703's body, so consumers can upgrade `av` on their own timelines:

```python
# socket/autopatrol_websocket_stream_puller.py
_AvError = getattr(av, "FFmpegError", None) or getattr(av, "AVError")
# ... except _AvError as e: ...
```

```python
# url/av_url_puller.py
try:
    from av.codec.context import SkipType as _SkipType
    _SKIP_DEFAULT = _SkipType.DEFAULT
    _SKIP_NONKEY = _SkipType.NONKEY
except ImportError:  # PyAV 13.x OR PyAV 17.0.1 (see finding below)
    _SKIP_DEFAULT = "DEFAULT"
    _SKIP_NONKEY = "NONKEY"
# ... codec_context.skip_frame = _SKIP_DEFAULT ...
```

Version bump: `actuate-pullers` 1.17.19 → **1.17.20**.

## T0 — unit + import (passed both versions)

29/29 [[actuate-pullers]] tests pass on av13.1.0 AND av17.0.1. Compat shim resolution:

| Resolution | av13.1.0 | av17.0.1 |
|---|---|---|
| `_AvError` | `FFmpegError` (av13 exposes both names; getattr picks FFmpegError first) | `FFmpegError` (only name) |
| `_SKIP_DEFAULT` | `SkipType.DEFAULT` (enum import succeeds) | `'DEFAULT'` (fallback — see finding below) |

## T1 — RTSP smoke vs `rtsp-camera-simulator` (passed both versions)

The simulator at `docker-compose.yml` in `/home/mork/work/vms-connector/rtsp_camera_simulator/` was already running locally ([[rtsp-deep-dive|RTSP]] [[h264-deep-dive|h264]] stream at `rtsp://localhost:8554/camera`). The mount point is `/camera`, not `/camera_simulator` despite the directory name. Wrote a 30-frame probe (`/tmp/aclibs-pyav17/_t1_probe_rtsp.py`):

| Op | av13.1.0 | av17.0.1 |
|---|---|---|
| `av.open(rtsp://)` | 1505 ms | 1519 ms |
| Decode 30 frames | 0.53 s / **56.7 fps** | 0.54 s / **55.4 fps** |
| `skip_frame` set (each direction) | succeeds (enum repr) | succeeds (string repr) |
| Bad URL → `_AvError` catch | `HTTPNotFoundError` (subclass of FFmpegError) | `HTTPNotFoundError` (subclass of FFmpegError) |
| Zero-size frames | 0 | 0 |

Latency identical within noise. [[pyav-entity|PyAV]] 17's documented multithreaded-`reformat()` benefit doesn't show on this codepath (single-stream [[h264-deep-dive|H.264]] decode; the bottleneck is wall-clock not CPU).

## T2-lite — connector E2E against local-test-stack (passed)

The vms-connector worktree at `/tmp/vmsc-pyav17-clean` (branch `feature/pyav-17-bump-clean`, 2 cherry-picks from the original feature/pyav-17-upgrade branch — av pin + bench scripts; left the `Drop custom FFmpeg build` commit OUT because it conflicted with stage's new Graviton 3/4 CFLAGS). Override [[actuate-pullers]] to point at the migration worktree:

```bash
cd /tmp/vmsc-pyav17-clean
uv sync                                          # av==17.0.0 picked up via pyproject pin ~=17.0.0
uv pip install -e /tmp/aclibs-pyav17/actuate-pullers --reinstall
VMS_CONNECTOR_DIR=/tmp/vmsc-pyav17-clean /home/mork/work/local-test-stack/run-connector.sh
```

Result: `connector exited with rc=0`. Immix call sequence matches the local-test-stack's validation checklist exactly:

| Immix call | Expected | Observed |
|---|---|---|
| `get_patrols` | ≥1 | 1 |
| `start_patrol` | 1 | 1 |
| `get_patrol_stream` (init + keepalive) | 2 | 2 |
| `end_patrol` (post-AP-summary-disable: pre-SQS) | 1 | 1 |
| `raise_patrol_alert` | 0 | 0 (correctly skipped: no stream_id history) |

No av-related exceptions anywhere in the log. The DDB / CHM errors (`ResourceNotFoundException` on healthcheck, `ValidationException` on save_chm_issue) are pre-documented placeholder-schema limitations of the stack; they reproduce identically on av13.

## T3 — not run (zero frames available to dump)

T2-lite produced `broken_stream: True, frame_returned: False` for the AP camera because the existing local-test-stack stubs `get_patrol_stream` to return a fake-ok response with no actual stream URL. The websocket puller never connects → no frames flow → a brain-in-jar dump from this run would be empty. T3 was therefore skipped.

For T3 to add value, T2 needs to run against a *real* stream source. The two paths considered:
- **T2-rtsp** (~2-3h scope) — build a non-AP customer config + point at the simulator. Would exercise `av_url_puller`'s 7 `skip_frame` sites at runtime.
- **T2-ws** (~3-4h+ scope) — build a local WebSocket fragment server. Would exercise `autopatrol_websocket_stream_puller`'s `_AvError` catch at runtime.

Neither was in scope for 2026-05-26. The headline benefit of #1703 ([[ffmpeg-entity|FFmpeg]] 8.0 rejecting bad NALUs upstream) is HEVC-corruption-dependent, so locally untestable regardless of T2 path. The AmeriGas soak is the right shape for that signal.

## Surprising finding worth memo-ing

**[[pyav-entity|PyAV]] 17.0.1 has neither `SkipType` enum nor `av.codec.context.SkipType` at the documented import path**, and the `skip_frame` field is still a Python `str` subclass that accepts the same string values as [[pyav-entity|PyAV]] 13:

```
>>> import av; av.__version__
'17.0.1'
>>> from av.codec.context import SkipType  # ImportError
>>> ctx = av.codec.context.CodecContext.create('h264', 'r')
>>> ctx.skip_frame
'DEFAULT'
>>> type(ctx.skip_frame).__mro__
('str', 'object')
>>> ctx.skip_frame = 'NONKEY'  # works, returns 'NONKEY'
```

[vms-connector#1703](https://github.com/aegissystems/vms-connector/issues/1703)'s body claims the 7 `skip_frame` sites must change to `SkipType.DEFAULT`/`SkipType.NONKEY` enum members. **That is not the case for [[pyav-entity|PyAV]] 17.0.1.** The compat shim's string fallback handles av17 transparently; the migration could have been *just* the `AVError → FFmpegError` rename (1 line).

The shim is still useful — it cleanly handles any intermediate [[pyav-entity|PyAV]] version where `SkipType` was the only accepted form ([[pyav-entity|PyAV]] 14-16, possibly), and the cost is ~10 lines of import-time code. But the issue body's framing of skip_frame as a required breaking change was overstated.

## Residual risks (deferred to AmeriGas soak)

The local ladder doesn't catch:
1. **[[ffmpeg-entity|FFmpeg]] 8.0 ABI vs 7.1.3** — [[rtsp-deep-dive|RTSP]] transport defaults, container teardown timing, demuxer probe behavior. Locally untested because the simulator + clean [[h264-deep-dive|H.264]] doesn't surface these.
2. **[[h265-hevc-deep-dive|HEVC]] corruption rejection** — the entire headline benefit of #1703. Requires corrupt sample data from a known-bad camera; locally untestable.
3. **WebSocket fragment decode on the AP path** — the only path that runs in production AutoPatrol mode. Needs a fragment server we don't have.

The issue's validation plan correctly identifies cust 41399 (AmeriGas Sacramento) as the right gate for (2). (1) and (3) are observable in the same soak.

## Tooling gaps surfaced

- **No unit tests for `av_url_puller.py`** — the file with the 7 skip_frame sites has zero direct tests. T0 covers it via import-time only. Worth a follow-up to write decode-path tests using `av`'s built-in synthetic streams (no [[rtsp-deep-dive|RTSP]] server needed).
- **local-test-stack stubs `get_patrol_stream` with no URL** — by design (the README calls this out and points at `rtsp-camera-simulator` as the upgrade path), but means the stack today only validates connector boot + lifecycle, not actual decode. A patch to the stub that lets it return a configurable stream URL would unlock T2-rtsp without much glue.
- **`feature/pyav-17-upgrade` (Jacob's original) was a 200-commit divergent branch**, not a focused feature branch. The cherry-pick-onto-stage approach took 3 commits and worked cleanly except for the `Drop custom FFmpeg build` commit which conflicts with stage's new Graviton 3/4 CFLAGS. Leaving the [[ffmpeg-entity|FFmpeg]] build drop for a follow-up PR after av17 soaks.

## Release plan (from here)

```
PR #358 (actuate-libraries)                ← draft now, awaiting review
   ↓ on merge to main, [patch:actuate-pullers] triggers bump-stable
   ↓ stable 1.17.20 publishes
   ↓
new vms-connector PR (feature/pyav-17-bump-clean, base=stage)
   • av~=13.1.0 → av~=17.0.0
   • actuate-pullers==1.17.19 → ==1.17.20
   • bench + diagnostic scripts
   ↓ on merge to stage, image builds
   ↓
deploy to cust 41399 (AmeriGas Sacramento) via connector_deployer
   ↓ 24-48h soak
   • watch reconnect rate vs ~28/4h baseline
   • watch snapshot quality (no gray previews)
   • watch inference detection rate
   ↓ if clean
   ↓
promote to stage fleet soak
   ↓ if clean
   ↓
promote to rearchitecture with [minor:actuate-pullers]
```

`Drop custom FFmpeg build` and [[opencv-entity|OpenCV]] 4.10 → 4.13 are explicitly **deferred** to follow-up PRs (optional per the issue, complications per the stage divergence).

## Cross-references

- [[2026-05-19_streaming-pyav17-crosscut]] — the sequencing analysis (streaming v1 vs #1703)
- [[2026-05-20_local-ap-e2e-stack-installed]] — local-test-stack reference
- [[2026-05-22_actuate-testing-toolkit-overview]] — the broader testing toolkit
- vms-connector#1703 — proposal capture
- vms-connector#1621 (old) — original feature/pyav-17-upgrade PR; will close in favor of `feature/pyav-17-bump-clean` after #358 lands
- ENG-136 — Jira ticket
- mark-todos §30 — workstream
