---
title: "Handoff: cv2 dst= → stage deploy (2026-05-19 resume)"
type: concept
topic: profiling-and-performance
tags: [handoff, actuate-movement, vms-connector, deploy, cv2-dst-preallocation, §30]
created: 2026-05-18
updated: 2026-05-18
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/2026-05-18.md
  - topics/personal-notes/notes/daily/2026-05-19.md
  - topics/personal-notes/notes/daily/2026-05-20.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/profiling-and-performance/notes/concepts/2026-05-19_cv2-dst-soak-status.md
  - topics/profiling-and-performance/notes/concepts/2026-05-20_memray-runner-investigation.md
incoming_updated: 2026-05-27
---

# Handoff — cv2 `dst=` → stage deploy

Resume point for §30. The [[opencv-entity|cv2]] `dst=` preallocation change is implemented, verified, and queued behind two draft PRs; the local-webcam test fixture is in place. Tomorrow's work is the staged release flow + a couple of harness papercuts.

## Where things stand at end-of-day 2026-05-18

- **Library PR [#349](https://github.com/aegissystems/actuate-libraries/pull/349) — draft, all CI green for 3 days.** Unit Tests + Changelog Reminder + Publish Dev all pass. The Publish [[dev-workflow|Dev workflow]] has been republishing `actuate-movement` `1.2.7.dev1+feature.actuate.movement.cv2.dst.preallocation` to CodeArtifact on every push.
- **Connector PR [#1696](https://github.com/aegissystems/vms-connector/pull/1696) — draft, CI green, two commits.** First commit pins `actuate-movement` to the dev build. Second commit (today) lands the local-webcam [[rtsp-deep-dive|RTSP]] fixture: `test_settings/webcam_rtsp/` (mediamtx-ffmpeg compose), `VMS_CONNECTOR_LOCAL_WEBCAM.setting.json`, `run-webcam-profile.sh` wrapper, README. ECR Custom build runs on every push.
- **Webcam fixture validated end-to-end today** with a 90 s session (`/tmp/profile-webcam-validate/2026-05-18/profile_20260518T194510Z/report.md`). `_decode_packet` 35 % self-time confirms the [[h264-deep-dive|H.264]] decode story carries from the simulator to real-camera workloads. RSS slope 153 MB/min over 88 s is warmup-dominated; longer soak needed for steady-state numbers.

## Tomorrow's plan — promote to stage

Sequential. Each step gates the next.

1. **Ready library PR #349 for review** → request review. *(Visible-to-others action — I won't flip this without confirmation.)*
2. **Wait for review + merge.** Merge triggers `Publish Stable` workflow → `actuate-movement` `1.2.7` published to CodeArtifact.
3. **Bump connector pin.** In the `feature/test-actuate-movement-cv2-dst` worktree (`/tmp/vms-connector-cv2`):
   ```bash
   sed -i 's|actuate-movement==1.2.7.dev1+feature.actuate.movement.cv2.dst.preallocation|actuate-movement==1.2.7|' pyproject.toml
   uv lock
   git add pyproject.toml uv.lock
   git commit -m "chore: bump actuate-movement pin from dev build to stable 1.2.7"
   git push
   ```
4. **Flip PR #1696 from draft → ready, then merge into `stage`.** Per [[2026-05-15]] CLAUDE.md the connector chain is `feature → stage → rearchitecture → prod`; merging into `stage` triggers the staging deploy.
5. **Soak overnight.** Suggested `/post-deploy-monitor` after the stage merge. Compare staging pod RSS / motion-event counts / alert verdicts vs the `rearchitecture` baseline.
6. **If clean overnight → propose stage → rearchitecture merge.** If anything regresses, revert connector PR #1696 (the library can stay merged — semver-compat).

## Harness papercuts (not blocking step 1 but worth landing before the next long run)

- ✅ **memray flamegraph render hang — FIXED 2026-05-19 (uncommitted).** Was a bare `subprocess.run` in `actuate-instrumentation/src/actuate_instrumentation/harness/runners/memray.py::render_flamegraph` with no timeout. Now takes `timeout_s=180` (default), uses `Popen` + `wait(timeout=)` + process-group kill on expiry, logs `[render_flamegraph] timed out after Ns` into the connector log, returns exit code 124 on timeout. Backwards-compat signature change — existing `session.py:126` callsite needs no edit. 17 harness tests still pass (`pytest tests/test_harness_artifacts.py tests/test_harness_parser.py tests/test_harness_report.py` with `PYTHONPATH=src`). Lives in `/tmp/actuate-instrumentation-v1` (branch `feature/actuate-instrumentation-v1`, with stash already applied; this fix is on top, uncommitted). **Companion change:** `vms-connector/test_settings/run-webcam-profile.sh` default `DURATION` lowered `5m` → `90s` (matches the 2026-05-18 clean validation-pass length). Both edits unstaged, ready to commit alongside the next harness push.
- ⚠️ **`memray stats --json` may still empty out** for the same root cause. The 120 s timeout in `report.py:250` (`allocation_hotspots_from_memray`) catches the hang but the report section will come up empty. Not yet investigated — if the next webcam run produces an empty allocation-hotspots section again, that's the next thread to pull.
- **Drop `--idle` from py-spy invocation in `runners/pyspy.py`** if it's set. Still open from 2026-05-14's hotspot triage; `expire_items` (TTL cache sleep loop) showing as 11% CPU was a measurement artifact. ~5 min, no GH issue needed.
- **Add a native `webcam-local` scenario to the harness** in `actuate-instrumentation`. The current wrapper at `vms-connector/test_settings/run-webcam-profile.sh` works by temporarily substituting the LOCAL_WEBCAM settings file in place of LOCAL_RTSP so the existing `rtsp-local` scenario picks it up. When the harness lands stable (post §30 push gate), add `scenarios/webcam_local.py` parallel to `rtsp_local.py` and drop the swap workaround.
- **mediamtx config cosmetic.** Logs `parameter 'protocols' is deprecated and has been replaced with 'rtspTransports'` at startup. Replace if regenerating.

## Caveat for short webcam runs (added 2026-05-19)

`_log_memory_breakdown` in `vms-connector/site_manager/connector/analytics_site_manager.py` ticks every 60 s by default (vms-connector#1694 — interval not yet env-var-configurable). The new `DURATION=90s` default captures only ~1 breakdown cycle, which is sufficient for py-spy + memray hotspot reads but not for RSS-slope analysis. For RSS-slope reads, run with `DURATION=180s` or longer until #1694 lands.

## Adjacent items still queued (§30 Phase 2.5)

- vms-connector#1693 — SSL-context churn investigation. Not started.
- vms-connector#1694 — `_log_memory_breakdown` interval env-var. Not started.
- Exp 2 and Exp 3 wiring in the `actuate-profile verify` command. Pre-push gate for `feature/actuate-instrumentation-v1` still blocked on these.

## Where the local working state lives (so tomorrow's first move isn't archaeology)

- Library cv2-dst worktree: `/tmp/actuate-libraries-cv2` (branch `feature/actuate-movement-cv2-dst-preallocation`, clean).
- Connector test-branch worktree: `/tmp/vms-connector-cv2` (branch `feature/test-actuate-movement-cv2-dst`, clean post-push).
- Instrumentation v1 worktree: `/tmp/actuate-instrumentation-v1` (branch `feature/actuate-instrumentation-v1` with `stash@{0}` applied — uncommitted, the harness source the wrapper needs).
- User's primary working tree at `/home/mork/work/actuate-libraries` was on `feat/autopatrol-tier-from-configured-codes` last time I looked; untouched by all of the above.

## Related

- **Status tracker (durable across handoffs):** [[2026-05-19_cv2-dst-soak-status]]
- A/B + first-findings: [[2026-05-14_first-hotspot-findings]]
- Tooling: [[2026-05-14_actuate-profile-report-subcommand]]
- Library issue / acceptance criteria: aegissystems/actuate-libraries#348
- Today's daily: [[2026-05-18]]
- Workstream: §30 in `mark-todos.md`
- Jira: ENG-246
