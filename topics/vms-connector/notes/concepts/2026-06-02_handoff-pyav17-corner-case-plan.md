---
title: "Handoff: PyAV-17 / FFmpeg-8 corner-case deep-plan (#1703)"
type: concept
topic: vms-connector
tags: [handoff, pyav, ffmpeg, hevc, miss-685, eng-136, release-plan]
created: 2026-06-02
updated: 2026-06-02
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/2026-06-02.md
  - topics/personal-notes/notes/daily/2026-06-03.md
  - topics/personal-notes/notes/daily/2026-06-04.md
  - topics/personal-notes/notes/daily/2026-06-15.md
  - topics/vms-connector/notes/syntheses/2026-06-15_pr1731-ap-to-prod-promotion-review.md
incoming_updated: 2026-06-19
---

# Handoff: PyAV-17 / FFmpeg-8 corner-case deep-plan (#1703)

Working note for the **"deep-plan #1703 corner cases before pushing"** workstream (mark-todos Today's Scope headline). Captures the risk re-assessment, the edits already made, and the remaining work. Entry point for resuming.

**Tickets/PRs:** Jira ENG-136 · GH issue [vms-connector#1703](https://github.com/aegissystems/vms-connector/issues/1703) · connector PR [#1714](https://github.com/aegissystems/vms-connector/pull/1714) (branch `feature/pyav-17-bump-clean`, draft/CONFLICTING) · lib PR [#358](https://github.com/aegissystems/actuate-libraries/pull/358) (MERGED, `[patch:actuate-pullers]` → published **1.17.20**). Driver: **MISS-685** (AmeriGas Sacramento, [[h265-hevc-deep-dive|HEVC]] gray-frame missed detection).

## The change

Bump `av` 13.1→17.0.1, `opencv-python-headless` 4.11→4.13, [[ffmpeg-entity|FFmpeg]] `n7.1.3`→`n8.1.1`. Core mechanism: [[ffmpeg-entity|FFmpeg]] 8.1 commit `bc1a3bfd2` sets `AV_FRAME_FLAG_CORRUPT` on [[h265-hevc-deep-dive|HEVC]] frames decoded against a missing/corrupt ref and **suppresses them by default** — so YOLO stops getting gray frames; FPS dips briefly during corruption windows instead.

## Risk re-assessment (verified against actual code, 2026-06-02)

Two scariest risks were checked by reading the puller + downstream (`connector-pipeline-expert` agent):

- **C2 — reconnect storm: DEBUNKED.** No frame-drought watchdog / read-timeout / FPS-floor reconnect exists in the puller. Reconnects fire only on a real `demux()`/`decode()` exception. Intermittent frames → quieter pipeline, NOT reconnects. The headline benefit is **not** self-defeating. (`av_url_puller.py` read loop ~1270; `base_stream_camera.py` `check_puller_state` only restarts on dead/unhealthy.)
- **C1 — AVDISCARD starvation thrashing: REAL but benign.** A trip is **log-only** (no reconnect/restart); oscillation floor ~10s (measurement window) + 1–3s starvation timeout → slow cycle, not flapping. Scope is narrower than the issue says: AVDISCARD/NONKEY is **global, not HEVC-specific**, and **never active on HW-decoded or intra-only streams** → blast radius = software-decoded dense-keyframe [[h265-hevc-deep-dive|HEVC]]/[[h264-deep-dive|H264]] (the MISS-685 cohort). Logic at `av_url_puller.py:666-683`; `_AVDISCARD_STARVATION_MULTIPLIER=3` × `(1/highest_fps)`.
- **Stale preview — REAL, unguarded.** During a corruption drought the last-good S3 snapshot persists with no age guard (`base_puller.py:647-652`). Better than the old gray upload, but operators see a frozen image with no staleness indicator. (Issue's "stale gray frame" framing is now "stale last-good frame.")
- **Nothing reads `is_corrupt`** anywhere in either repo → suppression creates no dead code and no ≥1-frame-per-packet assumption breaks.

## 🔴 Bug the issue AND lib PR #358 both missed

`CodecContext.close()` was **removed in [[pyav-entity|PyAV]] 16** (verified against the cached **av 17.0.1** wheel: stub has `open`/`create`/`flush_buffers`, no `close`; [[pyav-entity|PyAV]] 13.1.0 still has it). `actuate-pullers` `av_url_puller.py` calls `self._nvdec_ctx.close()` at **main lines 841 + 940** — both wrapped in `try: … except: pass`, so under [[pyav-entity|PyAV]] 17 it's **silently swallowed** (AttributeError caught), not a crash, but the explicit cleanup never runs and the bare-except masks the removal. **#358 migrated the API surface but did not touch these.**
**Fix:** remove the two `try/close/except` blocks, keep `self._nvdec_ctx = None` (CPython refcount drop → `__dealloc__` → `avcodec_free_context`, prompt + version-agnostic). New `[patch:actuate-pullers]` PR to main. (Note: `av.AVError` is already handled robustly on main via `_AvError = getattr(av,"FFmpegError",None) or getattr(av,"AVError")` at `autopatrol_websocket_stream_puller.py:15` — no action.)

## Docker matrix — FFmpeg pinned in 3 places, not 1 (issue under-counted)

| Image | [[ffmpeg-entity|FFmpeg]] source | Was | Now |
|---|---|---|---|
| `x86_dockerfile` (CPU x86) | PyAV-17 wheel's bundled [[ffmpeg-entity|FFmpeg]] 8.1 | auto | auto (no edit) |
| `arm_dockerfile` (CPU ARM) | `build_ffmpeg.sh` (source) | n7.1.3 | **n8.1.1** ✅ |
| `arm_dockerfile.gpu` | inline source build | n7.1.3 | **n8.1.1 + `--enable-gnutls`** ✅ |
| `x86_dockerfile.gpu` | inline source build | n7.1.3 | **n8.1.1 + `--enable-gnutls`** ✅ |

The AmeriGas soak validated **only the x86-CPU-wheel path**. ARM-CPU + GPU build PyAV-17 **from source**; left at 7.1.3 they'd lack the corrupt-frame fix (or fail to build PyAV-17 against 7.1.3). The `--enable-gnutls` adds also close the tracked **§15a** GPU rtsps/https gap (both GPU images install `libgnutls28-dev` via `apt_requirements.txt`, so configure is clean).

## Decisions locked

- **D1 = keep the custom [[ffmpeg-entity|FFmpeg]] build** (not stock wheel). Rationale: we control `--enable-gnutls` (rtsps/https — §15a shows what breaks without it), preserve the vaapi/cuda HW-accel door (§5 fleet-arch GPU/co-located inference direction), `--enable-libx265`. +5min cold build is cheap vs a TLS-capability regression.
- Bump all 3 source pins; fold §15a gnutls fix into both GPU builds.
- Validation gap → **add proactive guards** (not soak-observe-only).

## Edits already made (UNCOMMITTED on `feature/pyav-17-bump-clean`)

- `docker_files/dependencies/build_ffmpeg.sh:12` n7.1.3→n8.1.1 + comment
- `docker_files/arm_dockerfile.gpu` n8.1.1 + `--enable-gnutls` + comment
- `docker_files/x86_dockerfile.gpu` n8.1.1 + `--enable-gnutls` + comment
- `docker_files/arm_dockerfile` CVE comment refresh

## Remaining work (resume here)

1. ✅ **DONE 2026-06-03 — Removed `_nvdec_ctx.close()` calls** (main lines 841, 940). On branch `fix/actuate-pullers-pyav17-followups` (off main), UNCOMMITTED. Both `try/close/except` blocks deleted, `self._nvdec_ctx = None` kept ([[pyav-entity|PyAV]] 16+ removed `CodecContext.close()`; ref-drop → `__dealloc__`). Verified no other `CodecContext.close()` remains (all other `.close()` are `Container.close()`, valid). Will merge with the two guards below in one `[patch/minor:actuate-pullers]` PR.
2. **[[[actuate-pullers]]] C1 starvation hysteresis guard** — after N trips in a window on one stream, stop re-arming NONKEY (pin DEFAULT) until a clean measurement + rate-limit the WARN. Kills the oscillation pre-emptively.
3. **[[[actuate-pullers]]] Stale-preview guard** — emit metric/WARN when a preview hasn't refreshed in >M min (observability for the frozen-snapshot case).
4. **Build validation** — `docker buildx` ARM-CPU (PyAV-17 from source vs FFmpeg-8.1.1) + both GPU images ([[ffmpeg-entity|FFmpeg]] 8.1.1 + CUDA 12.1 nvcc + unpinned nv-codec-headers is the riskiest build). CI builds ARM64+x86 on PR — natural gate.
5. **Re-confirm MISS-685 corruption signal still live** on cust **41399** (AmeriGas Sacramento) before relying on the ~28-reconnects/4h baseline (measured pre-2026-05-19).
6. **Rebase `feature/pyav-17-bump-clean` onto stage** (CONFLICTING), bump `actuate-pullers` dev→stable pin once guards publish, mark #1714 Ready.
7. **Promote** stage→rearch with `[minor:actuate-pullers]` per issue.
8. Then the full polished synthesis (this note is the working draft).

## Progress 2026-06-03 — all code committed + pushed + PR'd

- ✅ **nvdec close fix + C1 starvation hysteresis + stale-preview guard** — all three on `actuate-libraries` branch `fix/actuate-pullers-pyav17-followups`, committed (`1a65bbb9`), pushed, **PR [#367](https://github.com/aegissystems/actuate-libraries/pull/367)** open to main (`[minor:actuate-pullers]`). 29 pullers tests pass, ruff clean.
  - C1 hysteresis: after 3 starvation trips / 120s → pin DEFAULT for 600s, WARN once per pin (`av_url_puller.py` AVDiscard constants + `_avdiscard_init`/`_avdiscard_on_packet`/`_avdiscard_finish_measurement`).
  - stale-preview: WARN once per episode when the 5-min preview cycle finds no new frame (`base_puller.py:upload_frame_preview`).
- ✅ **Custom [[ffmpeg-entity|FFmpeg]] build bump** — committed (`07bee6845`) + pushed on vms-connector `feature/pyav-17-bump-clean` (updates draft #1714).

### Gated / remaining (next session)
1. **Merge #367 → main** (review + approval; publishes stable [[actuate-pullers]]). Then **bump #1714's `actuate-pullers` pin to that stable** (dev pins not allowed on stage).
2. **Build validation** — connector CI on #1714 builds ARM64 + x86 (exercises [[ffmpeg-entity|FFmpeg]] n8.1.1 from source on ARM-CPU); GPU images need a manual `docker buildx` ([[ffmpeg-entity|FFmpeg]] 8.1.1 + CUDA 12.1 nvcc + nv-codec-headers). [[watch-entity|Watch]] CI.
3. **Re-confirm MISS-685 corruption signal** on cust 41399 before relying on the soak.
4. **Rebase #1714 onto stage** (CONFLICTING) + mark Ready; promote with `[minor:actuate-pullers]`.
5. **Unit tests for the two guards** (timing/threading — not yet added; existing suite passes).
6. Full polished synthesis (this handoff is the working draft).

## Progress 2026-06-05 — #367 validated to local bar

- **#367 reviewed clean** (actuate-pr-reviewer): no blockers; nvdec close-removal correct; guards thread-disjoint; tests genuine. One accept-leaning should-fix (C1 trip counter doesn't decay on recovery). Squash body must strip auto-bump lines, keep `[minor:actuate-pullers]`.
- **Local validation ladder run** (against #367 code on av17, connector venv via `PYTHONPATH` shadow):
  - **V1 [[rtsp-deep-dive|RTSP]] decode parity** PASS — 60 frames, 0 corrupt, 0 zero-size, `skip_frame` both directions (stays `str` on av17). NONKEY-on-long-GOP tanks throughput → corroborates the starvation condition C1 guards against.
  - **V2 corrupt-HEVC synth** partial — av17 decodes corrupted [[h265-hevc-deep-dive|HEVC]] without crash, damaged inter-frames dropped (not emitted gray). Could NOT synthetically isolate the `is_corrupt` suppress-vs-emit toggle (byte-flip breaks NAL parse; manual missing-ref decoder produced 0 frames). Confirms KB conclusion: faithful HEVC-corruption repro needs real bad-camera data → soak gate.
  - **V3 connector E2E** PASS — rc=0 on local-test-stack, AP lifecycle intact, no av/import errors. AIT skipped (no [[actuate-pullers]] dep → null test).
- Scripts: `/tmp/pyav17_val/` (v1_rtsp_decode_parity, v2_corrupt_hevc, v2b_missing_ref).

## Progress 2026-06-12 — train reconciliation + decision (READ THIS FIRST on resume)

**The work consolidated into an "upgrade train" on `feature/pyav-17-bump-clean` (#1714), separate from the #367 guards.** Reconciled the true state (local git ref went stale; used `gh api` at head SHA `396063dd`):

- **#1714 = [[pyav-entity|PyAV]] 17.0.1 + [[ffmpeg-entity|FFmpeg]] 8.1.1 + NumPy 2.4.6 + [[opencv-entity|OpenCV]] 4.13 + security/perf dep refresh** (cryptography 48, urllib3 2.7, requests 2.34, pillow 12.2, uvicorn 0.49, newrelic 13.1, psutil 7.2, shapely 2.1.2). **`actuate-pullers==1.20.3` stable, NO dev pins.** Body claims verified.
- **Validated:** 166 connector tests, all lib suites on numpy 1.26 *and* 2.4, ECR green. **Leg-1 A/B soak passed overnight** on `actuate-nyc-alibi-vigilant`: **−15% memory, −45% CPU**, reconnect parity, zero tracebacks. **Leg-2 (AmeriGas cust-41399, [[h265-hevc-deep-dive|HEVC]] efficacy) pending.**
- **⚠️ The #367 guards are NOT in the train.** Pullers 1.20.3 (= `main`) lacks C1 hysteresis / stale-preview / nvdec-close. The train uses the **old un-hysteresis'd `_AVDISCARD_STARVATION_MULTIPLIER` fallback** (its Leg-2 checklist literally says "bump `_MULTIPLIER` if thrashing"). **#367 is 71 commits behind `main`.**
- **DECISION (Mark, 06-12): train now, guards in parallel.** Drive #1714 → stage gated on Leg-2 soak; separately rebase+merge #367 → publish pullers ~1.21 → fold into the train (bump pin 1.20.3→~1.21) **before fleet rollout** (guards harden the exact corruption→NONKEY thrash Leg-2 exercises). Not blocking the stage A/B.
- **Superseded #1621** (old [[pyav-entity|PyAV]] PR) and **closed test #1696** (cv2-dst A/B) during cleanup.
- **Resume blockers:** AWS prod SSO expires (`aws sso login --profile prod` before any connector `uv lock`); #367 rebase is 71 commits.

## Related

- [[2026-05-26_pyav17-local-validation]] — local validation ladder
- [[2026-05-19_streaming-pyav17-crosscut]] · [[2026-05-19_live-streaming-v1-plan]]
- mark-todos §15a (GPU gnutls), §5 (fleet-arch HW-accel direction), §30 (profiling)
